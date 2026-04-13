## Tactical map — the entire game screen. Dark grid with clickable blips.
##
## Renders a 2D tactical display with grid, pulsing blips, threat zones,
## asset trails, drag-drop assignment, and range rings.
extends Control


const GRID_SIZE := 150.0
const GRID_COLOR := Color(0.045, 0.055, 0.075)
const GRID_MAJOR_COLOR := Color(0.06, 0.075, 0.1)
const GRID_MAJOR_EVERY := 4

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
var _radar_center := Vector2(800, 450)
var _radar_radius := 1000.0

# Tooltip
var _tooltip_text := ""
var _tooltip_pos := Vector2.ZERO
var _tooltip_visible := false


class BlipData:
	var id: String
	var pos: Vector2
	var blip_type: String
	var label: String
	var radius: float = 28.0
	var pulse_phase: float = 0.0
	var classified: bool = false
	var handler_line: String = ""
	var busy: bool = false
	var mission_target: String = ""
	# Spawn animation
	var spawn_progress: float = 0.0  # 0=invisible, 1=fully visible
	var spawning: bool = true
	# Classify animation
	var classify_flash: float = 0.0  # 1.0 when just classified, fades to 0


var _onboarding_blip: String = ""  # First blip to highlight for onboarding
var _onboarding_active := true

func _ready() -> void:
	# Camera starts centered — content fills viewport
	_camera_offset = Vector2(100, 60)


