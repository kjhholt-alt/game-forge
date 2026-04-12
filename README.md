# GameForge

**AI agents that build games, not just play them.**

GameForge is an AI-powered game development toolkit that uses a team of
specialized Claude agents to design, write, balance, and QA-test a complete
game from a single natural-language prompt. The output is a playable Godot 4
project.

---

## Architecture

```
                         +------------------+
                         |   Human Prompt   |
                         +--------+---------+
                                  |
                                  v
                      +-----------+-----------+
                      |    Game Director      |  <-- Opus (coordinator)
                      |   concept + routing   |
                      +-----------+-----------+
                                  |
            +----------+----------+----------+----------+
            |          |          |          |          |
            v          v          v          v          v
      +---------+ +---------+ +---------+ +---------+ +---------+
      |  World  | |Narrative| |Mechanics| |   Art   | |   QA    |
      | Builder | | Engine  | | Engine  | |Director | | Tester  |
      +---------+ +---------+ +---------+ +---------+ +---------+
      | regions | | quests  | | items   | |  asset  | | balance |
      | factions| | NPCs    | | balance | |  specs  | | review  |
      | lore    | | dialogue| | rules   | | styles  | | issues  |
      +---------+ +---------+ +---------+ +---------+ +---------+
            |          |          |          |          |
            +----------+----------+----------+----------+
                                  |
                                  v
                      +-----------+-----------+
                      |    Godot MCP Bridge   |
                      |  scenes + GDScript    |
                      +-----------+-----------+
                                  |
                                  v
                      +-----------+-----------+
                      |   Playable Godot 4    |
                      |       Project         |
                      +-----------------------+
```

## Quick Start

### 1. Install

```bash
# Clone
git clone https://github.com/kjhholt-alt/game-forge.git
cd game-forge

# Create a virtual environment
python -m venv .venv
source .venv/bin/activate   # Linux / macOS / Git Bash
# .venv\Scripts\activate    # Windows PowerShell

# Install
pip install -e ".[dev]"
```

### 2. Configure

```bash
# Set your Anthropic API key
export ANTHROPIC_API_KEY="sk-ant-..."

# Or create a .env file
echo 'ANTHROPIC_API_KEY=sk-ant-...' > .env
```

### 3. Create Your First Game

```bash
forge create "A roguelike dungeon crawler where you befriend monsters instead of fighting them" --genre roguelike
```

### 4. Iterate

```bash
forge iterate "Add a boss encounter in the crystal caves and make the friendship mechanic harder"
```

### 5. Export

```bash
forge export --output ./my-game
```

Open `./my-game/` in Godot 4.6+ and hit Play.

---

## How It Works

GameForge uses a **Director pattern** -- a single Opus-tier agent
coordinates a team of specialized workers:

| Agent | Model | Responsibility |
|-------|-------|----------------|
| **Game Director** | Opus | Reads the prompt, produces a game concept, orchestrates the pipeline, handles iteration |
| **World Builder** | Sonnet | Creates regions, biomes, factions, lore, and the world map graph |
| **Narrative Engine** | Sonnet | Writes quests (main + side), NPCs, dialogue trees, and story arcs |
| **Mechanics Engine** | Sonnet | Designs items, stats, balance curves, and interaction rules |
| **Art Director** | Sonnet | Produces detailed asset specifications for sprites, tilesets, and UI |
| **QA Tester** | Sonnet | Simulates a playtest, scores the design 0-10, and files issues |

Each agent receives a role-specific system prompt and returns structured
JSON that is validated against Pydantic schemas. The Director retries
on parse failures and iterates on critical QA issues automatically.

---

## CLI Commands

```
forge create <prompt> --genre <genre>   Create a new game
forge iterate <feedback>                Apply changes to the current project
forge export --output <dir>             Export as a Godot project
forge status                            Show current project summary
```

**Supported genres:** `rpg`, `roguelike`, `platformer`, `puzzle`,
`strategy`, `adventure`

---

