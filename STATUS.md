# GameForge — Status

**Last updated:** 2026-07-05

## 2026-07-05 — Saga Engine (gl-0084): CK3 mod pipeline Phase 0 scout + Phase 1 spec

New lane, `ck3_saga_engine/` — a fleet-written CK3 flavor-content pipeline
(events/decisions/story_cycles) gated by a real deterministic validator,
distinct from the Godot/Unity game-generation pipeline above. Kruz hand-built
a hello-world proof mod ("Saga Engine," `saga.1` event) before dispatching
this item; that seed is now migrated into git as
`ck3_saga_engine/mod/saga_engine/`.

**Toolchain proven, not just documented:**
- Installed `ck3-tiger` v1.19.0 (community CK3 script validator, exact
  version match for the installed game 1.19.0.6) to
  `~/.operator/bin/ck3-tiger/`.
- `ck3_saga_engine/tools/validate.py` wraps it, parses `--json` output, and
  **exits non-zero on fatal/error findings** — confirmed tiger's own exit
  code is always 0 regardless of errors, so this wrapper is the real gate.
  Verified both ways: clean on the real mod, correctly fails (exit 1, exact
  file/line/message) against a deliberately broken scratch mod.
- `ck3_saga_engine/tools/deploy.py` mirrors the git-tracked mod source into
  the live CK3 mod folder (which lives under `Documents\Paradox Interactive\`,
  outside the repo). Full loop tested: deploy → validate → 0 findings.
- Discovered `common/story_cycles` (vanilla's own multi-event narrative-arc
  system, e.g. the El Cid companion saga) as the right primitive for
  "20-event saga chains" — no new game system needs inventing.

**Docs:** `ck3_saga_engine/docs/SCOUT.md` (toolchain findings),
`THEME_SHORTLIST.md` (5 saga themes for Kruz to pick from, grounded in his
actual save history — a Balkans rise campaign and a Roman-restoration
campaign that reached Imperator), `SPEC.md` (Phase 1 pipeline: generate →
validate → localize-audit → scripted-save playtest, plus a style bible).

**Explicitly not done tonight (by design):** no saga content generated
beyond the pre-existing hello-world seed; no theme picked (Kruz's call);
Phase 2 (mass generation, first 20-event chain) is gated on that pick +
spec sign-off.

## 2026-06-23 — Unity 6 export backend (vertical slice) lands beside Godot

GameForge can now export the **same engine-neutral `GameProject`** to **Unity 6**,
not just Godot. The agent pipeline and `schemas/` were untouched; the Unity
coupling lives entirely beside the three Godot coupling points:

| | Godot | Unity (new) |
|---|---|---|
| Exporter | `orchestrator/godot_exporter.py` | `orchestrator/unity_exporter.py` |
| Template | `godot_template/` | `unity_template/` (Unity `6000.0.77f1`, Built-in RP) |
| Scenes | `.tscn` text | **built in C#** at runtime/build time |

**Key decision (why Unity differs from Godot):** you can't reliably have agents
emit Unity `.unity`/`.prefab` YAML (GUID + `.meta` soup), so — exactly like the
war-table project — the Unity scene is **constructed in C# code**, never
hand-authored. The exporter maps the manifest → (a) `StreamingAssets/gameforge_scene.json`
(a flat JsonUtility-friendly projection) + (b) `GeneratedGameInfo.cs` (the same
data baked into compile-time constants). `GameForgeRuntime.cs` is the single
source of truth that builds the scene from that data, driven by **both** Play and
the headless Editor render — so the PNG matches what plays.

**Wired:** `forge export --engine [godot|unity]` (default stays **godot**);
`GameForge.export(out, engine="unity")`; `unity_project_path` in config.

**PROVEN end-to-end (the gate):** exported `exports/existing-games/wickwater` to
Unity → ran Unity 6 **headless batchmode** → rendered a PNG of the game standing
up (title, 12 colour-coded room cubes, player at room 2/12 after `NextRoom()`,
live quests/items/NPCs/QA panel — all from real manifest data). Render proof:
`docs/unity_slice_wickwater.png`. The standalone player build also succeeds
headless: `GF_BUILD_RESULT result=Succeeded errors=0` → `GameForge.exe`.

The verify-by-looking + headless commands live in `docs/UNITY_EXPORT.md`.

**Tests:** 164 passed, 5 deselected (+3 new `tests/test_unity_exporter.py`, all
pure-Python — no Unity needed in CI). Slice scope is deliberate; deepening the
schema → C# mapping (combat, dialogue, item systems, spatial layouts) is the
next pass.

## 2026-06-11 — iterate() off the shim: the LAST silent-failure path is closed

`GameDirector.iterate()` (and with it the QA-fix loop `_iterate_on_qa` AND the
2026-05-16 Hermes auto-iteration, both of which ride it) was still on the old
Anthropic-shape `_call_claude` shim — the exact path FIRST_GENERATION_FINDINGS
proved replies conversationally inside a CLAUDE.md project and fails silently.
Now routed through `_call_structured(GameProject, ...)` like the 5 create
stages, with a verbatim-carry-through contract in the prompt and a 480s
timeout (whole-project regeneration is the heaviest call). New regression test
pins it (mocked `claudex.ask_structured`, asserts feedback + full project in
the prompt and validated swap of `_project`).

**Test invocation note:** with `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1` (the global
pytest-django-hang guard) this repo needs `-p asyncio` or every async test
false-fails:

```powershell
$env:PYTEST_DISABLE_PLUGIN_AUTOLOAD=1; py -m pytest -p asyncio -q
```

Verified 2026-06-11: **161 passed, 5 deselected** (bridge E2E needs a running
Godot, as before) + `scripts/smoke_first_generation.py` OK.

## What Is This

AI-agent-powered game development toolkit. A team of Claude agents (Opus directing, Sonnet generating, Haiku testing) creates complete Godot 4 games from natural-language prompts. Python orchestrator talks to Godot via JSON-RPC 2.0 over WebSocket — no intermediary servers, no third-party plugins.

## 2026-05-14 milestone — FULL 5-STAGE PIPELINE WORKS

The 5-agent pipeline had been sitting idle since 2026-04-12 (foundation
complete, but never actually run with real model calls). Tonight all
five stages produced a complete Pydantic-validated `GameProject`
end-to-end in 278 seconds (~4.5 min), via the Claude CLI (Max sub),
no model API key required.

**Live smoke output (smoke_full_pipeline.py):**
- title: "Wickwater"
- setting: sunken ossuary beneath a drowned coastal monastery
- 12 items / 6 quests / 5 NPCs / full style guide
- QA agent found 12 specific design issues
  ("quest_unfinished_compline is currently uncompletable as wired")
- 278s wall-clock

**Second generation (smoke_full_pipeline_puzzle.py, 2026-05-14):**
- title: "Steeped"  ·  genre: puzzle (proves multi-genre support)
- setting: a back-alley tea room on a rainy evening
- 12 items / 6 quests / 4 NPCs / full style guide
- QA verdict: **PLAYABLE** (12 minor issues, no blockers)
- 4 tea-themed glass orb colors, 3 difficulty modes, Steep+Pour
  combo mechanic, hand-lettered receipt scoring
- 358s wall-clock

Galleries:
- `docs/GAME_GALLERY.md` — Wickwater
- `docs/GAME_GALLERY_STEEPED.md` — Steeped

Mission Control's GAME-FORGE RUNS widget lists both runs once
the studio-os server is restarted (the running instance has the
pre-widget mission_control.py module cached in memory).

**Root cause uncovered:** the old SDK-shaped shim was flattening
the Director's multi-turn message envelope into XML-tagged text and
piping to `claude -p`. The CLI loaded the project's CLAUDE.md, saw a
vaguely-formatted prompt, and replied conversationally ("I'm ready to
help with GameForge work") instead of executing. JSON.loads exploded
on prose. Failed silently for weeks.

**Fix:** The Claude CLI has native `--output-format json --json-schema`
flags that force schema-matching structured output regardless of
project context. New helpers `claudex.ask_structured()` and
`GameDirector._call_structured()` route through this. The
`structured_output` envelope field carries the validated payload.

**Migrated:** `_generate_concept` only. The other 4 stages (world,
mechanics, narrative, art, QA) are straightforward ports — see
`docs/FIRST_GENERATION_FINDINGS.md` for the forward plan.

Smoke harness lives at `scripts/smoke_first_generation.py`. Run
`py scripts/smoke_first_generation.py` and you should see an OK report
in ~30 seconds.

Tests: 110/110 unit tests passing (5 pre-existing bridge_e2e failures
require a running Godot server, unrelated to this change). 9/9 director
tests migrated to mock `claudex.ask_structured`.

Cost per call: $0.26 first time (cache-creation overhead), $0.05-0.10
warm. Full 5-stage generation should land $0.50-1.50 per game.

## 2026-05-16 exporter pass — existing games now open as game-specific builds

The export gap is no longer blank-template only. `forge.export(...)` now writes
manifest-derived Godot scenes/scripts:

- `res://scenes/generated/generated_game.tscn` becomes the main scene.
- One generated scene is written for each manifest play space.
- `scripts/generated/game_project_data.gd`, `gameplay_loop.gd`, and
  `quest_runtime.gd` load the manifest, show rooms/quests/items/NPCs, and expose
  a visible "Still Unfinished" QA panel.

Rebuilt existing games with no model calls:

- The Midnight Interchange — 7 scenes, 3 scripts
- Steeped — 7 scenes, 3 scripts
- The Saltwind Steepers — 13 scenes, 3 scripts
- Wickwater — 13 scenes, 3 scripts

Godot 4.6.2 opened the generated Midnight export headlessly without script parse
errors. Python verification is 160 passed / 5 bridge E2E deselected.

## Current State: v0.1.2 — design-to-Godot vertical slice exporter working

### Working

- **Orchestrator pipeline**: GameDirector (Opus) coordinates 5 specialized worker agents through a 7-step pipeline: concept → world → mechanics → narrative → art → assembly → QA
- **5 agent workers**: WorldBuilder, NarrativeEngine, MechanicsEngine, ArtDirector, QATester — all with role-specific system prompts and structured JSON output
- **51 Pydantic schemas**: Full data contracts for worlds, dungeons, quests, NPCs, items, combat, encounters, dialogue trees, lore, stat systems, style guides, QA reports
- **MCP bridge**: Python WebSocket client (JSON-RPC 2.0) with reconnection, timeouts, and error handling
- **MCP server (Godot side)**: Custom `mcp_server.gd` — WebSocket server on port 6100, 20 tools exposed, accepts direct connections from the Python bridge
- **Bridge verified end-to-end**: Python connects → ping/pong → lists 20 tools → reads full game state (player_stats, inventory, quests, flags, gold, equipment)
- **Scene/script tools**: Create Godot scenes, generate GDScript, manage nodes — all via MCP
- **State persistence**: SQLite via aiosqlite — save/load worlds, entities, full projects
- **Asset pipeline**: Replicate FLUX for image gen, Pillow fallback for colored placeholder sprites with labels
- **Godot template**: 12 GDScript files — game state, event bus, dialogue (typewriter + branching), turn-based combat, inventory, quest tracker, NPC controller, MCP server, procedural dungeon/tilemap/encounter generation
- **CLI**: `forge create`, `forge iterate`, `forge export`, `forge status`
- **110 tests passing** (schemas: 55, state: 16, tools: 30, director: 9) + E2E bridge test
- **Top-level imports work**: `from orchestrator import GameForge, GameConfig`

### Installed & Configured

- **Godot 4.6.2** installed via `winget install GodotEngine.GodotEngine`
  - Exe: `C:\Users\Kruz\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.2-stable_win64.exe`
  - Console: same path but `_console.exe` (for headless/CLI use)
  - Aliases: `godot`, `godot_console` (available after shell restart)
- **MCP server**: Custom-built `mcp_server.gd` autoloaded in project.godot — no third-party plugin needed
  - Listens on `ws://127.0.0.1:6100`
  - JSON-RPC 2.0 protocol
  - 20 tools: create_scene, add_node, set_node_property, list_scenes, write_script, read_script, list_scripts, get_state, set_flag, add_item, remove_item, add_xp, modify_gold, start_quest, complete_quest, trigger_dialogue, start_combat, spawn_entity, teleport_player, notification
- **Python venv**: `.venv/` in project root, `pip install -e ".[dev]"` done

### Not Yet Done

- **Full `forge create` end-to-end**: Agent pipeline generates content through Claude CLI; next proof is opening/exporting the generated Godot project and hitting Play
- **Image generation**: AssetTools has Replicate FLUX integration code but needs `REPLICATE_API_TOKEN`; Pillow placeholders work now
- **Audio generation**: Stubbed in asset pipeline, not implemented
- **NobodyWho integration**: Local LLM for shipped NPC dialogue (zero API cost) — identified but not integrated

### Architecture

```
Python Orchestrator (Claude Agent SDK)
├── director.py      → Opus coordinator
├── world_builder    → Sonnet: maps, regions, dungeons
├── narrative_engine → Sonnet: quests, NPCs, dialogue
├── mechanics_engine → Haiku: stats, combat, balance
├── art_director     → Sonnet: asset descriptions
├── qa_tester        → Haiku: playtest simulation
│
├── GodotBridge (Python) ──WebSocket──→ mcp_server.gd (Godot)
│   ws://127.0.0.1:6100                 20 tools, JSON-RPC 2.0
│
├── [SQLite State]   Single source of truth
└── [Asset Pipeline] Replicate FLUX / Pillow fallback
```

## File Count

| Category | Files | Lines (approx) |
|----------|-------|-----------------|
| Orchestrator (Python) | 9 | ~2,500 |
| Schemas (Pydantic) | 7 | ~1,200 |
| Tools (MCP/state/assets) | 6 | ~1,500 |
| Godot template (GDScript) | 12 + 2 scene files | ~2,500 |
| Tests | 5 + conftest | ~2,000 |
| Examples | 3 | ~150 |
| Config/docs | 5 | ~300 |
| **Total** | **~49 source files** | **~10,150** |

## Test Results

```
110 passed in 43.46s
```

- `test_schemas.py`: 55 tests — all Pydantic models, JSON roundtrips, validation, enums
- `test_state.py`: 16 tests — SQLite CRUD, upsert, filtering, project lifecycle
- `test_tools.py`: 30 tests — MCP message formatting, GDScript gen, Pillow sprites
- `test_director.py`: 9 tests — concept generation, worker dispatch, pipeline flow (mocked API)
- `test_bridge_e2e.py`: E2E bridge test (launches Godot headless, connects, verifies ping + tools + state)

## What Comes Next

1. **First full game generation**: Run `forge create` through Claude CLI, output into Godot, hit Play
2. **Asset generation**: Prefer local/placeholders first; only wire external image services if explicitly wanted
3. **NobodyWho plugin**: Local LLM for NPC dialogue in shipped games
4. **Multi-agent parallelism**: WorldBuilder + NarrativeEngine can run concurrently
5. **Campaign mode**: Chain multiple `forge iterate` calls with persistent state
