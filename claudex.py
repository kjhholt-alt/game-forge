"""claudex — call Claude from any personal project via Max-sub subprocess.

No Anthropic SDK. No API key. Just `claude -p` under the hood. Works wherever
the Claude Code CLI is installed and signed into a Max subscription.

Quick start:

    from claudex import ask, ask_json, ask_batch, ask_stream

    text = ask("Summarize this in one sentence: ...")
    data = ask_json("Categorize: 'STARBUCKS STORE 09812'. Categories: Dining, Other.",
                    schema={"category": "str"})
    rows = ask_batch(items=["MERCH A", "MERCH B"],
                     instruction="Categorize each. Return JSON array of {item, category}.")

    # Streaming — yields StreamEvent for each chunk
    for ev in ask_stream("Write a 3-sentence summary of the French Revolution"):
        if ev.type == "text":
            print(ev.text, end="", flush=True)

Design rules (per `feedback_no_anthropic_key_max_sub_handoff.md`):
- Never imports `anthropic` SDK.
- Never reads `ANTHROPIC_API_KEY`.
- All calls go through `claude -p` subprocess.
- Caches by prompt hash to a project-local `.claudex_cache/` so the same
  prompt does not burn tokens twice.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator

DEFAULT_TIMEOUT_S = 120
CACHE_DIRNAME = ".claudex_cache"


class ClaudexError(RuntimeError):
    """Raised when the Claude CLI fails or returns malformed output."""


def _resolve_claude_bin() -> str:
    """Locate the Claude CLI. Prefer `claude.exe` on PATH; fall back to known install spots."""
    found = shutil.which("claude")
    if found:
        return found
    # Common Windows install locations
    candidates = [
        os.path.expandvars(r"%USERPROFILE%\.local\bin\claude.exe"),
        os.path.expandvars(r"%APPDATA%\npm\claude.cmd"),
        os.path.expandvars(r"%APPDATA%\npm\claude"),
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    raise ClaudexError("Claude CLI not found. Install from https://claude.ai/code.")


def _cache_path(project_root: Path, prompt: str) -> Path:
    h = hashlib.sha256(prompt.encode("utf-8")).hexdigest()[:16]
    cache_dir = project_root / CACHE_DIRNAME
    cache_dir.mkdir(exist_ok=True)
    return cache_dir / f"{h}.txt"


@dataclass
class Response:
    text: str
    cached: bool
    prompt_hash: str


def ask(
    prompt: str,
    *,
    project_root: Path | None = None,
    use_cache: bool = True,
    timeout_s: int = DEFAULT_TIMEOUT_S,
) -> Response:
    """Send a prompt to Claude via `claude -p`. Returns text response.

    Caches by SHA-256(prompt). Pass `use_cache=False` to bypass.
    """
    project_root = project_root or Path.cwd()
    h = hashlib.sha256(prompt.encode("utf-8")).hexdigest()[:16]
    cache_file = _cache_path(project_root, prompt)
    if use_cache and cache_file.exists():
        return Response(text=cache_file.read_text(encoding="utf-8"), cached=True, prompt_hash=h)

    bin_path = _resolve_claude_bin()
    try:
        proc = subprocess.run(
            [bin_path, "-p", prompt],
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=timeout_s,
            check=False,
        )
    except subprocess.TimeoutExpired as e:
        raise ClaudexError(f"Claude CLI timed out after {timeout_s}s") from e

    if proc.returncode != 0:
        raise ClaudexError(f"Claude CLI exit {proc.returncode}: {proc.stderr.strip()[:500]}")

    text = (proc.stdout or "").strip()
    if not text:
        raise ClaudexError("Claude CLI returned empty stdout.")

    if use_cache:
        cache_file.write_text(text, encoding="utf-8")
    return Response(text=text, cached=False, prompt_hash=h)


_JSON_FENCE = re.compile(r"```(?:json)?\s*(.*?)\s*```", re.DOTALL)


def _extract_json(text: str) -> Any:
    """Best-effort extraction of JSON from a model response."""
    candidates = []
    m = _JSON_FENCE.search(text)
    if m:
        candidates.append(m.group(1))
    candidates.append(text)
    for c in candidates:
        c = c.strip()
        try:
            return json.loads(c)
        except json.JSONDecodeError:
            continue
    raise ClaudexError(f"Could not parse JSON from response. Got: {text[:300]}")


def ask_json(
    prompt: str,
    *,
    project_root: Path | None = None,
    use_cache: bool = True,
    timeout_s: int = DEFAULT_TIMEOUT_S,
) -> Any:
    """Same as ask(), but parses JSON out of the response.

    Best practice: have the prompt say 'Return ONLY a JSON object/array, no prose.'
    """
    resp = ask(prompt, project_root=project_root, use_cache=use_cache, timeout_s=timeout_s)
    return _extract_json(resp.text)


def ask_batch(
    items: list[str],
    instruction: str,
    *,
    project_root: Path | None = None,
    item_label: str = "item",
    extra_keys: list[str] | None = None,
    use_cache: bool = True,
    timeout_s: int = DEFAULT_TIMEOUT_S,
) -> list[dict]:
    """Ask Claude to label/process a batch of items. Returns a list of dicts.

    Output schema: each dict has "{item_label}" key plus whatever extra_keys the
    instruction asks for (default ["category"]).
    """
    extras = extra_keys or ["category"]
    schema_hint = "{" + ", ".join([f'"{item_label}": "<string>"'] + [f'"{k}": "<string>"' for k in extras]) + "}"
    items_block = "\n".join(f"- {x}" for x in items)
    prompt = (
        f"{instruction}\n\n"
        f"Items:\n{items_block}\n\n"
        f"Return ONLY a JSON array. No prose, no markdown fences. Each element is:\n"
        f"  {schema_hint}\n"
        f"Return one element per item, in the same order."
    )
    data = ask_json(prompt, project_root=project_root, use_cache=use_cache, timeout_s=timeout_s)
    if not isinstance(data, list):
        raise ClaudexError(f"Expected JSON array, got {type(data).__name__}")
    return data


@dataclass
class StreamEvent:
    """One event from `claude -p --output-format stream-json`.

    type:
      - "text"   — a chunk of model-generated text (delta).
      - "result" — final wrap-up event with full text + token usage.
      - "error"  — CLI-emitted error event.
    text:    the chunk text (for "text") or full final text (for "result").
    raw:     the underlying parsed JSON event, for callers that want metadata.
    """

    type: str
    text: str
    raw: dict[str, Any]


def ask_stream(
    prompt: str,
    *,
    timeout_s: int = DEFAULT_TIMEOUT_S,
) -> Iterator[StreamEvent]:
    """Stream Claude's response as it generates.

    Yields one StreamEvent per JSON line on the CLI's stdout. The "text" events
    arrive incrementally; "result" arrives once at the end with the full string.
    Streaming bypasses the cache (no useful semantics for partial responses).

    Example:
        full = ""
        for ev in ask_stream(prompt):
            if ev.type == "text":
                full += ev.text
                print(ev.text, end="", flush=True)
            elif ev.type == "result":
                print()  # newline after stream
    """
    bin_path = _resolve_claude_bin()
    proc = subprocess.Popen(
        [bin_path, "-p", prompt, "--output-format", "stream-json", "--verbose"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        bufsize=1,  # line-buffered
    )

    if proc.stdout is None:
        proc.kill()
        raise ClaudexError("Claude CLI streaming: stdout pipe missing.")

    last_text_len = 0  # so we can yield deltas, not cumulative full text
    try:
        for raw_line in proc.stdout:
            line = raw_line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue

            etype = ev.get("type")
            if etype == "assistant":
                # The CLI emits the message-so-far in `message.content[].text`.
                # Diff against last_text_len to yield the delta.
                msg = ev.get("message") or {}
                content = msg.get("content") or []
                full = "".join(b.get("text", "") for b in content if b.get("type") == "text")
                if len(full) > last_text_len:
                    delta = full[last_text_len:]
                    last_text_len = len(full)
                    yield StreamEvent(type="text", text=delta, raw=ev)
            elif etype == "result":
                final_text = ev.get("result") or ""
                yield StreamEvent(type="result", text=final_text, raw=ev)
            elif etype == "error" or ev.get("is_error"):
                yield StreamEvent(type="error", text=ev.get("error", "") or line, raw=ev)
            # Ignore "system", "rate_limit_event", etc.

        rc = proc.wait(timeout=timeout_s)
        if rc != 0:
            err = (proc.stderr.read() if proc.stderr else "").strip()
            raise ClaudexError(f"Claude CLI exit {rc}: {err[:500]}")
    except subprocess.TimeoutExpired as e:
        proc.kill()
        raise ClaudexError(f"Claude CLI streaming timed out after {timeout_s}s") from e
    finally:
        if proc.poll() is None:
            proc.terminate()


def clear_cache(project_root: Path | None = None) -> int:
    """Wipe the local prompt cache. Returns number of entries removed."""
    root = project_root or Path.cwd()
    d = root / CACHE_DIRNAME
    if not d.exists():
        return 0
    n = 0
    for f in d.glob("*.txt"):
        f.unlink()
        n += 1
    return n


def health_check() -> dict:
    """Quick diagnostic: confirm CLI is reachable and Max-sub is signed in."""
    info: dict[str, Any] = {"claude_bin": None, "ok": False, "sample_response": None, "error": None}
    try:
        info["claude_bin"] = _resolve_claude_bin()
        resp = ask("Reply with the literal text 'CLAUDEX_OK' and nothing else.", use_cache=False, timeout_s=30)
        info["sample_response"] = resp.text
        info["ok"] = "CLAUDEX_OK" in resp.text
    except Exception as e:
        info["error"] = str(e)
    return info


if __name__ == "__main__":
    print(json.dumps(health_check(), indent=2))
