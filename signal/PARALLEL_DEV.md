# SIGNAL — Parallel Development Spec

> Read this file before touching any code. It defines who owns what.

## Game Overview

SIGNAL is an intelligence analyst roguelike in Godot 4.6. Three phases per operation:

1. **SIGNAL** — Evidence board. Read intercepted comms, draw connections between clues, compute prep score.
2. **BLACKSITE** — Terminal hacking. Scan hosts, exploit vulns, login with found creds, exfiltrate files. Detection meter rises.
3. **DEBRIEF** — Grade + XP. Show what was found, award skill points, advance campaign.

The tactical map (war room) is the persistent backdrop. Handler speaks via TTS. Zero reading required (subtitles optional).

## Architecture

```
Autoloads (singletons):
  EventBus      — Signal bus, all inter-system communication
  GameState     — Campaign + analyst persistence (loads from JSON)
  OpState       — Per-operation state (evidence, detection, terminal, SE)
  VoiceHandler  — TTS queue + subtitles
  Juice         — Visual feedback (pop, shake, float_text, glow)

Scene tree (main.tscn):
  Main (Control + main_controller.gd)
  ├── TacticalMap        — Grid + blips + assets + threat zones
  ├── HUD                — Codename, detection bar, budget, subtitles
  ├── BriefingOverlay    — [Lane 1] Phase overlay for briefing text
  ├── EvidenceBoard      — [Lane 2] SIGNAL phase interactive pinboard
  ├── TerminalPanel      — [Lane 3] BLACKSITE phase hacking terminal
  ├── SocialEngPanel     — [Lane 4] Employee dialogue/trust UI
  ├── DebriefOverlay     — [Lane 1] Post-op grading screen
  ├── COACards           — Slide-up course of action picker
  └── CRTOverlay         — Scanline/vignette shader
```

## Lane Ownership

### Lane 1: Core Loop (SPINE)
**Owner files:**
- `scripts/autoloads/event_bus.gd`
- `scripts/autoloads/game_state.gd`
- `scripts/autoloads/op_state.gd`
- `scripts/main/main_controller.gd`
- `scenes/main.tscn`
- `project.godot`
- `data/test_campaign.json`
- `data/test_mission.json`

**Delivers:** Phase state machine (briefing → signal → blacksite → debrief), campaign data loading, signal wiring between all systems.

**Merge order:** FIRST. Everything else plugs into this.

### Lane 2: Evidence Board (SIGNAL Phase)
**Owner files:**
- `scripts/ui/evidence_board_ui.gd` (NEW)
- `scenes/evidence_board.tscn` (NEW)
- Any files in `assets/` prefixed with `evidence_`

