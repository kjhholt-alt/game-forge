# Saga Engine — Phase 1 Content Pipeline Spec

**Status:** ACTIVE — Kruz picked the theme 2026-07-05: **#1 "Second Rome" —
Imperial Restoration Saga** (`THEME_SHORTLIST.md`) and gave the go ("Lets do
... second rome for CK3"). Phase 2 mass generation is unblocked; first batch
= the setup stage, per the batch sizing below.

## Mission

Turn "the fleet is good at writing" into DLC-scale CK3 flavor content, gated
by a deterministic validator instead of vibes. Phase 0 (`SCOUT.md`) proved
the toolchain works end to end on a real hello-world mod. This spec defines
the repeatable pipeline for producing real saga content on top of it.

## Pipeline

```
 GENERATE  ──▶  VALIDATE  ──▶  LOCALIZE-AUDIT  ──▶  PLAYTEST
 (agent)        (ck3-tiger,     (coverage + tone      (visible window,
                 headless,      check, still           Kruz-gated,
                 loop-until-     headless)              periodic not
                 clean)                                 per-batch)
```

### 1. Generate

One saga = one `story_cycle` (see `SCOUT.md` for why story_cycles are the
right primitive) + its full event chain + matching localization, produced
together in a single agent pass per content batch (a "stage" of the saga —
setup, 2-3 escalation stages, ending fork — not the whole 20 events in one
shot; smaller batches make the validate-loop below cheap to re-run).

Each generation prompt must include:
- The saga's reserved namespace + ID block (see Style Bible below)
- 1-2 real vanilla story_cycle files as few-shot reference (already have
  `ep3_story_cycle_el_cid.txt` read and excerpted in `SCOUT.md`)
- The chosen theme's hook/mechanical-shape from `THEME_SHORTLIST.md`
- The Style Bible (below), verbatim
- An explicit instruction to emit **both** the script file(s) and the
  matching `l_english.yml` in the same turn — never script without loc

Output lands directly under `ck3_saga_engine/mod/saga_engine/` (git-tracked
source), not the live CK3 mod folder.

### 2. Validate (the gate)

Immediately after each generation batch:

```
py tools/deploy.py       # sync git source -> live CK3 mod folder
py tools/validate.py     # ck3-tiger gate; exit 0 = clean, exit 1 = blocking issues
```

If `validate.py` exits non-zero: feed its exact stderr output (file, line,
message — it already reports in that shape) back to the generating agent as
a fix-it turn. Loop until clean or **3 attempts**, whichever comes first; if
still failing after 3, stop and flag for Kruz rather than guessing further
(same two-attempt-plus-one discipline as the rest of this codebase's
debugging rule).

`warning`/`untidy`/`tips` severities do not block the loop but should be
looked at before calling a batch done — they're often real (e.g. the UTF-8
BOM warning caught a real encoding bug during Phase 0 testing).

### 3. Localize-audit

Because generation already emits loc alongside script, this stage is an
audit, not a translation pass:
- Re-run `validate.py` — tiger's missing-localization check is authoritative
  for *coverage* (every `title =`/`desc =`/option `name =` key referenced
  has a matching yml entry).
- Manual/spot-check pass for *tone*: does the text match vanilla's register
  (grounded medieval voice, no anachronism, no modern idiom)? This is a
  judgment call tiger can't make — do it as part of generation review, not
  as a separate agent stage, to avoid burning an extra full pass per batch.

### 4. Scripted-save playtest

CK3 has no headless test-harness / scripted-input-replay mode (confirmed in
Phase 0 — the closest thing is launching the real game with `-debug_mode`
and using the console `event <id>` command to force-trigger content
out of its natural trigger conditions, then reading `logs/error.log` for
anything new). That means this stage:
- **Opens a visible game window.** Per this machine's standing rules (no
  visible windows while gaming; game-mode = zero fleet lanes), this step is
  NOT something the pipeline triggers automatically mid-batch.
