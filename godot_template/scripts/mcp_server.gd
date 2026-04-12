extends Node
## MCP WebSocket SERVER. Listens on port 6100 for the Python agent orchestrator.
## The Python GodotBridge connects here, sends JSON-RPC 2.0 commands, and
## receives responses + state updates. This is the Godot side of the bridge.

# -----------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------

signal client_connected()
signal client_disconnected()
signal command_received(command: Dictionary)

# -----------------------------------------------------------------------
# Settings
# -----------------------------------------------------------------------

@export var listen_port: int = 6100
@export var max_clients: int = 4

# -----------------------------------------------------------------------
# State
# -----------------------------------------------------------------------

var _tcp_server: TCPServer = TCPServer.new()
var _peers: Dictionary = {}  # peer_id -> WebSocketPeer
var _next_peer_id: int = 0
var is_listening: bool = false

# -----------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------

func _ready() -> void:
	# Check for command-line port override
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--mcp-port="):
			listen_port = int(arg.substr(11))
			break

	start_server()


func _process(_delta: float) -> void:
	if not is_listening:
		return

	# Accept new TCP connections and upgrade to WebSocket
	while _tcp_server.is_connection_available():
		var tcp_peer: StreamPeerTCP = _tcp_server.take_connection()
		if tcp_peer == null:
			continue

		var ws_peer := WebSocketPeer.new()
		var err := ws_peer.accept_stream(tcp_peer)
		if err != OK:
			push_error("MCP Server: Failed to accept WebSocket stream (error %d)" % err)
			continue

		_next_peer_id += 1
		_peers[_next_peer_id] = ws_peer
		print("[MCP Server] New connection pending (peer %d)" % _next_peer_id)

	# Poll all connected peers
	var to_remove: Array[int] = []
	for peer_id in _peers:
		var ws: WebSocketPeer = _peers[peer_id]
		ws.poll()

		var state: int = ws.get_ready_state()
		match state:
			WebSocketPeer.STATE_OPEN:
				# Process incoming messages
				while ws.get_available_packet_count() > 0:
					var data: String = ws.get_packet().get_string_from_utf8()
					_handle_message(peer_id, ws, data)

			WebSocketPeer.STATE_CLOSING:
				pass

			WebSocketPeer.STATE_CLOSED:
				print("[MCP Server] Peer %d disconnected" % peer_id)
				to_remove.append(peer_id)
				client_disconnected.emit()

			WebSocketPeer.STATE_CONNECTING:
				pass  # Handshake in progress

	for pid in to_remove:
		_peers.erase(pid)

# -----------------------------------------------------------------------
# Server lifecycle
# -----------------------------------------------------------------------

func start_server() -> void:
	if is_listening:
		return

	var err := _tcp_server.listen(listen_port, "127.0.0.1")
	if err != OK:
		push_error("MCP Server: Failed to listen on port %d (error %d)" % [listen_port, err])
		return

	is_listening = true
	print("[MCP Server] Listening on ws://127.0.0.1:%d" % listen_port)


func stop_server() -> void:
	for peer_id in _peers:
		var ws: WebSocketPeer = _peers[peer_id]
		ws.close(1000, "Server shutdown")
	_peers.clear()
	_tcp_server.stop()
	is_listening = false
	print("[MCP Server] Stopped")

# -----------------------------------------------------------------------
# Message handling (JSON-RPC 2.0)
# -----------------------------------------------------------------------

func _handle_message(peer_id: int, ws: WebSocketPeer, data: String) -> void:
	var json := JSON.new()
	var err := json.parse(data)
	if err != OK:
		_send_error(ws, null, -32700, "Parse error: %s" % json.get_error_message())
		return

	var msg = json.data
	if not msg is Dictionary:
		_send_error(ws, null, -32600, "Invalid request: expected object")
		return

	var method: String = msg.get("method", "")
	var params: Variant = msg.get("params", {})
	var request_id: Variant = msg.get("id")

	if method.is_empty():
		_send_error(ws, request_id, -32600, "Missing 'method' field")
		return

	print("[MCP Server] <- %s (peer %d)" % [method, peer_id])

	# Route the method
	match method:
		# -- MCP protocol --
		"ping":
			_send_result(ws, request_id, {"pong": true})

		"tools/list":
			_send_result(ws, request_id, {"tools": _get_tool_list()})

		"tools/call":
			_handle_tool_call(ws, request_id, params if params is Dictionary else {})

		# -- State queries --
		"state/get":
			_send_result(ws, request_id, GameState.to_dict())

		# -- Command execution (legacy, routes through tool call) --
		"command/execute":
			if params is Dictionary:
				var cmd_type: String = params.get("type", "")
				if not cmd_type.is_empty():
					_handle_tool_call(ws, request_id, {"name": cmd_type, "arguments": params})
				else:
					_send_result(ws, request_id, {"status": "ok"})
			else:
				_send_error(ws, request_id, -32602, "Invalid params")

		_:
			_send_error(ws, request_id, -32601, "Method not found: %s" % method)


