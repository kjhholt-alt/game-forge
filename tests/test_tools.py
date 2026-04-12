"""Tests for the tool layer: GodotBridge, SceneTools, ScriptTools, AssetTools.

All WebSocket communication is mocked. Asset generation uses Pillow locally.
"""

from __future__ import annotations

import asyncio
import json
import tempfile
from pathlib import Path
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from tools.asset_tools import AssetTools, _safe_filename
from tools.godot_bridge import GodotBridge, GodotBridgeError
from tools.scene_tools import SceneTools
from tools.script_tools import (
    ScriptTools,
    _build_export_line,
    _build_method,
    _gdscript_literal,
    _validate_gdscript_basics,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def mock_bridge() -> GodotBridge:
    """GodotBridge with mocked WebSocket."""
    bridge = GodotBridge("ws://localhost:6100")
    bridge._ws = MagicMock()
    bridge.call_tool = AsyncMock(return_value={})
    return bridge


@pytest.fixture
def scene_tools(mock_bridge: GodotBridge) -> SceneTools:
    return SceneTools(mock_bridge, "/tmp/godot_project")


@pytest.fixture
def script_tools(mock_bridge: GodotBridge) -> ScriptTools:
    return ScriptTools(mock_bridge, "/tmp/godot_project")


@pytest.fixture
def asset_tools(tmp_path: Path) -> AssetTools:
    return AssetTools(output_dir=str(tmp_path))


# ---------------------------------------------------------------------------
# GodotBridge
# ---------------------------------------------------------------------------


class TestGodotBridge:
    def test_json_rpc_message_format(self) -> None:
        """Verify the JSON-RPC 2.0 message structure."""
        bridge = GodotBridge("ws://localhost:6100")
        msg_id = bridge._next_id()
        payload = {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "id": msg_id,
            "params": {"name": "create_scene", "arguments": {"path": "res://test.tscn"}},
        }
        assert payload["jsonrpc"] == "2.0"
        assert payload["method"] == "tools/call"
        assert isinstance(payload["id"], int)

    def test_next_id_increments(self) -> None:
        bridge = GodotBridge()
        id1 = bridge._next_id()
        id2 = bridge._next_id()
        assert id2 == id1 + 1

    async def test_call_tool_sends_correct_params(self, mock_bridge: GodotBridge) -> None:
        await mock_bridge.call_tool("create_scene", {"path": "res://test.tscn", "root_type": "Node2D"})
        mock_bridge.call_tool.assert_awaited_once_with(
            "create_scene", {"path": "res://test.tscn", "root_type": "Node2D"}
        )

    async def test_call_tool_without_arguments(self, mock_bridge: GodotBridge) -> None:
        await mock_bridge.call_tool("list_files")
        mock_bridge.call_tool.assert_awaited_once_with("list_files")

    def test_not_connected_by_default(self) -> None:
        bridge = GodotBridge()
        assert bridge._ws is None

    async def test_connect_failure_raises(self) -> None:
        bridge = GodotBridge("ws://localhost:59999", timeout=1.0)
        with pytest.raises(GodotBridgeError, match="Failed to connect"):
            await bridge.connect()


# ---------------------------------------------------------------------------
# SceneTools
# ---------------------------------------------------------------------------


class TestSceneTools:
    async def test_create_scene(self, scene_tools: SceneTools) -> None:
        result = await scene_tools.create_scene("test_scene", "Node2D")
        scene_tools._bridge.call_tool.assert_awaited_once_with(
            "create_scene", {"path": "res://scenes/test_scene.tscn", "root_type": "Node2D"}
        )
        assert result == "res://scenes/test_scene.tscn"

    async def test_add_node(self, scene_tools: SceneTools) -> None:
        await scene_tools.add_node(
            "res://scenes/test.tscn", "Sprite", "Sprite2D", ".", {"texture": "res://tex.png"}
        )
        scene_tools._bridge.call_tool.assert_awaited_once()
        call_args = scene_tools._bridge.call_tool.call_args
        assert call_args[0][0] == "add_node"
        assert call_args[0][1]["node_name"] == "Sprite"
        assert call_args[0][1]["node_type"] == "Sprite2D"

    async def test_set_node_property(self, scene_tools: SceneTools) -> None:
        await scene_tools.set_node_property("res://scenes/test.tscn", ".", "position", [100, 200])
        call_args = scene_tools._bridge.call_tool.call_args
        assert call_args[0][0] == "set_node_property"
        assert call_args[0][1]["value"] == [100, 200]

    async def test_res_path_normalization(self, scene_tools: SceneTools) -> None:
        assert scene_tools._res_path("scenes/test.tscn") == "res://scenes/test.tscn"
        assert scene_tools._res_path("res://already/correct.tscn") == "res://already/correct.tscn"
        assert scene_tools._res_path("./relative/path.tscn") == "res://relative/path.tscn"


# ---------------------------------------------------------------------------
# ScriptTools
# ---------------------------------------------------------------------------


class TestScriptTools:
    async def test_write_script(self, script_tools: ScriptTools) -> None:
        content = "extends Node\n\nfunc _ready():\n\tpass\n"
        await script_tools.write_script("scripts/test.gd", content)
        call_args = script_tools._bridge.call_tool.call_args
        assert call_args[0][0] == "write_file"
        assert call_args[0][1]["path"] == "res://scripts/test.gd"
        assert call_args[0][1]["content"] == content

    async def test_generate_script(self, script_tools: ScriptTools) -> None:
        source = await script_tools.generate_script(
            class_name="TestEntity",
            extends="CharacterBody2D",
            signals=["health_changed", "died"],
            exports=[
                {"name": "speed", "type": "float", "default": 100.0},
                {"name": "health", "type": "int", "default": 100},
            ],
            methods=[
                {"name": "ready", "body": "print('hello')"},
                {"name": "take_damage", "args": ["amount: int"], "body": "health -= amount\nhealth_changed.emit()"},
            ],
        )
        assert "extends CharacterBody2D" in source
        assert "class_name TestEntity" in source
        assert "signal health_changed" in source
        assert "@export var speed: float = 100.0" in source
        assert "func _ready():" in source

    def test_gdscript_literal_bool(self) -> None:
        assert _gdscript_literal(True) == "true"
        assert _gdscript_literal(False) == "false"

    def test_gdscript_literal_int(self) -> None:
        assert _gdscript_literal(42) == "42"

    def test_gdscript_literal_string(self) -> None:
        assert _gdscript_literal("hello") == '"hello"'

    def test_gdscript_literal_list(self) -> None:
        assert _gdscript_literal([1, 2, 3]) == "[1, 2, 3]"

    def test_gdscript_literal_dict(self) -> None:
        result = _gdscript_literal({"a": 1})
        assert '"a": 1' in result

    def test_gdscript_literal_none(self) -> None:
        assert _gdscript_literal(None) == "null"

    def test_validate_empty_script(self) -> None:
        warnings = _validate_gdscript_basics("")
        assert any("empty" in w.lower() for w in warnings)

    def test_validate_missing_extends(self) -> None:
        warnings = _validate_gdscript_basics("func _ready():\n\tpass")
        assert any("extends" in w.lower() for w in warnings)

    def test_validate_spaces_warning(self) -> None:
        warnings = _validate_gdscript_basics("extends Node\n\nfunc _ready():\n    pass")
        assert any("spaces" in w.lower() for w in warnings)

    def test_validate_good_script(self) -> None:
        warnings = _validate_gdscript_basics("extends Node\n\nfunc _ready():\n\tpass")
        assert len(warnings) == 0

    def test_build_export_line(self) -> None:
        line = _build_export_line({"name": "speed", "type": "float", "default": 100.0})
        assert line == "@export var speed: float = 100.0"

    def test_build_method(self) -> None:
        result = _build_method({"name": "ready", "body": "print('hi')"})
        assert "func _ready():" in result
        assert "\tprint('hi')" in result


# ---------------------------------------------------------------------------
# AssetTools
# ---------------------------------------------------------------------------


class TestAssetTools:
    async def test_create_placeholder_sprite(self, asset_tools: AssetTools) -> None:
        path_str = await asset_tools.create_placeholder_sprite("test_hero", (32, 32))
        path = Path(path_str)
        assert path.exists()
        assert path.suffix == ".png"

    async def test_generate_sprite_fallback(self, asset_tools: AssetTools) -> None:
        """Without REPLICATE_API_TOKEN, generate_sprite should create a placeholder."""
        path_str = await asset_tools.generate_sprite("a blue slime", size=(64, 64))
        path = Path(path_str)
        assert path.exists()
        assert path.suffix == ".png"

    async def test_generate_tileset(self, asset_tools: AssetTools) -> None:
        path_str = await asset_tools.generate_tileset(
            {"grass": "green grass", "dirt": "brown dirt"}, tile_size=16
        )
        path = Path(path_str)
        assert path.exists()

    async def test_generate_portrait(self, asset_tools: AssetTools) -> None:
        path_str = await asset_tools.generate_portrait("a wise old wizard", size=(128, 128))
        path = Path(path_str)
        assert path.exists()

    async def test_list_assets_empty(self, asset_tools: AssetTools) -> None:
        assets = await asset_tools.list_assets()
        assert isinstance(assets, list)

    def test_safe_filename(self) -> None:
        assert _safe_filename("Hello World!") == "hello_world"
        assert _safe_filename("a" * 100) == "a" * 48
        assert _safe_filename("!!!") == "unnamed"
        assert _safe_filename("Test-Name_123") == "test-name_123"
