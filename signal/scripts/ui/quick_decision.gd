## Quick decision — popup during complications with 2-3 icon buttons.
##
## Appears center-bottom. Auto-dismisses if no choice made in 8 seconds.
## Used for mid-mission split-second decisions.
extends Control


signal decision_made(choice_id: String)

var _choices: Array = []
var _timer := 0.0
var _timeout := 8.0
var _active := false
var _buttons: Array = []


func _ready() -> void:
	visible = false


func show_decision(choices: Array, timeout: float = 8.0) -> void:
	_choices = choices
	_timeout = timeout
	_timer = 0.0
	_active = true
	visible = true

	# Clear old
	for child in get_children():
		child.queue_free()
	_buttons.clear()

	# Container
	var panel := PanelContainer.new()
	panel.anchors_preset = Control.PRESET_CENTER_BOTTOM
	panel.anchor_left = 0.5
	panel.anchor_top = 1.0
	panel.anchor_right = 0.5
	panel.anchor_bottom = 1.0
	panel.offset_left = -180
	panel.offset_top = -100
	panel.offset_right = 180
	panel.offset_bottom = -20

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.95)
	sb.border_color = Color(0.9, 0.5, 0.2, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	for choice in choices:
		var btn := Button.new()
		btn.text = choice.get("label", "?").to_upper()
		btn.custom_minimum_size = Vector2(100, 50)

		var risk: float = choice.get("risk", 0.5)
		if risk < 0.3:
			btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
		elif risk < 0.6:
			btn.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
		else:
			btn.add_theme_color_override("font_color", Color(0.9, 0.3, 0.2))

		var cid: String = choice.get("id", "")
		btn.pressed.connect(func(): _choose(cid))
		hbox.add_child(btn)
		_buttons.append(btn)

		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(12, 0)
		hbox.add_child(spacer)

	panel.add_child(hbox)
	add_child(panel)

	# Animate in
	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)


func _process(delta: float) -> void:
	if not _active:
		return
	_timer += delta
	if _timer >= _timeout:
		# Auto-pick first option (safest)
		if _choices.size() > 0:
			_choose(_choices[0].get("id", ""))


func _choose(choice_id: String) -> void:
	_active = false
	visible = false
	decision_made.emit(choice_id)
