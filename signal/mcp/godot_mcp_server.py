"""Godot MCP Server — lets Claude Code interact with a running Godot game.

Exposes tools: screenshot, click, key_press, scene_tree, game_state,
blips, hud, node_info. Communicates with Godot's debug HTTP server
on localhost:9090.

Usage in .claude.json:
  "godot-game": {
    "command": "python",
    "args": ["C:/Users/Kruz/Desktop/Projects/game-forge/signal/mcp/godot_mcp_server.py"]
  }
"""

import json
import sys
import urllib.request
import urllib.error
from typing import Any

GODOT_URL = "http://localhost:9090"


def call_godot(endpoint: str, method: str = "GET") -> dict:
    """Make an HTTP request to the Godot debug server."""
    try:
        req = urllib.request.Request(f"{GODOT_URL}{endpoint}", method=method)
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.URLError as e:
        return {"error": f"Cannot connect to Godot (is the game running?): {e}"}
    except json.JSONDecodeError:
        return {"error": "Invalid JSON from Godot"}
    except Exception as e:
        return {"error": str(e)}


# ---------------------------------------------------------------------------
# MCP Protocol (stdio JSON-RPC)
# ---------------------------------------------------------------------------

TOOLS = [
    {
        "name": "godot_screenshot",
        "description": "Take a screenshot of the running Godot game. Returns the file path to the PNG image which you can then read with the Read tool to see the game visually.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "godot_click",
        "description": "Click at screen coordinates in the running Godot game. Use button=1 for left click (select/classify), button=2 for right click (open options).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "x": {"type": "integer", "description": "X coordinate on screen"},
                "y": {"type": "integer", "description": "Y coordinate on screen"},
                "button": {"type": "integer", "description": "1=left, 2=right, 3=middle", "default": 1},
            },
            "required": ["x", "y"],
        },
    },
    {
        "name": "godot_key",
        "description": "Press a key in the running Godot game. Common keys: ENTER, ESCAPE, TAB, SPACE, SLASH (for advice).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "key": {"type": "string", "description": "Key name: ENTER, ESCAPE, TAB, SPACE, SLASH, F1-F12"},
            },
            "required": ["key"],
        },
    },
    {
        "name": "godot_state",
        "description": "Get the current game state — phase, detection level, FPS, voice status, etc.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "godot_blips",
        "description": "Get all blips on the tactical map — their positions, types, labels, and screen coordinates. Use screen coordinates for clicking.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "godot_hud",
        "description": "Read the HUD display — codename, budget, timer, objective text.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "godot_tree",
        "description": "Get the scene tree structure of the running game. Useful for debugging layout issues.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "depth": {"type": "integer", "description": "Max tree depth (default 3)", "default": 3},
            },
        },
    },
    {
        "name": "godot_node",
        "description": "Get properties of a specific node by path. Example path: 'Main/TacticalMap' or 'Main/HUD/TopBar'.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Node path from root (e.g. 'Main/TacticalMap')"},
            },
            "required": ["path"],
        },
    },
]


def handle_tool_call(name: str, arguments: dict) -> Any:
    """Execute a tool and return the result."""
    match name:
        case "godot_screenshot":
            result = call_godot("/screenshot")
            if "path" in result:
                return f"Screenshot saved to: {result['path']}\nSize: {result.get('width', '?')}x{result.get('height', '?')}\nUse the Read tool to view this image file."
            return json.dumps(result)

        case "godot_click":
            x = arguments.get("x", 0)
            y = arguments.get("y", 0)
            button = arguments.get("button", 1)
            return json.dumps(call_godot(f"/click?x={x}&y={y}&button={button}"))

        case "godot_key":
            key = arguments.get("key", "")
            return json.dumps(call_godot(f"/key?key={key}"))

        case "godot_state":
            return json.dumps(call_godot("/state"), indent=2)

        case "godot_blips":
            return json.dumps(call_godot("/blips"), indent=2)

        case "godot_hud":
            return json.dumps(call_godot("/hud"), indent=2)

        case "godot_tree":
            depth = arguments.get("depth", 3)
            return json.dumps(call_godot(f"/tree?depth={depth}"), indent=2)

        case "godot_node":
            path = arguments.get("path", "")
            return json.dumps(call_godot(f"/node?path={path}"), indent=2)

        case _:
            return json.dumps({"error": f"Unknown tool: {name}"})


def main():
    """Run the MCP server over stdio."""
    # Read JSON-RPC messages from stdin, write responses to stdout
    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break

            msg = json.loads(line.strip())
            msg_id = msg.get("id")
            method = msg.get("method", "")

            if method == "initialize":
                response = {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {"tools": {"listChanged": False}},
                        "serverInfo": {"name": "godot-game", "version": "1.0.0"},
                    },
                }
            elif method == "notifications/initialized":
                continue  # No response needed
            elif method == "tools/list":
                response = {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {"tools": TOOLS},
                }
            elif method == "tools/call":
                params = msg.get("params", {})
                tool_name = params.get("name", "")
                tool_args = params.get("arguments", {})
                result_text = handle_tool_call(tool_name, tool_args)
                response = {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {
                        "content": [{"type": "text", "text": str(result_text)}],
                    },
                }
            else:
                response = {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {},
                }

            sys.stdout.write(json.dumps(response) + "\n")
            sys.stdout.flush()

        except json.JSONDecodeError:
            continue
        except Exception as e:
            error_response = {
                "jsonrpc": "2.0",
                "id": None,
                "error": {"code": -32603, "message": str(e)},
            }
            sys.stdout.write(json.dumps(error_response) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
