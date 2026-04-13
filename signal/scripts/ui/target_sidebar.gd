## Target sidebar — left panel listing all targets with status.
##
## Maven-style: persistent list showing every detected contact.
## Click an entry to center the map on it. Status updates live.
extends PanelContainer


const STATUS_COLORS := {
	"unknown": Color(0.95, 0.6, 0.1),
	"hostile": Color(0.9, 0.2, 0.2),
	"friendly": Color(0.2, 0.8, 0.4),
	"asset": Color(0.3, 0.6, 0.9),
	"neutralized": Color(0.35, 0.35, 0.35),
}

var _entries: Dictionary = {}  # blip_id -> entry_node
var _scroll: ScrollContainer
var _list: VBoxContainer
var _header: Label


func _ready() -> void:
	# Style
	custom_minimum_size = Vector2(220, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.10, 0.95)
	sb.border_color = Color(0.15, 0.18, 0.25)
	sb.border_width_right = 1
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()

	# Maven-style header section
	var header_section := VBoxContainer.new()
	header_section.add_theme_constant_override("separation", 2)

	var title_row := HBoxContainer.new()
	var icon_lbl := Label.new()
	icon_lbl.text = "◉"
	icon_lbl.add_theme_font_size_override("font_size", 14)
	icon_lbl.add_theme_color_override("font_color", Color(0.3, 0.7, 0.9))
	title_row.add_child(icon_lbl)
	var sp1 := Control.new()
	sp1.custom_minimum_size = Vector2(6, 0)
	title_row.add_child(sp1)
	var title_lbl := Label.new()
	title_lbl.text = "AI THREAT ANALYSIS"
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
	title_row.add_child(title_lbl)
	header_section.add_child(title_row)

	# Tab bar
	var tab_row := HBoxContainer.new()
	for tab_name in ["Contacts", "Assets", "Intel"]:
		var tab := Button.new()
		tab.text = tab_name
		tab.custom_minimum_size = Vector2(60, 24)
		tab.add_theme_font_size_override("font_size", 10)
		tab_row.add_child(tab)
	header_section.add_child(tab_row)

	vbox.add_child(header_section)
	vbox.add_child(HSeparator.new())

	_header = Label.new()
	_header.text = "CONTACTS  0"
	_header.add_theme_font_size_override("font_size", 10)
	_header.add_theme_color_override("font_color", Color(0.4, 0.45, 0.55))
	vbox.add_child(_header)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_scroll.add_child(_list)
	vbox.add_child(_scroll)

	add_child(vbox)

	EventBus.blip_spawned.connect(_on_blip_spawned)
	EventBus.blip_classified.connect(_on_blip_classified)
	EventBus.mission_complete.connect(func(_g): _update_header())


