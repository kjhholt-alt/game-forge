"""End-to-end test: Python GodotBridge ↔ Godot MCP Server.

Launches Godot in headless mode, connects the Python bridge, and verifies
the JSON-RPC 2.0 round-trip works.

Run:  python -m pytest tests/test_bridge_e2e.py -v -s
"""

from __future__ import annotations

import asyncio
import subprocess
import sys
import time
from pathlib import Path

import pytest

# Skip if Godot is not installed
GODOT_EXE = None
_search_paths = [
    Path.home() / "AppData/Local/Microsoft/WinGet/Packages",
]
for base in _search_paths:
    if base.exists():
        for p in base.rglob("Godot_v*_console.exe"):
            GODOT_EXE = p
            break

if GODOT_EXE is None:
    # Try PATH
    import shutil
    _found = shutil.which("godot_console") or shutil.which("godot")
    if _found:
        GODOT_EXE = Path(_found)

skip_no_godot = pytest.mark.skipif(
    GODOT_EXE is None,
    reason="Godot not found — install via `winget install GodotEngine.GodotEngine`",
)

# All tests in this module need a live Godot MCP server. Mark the whole
# module e2e so CI skips by default; run locally with `pytest -m e2e`.
pytestmark = pytest.mark.e2e

PROJECT_DIR = Path(__file__).parent.parent / "godot_template"


@skip_no_godot
class TestBridgeE2E:
    """Integration tests that launch a real Godot instance."""

    @pytest.fixture(autouse=True)
    async def _godot_server(self):
        """Launch Godot headless, wait for MCP server to be ready, then tear down."""
        proc = subprocess.Popen(
            [
                str(GODOT_EXE),
                "--headless",
                "--path", str(PROJECT_DIR),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        # Give Godot time to start and the MCP server to bind
        await asyncio.sleep(4)

        yield proc

        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    @pytest.mark.asyncio
    async def test_ping(self):
        from tools.godot_bridge import GodotBridge

        async with GodotBridge("ws://localhost:6100", timeout=10) as bridge:
            result = await bridge.ping()
            assert result is True

    @pytest.mark.asyncio
    async def test_list_tools(self):
        from tools.godot_bridge import GodotBridge

        async with GodotBridge("ws://localhost:6100", timeout=10) as bridge:
            tools = await bridge.list_tools()
            assert len(tools) >= 15
            tool_names = [t["name"] for t in tools]
            assert "write_script" in tool_names
            assert "get_state" in tool_names
            assert "add_item" in tool_names

    @pytest.mark.asyncio
    async def test_get_state(self):
        from tools.godot_bridge import GodotBridge

        async with GodotBridge("ws://localhost:6100", timeout=10) as bridge:
            result = await bridge.call_tool("get_state")
            # Should have player_stats from GameState autoload
            assert "player_stats" in result or "name" in result.get("player_stats", {})

    @pytest.mark.asyncio
    async def test_set_and_get_flag(self):
        from tools.godot_bridge import GodotBridge

        async with GodotBridge("ws://localhost:6100", timeout=10) as bridge:
            await bridge.call_tool("set_flag", {"key": "test_flag", "value": True})
            state = await bridge.call_tool("get_state")
            assert state.get("flags", {}).get("test_flag") is True

    @pytest.mark.asyncio
    async def test_add_gold(self):
        from tools.godot_bridge import GodotBridge

        async with GodotBridge("ws://localhost:6100", timeout=10) as bridge:
            result = await bridge.call_tool("modify_gold", {"amount": 100})
            assert result["status"] == "ok"
            assert result["gold"] >= 100
