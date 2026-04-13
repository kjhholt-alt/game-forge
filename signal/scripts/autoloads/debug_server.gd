## Debug server — HTTP server inside the running game for external tool access.
##
## Lets Claude Code (via MCP) take screenshots, click at coordinates,
## read the scene tree, get game state, and simulate input.
##
## Runs on port 9090. Autoloaded.
extends Node


const PORT := 9090
const SCREENSHOT_PATH := "user://debug_screenshot.png"

var _server: TCPServer
var _clients: Array = []


func _ready() -> void:
	_server = TCPServer.new()
	var err := _server.listen(PORT)
	if err != OK:
		push_error("[DebugServer] Failed to listen on port %d: %s" % [PORT, err])
		return
	print("[DebugServer] Listening on http://localhost:%d" % PORT)


func _process(_delta: float) -> void:
	if not _server or not _server.is_listening():
		return

	# Accept new connections
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer:
			_clients.append({"peer": peer, "data": PackedByteArray()})

	# Process existing connections
	for i in range(_clients.size() - 1, -1, -1):
		var client: Dictionary = _clients[i]
		var peer: StreamPeerTCP = client["peer"]
		peer.poll()

		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			var available := peer.get_available_bytes()
			if available > 0:
				var chunk := peer.get_data(available)
				if chunk[0] == OK:
					client["data"].append_array(chunk[1])
					# Check if we have a complete HTTP request (ends with \r\n\r\n)
					var request_str: String = client["data"].get_string_from_utf8()
					if "\r\n\r\n" in request_str:
						_handle_request(peer, request_str)
						_clients.remove_at(i)
		elif peer.get_status() != StreamPeerTCP.STATUS_CONNECTING:
			_clients.remove_at(i)


func _handle_request(peer: StreamPeerTCP, raw: String) -> void:
	# Parse HTTP request line
	var lines := raw.split("\r\n")
	if lines.is_empty():
		_send_response(peer, 400, "Bad Request", "text/plain")
		return

	var request_line := lines[0]
	var parts := request_line.split(" ")
	if parts.size() < 2:
		_send_response(peer, 400, "Bad Request", "text/plain")
		return

	var method := parts[0]
	var full_path := parts[1]

	# Parse path and query string
	var path := full_path
	var query := {}
	if "?" in full_path:
		var split := full_path.split("?", true, 1)
		path = split[0]
		query = _parse_query(split[1])

	# Parse body for POST
	var body := ""
	var body_start := raw.find("\r\n\r\n")
	if body_start >= 0:
		body = raw.substr(body_start + 4)

	# Route
	match path:
		"/health":
			_send_json(peer, {"status": "ok", "game": "signal"})
		"/screenshot":
			_handle_screenshot(peer)
		"/click":
			_handle_click(peer, query)
		"/key":
			_handle_key(peer, query)
		"/tree":
			_handle_tree(peer, query)
		"/state":
			_handle_state(peer)
		"/node":
			_handle_node(peer, query)
		"/select_coa":
			_handle_select_coa(peer, query)
		"/blips":
			_handle_blips(peer)
		"/hud":
			_handle_hud(peer)
		_:
			_send_response(peer, 404, "Not Found: %s" % path, "text/plain")


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------

func _handle_screenshot(peer: StreamPeerTCP) -> void:
	# Capture viewport to PNG
	var img := get_viewport().get_texture().get_image()
	if not img:
		_send_response(peer, 500, "Failed to capture viewport", "text/plain")
		return

	var save_path := OS.get_user_data_dir() + "/debug_screenshot.png"
	img.save_png(save_path)
	_send_json(peer, {"path": save_path, "width": img.get_width(), "height": img.get_height()})


