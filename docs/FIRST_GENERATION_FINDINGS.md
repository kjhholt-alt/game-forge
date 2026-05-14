# First End-to-End Generation — Findings (2026-05-14)

## TL;DR

**Game-Forge now generates a complete 5-stage game project — concept →
world → mechanics → narrative → art → QA — end-to-end in ~4.5 minutes
via the Claude CLI. No Anthropic API key required.** Smoke harnesses
live at:

- `scripts/smoke_first_generation.py` — concept stage only (~30s)
- `scripts/smoke_full_pipeline.py` — full 5-stage pipeline (~4.5 min)

This is the first time the agent pipeline has been *actually run* with
real model calls since the v0.1 foundation landed (2026-04-12).

**Live smoke result (2026-05-14):**
  - title: "Wickwater"
  - world: sunken ossuary beneath a drowned coastal monastery
  - 12 items, 6 quests, 5 NPCs, full style guide
  - QA agent found 12 design issues including specific bugs
    ("quest_unfinished_compline is currently uncompletable as wired")
  - elapsed: 278s, total cost ~$1.50 (Opus 4.7, 1M context, mixed
    cache-creation + cache-read tokens)

## What didn't work — and why

The Director was designed against `_client.messages.create()` with an
Anthropic-shape multi-turn message envelope (`system` + `user` blocks).
The `claudex_anthropic_shim` flattened these into a single text prompt
with `<system>` / `<user>` / `<assistant>` XML tags and piped to
`claude -p`.

In practice, `claude -p` running inside a project directory with a
populated `CLAUDE.md`:

- **Treats the entire prompt as a conversational opener.** Even with the
  XML tags telling it "you are a senior game designer," the CLI loaded
  game-forge's CLAUDE.md, saw a vaguely-formatted request, and replied
  with `"I'm ready to help with GameForge work. What would you like to
  tackle?"` — losing the actual instruction in the haze of project
  context.
- **Doesn't honor schema requests via prose.** Even when the user
  message explicitly said `"Respond with a JSON object matching this
  schema: ..."`, the CLI's helpful-assistant mode took over and
  produced prose acknowledgments instead of JSON.
- **`--bare` mode unlocks clean context but kills Max-sub auth.** Tested
  `claude --bare`: removes CLAUDE.md auto-discovery (good), but disables
  OAuth/keychain reads, so it demands `ANTHROPIC_API_KEY`. Wrong
  tradeoff for our setup.

## What worked

The Claude CLI's **`--output-format json` + `--json-schema` flags**.
This forces the model into structured-output mode regardless of what
the project context wants to discuss. The returned envelope has a
`structured_output` field with the validated, schema-matching JSON
already extracted — no markdown-fence stripping required.

```bash
claude -p \
  --output-format json \
  --json-schema "$SCHEMA_JSON" \
  --append-system-prompt "$SYS" \
  < "$PROMPT_TEXT"
```

Returns:
```json
{
  "type": "result",
  "subtype": "success",
  "result": "<human-readable summary>",
  "structured_output": { ... schema-matching JSON ... },
  "usage": { ... },
  "modelUsage": { ... }
}
```

## The fix shipped

1. **`claudex.ask_structured(prompt, schema, *, system_prompt=...)`**
   in `claudex.py`. Calls `claude -p --output-format json --json-schema`
   with the prompt fed via stdin (avoids Windows command-line length
   limits when the schema is ~1KB+). Caches by SHA-256 of
   `(prompt + schema + system_prompt)` in `.claudex_cache/*.json`.

2. **`GameDirector._call_structured(schema_cls, system, user_message)`**
   in `orchestrator/director.py`. Async wrapper that takes a Pydantic
   model class, runs `ask_structured` in a thread, and returns the
   validated Pydantic instance. Bypasses the Anthropic-shape shim
   entirely.

3. **`_generate_concept` rewritten** to use `_call_structured` directly,
   with a cleaner prompt that omits the embedded schema dump (the
   `--json-schema` flag carries the schema). Other stages
   (`_build_world`, `_design_mechanics`, `_write_narrative`,
   `_direct_art`, `_run_qa`) still use the old `_call_claude` path — they
   need the same migration but each is more complex (multi-input,
   QA-iteration loop) and was deferred to a follow-up sprint.

## Smoke results

```
[  OK] import             0.42s
[  OK] director_init      0.00s
[  OK] concept           29.67s

title:    The Hollow Beneath Vellsmere
setting:  A single sunken chapel-dungeon under a flooded monastery...
mood:     Contemplative and faintly melancholic
mechanics: Lantern Moths (drift toward sound), Stone Wardens (puzzle
           guardians), Hollow Choristers (mirror your last three moves)...
art:      32x32 hand-pixeled, muted dusk palette
```

