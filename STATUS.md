# GameForge — Status

**Last updated:** 2026-04-12

## What Is This

AI-agent-powered game development toolkit. A team of Claude agents (Opus directing, Sonnet generating, Haiku testing) creates complete Godot 4 games from natural-language prompts. Python orchestrator talks to Godot via JSON-RPC 2.0 over WebSocket — no intermediary servers, no third-party plugins.

## Current State: v0.1.0 — Foundation Complete + Bridge Verified

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

- **Full `forge create` end-to-end**: Agent pipeline generates content but hasn't been run with real API key → Godot yet
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

1. **First full game generation**: Run `forge create` with real API key, output into Godot, hit Play
2. **Asset generation**: Wire up Replicate API key, test sprite/tileset output
3. **NobodyWho plugin**: Local LLM for NPC dialogue in shipped games
4. **Multi-agent parallelism**: WorldBuilder + NarrativeEngine can run concurrently
5. **Campaign mode**: Chain multiple `forge iterate` calls with persistent state
