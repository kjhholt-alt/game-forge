"""Export existing GameForge manifests with generated Godot content.

This script does not call a model. It reuses saved project JSON files and runs
the deterministic exporter so older games get the same scene/script treatment
as fresh runs.
"""

from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT))

from orchestrator.config import GameConfig  # noqa: E402
from orchestrator.forge import GameForge  # noqa: E402
from schemas import GameProject  # noqa: E402


KNOWN_MANIFESTS = [
    HERE / "smoke_full_pipeline.state.json",
    HERE / "smoke_full_pipeline_puzzle.state.json",
    HERE / "smoke_full_pipeline_rpg.state.json",
    HERE / "smoke_full_pipeline.export.prev-1778919521" / "game_project.json",
]


def main() -> int:
    out_root = ROOT / "exports" / "existing-games"
    out_root.mkdir(parents=True, exist_ok=True)

    exported: list[dict[str, object]] = []
    for manifest in KNOWN_MANIFESTS:
        if not manifest.exists():
            continue
        project = GameProject.model_validate_json(manifest.read_text(encoding="utf-8"))
        slug = _slug(project.concept.title)
        out_dir = out_root / slug
        if out_dir.exists():
            shutil.rmtree(out_dir)

        forge = GameForge(GameConfig(
            godot_project_path=str(ROOT / "godot_template"),
            state_db_path=str(out_root / f"{slug}.state.db"),
            enable_streaming=False,
        ))
        forge._project = project
        forge._director._project = project
        forge.export(out_dir)
        exported.append({
            "title": project.concept.title,
            "source": str(manifest),
            "output": str(out_dir),
            "scenes": len(project.scenes_generated),
            "scripts": len(project.scripts_generated),
        })

    report_path = out_root / "EXPORT_REPORT.json"
    report_path.write_text(json.dumps(exported, indent=2), encoding="utf-8")
    print(f"Exported {len(exported)} existing game(s).")
    print(f"Report: {report_path}")
    return 0


def _slug(value: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", value.lower()).strip("-")
    return slug or "generated-game"


if __name__ == "__main__":
    raise SystemExit(main())
