## Social engineering chat UI — conversation interface for BLACKSITE.
##
## Modal panel that overlays the dashboard when the player initiates
## conversation with a target employee. Shows employee profile on the
## left, chat messages on the right.
extends Control


@onready var employee_name_label: Label = $Panel/HSplit/ProfilePanel/VBox/NameLabel
@onready var employee_role_label: Label = $Panel/HSplit/ProfilePanel/VBox/RoleLabel
@onready var employee_traits_label: RichTextLabel = $Panel/HSplit/ProfilePanel/VBox/TraitsText
@onready var trust_bar: ProgressBar = $Panel/HSplit/ProfilePanel/VBox/TrustBar
@onready var suspicion_bar: ProgressBar = $Panel/HSplit/ProfilePanel/VBox/SuspicionBar
@onready var trust_label: Label = $Panel/HSplit/ProfilePanel/VBox/TrustLabel
@onready var suspicion_label: Label = $Panel/HSplit/ProfilePanel/VBox/SuspicionLabel

@onready var chat_scroll: ScrollContainer = $Panel/HSplit/ChatPanel/VBox/ChatScroll
@onready var chat_container: VBoxContainer = $Panel/HSplit/ChatPanel/VBox/ChatScroll/ChatContainer
@onready var chat_input: LineEdit = $Panel/HSplit/ChatPanel/VBox/InputRow/ChatInput
@onready var send_button: Button = $Panel/HSplit/ChatPanel/VBox/InputRow/SendButton
@onready var close_button: Button = $Panel/Header/CloseButton

var _current_employee: Dictionary = {}
var _employee_id: String = ""


func _ready() -> void:
	visible = false
	send_button.pressed.connect(_on_send)
	chat_input.text_submitted.connect(func(_t): _on_send())
	close_button.pressed.connect(_on_close)
	EventBus.se_conversation_started.connect(_on_conversation_started)


func _on_conversation_started(employee_id: String) -> void:
	# Find employee in current operation
	var op: Dictionary = GameState.get_current_operation()
	var target: Dictionary = op.get("blacksite_target", {})
	for emp in target.get("employees", []):
		if emp.get("id", "") == employee_id:
			_current_employee = emp
			_employee_id = employee_id
			_show_chat()
			return


func _show_chat() -> void:
	visible = true

	# Populate profile
	employee_name_label.text = _current_employee.get("name", "Unknown")
	employee_role_label.text = _current_employee.get("role", "")

	var traits: Array = _current_employee.get("personality_traits", [])
	employee_traits_label.text = "[color=#888888]%s[/color]" % ", ".join(traits)

	_update_bars()

	# Clear chat
	for child in chat_container.get_children():
		child.queue_free()

	# Initial greeting
	var speech: String = _current_employee.get("speech_pattern", "professional")
	var name: String = _current_employee.get("name", "Unknown").split(" ")[0]
	_add_npc_message("Hi, can I help you? I'm %s from %s." % [
		name,
		_current_employee.get("department", "the office"),
	])

	chat_input.grab_focus()


func _on_send() -> void:
	var msg: String = chat_input.text.strip_edges()
	chat_input.clear()
	if msg.is_empty():
		return

	_add_player_message(msg)
	EventBus.se_message_sent.emit(_employee_id, msg)

	# Simple keyword-based response system (placeholder for NobodyWho)
	await get_tree().create_timer(0.5 + randf() * 1.0).timeout
	_process_response(msg)


func _process_response(player_msg: String) -> void:
	var state: Dictionary = OpState.employee_states.get(_employee_id, {})
	var trust: int = state.get("trust", 0)
	var suspicion: int = state.get("suspicion", 0)
	var msg_lower := player_msg.to_lower()

	var response := ""
	var trust_delta := 0
	var suspicion_delta := 0

	# Check against knowledge set for relevant responses
	var knowledge: Array = _current_employee.get("knowledge_set", [])
	var secrets: Array = _current_employee.get("secrets", [])
	var threshold: int = _current_employee.get("trust_threshold", 5)

	# Friendly/empathetic approach builds trust
	if "help" in msg_lower or "busy" in msg_lower or "hard" in msg_lower or "appreciate" in msg_lower or "thanks" in msg_lower:
		trust_delta = 1
		response = _get_friendly_response()
	# Direct questions about systems raise suspicion but may reveal info
	elif "password" in msg_lower or "credential" in msg_lower or "login" in msg_lower:
		suspicion_delta = 2
		if trust >= threshold:
			# Trust is high enough — reveal a secret
			response = _reveal_secret(state)
		else:
			response = "I... probably shouldn't share that. Why do you need it?"
			suspicion_delta = 3
	# Questions about the target person (Mitchell)
	elif "mitchell" in msg_lower or "jack" in msg_lower:
		trust_delta = 0
		if trust >= 2:
			response = _get_mitchell_response(knowledge)
		else:
			response = "Mr. Mitchell? He's the VP of Operations, third floor. What's this about?"
	# Server/network questions
	elif "server" in msg_lower or "network" in msg_lower or "backup" in msg_lower:
		suspicion_delta = 1
		if trust >= threshold:
			response = _reveal_secret(state)
		elif trust >= 2:
			response = _get_technical_response(knowledge)
		else:
			response = "Are you from IT? I haven't seen you before."
			suspicion_delta = 2
	# Helios / shipping questions
	elif "helios" in msg_lower or "shipping" in msg_lower or "container" in msg_lower:
		suspicion_delta = 1
		if trust >= 3:
			response = _get_helios_response(knowledge)
		else:
			response = "That's... kind of specific. Who did you say you were with again?"
			suspicion_delta = 2
	# Generic conversation
	else:
		trust_delta = 1
		response = _get_generic_response()

	# Apply SE skill modifier
	var se_level: int = GameState.get_skill_level("social_engineering")
	if se_level > 1:
		trust_delta += 1  # Bonus trust per interaction

	# Update state
	state["trust"] = clamp(trust + trust_delta, 0, 10)
	state["suspicion"] = clamp(suspicion + suspicion_delta, 0, 10)
	OpState.employee_states[_employee_id] = state

	if suspicion_delta > 0 and state["suspicion"] >= 7:
		OpState.add_detection("se_suspicious")

	_add_npc_message(response)
	_update_bars()
	EventBus.se_response_received.emit(_employee_id, response, trust_delta, suspicion_delta > 0)

	GameState.add_xp("social_engineering", 5)


