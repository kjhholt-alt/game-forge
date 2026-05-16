extends Node
## MCP WebSocket client. Receives commands from the Python agent orchestrator.
## This allows the AI to modify the running game in real-time.

# -----------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------

signal connected()
signal disconnected()
signal command_received(command: Dictionary)

# -----------------------------------------------------------------------
# Settings
# -----------------------------------------------------------------------

var server_url: String = "ws://localhost:6100"
var auto_reconnect: bool = true
var reconnect_delay: float = 3.0

# -----------------------------------------------------------------------
# State
# -----------------------------------------------------------------------

var ws: WebSocketPeer = WebSocketPeer.new()
var is_connected: bool = false
var _reconnect_timer: float = 0.0
var _should_reconnect: bool = false
var _msg_id: int = 0

# -----------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------

func _ready() -> void:
	# Check for command-line override
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--mcp-url="):
			server_url = arg.substr(10)
			break

	# Auto-connect on start
	connect_to_server()


func _process(delta: float) -> void:
	ws.poll()

	var state: int = ws.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not is_connected:
				is_connected = true
				_should_reconnect = false
				connected.emit()
				# Send initial state
				send_state(GameState.to_dict())

			# Process incoming messages
			while ws.get_available_packet_count() > 0:
				var data: String = ws.get_packet().get_string_from_utf8()
				_handle_message(data)

		WebSocketPeer.STATE_CLOSING:
			pass  # Wait for close to complete

		WebSocketPeer.STATE_CLOSED:
			if is_connected:
				is_connected = false
				disconnected.emit()
				var code: int = ws.get_close_code()
				var reason: String = ws.get_close_reason()
				push_warning("MCP WebSocket closed: %d %s" % [code, reason])

			# Auto-reconnect logic
			if auto_reconnect and _should_reconnect:
				_reconnect_timer += delta
				if _reconnect_timer >= reconnect_delay:
					_reconnect_timer = 0.0
					connect_to_server()

		WebSocketPeer.STATE_CONNECTING:
			pass  # Still connecting

# -----------------------------------------------------------------------
# Connection
# -----------------------------------------------------------------------

func connect_to_server(url: String = "") -> void:
	if not url.is_empty():
		server_url = url

	var err: int = ws.connect_to_url(server_url)
	if err != OK:
		push_error("MCP: Failed to connect to %s (error %d)" % [server_url, err])
		_should_reconnect = auto_reconnect
	else:
		_should_reconnect = true


func disconnect_from_server() -> void:
	_should_reconnect = false
	ws.close(1000, "Client disconnect")

# -----------------------------------------------------------------------
# Sending
# -----------------------------------------------------------------------

func send_state(state: Dictionary) -> void:
	## Send the full game state to the Python orchestrator.
	_send_message({
		"jsonrpc": "2.0",
		"method": "state/update",
		"params": {
			"state": state,
		},
		"id": _next_id(),
	})


func send_event(event_name: String, data: Dictionary = {}) -> void:
	## Notify the orchestrator about a game event.
	_send_message({
		"jsonrpc": "2.0",
		"method": "event/notify",
		"params": {
			"event": event_name,
			"data": data,
		},
		"id": _next_id(),
	})


func send_response(request_id: int, result: Dictionary) -> void:
	## Send a response to an orchestrator request.
	_send_message({
		"jsonrpc": "2.0",
		"id": request_id,
		"result": result,
	})


func _send_message(msg: Dictionary) -> void:
	if not is_connected:
		push_warning("MCP: Not connected, cannot send message")
		return
	var json_str: String = JSON.stringify(msg)
	ws.send_text(json_str)


func _next_id() -> int:
	_msg_id += 1
	return _msg_id

# -----------------------------------------------------------------------
# Receiving
# -----------------------------------------------------------------------