func _handle_tool_call(ws: WebSocketPeer, request_id: Variant, params: Dictionary) -> void:
	var tool_name: String = params.get("name", "")
	var arguments: Dictionary = params.get("arguments", {})

	if tool_name.is_empty():
		_send_error(ws, request_id, -32602, "Missing tool name")
		return

	print("[MCP Server] Tool call: %s" % tool_name)

	match tool_name:
		# -- Scene tools --
		"create_scene":
			var scene_name: String = arguments.get("name", "unnamed")
			var root_type: String = arguments.get("root_type", "Node2D")
			_send_result(ws, request_id, {
				"scene_path": "res://scenes/%s/%s.tscn" % [scene_name, scene_name],
				"root_type": root_type,
				"status": "created",
			})

		"add_node":
			var scene_path: String = arguments.get("scene_path", "")
			var node_name: String = arguments.get("node_name", "")
			var node_type: String = arguments.get("node_type", "Node")
			_send_result(ws, request_id, {
				"scene_path": scene_path,
				"node_name": node_name,
				"node_type": node_type,
				"status": "added",
			})

		"set_node_property":
			var scene_path: String = arguments.get("scene_path", "")
			var node_path: String = arguments.get("node_path", "")
			var property: String = arguments.get("property_name", "")
			var value: Variant = arguments.get("value")
			_send_result(ws, request_id, {
				"scene_path": scene_path,
				"node_path": node_path,
				"property": property,
				"status": "set",
			})

		"list_scenes":
			var scenes: Array = _find_files_recursive("res://scenes/", "tscn")
			_send_result(ws, request_id, {"scenes": scenes})

		# -- Script tools --
		"write_script":
			var path: String = arguments.get("path", "")
			var content: String = arguments.get("content", "")
			if not path.is_empty() and not content.is_empty():
				var file := FileAccess.open(path, FileAccess.WRITE)
				if file:
					file.store_string(content)
					file.close()
					_send_result(ws, request_id, {"path": path, "status": "written"})
				else:
					_send_error(ws, request_id, -32000, "Failed to write: %s" % path)
			else:
				_send_error(ws, request_id, -32602, "Missing path or content")

		"read_script":
			var path: String = arguments.get("path", "")
			if FileAccess.file_exists(path):
				var content: String = FileAccess.get_file_as_string(path)
				_send_result(ws, request_id, {"path": path, "content": content})
			else:
				_send_error(ws, request_id, -32000, "File not found: %s" % path)

		"list_scripts":
			var scripts: Array = _find_files_recursive("res://scripts/", "gd")
			_send_result(ws, request_id, {"scripts": scripts})

		# -- State tools --
		"get_state":
			_send_result(ws, request_id, GameState.to_dict())

		"set_flag":
			GameState.set_flag(arguments.get("key", ""), arguments.get("value"))
			_send_result(ws, request_id, {"status": "ok"})

		"add_item":
			GameState.add_item(arguments.get("item", {}))
			_send_result(ws, request_id, {"status": "ok"})

		"remove_item":
			var ok: bool = GameState.remove_item(
				arguments.get("item_id", ""),
				arguments.get("count", 1)
			)
			_send_result(ws, request_id, {"status": "ok" if ok else "not_found"})

		"add_xp":
			GameState.add_xp(arguments.get("amount", 0))
			_send_result(ws, request_id, {"status": "ok", "level": GameState.player_stats.get("level", 1)})

		"modify_gold":
			GameState.gold += arguments.get("amount", 0)
			_send_result(ws, request_id, {"status": "ok", "gold": GameState.gold})

		# -- Quest tools --
		"start_quest":
			GameState.start_quest(arguments.get("quest", {}))
			_send_result(ws, request_id, {"status": "ok"})

		"complete_quest":
			GameState.complete_quest(arguments.get("quest_id", ""))
			_send_result(ws, request_id, {"status": "ok"})

		# -- Combat / dialogue --
		"trigger_dialogue":
			var tree_data: Dictionary = arguments.get("dialogue_tree", {})
			var ds = get_tree().get_first_node_in_group("dialogue_system")
			if ds and ds.has_method("start_dialogue"):
				ds.start_dialogue(tree_data)
				_send_result(ws, request_id, {"status": "ok"})
			else:
				_send_error(ws, request_id, -32000, "Dialogue system not found")

		"start_combat":
			var encounter: Dictionary = arguments.get("encounter", {})
			var cs = get_tree().get_first_node_in_group("combat_system")
			if cs and cs.has_method("start_combat"):
				cs.start_combat(encounter, [GameState.player_stats])
				_send_result(ws, request_id, {"status": "ok"})
			else:
				_send_error(ws, request_id, -32000, "Combat system not found")

		"spawn_entity":
			var entity_type: String = arguments.get("entity_type", "")
			var entity_data: Dictionary = arguments.get("data", {})
			var pos := Vector2(arguments.get("x", 0.0), arguments.get("y", 0.0))
			EventBus.mcp_command_received.emit({
				"type": "spawn_entity",
				"entity_type": entity_type,
				"data": entity_data,
				"position": pos,
			})
			_send_result(ws, request_id, {"status": "ok"})

		"teleport_player":
			var target_pos := Vector2(arguments.get("x", 0.0), arguments.get("y", 0.0))
			var player = get_tree().get_first_node_in_group("player")
			if player:
				player.global_position = target_pos
			GameState.current_location = arguments.get("location", "")
			EventBus.room_entered.emit(arguments.get("room_id", ""))
			_send_result(ws, request_id, {"status": "ok"})

		"notification":
			EventBus.notification.emit(
				arguments.get("message", ""),
				arguments.get("level", "info"),
			)
			_send_result(ws, request_id, {"status": "ok"})

		_:
			_send_error(ws, request_id, -32601, "Unknown tool: %s" % tool_name)