func _process(delta: float) -> void:
	_time += delta
	_radar_angle = fmod(_radar_angle + delta * 0.8, TAU)

	for blip in _blips.values():
		blip.pulse_phase = fmod(blip.pulse_phase + delta * 2.0, TAU)
		# Spawn animation
		if blip.spawning:
			blip.spawn_progress = min(1.0, blip.spawn_progress + delta * 2.5)
			if blip.spawn_progress >= 1.0:
				blip.spawning = false
		# Classify flash decay
		if blip.classify_flash > 0:
			blip.classify_flash = max(0.0, blip.classify_flash - delta * 1.5)

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
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.04))
	_draw_grid()
	_draw_sector_labels()
	_draw_radar_sweep()
	_draw_threat_zones()
	_draw_range_ring()
	_draw_base()

	# Trails with pulsing data-flow effect
	for mv in _moving_assets:
		var from_s := _world_to_screen(mv.get("from", Vector2.ZERO))
		var to_s := _world_to_screen(mv.get("to", Vector2.ZERO))
		var prog: float = mv.get("progress", 0.0)
		var current_s := _world_to_screen(
			(mv.get("from", Vector2.ZERO) as Vector2).lerp(mv.get("to", Vector2.ZERO), prog)
		)
		# Full planned path (dim dashed)
		draw_dashed_line(from_s, to_s, Color(0.15, 0.3, 0.5, 0.12), 1.0, 10.0)
		# Traveled path (solid bright)
		if from_s.distance_to(current_s) > 2:
			draw_line(from_s, current_s, Color(0.3, 0.6, 0.9, 0.6), 2.0)
		# Pulsing dot along the trail (data flow effect)
		var pulse_pos: float = fmod(prog + _time * 0.3, 1.0)
		var dot_s := from_s.lerp(to_s, pulse_pos)
		draw_circle(dot_s, 3.0, Color(0.4, 0.8, 1.0, 0.4))

	# Blips
	for blip in _blips.values():
		_draw_blip(blip)

	# Drag-drop preview — thicker line with glow
	if not _dragging_asset.is_empty() and _dragging_asset in _blips:
		var asset_sp := _world_to_screen(_blips[_dragging_asset].pos)
		# Glow line
		draw_line(asset_sp, _drag_pos, Color(0.2, 0.9, 0.4, 0.15), 6.0)
		# Core line
		draw_line(asset_sp, _drag_pos, Color(0.3, 0.9, 0.5, 0.6), 2.0)
		# Target cursor
		draw_arc(_drag_pos, 12, 0, TAU, 16, Color(0.3, 0.9, 0.5, 0.5), 1.5)
		draw_line(_drag_pos + Vector2(-16, 0), _drag_pos + Vector2(-6, 0), Color(0.3, 0.9, 0.5, 0.5), 1.5)
		draw_line(_drag_pos + Vector2(6, 0), _drag_pos + Vector2(16, 0), Color(0.3, 0.9, 0.5, 0.5), 1.5)
		draw_line(_drag_pos + Vector2(0, -16), _drag_pos + Vector2(0, -6), Color(0.3, 0.9, 0.5, 0.5), 1.5)
		draw_line(_drag_pos + Vector2(0, 6), _drag_pos + Vector2(0, 16), Color(0.3, 0.9, 0.5, 0.5), 1.5)

	# Selection ring
	if _selected_blip in _blips:
		var blip: BlipData = _blips[_selected_blip]
		var sp := _world_to_screen(blip.pos)
		var sr: float = (blip.radius + 10) * _zoom
		draw_arc(sp, sr, 0, TAU, 32, Color.WHITE, 2.0)
		var arc_start: float = _time * 2.0
		draw_arc(sp, sr + 4, arc_start, arc_start + 1.5, 16, Color(1, 1, 1, 0.25), 1.5)

		# Right-click hint on classified hostile blips
		if blip.classified and blip.blip_type in ["hostile"]:
			draw_string(ThemeDB.fallback_font, sp + Vector2(-50, blip.radius * _zoom + 40), "RIGHT-CLICK: OPTIONS", HORIZONTAL_ALIGNMENT_CENTER, 100, 10, Color(0.5, 0.6, 0.7, 0.5 + sin(_time * 2.0) * 0.2))

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
	if sp.x < -80 or sp.x > size.x + 80 or sp.y < -80 or sp.y > size.y + 80:
		return

	var color: Color = BLIP_COLORS.get(blip.blip_type, BLIP_COLORS["unknown"])
	var scale_factor: float = blip.spawn_progress if blip.spawning else 1.0
	var r: float = blip.radius * _zoom * scale_factor

	# Don't draw if still tiny
	if r < 2.0:
		return

	# Spawn flash ring (expanding ring when first appearing)
	if blip.spawning and blip.spawn_progress > 0.1:
		var flash_r: float = blip.radius * _zoom * 3.0 * (1.0 - blip.spawn_progress)
		var flash_alpha: float = 0.4 * (1.0 - blip.spawn_progress)
		draw_arc(sp, flash_r, 0, TAU, 32, Color(color.r, color.g, color.b, flash_alpha), 2.0)

	# Classify flash (white burst when classified)
	if blip.classify_flash > 0:
		var cf: float = blip.classify_flash
		draw_circle(sp, r * (1.0 + cf * 0.8), Color(1, 1, 1, cf * 0.25))
		draw_arc(sp, r * (1.5 + cf), 0, TAU, 32, Color(1, 1, 1, cf * 0.3), 2.0)

	# Onboarding highlight — big pulsing ring on first unclassified target
	if _onboarding_active and blip.id == _onboarding_blip:
		var ob_r: float = r + 20 + sin(_time * 3.0) * 8.0
		draw_arc(sp, ob_r, 0, TAU, 48, Color(1, 1, 1, 0.15 + sin(_time * 2.0) * 0.08), 2.5)
		# "CLICK" label above
		draw_string(ThemeDB.fallback_font, sp + Vector2(-30, -r - 28), "CLICK TO IDENTIFY", HORIZONTAL_ALIGNMENT_CENTER, 60, 13, Color(1, 1, 1, 0.5 + sin(_time * 2.0) * 0.3))

	# Glow behind blip (ambient light)
	if blip.blip_type != "neutralized":
		draw_circle(sp, r * 1.8, Color(color.r, color.g, color.b, 0.04))

	# Pulse rings
	if blip.blip_type != "neutralized":
		var pr: float = r + sin(blip.pulse_phase) * 6.0 * _zoom
		draw_arc(sp, pr, 0, TAU, 32, Color(color.r, color.g, color.b, 0.15), 2.0)
		var pr2: float = r + sin(blip.pulse_phase + 1.2) * 10.0 * _zoom
		draw_arc(sp, pr2, 0, TAU, 32, Color(color.r, color.g, color.b, 0.06), 1.5)

	# Outer ring — thick and visible
	draw_arc(sp, r, 0, TAU, 32, color, 3.0)

	# Inner fill — solid enough to see
	draw_circle(sp, r * 0.55, Color(color.r, color.g, color.b, 0.3))

	# Center dot
	draw_circle(sp, 3.5 * _zoom, color)

	# Hover glow
	if blip.id == _hovered_blip:
		draw_circle(sp, r + 10 * _zoom, Color(1, 1, 1, 0.06))
		draw_arc(sp, r + 5 * _zoom, 0, TAU, 32, Color(1, 1, 1, 0.2), 1.5)

	# Busy indicator
	if blip.busy:
		var a: float = _time * 3.0
		draw_arc(sp, r + 6 * _zoom, a, a + 2.0, 16, Color(0.2, 0.9, 0.4, 0.6), 3.0)

	# Label — bigger and more readable
	var label_text := blip.label
	if blip.blip_type == "unknown":
		label_text = "UNKNOWN"
	if blip.classified or blip.blip_type in ["asset", "neutralized", "unknown"]:
		var label_width := 120
		draw_string(
			ThemeDB.fallback_font,
			sp + Vector2(float(-label_width) / 2.0, r + 20 * _zoom),
			label_text,
			HORIZONTAL_ALIGNMENT_CENTER,
			label_width, int(13 * _zoom),
			Color(color.r, color.g, color.b, 0.9),
		)


