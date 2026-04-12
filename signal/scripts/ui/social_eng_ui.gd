## Social Engineering UI — employee chat modal with trust/suspicion mechanics.
##
## Keyword-based dialogue system. Build trust → reveal secrets.
## Opened via terminal "talk" command or button.
extends Control


const C_MODAL_BG := Color(0.035, 0.04, 0.055, 0.98)
const C_BORDER := Color(0.15, 0.2, 0.3)
const C_PLAYER_BG := Color(0.08, 0.12, 0.18)
const C_NPC_BG := Color(0.06, 0.07, 0.1)
const C_TRUST := Color(0.2, 0.8, 0.4)
const C_SUSPICION := Color(0.9, 0.3, 0.2)
const C_SECRET := Color(0.95, 0.8, 0.2)
const C_HEADER := Color(0.04, 0.05, 0.07)
const C_TEXT := Color(0.75, 0.8, 0.85)
const C_DIM := Color(0.45, 0.5, 0.58)

# Keyword categories
const KW_SMALLTALK := ["how are you", "busy", "long day", "weather", "weekend", "thanks", "appreciate", "hello", "hey", "hi", "good morning"]
const KW_WORK := ["server", "network", "system", "computer", "security", "IT", "database", "backup", "firewall", "migration"]
const KW_PROBE := ["password", "credentials", "login", "access", "confidential", "secret", "mitchell", "helios", "shipping", "container", "petrov"]
const KW_AGGRESSIVE := ["tell me", "you must", "i need you to", "now", "immediately", "or else", "demand", "answer me"]
const KW_VULNERABILITY := ["help", "workload", "overtime", "stressed", "too much", "overworked", "burned out", "appreciate", "tough job"]

# Response templates by personality style
const RESPONSES := {
	"tech_professional": {
		"smalltalk": [
			"Yeah, it's been crazy. Three tickets already this morning.",
			"Not bad, just another day in IT, you know?",
			"Ha, don't get me started. The exchange server went down at 2am.",
			"Could be worse. At least the coffee machine works today.",
		],
		"work": [
			"Oh sure, I can tell you about that. What specifically?",
			"Yeah, I manage most of that infrastructure. It's a lot.",
			"We just did a big migration last week actually.",
			"The security team runs nightly scans at 2am. Keep that in mind.",
		],
		"probe_low": [
			"Um, I can't really share that kind of info...",
			"That's... not something I should be discussing.",
			"Look, I'd like to help, but that's above my pay grade.",
			"I don't think I'm supposed to talk about that.",
		],
		"aggressive": [
			"Whoa, okay. Calm down. I don't respond well to pressure.",
			"I think we're done here. I don't appreciate the tone.",
			"That's not how you get information from me.",
		],
		"vulnerability": [
			"God, tell me about it. I've been pulling doubles all month.",
			"You actually get it? Nobody around here understands the workload.",
			"Honestly? Thanks for saying that. It means something.",
		],
		"fallback": [
			"Hmm, I'm not sure what you mean.",
			"Can you be more specific?",
			"I don't know about that, sorry.",
		],
	},
	"friendly_guard": {
		"smalltalk": [
			"Hey! Yeah man, another day right? Haha.",
			"Doing good, doing good. Quiet morning so far.",
			"Can't complain! Well, I could, but who'd listen? Heh.",
			"Oh you know, same old. I'm just here watching the door.",
		],
		"work": [
			"Oh yeah, the server room? That's down in B1. Need a special keycard though.",
			"Mr. Mitchell? VP of Operations, corner office on 3. Nice guy, busy though.",
			"Rachel in IT? She's always here late. Poor thing works too hard.",
			"The building has keycard access on all the exterior doors.",
		],
		"probe_low": [
			"Uhh I dunno about that stuff, I just work the desk y'know?",
			"Hmm, that's not really my area. I'm just security.",
			"I probably shouldn't say anything about that...",
		],
		"aggressive": [
			"Hey man, easy. I'm trying to be helpful here.",
			"Whoa, that's not cool. I don't have to tell you anything.",
			"Alright buddy, I think this conversation is over.",
		],
		"vulnerability": [
			"Yeah it gets boring here sometimes, not gonna lie.",
			"Thanks man, most people just walk past without saying hi.",
			"You're alright, you know that? Most folks don't even notice me.",
		],
		"fallback": [
			"Hmm, beats me!",
			"I'm not sure about that one, sorry.",
			"Not really my department, ha.",
		],
	},
}

