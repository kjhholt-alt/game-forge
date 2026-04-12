## Evidence Board UI — SIGNAL phase conspiracy board.
extends Control

const BG_COLOR := Color(0.025, 0.03, 0.045)
const CARD_BG := Color(0.04, 0.05, 0.07, 0.95)
const CARD_BORDER := Color(0.12, 0.15, 0.2)
const SEL_BORDER := Color(0.3, 0.6, 0.9)
const TEXT_PRI := Color(0.75, 0.8, 0.85)
const TEXT_SEC := Color(0.45, 0.5, 0.58)
const GREEN := Color(0.2, 0.8, 0.4)
const RED := Color(0.9, 0.3, 0.2)
const PANEL_BG := Color(0.03, 0.035, 0.05, 0.95)

const CLS_CLR := {
	"unclassified": Color(0.45, 0.48, 0.52), "confidential": Color(0.3, 0.5, 0.9),
	"secret": Color(0.9, 0.75, 0.2), "top_secret": Color(0.9, 0.25, 0.2),
}
const TYPE_LBL := {
	"phone_transcript": "PHONE", "email": "EMAIL", "financial_record": "FINANCE",
	"surveillance_log": "SURVEIL", "document": "DOC",
}

var _grid: GridContainer
var _conn_list: VBoxContainer
var _prep_bar: ProgressBar
var _prep_label: Label
var _doc_viewer: PanelContainer
var _doc_content: RichTextLabel
var _doc_title: Label
var _card_nodes: Dictionary = {}
var _first_sel: String = ""


func _ready() -> void:
	visible = false
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	EventBus.phase_changed.connect(_on_phase_changed)

func _sb(bg: Color, border: Color = CARD_BORDER, bw: int = 1, cr: int = 4, margin: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(bw); s.set_corner_radius_all(cr)
	s.content_margin_left = margin; s.content_margin_right = margin
	s.content_margin_top = margin; s.content_margin_bottom = margin
	return s

func _lbl(text: String, size: int, color: Color, align: int = -1) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if align >= 0:
		l.horizontal_alignment = align as HorizontalAlignment
	return l

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.color = BG_COLOR; bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var hsplit := HSplitContainer.new()
	hsplit.anchors_preset = Control.PRESET_FULL_RECT
	hsplit.offset_left = 16; hsplit.offset_top = 16
	hsplit.offset_right = -16; hsplit.offset_bottom = -16
	hsplit.dragger_visibility = HSplitContainer.DRAGGER_HIDDEN
	add_child(hsplit)

	hsplit.add_child(_build_left())
	hsplit.add_child(_build_right())
	hsplit.resized.connect(func(): hsplit.split_offset = int(hsplit.size.x * 0.70))

	_doc_viewer = _build_doc_viewer()
	add_child(_doc_viewer)


func _build_left() -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 7.0
	p.add_theme_stylebox_override("panel", _sb(PANEL_BG))

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.add_child(_lbl("// SIGNAL — EVIDENCE BOARD //", 12, Color(0.4, 0.55, 0.7, 0.8)))
	vb.add_child(_lbl("Click two items to link. Double-click to read. [ESC] cancel.", 11, TEXT_SEC))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	vb.add_child(scroll)

	p.add_child(vb)
	return p


func _build_right() -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 3.0
	p.add_theme_stylebox_override("panel", _sb(PANEL_BG))

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)

	# Prep score
	vb.add_child(_lbl("PREP SCORE", 11, TEXT_SEC))
	_prep_bar = ProgressBar.new()
	_prep_bar.min_value = 0.0; _prep_bar.max_value = 100.0; _prep_bar.value = 0.0
	_prep_bar.show_percentage = false; _prep_bar.custom_minimum_size = Vector2(0, 18)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.06, 0.07, 0.1); bar_bg.set_corner_radius_all(3)
	_prep_bar.add_theme_stylebox_override("background", bar_bg)
	_update_bar_fill(0.0)
	vb.add_child(_prep_bar)

	_prep_label = _lbl("0%", 20, RED, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(_prep_label)

	vb.add_child(HSeparator.new())

	# Connections list
	vb.add_child(_lbl("CONNECTIONS", 11, TEXT_SEC))
	var cs := ScrollContainer.new()
	cs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_conn_list = VBoxContainer.new()
	_conn_list.add_theme_constant_override("separation", 4)
	_conn_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cs.add_child(_conn_list)
	vb.add_child(cs)

	# GO DARK indicator
	var gd := PanelContainer.new()
	gd.custom_minimum_size = Vector2(0, 44)
	gd.add_theme_stylebox_override("panel", _sb(Color(0.08, 0.12, 0.18, 0.9), Color(0.2, 0.4, 0.6, 0.6), 1, 4, 10))
	var gl := _lbl("[TAB]  GO DARK", 14, Color(0.4, 0.7, 0.9), HORIZONTAL_ALIGNMENT_CENTER)
	gd.add_child(gl)
	var tw := gl.create_tween().set_loops()
	tw.tween_property(gl, "modulate:a", 0.4, 1.2)
	tw.tween_property(gl, "modulate:a", 1.0, 1.2)
	vb.add_child(gd)

	p.add_child(vb)
	return p


func _build_doc_viewer() -> PanelContainer:
	var v := PanelContainer.new()
	v.visible = false; v.anchors_preset = Control.PRESET_CENTER
	v.offset_left = -360; v.offset_top = -260; v.offset_right = 360; v.offset_bottom = 260
	v.add_theme_stylebox_override("panel", _sb(Color(0.03, 0.035, 0.05, 0.98), SEL_BORDER, 2, 6, 20))

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)

	var row := HBoxContainer.new()
	_doc_title = _lbl("", 14, TEXT_PRI)
	_doc_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_doc_title)
	var cb := Button.new()
	cb.text = " X "; cb.add_theme_font_size_override("font_size", 12)
	var cs := _sb(Color(0.08, 0.06, 0.06, 0.9), Color.TRANSPARENT, 0, 3, 4)
	cb.add_theme_stylebox_override("normal", cs)
	cb.add_theme_stylebox_override("hover", cs)
	cb.add_theme_stylebox_override("pressed", cs)
	cb.pressed.connect(_close_doc)
	row.add_child(cb)
	vb.add_child(row)

	_doc_content = RichTextLabel.new()
	_doc_content.bbcode_enabled = false; _doc_content.scroll_active = true
	_doc_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_doc_content.add_theme_font_size_override("normal_font_size", 12)
	_doc_content.add_theme_color_override("default_color", Color(0.65, 0.7, 0.78))
	vb.add_child(_doc_content)

	v.add_child(vb)
	return v

