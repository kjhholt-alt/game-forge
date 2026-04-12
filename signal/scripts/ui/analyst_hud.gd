## Analyst HUD — persistent sidebar showing codename, skills, and toolkit.
##
## Slides in from the left edge. Toggle with backtick key or button.
extends Control


const SKILL_COLORS := {
	"sigint": Color(0.3, 0.8, 0.4),
	"humint": Color(0.4, 0.7, 0.9),
	"cryptography": Color(0.8, 0.6, 0.9),
	"social_engineering": Color(0.9, 0.6, 0.4),
	"network_exploitation": Color(0.9, 0.9, 0.3),
}

const SKILL_LABELS := {
	"sigint": "SIGINT",
	"humint": "HUMINT",
	"cryptography": "CRYPTO",
	"social_engineering": "SOCENG",
	"network_exploitation": "NETXPL",
}

var _panel: PanelContainer
var _vbox: VBoxContainer
var _skill_bars: Dictionary = {}
var _expanded := false
var _toggle_btn: Button


func _ready() -> void:
	# Toggle button (always visible on left edge)
	_toggle_btn = Button.new()
	_toggle_btn.text = ">"
	_toggle_btn.custom_minimum_size = Vector2(24, 80)
	_toggle_btn.position = Vector2(0, 100)
	_toggle_btn.pressed.connect(_toggle)
	_toggle_btn.add_theme_font_size_override("font_size", 16)
	add_child(_toggle_btn)

	# HUD panel
	_panel = PanelContainer.new()
	_panel.position = Vector2(-260, 60)
	_panel.custom_minimum_size = Vector2(250, 400)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.95)
	sb.border_color = Color(0.12, 0.16, 0.22, 1)
	sb.set_border_width_all(1)
	sb.border_width_right = 2
	sb.set_corner_radius_all(0)
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", sb)

	_vbox = VBoxContainer.new()
	_build_hud()
	_panel.add_child(_vbox)
	add_child(_panel)

	EventBus.xp_gained.connect(_on_xp_changed)
	EventBus.skill_leveled_up.connect(_on_skill_leveled)
	EventBus.phase_changed.connect(func(_p): _refresh())


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_QUOTELEFT:
		_toggle()


func _toggle() -> void:
	_expanded = !_expanded
	var target_x := 0.0 if _expanded else -260.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_panel, "position:x", target_x, 0.3)
	_toggle_btn.text = "<" if _expanded else ">"
	_toggle_btn.position.x = 250.0 if _expanded else 0.0

	if _expanded:
		_refresh()


func _build_hud() -> void:
	# Codename header
	var header := Label.new()
	header.text = "ANALYST"
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", Color(0.35, 0.4, 0.45))
	_vbox.add_child(header)

	var codename := Label.new()
	codename.name = "Codename"
	codename.text = GameState.analyst.get("codename", "???")
	codename.add_theme_font_size_override("font_size", 20)
	codename.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	_vbox.add_child(codename)

	_vbox.add_child(HSeparator.new())

	# Skills section
	var skills_header := Label.new()
	skills_header.text = "SKILLS"
	skills_header.add_theme_font_size_override("font_size", 10)
	skills_header.add_theme_color_override("font_color", Color(0.35, 0.4, 0.45))
	_vbox.add_child(skills_header)

	for skill_type in SKILL_LABELS.keys():
		var row := VBoxContainer.new()
		row.name = "Skill_%s" % skill_type

		var label_row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.name = "Label"
		lbl.text = SKILL_LABELS[skill_type]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", SKILL_COLORS.get(skill_type, Color.WHITE))
		label_row.add_child(lbl)

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label_row.add_child(spacer)

		var level_lbl := Label.new()
		level_lbl.name = "Level"
		level_lbl.text = "LV 1"
		level_lbl.add_theme_font_size_override("font_size", 11)
		level_lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
		label_row.add_child(level_lbl)

		row.add_child(label_row)

		var bar := ProgressBar.new()
		bar.name = "XPBar"
		bar.min_value = 0
		bar.max_value = 100
		bar.value = 0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 6)
		var fill := StyleBoxFlat.new()
		fill.bg_color = SKILL_COLORS.get(skill_type, Color.WHITE) * 0.7
		fill.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)

		_vbox.add_child(row)
		_skill_bars[skill_type] = row

	_vbox.add_child(HSeparator.new())

	# Phase indicator
	var phase_header := Label.new()
	phase_header.text = "STATUS"
	phase_header.add_theme_font_size_override("font_size", 10)
	phase_header.add_theme_color_override("font_color", Color(0.35, 0.4, 0.45))
	_vbox.add_child(phase_header)

	var phase_lbl := Label.new()
	phase_lbl.name = "PhaseStatus"
	phase_lbl.text = "STANDBY"
	phase_lbl.add_theme_font_size_override("font_size", 12)
	_vbox.add_child(phase_lbl)

	var ops_lbl := Label.new()
	ops_lbl.name = "OpsCompleted"
	ops_lbl.text = "Ops completed: 0"
	ops_lbl.add_theme_font_size_override("font_size", 11)
	ops_lbl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5))
	_vbox.add_child(ops_lbl)


func _refresh() -> void:
	# Update codename
	var cn_node := _vbox.get_node_or_null("Codename")
	if cn_node:
		cn_node.text = GameState.analyst.get("codename", "???")

	# Update skills
	for skill_type in SKILL_LABELS.keys():
		var row := _skill_bars.get(skill_type)
		if not row:
			continue
		var skill_data: Dictionary = GameState.analyst.skills.get(skill_type, {})
		var level: int = skill_data.get("level", 1)
		var xp: int = skill_data.get("xp", 0)
		var xp_next: int = skill_data.get("xp_to_next", 100)

		var level_lbl := row.get_node_or_null("Label/Level") if row.has_node("Label/Level") else null
		# Try the HBoxContainer child
		for child in row.get_children():
			if child is HBoxContainer:
				var lv := child.get_node_or_null("Level")
				if lv:
					lv.text = "LV %d" % level
		var bar := row.get_node_or_null("XPBar")
		if bar:
			bar.max_value = xp_next
			bar.value = xp

	# Update phase
	var phase_node := _vbox.get_node_or_null("PhaseStatus")
	if phase_node:
		match GameState.current_phase:
			"briefing": phase_node.text = "BRIEFING"
			"signal": phase_node.text = "SIGNAL ANALYSIS"
			"blacksite": phase_node.text = "BLACKSITE — ACTIVE"
			"debrief": phase_node.text = "DEBRIEF"
			_: phase_node.text = "STANDBY"

	var ops_node := _vbox.get_node_or_null("OpsCompleted")
	if ops_node:
		ops_node.text = "Ops completed: %d" % GameState.analyst.get("ops_completed", 0)


func _on_xp_changed(_skill: String, _amount: int) -> void:
	if _expanded:
		_refresh()


func _on_skill_leveled(_skill: String, _level: int) -> void:
	_refresh()