func _handle_click(peer: StreamPeerTCP, query: Dictionary) -> void:
	var x := int(query.get("x", "0"))
	var y := int(query.get("y", "0"))
	var button := int(query.get("button", "1"))  # 1=left, 2=right, 3=middle

	var click_pos := Vector2(x, y)

	# Try COA cards first (they're on top when visible)
	var coa = get_tree().root.get_node_or_null("Main/COACards")
	if coa and coa.visible and coa.has_method("try_click_at"):
		if coa.try_click_at(click_pos):
			_send_json(peer, {"clicked": true, "x": x, "y": y, "button": button, "target": "coa_card"})
			return

	# Try keyboard shortcuts
	var main = get_tree().root.get_node_or_null("Main")

	# Fall through to TacticalMap
	var map_node = get_tree().root.get_node_or_null("Main/TacticalMap")
	if map_node and map_node.has_method("_gui_input"):
		var map_pos: Vector2 = map_node.global_position
		var local := click_pos - map_pos

		var click_event := InputEventMouseButton.new()
		click_event.position = local
		click_event.global_position = click_pos
		click_event.button_index = button
		click_event.pressed = true
		map_node._gui_input(click_event)

		await get_tree().process_frame

		var release := InputEventMouseButton.new()
		release.position = local
		release.global_position = click_pos
		release.button_index = button
		release.pressed = false
		map_node._gui_input(release)

	_send_json(peer, {"clicked": true, "x": x, "y": y, "button": button})


func _handle_key(peer: StreamPeerTCP, query: Dictionary) -> void:
	var keycode := int(query.get("keycode", "0"))
	var key_name: String = query.get("key", "")

	# Map common key names
	if not key_name.is_empty():
		match key_name.to_upper():
			"ENTER": keycode = KEY_ENTER
			"ESCAPE", "ESC": keycode = KEY_ESCAPE
			"TAB": keycode = KEY_TAB
			"SPACE": keycode = KEY_SPACE
			"SLASH": keycode = KEY_SLASH
			"F1": keycode = KEY_F1
			"F12": keycode = KEY_F12

	if keycode == 0:
		_send_response(peer, 400, "No valid keycode", "text/plain")
		return

	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	Input.parse_input_event(press)

	await get_tree().create_timer(0.05).timeout
	var release := InputEventKey.new()
	release.keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)

	_send_json(peer, {"key_sent": true, "keycode": keycode})


func _handle_tree(peer: StreamPeerTCP, query: Dictionary) -> void:
	var max_depth := int(query.get("depth", "3"))
	var root := get_tree().root
	var tree := _node_to_dict(root, 0, max_depth)
	_send_json(peer, tree)


func _handle_state(peer: StreamPeerTCP) -> void:
	# Collect game state from all autoloads
	var state := {}

	# GameState
	if has_node("/root/GameState"):
		var gs = get_node("/root/GameState")
		state["phase"] = gs.get("current_phase") if gs.get("current_phase") else "unknown"
		state["campaign_loaded"] = gs.get("campaign_loaded") if gs.get("campaign_loaded") else false

	# OpState
	if has_node("/root/OpState"):
		var ops = get_node("/root/OpState")
		state["detection"] = ops.get("detection_value") if ops.get("detection_value") != null else 0.0
		state["detection_level"] = ops.get("detection_level") if ops.get("detection_level") else "green"
		state["exfiltrated_files"] = ops.get("exfiltrated_files").size() if ops.get("exfiltrated_files") else 0

	# VoiceHandler
	if has_node("/root/VoiceHandler"):
		state["voice_enabled"] = true

	state["fps"] = Engine.get_frames_per_second()
	state["time"] = Time.get_ticks_msec() / 1000.0

	_send_json(peer, state)


func _handle_node(peer: StreamPeerTCP, query: Dictionary) -> void:
	var node_path: String = query.get("path", "")
	if node_path.is_empty():
		_send_response(peer, 400, "Missing 'path' parameter", "text/plain")
		return

	var node := get_tree().root.get_node_or_null(node_path)
	if not node:
		_send_json(peer, {"error": "Node not found: %s" % node_path})
		return

	var info := {
		"name": node.name,
		"class": node.get_class(),
		"path": str(node.get_path()),
		"visible": node.get("visible") if node.get("visible") != null else true,
		"children": node.get_child_count(),
	}

	# Position for Control nodes
	if node is Control:
		info["position"] = {"x": node.position.x, "y": node.position.y}
		info["size"] = {"w": node.size.x, "h": node.size.y}
		info["visible"] = node.visible

	# Position for Node2D
	if node is Node2D:
		info["position"] = {"x": node.position.x, "y": node.position.y}

	_send_json(peer, info)


