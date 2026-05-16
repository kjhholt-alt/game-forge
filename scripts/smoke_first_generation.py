"""First-generation smoke harness for GameForge.

This is the smallest end-to-end exercise: it instantiates the Director,
runs ONE concept-generation call against the Claude CLI via claudex,
and reports timing + the structured output.

The goal is to validate that the entire chain — config → director →
claudex shim → claude -p subprocess → JSON parse → Pydantic schema —
works end-to-end before we attempt full game generation.

Usage:
    py scripts/smoke_first_generation.py

Designed to fit under 60 seconds and produce a single JSON report at
scripts/smoke_first_generation.report.json so subsequent runs are
diffable.

No real-money implications: claudex routes through the local Claude CLI
(Max sub), zero per-token charges. The Replicate calls (sprite gen) are
deferred to a separate smoke and are NOT exercised here.
"""
from __future__ import annotations

import asyncio
import json
import sys
import time
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT))

REPORT_PATH = HERE / "smoke_first_generation.report.json"


async def main() -> int:
    started_at = time.time()
    record: dict = {
        "started_at_iso": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "stages": [],
        "ok": False,
        "error": None,
    }

    # --- Stage 1: Import the orchestrator ---
    stage_t = time.time()
    try:
        from orchestrator.config import GameConfig, GameGenre
        from orchestrator.director import GameDirector
        record["stages"].append({
            "stage": "import",
            "elapsed_s": round(time.time() - stage_t, 2),
            "ok": True,
        })
    except Exception as e:
        record["stages"].append({
            "stage": "import",
            "elapsed_s": round(time.time() - stage_t, 2),
            "ok": False,
            "error": f"{type(e).__name__}: {e}",
        })
        record["error"] = "import failed"
        REPORT_PATH.write_text(json.dumps(record, indent=2))
        print(json.dumps(record, indent=2))
        return 1

    # --- Stage 2: Initialize Director ---
    stage_t = time.time()
    try:
        # Use empty key — claudex doesn't read it but Pydantic settings
        # config may require it. The actual Anthropic SDK is shimmed.
        config = GameConfig(
            state_db_path=str(HERE / "smoke_first_generation.state.db"),
            max_retries=1,
            enable_streaming=False,
        )
        director = GameDirector(config)
        record["stages"].append({
            "stage": "director_init",
            "elapsed_s": round(time.time() - stage_t, 2),
            "ok": True,
            "director_model": config.director_model,
            "worker_model": config.worker_model,
        })
    except Exception as e:
        record["stages"].append({
            "stage": "director_init",
            "elapsed_s": round(time.time() - stage_t, 2),
            "ok": False,
            "error": f"{type(e).__name__}: {e}",
            "traceback": traceback.format_exc(),
        })
        record["error"] = "director init failed"
        REPORT_PATH.write_text(json.dumps(record, indent=2))
        print(json.dumps(record, indent=2))
        return 2

    # --- Stage 3: Generate concept ---
    stage_t = time.time()
    smoke_prompt = (
        "A minimal top-down roguelike: one dungeon, three enemy types, "
        "one treasure room. Pixel art, calm exploration over combat."
    )
    try:
        concept = await asyncio.wait_for(
            director._generate_concept(smoke_prompt, GameGenre.ROGUELIKE),
            timeout=180.0,  # 3 min hard cap for the single call
        )
        record["stages"].append({
            "stage": "concept",
            "elapsed_s": round(time.time() - stage_t, 2),
            "ok": True,
            "concept": {
                "title": concept.title,
                "genre": concept.genre,
                "setting": concept.setting[:200],
                "core_mechanics": concept.core_mechanics,
                "art_style": concept.art_style,
                "target_mood": concept.target_mood,
            },
        })
        record["ok"] = True
    except asyncio.TimeoutError:
        record["stages"].append({
            "stage": "concept",
            "elapsed_s": round(time.time() - stage_t, 2),
            "ok": False,
            "error": "timeout after 180s",
        })
        record["error"] = "concept generation timed out"
    except Exception as e:
        record["stages"].append({
            "stage": "concept",
            "elapsed_s": round(time.time() - stage_t, 2),
            "ok": False,
            "error": f"{type(e).__name__}: {e}",
            "traceback": traceback.format_exc(),
        })
        record["error"] = "concept generation raised"

    record["total_elapsed_s"] = round(time.time() - started_at, 2)
    REPORT_PATH.write_text(json.dumps(record, indent=2))

    # Print a tight summary so the CI log stays readable
    print("=" * 60)
    print(f"FIRST GENERATION SMOKE — {'OK' if record['ok'] else 'FAIL'}")
    print("=" * 60)
    for s in record["stages"]:
        status = "OK" if s["ok"] else "FAIL"
        print(f"  [{status:>4}] {s['stage']:<16} {s['elapsed_s']:>6.2f}s"
              f"{'  ' + s.get('error', '') if not s['ok'] else ''}")
    if record["ok"]:
        c = next(s for s in record["stages"] if s["stage"] == "concept")
        cp = c["concept"]
        print()
        print(f"  title:    {cp['title']}")
        print(f"  setting:  {cp['setting'][:120]}")
        print(f"  mood:     {cp['target_mood']}")
        print(f"  mechanics: {', '.join(cp['core_mechanics'])}")
        print(f"  art:      {cp['art_style']}")
    print()
    print(f"  total:    {record['total_elapsed_s']:.2f}s")
    print(f"  report:   {REPORT_PATH}")
    return 0 if record["ok"] else 3


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
