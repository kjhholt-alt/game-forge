## Connection type selector — popup when player draws evidence links.
##
## Shows a dropdown to pick connection type + optional note field.
## Appears at the mouse position when a connection is made.
extends PopupPanel


signal connection_confirmed(conn_type: String, note: String)
signal connection_cancelled


const CONNECTION_TYPES := [
	{"id": "mentions", "label": "MENTIONS", "desc": "One document references the other", "color": Color(0.7, 0.7, 0.7)},
	{"id": "finances", "label": "FINANCES", "desc": "Financial link between items", "color": Color(0.9, 0.8, 0.2)},
	{"id": "contacts", "label": "CONTACTS", "desc": "Same person/entity appears in both", "color": Color(0.3, 0.7, 0.9)},
	{"id": "location", "label": "LOCATION", "desc": "Same location referenced", "color": Color(0.9, 0.4, 0.3)},
	{"id": "timeline", "label": "TIMELINE", "desc": "Events are chronologically linked", "color": Color(0.6, 0.4, 0.9)},
	{"id": "identity", "label": "IDENTITY", "desc": "Same person under different names", "color": Color(0.9, 0.5, 0.7)},
]

var _selected_index: int = 0
var _buttons: Array[Button] = []
var _note_field: LineEdit


func _ready() -> void:
	transparent_bg = true
	size = Vector2(320, 380)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.10, 0.98)
	sb.border_color = Color(0.2, 0.25, 0.32, 1)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()

	var header := Label.new()
	header.text = "CONNECTION TYPE"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.4, 0.5, 0.55))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	for i in range(CONNECTION_TYPES.size()):
		var ct: Dictionary = CONNECTION_TYPES[i]
		var btn := Button.new()
		btn.text = "  %s  —  %s" % [ct["label"], ct["desc"]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(280, 36)
		btn.add_theme_color_override("font_color", ct["color"])
		btn.pressed.connect(func(): _select_type(i))
		vbox.add_child(btn)
		_buttons.append(btn)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	var note_label := Label.new()
	note_label.text = "NOTE (optional)"
	note_label.add_theme_font_size_override("font_size", 11)
	note_label.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5))
	vbox.add_child(note_label)

	_note_field = LineEdit.new()
	_note_field.placeholder_text = "Why are these connected?"
	_note_field.custom_minimum_size = Vector2(280, 32)
	_note_field.text_submitted.connect(func(_t): _confirm())
	vbox.add_child(_note_field)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(80, 32)
	cancel_btn.pressed.connect(func(): _cancel())
	btn_row.add_child(cancel_btn)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(8, 0)
	btn_row.add_child(spacer)

	var confirm_btn := Button.new()
	confirm_btn.text = "CONNECT"
	confirm_btn.custom_minimum_size = Vector2(100, 32)
	confirm_btn.pressed.connect(func(): _confirm())
	btn_row.add_child(confirm_btn)

	vbox.add_child(btn_row)

	panel.add_child(vbox)
	add_child(panel)

	popup_hide.connect(func(): connection_cancelled.emit())


func show_at(pos: Vector2) -> void:
	_selected_index = 0
	_note_field.text = ""
	_highlight_selected()
	position = pos - Vector2(160, 0)
	popup()


func _select_type(index: int) -> void:
	_selected_index = index
	_highlight_selected()


func _highlight_selected() -> void:
	for i in range(_buttons.size()):
		if i == _selected_index:
			_buttons[i].add_theme_color_override("font_color", Color.WHITE)
		else:
			var ct: Dictionary = CONNECTION_TYPES[i]
			_buttons[i].add_theme_color_override("font_color", ct["color"])


func _confirm() -> void:
	var ct: Dictionary = CONNECTION_TYPES[_selected_index]
	connection_confirmed.emit(ct["id"], _note_field.text)
	hide()


func _cancel() -> void:
	connection_cancelled.emit()
	hide()