func _reveal_secret(state: Dictionary) -> String:
	var secrets: Array = _current_employee.get("secrets", [])
	var revealed: Array = state.get("secrets_revealed", [])

	for secret in secrets:
		if secret not in revealed:
			revealed.append(secret)
			state["secrets_revealed"] = revealed
			OpState.employee_states[_employee_id] = state
			EventBus.se_secret_revealed.emit(_employee_id, secret)
			return "Look, between us... %s" % secret

	return "I've told you everything I know. Really."


func _get_friendly_response() -> String:
	var responses := [
		"Yeah, it's been a crazy week. Thanks for understanding.",
		"I appreciate that. Not everyone around here does.",
		"You seem alright. What did you need?",
		"Ha, tell me about it. This place keeps me busy.",
	]
	return responses[randi() % responses.size()]


func _get_mitchell_response(knowledge: Array) -> String:
	for k in knowledge:
		if "mitchell" in k.to_lower() or "jack" in k.to_lower():
			return k
	return "He's been working late a lot recently. Seemed stressed."


func _get_technical_response(knowledge: Array) -> String:
	for k in knowledge:
		if "server" in k.to_lower() or "ip" in k.to_lower() or "backup" in k.to_lower():
			return "Well, I can tell you that %s" % k.to_lower()
	return "The systems have been running fine since the migration."


func _get_helios_response(knowledge: Array) -> String:
	for k in knowledge:
		if "helios" in k.to_lower() or "logist" in k.to_lower():
			return k
	return "I've seen the name in the system. Mitchell added those entries himself."


func _get_generic_response() -> String:
	var responses := [
		"Mm-hmm. Yeah.",
		"Sure, makes sense.",
		"Right. Anything else?",
		"I see what you mean.",
		"Okay.",
	]
	return responses[randi() % responses.size()]


func _add_player_message(text: String) -> void:
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.custom_minimum_size = Vector2(0, 30)
	lbl.text = "[right][color=#66aaff]YOU:[/color] %s[/right]" % text
	chat_container.add_child(lbl)
	await get_tree().process_frame
	chat_scroll.scroll_vertical = chat_scroll.get_v_scroll_bar().max_value


func _add_npc_message(text: String) -> void:
	var name: String = _current_employee.get("name", "NPC").split(" ")[0].to_upper()
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.custom_minimum_size = Vector2(0, 30)
	lbl.text = "[color=#88cc88]%s:[/color] %s" % [name, text]
	chat_container.add_child(lbl)
	await get_tree().process_frame
	chat_scroll.scroll_vertical = chat_scroll.get_v_scroll_bar().max_value


func _update_bars() -> void:
	var state: Dictionary = OpState.employee_states.get(_employee_id, {})
	var trust: int = state.get("trust", 0)
	var suspicion: int = state.get("suspicion", 0)
	var threshold: int = _current_employee.get("trust_threshold", 5)

	trust_bar.max_value = 10
	trust_bar.value = trust
	trust_label.text = "TRUST: %d / %d (need %d)" % [trust, 10, threshold]

	var trust_fill := StyleBoxFlat.new()
	trust_fill.bg_color = Color(0.2, 0.7, 0.4) if trust >= threshold else Color(0.3, 0.5, 0.6)
	trust_fill.set_corner_radius_all(2)
	trust_bar.add_theme_stylebox_override("fill", trust_fill)

	suspicion_bar.max_value = 10
	suspicion_bar.value = suspicion
	suspicion_label.text = "SUSPICION: %d / 10" % suspicion

	var susp_fill := StyleBoxFlat.new()
	if suspicion >= 7:
		susp_fill.bg_color = Color(0.9, 0.2, 0.2)
	elif suspicion >= 4:
		susp_fill.bg_color = Color(0.9, 0.6, 0.2)
	else:
		susp_fill.bg_color = Color(0.4, 0.4, 0.4)
	susp_fill.set_corner_radius_all(2)
	suspicion_bar.add_theme_stylebox_override("fill", susp_fill)


func _on_close() -> void:
	visible = false
	EventBus.se_conversation_ended.emit(_employee_id)
