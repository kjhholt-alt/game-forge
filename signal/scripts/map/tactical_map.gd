## Tactical map — the entire game screen. Dark grid with clickable blips.
##
## Renders a 2D tactical display with grid, pulsing blips, threat zones,
## asset trails, drag-drop assignment, and range rings.
extends Control


const GRID_SIZE := 150.0
const GRID_COLOR := Color(0.16, 0.18, 0.25)
const GRID_MAJOR_COLOR := Color(0.22, 0.26, 0.35)
const GRID_MAJOR_EVERY := 4

const BLIP_COLORS := {
	"unknown": Color(1.0, 0.7, 0.15),
	"hostile": Color(1.0, 0.25, 0.2),
	"friendly": Color(0.2, 1.0, 0.5),
	"asset": Color(0.35, 0.7, 1.0),
	"neutralized": Color(0.4, 0.4, 0.4),
	"active": Color(0.25, 1.0, 0.5),
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
	var radius: float = 42.0
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


var _onboarding_blip: String = ""
var _onboarding_active := true

# Terrain background
var _terrain_rect: ColorRect = null

func _ready() -> void:
	_camera_offset = Vector2(100, 60)

	# Create terrain shader background
	_terrain_rect = ColorRect.new()
	_terrain_rect.anchors_preset = Control.PRESET_FULL_RECT
	_terrain_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader = load("res://assets/shaders/terrain.gdshader")
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		_terrain_rect.material = mat
	add_child(_terrain_rect)
	move_child(_terrain_rect, 0)  # Behind everything


func _process(delta: float) -> void:
	_time += delta
	_radar_angle = fmod(_radar_angle + delta * 0.8, TAU)

	# Update terrain shader with camera offset
	if _terrain_rect and _terrain_rect.material:
		_terrain_rect.material.set_shader_parameter("offset", _camera_offset)
		_terrain_rect.material.set_shader_parameter("zoom_level", _zoom)

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
	# Terrain shader handles the background
	_draw_grid()
	_draw_geography()
	_draw_road_network()
	_draw_sector_labels()
	_draw_compass_rose()
	_draw_radar_sweep()
	_draw_sensor_arcs()
	_draw_threat_zones()
	_draw_range_rings_on_targets()
	_draw_range_ring()
	_draw_base()
	_draw_map_icons()
	_draw_scale_bar()
	_draw_cursor_coords()

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
			draw_string(ThemeDB.fallback_font, sp + Vector2(-80, blip.radius * _zoom + 45), "RIGHT-CLICK: OPTIONS", HORIZONTAL_ALIGNMENT_CENTER, 160, 13, Color(0.7, 0.8, 0.9, 0.6 + sin(_time * 2.0) * 0.25))

	# Edge indicators for off-screen blips
	_draw_edge_indicators()

	# Tooltip
	if _tooltip_visible:
		_draw_tooltip()


func _draw_compass_rose() -> void:
	# Maven-style compass in top-right corner
	var cx: float = size.x - 70
	var cy: float = 80.0
	var r: float = 45.0
	var line_color := Color(0.4, 0.45, 0.55)
	var text_color := Color(0.5, 0.6, 0.7)

	# Outer circle
	draw_arc(Vector2(cx, cy), r, 0, TAU, 32, Color(0.3, 0.35, 0.45, 0.5), 1.5)

	# N/S/E/W lines
	draw_line(Vector2(cx, cy - r), Vector2(cx, cy + r), line_color, 1.0)
	draw_line(Vector2(cx - r, cy), Vector2(cx + r, cy), line_color, 1.0)

	# North pointer (brighter)
	draw_line(Vector2(cx, cy), Vector2(cx, cy - r + 4), Color(0.9, 0.3, 0.2, 0.8), 2.0)

	# Labels
	draw_string(ThemeDB.fallback_font, Vector2(cx - 4, cy - r - 6), "N", HORIZONTAL_ALIGNMENT_CENTER, 8, 10, Color(0.9, 0.3, 0.2, 0.8))
	draw_string(ThemeDB.fallback_font, Vector2(cx - 4, cy + r + 14), "S", HORIZONTAL_ALIGNMENT_CENTER, 8, 9, text_color)
	draw_string(ThemeDB.fallback_font, Vector2(cx + r + 6, cy + 3), "E", HORIZONTAL_ALIGNMENT_LEFT, 8, 9, text_color)
	draw_string(ThemeDB.fallback_font, Vector2(cx - r - 14, cy + 3), "W", HORIZONTAL_ALIGNMENT_LEFT, 8, 9, text_color)

	# Diagonal ticks
	for i in range(8):
		var angle: float = float(i) * TAU / 8.0
		var inner_r: float = r - 6
		var p1 := Vector2(cx + cos(angle) * inner_r, cy + sin(angle) * inner_r)
		var p2 := Vector2(cx + cos(angle) * r, cy + sin(angle) * r)
		draw_line(p1, p2, Color(0.2, 0.25, 0.35, 0.3), 1.0)


func _draw_radar_sweep() -> void:
	var center_s := _world_to_screen(_radar_center)
	var r_s: float = _radar_radius * _zoom
	# Sweep line
	var end := center_s + Vector2(cos(_radar_angle), sin(_radar_angle)) * r_s
	draw_line(center_s, end, Color(0.2, 0.8, 0.4, 0.18), 1.0)
	# Trailing fade (arc behind the sweep line)
	for i in range(20):
		var a: float = _radar_angle - float(i) * 0.04
		var e := center_s + Vector2(cos(a), sin(a)) * r_s
		var alpha: float = 0.15 * (1.0 - float(i) / 20.0)
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
		draw_string(ThemeDB.fallback_font, sp + Vector2(-70, -r - 35), "CLICK TO IDENTIFY", HORIZONTAL_ALIGNMENT_CENTER, 140, 16, Color(1, 1, 1, 0.7 + sin(_time * 2.0) * 0.25))

	# Large glow halo — needs to be VERY visible on ultrawide
	if blip.blip_type != "neutralized":
		draw_circle(sp, r * 3.0, Color(color.r, color.g, color.b, 0.12))
		draw_circle(sp, r * 2.2, Color(color.r, color.g, color.b, 0.22))
		draw_circle(sp, r * 1.5, Color(color.r, color.g, color.b, 0.3))

	# Pulse rings — bright
	if blip.blip_type != "neutralized":
		var pr: float = r + sin(blip.pulse_phase) * 6.0 * _zoom
		draw_arc(sp, pr, 0, TAU, 48, Color(color.r, color.g, color.b, 0.5), 3.0)

	# SOLID filled circle (the main visible element)
	draw_circle(sp, r, Color(color.r * 0.25, color.g * 0.25, color.b * 0.25, 0.9))

	# Outer ring — THICK BRIGHT FULL COLOR
	draw_arc(sp, r, 0, TAU, 48, color, 5.0)

	# Inner bright core
	draw_circle(sp, r * 0.45, Color(color.r, color.g, color.b, 0.7))

	# Center white dot
	draw_circle(sp, 4.0 * _zoom, Color(1, 1, 1, 1.0))

	# Hover glow
	if blip.id == _hovered_blip:
		draw_circle(sp, r + 10 * _zoom, Color(1, 1, 1, 0.15))
		draw_arc(sp, r + 5 * _zoom, 0, TAU, 32, Color(1, 1, 1, 0.2), 1.5)

	# Busy indicator
	if blip.busy:
		var a: float = _time * 3.0
		draw_arc(sp, r + 6 * _zoom, a, a + 2.0, 16, Color(0.2, 0.9, 0.4, 0.6), 3.0)

	# Label — Maven-style white text
	var label_text := blip.label
	if blip.blip_type == "unknown":
		label_text = "UNKNOWN"

	if blip.classified or blip.blip_type in ["asset", "neutralized", "unknown"]:
		var label_width := 180
		var label_y: float = r + 22 * _zoom
		var label_pos := sp + Vector2(float(-label_width) / 2.0, label_y)

		# Shadow for readability
		draw_string(ThemeDB.fallback_font, label_pos + Vector2(1, 1), label_text, HORIZONTAL_ALIGNMENT_CENTER, label_width, int(14 * _zoom), Color(0, 0, 0, 0.6))
		# Main label — WHITE like Maven
		var label_color := Color(0.9, 0.92, 0.95) if blip.classified else Color(0.7, 0.7, 0.7)
		draw_string(ThemeDB.fallback_font, label_pos, label_text, HORIZONTAL_ALIGNMENT_CENTER, label_width, int(14 * _zoom), label_color)

		# Type subtitle for classified targets (e.g. "HOSTILE • CV DETECTION")
		if blip.classified and blip.blip_type != "neutralized":
			var type_text := blip.blip_type.to_upper()
			var sub_pos := sp + Vector2(float(-label_width) / 2.0, label_y + 16 * _zoom)
			draw_string(ThemeDB.fallback_font, sub_pos, type_text, HORIZONTAL_ALIGNMENT_CENTER, label_width, int(10 * _zoom), Color(color.r, color.g, color.b, 0.6))


func _draw_geography() -> void:
	# Large-scale geographic features drawn ON TOP of the terrain shader
	# These create the dramatic water/land contrast that Maven shows

	# Large water body (bay/delta) — bottom-right area
	var water_color := Color(0.03, 0.04, 0.09, 0.7)
	var coast_color := Color(0.30, 0.35, 0.45, 0.7)
	var bay_points := PackedVector2Array()
	for p in [Vector2(1200, 700), Vector2(1400, 650), Vector2(1600, 720), Vector2(1800, 850), Vector2(1920, 900), Vector2(1920, 1080), Vector2(1200, 1080)]:
		bay_points.append(_world_to_screen(p))
	if bay_points.size() >= 3:
		var colors := PackedColorArray()
		for i in range(bay_points.size()):
			colors.append(water_color)
		draw_polygon(bay_points, colors)
		# Coastline border
		draw_polyline(bay_points, coast_color, 2.0)

	# River running through the center
	var river_points := [Vector2(0, 400), Vector2(200, 380), Vector2(450, 420), Vector2(700, 350), Vector2(900, 380), Vector2(1100, 400), Vector2(1200, 700)]
	for i in range(river_points.size() - 1):
		var a := _world_to_screen(river_points[i])
		var b := _world_to_screen(river_points[i + 1])
		# Wide river
		draw_line(a, b, Color(0.04, 0.05, 0.10, 0.6), 6.0 * _zoom)
		# Shore lines
		draw_line(a + Vector2(0, 3), b + Vector2(0, 3), coast_color, 1.0)
		draw_line(a + Vector2(0, -3), b + Vector2(0, -3), coast_color, 1.0)

	# Urban area patches — bright regions
	var urban_color := Color(0.30, 0.34, 0.42, 0.30)
	var urban_areas := [
		[Vector2(750, 300), Vector2(950, 280), Vector2(1050, 350), Vector2(1000, 450), Vector2(800, 430), Vector2(700, 380)],
		[Vector2(1300, 350), Vector2(1500, 320), Vector2(1550, 400), Vector2(1450, 480), Vector2(1300, 450)],
		[Vector2(300, 550), Vector2(500, 520), Vector2(550, 600), Vector2(400, 650), Vector2(280, 620)],
	]
	for area in urban_areas:
		var pts := PackedVector2Array()
		for p in area:
			pts.append(_world_to_screen(p))
		if pts.size() >= 3:
			var uc := PackedColorArray()
			for i in range(pts.size()):
				uc.append(urban_color)
			draw_polygon(pts, uc)

	# Small lake/pond
	var lake_center := _world_to_screen(Vector2(400, 200))
	draw_circle(lake_center, 25 * _zoom, Color(0.04, 0.05, 0.10, 0.5))
	draw_arc(lake_center, 25 * _zoom, 0, TAU, 24, coast_color, 1.0)


func _draw_road_network() -> void:
	# Thin infrastructure lines across the map — Maven shows roads as visible gray lines
	var road_color := Color(0.35, 0.40, 0.50, 0.6)
	var highway_color := Color(0.42, 0.46, 0.55, 0.7)
	var border_color := Color(0.35, 0.30, 0.28, 0.5)

	# Major highways (thick, bright)
	var highways := [
		[Vector2(0, 500), Vector2(400, 480), Vector2(700, 350), Vector2(1100, 400), Vector2(1500, 550), Vector2(1920, 600)],
		[Vector2(600, 0), Vector2(650, 200), Vector2(700, 350), Vector2(750, 600), Vector2(800, 900), Vector2(850, 1080)],
	]
	for hw in highways:
		for i in range(hw.size() - 1):
			var a := _world_to_screen(hw[i])
			var b := _world_to_screen(hw[i + 1])
			draw_line(a, b, highway_color, 3.0)

	# Secondary roads — DENSE network
	var roads := [
		[Vector2(200, 100), Vector2(500, 300), Vector2(900, 300)],
		[Vector2(700, 350), Vector2(700, 600), Vector2(900, 800)],
		[Vector2(1100, 100), Vector2(1300, 300), Vector2(1400, 550)],
		[Vector2(400, 480), Vector2(300, 700), Vector2(150, 800)],
		[Vector2(1500, 300), Vector2(1600, 500), Vector2(1700, 700)],
		[Vector2(100, 300), Vector2(400, 350), Vector2(700, 350)],
		[Vector2(900, 300), Vector2(1100, 250), Vector2(1400, 300)],
		[Vector2(1300, 550), Vector2(1500, 450), Vector2(1700, 400)],
		[Vector2(300, 600), Vector2(500, 550), Vector2(700, 600)],
		[Vector2(800, 500), Vector2(1000, 550), Vector2(1200, 500)],
		[Vector2(150, 450), Vector2(400, 480)],
		[Vector2(1100, 400), Vector2(1300, 550)],
		[Vector2(950, 200), Vector2(1100, 100)],
	]
	for road in roads:
		for i in range(road.size() - 1):
			var a := _world_to_screen(road[i])
			var b := _world_to_screen(road[i + 1])
			draw_line(a, b, road_color, 1.5)

	# Intersection markers — small dots where roads cross
	var marker_color := Color(0.35, 0.40, 0.50, 0.6)
	var intersections := [
		Vector2(700, 350), Vector2(400, 480), Vector2(1100, 400),
		Vector2(500, 300), Vector2(900, 300), Vector2(1300, 300),
		Vector2(1300, 550), Vector2(700, 600), Vector2(1500, 550),
		Vector2(300, 700), Vector2(1600, 500), Vector2(650, 200),
		Vector2(800, 500), Vector2(1000, 550),
	]
	for pt in intersections:
		var sp := _world_to_screen(pt)
		draw_circle(sp, 3.0 * _zoom, marker_color)

	# Region boundaries (dashed)
	var boundaries := [
		[Vector2(0, 250), Vector2(1920, 350)],
		[Vector2(800, 0), Vector2(750, 1080)],
		[Vector2(1200, 0), Vector2(1250, 700)],
	]
	for bd in boundaries:
		draw_dashed_line(_world_to_screen(bd[0]), _world_to_screen(bd[1]), border_color, 1.5, 10.0)


func _draw_sector_labels() -> void:
	# Compass labels at edges
	var edge_color := Color(0.35, 0.40, 0.52)
	var font_size := 11
	draw_string(ThemeDB.fallback_font, Vector2(size.x / 2 - 20, 20), "NORTH", HORIZONTAL_ALIGNMENT_CENTER, 40, font_size, edge_color)
	draw_string(ThemeDB.fallback_font, Vector2(size.x / 2 - 20, size.y - 10), "SOUTH", HORIZONTAL_ALIGNMENT_CENTER, 40, font_size, edge_color)
	draw_string(ThemeDB.fallback_font, Vector2(8, size.y / 2 + 4), "WEST", HORIZONTAL_ALIGNMENT_LEFT, 40, font_size, edge_color)
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 48, size.y / 2 + 4), "EAST", HORIZONTAL_ALIGNMENT_LEFT, 40, font_size, edge_color)

	# Map place names — DENSE, Maven has labels EVERYWHERE
	var place_color := Color(0.45, 0.52, 0.62)
	var place_dim := Color(0.30, 0.35, 0.42)
	var place_size := 11
	var places := [
		# Major locations (brighter)
		[Vector2(300, 100), "SECTOR ALPHA-7", true],
		[Vector2(700, 250), "FORWARD OPS BASE", true],
		[Vector2(1100, 150), "RIDGELINE NORTH", true],
		[Vector2(900, 500), "INDUSTRIAL ZONE", true],
		[Vector2(1300, 400), "DISTRICT 9", true],
		[Vector2(1500, 600), "PORT FACILITY", true],
		[Vector2(1200, 800), "AIRFIELD SOUTH", true],
		[Vector2(400, 300), "CHECKPOINT BRAVO", true],
		# Minor locations (dimmer, smaller)
		[Vector2(500, 450), "Valley Crossing", false],
		[Vector2(200, 650), "Marshland", false],
		[Vector2(800, 700), "Highway Junction", false],
		[Vector2(1600, 200), "Comms Array", false],
		[Vector2(100, 200), "Outpost Lima", false],
		[Vector2(600, 120), "Route 7 Bridge", false],
		[Vector2(1000, 300), "Ammo Depot", false],
		[Vector2(1400, 250), "Radar Station", false],
		[Vector2(350, 550), "Fuel Storage", false],
		[Vector2(750, 850), "Rail Yard", false],
		[Vector2(1150, 650), "Water Treatment", false],
		[Vector2(1650, 450), "Power Station", false],
		[Vector2(450, 750), "Container Port", false],
		[Vector2(950, 150), "AA Battery Site", false],
		[Vector2(1500, 750), "Refugee Camp", false],
		[Vector2(250, 400), "Mosque Complex", false],
	]
	for p in places:
		var sp := _world_to_screen(p[0])
		if sp.x > 0 and sp.x < size.x and sp.y > 0 and sp.y < size.y:
			var is_major: bool = p[2] if p.size() > 2 else false
			var pc: Color = place_color if is_major else place_dim
			var ps: int = 12 if is_major else 10
			draw_string(ThemeDB.fallback_font, sp, p[1], HORIZONTAL_ALIGNMENT_LEFT, 250, ps, pc)

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
				draw_string(ThemeDB.fallback_font, Vector2(x + 4, y - 4), "%d,%d" % [ix, iy2], HORIZONTAL_ALIGNMENT_LEFT, 50, 10, Color(0.25, 0.30, 0.40))
			y += gs
			iy2 += 1
		x += gs
		ix += 1


