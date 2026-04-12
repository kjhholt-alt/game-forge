## Tactical map — the entire game screen. Dark grid with clickable blips.
##
## Renders a 2D tactical display with grid, pulsing blips, threat zones,
## asset trails, drag-drop assignment, and range rings.
extends Control


const GRID_SIZE := 60.0
const GRID_COLOR := Color(0.06, 0.08, 0.11)
const GRID_MAJOR_COLOR := Color(0.08, 0.11, 0.15)
const GRID_MAJOR_EVERY := 5

const BLIP_COLORS := {
	"unknown": Color(0.95, 0.6, 0.1),
	"hostile": Color(0.9, 0.2, 0.2),
	"friendly": Color(0.2, 0.8, 0.4),
	"asset": Color(0.3, 0.6, 0.9),
	"neutralized": Color(0.3, 0.3, 0.3),
	"active": Color(0.2, 0.9, 0.4),
}

var _camera_offset := Vector2.ZERO
var _zoom := 1.0
var _dragging := false
var _blips: Dictionary = {}
var _selected_blip: String = ""
var _hovered_blip: String = ""
var _time := 0.0

# Asset movement
var _moving_assets: Array = []

# Drag-drop
var _dragging_asset: String = ""
var _drag_pos := Vector2.ZERO

# Threat zones
var _threat_zones: Array = []  # [{center, radius, color}]

# Range rings (show when selecting asset)
var _show_range_ring: bool = false
var _range_ring_pos := Vector2.ZERO
var _range_ring_radius := 200.0

# Base marker
var _base_pos := Vector2(100, 400)

# Radar sweep
var _radar_angle := 0.0
var _radar_center := Vector2(400, 300)
var _radar_radius := 500.0

# Tooltip
var _tooltip_text := ""
var _tooltip_pos := Vector2.ZERO
var _tooltip_visible := false


class BlipData:
	var id: String
	var pos: Vector2
	var blip_type: String
	var label: String
	var radius: float = 14.0
	var pulse_phase: float = 0.0
	var classified: bool = false
	var handler_line: String = ""
	var busy: bool = false  # Asset is on a mission
	var mission_target: String = ""  # Which target this asset is assigned to


func _ready() -> void:
	_camera_offset = Vector2(200, 150)


func _process(delta: float) -> void:
	_time += delta
	_radar_angle = fmod(_radar_angle + delta * 0.8, TAU)

	for blip in _blips.values():
		blip.pulse_phase = fmod(blip.pulse_phase + delta * 2.0, TAU)

	# Update tooltip
	if not _hovered_blip.is_empty() and _hovered_blip in _blips:
		_tooltip_visible = true
		var blip: BlipData = _blips[_hovered_blip]
		_tooltip_pos = _world_to_screen(blip.pos) + Vector2(20, -40)
		var status := "BUSY" if blip.busy else blip.blip_type.to_upper()
		_tooltip_text = "%s\n%s" % [blip.label, status]
	else:
		_tooltip_visible = false

	# Move assets
	for i in range(_moving_assets.size() - 1, -1, -1):
		var mv: Dictionary = _moving_assets[i]
		mv["progress"] += delta * mv.get("speed", 0.5)
		if mv["progress"] >= 1.0:
			mv["progress"] = 1.0
			var asset_id: String = mv.get("asset_id", "")
			var target_id: String = mv.get("target_id", "")
			if asset_id in _blips:
				_blips[asset_id].pos = mv.get("to", Vector2.ZERO)
			if mv.get("returning", false):
				# Asset returned to base
				if asset_id in _blips:
					_blips[asset_id].busy = false
					_blips[asset_id].mission_target = ""
				EventBus.asset_returned.emit(asset_id)
			else:
				EventBus.asset_arrived.emit(asset_id, target_id)
			_moving_assets.remove_at(i)
		else:
			var from: Vector2 = mv.get("from", Vector2.ZERO)
			var to: Vector2 = mv.get("to", Vector2.ZERO)
			if mv.get("asset_id", "") in _blips:
				_blips[mv["asset_id"]].pos = from.lerp(to, mv["progress"])

	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.03, 0.045))
	_draw_grid()
	_draw_radar_sweep()
	_draw_threat_zones()
	_draw_range_ring()
	_draw_base()

	# Trails first (behind blips)
	for mv in _moving_assets:
		var from_s := _world_to_screen(mv.get("from", Vector2.ZERO))
		var to_s := _world_to_screen(mv.get("to", Vector2.ZERO))
		var current_s := _world_to_screen(
			(mv.get("from", Vector2.ZERO) as Vector2).lerp(mv.get("to", Vector2.ZERO), mv.get("progress", 0.0))
		)
		# Full path (dim)
		draw_dashed_line(from_s, to_s, Color(0.2, 0.4, 0.6, 0.15), 1.0, 8.0)
		# Traveled path (bright)
		draw_line(from_s, current_s, Color(0.3, 0.6, 0.9, 0.5), 1.5)

	# Blips
	for blip in _blips.values():
		_draw_blip(blip)

	# Drag-drop preview
	if not _dragging_asset.is_empty():
		draw_line(_world_to_screen(_blips[_dragging_asset].pos), _drag_pos, Color(0.3, 0.9, 0.5, 0.5), 2.0)
		draw_circle(_drag_pos, 6, Color(0.3, 0.9, 0.5, 0.5))

	# Selection ring
	if _selected_blip in _blips:
		var blip: BlipData = _blips[_selected_blip]
		var sp := _world_to_screen(blip.pos)
		var sr: float = (blip.radius + 8) * _zoom
		draw_arc(sp, sr, 0, TAU, 32, Color.WHITE, 1.5)
		# Rotating selection arc
		var arc_start: float = _time * 2.0
		draw_arc(sp, sr + 3, arc_start, arc_start + 1.5, 16, Color(1, 1, 1, 0.3), 1.0)

	# Edge indicators for off-screen blips
	_draw_edge_indicators()

	# Tooltip
	if _tooltip_visible:
		_draw_tooltip()