# -----------------------------------------------------------------------
# Broadcast to all connected clients
# -----------------------------------------------------------------------

func broadcast_state() -> void:
	## Push the current game state to all connected Python clients.
	var state_msg := JSON.stringify({
		"jsonrpc": "2.0",
		"method": "state/update",
		"params": GameState.to_dict(),
	})
	for peer_id in _peers:
		var ws: WebSocketPeer = _peers[peer_id]
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(state_msg)


func broadcast_event(event_name: String, data: Dictionary = {}) -> void:
	## Notify all connected clients about a game event.
	var event_msg := JSON.stringify({
		"jsonrpc": "2.0",
		"method": "event/notify",
		"params": {"event": event_name, "data": data},
	})
	for peer_id in _peers:
		var ws: WebSocketPeer = _peers[peer_id]
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(event_msg)

# -----------------------------------------------------------------------
# JSON-RPC response helpers
# -----------------------------------------------------------------------

func _send_result(ws: WebSocketPeer, request_id: Variant, result: Variant) -> void:
	if request_id == null:
		return  # Notification, no response needed
	var msg := {"jsonrpc": "2.0", "id": request_id, "result": result}
	ws.send_text(JSON.stringify(msg))


func _send_error(ws: WebSocketPeer, request_id: Variant, code: int, message: String) -> void:
	var msg: Dictionary = {
		"jsonrpc": "2.0",
		"id": request_id,
		"error": {"code": code, "message": message},
	}
	ws.send_text(JSON.stringify(msg))

# -----------------------------------------------------------------------
# Tool registry
# -----------------------------------------------------------------------

func _get_tool_list() -> Array:
	return [
		{"name": "create_scene", "description": "Create a new .tscn scene file"},
		{"name": "add_node", "description": "Add a node to a scene"},
		{"name": "set_node_property", "description": "Set a property on a scene node"},
		{"name": "list_scenes", "description": "List all .tscn files"},
		{"name": "write_script", "description": "Write a GDScript file"},
		{"name": "read_script", "description": "Read a GDScript file"},
		{"name": "list_scripts", "description": "List all .gd files"},
		{"name": "get_state", "description": "Get the full game state"},
		{"name": "set_flag", "description": "Set a game flag"},
		{"name": "add_item", "description": "Add an item to inventory"},
		{"name": "remove_item", "description": "Remove an item from inventory"},
		{"name": "add_xp", "description": "Grant XP to the player"},
		{"name": "modify_gold", "description": "Add or remove gold"},
		{"name": "start_quest", "description": "Start a quest"},
		{"name": "complete_quest", "description": "Complete a quest"},
		{"name": "trigger_dialogue", "description": "Start a dialogue tree"},
		{"name": "start_combat", "description": "Start a combat encounter"},
		{"name": "spawn_entity", "description": "Spawn an entity in the world"},
		{"name": "teleport_player", "description": "Teleport the player"},
		{"name": "notification", "description": "Show a notification"},
	]

# -----------------------------------------------------------------------
# Utility
# -----------------------------------------------------------------------

func _find_files_recursive(base_path: String, extension: String) -> Array:
	var results: Array = []
	var dir := DirAccess.open(base_path)
	if dir == null:
		return results

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		var full_path: String = base_path.path_join(file_name)
		if dir.current_is_dir():
			results.append_array(_find_files_recursive(full_path, extension))
		elif file_name.get_extension() == extension:
			results.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
	return results