func _handle_select_coa(peer: StreamPeerTCP, query: Dictionary) -> void:
	var index := int(query.get("index", "0"))
	var coa = get_tree().root.get_node_or_null("Main/COACards")
	if coa and coa.has_method("select_by_index"):
		var ok: bool = coa.select_by_index(index)
		_send_json(peer, {"selected": ok, "index": index})
	else:
		_send_json(peer, {"error": "COACards not found"})


func _handle_blips(peer: StreamPeerTCP) -> void:
	# Get blip data from the tactical map
	var map_node = get_tree().root.get_node_or_null("Main/TacticalMap")
	if not map_node:
		_send_json(peer, {"error": "TacticalMap not found"})
		return

	var blips_data := []
	var map_offset: Vector2 = map_node.global_position
	for blip in map_node._blips.values():
		var map_local: Vector2 = map_node._world_to_screen(blip.pos)
		var viewport_pos: Vector2 = map_local + map_offset
		blips_data.append({
			"id": blip.id,
			"type": blip.blip_type,
			"label": blip.label,
			"world_x": blip.pos.x,
			"world_y": blip.pos.y,
			"classified": blip.classified,
			"busy": blip.busy,
			"viewport_x": viewport_pos.x,
			"viewport_y": viewport_pos.y,
			"map_local_x": map_local.x,
			"map_local_y": map_local.y,
		})

	_send_json(peer, {"blips": blips_data, "count": blips_data.size()})


func _handle_hud(peer: StreamPeerTCP) -> void:
	var hud_node = get_tree().root.get_node_or_null("Main/HUD")
	if not hud_node:
		_send_json(peer, {"error": "HUD not found"})
		return

	var info := {}
	var codename = hud_node.get_node_or_null("TopBar/Codename")
	if codename:
		info["codename"] = codename.text
	var budget = hud_node.get_node_or_null("TopBar/BudgetLabel")
	if budget:
		info["budget"] = budget.text
	var timer = hud_node.get_node_or_null("TopBar/TimerLabel")
	if timer:
		info["timer"] = timer.text
	var objective = hud_node.get_node_or_null("TopBar/ObjectiveLabel")
	if objective:
		info["objective"] = objective.text

	_send_json(peer, info)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _node_to_dict(node: Node, depth: int, max_depth: int) -> Dictionary:
	var d := {
		"name": node.name,
		"class": node.get_class(),
	}
	if node is Control:
		d["visible"] = node.visible
	if depth < max_depth:
		var children := []
		for child in node.get_children():
			children.append(_node_to_dict(child, depth + 1, max_depth))
		if not children.is_empty():
			d["children"] = children
	elif node.get_child_count() > 0:
		d["child_count"] = node.get_child_count()
	return d


func _parse_query(query_string: String) -> Dictionary:
	var result := {}
	for pair in query_string.split("&"):
		var kv := pair.split("=", true, 1)
		if kv.size() == 2:
			result[kv[0]] = kv[1].uri_decode()
		elif kv.size() == 1:
			result[kv[0]] = ""
	return result


func _send_json(peer: StreamPeerTCP, data: Variant) -> void:
	var json_str := JSON.stringify(data)
	_send_response(peer, 200, json_str, "application/json")


func _send_response(peer: StreamPeerTCP, code: int, body: String, content_type: String) -> void:
	var status_text := "OK" if code == 200 else "Error"
	var response := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n%s" % [
		code, status_text, content_type, body.length(), body,
	]
	peer.put_data(response.to_utf8_buffer())