func _draw_sensor_arcs() -> void:
	# Draw sensor coverage fan arcs from asset positions
	for blip in _blips.values():
		if blip.blip_type != "asset" or blip.spawn_progress < 0.5:
			continue
		var sp := _world_to_screen(blip.pos)
		var sensor_range: float = 250.0 * _zoom  # Sensor range in screen pixels

		# Fan arc — 90 degree coverage in front direction
		var direction: float = 0.0  # Default facing right
		# If busy, face toward target
		if blip.busy and blip.mission_target in _blips:
			var target_sp := _world_to_screen(_blips[blip.mission_target].pos)
			direction = sp.angle_to_point(target_sp)
		else:
			direction = -PI / 2.0  # Face up when idle

		var arc_half := PI / 4.0  # 45 degrees each side = 90 degree fan
		var segments := 20
		var fan_points := PackedVector2Array()
		fan_points.append(sp)
		for i in range(segments + 1):
			var angle: float = direction - arc_half + (arc_half * 2.0) * float(i) / float(segments)
			fan_points.append(sp + Vector2(cos(angle), sin(angle)) * sensor_range)
		fan_points.append(sp)

		# Fill with translucent blue
		if fan_points.size() >= 3:
			var colors := PackedColorArray()
			for i in range(fan_points.size()):
				colors.append(Color(0.15, 0.4, 0.8, 0.12))
			draw_polygon(fan_points, colors)

		# Edge lines
		draw_line(sp, sp + Vector2(cos(direction - arc_half), sin(direction - arc_half)) * sensor_range, Color(0.2, 0.5, 0.9, 0.25), 1.5)
		draw_line(sp, sp + Vector2(cos(direction + arc_half), sin(direction + arc_half)) * sensor_range, Color(0.2, 0.5, 0.9, 0.25), 1.5)

		# Arc edge
		for i in range(segments):
			var a1: float = direction - arc_half + (arc_half * 2.0) * float(i) / float(segments)
			var a2: float = direction - arc_half + (arc_half * 2.0) * float(i + 1) / float(segments)
			var p1 := sp + Vector2(cos(a1), sin(a1)) * sensor_range
			var p2 := sp + Vector2(cos(a2), sin(a2)) * sensor_range
			draw_line(p1, p2, Color(0.2, 0.5, 0.9, 0.2), 1.5)


