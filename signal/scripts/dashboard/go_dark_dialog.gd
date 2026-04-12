## Go Dark confirmation dialog — shows prep score before entering BLACKSITE.
##
## Displays evidence board analysis quality and warns the player
## about what they'll face based on their prep level.
extends PopupPanel


signal confirmed
signal cancelled


var _prep_score: float = 0.0


func _ready() -> void:
	transparent_bg = true
	size = Vector2(420, 320)


func show_confirmation(prep_score: float) -> void:
	_prep_score = prep_score

	# Clear old content
	for child in get_children():
		child.queue_free()

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.10, 0.98)
	sb.border_color = Color(0.9, 0.3, 0.3, 0.8)
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()

	# Header
	var header := Label.new()
	header.text = "GO DARK"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var subtitle := Label.new()
	subtitle.text = "Enter BLACKSITE phase — this cannot be undone"
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	# Prep score display
	var score_pct := int(_prep_score * 100)
	var score_color: Color
	var score_label_text: String
	var readiness: String

	if score_pct >= 75:
		score_color = Color(0.2, 0.9, 0.4)
		readiness = "EXCELLENT — Full network map, known credentials, clear targets."
	elif score_pct >= 50:
		score_color = Color(0.9, 0.8, 0.2)
		readiness = "ADEQUATE — Partial intel. Some hosts and credentials known."
	elif score_pct >= 25:
		score_color = Color(0.9, 0.5, 0.2)
		readiness = "POOR — Limited intel. You'll be working mostly blind."
	else:
		score_color = Color(0.9, 0.2, 0.2)
		readiness = "CRITICAL — Almost no intel. High risk of detection."

	var score_row := HBoxContainer.new()
	var score_lbl := Label.new()
	score_lbl.text = "PREP SCORE:"
	score_lbl.add_theme_font_size_override("font_size", 14)
	score_row.add_child(score_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_row.add_child(spacer)

	var score_val := Label.new()
	score_val.text = "%d%%" % score_pct
	score_val.add_theme_font_size_override("font_size", 28)
	score_val.add_theme_color_override("font_color", score_color)
	score_row.add_child(score_val)
	vbox.add_child(score_row)

	# Progress bar
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = _prep_score
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = score_color
	bar_fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", bar_fill)
	vbox.add_child(bar)

	# Readiness text
	var ready_lbl := RichTextLabel.new()
	ready_lbl.bbcode_enabled = true
	ready_lbl.fit_content = true
	ready_lbl.custom_minimum_size = Vector2(0, 40)
	ready_lbl.text = "[color=#%s]%s[/color]" % [score_color.to_html(false), readiness]
	ready_lbl.add_theme_font_size_override("normal_font_size", 12)
	vbox.add_child(ready_lbl)

	vbox.add_child(HSeparator.new())

	# Connection stats
	var conn_count: int = OpState.connections.size()
	var stats_lbl := Label.new()
	stats_lbl.text = "Evidence connections: %d  |  Items analyzed: %d / %d" % [
		conn_count,
		OpState.pinned_ids.size() if not OpState.pinned_ids.is_empty() else conn_count,
		OpState.evidence_items.size(),
	]
	stats_lbl.add_theme_font_size_override("font_size", 11)
	stats_lbl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5))
	vbox.add_child(stats_lbl)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer2)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var cancel_btn := Button.new()
	cancel_btn.text = "KEEP ANALYZING"
	cancel_btn.custom_minimum_size = Vector2(160, 40)
	cancel_btn.pressed.connect(func():
		cancelled.emit()
		hide()
	)
	btn_row.add_child(cancel_btn)

	var btn_spacer := Control.new()
	btn_spacer.custom_minimum_size = Vector2(16, 0)
	btn_row.add_child(btn_spacer)

	var confirm_btn := Button.new()
	confirm_btn.text = "GO DARK"
	confirm_btn.custom_minimum_size = Vector2(140, 40)
	confirm_btn.pressed.connect(func():
		confirmed.emit()
		hide()
	)
	btn_row.add_child(confirm_btn)

	vbox.add_child(btn_row)

	panel.add_child(vbox)
	add_child(panel)

	# Center on screen
	position = (get_viewport().get_visible_rect().size - size) / 2
	popup()
