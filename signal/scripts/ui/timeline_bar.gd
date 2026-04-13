## Timeline bar — bottom bar showing active missions as progress segments.
##
## Maven-style Gantt view: each active mission is a colored bar
## showing progress from assignment to completion.
extends PanelContainer


var _missions: Dictionary = {}  # target_id -> {asset_label, progress, coa_label, color}
var _container: HBoxContainer


func _ready() -> void:
	# Style
	custom_minimum_size = Vector2(0, 32)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.95)
	sb.border_color = Color(0.12, 0.15, 0.22)
	sb.border_width_top = 1
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()

	# Label
	var lbl := Label.new()
	lbl.text = "MISSIONS"
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.3, 0.35, 0.42))
	lbl.custom_minimum_size = Vector2(70, 0)
	hbox.add_child(lbl)

	var sep := VSeparator.new()
	hbox.add_child(sep)

	_container = HBoxContainer.new()
	_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_container.add_theme_constant_override("separation", 8)
	hbox.add_child(_container)

	# Right side — coordinate/timestamp display (Maven-style)
	var sep2 := VSeparator.new()
	hbox.add_child(sep2)

	var coord_label := Label.new()
	coord_label.name = "CoordLabel"
	coord_label.text = "N/A"
	coord_label.add_theme_font_size_override("font_size", 10)
	coord_label.add_theme_color_override("font_color", Color(0.35, 0.4, 0.5))
	coord_label.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(coord_label)

	var time_label := Label.new()
	time_label.name = "TimeStamp"
	time_label.add_theme_font_size_override("font_size", 10)
	time_label.add_theme_color_override("font_color", Color(0.35, 0.4, 0.5))
	time_label.custom_minimum_size = Vector2(160, 0)
	hbox.add_child(time_label)

	add_child(hbox)

	EventBus.mission_started.connect(_on_mission_started)
	EventBus.asset_arrived.connect(_on_mission_done)
	EventBus.asset_returned.connect(func(_id): _rebuild())


func add_mission(target_id: String, asset_label: String, coa_label: String) -> void:
	_missions[target_id] = {
		"asset_label": asset_label,
		"coa_label": coa_label,
		"start_time": Time.get_ticks_msec(),
		"done": false,
	}
	_rebuild()


func complete_mission(target_id: String) -> void:
	if target_id in _missions:
		_missions[target_id]["done"] = true
	_rebuild()


func _rebuild() -> void:
	for child in _container.get_children():
		child.queue_free()

	for tid in _missions:
		var m: Dictionary = _missions[tid]
		if m.get("done", false):
			continue

		var seg := PanelContainer.new()
		seg.custom_minimum_size = Vector2(140, 22)
		var ssb := StyleBoxFlat.new()
		ssb.bg_color = Color(0.06, 0.08, 0.12, 0.9)
		ssb.border_color = Color(0.2, 0.4, 0.6, 0.5)
		ssb.set_border_width_all(1)
		ssb.set_corner_radius_all(2)
		ssb.content_margin_left = 6
		ssb.content_margin_right = 6
		ssb.content_margin_top = 2
		ssb.content_margin_bottom = 2
		seg.add_theme_stylebox_override("panel", ssb)

		var row := HBoxContainer.new()

		# Asset name
		var albl := Label.new()
		albl.text = m.get("asset_label", "?")
		albl.add_theme_font_size_override("font_size", 10)
		albl.add_theme_color_override("font_color", Color(0.3, 0.6, 0.9))
		row.add_child(albl)

		# Arrow
		var arrow := Label.new()
		arrow.text = " → "
		arrow.add_theme_font_size_override("font_size", 10)
		arrow.add_theme_color_override("font_color", Color(0.3, 0.35, 0.4))
		row.add_child(arrow)

		# COA type
		var clbl := Label.new()
		clbl.text = m.get("coa_label", "?").to_upper()
		clbl.add_theme_font_size_override("font_size", 10)
		clbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
		row.add_child(clbl)

		# Elapsed time
		var elapsed_ms: int = Time.get_ticks_msec() - m.get("start_time", 0)
		var elapsed_s: int = elapsed_ms / 1000
		var time_lbl := Label.new()
		time_lbl.text = " %ds" % elapsed_s
		time_lbl.add_theme_font_size_override("font_size", 9)
		time_lbl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5))
		row.add_child(time_lbl)

		seg.add_child(row)
		_container.add_child(seg)

	# Show "NO ACTIVE" if empty
	if _container.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "NO ACTIVE MISSIONS"
		empty.add_theme_font_size_override("font_size", 10)
		empty.add_theme_color_override("font_color", Color(0.25, 0.3, 0.35))
		_container.add_child(empty)


func _on_mission_started(target_id: String, coa_id: String, asset_id: String) -> void:
	# Main controller will call add_mission with proper labels
	pass


func _on_mission_done(asset_id: String, target_id: String) -> void:
	complete_mission(target_id)


func _process(_delta: float) -> void:
	# Refresh elapsed times every second
	if Engine.get_process_frames() % 60 == 0:
		if not _missions.is_empty():
			_rebuild()
		# Update timestamp
		var ts = get_node_or_null("TimeStamp")
		if not ts:
			# Try inside the HBoxContainer
			for child in get_children():
				if child is HBoxContainer:
					ts = child.get_node_or_null("TimeStamp")
					break
		if ts:
			var dt := Time.get_datetime_dict_from_system()
			ts.text = "%04d-%02d-%02d %02d:%02d:%02dZ" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