## Project Structure

```
game-forge/
  orchestrator/          # Core agent orchestration
    __init__.py          # Package init, exports GameForge + GameConfig
    config.py            # Pydantic settings, enums (AgentRole, GameGenre)
    director.py          # GameDirector -- Opus coordinator
    forge.py             # GameForge -- high-level facade
    cli.py               # Click CLI (the `forge` command)
    prompts.py           # System prompts for each agent role
  schemas/               # Pydantic data models (51 types)
    world.py             # Biome, Room, Region, DungeonLayout, WorldDefinition
    quest.py             # Quest, QuestChain, DialogueTree, LoreEntry
    npc.py               # NPCDefinition, Personality, Relationship, Schedule
    item.py              # ItemDefinition, LootTable, StatModifier
    combat.py            # CombatSystem, StatSystem, Encounter, Ability, QAReport
    project.py           # GameConcept, GameProject, GameGenre
  tools/                 # MCP bridge and Godot integration
    godot_bridge.py      # WebSocket MCP client (JSON-RPC 2.0)
    scene_tools.py       # Create/modify Godot scenes via MCP
    script_tools.py      # Generate and validate GDScript
    state_tools.py       # SQLite game state persistence (aiosqlite)
    asset_tools.py       # AI image generation + Pillow placeholders
  godot_template/        # Godot 4.6 game template (11 GDScript files)
    scripts/
      game_state.gd      # Central state autoload (inventory, quests, stats)
      event_bus.gd       # Global signal bus (15 signals)
      dialogue_system.gd # Branching dialogue with typewriter effect
      combat_system.gd   # Turn-based combat engine
      inventory.gd       # Inventory UI with rarity colors
      quest_tracker.gd   # Quest journal with objectives
      npc_controller.gd  # NPC behavior (wander, talk, follow)
      mcp_client.gd      # WebSocket bridge to Python orchestrator
      procedural/        # Tilemap, dungeon, and encounter generation
  tests/                 # Pytest test suite
  examples/              # Example prompts and outputs
  pyproject.toml         # Python project configuration
  requirements.txt       # Flat dependency list
```

---

## Tech Stack

- **Python 3.11+** -- async throughout
- **Anthropic Claude API** -- Opus for direction, Sonnet for workers, Haiku for fast tasks
- **Pydantic v2** -- schema validation for every agent input/output
- **Click** -- CLI framework
- **Rich** -- terminal UI (progress spinners, tables, panels)
- **Godot 4.6+** -- target game engine
- **Godot MCP Server** -- WebSocket bridge for scene/script generation
- **aiosqlite** -- async SQLite for game state persistence
- **Pillow** -- placeholder asset generation
- **websockets** -- MCP bridge transport

---

## Requirements

| Requirement | Version | Notes |
|-------------|---------|-------|
| Python | >= 3.11 | async/await, `StrEnum`, type hints |
| Anthropic API key | -- | Set as `ANTHROPIC_API_KEY` |
| Godot Engine | >= 4.6 | For opening exported projects |
| Godot MCP Server | -- | Optional; enables live scene generation via WebSocket |

---

## Programmatic Usage

```python
import asyncio
from orchestrator import GameForge, GameConfig, GameGenre

async def main():
    config = GameConfig(anthropic_api_key="sk-ant-...")
    forge = GameForge(config)

    # Create
    project = await forge.create(
        "A cozy farming RPG with magic crops",
        GameGenre.RPG,
    )
    print(f"Created: {project.concept.title}")
    print(f"Regions: {len(project.world.overworld.regions)}")
    print(f"Quests: {len(project.quests)}")

    # Iterate
    project = await forge.iterate("Add a fishing mini-game")

    # Export
    forge.export("./my-farm-game")

asyncio.run(main())
```

---

## Development

```bash
# Install dev dependencies
pip install -e ".[dev]"

# Run tests
pytest

# Type check
mypy orchestrator schemas

# Lint
ruff check .
```

---

## License

MIT
