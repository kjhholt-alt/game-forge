"""Claude CLI client for GameForge.

All model calls go through ``claude -p`` via ``claudex``. This module gives
older worker code a small messages-style client without depending on an API SDK
or reading API keys.
"""

from __future__ import annotations

import asyncio
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

import claudex as _cx  # noqa: E402


@dataclass
class TextBlock:
    type: str = "text"
    text: str = ""


@dataclass
class Message:
    content: list[TextBlock]
    stop_reason: str = "end_turn"
    role: str = "assistant"

    def model_dump(self) -> dict[str, Any]:
        return {
            "content": [{"type": b.type, "text": b.text} for b in self.content],
            "stop_reason": self.stop_reason,
            "role": self.role,
        }


class types:
    Message = Message


def _flatten_messages(system: str | None, messages: list[dict[str, Any]] | None) -> str:
    parts: list[str] = []
    if system:
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


class Messages:
    def create(
        self,
        *,
        model: str | None = None,
        max_tokens: int | None = None,
        system: Any = None,
        messages: list[dict[str, Any]] | None = None,
        **_: Any,
    ) -> Message:
        prompt = _flatten_messages(system, messages)
        r = _cx.ask(prompt, use_cache=True, timeout_s=120)
        return Message(content=[TextBlock(text=r.text)])


class AsyncMessages:
    async def create(
        self,
        *,
        model: str | None = None,
        max_tokens: int | None = None,
        system: Any = None,
        messages: list[dict[str, Any]] | None = None,
        **_: Any,
    ) -> Message:
        prompt = _flatten_messages(system, messages)
        r = await asyncio.to_thread(_cx.ask, prompt, use_cache=True, timeout_s=120)
        return Message(content=[TextBlock(text=r.text)])


class ClaudeClient:
    """Sync messages-style client backed by the signed-in Claude CLI."""

    def __init__(self, **_: Any) -> None:
        self.messages = Messages()


class AsyncClaudeClient:
    """Async messages-style client backed by the signed-in Claude CLI."""

    def __init__(self, **_: Any) -> None:
        self.messages = AsyncMessages()


ClaudeCliError = _cx.ClaudexError
ConnectionError = _cx.ClaudexError
RateLimitError = _cx.ClaudexError
