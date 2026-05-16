"""Second-genre Game-Forge smoke — puzzle (not roguelike) to prove
the pipeline isn't roguelike-only.

Writes scripts/smoke_full_pipeline_puzzle.report.json + state.json so
the original Wickwater state remains intact for comparison.
"""
from __future__ import annotations

import asyncio
import json
import os
import sys
import time
import traceback
from pathlib import Path

os.environ.setdefault("PYTHONIOENCODING", "utf-8")
try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT))

REPORT_PATH = HERE / "smoke_full_pipeline_puzzle.report.json"


async def main() -> int:
    started_at = time.time()
    record: dict = {"started_at_iso": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "ok": False}

    try:
        from orchestrator.config import GameConfig, GameGenre
        from orchestrator.forge import GameForge

        config = GameConfig(
            state_db_path=str(HERE / "smoke_full_pipeline_puzzle.state.db"),
            max_retries=1,
            enable_streaming=False,
        )
        forge = GameForge(config)
        # Force a fresh project (don't load previous state)
        forge._project = None

        project = await asyncio.wait_for(
            forge.create(
                prompt=(
                    "A short cozy block-stacking puzzle game where you "
                    "arrange falling glass orbs by color to clear lines. "
                    "Three difficulty modes. Single-screen. Pixel art with "
                    "a tea-room aesthetic — wood grain background, hand-"
                    "lettered scores, calm jazz piano. Single-session play."
                ),
                genre=GameGenre.PUZZLE,
            ),
            timeout=900,
        )
        record["ok"] = True
        record["summary"] = {
            "concept_title": project.concept.title,
            "concept_setting": project.concept.setting[:200],
            "world_name": project.world.name if project.world else None,
            "items_count": len(project.items),
            "quests_count": len(project.quests),
            "npcs_count": len(project.npcs),
            "qa_playable": project.qa_report.playable if project.qa_report else None,
            "qa_issue_count": len(project.qa_report.issues) if project.qa_report else None,
        }
    except asyncio.TimeoutError:
        record["error"] = "timeout"
    except Exception as e:
        record["error"] = f"{type(e).__name__}: {e}"
        record["traceback"] = traceback.format_exc()

    record["elapsed_s"] = round(time.time() - started_at, 2)
    REPORT_PATH.write_text(json.dumps(record, indent=2))

    print("=" * 60)
    print(f"PUZZLE-GENRE SMOKE — {'OK' if record['ok'] else 'FAIL'}")
    print("=" * 60)
    if record["ok"]:
        s = record["summary"]
        print(f"  title:  {s['concept_title']}")
        print(f"  world:  {s['world_name']}")
        print(f"  items:  {s['items_count']}, quests: {s['quests_count']}, npcs: {s['npcs_count']}")
        print(f"  qa:     {'playable' if s['qa_playable'] else 'NOT playable'} ({s['qa_issue_count']} issues)")
    else:
        print(f"  error:  {record.get('error')}")
    print(f"  elapsed: {record['elapsed_s']:.1f}s")
    return 0 if record["ok"] else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
