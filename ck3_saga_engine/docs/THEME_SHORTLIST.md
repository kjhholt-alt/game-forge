# Saga Engine — Theme Shortlist (pick one)

> **DECIDED 2026-07-05: Kruz picked #1 "Second Rome".** Kept for the record;
> the other four themes remain candidates for later sagas.

**For:** Kruz, morning-after review of gl-0084.
**Ask:** pick ONE of these 5 as the Phase 1/2 saga theme. Mass content
generation (Phase 2) does not start until you pick and the spec
(`SPEC.md`) gets your sign-off.

Each theme is scoped to be buildable on the primitives confirmed in
`SCOUT.md` (mainly `common/story_cycles`) — none of these need new game
systems invented from scratch. Grounded in your actual save history: a
Balkans rise-from-count campaign (Ban Ivan of Raska → "Ivan the Great of
Serbia") and a longer Roman-revival campaign (Julius Caesar II of Italy →
Karl II of Italy → **Imperator** Karl of Italia) — both classic "humble
start to legend" arcs, which is the emotional shape all 5 options lean into.

---

## 1. "Second Rome" — Imperial Restoration Saga

**Hook:** You're not just conquering — you're trying to convince history
(and your own court) that you're the legitimate heir to a fallen empire.
The saga tracks a rising "Restorer" reputation counter as you take
imperium-adjacent titles, and spawns a rival claimant story thread (a
pretender, a jealous patriarch/pope-equivalent, a foreign emperor who denies
your legitimacy) who actively works against your coronation.

**Why it fits:** direct match for the Karl of Italia → Imperator campaign
you already played to completion. This is the "did the thing, want it as a
richer story next time" theme.

**Mechanical shape:** `story_cycle` with a `tug_of_war_counter`
(legitimacy vs. a rival's counter-claim, El Cid-style), triggered when a
character holds an empire-tier title or a specific set of kingdoms; ends in
one of 3-4 forks (recognized restorer / hollow crown / rival wins / dynasty
schism).

**Scope:** ~18-22 events across setup → 3 escalation stages → ending fork.

---

## 2. "Blood and Oath" — Succession Crisis Saga

**Hook:** A universal, culture/religion-agnostic saga about whether your
dynasty survives you. Triggers when your heir situation gets dangerous
(contested succession law, multiple viable claimants, a scheming younger
sibling) and plays out as a slow-burn trust/betrayal arc among your own
children and court.

**Why it fits:** works in *any* campaign regardless of start — highest
replay surface of the 5, good if you want the saga to show up reliably
across many different games rather than one specific playstyle.

**Mechanical shape:** `story_cycle` anchored to `story_owner`'s heir(s),
loyalty tug-of-war per rival claimant, on_action hook off succession-law
changes and heir-coming-of-age; ends in stable succession / disinherit /
open war of succession.

**Scope:** ~20 events, most reusable across cultures (light
culture-flavored text variants, not full rewrites).

---

## 3. "The Wandering Legend" — Landless Adventurer Saga

**Hook:** An original-content sibling to vanilla's El Cid story — you (or a
disinherited/landless character) build a legendary-warband reputation from
nothing: hired blade → feared mercenary captain → kingmaker. Explicitly
patterned on the vanilla `ep3_story_cycle_el_cid.txt` mechanics (companion
loyalty counter, landless-specific effect_group branch) but wholly new
writing and a different narrative arc.

**Why it fits:** lowest technical risk — closest 1:1 mapping to a vanilla
system we already have full source for, so the fastest path to a real
20-event validator-clean chain (good pick if you want Phase 2's first
milestone to land fast and clean).

**Mechanical shape:** near-identical skeleton to El Cid's story_cycle
(`has_government = landless_adventurer_government` branch reused
conceptually), new companion character, new loyalty counter, new endings
(become a landed lord / die a legend / betray your own warband).

**Scope:** ~16-18 events — smallest of the 5, by design.

---

## 4. "Whispers of the Old Faith" — Secret Heresy Saga

**Hook:** A slow-burn temptation arc — a secret cult or heretical
sect offers your ruler forbidden power (a relic, a rite, a whispered
promise) in exchange for small compromises that compound. Leans on CK3's
existing secret-religion/faith-conversion flavor space but as a personal,
character-level story rather than a realm-wide mechanic.

**Why it fits:** the one "morally interesting" option of the 5 — best pick
if you want the saga to produce genuine dilemma moments rather than pure
power-fantasy escalation. Higher writing bar (needs restraint to land the
creepy tone without going full parody).

**Mechanical shape:** `story_cycle` gated behind a `secret` variable/effect,
escalating `effect_group` stages each asking for a bigger compromise,
discovery risk that scales over time; ends in mastery / exposure-and-ruin /
walking away (with a lasting scar/trait either way).

**Scope:** ~20 events, more branch-heavy than the others (discovery risk
means more failure-state content).

---

## 5. "The Long Memory" — Multi-Generation Dynasty Legacy Saga

**Hook:** Not one ruler's story — the *dynasty's*. A recurring family
trait (a blessing, a curse, a prophecy) resurfaces once per generation,
tracked via `dynasty_legacies`/house-level variables and the `memory_type`
system, so the "saga" is actually stitched across however many rulers you
play through one house.

**Why it fits:** most structurally ambitious — plays to the "year-long
platform, not a one-off" framing of the whole gl-0084 pitch, since it's
designed to keep paying off session after session rather than resolving in
one reign.

**Mechanical shape:** house-level variables (not story_cycle's
character-owner model) + `on_action` hooks on birth/heir-succession to
re-roll/re-trigger the family-memory event each generation; no single
"ending" — it's designed to recur.

**Scope:** hardest to scope as "20 events" cleanly since it's inherently
open-ended — pick this one only if you're OK with Phase 2's first milestone
being "one full generation's cycle" (~15 events) rather than a closed arc.

---

## Recommendation if you want a fast, low-risk Phase 2 win

**#3, The Wandering Legend** — closest to a proven vanilla pattern
(El Cid), smallest scope, lowest ambiguity about what "20-event chain,
validator-clean, in a live campaign" even means to prove. **#1, Second
Rome** is the best fit to your actual play history if you'd rather the
first saga be the one you'd personally want to trigger in your own game.