func _draw_radar_sweep() -> void:
	var center_s := _world_to_screen(_radar_center)
	var r_s: float = _radar_radius * _zoom
	# Sweep line
	var end := center_s + Vector2(cos(_radar_angle), sin(_radar_angle)) * r_s
	draw_line(center_s, end, Color(0.2, 0.8, 0.4, 0.08), 1.0)
	# Trailing fade (arc behind the sweep line)
	for i in range(20):
		var a: float = _radar_angle - float(i) * 0.04
		var e := center_s + Vector2(cos(a), sin(a)) * r_s
		var alpha: float = 0.06 * (1.0 - float(i) / 20.0)
		draw_line(center_s, e, Color(0.2, 0.8, 0.4, alpha), 1.0)


func _draw_edge_indicators() -> void:
	var margin := 20.0
	var indicator_size := 8.0
	for blip in _blips.values():
		if blip.blip_type == "neutralized":
			continue
		var sp := _world_to_screen(blip.pos)
		if sp.x >= -20 and sp.x <= size.x + 20 and sp.y >= -20 and sp.y <= size.y + 20:
			continue  # On screen, skip

		var color: Color = BLIP_COLORS.get(blip.blip_type, Color.WHITE)
		# Clamp to edge
		var edge_x: float = clamp(sp.x, margin, size.x - margin)
		var edge_y: float = clamp(sp.y, margin, size.y - margin)
		var edge_pos := Vector2(edge_x, edge_y)

		# Arrow pointing toward blip
		var dir := (sp - edge_pos).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var points := PackedVector2Array([
			edge_pos + dir * indicator_size,
			edge_pos - dir * indicator_size * 0.5 + perp * indicator_size * 0.5,
			edge_pos - dir * indicator_size * 0.5 - perp * indicator_size * 0.5,
		])
		draw_colored_polygon(points, Color(color.r, color.g, color.b, 0.6))


func _draw_tooltip() -> void:
	var pos := _tooltip_pos
	var lines := _tooltip_text.split("\n")
	var line_height := 16
	var width := 120
	var height: int = lines.size() * line_height + 12

	# Background
	draw_rect(Rect2(pos, Vector2(width, height)), Color(0.05, 0.06, 0.09, 0.92))
	draw_rect(Rect2(pos, Vector2(width, height)), Color(0.15, 0.2, 0.28), false, 1.0)

	# Text
	for i in range(lines.size()):
		var color := Color(0.8, 0.85, 0.9) if i == 0 else Color(0.5, 0.55, 0.6)
		var fsize := 12 if i == 0 else 10
		draw_string(ThemeDB.fallback_font, pos + Vector2(8, 16 + i * line_height), lines[i], HORIZONTAL_ALIGNMENT_LEFT, width - 16, fsize, color)


