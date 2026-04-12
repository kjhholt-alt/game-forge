## Upgrade shop — spend budget on new assets between missions.
##
## Shows available assets as cards with stats and prices.
## Click to buy. Handler comments on purchases.
extends Control


signal shop_closed
signal asset_purchased(asset_data: Dictionary)

const SHOP_ITEMS := [
	{"id": "asset-predator", "label": "PREDATOR", "type": "drone", "speed": 0.7, "stealth": 0.9, "firepower": 0.2, "price": 15000, "desc": "High-altitude surveillance drone"},
	{"id": "asset-viper", "label": "VIPER", "type": "jet", "speed": 0.9, "stealth": 0.2, "firepower": 0.95, "price": 25000, "desc": "Strike aircraft"},
	{"id": "asset-ghost", "label": "GHOST", "type": "spec_ops", "speed": 0.4, "stealth": 0.95, "firepower": 0.5, "price": 20000, "desc": "Tier 1 special operations team"},
	{"id": "asset-cyber", "label": "CIPHER", "type": "cyber", "speed": 1.0, "stealth": 1.0, "firepower": 0.0, "price": 12000, "desc": "Remote cyber operations unit"},
	{"id": "asset-sat", "label": "KEYHOLE", "type": "satellite", "speed": 0.5, "stealth": 1.0, "firepower": 0.0, "price": 30000, "desc": "Orbital reconnaissance satellite"},
]

var _budget: int = 0
var _owned_ids: Array = []


func _ready() -> void:
	visible = false


func show_shop(budget: int, owned_asset_ids: Array) -> void:
	_budget = budget
	_owned_ids = owned_asset_ids
	visible = true
	_build_ui()


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	# Overlay
	var overlay := ColorRect.new()
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	overlay.color = Color(0, 0, 0, 0.7)
	add_child(overlay)

	# Panel
	var panel := VBoxContainer.new()
	panel.anchors_preset = Control.PRESET_CENTER
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -350
	panel.offset_top = -250
	panel.offset_right = 350
	panel.offset_bottom = 250

	# Header
	var header := Label.new()
	header.text = "ASSET REQUISITION"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(header)

	var budget_lbl := Label.new()
	budget_lbl.text = "BUDGET: $%dK" % (_budget / 1000)
	budget_lbl.add_theme_font_size_override("font_size", 14)
	budget_lbl.add_theme_color_override("font_color", Color(0.2, 0.8, 0.4))
	budget_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(budget_lbl)

	panel.add_child(HSeparator.new())

	# Asset grid
	var grid := HBoxContainer.new()
	grid.alignment = BoxContainer.ALIGNMENT_CENTER

	for item in SHOP_ITEMS:
		var card := _create_shop_card(item)
		grid.add_child(card)

	panel.add_child(grid)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	panel.add_child(spacer)

	# Continue button
	var continue_btn := Button.new()
	continue_btn.text = "DEPLOY"
	continue_btn.custom_minimum_size = Vector2(200, 45)
	continue_btn.pressed.connect(func():
		visible = false
		shop_closed.emit()
	)
	panel.add_child(continue_btn)
	# center the button
	continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	add_child(panel)

	VoiceHandler.speak("New assets available. Spend your budget wisely.")


func _create_shop_card(item: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(120, 180)

	var owned: bool = item.get("id", "") in _owned_ids
	var can_afford: bool = _budget >= item.get("price", 99999)

	var sb := StyleBoxFlat.new()
	if owned:
		sb.bg_color = Color(0.1, 0.15, 0.12, 0.9)
		sb.border_color = Color(0.2, 0.7, 0.3, 0.5)
	elif can_afford:
		sb.bg_color = Color(0.06, 0.07, 0.1, 0.9)
		sb.border_color = Color(0.2, 0.25, 0.35)
	else:
		sb.bg_color = Color(0.04, 0.05, 0.07, 0.9)
		sb.border_color = Color(0.12, 0.14, 0.18)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()

	# Name
	var name_lbl := Label.new()
	name_lbl.text = item.get("label", "?")
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.3, 0.6, 0.9) if not owned else Color(0.2, 0.7, 0.3))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	# Type
	var type_lbl := Label.new()
	type_lbl.text = item.get("type", "").to_upper()
	type_lbl.add_theme_font_size_override("font_size", 9)
	type_lbl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5))
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(type_lbl)

	# Stat bars
	var stats := {"SPD": item.get("speed", 0), "STL": item.get("stealth", 0), "PWR": item.get("firepower", 0)}
	for sname in stats:
		var row := HBoxContainer.new()
		var sl := Label.new()
		sl.text = sname
		sl.add_theme_font_size_override("font_size", 8)
		sl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5))
		sl.custom_minimum_size = Vector2(24, 0)
		row.add_child(sl)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 1.0
		bar.value = stats[sname]
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(60, 4)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.3, 0.6, 0.9, 0.7) if not owned else Color(0.2, 0.7, 0.3, 0.7)
		fill.set_corner_radius_all(1)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		vbox.add_child(row)

	# Price / status
	var price_lbl := Label.new()
	if owned:
		price_lbl.text = "OWNED"
		price_lbl.add_theme_color_override("font_color", Color(0.2, 0.7, 0.3))
	else:
		price_lbl.text = "$%dK" % (item.get("price", 0) / 1000)
		price_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2) if can_afford else Color(0.5, 0.3, 0.3))
	price_lbl.add_theme_font_size_override("font_size", 12)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(price_lbl)

	# Buy button
	if not owned and can_afford:
		var buy_btn := Button.new()
		buy_btn.text = "BUY"
		buy_btn.custom_minimum_size = Vector2(0, 28)
		buy_btn.pressed.connect(func(): _buy(item))
		vbox.add_child(buy_btn)

	card.add_child(vbox)
	return card


func _buy(item: Dictionary) -> void:
	var price: int = item.get("price", 0)
	if _budget < price:
		return
	_budget -= price
	_owned_ids.append(item.get("id", ""))
	asset_purchased.emit(item)
	VoiceHandler.speak("Acquired %s. Good choice." % item.get("label", "asset"))
	_build_ui()  # Refresh
