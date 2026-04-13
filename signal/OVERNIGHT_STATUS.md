# SIGNAL Overnight Sprint Status — 2026-04-13

## What's Working
- **Full gameplay loop**: Click target → classify → right-click → COA cards → select option → asset moves → mission resolves → budget reward → objective counter updates
- **3 targets**: CONVOY, COMPOUND, SIGINT (+ 1 delayed vehicle at 25s)
- **3 assets**: REAPER (drone), ALPHA (ground), BRAVO (ground)  
- **Handler voice**: TTS speaks on every action (classify, assign, resolve, complications)
- **Detection system**: Each COA costs detection, visible in HUD
- **Mission chaining**: 2 missions (MERIDIAN SHADOW → ARCTIC LENS) with upgrade shop between
- **Claude DM server**: Runtime AI for handler commentary, intel assessments, advisory (port 8090)

## Visual State
- Dark navy terrain shader with procedural features (water, roads, elevation)
- Blips: solid fill + thick 6px ring + triple-layer glow halo + white center
- White text labels with shadow on classified targets
- Sidebar: Maven-style cards with colored left border, title, status line, type badge
- Compass rose in top-right
- COA cards: 140x180px with EYE/NET/BOLT icons, risk bars, colored labels
- Grid lines visible, sector labels at edges
- CRT shader: minimal (scanlines + slight vignette)

## MCP Debug Server (port 9090)
The game exposes an HTTP server for remote playtesting:
```
GET  /health          → {"status": "ok"}
GET  /screenshot      → saves PNG, returns path
GET  /blips           → all blip positions + states
GET  /hud             → codename, budget, timer, objective
GET  /state           → phase, detection, fps
GET  /tree?depth=3    → scene tree
GET  /node?path=...   → node properties
POST /click?x=&y=&button= → click at viewport coords
POST /key?key=ENTER   → simulate keypress
GET  /select_coa?index=1  → select COA card by index
```

## Known Issues
1. Blips still dimmer than Maven reference on ultrawide (3440x1417)
2. Sidebar doesn't update entry text when targets are neutralized
3. Phase shows "briefing" even during active gameplay (state machine bypass)
4. The staggered intro has ~15s wait for first click before remaining targets appear
5. CRT scanlines are visible as horizontal banding in screenshots

## File Inventory (17 GDScript + 7 support files)
```
scripts/autoloads/: event_bus.gd, game_state.gd, op_state.gd, voice_handler.gd, debug_server.gd
scripts/map/:       tactical_map.gd
scripts/main/:      main_controller.gd
scripts/ui/:        coa_cards.gd, hud.gd, juice.gd, crt_overlay.gd, 
                    target_sidebar.gd, info_card.gd, timeline_bar.gd,
                    quick_decision.gd, upgrade_shop.gd
scripts/systems/:   detection_system.gd, claude_dm.gd
server/:            dm_server.py, requirements.txt
mcp/:               godot_mcp_server.py
assets/shaders/:    terrain.gdshader, crt_effect.gdshader
assets/themes/:     war_room.tres
data/:              test_mission.json, mission_02.json, test_campaign.json
```