var _employee_data: Dictionary = {}
var _employee_id: String = ""
var _trust: int = 0
var _suspicion: int = 0
var _secrets_revealed: Array = []
var _knowledge_index: int = 0
var _chat_log: RichTextLabel
var _input: LineEdit
var _trust_bar: ProgressBar
var _suspicion_bar: ProgressBar
var _secrets_list: VBoxContainer
var _name_label: Label
var _role_label: Label
var _traits_label: Label
var _backdrop: ColorRect
var _modal: PanelContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func open_chat(employee_id: String) -> void:
	_employee_id = employee_id
	_employee_data = OpState.get_employee(employee_id)
	if _employee_data.is_empty():
		push_error("Employee not found: %s" % employee_id)
		return

	# Restore state from OpState
	var state: Dictionary = OpState.employee_states.get(employee_id, {})
	_trust = state.get("trust", 0)
	_suspicion = state.get("suspicion", 0)
	_secrets_revealed = state.get("secrets_revealed", []).duplicate()
	_knowledge_index = 0

	_build_ui()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Opening message
	var name_str: String = _employee_data.get("name", "Unknown")
	_add_system_msg("Connected to %s — %s" % [name_str, _employee_data.get("role", "")])
	_add_npc_msg(_get_greeting())
	VoiceHandler.speak("You're talking to %s. Tread carefully." % name_str)

	_input.grab_focus()


func close_chat() -> void:
	# Save state back
	OpState.employee_states[_employee_id] = {
		"trust": _trust,
		"suspicion": _suspicion,
		"secrets_revealed": _secrets_revealed,
	}
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Clean up UI
	for child in get_children():
		child.queue_free()


func _build_ui() -> void:
	# Clear previous UI
	for child in get_children():
		child.queue_free()

	# Backdrop
	_backdrop = ColorRect.new()
	_backdrop.anchors_preset = Control.PRESET_FULL_RECT
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.6)
	_backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			close_chat()
	)
	add_child(_backdrop)

	# Modal panel
	_modal = PanelContainer.new()
	_modal.anchors_preset = Control.PRESET_CENTER
	_modal.offset_left = -380
	_modal.offset_top = -270
	_modal.offset_right = 380
	_modal.offset_bottom = 270
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_MODAL_BG
	sb.border_color = C_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	_modal.add_theme_stylebox_override("panel", sb)
	add_child(_modal)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)

	# Header
	var header := _build_header()
	vbox.add_child(header)

	# Content area: chat + profile
	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 0)

	# Chat panel (left 65%)
	var chat_panel := _build_chat_panel()
	chat_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_panel.size_flags_stretch_ratio = 0.65
	hbox.add_child(chat_panel)

	# Profile panel (right 35%)
	var profile_panel := _build_profile_panel()
	profile_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_panel.size_flags_stretch_ratio = 0.35
	hbox.add_child(profile_panel)

	vbox.add_child(hbox)

	# Input bar
	var input_bar := _build_input_bar()
	vbox.add_child(input_bar)

	_modal.add_child(vbox)


func _build_header() -> PanelContainer:
	var panel := PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = C_HEADER
	hsb.border_color = C_BORDER
	hsb.border_width_bottom = 1
	hsb.content_margin_left = 16
	hsb.content_margin_right = 16
	hsb.content_margin_top = 10
	hsb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", hsb)

	var hbox := HBoxContainer.new()

	_name_label = Label.new()
	_name_label.text = _employee_data.get("name", "Unknown")
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.add_theme_color_override("font_color", C_TEXT)
	hbox.add_child(_name_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	_role_label = Label.new()
	_role_label.text = "%s — %s" % [_employee_data.get("role", ""), _employee_data.get("department", "")]
	_role_label.add_theme_font_size_override("font_size", 11)
	_role_label.add_theme_color_override("font_color", C_DIM)
	hbox.add_child(_role_label)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(16, 0)
	hbox.add_child(spacer2)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.pressed.connect(close_chat)
	hbox.add_child(close_btn)

	panel.add_child(hbox)
	return panel


func _build_chat_panel() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)

	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.add_theme_color_override("default_color", C_TEXT)
	_chat_log.add_theme_font_size_override("normal_font_size", 12)
	vbox.add_child(_chat_log)

	return vbox


