"""anthropic-SDK-shaped shim backed by claudex (`claude -p` subprocess).

Drop-in replacement for projects that have many `import anthropic` sites
and use the SDK's `Anthropic()` / `AsyncAnthropic()` clients with
`.messages.create(model, max_tokens, system, messages)`.

Usage: replace `import anthropic` with `import claudex_anthropic_shim as anthropic`.

Limitations vs the real SDK:
- No streaming. `messages.stream()` is not implemented.
- No tool_use / function calling. `claude -p` does not expose these.
- No prompt caching cache_control. The CLI uses Max-sub auth which has its own caching.
- Model selection is ignored — whatever the Claude CLI is signed into is used.

If you need any of the above, call claudex.ask directly instead.
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

# Import the real claudex from the same dir
_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

import claudex as _cx  # noqa: E402


@dataclass
class _TextBlock:
    type: str = "text"
    text: str = ""


@dataclass
class _Message:
    content: list[_TextBlock]
    stop_reason: str = "end_turn"
    role: str = "assistant"

    def model_dump(self) -> dict[str, Any]:
        return {
            "content": [{"type": b.type, "text": b.text} for b in self.content],
            "stop_reason": self.stop_reason,
            "role": self.role,
        }


def _flatten_messages(system: str | None, messages: list[dict[str, Any]] | None) -> str:
    parts: list[str] = []
    if system:
        # system can be a list of blocks (with cache_control) or a plain string
        if isinstance(system, list):
            text = "\n".join(
                b.get("text", "") if isinstance(b, dict) else str(b) for b in system
            )
        else:
            text = str(system)
        parts.append(f"<system>\n{text}\n</system>")
    for m in messages or []:
        role = m.get("role", "user")
        content = m.get("content", "")
        if isinstance(content, list):
            content = "\n".join(
                b.get("text", "") if isinstance(b, dict) else str(b) for b in content
            )
        parts.append(f"<{role}>\n{content}\n</{role}>")
    parts.append("<assistant>")
    return "\n\n".join(parts)


class _Messages:
    def create(
        self,
        *,
        model: str | None = None,
        max_tokens: int | None = None,
        system: Any = None,
        messages: list[dict[str, Any]] | None = None,
        **_: Any,
    ) -> _Message:
        prompt = _flatten_messages(system, messages)
        r = _cx.ask(prompt, use_cache=True, timeout_s=120)
        return _Message(content=[_TextBlock(text=r.text)])


class _AsyncMessages:
    async def create(
        self,
        *,
        model: str | None = None,
        max_tokens: int | None = None,
        system: Any = None,
        messages: list[dict[str, Any]] | None = None,
        **_: Any,
    ) -> _Message:
        prompt = _flatten_messages(system, messages)
        r = await asyncio.to_thread(_cx.ask, prompt, use_cache=True, timeout_s=120)
        return _Message(content=[_TextBlock(text=r.text)])


class Anthropic:
    """Sync client. `api_key` argument accepted but ignored — Max-sub via CLI."""

    def __init__(self, api_key: str | None = None, **_: Any) -> None:
        self.messages = _Messages()


class AsyncAnthropic:
    """Async client. `api_key` argument accepted but ignored — Max-sub via CLI."""

    def __init__(self, api_key: str | None = None, **_: Any) -> None:
        self.messages = _AsyncMessages()


# Re-export claudex error so callers can `except anthropic.APIError`-style if needed.
APIError = _cx.ClaudexError
APIConnectionError = _cx.ClaudexError
RateLimitError = _cx.ClaudexError
