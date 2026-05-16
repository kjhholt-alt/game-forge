# Existing Games Build Gap Review

_Updated 2026-05-16 after the deterministic Godot exporter pass._

## What Changed

GameForge exports are no longer only the shared Godot template plus
`game_project.json`. Every export now gets:

- `scenes/generated/generated_game.tscn` as the actual main scene
- One generated room/space scene per manifest play space
- `scripts/generated/game_project_data.gd` to load the manifest
- `scripts/generated/gameplay_loop.gd` for a playable inspection loop
- `scripts/generated/quest_runtime.gd` for quest/item progress state
- A visible **Still Unfinished** panel sourced from the QA report

This turns each saved design into a runnable vertical-slice shell: you can open
the project, move through its rooms/spaces, click quest and item beats, read NPC
context, and see the remaining build gaps inside the game itself.

## Existing Games

### The Midnight Interchange

Export: `exports/existing-games/the-midnight-interchange`

Generated: 7 scenes, 3 scripts

Feel that is working:
- Brass-clock midnight station identity is clear.
- Five-room loop maps cleanly to generated spaces.
- Quest/item/NPC panels make the clockmaker fantasy readable fast.

Still missing:
- Real mainspring charge economy instead of generic "Solve" clicks.
- Actual Stationmaster riddle, Porter memory-match, and Last Passenger sliding-tile mechanics.
- Persistent ledger save state and moon-meter balance.
- Custom platform/glass/steam shaders and art assets.

### Steeped

Export: `exports/existing-games/steeped`

Generated: 7 scenes, 3 scripts

Feel that is working:
- Tea-room puzzle identity survives the export.
- Display-case/orb concept is readable without rereading the design doc.
- Cozy single-screen tone fits the generated shell.

Still missing:
- Real falling-orb grid, color matching, clear scoring, and difficulty modes.
- Tea-room UI polish: receipt scoring, glass orb states, jazz/ambient audio.
- Puzzle-specific failure/retry loop.

### The Saltwind Steepers

Export: `exports/existing-games/the-saltwind-steepers`

Generated: 13 scenes, 3 scripts

Feel that is working:
- The travel/coastal-village RPG premise reads well as a room/quest atlas.
- NPC and delivery beats give it a stronger "cozy route planning" feel than the template did.

Still missing:
- Sailing route navigation and weather friction.
- Trade goods, recipe decoding, letter delivery state, and village reputation.
- A non-combat RPG progression model instead of generic quest completion.

### Wickwater

Export: `exports/existing-games/wickwater`

Generated: 13 scenes, 3 scripts

Feel that is working:
- Flooded monastery, lantern-oil pressure, and shrine/relic mood are still the strongest concept package.
- Generated room cards make the tide-shifted layout easier to understand.

Still missing:
- Oil drain, tide phase changes, and lantern reflection puzzles.
- Wick crafting recipes and relic-to-wick mapping.
- Choirbone note response, Brinewraith reflection, Hollowman mirror logic.
- Strongest candidate for the next hand-built mechanic pass.

## Recommendation

Do the next pass game-by-game instead of trying to make one generic mechanic
engine solve all four. Start with **Wickwater** if the goal is atmosphere and
mechanical identity, or **Steeped** if the goal is the fastest actually playable
loop.
