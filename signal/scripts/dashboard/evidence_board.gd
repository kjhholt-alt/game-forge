## Evidence board — GraphEdit-based intelligence pinboard.
##
## The player's home base during SIGNAL phase. Evidence items appear as
## draggable GraphNodes. The player draws connections between them to
## map out the conspiracy before entering BLACKSITE.
extends GraphEdit


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const EVIDENCE_COLORS := {
	"phone_transcript": Color(0.2, 0.8, 0.3),
	"email": Color(0.3, 0.5, 0.9),
	"financial_record": Color(0.9, 0.8, 0.2),
	"surveillance_log": Color(0.9, 0.3, 0.3),
	"credential": Color(0.8, 0.4, 0.9),
	"document": Color(0.6, 0.6, 0.6),
}

const EVIDENCE_ICONS := {
	"phone_transcript": "PHONE",
	"email": "EMAIL",
	"financial_record": "FINANCE",
	"surveillance_log": "SURVEIL",
	"credential": "KEY",
	"document": "DOC",
}

const NODE_WIDTH := 300
const NODE_MIN_HEIGHT := 120
const GRID_COLS := 3
const GRID_SPACING_X := 360
const GRID_SPACING_Y := 200
const GRID_OFFSET := Vector2(40, 40)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _nodes: Dictionary = {}
var _conn_counter: int = 0
var _pending_connection: Dictionary = {}  # Stores pending connection while popup is open
var _connection_popup: PopupPanel = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	right_disconnects = true
	snapping_enabled = true
	snapping_distance = 20
	minimap_enabled = true
	minimap_size = Vector2(200, 150)
	show_grid = true

	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)
	EventBus.intercepts_received.connect(_on_intercepts_received)
	EventBus.phase_changed.connect(_on_phase_changed)

	# Create connection type popup
	_connection_popup = preload("res://scripts/dashboard/connection_popup.gd").new()
	add_child(_connection_popup)
	_connection_popup.connection_confirmed.connect(_on_connection_type_selected)
	_connection_popup.connection_cancelled.connect(_on_connection_cancelled)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func load_evidence(items: Array) -> void:
	clear_board()

	var col := 0
	var row := 0

	for item in items:
		var node := _create_evidence_node(item)
		add_child(node)
		node.position_offset = GRID_OFFSET + Vector2(col * GRID_SPACING_X, row * GRID_SPACING_Y)

		_nodes[item.get("id", "")] = node

		col += 1
		if col >= GRID_COLS:
			col = 0
			row += 1

	# Zoom to fit content
	zoom = 0.85
	scroll_offset = Vector2(-20, -20)


func clear_board() -> void:
	clear_connections()
	for node in _nodes.values():
		if is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	_conn_counter = 0


func get_prep_score() -> float:
	return OpState.compute_prep_score()


# ---------------------------------------------------------------------------
# Node creation
# ---------------------------------------------------------------------------

