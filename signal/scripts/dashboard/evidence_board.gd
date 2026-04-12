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
	"phone_transcript": Color(0.2, 0.8, 0.3, 1.0),    # Green
	"email": Color(0.3, 0.5, 0.9, 1.0),                # Blue
	"financial_record": Color(0.9, 0.8, 0.2, 1.0),     # Yellow
	"surveillance_log": Color(0.9, 0.3, 0.3, 1.0),     # Red
	"credential": Color(0.8, 0.4, 0.9, 1.0),           # Purple
	"document": Color(0.6, 0.6, 0.6, 1.0),             # Gray
}

const EVIDENCE_ICONS := {
	"phone_transcript": "PHONE",
	"email": "EMAIL",
	"financial_record": "$$",
	"surveillance_log": "EYE",
	"credential": "KEY",
	"document": "DOC",
}

const CONNECTION_TYPE_OPTIONS := [
	"mentions",
	"finances",
	"contacts",
	"location",
	"timeline",
	"identity",
]


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Map of evidence_id -> GraphNode instance
var _nodes: Dictionary = {}

## Connection counter for unique IDs
var _conn_counter: int = 0


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# GraphEdit settings
	right_disconnects = true
	snapping_enabled = true
	snapping_distance = 20
	minimap_enabled = true
	minimap_size = Vector2(200, 150)

	# Connect signals
	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)
	EventBus.intercepts_received.connect(_on_intercepts_received)
	EventBus.phase_changed.connect(_on_phase_changed)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func load_evidence(items: Array) -> void:
	"""Load evidence items onto the board as GraphNodes."""
	clear_board()

	var col := 0
	var row := 0
	var spacing := Vector2(280, 180)

	for item in items:
		var node := _create_evidence_node(item)
		add_child(node)
		node.position_offset = Vector2(col * spacing.x + 50, row * spacing.y + 50)

		_nodes[item.get("id", "")] = node

		col += 1
		if col >= 4:
			col = 0
			row += 1


func clear_board() -> void:
	"""Remove all evidence nodes and connections."""
	clear_connections()
	for node in _nodes.values():
		if is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	_conn_counter = 0


func get_prep_score() -> float:
	"""Compute and return the current prep score."""
	return OpState.compute_prep_score()


# ---------------------------------------------------------------------------
# Node creation
# ---------------------------------------------------------------------------

func _create_evidence_node(item: Dictionary) -> GraphNode:
	"""Create a GraphNode for an evidence item."""
	var node := GraphNode.new()
	var ev_id: String = item.get("id", "unknown")
	var ev_type: String = item.get("evidence_type", "document")

	node.name = "Evidence_%s" % ev_id
	node.title = "%s  %s" % [EVIDENCE_ICONS.get(ev_type, "?"), item.get("title", "Unknown")]
	node.size = Vector2(240, 100)
	node.resizable = true
	node.draggable = true

	# Color the title bar
	var color: Color = EVIDENCE_COLORS.get(ev_type, Color.GRAY)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, 0.3)
	sb.border_color = color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	node.add_theme_stylebox_override("titlebar", sb)

	var sb_selected := sb.duplicate()
	sb_selected.border_color = Color.WHITE
	sb_selected.set_border_width_all(2)
	node.add_theme_stylebox_override("titlebar_selected", sb_selected)

	# Content preview (first 80 chars)
	var content: String = item.get("content", "")
	var preview: String = content.substr(0, 80)
	if content.length() > 80:
		preview += "..."

	var label := RichTextLabel.new()
	label.text = preview
	label.fit_content = true
	label.custom_minimum_size = Vector2(220, 40)
	label.add_theme_font_size_override("normal_font_size", 11)
	label.add_theme_color_override("default_color", Color(0.7, 0.7, 0.7))
	node.add_child(label)

	# Classification badge
	var classification: String = item.get("classification", "confidential")
	var badge := Label.new()
	badge.text = classification.to_upper()
	badge.add_theme_font_size_override("font_size", 9)
	badge.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	node.add_child(badge)

	# Set up connection slots (1 input on left, 1 output on right)
	node.set_slot(0, true, 0, color, true, 0, color)

	# Store evidence ID as metadata
	node.set_meta("evidence_id", ev_id)

	# Click to open in document viewer
	node.node_selected.connect(func(): _on_evidence_selected(ev_id))

	return node


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_evidence_selected(evidence_id: String) -> void:
	"""Handle evidence node selection — open in document viewer."""
	EventBus.evidence_selected.emit(evidence_id)
	EventBus.document_opened.emit(evidence_id)


func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	"""Handle player drawing a connection between evidence items."""
	# Get evidence IDs from node metadata
	var from_gn: GraphNode = get_node(NodePath(from_node))
	var to_gn: GraphNode = get_node(NodePath(to_node))

	if not from_gn or not to_gn:
		return

	var from_id: String = from_gn.get_meta("evidence_id", "")
	var to_id: String = to_gn.get_meta("evidence_id", "")

	if from_id.is_empty() or to_id.is_empty() or from_id == to_id:
		return

	# Create the visual connection
	connect_node(from_node, from_port, to_node, to_port)

	# Default connection type — player can change via context menu later
	_conn_counter += 1
	var conn_id := "conn-%03d" % _conn_counter

	# Store in OpState
	OpState.connections.append({
		"id": conn_id,
		"from_id": from_id,
		"to_id": to_id,
		"type": "mentions",  # Default — TODO: popup selector
		"note": "",
	})

	EventBus.evidence_connected.emit(from_id, to_id, "mentions")


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	"""Handle player removing a connection."""
	disconnect_node(from_node, from_port, to_node, to_port)

	# Find and remove from OpState
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
	"""Handle new intercepts arriving during the op."""
	for ev_id in evidence_ids:
		if ev_id in OpState.evidence_items and ev_id not in _nodes:
			var item: Dictionary = OpState.evidence_items[ev_id]
			var node := _create_evidence_node(item)
			add_child(node)
			# Place new items at a random position near the center
			node.position_offset = Vector2(
				randf_range(200, 600),
				randf_range(100, 400),
			)
			_nodes[ev_id] = node


func _on_phase_changed(new_phase: String) -> void:
	"""Adjust board behavior based on current phase."""
	match new_phase:
		"signal":
			# Full interaction mode
			visible = true
		"blacksite":
			# Read-only reference mode — shrink but keep visible
			visible = true
		"debrief", "briefing":
			visible = false