func _make_card(item: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(220, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var eid: String = item.get("id", "")
	var cls: String = item.get("classification", "unclassified")
	var clue: bool = item.get("is_clue", false)

	var s := _sb(CARD_BG if clue else Color(0.035, 0.04, 0.055, 0.8), CARD_BORDER, 1, 4, 8)
	if clue:
		s.border_width_left = 3; s.border_color = Color(GREEN, 0.5)
	card.add_theme_stylebox_override("panel", s)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)

	# Classification dot + type + class label
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(4, 14); dot.color = CLS_CLR.get(cls, Color.GRAY)
	top.add_child(dot)
	top.add_child(_lbl(TYPE_LBL.get(item.get("evidence_type", ""), "DOC"), 9, CLS_CLR.get(cls, Color.GRAY)))
	var cl := _lbl(cls.to_upper(), 8, Color(TEXT_SEC, 0.6))
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(cl)
	vb.add_child(top)

	# Title (truncated)
	var t: String = item.get("title", "Unknown")
	if t.length() > 42: t = t.substr(0, 39) + "..."
	var tl := _lbl(t, 12, TEXT_PRI if clue else Color(TEXT_PRI, 0.55))
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(tl)

	# Source
	var sl := _lbl(item.get("source", ""), 9, Color(TEXT_SEC, 0.6))
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sl)

	# Tags
	var tags: Array = item.get("tags", [])
	if not tags.is_empty():
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 2)
		for tag in tags:
			var b := PanelContainer.new()
			b.add_theme_stylebox_override("panel", _sb(Color(0.08, 0.1, 0.15, 0.8), Color.TRANSPARENT, 0, 2, 4))
			b.add_child(_lbl(tag, 8, Color(0.5, 0.6, 0.75)))
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			flow.add_child(b)
		vb.add_child(flow)

	card.add_child(vb)
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_card_click(eid, card)
	)
	return card

func _on_phase_changed(phase: String) -> void:
	if phase == "signal":
		_populate(); visible = true
	else:
		visible = false; _close_doc(); _clear_sel()


func _populate() -> void:
	for c in _grid.get_children(): c.queue_free()
	_card_nodes.clear()
	for c in _conn_list.get_children(): c.queue_free()

	for eid in OpState.evidence_items:
		var item: Dictionary = OpState.evidence_items[eid]
		if not item.get("discovered", false): continue
		var card := _make_card(item)
		_grid.add_child(card); _card_nodes[eid] = card

	for conn in OpState.connections:
		_add_conn_label(conn.get("from_id", ""), conn.get("to_id", ""))
	_refresh_prep()

func _on_card_click(eid: String, card: PanelContainer) -> void:
	if _doc_viewer.visible:
		_close_doc(); return

	if _first_sel.is_empty():
		_first_sel = eid; _set_sel(eid, true)
		var tw := card.create_tween().set_loops(6)
		tw.tween_property(card, "modulate:a", 0.6, 0.35)
		tw.tween_property(card, "modulate:a", 1.0, 0.35)
		tw.finished.connect(func():
			if not _first_sel.is_empty(): _clear_sel()
		)
		VoiceHandler.speak("Select a second item to link.")
	elif _first_sel == eid:
		_clear_sel(); _open_doc(eid)
	else:
		var from := _first_sel; _clear_sel(); _link(from, eid)


