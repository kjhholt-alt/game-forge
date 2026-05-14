# First End-to-End Generation — Findings (2026-05-14)

## TL;DR

**Game-Forge can now generate a Pydantic-validated `GameConcept` end-to-end
in 30s via the Claude CLI, no Anthropic API key required.** Smoke harness
lives at `scripts/smoke_first_generation.py`. The Director's
`_generate_concept` stage uses the new `_call_structured()` helper.

This is the first time the agent pipeline has been *actually run* with
real model calls since the v0.1 foundation landed (2026-04-12). The
previous attempt failed: see below.

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

## What's next (NOT done in this sprint)

The path forward is clear; everything below is straightforward port
work, no more architectural unknowns:

1. **Migrate the other 4 stages** to `_call_structured`:
   - `_build_world` → `WorldDefinition`
   - `_design_mechanics` → `(ItemDefinition[], dict)` (compound; needs
     two stages or a wrapper Pydantic model)
   - `_write_narrative` → `(Quest[], NPCDefinition[])`
   - `_direct_art` → `StyleGuide`
   - `_run_qa` → `QAReport`

2. **`_dispatch_worker` migration.** Most stages already go through
   `_dispatch_worker(role, task, response_schema)` which then calls
   `_call_claude`. Punching `ask_structured` through to that level
   would migrate everything at once.

3. **Full `forge create` E2E.** Once all stages are on
   `ask_structured`, a full 5-agent run should land in 3-5 minutes
   wall-clock. Demo target: video of `forge create "<prompt>"` →
   playable Godot project in under 10 min.

4. **Asset pipeline smoke.** Replicate FLUX integration for sprite
   generation is wired but never run end-to-end. Token is in
   `pool-prospector/.env.local` — copy into `game-forge/.env`.

5. **Streaming.** `claude -p` supports `--output-format stream-json`
   for incremental output. Useful for the rich.Progress UI in
   `forge create` so users see concept → world → mechanics → narrative
   arrive sequentially instead of staring at a spinner for 3 min.

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