Pydantic `GameConcept.model_validate(...)` passes cleanly.

Cost per call (Opus 4.7, 1M context, ~30k cache-creation input tokens
on the first invocation): ~$0.26. With caching warm and at standard
8192-token context: $0.05-0.10. Full 5-stage generation should land in
the $0.50-1.50 range per game.

## Update 2 — 2026-05-14 (deeper): `--json-schema` is post-validation only

Initial assumption: `claude -p --output-format json --json-schema <schema>`
constrains generation. **Wrong.** Empirical findings after migrating
all 5 stages:

- `--json-schema` validates the model's output against the schema and
  populates `envelope.structured_output` only if validation passes.
  It does **not** influence what the model produces.
- Without the schema in the prompt, the model invents shape freely.
  WorldDefinition (which has nested `overworld.regions[].rooms[]`)
  came back as `{"world": {...}, "landmarks": [...]}` — totally
  different from the Pydantic schema.
- Anthropic's structured-output validator is **stricter than Pydantic**.
  We saw cases where the model produced a JSON object that
  `WorldDefinition.model_validate(...)` accepts cleanly, but
  `structured_output` was still null. Likely cause: missing
  `additionalProperties: false` somewhere in the tree, or strict
  enforcement of JSON Schema features Pydantic emits leniently.
- The schema also has to fit on the Windows command line (~32K).
  At 6.6KB inlined for WorldDefinition, headroom shrinks fast and
  the `_NarrativeBundle` schema at ~7KB pushes too close to the
  limit.

**Final approach** (locked in master 5fae0d8 + follow-up):

1. Embed the inlined schema in the user prompt — this drives shape.
2. Drop `--json-schema` from the CLI args — it's not helping and it
   blows the cmdline limit.
3. Parse JSON out of the prose `result` field of the envelope.
4. Caller's `Schema.model_validate(...)` is the real gate.

`ask_structured()` now reads the docstring "schema-validated call"
loosely: the CLI is doing best-effort, Pydantic is doing the actual
validation. That's fine — Pydantic is what we ultimately care about.

## Update — 2026-05-14 (later same sprint): all 5 stages migrated

All five director stages now route through `_call_structured`:

- `_generate_concept` → `GameConcept`
- `_build_world` → `WorldDefinition`
- `_design_mechanics` → `_ItemsBundle` (private wrapper) → `list[ItemDefinition]`
- `_write_narrative` → `_NarrativeBundle` → `(list[Quest], list[NPCDefinition])`
- `_direct_art` → `StyleGuide`
- `_run_qa` → `QAReport`

Two private Pydantic wrappers (`_ItemsBundle`, `_NarrativeBundle`) were
needed because the CLI's `--json-schema` flag operates on a single root
object, but mechanics returns a list and narrative returns two lists.
The wrappers give us a stable root shape that the CLI can validate.

Test layer also migrated. The two `TestCreateGamePipeline` tests
previously mocked `_client.messages.create` (the Anthropic shim).
Now they mock `claudex.ask_structured` with a sequence of 6 stage
responses. 9/9 director tests pass.

`scripts/smoke_full_pipeline.py` runs the entire 5-stage pipeline
end-to-end via `GameForge.create()`. See the report file for results.

## What's next (still NOT done)

1. **Asset pipeline smoke.** Replicate FLUX integration for sprite
   generation is wired but never run end-to-end. Token is in
   `pool-prospector/.env.local` — copy into `game-forge/.env`.

2. **Godot export E2E.** After a project is created, `forge export
   <path>` instantiates the Godot template, writes scripts, and
   wires up the MCP server. Smoke that against a fresh `tmp/` dir.

3. **Streaming.** `claude -p` supports `--output-format stream-json`
   for incremental output. Useful for the rich.Progress UI in
   `forge create` so users see stages arriving sequentially.

4. **CLI bin wrapper / install script.** `forge create` works but
   `forge.bat` / `pip install -e .` flow needs documenting.

5. **`iterate()` migration.** Same pattern — `_iterate_on_qa` still
   uses `_call_claude` via `_dispatch_worker`. Lower priority since
   `create()` is the demo path.

## Files touched this sprint

- `claudex.py` — added `ask_structured()` + `_cache_path` suffix arg
- `orchestrator/director.py` — added `_call_structured()` +
  rewrote `_generate_concept`
- `scripts/smoke_first_generation.py` — new harness, reproducible
- `docs/FIRST_GENERATION_FINDINGS.md` — this doc

Tests on the old `_call_claude` path still pass (mocks bypass the
shim entirely). New `_call_structured` path is exercised only by the
smoke for now; a unit test that mocks `claudex.ask_structured` is the
obvious next add.