func _create_evidence_node(item: Dictionary) -> GraphNode:
	var node := GraphNode.new()
	var ev_id: String = item.get("id", "unknown")
	var ev_type: String = item.get("evidence_type", "document")
	var color: Color = EVIDENCE_COLORS.get(ev_type, Color.GRAY)
	var icon_tag: String = EVIDENCE_ICONS.get(ev_type, "?")

	node.name = "Evidence_%s" % ev_id
	node.title = "[%s]  %s" % [icon_tag, item.get("title", "Unknown")]
	node.custom_minimum_size = Vector2(NODE_WIDTH, NODE_MIN_HEIGHT)
	node.resizable = false
	node.draggable = true

	# --- Title bar styling ---
	var sb_title := StyleBoxFlat.new()
	sb_title.bg_color = Color(color.r * 0.3, color.g * 0.3, color.b * 0.3, 0.9)
	sb_title.border_color = color
	sb_title.border_width_top = 2
	sb_title.border_width_left = 1
	sb_title.border_width_right = 1
	sb_title.border_width_bottom = 0
	sb_title.corner_radius_top_left = 4
	sb_title.corner_radius_top_right = 4
	sb_title.content_margin_left = 8
	sb_title.content_margin_right = 8
	sb_title.content_margin_top = 6
	sb_title.content_margin_bottom = 6
	node.add_theme_stylebox_override("titlebar", sb_title)

	var sb_sel := sb_title.duplicate()
	sb_sel.border_color = Color.WHITE
	sb_sel.border_width_top = 2
	sb_sel.border_width_left = 2
	sb_sel.border_width_right = 2
	node.add_theme_stylebox_override("titlebar_selected", sb_sel)

	# --- Panel body styling ---
	var sb_panel := StyleBoxFlat.new()
	sb_panel.bg_color = Color(0.08, 0.09, 0.12, 0.95)
	sb_panel.border_color = Color(color.r * 0.5, color.g * 0.5, color.b * 0.5, 0.6)
	sb_panel.set_border_width_all(1)
	sb_panel.border_width_top = 0
	sb_panel.corner_radius_bottom_left = 4
	sb_panel.corner_radius_bottom_right = 4
	sb_panel.content_margin_left = 10
	sb_panel.content_margin_right = 10
	sb_panel.content_margin_top = 8
	sb_panel.content_margin_bottom = 8
	node.add_theme_stylebox_override("panel", sb_panel)
	node.add_theme_stylebox_override("panel_selected", sb_panel)

	# --- Title font color ---
	node.add_theme_color_override("title_color", color)

	# --- Content label ---
	var content: String = item.get("content", "")
	var preview: String = content.substr(0, 120).replace("\n", " ")
	if content.length() > 120:
		preview += "..."

	var label := Label.new()
	label.text = preview
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(NODE_WIDTH - 30, 50)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.65, 0.68, 0.72))
	node.add_child(label)

	# --- Classification + type badges ---
	var badge_row := HBoxContainer.new()
	badge_row.custom_minimum_size = Vector2(NODE_WIDTH - 30, 20)

	var classification: String = item.get("classification", "confidential")
	var cls_label := Label.new()
	cls_label.text = classification.to_upper()
	cls_label.add_theme_font_size_override("font_size", 10)
	match classification:
		"top_secret": cls_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
		"secret": cls_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
		"confidential": cls_label.add_theme_color_override("font_color", Color(0.3, 0.5, 0.9))
		_: cls_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	badge_row.add_child(cls_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge_row.add_child(spacer)

	var ts: String = item.get("timestamp", "")
	if ts.length() > 10:
		ts = ts.substr(0, 10)
	var ts_label := Label.new()
	ts_label.text = ts
	ts_label.add_theme_font_size_override("font_size", 10)
	ts_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	badge_row.add_child(ts_label)

	node.add_child(badge_row)

	# --- Connection slots ---
	node.set_slot(0, true, 0, color, true, 0, color)

	# --- Metadata ---
	node.set_meta("evidence_id", ev_id)

	# --- Selection ---
	node.node_selected.connect(func(): _on_evidence_selected(ev_id))

	return node


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_evidence_selected(evidence_id: String) -> void:
	EventBus.evidence_selected.emit(evidence_id)
	EventBus.document_opened.emit(evidence_id)


func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var from_gn: GraphNode = get_node(NodePath(from_node))
	var to_gn: GraphNode = get_node(NodePath(to_node))

	if not from_gn or not to_gn:
		return

	var from_id: String = from_gn.get_meta("evidence_id", "")
	var to_id: String = to_gn.get_meta("evidence_id", "")

	if from_id.is_empty() or to_id.is_empty() or from_id == to_id:
		return

	# Draw the visual connection immediately
	connect_node(from_node, from_port, to_node, to_port)

	# Store pending connection and show type selector
	_pending_connection = {
		"from_node": from_node,
		"from_port": from_port,
		"to_node": to_node,
		"to_port": to_port,
		"from_id": from_id,
		"to_id": to_id,
	}
	_connection_popup.show_at(get_viewport().get_mouse_position())


func _on_connection_type_selected(conn_type: String, note: String) -> void:
	if _pending_connection.is_empty():
		return

	_conn_counter += 1
	var conn_id := "conn-%03d" % _conn_counter

	OpState.connections.append({
		"id": conn_id,
		"from_id": _pending_connection.get("from_id", ""),
		"to_id": _pending_connection.get("to_id", ""),
		"type": conn_type,
		"note": note,
	})

	EventBus.evidence_connected.emit(
		_pending_connection.get("from_id", ""),
		_pending_connection.get("to_id", ""),
		conn_type,
	)
	_pending_connection = {}


func _on_connection_cancelled() -> void:
	# Remove the visual connection that was already drawn
	if not _pending_connection.is_empty():
		disconnect_node(
			_pending_connection.get("from_node", ""),
			_pending_connection.get("from_port", 0),
			_pending_connection.get("to_node", ""),
			_pending_connection.get("to_port", 0),
		)
		_pending_connection = {}


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	disconnect_node(from_node, from_port, to_node, to_port)

	var from_gn: GraphNode = get_node(NodePath(from_node))
	var to_gn: GraphNode = get_node(NodePath(to_node))
	if not from_gn or not to_gn:
		return

	var from_id: String = from_gn.get_meta("evidence_id", "")
	var to_id: String = to_gn.get_meta("evidence_id", "")

	for i in range(OpState.connections.size() - 1, -1, -1):
		var conn: Dictionary = OpState.connections[i]
		if conn.get("from_id") == from_id and conn.get("to_id") == to_id:
			var conn_id: String = conn.get("id", "")
			OpState.connections.remove_at(i)
			EventBus.evidence_disconnected.emit(conn_id)
			break


func _on_intercepts_received(evidence_ids: Array) -> void:
	for ev_id in evidence_ids:
		if ev_id in OpState.evidence_items and ev_id not in _nodes:
			var item: Dictionary = OpState.evidence_items[ev_id]
			var node := _create_evidence_node(item)
			add_child(node)
			node.position_offset = Vector2(
				randf_range(100, 800),
				randf_range(80, 500),
			)
			_nodes[ev_id] = node


func _on_phase_changed(new_phase: String) -> void:
	match new_phase:
		"signal":
			visible = true
		"blacksite":
			visible = true
		"debrief", "briefing":
			visible = false
