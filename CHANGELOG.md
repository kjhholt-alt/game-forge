# CHANGELOG

All notable changes to GameForge will be documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org).

## [Unreleased]

## [0.1.1] — 2026-05-14

This is the first release where the 5-agent pipeline actually runs
end-to-end. Previous v0.1.0 had the foundation in place but the
Director's prompts were incompatible with the claudex shim — the
Claude CLI was loading project context and replying conversationally
instead of producing schema-matching JSON.

### Added
- `claudex.ask_structured(prompt, schema, *, system_prompt=...)` —
  schema-validated CLI calls. Inlines `$defs/$ref` (Anthropic's
  validator rejects refs), embeds schema in prompt to drive shape,
  pipes stdin to dodge Windows cmdline limits, parses prose `result`
  field, returns dict for Pydantic validation at the call site.
- `GameDirector._call_structured(schema_cls, system, user_message)` —
  async wrapper that returns validated Pydantic instances. All 5
  director stages migrated to this path.
- `_ItemsBundle` + `_NarrativeBundle` private Pydantic wrappers
  in `orchestrator/director.py` — handle compound-shape stage
  responses (mechanics returns list, narrative returns two lists)
  by giving the CLI a stable single-root shape to validate.
- `scripts/smoke_first_generation.py` — concept-stage smoke
  (~30s).
- `scripts/smoke_full_pipeline.py` — full 5-stage pipeline + export
  smoke (~4.5-8 min depending on genre).
- `scripts/smoke_full_pipeline_puzzle.py` — second-genre smoke
  (puzzle).
- `scripts/smoke_full_pipeline_rpg.py` — third-genre smoke (RPG).
- `scripts/dump_game_gallery.py` — converts saved GameProject state
  to a human-readable Markdown gallery.
- `scripts/quickrun.bat` — one-click pipeline + gallery + open
  exported folder. Wraps the three sequential scripts so non-
  developers can demo the pipeline.
- `docs/FIRST_GENERATION_FINDINGS.md` — full root-cause + fix
  walkthrough for the prompt-structure issue.
- `docs/GAME_GALLERY.md` — Wickwater (roguelike, NOT PLAYABLE,
  12 QA issues).
- `docs/GAME_GALLERY_STEEPED.md` — Steeped (puzzle, PLAYABLE,
  12 minor QA issues).
- `docs/GAME_GALLERY_SALTWIND.md` — The Saltwind Steepers (RPG,
  NOT PLAYABLE, 14 QA issues).

### Fixed
- `pyproject.toml`: added `[tool.setuptools] py-modules = ["claudex",
  "claudex_anthropic_shim"]`. Without it, `pip install -e .` excluded
  the top-level single-module shims and `forge --help` raised
  `ModuleNotFoundError`.
- `claudex.ask_structured` originally tried to use the CLI's
  `--json-schema` flag. Empirically `--json-schema` is post-validation
  only (doesn't constrain generation), Anthropic's validator is
  stricter than Pydantic, and large schemas exceed Windows' 32K
  cmdline limit. Now the schema travels in the prompt and Pydantic
  is the validation gate.

### Changed
- All 5 director stages (`_generate_concept`, `_build_world`,
  `_design_mechanics`, `_write_narrative`, `_direct_art`, `_run_qa`)
  now route through `_call_structured` instead of the
  `_client.messages.create` Anthropic-shape shim. The shim path is
  kept for `iterate()` until that stage is migrated.
- `tests/test_director.py` — migrated 3 tests to mock
  `claudex.ask_structured` instead of `_client.messages.create`.
  9/9 tests pass; 110/110 unit tests still green overall.

### Verified
- First generation: Wickwater (30s concept stage in isolation)
- Full pipeline: Wickwater (278s end-to-end)
- Multi-genre: Steeped (puzzle, 358s, PLAYABLE) + Saltwind Steepers
  (RPG, 474s, NOT PLAYABLE — appropriate strictness)
- Export: produces openable Godot 4.6 project with project.godot +
  96KB manifest + scenes/ + 10 GDScript systems

### Cost
- Per call: ~$0 incremental on Claude Max sub (claudex → `claude -p`).
- Per call (if using API key path): ~$0.26 first time, $0.05-0.10
  warm with cache.

## [0.1.0] — 2026-04-12

Foundation release. 49 source files, 110 tests, 5-agent Opus
director, 51 Pydantic schemas, JSON-RPC 2.0 WebSocket bridge to
Godot, 20-tool MCP server. Pipeline was technically wireable but
the Director's prompts didn't survive the round-trip through
claudex — see Findings doc for the diagnosis that landed in 0.1.1.