func _draw_range_rings_on_targets() -> void:
	# Concentric range rings around classified hostile targets (Maven-style)
	for blip in _blips.values():
		if blip.blip_type != "hostile" or not blip.classified:
			continue
		var sp := _world_to_screen(blip.pos)
		# 3 concentric rings
		for i in range(1, 4):
			var ring_r: float = float(i) * 60.0 * _zoom
			var alpha: float = 0.15 / float(i)
			draw_arc(sp, ring_r, 0, TAU, 48, Color(0.9, 0.25, 0.2, alpha), 1.0)


func _draw_threat_zones() -> void:
	for tz in _threat_zones:
		var center_s := _world_to_screen(tz.get("center", Vector2.ZERO))
		var radius_s: float = tz.get("radius", 100) * _zoom
		var color: Color = tz.get("color", Color(0.9, 0.2, 0.2, 0.25))
		draw_circle(center_s, radius_s, color)
		draw_arc(center_s, radius_s, 0, TAU, 48, Color(color.r, color.g, color.b, 0.4), 2.0)
		# Inner ring for emphasis
		draw_arc(center_s, radius_s * 0.6, 0, TAU, 32, Color(color.r, color.g, color.b, 0.15), 1.0)


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
	draw_arc(sp, s * 2.5, 0, TAU, 32, Color(0.15, 0.5, 0.3, 0.3), 1.5)

	# Landing pad / HQ — double diamond
	var points := PackedVector2Array([
		sp + Vector2(0, -s), sp + Vector2(s, 0), sp + Vector2(0, s), sp + Vector2(-s, 0),
	])
	draw_colored_polygon(points, Color(0.1, 0.3, 0.18, 0.5))
	draw_polyline(points + PackedVector2Array([points[0]]), Color(0.2, 0.8, 0.4, 0.8), 2.0)

	# Inner diamond
	var s2: float = s * 0.5
	var inner := PackedVector2Array([
		sp + Vector2(0, -s2), sp + Vector2(s2, 0), sp + Vector2(0, s2), sp + Vector2(-s2, 0),
	])
	draw_polyline(inner + PackedVector2Array([inner[0]]), Color(0.2, 0.8, 0.4, 0.3), 1.0)

	# Label
	draw_string(ThemeDB.fallback_font, sp + Vector2(-20, s + 18 * _zoom), "HQ / BASE", HORIZONTAL_ALIGNMENT_CENTER, 40, int(11 * _zoom), Color(0.2, 0.7, 0.4, 0.6))


