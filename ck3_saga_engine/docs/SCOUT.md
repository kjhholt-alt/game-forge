# Saga Engine — Phase 0 Toolchain Scout

**Date:** 2026-07-05
**Scope:** gl-0084 Phase 0 — understand the CK3 modding toolchain well enough
to build a real generate → validate → localize → playtest pipeline on top of
it. No mass content generation happens in this pass.

## Environment ground truth (this machine)

| Thing | Value |
|---|---|
| CK3 install | `A:\Steam\steamapps\common\Crusader Kings III` (Steam AppID `1158310`) |
| Game version | `1.19.0.6` ("Scribe") |
| CK3 user-data dir | `C:\Users\Kruz\Documents\Paradox Interactive\Crusader Kings III\` |
| Live mod folder | `...\Crusader Kings III\mod\` (this is what the game reads — NOT under git) |
| Mod enabled via | `dlc_load.json` → `"enabled_mods": ["mod/saga_engine.mod"]` |
| Error/debug logs | `...\Crusader Kings III\logs\error.log`, `debug.log` |
| ck3-tiger validator | installed at `C:\Users\Kruz\.operator\bin\ck3-tiger\ck3-tiger.exe` (v1.19.0, exact match for game 1.19.0.6) |

Kruz already hand-built a hello-world proof tonight (~1am) before dispatching
this item: a one-event test mod named "Saga Engine," launched the real game
with it enabled, and confirmed it loaded. That mod is now the seed of the
git-tracked source at `ck3_saga_engine/mod/saga_engine/` (copied in, not
reinvented) — see "Existing proof-of-concept" below.

## Mod anatomy

A CK3 mod is two things:
1. An outer descriptor `mod/<name>.mod` in the user-data mod folder — this is
   what the launcher and `dlc_load.json` reference. Has `path=` pointing at
   the content folder.
2. A content folder `mod/<name>/` containing script (Paradox's own
   whitespace-delimited `key = value` / `key = { ... }` format) and
   localization.

```
mod/
  saga_engine.mod                        <- outer descriptor, path="mod/saga_engine"
  saga_engine/
    descriptor.mod                       <- same content, some tools read this copy instead
    events/*.txt                         <- character_event / story-relevant events
    localization/english/*.yml           <- one loc file per event/decision file, same basename convention
    common/decisions/*.txt               <- player-invoked decisions
    common/on_action/*.txt               <- hooks that fire events on game triggers (birthdays, deaths, etc.)
    common/story_cycles/*.txt            <- see below, this IS the saga-chain primitive
    thumbnail.png                        <- referenced by picture= in the .mod file
```

**Hard gotcha (verified by test):** every script and localization file MUST
be UTF-8 **with BOM**. A file written without a BOM passes fine at the OS
level but ck3-tiger flags `warning(encoding): Expected UTF-8 BOM encoding`.
Kruz's existing files are correctly BOM-prefixed (`\xef\xbb\xbf`) — confirmed
by reading the raw bytes. Any pipeline that emits files (agent-written or
otherwise) must write UTF-8-BOM, not plain UTF-8.

## Event syntax (current, 1.19)

```
namespace = saga

saga.1 = {
    type = character_event
    title = saga.1.t
    desc = saga.1.desc
    theme = intrigue
    left_portrait = { character = root  animation = personality_cynical }

    immediate = { }        # effects that always run on fire
    trigger = { }           # (omitted here) gates whether it CAN fire
    option = {
        name = saga.1.a
        add_prestige = minor_prestige_gain
    }
    option = {
        name = saga.1.b
        add_piety = minor_piety_gain
    }
}
```

- IDs are `namespace.number`; loc keys are `namespace.number.t` (title),
  `.desc`, `.a`/`.b`/... (option labels). This convention is load-bearing —
  ck3-tiger and the game both expect it.
- `theme` must reference a real `common/event_themes` entry (controls the
  background art/music sting). `left_portrait.animation` must be a real
  portrait animation.
- An event with no trigger to fire it is only reachable via
  `trigger_event = saga.1` from a decision, on_action, or story_cycle. If
  nothing calls it, the game itself logs it as **orphaned** at boot
  (`jomini_eventmanager.cpp: Event saga.1 is orphaned`) — confirmed in
  tonight's error.log. This is a **warning, not a failure**, but every real
  saga event needs a wiring path or it'll show up as orphaned forever.

## The saga-chain primitive: `common/story_cycles`

This is the single most important discovery of the scout. CK3 already ships
a first-class system for exactly what gl-0084 wants — a multi-event narrative
arc with state, branching endings, and a defined lifecycle. It is NOT
something we need to invent on top of raw events.

Read in full: `game/common/story_cycles/ep3_story_cycle_el_cid.txt` (The
Song of El Cid — a companion/rival saga with a loyalty tug-of-war counter and
three distinct endings). Structure:

```
story_<name> = {
    visible = yes
    icon = { reference = "gfx/..." }
    background = { reference = "gfx/..." }
    visualization = {
        character = { variable_name = "..."  label = "..." }
        tug_of_war_counter = { variable_name = "..."  min = -5  max = 5  ... }
    }
    on_setup = { ... }        # runs when the story starts
    on_end = { ... }          # cleanup — remove_variable everything you set
    on_owner_death = { end_story = yes }

    effect_group = {
        months = 1              # or months = { 6 12 } for a random range
        chance = 100
        first_valid = {          # or random_valid
            triggered_effect = {
                trigger = { ... }
                effect = { trigger_event = ... }
            }
            ...
        }
    }
}
```

`effect_group` blocks are the heartbeat — they tick on an interval and fire
the first (or a random) matching branch, each branch usually calling
`trigger_event` to advance the narrative. A "20-event saga chain" is
naturally: 1 story_cycle definition + ~20 events wired to it across several
`effect_group` stages, with an ending fork at the end (like El Cid's 3
endings). This maps cleanly onto "generate N events + wire them into a
story_cycle skeleton" as a repeatable content-batch shape.

Vanilla has ~20+ existing story_cycles to mine for patterns
(`book_translation_story_cycle.txt`, `bp2_child_of_destiny_story_cycle.txt`,
`ep3_story_cycle_grand_ambitions.txt`, etc.) — good reference corpus for the
style bible and for few-shot examples in generation prompts.

## Decisions and on_actions (the other two entry points)

- `common/decisions/*.txt` — player-invoked, gated by `is_shown` /
  `is_valid`, run `effect` on confirm. Good for saga *starts* ("begin the
  saga") rather than the saga body itself.
- `common/on_action/*.txt` — hooks tied to game events (birthdays, deaths,
  wars ending, etc.) via `on_actions = { ... }` lists, sometimes gated by a
  local `trigger`. This is how vanilla wires story_cycles' `trigger_event =
  { on_action = ... }` calls, and how a saga could auto-start for eligible
  characters instead of needing a manual decision.

## The validator: ck3-tiger

[amtep/tiger](https://github.com/amtep/tiger) — open-source (Rust), the de
facto community standard for CK3/Vic3/Imperator script validation. Not made
by Paradox; no official in-game or CLI validator exists otherwise. Checks:
syntax, unknown fields/tokens, missing referenced items (traits, triggers,
gfx, etc.), missing localization, scope consistency, and CK3-specific
history sanity (no one is their own grandfather).

- Installed to `C:\Users\Kruz\.operator\bin\ck3-tiger\` (matches the
  `~/.operator/bin` convention already used for other standalone tools on
  this machine).
- Version v1.19.0 downloaded from the GitHub release, confirmed via `gh
  release view` — exact match for the installed game (1.19.0.6). Re-check
  `github.com/amtep/tiger/releases` after any CK3 patch; tiger tracks game
  versions closely and mismatches are reported (but non-fatal) at startup.
- Command: `ck3-tiger.exe --json --game "<CK3 install root>" "<path to
  .mod file>"`. Point `--game` at the CK3 install **root**, not the `game\`
  subfolder — pointing at `game\` works but prints a "does not look like a
  CK3 directory" fallback line before it self-corrects.
- **Exit code is always 0**, even with fatal errors present — confirmed by
  testing against a deliberately broken mod. Tiger is a *reporter*, not a
  gate. `--json` output (stdout, banner goes to stderr so they don't mix) is
  an array of report objects: `{severity, key, message, locations: [{path,
  linenr, ...}], ...}`. Anything gating a pipeline must parse this itself.
- `ck3-tiger.conf` in the mod root can scope which languages get checked and
  filter/suppress specific report categories.

### `tools/validate.py` (built + proven tonight)

Wraps the above: runs tiger `--json`, counts by severity, prints a summary,
and **exits non-zero if any `fatal` or `error` severity report exists**
(warnings/untidy/tips do not block). Verified against both:
- the real (clean) `saga_engine` mod → exit 0, "no problems found"
- a scratch mod with a deliberately invalid effect key → exit 1, correctly
  named the file, line, and message

This is the deterministic gate the project's "why" calls for.

## How the two validation layers fit together

1. **Static gate — `ck3-tiger` / `validate.py`.** Fully headless, no game
   window, seconds to run. Catches almost everything: bad syntax, unknown
   fields, missing loc, missing referenced game objects, missing BOM. This is
   the gate that should run after **every** generation batch, with no
   restriction on when — it never puts a window on screen.
2. **Runtime check — actually booting the game.** Catches the remaining
   category tiger can't: orphaned events (nothing wired to fire them), things
   that are syntactically valid but produce a genuinely-broken player
   experience, and general "does it actually still load" sanity. This
   **does** open a visible game window, so per this machine's standing rules
   (no visible windows while gaming, game-mode = zero fleet lanes) it is NOT
   something the pipeline should trigger autonomously mid-session — it's a
   Kruz-driven or posture-gated step, same as any other visible-window
   action. Kruz already did this manually for the seed mod tonight; the
   Phase 1 spec treats it as a scheduled/manual checkpoint, not a per-batch
   automatic step.

## How big community mods CI themselves

There's no official Paradox GitHub Action (copyright restrictions on
redistributing tiger inside one, per amtep's docs). The community pattern
(e.g. `kaiser-chris/tiger-action-public`) is: self-host the tiger binary,
wrap it in a GitHub Action, run on push/PR, fail the build on findings. Since
this project is explicitly private/local (never publishing — hard rail), we
don't need real GitHub Actions at all — the local equivalent is
`deploy.py` → `validate.py` run after every content batch, which is what's
built here.

## Existing proof-of-concept (verified, not hypothetical)

Kruz's hand-made test event (`saga.1`, "A Quiet Word") is now the seed of
`ck3_saga_engine/mod/saga_engine/` in git. Tonight, on top of the git-tracked
copy:
- `deploy.py` synced it to the live CK3 mod folder
- `validate.py` confirmed 0 fatal/error/warning findings
- (Separately, a deliberately broken scratch mod was created, validated as
  failing with the exact expected error, then deleted — proving the gate
  actually gates and not just always-passes.)

The full loop — generate → deploy → validate — is real and working today,
on real tooling, against the real installed game version. Nothing here is
aspirational.
