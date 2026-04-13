# SIGNAL Playtest Report — First Visual Review via MCP Debug Server
**Date:** 2026-04-12
**Resolution:** 3440x1417 (ultrawide, stretched from 1920x1080)

## Screenshot Analysis

### CRITICAL Issues (Game-Breaking)
1. **Everything is nearly invisible** — The entire game is almost black. Blips, grid, terrain, sidebar entries are all barely visible. The brightness/contrast is tuned for a calibrated monitor in a dark room, not a real play environment.
2. **Click input doesn't register through debug server** — `Input.parse_input_event` doesn't work with stretch mode. Fixed to use `get_viewport().push_input()`. Need to verify.
3. **Viewport coordinate mismatch** — Blip screen coordinates are map-local, not viewport-global. Need offset for the sidebar (220px). Fixed in debug server.

### MAJOR Issues (Unplayable)
4. **Blips are too small for ultrawide** — 28px radius at 1920x1080 looks okay, but stretched to 3440 pixels the blips are tiny. Need to scale with actual viewport or use bigger base radius.
5. **Terrain shader is too dark** — The procedural terrain noise is using colors in the 0.02-0.065 range. On a real monitor these all look the same: black. Need to brighten the palette significantly (0.05-0.15 range).
6. **Grid lines invisible** — Grid colors at 0.045-0.06 are below visible threshold on most monitors. Need 0.08-0.12 minimum.
7. **Sidebar text microscopic** — On 3440px width, the 220px sidebar with 12px font is unreadable. Need wider sidebar (280px+) or bigger fonts.
8. **HUD top bar too thin** — 38px at 1920 → ~27px visual at 3440 stretch. Codename and budget labels are nearly invisible.
9. **No visual distinction between map area and void** — The map background and the area outside the map (behind sidebar, below timeline) are the same black. No borders, no visual separation.

### MODERATE Issues (Bad UX)
10. **Onboarding "CLICK TO IDENTIFY" text too small** — 13px font with 0.5 alpha on black background = invisible.
11. **Radar sweep invisible** — 0.08 alpha green lines on near-black background. Can't see it.
12. **Threat zones invisible** — 0.06 alpha red fills. Below visible threshold.
13. **Sensor fan arcs invisible** — 0.04 alpha blue fills. Way too transparent.
14. **Base marker invisible** — Diamond at 0.3-0.4 alpha green on black.
15. **Timeline bar shows "NO ACTIVE MISSIONS" but it's unreadable** — 10px font, 0.25 alpha.
16. **Subtitle bar positioned off-screen on ultrawide** — Centered at 50% of 1920 but the game area starts at 220px.

### MINOR Issues (Polish)
17. **COACards visibility = false** — They should be visible=true but empty, not hidden entirely. Otherwise they can't receive size updates.
18. **Objective counter says "TARGETS: 0/1"** — Should be 0/3 or whatever the actual total is. Counter seems wrong.
19. **Phase is "briefing"** even though targets are on screen — The phase state machine may be stuck.

## Root Cause Analysis

**The #1 problem is BRIGHTNESS.** Every single color value in the game is too dark by a factor of 2-3x. The design was done by imagining a Palantir-style dark UI, but Palantir's "dark" is much brighter than what we have. Palantir uses:
- Background: ~#0d1117 (RGB: 13, 17, 23) 
- Grid/borders: ~#1e2636 (RGB: 30, 38, 54)
- Text: ~#c0c8d4 (RGB: 192, 200, 212)
- Accent colors: Full saturation (not 0.3 alpha)

We're using:
- Background: #050813 (RGB: 5, 8, 19) — TOO DARK
- Grid: #0a0e1a (RGB: 10, 14, 26) — INVISIBLE
- Blips: Correct hue but too low alpha
- Everything has excessive transparency

**Fix: Double or triple all brightness values. Remove most transparency below 0.3.**

## Action Plan
1. Brighten terrain shader palette 2-3x
2. Brighten grid lines 2x
3. Brighten blip colors and increase alpha to 1.0 for rings
4. Increase blip radius to 36px (for ultrawide)
5. Brighten sidebar background and increase font size
6. Brighten HUD bar
7. Make all threat zones, sensor arcs, range rings at least 0.15 alpha
8. Fix coordinate mapping in debug server
9. Fix phase state machine
10. Increase all text sizes by 2px minimum