func _draw_sector_labels() -> void:
	# Compass labels at edges
	var edge_color := Color(0.12, 0.16, 0.22)
	var font_size := 11
	draw_string(ThemeDB.fallback_font, Vector2(size.x / 2 - 20, 20), "NORTH", HORIZONTAL_ALIGNMENT_CENTER, 40, font_size, edge_color)
	draw_string(ThemeDB.fallback_font, Vector2(size.x / 2 - 20, size.y - 10), "SOUTH", HORIZONTAL_ALIGNMENT_CENTER, 40, font_size, edge_color)
	draw_string(ThemeDB.fallback_font, Vector2(8, size.y / 2 + 4), "WEST", HORIZONTAL_ALIGNMENT_LEFT, 40, font_size, edge_color)
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 48, size.y / 2 + 4), "EAST", HORIZONTAL_ALIGNMENT_LEFT, 40, font_size, edge_color)

	# Grid coordinate labels at major intersections
	var gs: float = GRID_SIZE * _zoom * GRID_MAJOR_EVERY
	if gs < 60:
		return
	var ox := fmod(_camera_offset.x, gs)
	var oy := fmod(_camera_offset.y, gs)
	var ix := int(-_camera_offset.x / gs)
	var x := ox
	while x < size.x:
		var iy2 := int(-_camera_offset.y / gs)
		var y := oy
		while y < size.y:
			if x > 60 and x < size.x - 60 and y > 30 and y < size.y - 30:
				draw_string(ThemeDB.fallback_font, Vector2(x + 4, y - 4), "%d,%d" % [ix, iy2], HORIZONTAL_ALIGNMENT_LEFT, 50, 9, Color(0.08, 0.1, 0.14))
			y += gs
			iy2 += 1
		x += gs
		ix += 1


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
	var s: float = 18 * _zoom

	# Outer perimeter circle
	draw_arc(sp, s * 2.5, 0, TAU, 32, Color(0.15, 0.4, 0.25, 0.15), 1.0)

	# Landing pad / HQ — double diamond
	var points := PackedVector2Array([
		sp + Vector2(0, -s), sp + Vector2(s, 0), sp + Vector2(0, s), sp + Vector2(-s, 0),
	])
	draw_colored_polygon(points, Color(0.1, 0.25, 0.15, 0.4))
	draw_polyline(points + PackedVector2Array([points[0]]), Color(0.2, 0.8, 0.4, 0.6), 2.0)

	# Inner diamond
	var s2: float = s * 0.5
	var inner := PackedVector2Array([
		sp + Vector2(0, -s2), sp + Vector2(s2, 0), sp + Vector2(0, s2), sp + Vector2(-s2, 0),
	])
	draw_polyline(inner + PackedVector2Array([inner[0]]), Color(0.2, 0.8, 0.4, 0.3), 1.0)

	# Label
	draw_string(ThemeDB.fallback_font, sp + Vector2(-20, s + 18 * _zoom), "HQ / BASE", HORIZONTAL_ALIGNMENT_CENTER, 40, int(11 * _zoom), Color(0.2, 0.7, 0.4, 0.6))


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

	# Set first unknown blip as onboarding target
	if blip_type == "unknown" and _onboarding_blip.is_empty():
		_onboarding_blip = id


func classify_blip(id: String, new_type: String, new_label: String) -> void:
	if id in _blips:
		_blips[id].blip_type = new_type
		_blips[id].label = new_label
		_blips[id].classified = true
		_blips[id].classify_flash = 1.0  # Trigger flash animation

		# Clear onboarding once first blip is classified
		if id == _onboarding_blip:
			_onboarding_active = false
			_onboarding_blip = ""
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
			var old_hover := _hovered_blip
			_hovered_blip = _get_blip_at(event.position)
			# Cursor change
			if not _hovered_blip.is_empty():
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			else:
				mouse_default_cursor_shape = Control.CURSOR_ARROW


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
