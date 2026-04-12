## Comms panel — handler messages, alerts, and social engineering chat.
##
## Bottom-right panel displaying handler communications and system alerts.
## During BLACKSITE, also shows social engineering conversation UI.
extends Control


@onready var message_container: VBoxContainer = $ScrollContainer/MessageContainer
@onready var scroll_container: ScrollContainer = $ScrollContainer


const COLOR_NORMAL := Color(0.7, 0.7, 0.7)
const COLOR_WARNING := Color(0.9, 0.7, 0.2)
const COLOR_CRITICAL := Color(0.9, 0.2, 0.2)
const COLOR_HANDLER := Color(0.4, 0.7, 0.9)
const COLOR_SYSTEM := Color(0.5, 0.5, 0.5)


func _ready() -> void:
	EventBus.handler_message.connect(_on_handler_message)
	EventBus.handler_hint.connect(_on_handler_hint)
	EventBus.detection_changed.connect(_on_detection_changed)
	EventBus.file_exfiltrated.connect(_on_file_exfiltrated)
	EventBus.host_connected.connect(_on_host_connected)
	EventBus.analyst_burned.connect(_on_analyst_burned)
	EventBus.phase_changed.connect(_on_phase_changed)

	_add_message("HANDLER", "System online. Awaiting operation briefing.", "normal")


func _on_handler_message(text: String, priority: String) -> void:
	_add_message("HANDLER", text, priority)


func _on_handler_hint(hint_text: String) -> void:
	_add_message("HANDLER", "[HINT] " + hint_text, "normal")


func _on_detection_changed(level: String, value: float) -> void:
	match level:
		"yellow":
			_add_message("SYSTEM", "Detection level: YELLOW — anomaly flagged on target network.", "warning")
		"red":
			_add_message("SYSTEM", "Detection level: RED — active investigation in progress. Proceed with caution.", "critical")
		"black":
			_add_message("SYSTEM", "DETECTION LEVEL: BLACK — COVER BLOWN", "critical")


func _on_file_exfiltrated(file_id: String) -> void:
	_add_message("SYSTEM", "File exfiltrated: %s" % file_id, "normal")


func _on_host_connected(host_id: String) -> void:
	var host: Dictionary = OpState.discovered_hosts.get(host_id, {})
	var hostname: String = host.get("hostname", host_id)
	_add_message("SYSTEM", "Connected to %s" % hostname, "normal")


func _on_analyst_burned() -> void:
	_add_message("HANDLER", "We've lost the link. Your cover is blown. Get out.", "critical")


func _on_phase_changed(new_phase: String) -> void:
	match new_phase:
		"briefing":
			_add_message("HANDLER", "New operation briefing incoming.", "normal")
		"signal":
			_add_message("HANDLER", "Intercepts are coming in. Start building your picture.", "normal")
		"blacksite":
			_add_message("HANDLER", "You're dark. Terminal access granted. Watch the detection meter.", "warning")
		"debrief":
			_add_message("HANDLER", "Operation complete. Compiling debrief.", "normal")


func _add_message(sender: String, text: String, priority: String) -> void:
	"""Add a styled message to the comms panel."""
	var label := RichTextLabel.new()
	label.fit_content = true
	label.bbcode_enabled = true
	label.custom_minimum_size = Vector2(0, 30)

	var color: Color
	match priority:
		"critical": color = COLOR_CRITICAL
		"warning": color = COLOR_WARNING
		_: color = COLOR_NORMAL

	var sender_color: Color = COLOR_HANDLER if sender == "HANDLER" else COLOR_SYSTEM
	var time_str := Time.get_time_string_from_system()

	label.text = "[color=#%s]%s[/color] [color=#%s][%s][/color] %s" % [
		color.to_html(false),
		time_str.substr(0, 5),
		sender_color.to_html(false),
		sender,
		text,
	]

	message_container.add_child(label)

	# Auto-scroll to bottom
	await get_tree().process_frame
	scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value