**Reads (don't modify):**
- `OpState.evidence_items`, `OpState.connections`, `OpState.compute_prep_score()`
- `EventBus` signals (emit only, don't add new ones without coordinating with Lane 1)

**Delivers:** Interactive evidence card grid, drag-to-connect lines, prep score display, clue vs noise visual distinction.

**Key signals to emit:**
- `EventBus.handler_speak` — when player discovers something
- Custom signals should go through EventBus (ask Lane 1 to add them)

### Lane 3: Terminal / BLACKSITE
**Owner files:**
- `scripts/ui/terminal_ui.gd` (NEW)
- `scenes/terminal.tscn` (NEW)
- `scripts/systems/detection_system.gd`
- Any files in `assets/` prefixed with `terminal_`

**Reads (don't modify):**
- `OpState.discovered_hosts`, `OpState.connected_host_id`, `OpState.found_credentials`
- `OpState.add_detection()`, `OpState.add_credential()`, `OpState.exfiltrate_file()`
- Campaign data: `GameState.get_current_operation().blacksite_target.network`

**Delivers:** Command-line terminal UI, host scanning, credential login, file browsing, file download with detection cost, netmap ASCII display.

**Key signals to emit:**
- `EventBus.terminal_command` — every command (detection_system listens for XP)
- `EventBus.file_exfiltrated` — via OpState.exfiltrate_file()
- `EventBus.handler_speak` — handler commentary on actions

### Lane 4: Social Engineering
**Owner files:**
- `scripts/ui/social_eng_ui.gd` (NEW)
- `scenes/social_eng.tscn` (NEW)
- Any files in `assets/` prefixed with `social_`

**Reads (don't modify):**
- `OpState.employee_states`
- Campaign data: `GameState.get_current_operation().blacksite_target.employees`

**Delivers:** NPC chat modal, trust/suspicion bars, keyword-based dialogue responses, secret reveals, personality-driven speech patterns.

**Key signals to emit:**
- `EventBus.handler_speak` — handler hints about social engineering
- Detection events via `OpState.add_detection("se_suspicious")` or `("se_failed")`

### Lane 5: Polish & VFX
**Owner files:**
- `assets/shaders/*.gdshader`
- `assets/themes/*.tres`
- `scripts/ui/juice.gd`
- `scripts/ui/crt_overlay.gd`
- `scripts/ui/hud.gd` (visual tweaks only — don't change signal connections)

**Delivers:** Tuned CRT shader, refined dark theme, screen flash on detection changes, ambient effects, sound stubs.

## Shared Interfaces

### EventBus Signals (complete list)
```gdscript
# Map
signal blip_clicked(blip_id: String)
signal blip_classified(blip_id: String, classification: String)
signal blip_spawned(blip_id: String)

# Decisions
signal coa_requested(blip_id: String)
signal coa_selected(blip_id: String, coa_id: String)

# Assets
signal asset_assigned(asset_id: String, blip_id: String)
signal asset_arrived(asset_id: String, blip_id: String)
signal asset_returned(asset_id: String)

# Missions
signal mission_started(blip_id: String, coa_id: String, asset_id: String)
signal mission_complication(blip_id: String, complication: Dictionary)
signal mission_resolved(blip_id: String, result: Dictionary)

# Detection
signal detection_changed(level: String, value: float)
signal analyst_burned()

# Handler voice
signal handler_speak(text: String, priority: String)
signal handler_subtitle(text: String)

# Progression
signal budget_changed(new_budget: int)
signal asset_unlocked(asset_id: String)
signal campaign_phase_changed(phase: String)

# Game state
signal game_loaded()
signal mission_complete(grade: String)

# Campaign & skills (Lane 1 added)
signal campaign_loaded(campaign_id: String)
signal xp_gained(skill_type: String, amount: int)
signal skill_leveled_up(skill_type: String, new_level: int)
signal phase_changed(new_phase: String)

# Terminal (Lane 3)
signal terminal_command(command: String, args: Array)
signal file_exfiltrated(file_id: String)

# Evidence board (Lane 2)
signal evidence_connection_made(from_id: String, to_id: String, conn_type: String)
signal evidence_pinned(evidence_id: String)
signal prep_score_updated(score: float)

# Social engineering (Lane 4)
signal se_trust_changed(employee_id: String, new_trust: int)
signal se_secret_revealed(employee_id: String, secret: String)
```

### Phase Flow
```
main_controller manages phase:
  "briefing"   → show BriefingOverlay, hide everything else
  "signal"     → show EvidenceBoard + TacticalMap, hide terminal
  "blacksite"  → show TerminalPanel + SocialEngPanel, dim tactical map
  "debrief"    → show DebriefOverlay with grade + XP summary

Transitions:
  briefing  → signal:    player clicks "BEGIN ANALYSIS"
  signal    → blacksite: player clicks "GO DARK" (prep score shown)
  blacksite → debrief:   all required files exfiltrated OR analyst burned
  debrief   → (next op or campaign end)
```

### Data Shapes (from test_campaign.json)
- **Evidence item:** `{ id, evidence_type, title, content, source, tags, is_clue, clue_target_ids }`
- **Employee:** `{ id, name, role, personality_traits, speech_pattern, knowledge_set, vulnerabilities, trust_threshold, secrets }`
- **Host:** `{ id, hostname, ip, services[], files[], credentials[], requires_credentials }`
- **Vulnerability chain:** `{ id, name, steps[] }` where each step has `{ action, requires[], reveals[] }`

## Merge Order
1. **Lane 1** (Core Loop) — establishes phase machine, signals, autoloads
2. **Lane 2** (Evidence Board) — plugs into SIGNAL phase
3. **Lane 3** (Terminal) — plugs into BLACKSITE phase
4. **Lane 4** (Social Engineering) — plugs into BLACKSITE phase
5. **Lane 5** (Polish) — final visual pass

Lanes 2-4 can merge in any order after Lane 1. Lane 5 goes last.

## Rules
- **Never modify a file you don't own** without coordinating first
- **New EventBus signals** — add them to event_bus.gd AND update this spec
- **New autoloads** — must go through Lane 1 (they modify project.godot)
- **Test after every change** — run Godot, verify no errors in Output panel
- **Commit per feature** — small, atomic commits. Branch per lane.
