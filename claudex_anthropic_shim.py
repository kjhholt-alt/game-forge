"""Deprecated compatibility wrapper around ``claudex_client``.

New GameForge code imports ``claudex_client`` directly. This file remains so
old notebooks/scripts that imported the former SDK-shaped shim do not
immediately break.
"""

from __future__ import annotations

from claudex_client import (  # noqa: F401
    AsyncClaudeClient,
    ClaudeClient,
    ClaudeCliError,
    ConnectionError,
    Message,
    RateLimitError,
    TextBlock,
    types,
)

Anthropic = ClaudeClient
AsyncAnthropic = AsyncClaudeClient
APIError = ClaudeCliError
APIConnectionError = ConnectionError