func add_entry(blip_id: String, label: String, blip_type: String) -> void:
	if blip_id in _entries:
		return

	var entry := PanelContainer.new()
	entry.custom_minimum_size = Vector2(200, 90)  # Tall Maven-style cards
	var status_color: Color = STATUS_COLORS.get(blip_type, Color.GRAY)
	var esb := StyleBoxFlat.new()
	esb.bg_color = Color(0.08, 0.09, 0.13, 0.94)
	esb.border_color = Color(0.14, 0.17, 0.24)
	esb.set_border_width_all(1)
	esb.border_width_left = 3
	esb.border_color = status_color
	esb.set_corner_radius_all(3)
	esb.content_margin_left = 0
	esb.content_margin_right = 0
	esb.content_margin_top = 0
	esb.content_margin_bottom = 4
	entry.add_theme_stylebox_override("panel", esb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	# Colored header bar — Maven's "Top Match" / "Strong Match" bar
	var header_bar := PanelContainer.new()
	header_bar.custom_minimum_size = Vector2(0, 20)
	var hb_sb := StyleBoxFlat.new()
	if blip_type == "asset":
		hb_sb.bg_color = Color(0.12, 0.22, 0.18, 0.9)
	elif blip_type == "hostile":
		hb_sb.bg_color = Color(0.22, 0.12, 0.10, 0.9)
	else:
		hb_sb.bg_color = Color(0.18, 0.16, 0.10, 0.9)
	hb_sb.content_margin_left = 10
	hb_sb.content_margin_right = 8
	hb_sb.content_margin_top = 2
	hb_sb.content_margin_bottom = 2
	header_bar.add_theme_stylebox_override("panel", hb_sb)

	var hbar_row := HBoxContainer.new()
	var hbar_badge := Label.new()
	hbar_badge.name = "Badge"
	if blip_type == "asset":
		hbar_badge.text = "AVAILABLE"
		hbar_badge.add_theme_color_override("font_color", Color(0.3, 0.8, 0.5))
	elif blip_type == "hostile":
		hbar_badge.text = "TOP MATCH"
		hbar_badge.add_theme_color_override("font_color", Color(0.9, 0.4, 0.3))
	else:
		hbar_badge.text = "PENDING"
		hbar_badge.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3))
	hbar_badge.add_theme_font_size_override("font_size", 9)
	hbar_row.add_child(hbar_badge)

	var hbar_spacer := Control.new()
	hbar_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbar_row.add_child(hbar_spacer)

	var hbar_action := Label.new()
	hbar_action.text = "Edit Asset"
	hbar_action.add_theme_font_size_override("font_size", 9)
	hbar_action.add_theme_color_override("font_color", Color(0.3, 0.5, 0.7))
	hbar_row.add_child(hbar_action)

	header_bar.add_child(hbar_row)
	vbox.add_child(header_bar)

	# Content area with padding
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 1)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(8, 0)

	# Content below header bar — with left padding
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 0)

	# Left padding
	var lpad := Control.new()
	lpad.custom_minimum_size = Vector2(10, 0)
	top_row.add_child(lpad)

	var lbl := Label.new()
	lbl.name = "Label"
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(lbl)

	var type_lbl := Label.new()
	type_lbl.name = "Type"
	type_lbl.text = blip_type.to_upper()
	type_lbl.add_theme_font_size_override("font_size", 9)
	type_lbl.add_theme_color_override("font_color", status_color)
	top_row.add_child(type_lbl)

	var rpad := Control.new()
	rpad.custom_minimum_size = Vector2(8, 0)
	top_row.add_child(rpad)
	vbox.add_child(top_row)

	# Status line with left padding
	var status_row := HBoxContainer.new()
	var spad := Control.new()
	spad.custom_minimum_size = Vector2(10, 0)
	status_row.add_child(spad)

	var status_lbl := Label.new()
	status_lbl.name = "Status"
	status_lbl.text = "Pending classification"
	status_lbl.add_theme_font_size_override("font_size", 9)
	status_lbl.add_theme_color_override("font_color", Color(0.38, 0.43, 0.55))
	status_row.add_child(status_lbl)
	vbox.add_child(status_row)

	# Timestamp line with left padding
	var time_row := HBoxContainer.new()
	var tpad := Control.new()
	tpad.custom_minimum_size = Vector2(10, 0)
	time_row.add_child(tpad)

	var time_lbl := Label.new()
	time_lbl.name = "Timestamp"
	time_lbl.text = "LINK: Updated %ds ago" % int(Time.get_ticks_msec() / 1000)
	time_lbl.add_theme_font_size_override("font_size", 8)
	time_lbl.add_theme_color_override("font_color", Color(0.30, 0.35, 0.45))
	time_row.add_child(time_lbl)
	vbox.add_child(time_row)

	entry.add_child(vbox)

	# Click to select
	entry.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			EventBus.blip_clicked.emit(blip_id)
	)

	# Hover effect
	entry.mouse_entered.connect(func():
		esb.bg_color = Color(0.10, 0.12, 0.18, 0.95)
	)
	entry.mouse_exited.connect(func():
		esb.bg_color = Color(0.07, 0.08, 0.12, 0.92)
	)

	_list.add_child(entry)
	_entries[blip_id] = entry
	_update_header()


func update_entry(blip_id: String, label: String, blip_type: String) -> void:
	if blip_id not in _entries:
		return
	var entry: PanelContainer = _entries[blip_id]

	# Update the colored left border
	var status_color: Color = STATUS_COLORS.get(blip_type, Color.GRAY)
	var sb = entry.get_theme_stylebox("panel")
	if sb:
		sb.border_color = status_color

	# Find label and badge by walking the tree
	var vbox = entry.get_child(0) if entry.get_child_count() > 0 else null
	if not vbox:
		return

	for child in vbox.get_children():
		if child is HBoxContainer:
			# Check for Label node
			var lbl = child.get_node_or_null("Label")
			if lbl and not label.is_empty():
				lbl.text = label
			var type_lbl = child.get_node_or_null("Type")
			if type_lbl:
				type_lbl.text = blip_type.to_upper()
				type_lbl.add_theme_color_override("font_color", status_color)
			var badge = child.get_node_or_null("Badge")
			if badge:
				if blip_type == "neutralized":
					badge.text = "DONE"
					badge.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
				elif blip_type in ["hostile"]:
					badge.text = "CLASSIFIED"
					badge.add_theme_color_override("font_color", Color(0.3, 0.7, 0.5))
		elif child is Label and child.name == "Status":
			match blip_type:
				"hostile": child.text = "Target classified • Hostile"
				"neutralized": child.text = "Target neutralized"
				"asset": child.text = "Ready for tasking"

	# Dim neutralized entries
	if blip_type == "neutralized":
		entry.modulate = Color(0.5, 0.5, 0.5, 0.7)


func _update_header() -> void:
	var total := _entries.size()
	_header.text = "CONTACTS  %d" % total


func _on_blip_spawned(blip_id: String) -> void:
	# Will be called by main controller after adding blip
	pass


func _on_blip_classified(blip_id: String, new_type: String) -> void:
	# Find the entry and update it
	update_entry(blip_id, "", new_type)
