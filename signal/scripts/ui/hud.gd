## HUD — minimal top bar with timer + asset tray with stat bars.
extends Control


@onready var codename_label: Label = $TopBar/Codename
@onready var detection_bar: ProgressBar = $TopBar/DetectionBar
@onready var budget_label: Label = $TopBar/BudgetLabel
@onready var subtitle_label: Label = $SubtitleBar/SubtitleText
@onready var timer_label: Label = $TopBar/TimerLabel
@onready var asset_tray: HBoxContainer = $AssetTray

var _mission_time := 0.0
var _mission_active := false
var _subtitle_tween: Tween


func _ready() -> void:
	EventBus.detection_changed.connect(_on_detection)
	EventBus.budget_changed.connect(_on_budget)
	EventBus.handler_subtitle.connect(_on_subtitle)
	EventBus.mission_started.connect(func(_a, _b, _c): _mission_active = true)
	EventBus.mission_complete.connect(func(_g): _mission_active = false)
	EventBus.asset_returned.connect(_on_asset_returned)

	detection_bar.min_value = 0.0
	detection_bar.max_value = 1.0
	detection_bar.value = 0.0
	subtitle_label.text = ""
	timer_label.text = "00:00"


func _process(delta: float) -> void:
	if _mission_active or true:  # Always tick for now
		_mission_time += delta
		var mins := int(_mission_time) / 60
		var secs := int(_mission_time) % 60
		timer_label.text = "%02d:%02d" % [mins, secs]


func set_codename(text: String) -> void:
	codename_label.text = text


func setup_asset_tray(assets: Array) -> void:
	# Clear old
	for child in asset_tray.get_children():
		child.queue_free()

	for asset in assets:
		var card := _create_asset_card(asset)
		asset_tray.add_child(card)


func _create_asset_card(asset: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Asset_%s" % asset.get("id", "")
	card.custom_minimum_size = Vector2(120, 60)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.9)
	sb.border_color = Color(0.15, 0.2, 0.28)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()

	# Label
	var lbl := Label.new()
	lbl.text = asset.get("label", "UNIT")
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.3, 0.6, 0.9))
	vbox.add_child(lbl)

	# Stat bars
	var stats := {"SPD": asset.get("speed", 0.5), "STL": asset.get("stealth", 0.5), "PWR": asset.get("firepower", 0.5)}
	for stat_name in stats:
		var row := HBoxContainer.new()
		var stat_lbl := Label.new()
		stat_lbl.text = stat_name
		stat_lbl.add_theme_font_size_override("font_size", 8)
		stat_lbl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5))
		stat_lbl.custom_minimum_size = Vector2(26, 0)
		row.add_child(stat_lbl)

		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = stats[stat_name]
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(60, 4)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.3, 0.6, 0.9, 0.7)
		fill.set_corner_radius_all(1)
		bar.add_theme_stylebox_override("fill", fill)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.08, 0.09, 0.12)
		bg.set_corner_radius_all(1)
		bar.add_theme_stylebox_override("background", bg)
		row.add_child(bar)
		vbox.add_child(row)

	card.add_child(vbox)
	return card


func _on_detection(level: String, value: float) -> void:
	detection_bar.value = value
	var fill := StyleBoxFlat.new()
	match level:
		"green": fill.bg_color = Color(0.2, 0.7, 0.3)
		"yellow": fill.bg_color = Color(0.9, 0.7, 0.2)
		"red": fill.bg_color = Color(0.9, 0.3, 0.2)
		"black": fill.bg_color = Color(0.9, 0.1, 0.1)
	fill.set_corner_radius_all(2)
	detection_bar.add_theme_stylebox_override("fill", fill)


func _on_budget(new_budget: int) -> void:
	budget_label.text = "$%dK" % (new_budget / 1000)


func _on_subtitle(text: String) -> void:
	subtitle_label.text = text
	subtitle_label.modulate.a = 1.0
	if text.is_empty():
		subtitle_label.visible = false
		return

	subtitle_label.visible = true
	if _subtitle_tween and _subtitle_tween.is_valid():
		_subtitle_tween.kill()
	_subtitle_tween = create_tween()
	_subtitle_tween.tween_interval(4.0)
	_subtitle_tween.tween_property(subtitle_label, "modulate:a", 0.0, 0.5)
	_subtitle_tween.tween_callback(func(): subtitle_label.visible = false)


func _on_asset_returned(asset_id: String) -> void:
	# Flash the asset card green briefly
	var card = asset_tray.get_node_or_null("Asset_%s" % asset_id)
	if card:
		Juice.pulse_color(card, Color(0.2, 0.9, 0.4, 0.3), 0.5)
