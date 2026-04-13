## Info card — Maven-style rich analysis popup near a blip.
##
## Shows classification, threat assessment, asset count, recommended approach.
## Claude DM generates the analysis text. Falls back to pre-written data.
extends Control


var _card: PanelContainer = null
var _dismiss_timer := 0.0
var _active := false
const DISMISS_TIME := 8.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if not _active:
		return
	_dismiss_timer += delta
	if _dismiss_timer >= DISMISS_TIME:
		dismiss()


func show_card(screen_pos: Vector2, data: Dictionary) -> void:
	dismiss()

	var label: String = data.get("label", "UNKNOWN")
	var blip_type: String = data.get("type", "unknown")
	var classification: String = data.get("classification", "")
	var threat: String = data.get("threat", "")
	var details: Array = data.get("details", [])
	var recommendation: String = data.get("recommendation", "")

	_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.10, 0.96)
	sb.border_color = Color(0.18, 0.22, 0.32, 0.9)
	sb.set_border_width_all(1)

	# Colored top border based on type
	match blip_type:
		"hostile": sb.border_color = Color(0.9, 0.25, 0.2, 0.8)
		"unknown": sb.border_color = Color(0.9, 0.6, 0.15, 0.8)
		"asset": sb.border_color = Color(0.3, 0.6, 0.9, 0.8)
	sb.border_width_top = 3

	sb.set_corner_radius_all(4)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	# Header: icon + label
	var header := HBoxContainer.new()
	var icon := Label.new()
	match blip_type:
		"hostile": icon.text = "◆"
		"unknown": icon.text = "◇"
		"asset": icon.text = "▲"
		_: icon.text = "●"
	var icon_color: Color
	match blip_type:
		"hostile": icon_color = Color(1.0, 0.3, 0.25)
		"unknown": icon_color = Color(1.0, 0.7, 0.2)
		"asset": icon_color = Color(0.4, 0.7, 1.0)
		_: icon_color = Color(0.7, 0.7, 0.7)
	icon.add_theme_font_size_override("font_size", 18)
	icon.add_theme_color_override("font_color", icon_color)
	header.add_child(icon)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(8, 0)
	header.add_child(spacer)

	var name_lbl := Label.new()
	name_lbl.text = label
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	header.add_child(name_lbl)
	vbox.add_child(header)

	# Classification line (e.g. "Computer Vision Detection • Vehicle")
	if not classification.is_empty():
		var cls_lbl := Label.new()
		cls_lbl.text = classification
		cls_lbl.add_theme_font_size_override("font_size", 11)
		cls_lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
		vbox.add_child(cls_lbl)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Detail lines (e.g. "3 vehicles detected", "Armed personnel", "Active radar")
	for detail in details:
		var d_row := HBoxContainer.new()
		var bullet := Label.new()
		bullet.text = "•"
		bullet.add_theme_font_size_override("font_size", 11)
		bullet.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6))
		d_row.add_child(bullet)

		var sp2 := Control.new()
		sp2.custom_minimum_size = Vector2(6, 0)
		d_row.add_child(sp2)

		var d_lbl := Label.new()
		d_lbl.text = str(detail)
		d_lbl.add_theme_font_size_override("font_size", 12)
		d_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82))
		d_row.add_child(d_lbl)
		vbox.add_child(d_row)

	# Threat assessment
	if not threat.is_empty():
		var threat_row := HBoxContainer.new()
		var t_icon := Label.new()
		t_icon.text = "⚠"
		t_icon.add_theme_font_size_override("font_size", 12)
		match threat.to_lower():
			"high": t_icon.add_theme_color_override("font_color", Color(0.9, 0.3, 0.2))
			"medium": t_icon.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
			_: t_icon.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4))
		threat_row.add_child(t_icon)

		var sp3 := Control.new()
		sp3.custom_minimum_size = Vector2(4, 0)
		threat_row.add_child(sp3)

		var t_lbl := Label.new()
		t_lbl.text = "Threat: %s" % threat.to_upper()
		t_lbl.add_theme_font_size_override("font_size", 11)
		t_lbl.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
		threat_row.add_child(t_lbl)
		vbox.add_child(threat_row)

	# Recommendation
	if not recommendation.is_empty():
		var rec_lbl := Label.new()
		rec_lbl.text = "→ %s" % recommendation
		rec_lbl.add_theme_font_size_override("font_size", 11)
		rec_lbl.add_theme_color_override("font_color", Color(0.4, 0.7, 0.9))
		vbox.add_child(rec_lbl)

	_card.add_child(vbox)
	_card.custom_minimum_size = Vector2(260, 0)

	# Position near the blip
	_card.position = screen_pos + Vector2(50, -30)
	if _card.position.x + 280 > size.x:
		_card.position.x = screen_pos.x - 290
	if _card.position.y < 50:
		_card.position.y = 50

	add_child(_card)

	# Fade in
	_card.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_card, "modulate:a", 1.0, 0.2)

	_active = true
	_dismiss_timer = 0.0


func dismiss() -> void:
	_active = false
	if _card and is_instance_valid(_card):
		_card.queue_free()
		_card = null
