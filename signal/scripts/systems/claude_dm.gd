## Claude DM — runtime AI integration for handler, intel, debrief, advisory.
##
## Calls the Python DM server via HTTP. Falls back to pre-written lines
## if the server is unavailable (offline mode).
extends Node


const SERVER_URL := "http://localhost:8090"
var _server_online := false
var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)

	# Check if server is running
	_check_server()


func _check_server() -> void:
	var check := HTTPRequest.new()
	add_child(check)
	check.request_completed.connect(func(result, code, _h, _b):
		_server_online = (code == 200)
		if _server_online:
			print("[ClaudeDM] Server online at %s" % SERVER_URL)
		else:
			print("[ClaudeDM] Server offline — using fallback lines")
		check.queue_free()
	)
	check.request(SERVER_URL + "/health")


# ---------------------------------------------------------------------------
# Public API — each returns the handler text to speak
# ---------------------------------------------------------------------------

func get_handler_commentary(action: String, game_state: Dictionary, callback: Callable) -> void:
	if not _server_online:
		callback.call("")  # Empty = use fallback
		return

	var body := JSON.stringify({"action": action, "game_state": game_state})
	_post("/handler", body, func(response: Dictionary):
		callback.call(response.get("text", ""))
	)


func get_intel_assessment(blip_data: Dictionary, game_state: Dictionary, callback: Callable) -> void:
	if not _server_online:
		callback.call("")
		return

	var body := JSON.stringify({"blip_data": blip_data, "game_state": game_state})
	_post("/intel", body, func(response: Dictionary):
		callback.call(response.get("text", ""))
	)


func get_debrief(mission_summary: Dictionary, callback: Callable) -> void:
	if not _server_online:
		callback.call("")
		return

	var body := JSON.stringify({"mission_summary": mission_summary})
	_post("/debrief", body, func(response: Dictionary):
		callback.call(response.get("text", ""))
	)


func get_advice(game_state: Dictionary, callback: Callable) -> void:
	if not _server_online:
		callback.call("No advisory available offline.")
		return

	var body := JSON.stringify({"game_state": game_state})
	_post("/advise", body, func(response: Dictionary):
		callback.call(response.get("text", ""))
	)


func interrogate(npc_data: Dictionary, approach: String, trust: int, turn: int, callback: Callable) -> void:
	if not _server_online:
		callback.call({"text": "No response.", "revealed": ""})
		return

	var body := JSON.stringify({
		"npc_data": npc_data,
		"approach": approach,
		"trust": trust,
		"turn": turn,
	})
	_post("/interrogate", body, func(response: Dictionary):
		callback.call(response)
	)


func generate_mission(previous_missions: Array, player_style: Dictionary, budget: int, owned_assets: Array, callback: Callable) -> void:
	if not _server_online:
		callback.call({})
		return

	var body := JSON.stringify({
		"previous_missions": previous_missions,
		"player_style": player_style,
		"budget": budget,
		"owned_assets": owned_assets,
	})
	_post("/generate_mission", body, func(response: Dictionary):
		callback.call(response.get("mission", {}))
	)


func is_online() -> bool:
	return _server_online


# ---------------------------------------------------------------------------
# HTTP helper
# ---------------------------------------------------------------------------

func _post(endpoint: String, body: String, callback: Callable) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, response_body: PackedByteArray):
		var response := {}
		if code == 200:
			var json := JSON.new()
			if json.parse(response_body.get_string_from_utf8()) == OK:
				response = json.data
		callback.call(response)
		req.queue_free()
	)
	req.request(
		SERVER_URL + endpoint,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		body,
	)
