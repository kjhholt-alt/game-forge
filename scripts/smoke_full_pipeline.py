"""Full 5-stage pipeline smoke for GameForge.

Runs concept → world → mechanics → narrative → art → QA end-to-end
through claudex.ask_structured. No model API key required; all
model calls go through `claude -p --output-format json --json-schema`
backed by the Max-sub Claude CLI.

Cost: roughly $1.00-$2.50 per run depending on Opus cache warmth.
Wall-clock: 2.5-5 minutes.

Writes scripts/smoke_full_pipeline.report.json with per-stage timing
and a summary of the generated project.

Usage:
    py scripts/smoke_full_pipeline.py
"""
from __future__ import annotations

import asyncio
import json
import os
import sys
import time
import traceback
from pathlib import Path

# Force UTF-8 stdout BEFORE rich loads — its Progress spinner uses
# braille-pattern chars (⠇, ⠋, etc.) that cp1252 (Windows
# console default) can't render. Without this the 5-stage pipeline
# crashes in the spinner, not in the generation.
os.environ.setdefault("PYTHONIOENCODING", "utf-8")
try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT))

REPORT_PATH = HERE / "smoke_full_pipeline.report.json"


async def main() -> int:
    started_at = time.time()
    record: dict = {
        "started_at_iso": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "ok": False,
        "summary": None,
        "error": None,
        "elapsed_s": None,
    }

    try:
        from orchestrator.config import GameConfig, GameGenre
        from orchestrator.forge import GameForge

        config = GameConfig(
            state_db_path=str(HERE / "smoke_full_pipeline.state.db"),
            max_retries=1,
            enable_streaming=False,
        )
        forge = GameForge(config)
        prompt = os.environ.get("GAMEFORGE_SMOKE_PROMPT") or (
            "A short cozy roguelike about a lantern-keeper exploring "
            "a flooded crypt. One dungeon. Three enemy types, all "
            "puzzles not DPS-checks. One hidden treasure room per "
            "run. Pixel art, calm and contemplative, ~15 min sessions."
        )

        outer_timeout = int(os.environ.get("GAMEFORGE_SMOKE_OUTER_TIMEOUT_S", "900"))
        project = await asyncio.wait_for(
            forge.create(
                prompt=prompt,
                genre=GameGenre.ROGUELIKE,
            ),
            timeout=outer_timeout,  # default 15 min hard cap; env-overridable
        )
        # Export to a tmp dir + verify the Godot scaffolding landed
        export_dir = HERE / "smoke_full_pipeline.export"
        if export_dir.exists():
            import shutil as _sh
            archive_dir = HERE / f"smoke_full_pipeline.export.prev-{int(started_at)}"
            _sh.move(str(export_dir), str(archive_dir))
            record["archived_previous_export_dir"] = str(archive_dir)
        forge.export(export_dir)
        manifest = export_dir / "game_project.json"
        manifest_ok = manifest.exists() and manifest.stat().st_size > 1000
        project_godot = export_dir / "project.godot"
        mcp_server = export_dir / "scripts" / "mcp_server.gd"

        record["ok"] = True
        record["summary"] = {
            "concept_title": project.concept.title,
            "concept_setting": project.concept.setting[:200],
            "world_name": project.world.name if project.world else None,
            "items_count": len(project.items),
            "quests_count": len(project.quests),
            "npcs_count": len(project.npcs),
            "prompt": prompt,
            "style_guide_present": project.style_guide is not None,
            "qa_playable": project.qa_report.playable if project.qa_report else None,
            "qa_issue_count": (
                len(project.qa_report.issues) if project.qa_report else None
            ),
            "scenes_generated": len(project.scenes_generated),
            "scripts_generated": len(project.scripts_generated),
            "export_dir": str(export_dir),
            "export_manifest_kb": (
                round(manifest.stat().st_size / 1024, 1) if manifest_ok else None
            ),
            "export_has_project_godot": project_godot.exists(),
            "export_has_mcp_server": mcp_server.exists(),
        }
    except asyncio.TimeoutError:
        record["error"] = "pipeline timeout after 900s"
    except Exception as e:
        record["error"] = f"{type(e).__name__}: {e}"
        record["traceback"] = traceback.format_exc()

    record["elapsed_s"] = round(time.time() - started_at, 2)
    REPORT_PATH.write_text(json.dumps(record, indent=2))

    print("=" * 60)
    print(f"FULL PIPELINE SMOKE — {'OK' if record['ok'] else 'FAIL'}")
    print("=" * 60)
    if record["ok"]:
        s = record["summary"]
        print(f"  title:    {s['concept_title']}")
        print(f"  setting:  {s['concept_setting'][:100]}")
        print(f"  world:    {s['world_name']}")
        print(f"  items:    {s['items_count']}")
        print(f"  quests:   {s['quests_count']}")
        print(f"  npcs:     {s['npcs_count']}")
        print(f"  style:    {'OK' if s['style_guide_present'] else '-'}")
        print(f"  qa.playable: {s['qa_playable']}")
        print(f"  qa.issues:   {s['qa_issue_count']}")
    else:
        print(f"  error: {record.get('error')}")
        if record.get("traceback"):
            print("  traceback:")
            for line in record["traceback"].splitlines()[-15:]:
                print(f"    {line}")
    print()
    print(f"  elapsed: {record['elapsed_s']:.2f}s")
    print(f"  report:  {REPORT_PATH}")
    return 0 if record["ok"] else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