func _link(from_id: String, to_id: String) -> void:
	for c in OpState.connections:
		var f: String = c.get("from_id", ""); var t: String = c.get("to_id", "")
		if (f == from_id and t == to_id) or (f == to_id and t == from_id):
			VoiceHandler.speak("Already linked."); return

	OpState.connections.append({"id": "conn-%d" % OpState.connections.size(),
		"from_id": from_id, "to_id": to_id, "type": "linked", "note": ""})
	_add_conn_label(from_id, to_id)

	if _card_nodes.has(from_id): Juice.glow_border(_card_nodes[from_id], SEL_BORDER, 0.6)
	if _card_nodes.has(to_id): Juice.glow_border(_card_nodes[to_id], SEL_BORDER, 0.6)

	var score: float = OpState.compute_prep_score()
	EventBus.prep_score_updated.emit(score)
	EventBus.evidence_connection_made.emit(from_id, to_id, "linked")
	_refresh_prep()

	# Hint on good links (check both directions)
	var fi: Dictionary = OpState.evidence_items.get(from_id, {})
	var ti: Dictionary = OpState.evidence_items.get(to_id, {})
	if (fi.get("is_clue", false) and to_id in fi.get("clue_target_ids", [])) \
		or (ti.get("is_clue", false) and from_id in ti.get("clue_target_ids", [])):
		VoiceHandler.speak("Good link. That connection checks out.")
		Juice.float_text(self, "+INTEL", Vector2(size.x * 0.5, size.y * 0.4), GREEN)


func _add_conn_label(from_id: String, to_id: String) -> void:
	var ft := _short(from_id); var tt := _short(to_id)
	var l := _lbl("%s  ->  %s" % [ft, tt], 10, Color(0.55, 0.65, 0.8))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_conn_list.add_child(l)

func _short(eid: String) -> String:
	var t: String = OpState.evidence_items.get(eid, {}).get("title", eid)
	return t.substr(0, 22) + "..." if t.length() > 25 else t

func _set_sel(eid: String, on: bool) -> void:
	var card: PanelContainer = _card_nodes.get(eid)
	if not card: return
	var s: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate()
	if on:
		s.border_color = SEL_BORDER; s.set_border_width_all(2)
	else:
		var item: Dictionary = OpState.evidence_items.get(eid, {})
		s.set_border_width_all(1)
		if item.get("is_clue", false):
			s.border_color = Color(GREEN, 0.5); s.border_width_left = 3
		else:
			s.border_color = CARD_BORDER
	card.add_theme_stylebox_override("panel", s)

func _clear_sel() -> void:
	if not _first_sel.is_empty():
		_set_sel(_first_sel, false)
		var card: PanelContainer = _card_nodes.get(_first_sel)
		if card: card.modulate.a = 1.0
	_first_sel = ""

func _open_doc(eid: String) -> void:
	var item: Dictionary = OpState.evidence_items.get(eid, {})
	if item.is_empty(): return
	_doc_title.text = item.get("title", "Unknown")
	var cls: String = item.get("classification", "unclassified")
	_doc_content.text = "[%s] %s\nSource: %s\n\n%s" % [
		cls.to_upper(), TYPE_LBL.get(item.get("evidence_type", ""), "DOC"),
		item.get("source", "Unknown"), item.get("content", "No content.")]
	_doc_viewer.visible = true
	Juice.pop(_doc_viewer, 1.05, 0.15)
	if item.get("is_clue", false):
		VoiceHandler.speak("Interesting. Check the names mentioned.")

func _close_doc() -> void:
	_doc_viewer.visible = false

func _refresh_prep() -> void:
	var pct: float = OpState.prep_score * 100.0
	_prep_bar.value = pct
	_prep_label.text = "%d%%" % int(pct)
	var c: Color = GREEN if pct >= 70 else (Color(0.9, 0.75, 0.2) if pct >= 35 else RED)
	_prep_label.add_theme_color_override("font_color", c)
	_update_bar_fill(OpState.prep_score)

func _update_bar_fill(n: float) -> void:
	var s := StyleBoxFlat.new(); s.set_corner_radius_all(3)
	s.bg_color = GREEN if n >= 0.7 else (Color(0.9, 0.75, 0.2) if n >= 0.35 else RED)
	_prep_bar.add_theme_stylebox_override("fill", s)

func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _doc_viewer.visible:
			_close_doc(); get_viewport().set_input_as_handled()
		elif not _first_sel.is_empty():
			_clear_sel(); get_viewport().set_input_as_handled()
