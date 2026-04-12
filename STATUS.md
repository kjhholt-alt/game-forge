# GameForge — Status

**Last updated:** 2026-04-12

## What Is This

AI-agent-powered game development toolkit. A team of Claude agents (Opus directing, Sonnet generating, Haiku testing) creates complete Godot 4 games from natural-language prompts. Python orchestrator talks to Godot via MCP WebSocket bridge.

## Current State: v0.1.0 — Foundation Complete

### Working

- **Orchestrator pipeline**: GameDirector (Opus) coordinates 5 specialized worker agents through a 7-step pipeline: concept → world → mechanics → narrative → art → assembly → QA
- **5 agent workers**: WorldBuilder, NarrativeEngine, MechanicsEngine, ArtDirector, QATester — all with role-specific system prompts and structured JSON output
- **51 Pydantic schemas**: Full data contracts for worlds, dungeons, quests, NPCs, items, combat, encounters, dialogue trees, lore, stat systems, style guides, QA reports
- **MCP bridge**: WebSocket client (JSON-RPC 2.0) with reconnection, timeouts, and error handling
- **Scene/script tools**: Create Godot scenes, generate GDScript, manage nodes — all via MCP
- **State persistence**: SQLite via aiosqlite — save/load worlds, entities, full projects
- **Asset pipeline**: Replicate FLUX for image gen, Pillow fallback for colored placeholder sprites with labels
- **Godot template**: 11 GDScript files — game state, event bus, dialogue (typewriter + branching), turn-based combat, inventory, quest tracker, NPC controller, MCP client, procedural dungeon/tilemap/encounter generation
- **CLI**: `forge create`, `forge iterate`, `forge export`, `forge status`
- **110 tests passing** (schemas: 55, state: 16, tools: 30, director: 9)
- **Top-level imports work**: `from orchestrator import GameForge, GameConfig`

### Not Yet Wired

- **Godot MCP server**: The bridge client is built but needs an actual Godot MCP server running (install [Godot-MCP](https://github.com/ee0pdt/Godot-MCP) or [Godot MCP Pro](https://github.com/youichi-uda/godot-mcp-pro))
- **Live scene generation**: SceneTools/ScriptTools make MCP calls but haven't been tested against a running Godot instance
- **Image generation**: AssetTools has Replicate FLUX integration code but needs `REPLICATE_API_TOKEN` configured; Pillow placeholders work now
- **Audio generation**: Stubbed in asset pipeline, not implemented
- **NobodyWho integration**: Local LLM for shipped NPC dialogue (zero API cost) — identified but not integrated

### Architecture

```
Python Orchestrator (Claude Agent SDK)
├── director.py     → Opus coordinator
├── world_builder   → Sonnet: maps, regions, dungeons
├── narrative_engine → Sonnet: quests, NPCs, dialogue
├── mechanics_engine → Haiku: stats, combat, balance
├── art_director    → Sonnet: asset descriptions
├── qa_tester       → Haiku: playtest simulation
│
├── [MCP Bridge] ←→ Godot Engine (GDScript runtime)
├── [SQLite State]   Single source of truth
└── [Asset Pipeline] Replicate FLUX / Pillow fallback
```

## File Count

| Category | Files | Lines (approx) |
|----------|-------|-----------------|
| Orchestrator (Python) | 9 | ~2,500 |
| Schemas (Pydantic) | 7 | ~1,200 |
| Tools (MCP/state/assets) | 6 | ~1,500 |
| Godot template (GDScript) | 11 + 2 scene files | ~2,000 |
| Tests | 4 + conftest | ~1,800 |
| Examples | 3 | ~150 |
| Config/docs | 5 | ~300 |
| **Total** | **~47 source files** | **~9,500** |

## Test Results

```
110 passed in 43.46s
```

- `test_schemas.py`: 55 tests — all Pydantic models, JSON roundtrips, validation, enums
- `test_state.py`: 16 tests — SQLite CRUD, upsert, filtering, project lifecycle
- `test_tools.py`: 30 tests — MCP message formatting, GDScript gen, Pillow sprites
- `test_director.py`: 9 tests — concept generation, worker dispatch, pipeline flow (mocked API)

## What Comes Next

1. **Install Godot 4.6 + MCP server** — connect the bridge to a real Godot instance
2. **End-to-end test**: `forge create` → open in Godot → hit Play
3. **Asset generation**: Wire up Replicate API key, test sprite/tileset output
4. **NobodyWho plugin**: Local LLM for NPC dialogue in shipped games
5. **Multi-agent parallelism**: WorldBuilder + NarrativeEngine can run concurrently
6. **Campaign mode**: Chain multiple `forge iterate` calls with persistent state
