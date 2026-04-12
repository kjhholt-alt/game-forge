## Comms panel — handler messages, alerts, and social engineering chat.
##
## Bottom-right panel displaying handler communications and system alerts.
extends Control


@onready var message_container: VBoxContainer = $VBox/ScrollContainer/MessageContainer
@onready var scroll_container: ScrollContainer = $VBox/ScrollContainer


const COLOR_NORMAL := Color(0.7, 0.7, 0.7)
const COLOR_WARNING := Color(0.9, 0.7, 0.2)
const COLOR_CRITICAL := Color(0.9, 0.2, 0.2)
const COLOR_HANDLER := Color(0.4, 0.7, 0.9)
const COLOR_SYSTEM := Color(0.35, 0.4, 0.45)
const COLOR_TIMESTAMP := Color(0.25, 0.3, 0.35)

const TYPEWRITER_SPEED := 0.02  # seconds per character


func _ready() -> void:
	EventBus.handler_message.connect(_on_handler_message)
	EventBus.handler_hint.connect(_on_handler_hint)
	EventBus.detection_changed.connect(_on_detection_changed)
	EventBus.file_exfiltrated.connect(_on_file_exfiltrated)
	EventBus.host_connected.connect(_on_host_connected)
	EventBus.analyst_burned.connect(_on_analyst_burned)
	EventBus.phase_changed.connect(_on_phase_changed)
	EventBus.se_secret_revealed.connect(_on_secret_revealed)
	EventBus.evidence_connected.connect(_on_evidence_connected)

	_add_message("SYSTEM", "Comms channel established.", "normal", false)


func _on_handler_message(text: String, priority: String) -> void:
	_add_message("HANDLER", text, priority, true)


func _on_handler_hint(hint_text: String) -> void:
	_add_message("HANDLER", hint_text, "normal", true)


func _on_detection_changed(level: String, _value: float) -> void:
	match level:
		"yellow":
			_add_message("ALERT", "Detection: YELLOW — anomaly flagged.", "warning", false)
		"red":
			_add_message("ALERT", "Detection: RED — active investigation.", "critical", false)
		"black":
			_add_message("ALERT", "DETECTION: BLACK — COVER BLOWN", "critical", false)


func _on_file_exfiltrated(file_id: String) -> void:
	var short_name: String = file_id.get_file() if "/" in file_id else file_id
	_add_message("SYSTEM", "Exfiltrated: %s" % short_name, "normal", false)


func _on_host_connected(host_id: String) -> void:
	var host: Dictionary = OpState.discovered_hosts.get(host_id, {})
	var hostname: String = host.get("hostname", host_id)
	_add_message("SYSTEM", "Shell on %s" % hostname, "normal", false)


func _on_analyst_burned() -> void:
	_add_message("HANDLER", "Link severed. Your cover is blown. Get out.", "critical", true)


func _on_secret_revealed(employee_id: String, secret: String) -> void:
	var op: Dictionary = GameState.get_current_operation()
	var target: Dictionary = op.get("blacksite_target", {})
	var emp_name := employee_id
	for emp in target.get("employees", []):
		if emp.get("id", "") == employee_id:
			emp_name = emp.get("name", employee_id)
			break
	_add_message("INTEL", "%s revealed: %s" % [emp_name, secret], "warning", false)


func _on_evidence_connected(from_id: String, to_id: String, conn_type: String) -> void:
	_add_message("BOARD", "Link: %s -> %s [%s]" % [from_id, to_id, conn_type.to_upper()], "normal", false)


func _on_phase_changed(new_phase: String) -> void:
	match new_phase:
		"briefing":
			_add_message("SYSTEM", "Awaiting briefing.", "normal", false)
		"signal":
			_add_message("HANDLER", "Intercepts are live. Build your picture.", "normal", true)
		"blacksite":
			_add_message("HANDLER", "You're dark. Watch the detection meter.", "warning", true)
		"debrief":
			_add_message("SYSTEM", "Operation complete. Compiling debrief.", "normal", false)


func _add_message(sender: String, text: String, priority: String, typewriter: bool) -> void:
	var label := RichTextLabel.new()
	label.fit_content = true
	label.bbcode_enabled = true
	label.custom_minimum_size = Vector2(0, 24)
	label.add_theme_font_size_override("normal_font_size", 12)

	var color: Color
	match priority:
		"critical": color = COLOR_CRITICAL
		"warning": color = COLOR_WARNING
		_: color = COLOR_NORMAL

	var sender_color: Color
	match sender:
		"HANDLER": sender_color = COLOR_HANDLER
		"ALERT": sender_color = COLOR_CRITICAL
		"INTEL": sender_color = COLOR_WARNING
		"BOARD": sender_color = Color(0.5, 0.5, 0.5)
		_: sender_color = COLOR_SYSTEM

	var time_str := Time.get_time_string_from_system().substr(0, 8)

	var full_text := "[color=#%s]%s[/color] [color=#%s]%s[/color]  %s" % [
		COLOR_TIMESTAMP.to_html(false),
		time_str,
		sender_color.to_html(false),
		sender,
		text,
	]

	if typewriter:
		label.text = ""
		message_container.add_child(label)
		_typewrite(label, full_text)
	else:
		label.text = full_text
		message_container.add_child(label)

	_scroll_to_bottom()


func _typewrite(label: RichTextLabel, full_text: String) -> void:
	# Strip bbcode for character counting, then reveal progressively
	label.text = full_text
	label.visible_ratio = 0.0

	var char_count := full_text.length()
	var duration := char_count * TYPEWRITER_SPEED
	duration = clamp(duration, 0.3, 3.0)

	var tween := create_tween()
	tween.tween_property(label, "visible_ratio", 1.0, duration)


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value
