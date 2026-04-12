## HUD — minimal top bar and bottom asset tray. No text walls.
extends Control


@onready var codename_label: Label = $TopBar/Codename
@onready var detection_bar: ProgressBar = $TopBar/DetectionBar
@onready var budget_label: Label = $TopBar/BudgetLabel
@onready var subtitle_label: Label = $SubtitleBar/SubtitleText


func _ready() -> void:
	EventBus.detection_changed.connect(_on_detection)
	EventBus.budget_changed.connect(_on_budget)
	EventBus.handler_subtitle.connect(_on_subtitle)
	EventBus.campaign_phase_changed.connect(_on_phase)

	detection_bar.min_value = 0.0
	detection_bar.max_value = 1.0
	detection_bar.value = 0.0

	subtitle_label.text = ""


func set_codename(text: String) -> void:
	codename_label.text = text


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
	if text.is_empty():
		subtitle_label.visible = false
	else:
		subtitle_label.visible = true
		# Auto-dismiss after a few seconds
		var tween := create_tween()
		tween.tween_interval(4.0)
		tween.tween_property(subtitle_label, "modulate:a", 0.0, 0.5)
		tween.tween_callback(func():
			subtitle_label.visible = false
			subtitle_label.modulate.a = 1.0
		)


func _on_phase(phase: String) -> void:
	pass
