## Course of Action cards — slide up from bottom on right-click.
##
## 2-3 option cards with icon + one-word label + risk/reward bar.
## Click to select. Cards dismiss. Zero reading.
extends Control


signal coa_selected(coa_id: String)

const CARD_WIDTH := 100
const CARD_HEIGHT := 140
const CARD_SPACING := 16
const CARD_Y_HIDDEN := 200.0  # Below screen
const CARD_Y_VISIBLE := 20.0  # Visible position from bottom

const ICON_MAP := {
	"surveil": "EYE",
	"intercept": "NET",
	"strike": "BOLT",
	"extract": "OUT",
	"hack": "CODE",
	"support": "SHIELD",
	"hold": "WAIT",
	"abort": "X",
	"capture": "CUFF",
	"jam": "ZAP",
}

var _cards: Array = []
var _visible := false
var _target_blip_id: String = ""


func _ready() -> void:
	visible = false
	EventBus.coa_requested.connect(_on_coa_requested)


func show_options(blip_id: String, options: Array) -> void:
	_target_blip_id = blip_id
	_clear_cards()
	visible = true
	_visible = true

	var total_width: float = options.size() * (CARD_WIDTH + CARD_SPACING) - CARD_SPACING
	var start_x: float = (size.x - total_width) / 2.0

	for i in range(options.size()):
		var opt: Dictionary = options[i]
		var card := _create_card(opt, i)
		card.position = Vector2(start_x + i * (CARD_WIDTH + CARD_SPACING), size.y)
		add_child(card)
		_cards.append(card)

		# Animate slide up with stagger
		var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(
			card, "position:y",
			size.y - CARD_HEIGHT - CARD_Y_VISIBLE,
			0.3,
		).set_delay(i * 0.08)


func dismiss() -> void:
	for i in range(_cards.size()):
		var card: Control = _cards[i]
		var tween := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(card, "position:y", size.y + 20, 0.2).set_delay(i * 0.04)
	await get_tree().create_timer(0.4).timeout
	_clear_cards()
	visible = false
	_visible = false


func _create_card(opt: Dictionary, index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.95)
	sb.border_color = Color(0.2, 0.25, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 12
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	# Big icon text
	var icon_label := Label.new()
	var coa_id: String = opt.get("id", "")
	icon_label.text = ICON_MAP.get(coa_id, "?")
	icon_label.add_theme_font_size_override("font_size", 22)
	icon_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(icon_label)

	# One-word label
	var label := Label.new()
	label.text = opt.get("label", coa_id).to_upper()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	# Risk/reward bar
	var risk: float = opt.get("risk", 0.5)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = risk
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	var fill := StyleBoxFlat.new()
	if risk < 0.3:
		fill.bg_color = Color(0.2, 0.8, 0.4)
	elif risk < 0.6:
		fill.bg_color = Color(0.9, 0.7, 0.2)
	else:
		fill.bg_color = Color(0.9, 0.3, 0.2)
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	vbox.add_child(bar)

	# Risk label
	var risk_label := Label.new()
	risk_label.text = "RISK" if risk >= 0.5 else "SAFE"
	risk_label.add_theme_font_size_override("font_size", 9)
	risk_label.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5))
	risk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(risk_label)

	card.add_child(vbox)

	# Click handler
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_card_clicked(opt)
	)

	# Hover effect
	card.mouse_entered.connect(func():
		sb.border_color = Color(0.4, 0.6, 0.9)
		sb.bg_color = Color(0.1, 0.12, 0.18, 0.95)
	)
	card.mouse_exited.connect(func():
		sb.border_color = Color(0.2, 0.25, 0.35)
		sb.bg_color = Color(0.08, 0.09, 0.13, 0.95)
	)

	return card


func _on_card_clicked(opt: Dictionary) -> void:
	var coa_id: String = opt.get("id", "")
	EventBus.coa_selected.emit(_target_blip_id, coa_id)
	dismiss()


func _on_coa_requested(_blip_id: String) -> void:
	# Mission manager will call show_options() with actual data
	pass


func _clear_cards() -> void:
	for card in _cards:
		if is_instance_valid(card):
			card.queue_free()
	_cards.clear()
