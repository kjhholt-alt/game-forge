"""GameForge -- high-level entry point.

Provides a clean API surface for both the CLI and programmatic usage.
Wraps GameDirector and handles project persistence.
"""

from __future__ import annotations

import json
import logging
import shutil
from pathlib import Path

from rich.console import Console

from orchestrator.config import GameConfig
from orchestrator.director import GameDirector
from orchestrator.godot_exporter import generate_godot_content
from orchestrator.unity_exporter import generate_unity_content
from schemas import GameGenre, GameProject

logger = logging.getLogger(__name__)
console = Console()

# Unity projects accrete large generated trees; never drag them along when the
# template is copied into an export directory.
_UNITY_IGNORE = (
    "Library",
    "Temp",
    "obj",
    "Logs",
    "UserSettings",
    "_build",
    "_renders",
    "*.csproj",
    "*.sln",
)


class GameForge:
    """High-level facade for creating, iterating, and exporting games.

    Usage::

        forge = GameForge(GameConfig())
        project = await forge.create("A dark roguelike ...", GameGenre.ROGUELIKE)
        project = await forge.iterate("Make combat harder")
        forge.export(Path("./my-game"))
    """

    def __init__(self, config: GameConfig | None = None) -> None:
        self.config = config or GameConfig()
        self._director = GameDirector(self.config)
        self._project: GameProject | None = None
        self._state_path = Path(self.config.state_db_path).with_suffix(".json")

        # Attempt to restore previous session
        self._load_state()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def create(self, prompt: str, genre: GameGenre) -> GameProject:
        """Create a new game from a natural-language prompt.

        Parameters
        ----------
        prompt:
            Free-form game idea.
        genre:
            Target game genre.

        Returns
        -------
        GameProject
            Fully assembled game project.
        """
        self._project = await self._director.create_game(prompt, genre)
        self._save_state()
        return self._project

    async def iterate(self, feedback: str) -> GameProject:
        """Apply feedback to the current project.

        Parameters
        ----------
        feedback:
            Description of desired changes.

        Returns
        -------
        GameProject
            Updated game project.
        """
        self._project = await self._director.iterate(feedback)
        self._save_state()
        return self._project

    def export(self, output_dir: Path, engine: str = "godot") -> Path:
        """Export the current project as a playable game project.

        Parameters
        ----------
        output_dir:
            Destination directory.  Created if it doesn't exist.
        engine:
            Target engine backend -- ``"godot"`` (default) or ``"unity"``. Both
            consume the same engine-neutral ``GameProject``; only the backend
            differs.

        Returns
        -------
        Path
            The output directory.

        Raises
        ------
        RuntimeError
            If no project exists yet.
        ValueError
            If *engine* is not a supported backend.
        """
        if self._project is None:
            raise RuntimeError("No project to export. Run create() first.")

        engine = (engine or "godot").lower()
        output_dir = Path(output_dir)
        if engine == "godot":
            return self._export_godot(output_dir)
        if engine == "unity":
            return self._export_unity(output_dir)
        raise ValueError(f"Unknown engine '{engine}'. Choose 'godot' or 'unity'.")

    def _export_godot(self, output_dir: Path) -> Path:
        assert self._project is not None
        template_dir = Path(self.config.godot_project_path)

        if template_dir.exists():
            shutil.copytree(template_dir, output_dir, dirs_exist_ok=True)
            console.print(f"[green]Copied Godot template to {output_dir}")
        else:
            output_dir.mkdir(parents=True, exist_ok=True)
            console.print(f"[yellow]Template not found at {template_dir} -- created empty dir")

        scenes, scripts = generate_godot_content(self._project, output_dir)
        console.print(
            f"[green]Generated {len(scenes)} scene(s) and {len(scripts)} script(s) from manifest"
        )

        self._write_manifest(output_dir)
        return output_dir

    def _export_unity(self, output_dir: Path) -> Path:
        assert self._project is not None
        template_dir = Path(self.config.unity_project_path)

        if template_dir.exists():
            shutil.copytree(
                template_dir,
                output_dir,
                dirs_exist_ok=True,
                ignore=shutil.ignore_patterns(*_UNITY_IGNORE),
            )
            console.print(f"[green]Copied Unity template to {output_dir}")
        else:
            output_dir.mkdir(parents=True, exist_ok=True)
            console.print(f"[yellow]Unity template not found at {template_dir} -- created empty dir")

        scenes, scripts = generate_unity_content(self._project, output_dir)
        console.print(
            f"[green]Generated Unity scene model + {len(scripts)} script artifact(s) from manifest"
        )

        self._write_manifest(output_dir)
        return output_dir

    def _write_manifest(self, output_dir: Path) -> None:
        assert self._project is not None
        manifest_path = output_dir / "game_project.json"
        manifest_path.write_text(
            self._project.model_dump_json(indent=2),
            encoding="utf-8",
        )
        console.print(f"[green]Wrote project manifest to {manifest_path}")

    def status(self) -> dict[str, object]:
        """Return a summary dict of the current project state."""
        if self._project is None:
            return {"status": "no_project", "message": "No active project."}

        p = self._project
        regions = p.world.overworld.regions if p.world and p.world.overworld else []
        return {
            "status": "active",
            "title": p.concept.title,
            "genre": p.concept.genre.value,
            "regions": len(regions),
            "dungeons": len(p.world.dungeons) if p.world else 0,
            "quests": len(p.quests),
            "npcs": len(p.npcs),
            "items": len(p.items),
            "encounters": len(p.encounters),
            "has_style_guide": p.style_guide is not None,
            "scenes_generated": len(p.scenes_generated),
            "scripts_generated": len(p.scripts_generated),
            "qa_playable": p.qa_report.playable if p.qa_report else None,
            "qa_score": p.qa_report.overall_score if p.qa_report else None,
        }

    # ------------------------------------------------------------------
    # Persistence
    # ------------------------------------------------------------------

    def _save_state(self) -> None:
        """Persist the current project to a JSON file."""
        if self._project is None:
            return
        try:
            self._state_path.write_text(
                self._project.model_dump_json(indent=2),
                encoding="utf-8",
            )
            logger.debug("State saved to %s", self._state_path)
        except OSError as exc:
            logger.warning("Failed to save state: %s", exc)

    def _load_state(self) -> None:
        """Restore a project from the state file if it exists."""
        if not self._state_path.exists():
            return
        try:
            raw = self._state_path.read_text(encoding="utf-8")
            self._project = GameProject.model_validate_json(raw)
            self._director._project = self._project
            logger.info("Restored project '%s' from %s", self._project.concept.title, self._state_path)
        except Exception as exc:
            logger.warning("Could not restore state: %s", exc)