# --- Public API ---

func _draw_map_icons() -> void:
	# Small military-style markers at key locations — Maven has these scattered everywhere
	var icon_color := Color(0.40, 0.46, 0.56)
	var s: float = 5.0 * _zoom

	# Triangle markers (radar/comms sites)
	var triangles := [Vector2(950, 150), Vector2(1400, 250), Vector2(600, 120)]
	for pt in triangles:
		var sp := _world_to_screen(pt)
		if sp.x < 0 or sp.x > size.x or sp.y < 0 or sp.y > size.y:
			continue
		var tri := PackedVector2Array([sp + Vector2(0, -s), sp + Vector2(s, s), sp + Vector2(-s, s)])
		draw_polyline(tri + PackedVector2Array([tri[0]]), icon_color, 1.0)

	# Square markers (buildings/facilities)
	var squares := [Vector2(350, 550), Vector2(1150, 650), Vector2(750, 850), Vector2(1500, 750)]
	for pt in squares:
		var sp := _world_to_screen(pt)
		if sp.x < 0 or sp.x > size.x or sp.y < 0 or sp.y > size.y:
			continue
		draw_rect(Rect2(sp - Vector2(s, s), Vector2(s * 2, s * 2)), icon_color, false, 1.0)

	# X markers (destroyed/inactive)
	var x_marks := [Vector2(200, 400), Vector2(1650, 450)]
	for pt in x_marks:
		var sp := _world_to_screen(pt)
		if sp.x < 0 or sp.x > size.x or sp.y < 0 or sp.y > size.y:
			continue
		draw_line(sp + Vector2(-s, -s), sp + Vector2(s, s), Color(0.35, 0.30, 0.28), 1.0)
		draw_line(sp + Vector2(s, -s), sp + Vector2(-s, s), Color(0.35, 0.30, 0.28), 1.0)

	# Diamond markers (POIs)
	var diamonds := [Vector2(450, 750), Vector2(1000, 300)]
	for pt in diamonds:
		var sp := _world_to_screen(pt)
		if sp.x < 0 or sp.x > size.x or sp.y < 0 or sp.y > size.y:
			continue
		var dia := PackedVector2Array([sp + Vector2(0, -s), sp + Vector2(s, 0), sp + Vector2(0, s), sp + Vector2(-s, 0)])
		draw_polyline(dia + PackedVector2Array([dia[0]]), icon_color, 1.0)