- Runs **periodically** (once a saga's full arc is validator-clean, not
  after every micro-batch) and either by Kruz directly, or by an agent only
  during an explicitly safe/away window with Kruz's standing go-ahead —
  same posture rules that gate every other visible-window action on this
  machine.
- Procedure: enable the mod on a real or dedicated debug save → `debug_mode`
  console → `event <namespace.id>` for each new event in chain order →
  visually confirm portraits/text/options/effects → diff `error.log`
  against its pre-playtest state for anything new (watch especially for
  "orphaned event" — means a wiring gap in the story_cycle's effect_groups,
  not a tiger-catchable issue).

## Style Bible

- **Namespace per saga**, ID block reserved up front to avoid collisions
  across sagas sharing one mod (e.g. saga #1 gets `saga_<name>.1000-1999`).
  The existing hello-world used bare `saga.1` — fine as a throwaway proof,
  but real sagas need their own namespace so multiple sagas can coexist in
  one mod without ID clashes.
- **Encoding:** UTF-8 with BOM, no exceptions — every `.txt` and `.yml` file.
  Verified gotcha from Phase 0; tiger catches it as a warning but it's worth
  getting right at generation time rather than patching after.
- **File layout** mirrors vanilla: `events/<saga>_events.txt`,
  `common/story_cycles/<saga>_story_cycle.txt`,
  `localization/english/<saga>_l_english.yml` — one loc file per script file,
  same basename, matching existing convention in both vanilla and the
  hello-world seed.
- **Voice:** grounded medieval register, 2-4 sentence event `desc`, option
  labels are a single short imperative or reactive line (see vanilla
  examples and the hello-world `saga.1` event for length calibration — do
  not write paragraphs).
- **Reachability:** every event must be wired into the saga's story_cycle
  `effect_group`s (or an `on_action`/decision entry point for the saga's
  start). No orphaned events — check both tiger's `--unused` flag output and
  the game's own boot-time orphan warning during playtest.
- **References must resolve:** `theme=`, portrait `animation=`, trait, and
  gfx references must be real vanilla (or DLC-owned, if Kruz's install has
  it) identifiers — tiger's missing-item check is authoritative here, but
  writing against the vanilla corpus already skimmed in `SCOUT.md` avoids
  most of these round-trips.

## Repo layout

```
game-forge/ck3_saga_engine/
  docs/
    SCOUT.md              Phase 0 findings (this pass)
    THEME_SHORTLIST.md     5 themes, awaiting Kruz's pick
    SPEC.md                 this file
  mod/
    saga_engine.mod        outer descriptor (git-tracked source of truth)
    saga_engine/            content folder (git-tracked source of truth)
  tools/
    deploy.py                git source -> live CK3 mod folder
    validate.py               ck3-tiger gate, parses --json, exits non-zero on fatal/error
```

The live CK3 mod folder
(`~\Documents\Paradox Interactive\Crusader Kings III\mod\saga_engine\`) is a
**deploy target**, not source — always edit under `ck3_saga_engine/mod/` and
run `deploy.py`, never hand-edit the Documents copy directly, or git and the
live game will drift.

## Open decision (blocks Phase 2)

Kruz picks one theme from `THEME_SHORTLIST.md`. Once picked:
1. Reserve that saga's namespace + ID block in this doc.
2. Generate the saga's `story_cycle` skeleton + stage-1 events as the first
   batch through the pipeline above.
3. Phase 2's proof bar (from the dispatch): "one 20-event saga chain
   validator-clean in a live campaign" — the "in a live campaign" part is
   the playtest stage above, and per the posture rules it's the one part of
   this that isn't fully autonomous by design.

## Explicit non-goals for this pass (gl-0084 Phase 0/1)

- No saga content was generated tonight beyond the pre-existing hello-world
  seed (which was Kruz's own manual proof-of-concept, just migrated into
  git).
- No theme was picked — that's explicitly Kruz's call per the dispatch.
- The game was not launched by this session. All validation tonight used the
  fully headless `ck3-tiger` path; the visible-window playtest step was
  exercised by Kruz himself earlier tonight, not re-run here.