func _build_profile_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.03, 0.035, 0.05, 0.95)
	psb.border_color = C_BORDER
	psb.border_width_left = 1
	psb.content_margin_left = 12
	psb.content_margin_right = 12
	psb.content_margin_top = 12
	psb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", psb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	# Photo description
	var photo := Label.new()
	photo.text = _employee_data.get("photo_description", "No photo available.")
	photo.add_theme_font_size_override("font_size", 10)
	photo.add_theme_color_override("font_color", C_DIM)
	photo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(photo)

	# Trust bar
	var trust_header := Label.new()
	trust_header.text = "TRUST"
	trust_header.add_theme_font_size_override("font_size", 10)
	trust_header.add_theme_color_override("font_color", C_DIM)
	vbox.add_child(trust_header)

	_trust_bar = ProgressBar.new()
	_trust_bar.min_value = 0
	_trust_bar.max_value = _employee_data.get("trust_threshold", 3)
	_trust_bar.value = _trust
	_trust_bar.show_percentage = false
	_trust_bar.custom_minimum_size = Vector2(0, 10)
	var tf := StyleBoxFlat.new()
	tf.bg_color = C_TRUST
	tf.set_corner_radius_all(2)
	_trust_bar.add_theme_stylebox_override("fill", tf)
	vbox.add_child(_trust_bar)

	# Suspicion bar
	var susp_header := Label.new()
	susp_header.text = "SUSPICION"
	susp_header.add_theme_font_size_override("font_size", 10)
	susp_header.add_theme_color_override("font_color", C_DIM)
	vbox.add_child(susp_header)

	_suspicion_bar = ProgressBar.new()
	_suspicion_bar.min_value = 0
	_suspicion_bar.max_value = 5
	_suspicion_bar.value = _suspicion
	_suspicion_bar.show_percentage = false
	_suspicion_bar.custom_minimum_size = Vector2(0, 10)
	var sf := StyleBoxFlat.new()
	sf.bg_color = C_SUSPICION
	sf.set_corner_radius_all(2)
	_suspicion_bar.add_theme_stylebox_override("fill", sf)
	vbox.add_child(_suspicion_bar)

	# Traits
	_traits_label = Label.new()
	var traits: Array = _employee_data.get("personality_traits", [])
	_traits_label.text = "Traits: %s" % ", ".join(traits)
	_traits_label.add_theme_font_size_override("font_size", 10)
	_traits_label.add_theme_color_override("font_color", C_DIM)
	_traits_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_traits_label)

	# Secrets revealed
	var sec_header := Label.new()
	sec_header.text = "SECRETS REVEALED"
	sec_header.add_theme_font_size_override("font_size", 10)
	sec_header.add_theme_color_override("font_color", C_SECRET)
	vbox.add_child(sec_header)

	_secrets_list = VBoxContainer.new()
	_secrets_list.add_theme_constant_override("separation", 4)
	for s in _secrets_revealed:
		_add_secret_to_list(s)
	vbox.add_child(_secrets_list)

	panel.add_child(vbox)
	return panel


func _build_input_bar() -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)

	var bar_bg := PanelContainer.new()
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0.03, 0.035, 0.05)
	isb.border_color = C_BORDER
	isb.border_width_top = 1
	isb.content_margin_left = 12
	isb.content_margin_right = 8
	isb.content_margin_top = 8
	isb.content_margin_bottom = 8
	bar_bg.add_theme_stylebox_override("panel", isb)
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var inner_hbox := HBoxContainer.new()

	_input = LineEdit.new()
	_input.placeholder_text = "Type a message..."
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.add_theme_color_override("font_color", C_TEXT)
	_input.add_theme_font_size_override("font_size", 13)
	_input.text_submitted.connect(_on_input_submitted)
	inner_hbox.add_child(_input)

	var send_btn := Button.new()
	send_btn.text = "SEND"
	send_btn.pressed.connect(func(): _on_input_submitted(_input.text))
	inner_hbox.add_child(send_btn)

	bar_bg.add_child(inner_hbox)
	hbox.add_child(bar_bg)
	return hbox


# ===========================================================================
# Message handling
# ===========================================================================