func _draw_cursor_coords() -> void:
	# Show world coordinates at bottom-left of map (updates with mouse position)
	# Maven shows "N/A S3" coordinate format at bottom
	var mouse_pos := get_local_mouse_position()
	var world_pos := _screen_to_world(mouse_pos)
	var coord_text := "%.0f, %.0f" % [world_pos.x, world_pos.y]
	var coord_color := Color(0.35, 0.40, 0.50)
	draw_string(ThemeDB.fallback_font, Vector2(10, size.y - 8), coord_text, HORIZONTAL_ALIGNMENT_LEFT, 120, 10, coord_color)


func _draw_scale_bar() -> void:
	# Maven-style scale bar at bottom right of map
	var bar_x: float = size.x - 180
	var bar_y: float = size.y - 20
	var bar_width: float = 100 * _zoom
	var scale_color := Color(0.35, 0.40, 0.50)

	draw_line(Vector2(bar_x, bar_y), Vector2(bar_x + bar_width, bar_y), scale_color, 1.5)
	draw_line(Vector2(bar_x, bar_y - 4), Vector2(bar_x, bar_y + 4), scale_color, 1.0)
	draw_line(Vector2(bar_x + bar_width, bar_y - 4), Vector2(bar_x + bar_width, bar_y + 4), scale_color, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(bar_x + bar_width / 2 - 15, bar_y - 8), "10 km", HORIZONTAL_ALIGNMENT_CENTER, 30, 9, scale_color)


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


func add_threat_zone(center: Vector2, radius: float, color: Color = Color(0.9, 0.2, 0.2, 0.25)) -> void:
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
