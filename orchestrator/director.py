"""GameDirector -- the Opus-level brain that orchestrates every agent.

The Director takes a human prompt, produces a game concept, then
dispatches worker agents (WorldBuilder, NarrativeEngine, MechanicsEngine,
ArtDirector, QATester) in a structured pipeline.  Each worker returns
validated Pydantic models that the Director assembles into a GameProject.
"""

from __future__ import annotations

import json
import logging
from typing import Any

import anthropic
from rich.console import Console
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn

from orchestrator.config import AgentRole, GameConfig, GameGenre
from orchestrator.prompts import ROLE_PROMPTS
from schemas.game import (
    ArtAssetSpec,
    GameConcept,
    GameProject,
    Item,
    NPC,
    QAReport,
    Quest,
    WorldDefinition,
)

logger = logging.getLogger(__name__)
console = Console()


class DirectorError(Exception):
    """Raised when the Director cannot complete a pipeline step."""


class GameDirector:
    """Top-level game creation orchestrator.

    Uses Opus to coordinate WorldBuilder, NarrativeEngine, MechanicsEngine,
    ArtDirector, and QATester -- each backed by a Claude API call with a
    role-specific system prompt.
    """

    def __init__(self, config: GameConfig) -> None:
        self.config = config
        self._client = anthropic.AsyncAnthropic(api_key=config.anthropic_api_key)
        self._project: GameProject | None = None

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def create_game(self, prompt: str, genre: GameGenre) -> GameProject:
        """Full pipeline: concept -> world -> mechanics -> narrative -> assets -> QA.

        Parameters
        ----------
        prompt:
            Free-form description of the desired game.
        genre:
            Target genre enum value.

        Returns
        -------
        GameProject
            The fully assembled game project with all generated content.
        """
        with Progress(
            SpinnerColumn(),
            TextColumn("[bold cyan]{task.description}"),
            console=console,
        ) as progress:
            # 1 -- Concept
            tid = progress.add_task("Generating game concept...", total=None)
            concept = await self._generate_concept(prompt, genre)
            progress.update(tid, description="[green]Concept ready")
            console.print(Panel(
                f"[bold]{concept.title}[/bold]\n{concept.setting}",
                title="Game Concept",
                border_style="cyan",
            ))

            # 2 -- World
            progress.update(tid, description="Building world...")
            world = await self._build_world(concept)
            region_names = ", ".join(r.name for r in world.regions) if world.regions else "none"
            console.print(f"  [dim]Regions:[/dim] {region_names}")

            # 3 -- Mechanics (items)
            progress.update(tid, description="Designing mechanics & items...")
            items = await self._design_mechanics(concept, world)
            console.print(f"  [dim]Items:[/dim] {len(items)} created")

            # 4 -- Narrative (quests + NPCs)
            progress.update(tid, description="Writing narrative...")
            quests, npcs = await self._write_narrative(concept, world, items)
            console.print(f"  [dim]Quests:[/dim] {len(quests)}  |  [dim]NPCs:[/dim] {len(npcs)}")

            # 5 -- Art asset specs
            progress.update(tid, description="Art directing...")
            art_specs = await self._direct_art(concept, world, npcs)
            console.print(f"  [dim]Art specs:[/dim] {len(art_specs)}")

            # 6 -- Assemble project
            project = GameProject(
                concept=concept,
                world=world,
                quests=quests,
                npcs=npcs,
                items=items,
                art_specs=art_specs,
            )

            # 7 -- QA
            progress.update(tid, description="Running QA playtest...")
            qa_report = await self._run_qa(project)
            project.qa_report = qa_report

            score_colour = "green" if qa_report.passed else "red"
            console.print(Panel(
                f"Score: [{score_colour}]{qa_report.overall_score}/10[/{score_colour}]\n"
                f"{qa_report.summary}\n"
                f"Issues: {len(qa_report.issues)}  |  "
                f"Passed: {'Yes' if qa_report.passed else 'No'}",
                title="QA Report",
                border_style="yellow",
            ))

            # 8 -- Iterate on critical issues (up to max_retries)
            if not qa_report.passed:
                progress.update(tid, description="Iterating on QA feedback...")
                project = await self._iterate_on_qa(project, qa_report)

            progress.update(tid, description="[bold green]Done!")

        self._project = project
        return project

    async def iterate(self, feedback: str) -> GameProject:
        """Take human feedback and regenerate / modify the current game.

        Parameters
        ----------
        feedback:
            Free-form description of desired changes.

        Returns
        -------
        GameProject
            Updated game project.

        Raises
        ------
        DirectorError
            If no project has been created yet.
        """
        if self._project is None:
            raise DirectorError("No active project. Run create_game() first.")

        console.print(f"[cyan]Applying feedback:[/cyan] {feedback}")

        result = await self._dispatch_worker(
            role=AgentRole.DIRECTOR,
            task={
                "action": "iterate",
                "feedback": feedback,
                "current_project": self._project.model_dump(mode="json"),
            },
            response_schema="GameProject",
        )

        # Re-parse full project from the response
        self._project = GameProject.model_validate(result)
        return self._project

    # ------------------------------------------------------------------
    # Internal pipeline steps
    # ------------------------------------------------------------------

    async def _generate_concept(self, prompt: str, genre: GameGenre) -> GameConcept:
        """Use Opus to create a detailed game design document from a prompt."""
        user_message = (
            f"Create a game concept for the following idea:\n\n"
            f"Prompt: {prompt}\n"
            f"Genre: {genre.value}\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(GameConcept.model_json_schema(), indent=2)}"
        )

        result = await self._call_claude(
            model=self.config.director_model,
            system=ROLE_PROMPTS["director"],
            user_message=user_message,
        )
        return GameConcept.model_validate(result)

    async def _build_world(self, concept: GameConcept) -> WorldDefinition:
        """Dispatch WorldBuilder to create the world structure."""
        user_message = (
            f"Build a world for this game concept:\n\n"
            f"{concept.model_dump_json(indent=2)}\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(WorldDefinition.model_json_schema(), indent=2)}"
        )

        result = await self._dispatch_worker(
            role=AgentRole.WORLD_BUILDER,
            task={"concept": concept.model_dump(mode="json")},
            response_schema="WorldDefinition",
            override_message=user_message,
        )
        return WorldDefinition.model_validate(result)

    async def _design_mechanics(
        self,
        concept: GameConcept,
        world: WorldDefinition,
    ) -> list[Item]:
        """Dispatch MechanicsEngine to define items and balance."""
        user_message = (
            f"Design the item system for this game:\n\n"
            f"Concept: {concept.model_dump_json(indent=2)}\n\n"
            f"World: {world.model_dump_json(indent=2)}\n\n"
            f"Respond with a JSON object: {{\"items\": [...]}} where each item "
            f"matches this schema:\n"
            f"{json.dumps(Item.model_json_schema(), indent=2)}"
        )

        result = await self._dispatch_worker(
            role=AgentRole.MECHANICS,
            task={
                "concept": concept.model_dump(mode="json"),
                "world": world.model_dump(mode="json"),
            },
            response_schema="items_list",
            override_message=user_message,
        )

        raw_items = result.get("items", result) if isinstance(result, dict) else result
        if isinstance(raw_items, list):
            return [Item.model_validate(i) for i in raw_items]
        return []

    async def _write_narrative(
        self,
        concept: GameConcept,
        world: WorldDefinition,
        items: list[Item],
    ) -> tuple[list[Quest], list[NPC]]:
        """Dispatch NarrativeEngine to create quests, NPCs, and dialogue."""
        user_message = (
            f"Write the narrative content for this game:\n\n"
            f"Concept: {concept.model_dump_json(indent=2)}\n\n"
            f"World: {world.model_dump_json(indent=2)}\n\n"
            f"Available items: {json.dumps([i.model_dump(mode='json') for i in items])}\n\n"
            f"Respond with a JSON object: {{\"quests\": [...], \"npcs\": [...]}}.\n"
            f"Quest schema:\n{json.dumps(Quest.model_json_schema(), indent=2)}\n"
            f"NPC schema:\n{json.dumps(NPC.model_json_schema(), indent=2)}"
        )

        result = await self._dispatch_worker(
            role=AgentRole.NARRATIVE,
            task={
                "concept": concept.model_dump(mode="json"),
                "world": world.model_dump(mode="json"),
                "items": [i.model_dump(mode="json") for i in items],
            },
            response_schema="narrative",
            override_message=user_message,
        )

        quests = [Quest.model_validate(q) for q in result.get("quests", [])]
        npcs = [NPC.model_validate(n) for n in result.get("npcs", [])]
        return quests, npcs

    async def _direct_art(
        self,
        concept: GameConcept,
        world: WorldDefinition,
        npcs: list[NPC],
    ) -> list[ArtAssetSpec]:
        """Dispatch ArtDirector to describe needed visual assets."""
        user_message = (
            f"Create art asset specifications for this game:\n\n"
            f"Concept: {concept.model_dump_json(indent=2)}\n\n"
            f"World: {world.model_dump_json(indent=2)}\n\n"
            f"NPCs: {json.dumps([n.model_dump(mode='json') for n in npcs])}\n\n"
            f"Respond with a JSON object: {{\"assets\": [...]}} where each asset "
            f"matches this schema:\n"
            f"{json.dumps(ArtAssetSpec.model_json_schema(), indent=2)}"
        )

        result = await self._dispatch_worker(
            role=AgentRole.ART_DIRECTOR,
            task={
                "concept": concept.model_dump(mode="json"),
                "world": world.model_dump(mode="json"),
                "npcs": [n.model_dump(mode="json") for n in npcs],
            },
            response_schema="assets_list",
            override_message=user_message,
        )

        raw = result.get("assets", result) if isinstance(result, dict) else result
        if isinstance(raw, list):
            return [ArtAssetSpec.model_validate(a) for a in raw]
        return []

    async def _run_qa(self, project: GameProject) -> QAReport:
        """Dispatch QATester to playtest and report issues."""
        user_message = (
            f"Perform a QA playtest review of this game project:\n\n"
            f"{project.model_dump_json(indent=2)}\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(QAReport.model_json_schema(), indent=2)}"
        )

        result = await self._dispatch_worker(
            role=AgentRole.QA_TESTER,
            task={"project": project.model_dump(mode="json")},
            response_schema="QAReport",
            override_message=user_message,
        )
        return QAReport.model_validate(result)

    async def _iterate_on_qa(
        self,
        project: GameProject,
        qa_report: QAReport,
    ) -> GameProject:
        """Attempt to fix critical QA issues up to max_retries times."""
        for attempt in range(1, self.config.max_retries + 1):
            critical_issues = [
                i for i in qa_report.issues if i.severity.value == "critical"
            ]
            if not critical_issues:
                break

            logger.info("QA iteration %d -- fixing %d critical issues", attempt, len(critical_issues))
            console.print(
                f"  [yellow]QA iteration {attempt}:[/yellow] "
                f"fixing {len(critical_issues)} critical issue(s)"
            )

            feedback = "Fix these critical issues:\n" + "\n".join(
                f"- [{i.category}] {i.description} (suggested: {i.suggested_fix})"
                for i in critical_issues
            )

            project = await self.iterate(feedback)

            # Re-run QA
            qa_report = await self._run_qa(project)
            project.qa_report = qa_report

            if qa_report.passed:
                console.print("  [green]QA passed after iteration!")
                break

        return project

    # ------------------------------------------------------------------
    # Low-level Claude API helpers
    # ------------------------------------------------------------------

    async def _dispatch_worker(
        self,
        role: AgentRole,
        task: dict[str, Any],
        response_schema: str,
        override_message: str | None = None,
    ) -> dict[str, Any]:
        """Send a task to a worker agent and await structured JSON response.

        Parameters
        ----------
        role:
            Which agent role to assume (selects model + system prompt).
        task:
            Structured task payload (used if *override_message* is None).
        response_schema:
            Human-readable label for the expected response shape (for logging).
        override_message:
            If provided, use this as the user message instead of serialising *task*.

        Returns
        -------
        dict
            Parsed JSON response from the Claude API.
        """
        model = (
            self.config.director_model
            if role == AgentRole.DIRECTOR
            else self.config.worker_model
        )
        system = ROLE_PROMPTS.get(role.value, ROLE_PROMPTS["director"])
        user_message = override_message or json.dumps(task, indent=2)

        logger.debug("Dispatching %s (model=%s, schema=%s)", role.value, model, response_schema)
        return await self._call_claude(model=model, system=system, user_message=user_message)

    async def _call_claude(
        self,
        model: str,
        system: str,
        user_message: str,
    ) -> dict[str, Any]:
        """Make a Claude API call and parse the JSON response.

        Retries up to ``config.max_retries`` on transient failures.

        Returns
        -------
        dict
            Parsed JSON from the assistant's response.

        Raises
        ------
        DirectorError
            If all retries are exhausted or the response is not valid JSON.
        """
        last_error: Exception | None = None

        for attempt in range(1, self.config.max_retries + 1):
            try:
                response = await self._client.messages.create(
                    model=model,
                    max_tokens=8192,
                    system=system,
                    messages=[{"role": "user", "content": user_message}],
                )

                # Extract text content
                text = ""
                for block in response.content:
                    if hasattr(block, "text"):
                        text += block.text

                # Strip markdown code fences if present
                text = text.strip()
                if text.startswith("```"):
                    # Remove opening fence (```json or ```)
                    first_newline = text.index("\n")
                    text = text[first_newline + 1:]
                if text.endswith("```"):
                    text = text[:-3]
                text = text.strip()

                return json.loads(text)  # type: ignore[no-any-return]

            except json.JSONDecodeError as exc:
                logger.warning(
                    "Attempt %d/%d: invalid JSON from %s -- %s",
                    attempt, self.config.max_retries, model, exc,
                )
                last_error = exc
            except anthropic.APIError as exc:
                logger.warning(
                    "Attempt %d/%d: API error from %s -- %s",
                    attempt, self.config.max_retries, model, exc,
                )
                last_error = exc

        raise DirectorError(
            f"Failed after {self.config.max_retries} attempts. Last error: {last_error}"
        )