func _draw_grid() -> void:
	var gs: float = GRID_SIZE * _zoom
	if gs < 8:
		return
	var ox := fmod(_camera_offset.x, gs)
	var oy := fmod(_camera_offset.y, gs)
	var ix := int(-_camera_offset.x / gs)
	var x := ox
	while x < size.x:
		var c := GRID_MAJOR_COLOR if ix % GRID_MAJOR_EVERY == 0 else GRID_COLOR
		draw_line(Vector2(x, 0), Vector2(x, size.y), c, 1.0)
		x += gs
		ix += 1
	var iy := int(-_camera_offset.y / gs)
	var y := oy
	while y < size.y:
		var c := GRID_MAJOR_COLOR if iy % GRID_MAJOR_EVERY == 0 else GRID_COLOR
		draw_line(Vector2(0, y), Vector2(size.x, y), c, 1.0)
		y += gs
		iy += 1


func _draw_blip(blip: BlipData) -> void:
	var sp := _world_to_screen(blip.pos)
	if sp.x < -60 or sp.x > size.x + 60 or sp.y < -60 or sp.y > size.y + 60:
		return

	var color: Color = BLIP_COLORS.get(blip.blip_type, BLIP_COLORS["unknown"])
	var r: float = blip.radius * _zoom

	# Pulse ring (only non-neutralized)
	if blip.blip_type != "neutralized":
		var pr: float = r + sin(blip.pulse_phase) * 3.0 * _zoom
		draw_arc(sp, pr, 0, TAU, 24, Color(color.r, color.g, color.b, 0.2), 1.5)
		# Second pulse ring (delayed)
		var pr2: float = r + sin(blip.pulse_phase + 1.0) * 5.0 * _zoom
		draw_arc(sp, pr2, 0, TAU, 24, Color(color.r, color.g, color.b, 0.08), 1.0)

	# Outer ring
	draw_arc(sp, r, 0, TAU, 24, color, 2.0)

	# Inner fill
	draw_circle(sp, r * 0.45, Color(color.r, color.g, color.b, 0.35))

	# Center dot
	draw_circle(sp, 2.0 * _zoom, color)

	# Hover glow
	if blip.id == _hovered_blip:
		draw_circle(sp, r + 6 * _zoom, Color(1, 1, 1, 0.08))

	# Busy indicator (spinning arc for assets on mission)
	if blip.busy:
		var a: float = _time * 3.0
		draw_arc(sp, r + 4 * _zoom, a, a + 2.0, 12, Color(0.2, 0.9, 0.4, 0.6), 2.0)

	# Label
	if blip.classified or blip.blip_type in ["asset", "neutralized"]:
		draw_string(
			ThemeDB.fallback_font,
			sp + Vector2(-20, r + 16 * _zoom),
			blip.label,
			HORIZONTAL_ALIGNMENT_CENTER,
			40, int(10 * _zoom),
			Color(color.r, color.g, color.b, 0.8),
		)


func _draw_threat_zones() -> void:
	for tz in _threat_zones:
		var center_s := _world_to_screen(tz.get("center", Vector2.ZERO))
		var radius_s: float = tz.get("radius", 100) * _zoom
		var color: Color = tz.get("color", Color(0.9, 0.2, 0.2, 0.06))
		draw_circle(center_s, radius_s, color)
		draw_arc(center_s, radius_s, 0, TAU, 48, Color(color.r, color.g, color.b, 0.2), 1.0)


func _draw_range_ring() -> void:
	if not _show_range_ring:
		return
	var center_s := _world_to_screen(_range_ring_pos)
	var r_s: float = _range_ring_radius * _zoom
	draw_arc(center_s, r_s, 0, TAU, 48, Color(0.3, 0.6, 0.9, 0.15), 1.0)


func _draw_base() -> void:
	var sp := _world_to_screen(_base_pos)
	# Base icon — diamond shape
	var s: float = 10 * _zoom
	var points := PackedVector2Array([
		sp + Vector2(0, -s), sp + Vector2(s, 0), sp + Vector2(0, s), sp + Vector2(-s, 0),
	])
	draw_colored_polygon(points, Color(0.2, 0.5, 0.3, 0.3))
	draw_polyline(points + PackedVector2Array([points[0]]), Color(0.2, 0.8, 0.4, 0.5), 1.5)
	draw_string(ThemeDB.fallback_font, sp + Vector2(-12, s + 14 * _zoom), "BASE", HORIZONTAL_ALIGNMENT_CENTER, 24, int(9 * _zoom), Color(0.2, 0.7, 0.4, 0.5))


