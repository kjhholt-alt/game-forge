"""CampaignDirector -- the Opus-level brain for SIGNAL ops campaigns.

Orchestrates the intelligence campaign generation pipeline:
CampaignArchitect (Opus) → IntelArchitect + TargetProfiler + NetworkDesigner
(Sonnet, parallel) → QAValidator (Haiku) per operation.

Follows the same patterns as GameDirector: structured Claude API calls,
validated Pydantic responses, Rich progress output, retry on failure.
"""

from __future__ import annotations

import asyncio
import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Any

import claudex_anthropic_shim as anthropic  # Max-sub via claudex; no API key
from rich.console import Console
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.table import Table

from orchestrator.config import AgentRole, GameConfig
from orchestrator.prompts import ROLE_PROMPTS
from schemas.signal_ops import (
    AnalystDefinition,
    AnalystSkill,
    AnalystSkillType,
    Campaign,
    CampaignTheme,
    ConspiracyGraph,
    InterceptBatch,
    NetworkTopology,
    Operation,
    TargetProfile,
)
from schemas.combat import QAReport

logger = logging.getLogger(__name__)
console = Console()


class CampaignDirectorError(Exception):
    """Raised when the CampaignDirector cannot complete a pipeline step."""


class CampaignDirector:
    """Top-level intelligence campaign orchestrator.

    Uses Opus to design the conspiracy, then dispatches Sonnet workers
    (IntelArchitect, TargetProfiler, NetworkDesigner) in parallel per
    operation, with Haiku QA validation at the end.
    """

    def __init__(self, config: GameConfig) -> None:
        self.config = config
        self._client = anthropic.AsyncAnthropic(api_key=config.anthropic_api_key)
        self._campaign: Campaign | None = None

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def create_campaign(
        self,
        theme: CampaignTheme,
        num_ops: int = 5,
        seed_prompt: str = "",
    ) -> Campaign:
        """Full pipeline: conspiracy → per-op generation → QA validation.

        Parameters
        ----------
        theme:
            Campaign theme (arms trafficking, corporate espionage, etc.).
        num_ops:
            Number of operations in the campaign (4-6).
        seed_prompt:
            Optional creative prompt to shape the conspiracy.

        Returns
        -------
        Campaign
            Fully assembled campaign with all operations.
        """
        num_ops = max(4, min(6, num_ops))

        with Progress(
            SpinnerColumn(),
            TextColumn("[bold cyan]{task.description}"),
            console=console,
        ) as progress:
            # 1 -- Design the conspiracy
            tid = progress.add_task("Designing conspiracy...", total=None)
            conspiracy = await self._design_conspiracy(theme, num_ops, seed_prompt)
            progress.update(tid, description="[green]Conspiracy designed")
            console.print(Panel(
                f"[bold]{conspiracy.title}[/bold]\n{conspiracy.synopsis}\n"
                f"Nodes: {len(conspiracy.nodes)}  |  Edges: {len(conspiracy.edges)}",
                title=f"Campaign: {conspiracy.title}",
                border_style="cyan",
            ))

            # 2 -- Generate operation skeletons from conspiracy
            progress.update(tid, description="Generating operation structures...")
            op_skeletons = await self._generate_op_skeletons(conspiracy, num_ops)
            console.print(f"  [dim]Operations planned:[/dim] {len(op_skeletons)}")

            # 3 -- For each op, generate intel + target + network in parallel
            operations: list[Operation] = []
            for i, skeleton in enumerate(op_skeletons):
                op_num = i + 1
                progress.update(
                    tid,
                    description=f"Building op {op_num}/{len(op_skeletons)}: {skeleton.get('codename', 'UNKNOWN')}...",
                )
                operation = await self._build_operation(skeleton, conspiracy, i)
                operations.append(operation)
                console.print(
                    f"  [dim]Op {op_num}:[/dim] {operation.briefing.codename} "
                    f"(difficulty {operation.difficulty}, "
                    f"{len(operation.signal_data.items)} intercepts, "
                    f"{len(operation.blacksite_target.employees)} employees, "
                    f"{len(operation.blacksite_target.network.hosts)} hosts)"
                )

            # 4 -- QA validate each operation
            progress.update(tid, description="Running QA validation...")
            qa_results: list[QAReport] = []
            for i, op in enumerate(operations):
                qa = await self._validate_operation(op)
                qa_results.append(qa)
                status = "[green]PASS" if qa.playable else "[red]FAIL"
                console.print(
                    f"  [dim]QA Op {i + 1}:[/dim] {status} "
                    f"(score: {qa.overall_score}/10, issues: {len(qa.issues)})"
                )

            # 5 -- Create default analyst
            analyst = AnalystDefinition(
                id=str(uuid.uuid4()),
                codename=_generate_codename(),
                skills=[
                    AnalystSkill(skill_type=st) for st in AnalystSkillType
                ],
            )

            # 6 -- Assemble campaign
            now = datetime.now(timezone.utc).isoformat()
            campaign = Campaign(
                id=str(uuid.uuid4()),
                name=conspiracy.title,
                conspiracy=conspiracy,
                operations=operations,
                analyst=analyst,
                created_at=now,
                updated_at=now,
            )

            # Summary table
            progress.update(tid, description="[bold green]Campaign ready!")

        self._print_campaign_summary(campaign, qa_results)
        self._campaign = campaign
        return campaign

    # ------------------------------------------------------------------
    # Internal pipeline steps
    # ------------------------------------------------------------------

    async def _design_conspiracy(
        self,
        theme: CampaignTheme,
        num_ops: int,
        seed_prompt: str,
    ) -> ConspiracyGraph:
        """Use Opus to design the overarching conspiracy graph."""
        user_message = (
            f"Design an intelligence campaign conspiracy for:\n\n"
            f"Theme: {theme.value}\n"
            f"Number of operations: {num_ops}\n"
            f"{'Creative direction: ' + seed_prompt if seed_prompt else ''}\n\n"
            f"Create a conspiracy graph with interconnected nodes (people, organizations, "
            f"events, assets, locations) and a sequence of {num_ops} operations that "
            f"progressively reveal the conspiracy.\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(ConspiracyGraph.model_json_schema(), indent=2)}"
        )

        result = await self._call_claude(
            model=self.config.director_model,
            system=ROLE_PROMPTS["campaign_architect"],
            user_message=user_message,
        )
        return ConspiracyGraph.model_validate(result)

    async def _generate_op_skeletons(
        self,
        conspiracy: ConspiracyGraph,
        num_ops: int,
    ) -> list[dict[str, Any]]:
        """Use Opus to plan the operation sequence from the conspiracy."""
        user_message = (
            f"Given this conspiracy graph, plan {num_ops} operations in sequence.\n\n"
            f"Conspiracy:\n{conspiracy.model_dump_json(indent=2)}\n\n"
            f"For each operation, provide:\n"
            f"- codename: two-word operation codename\n"
            f"- target_node_ids: which conspiracy nodes this op targets\n"
            f"- org_name: target organization name\n"
            f"- sector: organization sector\n"
            f"- difficulty: 1-10 (ramp from ~3 to ~8-9)\n"
            f"- objectives: list of mission objectives\n"
            f"- intel_hints: what clues should be in the intercepts\n"
            f"- reveals: what this op reveals about the conspiracy\n\n"
            f"Respond with JSON: {{\"operations\": [...]}}"
        )

        result = await self._call_claude(
            model=self.config.director_model,
            system=ROLE_PROMPTS["campaign_architect"],
            user_message=user_message,
        )

        ops = result.get("operations", result) if isinstance(result, dict) else result
        return ops if isinstance(ops, list) else []

    async def _build_operation(
        self,
        skeleton: dict[str, Any],
        conspiracy: ConspiracyGraph,
        op_index: int,
    ) -> Operation:
        """Build a full operation by dispatching workers in parallel."""
        codename = skeleton.get("codename", f"OP-{op_index + 1}")
        org_name = skeleton.get("org_name", "Unknown Corp")
        sector = skeleton.get("sector", "unknown")
        difficulty = skeleton.get("difficulty", 3 + op_index)
        objectives = skeleton.get("objectives", ["Exfiltrate target data"])

        context = json.dumps({
            "conspiracy": conspiracy.model_dump(mode="json"),
            "operation_skeleton": skeleton,
            "op_index": op_index,
        })

        # Dispatch all three workers in parallel
        intel_task = self._generate_intercepts(context, difficulty)
        target_task = self._generate_target_profile(context, org_name, sector, difficulty)
        network_task = self._generate_network(context, difficulty)

        intercepts, target_profile, network = await asyncio.gather(
            intel_task, target_task, network_task,
        )

        # Attach the network to the target profile
        target_profile.network = network

        from schemas.signal_ops import OpBriefing, InterceptBatch

        return Operation(
            id=str(uuid.uuid4()),
            op_index=op_index,
            briefing=OpBriefing(
                codename=codename,
                summary=skeleton.get("summary", f"Infiltrate {org_name}."),
                objectives=objectives,
                warnings=skeleton.get("warnings", []),
            ),
            signal_data=intercepts,
            blacksite_target=target_profile,
            difficulty=max(1, min(10, difficulty)),
            required_exfil=network.exfil_target_ids,
            unlocks_ops=skeleton.get("unlocks", []),
        )

    async def _generate_intercepts(
        self,
        context: str,
        difficulty: int,
    ) -> InterceptBatch:
        """Dispatch IntelArchitect to generate evidence items."""
        num_items = 5 + difficulty  # More items at higher difficulty
        clue_ratio = max(0.3, 0.6 - difficulty * 0.03)  # Fewer clues at higher difficulty

        user_message = (
            f"Generate intelligence intercepts for this operation.\n\n"
            f"Context:\n{context}\n\n"
            f"Requirements:\n"
            f"- Generate {num_items} evidence items total\n"
            f"- Approximately {int(num_items * clue_ratio)} should be real clues\n"
            f"- The rest should be realistic noise\n"
            f"- Difficulty level: {difficulty}/10\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(InterceptBatch.model_json_schema(), indent=2)}"
        )

        result = await self._dispatch_worker(
            role=AgentRole.INTEL_ARCHITECT,
            user_message=user_message,
        )
        return InterceptBatch.model_validate(result)

    async def _generate_target_profile(
        self,
        context: str,
        org_name: str,
        sector: str,
        difficulty: int,
    ) -> TargetProfile:
        """Dispatch TargetProfiler to generate the BLACKSITE target."""
        num_employees = 2 + (difficulty // 2)  # More employees at higher difficulty

        user_message = (
            f"Generate a target profile for the BLACKSITE phase.\n\n"
            f"Context:\n{context}\n\n"
            f"Organization: {org_name} ({sector})\n"
            f"Number of employees to profile: {num_employees}\n"
            f"Difficulty level: {difficulty}/10\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(TargetProfile.model_json_schema(), indent=2)}"
        )

        result = await self._dispatch_worker(
            role=AgentRole.TARGET_PROFILER,
            user_message=user_message,
        )
        return TargetProfile.model_validate(result)

    async def _generate_network(
        self,
        context: str,
        difficulty: int,
    ) -> NetworkTopology:
        """Dispatch NetworkDesigner to generate the network topology."""
        num_subnets = 1 + (difficulty // 3)
        num_hosts = 3 + difficulty

        user_message = (
            f"Design the network topology for this BLACKSITE target.\n\n"
            f"Context:\n{context}\n\n"
            f"Requirements:\n"
            f"- {num_subnets} subnet(s)\n"
            f"- Approximately {num_hosts} hosts total\n"
            f"- At least one solvable vulnerability chain from entry to exfiltration\n"
            f"- Difficulty level: {difficulty}/10\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(NetworkTopology.model_json_schema(), indent=2)}"
        )

        result = await self._dispatch_worker(
            role=AgentRole.NETWORK_DESIGNER,
            user_message=user_message,
        )
        return NetworkTopology.model_validate(result)

    async def _validate_operation(self, operation: Operation) -> QAReport:
        """Dispatch QA Validator to check operation solvability."""
        user_message = (
            f"Validate this SIGNAL operation for solvability and quality.\n\n"
            f"Operation:\n{operation.model_dump_json(indent=2)}\n\n"
            f"Check: evidence chain completeness, network solvability, "
            f"social engineering paths, difficulty calibration, dead ends, "
            f"credential consistency.\n\n"
            f"Respond with a JSON object matching this schema:\n"
            f"{json.dumps(QAReport.model_json_schema(), indent=2)}"
        )

        result = await self._call_claude(
            model=self.config.fast_model,
            system=ROLE_PROMPTS["signal_qa_validator"],
            user_message=user_message,
        )
        return QAReport.model_validate(result)

    # ------------------------------------------------------------------
    # Low-level helpers
    # ------------------------------------------------------------------

    async def _dispatch_worker(
        self,
        role: AgentRole,
        user_message: str,
    ) -> dict[str, Any]:
        """Send a task to a Sonnet worker agent."""
        system = ROLE_PROMPTS.get(role.value, ROLE_PROMPTS["campaign_architect"])
        return await self._call_claude(
            model=self.config.worker_model,
            system=system,
            user_message=user_message,
        )

    async def _call_claude(
        self,
        model: str,
        system: str,
        user_message: str,
    ) -> dict[str, Any]:
        """Make a Claude API call and parse the JSON response.

        Retries up to ``config.max_retries`` on transient failures.
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

                text = ""
                for block in response.content:
                    if hasattr(block, "text"):
                        text += block.text

                # Strip markdown code fences if present
                text = text.strip()
                if text.startswith("```"):
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

        raise CampaignDirectorError(
            f"Failed after {self.config.max_retries} attempts. Last error: {last_error}"
        )

    @staticmethod
    def _print_campaign_summary(campaign: Campaign, qa_results: list[QAReport]) -> None:
        """Print a rich summary table of the generated campaign."""
        table = Table(title=f"Campaign: {campaign.name}", border_style="cyan")
        table.add_column("#", style="dim", width=3)
        table.add_column("Codename", style="bold")
        table.add_column("Target", style="cyan")
        table.add_column("Diff", justify="center")
        table.add_column("Intercepts", justify="center")
        table.add_column("Employees", justify="center")
        table.add_column("Hosts", justify="center")
        table.add_column("QA", justify="center")

        for i, op in enumerate(campaign.operations):
            qa = qa_results[i] if i < len(qa_results) else None
            qa_str = (
                f"[green]{qa.overall_score}/10"
                if qa and qa.playable
                else f"[red]{qa.overall_score}/10" if qa else "—"
            )
            table.add_row(
                str(i + 1),
                op.briefing.codename,
                op.blacksite_target.org_name,
                str(op.difficulty),
                str(len(op.signal_data.items)),
                str(len(op.blacksite_target.employees)),
                str(len(op.blacksite_target.network.hosts)),
                qa_str,
            )

        console.print(table)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_CODENAMES = [
    "WRAITH", "CIPHER", "PHANTOM", "SPECTRE", "GHOST",
    "NOMAD", "VECTOR", "PRISM", "SHADOW", "RAVEN",
    "VIPER", "ECHO", "DELTA", "ONYX", "FROST",
    "APEX", "TORCH", "AEGIS", "HAVOC", "SENTINEL",
]


def _generate_codename() -> str:
    """Pick a random analyst codename."""
    import random
    return random.choice(_CODENAMES)