func _handle_message(data: String) -> void:
	var json := JSON.new()
	var err := json.parse(data)
	if err != OK:
		push_warning("MCP: Invalid JSON received: %s" % json.get_error_message())
		return

	var msg: Dictionary = json.data
	if not msg is Dictionary:
		push_warning("MCP: Expected Dictionary, got %s" % typeof(msg))
		return

	# If it has a method field, it's a request/notification from the orchestrator
	if msg.has("method"):
		var method: String = msg.get("method", "")
		var params: Dictionary = msg.get("params", {})
		var request_id = msg.get("id", null)

		match method:
			"state/get":
				# Orchestrator wants current state
				if request_id != null:
					send_response(request_id, GameState.to_dict())
			"command/execute":
				# Execute a game command
				_execute_command(params)
				if request_id != null:
					send_response(request_id, {"status": "ok"})
			"ping":
				if request_id != null:
					send_response(request_id, {"pong": true})
			_:
				push_warning("MCP: Unknown method: %s" % method)

		command_received.emit(msg)
		EventBus.mcp_command_received.emit(msg)

	# If it's a response to one of our requests, we mostly just log it
	elif msg.has("result"):
		pass  # Response to our outgoing request
	elif msg.has("error"):
		push_error("MCP: Server error: %s" % str(msg["error"]))

# -----------------------------------------------------------------------
# Command execution
# -----------------------------------------------------------------------

func _execute_command(command: Dictionary) -> void:
	## Execute a command from the Python orchestrator.
	## Commands: spawn_entity, modify_state, trigger_dialogue, start_combat, etc.
	var cmd_type: String = command.get("type", "")

	match cmd_type:
		"spawn_entity":
			_cmd_spawn_entity(command)
		"modify_state":
			_cmd_modify_state(command)
		"trigger_dialogue":
			_cmd_trigger_dialogue(command)
		"start_combat":
			_cmd_start_combat(command)
		"set_flag":
			GameState.set_flag(command.get("key", ""), command.get("value"))
		"add_item":
			GameState.add_item(command.get("item", {}))
		"remove_item":
			GameState.remove_item(command.get("item_id", ""), command.get("count", 1))
		"add_xp":
			GameState.add_xp(command.get("amount", 0))
		"modify_gold":
			GameState.gold += command.get("amount", 0)
		"start_quest":
			GameState.start_quest(command.get("quest", {}))
		"complete_quest":
			GameState.complete_quest(command.get("quest_id", ""))
		"notification":
			EventBus.notification.emit(
				command.get("message", ""),
				command.get("level", "info"),
			)
		"teleport_player":
			_cmd_teleport_player(command)
		_:
			push_warning("MCP: Unknown command type: %s" % cmd_type)


func _cmd_spawn_entity(command: Dictionary) -> void:
	var entity_type: String = command.get("entity_type", "")
	var entity_data: Dictionary = command.get("data", {})
	var pos: Vector2 = Vector2(
		command.get("x", 0.0),
		command.get("y", 0.0),
	)
	# Spawning requires knowing what scene to instantiate
	# For now, emit an event that other systems can handle
	EventBus.mcp_command_received.emit({
		"type": "spawn_entity",
		"entity_type": entity_type,
		"data": entity_data,
		"position": pos,
	})


func _cmd_modify_state(command: Dictionary) -> void:
	var path: String = command.get("path", "")
	var value = command.get("value")
	# Support dot-notation paths like "player_stats.hp"
	var parts: PackedStringArray = path.split(".")
	if parts.size() == 1:
		GameState.set_flag(parts[0], value)
	elif parts.size() == 2 and parts[0] == "player_stats":
		GameState.modify_stat(parts[1], value)


func _cmd_trigger_dialogue(command: Dictionary) -> void:
	var tree_data: Dictionary = command.get("dialogue_tree", {})
	var dialogue_system = get_tree().get_first_node_in_group("dialogue_system")
	if dialogue_system and dialogue_system.has_method("start_dialogue"):
		dialogue_system.start_dialogue(tree_data)


func _cmd_start_combat(command: Dictionary) -> void:
	var encounter: Dictionary = command.get("encounter", {})
	var combat_system = get_tree().get_first_node_in_group("combat_system")
	if combat_system and combat_system.has_method("start_combat"):
		combat_system.start_combat(encounter, [GameState.player_stats])


func _cmd_teleport_player(command: Dictionary) -> void:
	var target_pos := Vector2(
		command.get("x", 0.0),
		command.get("y", 0.0),
	)
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.global_position = target_pos
	GameState.current_location = command.get("location", "")
	EventBus.room_entered.emit(command.get("room_id", ""))