# --- Public API ---

func add_blip(id: String, pos: Vector2, blip_type: String, label: String, handler_line: String = "") -> void:
	var blip := BlipData.new()
	blip.id = id
	blip.pos = pos
	blip.blip_type = blip_type
	blip.label = label
	blip.handler_line = handler_line
	blip.pulse_phase = randf() * TAU
	_blips[id] = blip
	EventBus.blip_spawned.emit(id)


func classify_blip(id: String, new_type: String, new_label: String) -> void:
	if id in _blips:
		_blips[id].blip_type = new_type
		_blips[id].label = new_label
		_blips[id].classified = true
		EventBus.blip_classified.emit(id, new_type)


func move_asset(asset_id: String, target_id: String, speed: float = 0.3, returning: bool = false) -> void:
	if asset_id not in _blips or target_id not in _blips:
		return
	if not returning:
		_blips[asset_id].busy = true
		_blips[asset_id].mission_target = target_id
	_moving_assets.append({
		"asset_id": asset_id,
		"target_id": target_id,
		"from": _blips[asset_id].pos,
		"to": _blips[target_id].pos,
		"progress": 0.0,
		"speed": speed,
		"returning": returning,
	})


func return_asset_to_base(asset_id: String) -> void:
	if asset_id not in _blips:
		return
	# Create a temporary base blip to move toward
	var base_id := "_base_return"
	if base_id not in _blips:
		add_blip(base_id, _base_pos, "friendly", "")
	move_asset(asset_id, base_id, 0.6, true)


func add_threat_zone(center: Vector2, radius: float, color: Color = Color(0.9, 0.2, 0.2, 0.06)) -> void:
	_threat_zones.append({"center": center, "radius": radius, "color": color})


func remove_blip(id: String) -> void:
	_blips.erase(id)

func get_blip(id: String) -> BlipData:
	return _blips.get(id)

func set_base_pos(pos: Vector2) -> void:
	_base_pos = pos

func is_asset_busy(asset_id: String) -> bool:
	if asset_id in _blips:
		return _blips[asset_id].busy
	return false


# --- Coordinate conversion ---

func _world_to_screen(world_pos: Vector2) -> Vector2:
	return (world_pos * _zoom) + _camera_offset

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return (screen_pos - _camera_offset) / _zoom


# --- Input ---

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			var before := _screen_to_world(event.position)
			_zoom = clamp(_zoom * 1.1, 0.3, 3.0)
			var after := _screen_to_world(event.position)
			_camera_offset += (after - before) * _zoom
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var before := _screen_to_world(event.position)
			_zoom = clamp(_zoom * 0.9, 0.3, 3.0)
			var after := _screen_to_world(event.position)
			_camera_offset += (after - before) * _zoom
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var clicked := _get_blip_at(event.position)
				if clicked:
					# Check if it's an asset — start drag
					if _blips[clicked].blip_type == "asset" and not _blips[clicked].busy:
						_dragging_asset = clicked
						_drag_pos = event.position
						_show_range_ring = true
						_range_ring_pos = _blips[clicked].pos
					else:
						_selected_blip = clicked
						EventBus.blip_clicked.emit(clicked)
				else:
					_selected_blip = ""
					_dragging_asset = ""
					_show_range_ring = false
			else:
				# Release drag — check if dropped on a target
				if not _dragging_asset.is_empty():
					var drop_target := _get_blip_at(event.position)
					if drop_target and drop_target != _dragging_asset and _blips[drop_target].classified:
						EventBus.asset_assigned.emit(_dragging_asset, drop_target)
					_dragging_asset = ""
					_show_range_ring = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var clicked := _get_blip_at(event.position)
			if clicked and clicked in _blips and _blips[clicked].classified and _blips[clicked].blip_type != "asset":
				EventBus.coa_requested.emit(clicked)

	if event is InputEventMouseMotion:
		if _dragging:
			_camera_offset += event.relative
		elif not _dragging_asset.is_empty():
			_drag_pos = event.position
		else:
			_hovered_blip = _get_blip_at(event.position)


func _get_blip_at(screen_pos: Vector2) -> String:
	var closest := ""
	var closest_dist := 9999.0
	for blip in _blips.values():
		var bs := _world_to_screen(blip.pos)
		var d := screen_pos.distance_to(bs)
		if d <= (blip.radius + 8) * _zoom and d < closest_dist:
			closest = blip.id
			closest_dist = d
	return closest