func _on_input_submitted(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		return
	_input.text = ""

	_add_player_msg(text)
	_process_input(text)
	_input.grab_focus()


func _process_input(text: String) -> void:
	var lower := text.to_lower()
	var style := _get_response_style()

	# Check categories in priority order
	if _matches_any(lower, KW_AGGRESSIVE):
		_handle_aggressive(style)
	elif _matches_any(lower, KW_PROBE):
		_handle_probe(style)
	elif _matches_any(lower, KW_VULNERABILITY):
		_handle_vulnerability(style)
	elif _matches_any(lower, KW_WORK):
		_handle_work(style)
	elif _matches_any(lower, KW_SMALLTALK):
		_handle_smalltalk(style)
	else:
		_handle_fallback(style)

	_update_bars()
	_check_suspicion()


func _handle_smalltalk(style: String) -> void:
	_trust = min(_trust + 1, 10)
	_add_npc_msg(_pick_response(style, "smalltalk"))
	EventBus.se_trust_changed.emit(_employee_id, _trust)


func _handle_work(style: String) -> void:
	_trust = min(_trust + 1, 10)
	var knowledge: Array = _employee_data.get("knowledge_set", [])
	if not knowledge.is_empty() and _knowledge_index < knowledge.size():
		var info: String = knowledge[_knowledge_index]
		_knowledge_index = (_knowledge_index + 1) % knowledge.size()
		_add_npc_msg(_pick_response(style, "work"))
		_add_system_msg("[color=#6688aa]Intel: %s[/color]" % info)
	else:
		_add_npc_msg(_pick_response(style, "work"))
	EventBus.se_trust_changed.emit(_employee_id, _trust)


func _handle_probe(style: String) -> void:
	var threshold: int = _employee_data.get("trust_threshold", 3)
	if _trust >= threshold:
		# Reveal a secret!
		var secrets: Array = _employee_data.get("secrets", [])
		var unrevealed := []
		for s in secrets:
			if s not in _secrets_revealed:
				unrevealed.append(s)

		if not unrevealed.is_empty():
			var secret: String = unrevealed[0]
			_secrets_revealed.append(secret)
			_add_npc_msg("Look... I probably shouldn't tell you this, but...")
			_add_secret_msg(secret)
			_add_secret_to_list(secret)
			EventBus.se_secret_revealed.emit(_employee_id, secret)
			VoiceHandler.speak("Good work. That could be useful.")
			Juice.float_text(self, "+SECRET", Vector2(size.x / 2, size.y / 2 - 50), C_SECRET)
		else:
			_add_npc_msg("I've told you everything I know about that.")
	else:
		_suspicion += 1
		_add_npc_msg(_pick_response(style, "probe_low"))
		if _suspicion == 3:
			_add_system_msg("[color=#cc8833]They seem uncomfortable with your questions.[/color]")


func _handle_aggressive(style: String) -> void:
	_suspicion += 2
	_trust = max(0, _trust - 1)
	_add_npc_msg(_pick_response(style, "aggressive"))
	EventBus.se_trust_changed.emit(_employee_id, _trust)


func _handle_vulnerability(style: String) -> void:
	_trust = min(_trust + 2, 10)
	_add_npc_msg(_pick_response(style, "vulnerability"))
	EventBus.se_trust_changed.emit(_employee_id, _trust)
	_add_system_msg("[color=#44aa66]They're opening up to you.[/color]")


func _handle_fallback(style: String) -> void:
	_add_npc_msg(_pick_response(style, "fallback"))


func _check_suspicion() -> void:
	if _suspicion >= 5:
		_add_npc_msg("I'm going to report this conversation. We're done.")
		_add_system_msg("[color=#cc3333]SUSPICION MAXED — Conversation terminated. Detection increased.[/color]")
		OpState.add_detection("se_failed")
		await get_tree().create_timer(1.5).timeout
		close_chat()
	elif _suspicion >= 4:
		_add_system_msg("[color=#cc6633]\"I don't think I should be telling you this.\"[/color]")
	elif _suspicion >= 3:
		_add_system_msg("[color=#cc8833]\"You're asking a lot of questions...\"[/color]")


# ===========================================================================
# Chat display helpers
# ===========================================================================

func _add_player_msg(text: String) -> void:
	_chat_log.append_text("[right][color=#6699cc]You: %s[/color][/right]\n" % text)


func _add_npc_msg(text: String) -> void:
	var name_str: String = _employee_data.get("name", "???").split(" ")[0]
	_chat_log.append_text("[color=#bbbbcc]%s: %s[/color]\n" % [name_str, text])


func _add_system_msg(text: String) -> void:
	_chat_log.append_text("[center]%s[/center]\n" % text)


func _add_secret_msg(secret: String) -> void:
	_chat_log.append_text("[center][color=#f2cc33][SECRET REVEALED] %s[/color][/center]\n" % secret)


func _add_secret_to_list(secret: String) -> void:
	var lbl := Label.new()
	lbl.text = "• %s" % secret
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", C_SECRET)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_secrets_list.add_child(lbl)


func _update_bars() -> void:
	if _trust_bar:
		_trust_bar.value = _trust
	if _suspicion_bar:
		_suspicion_bar.value = _suspicion


# ===========================================================================
# Response helpers
# ===========================================================================

func _get_response_style() -> String:
	var traits: Array = _employee_data.get("personality_traits", [])
	if "talkative" in traits or "friendly" in traits:
		return "friendly_guard"
	return "tech_professional"


func _get_greeting() -> String:
	var style := _get_response_style()
	if style == "friendly_guard":
		return "Hey there! What can I do for you?"
	return "Hi. Can I help you with something?"


func _pick_response(style: String, category: String) -> String:
	var pool: Array = RESPONSES.get(style, RESPONSES["tech_professional"]).get(category, ["..."])
	return pool[randi() % pool.size()]


func _matches_any(text: String, keywords: Array) -> bool:
	for kw in keywords:
		if kw in text:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_chat()
		get_viewport().set_input_as_handled()
