## Tactical map — the entire game screen. Dark grid with clickable blips.
##
## Renders a 2D tactical display with:
## - Grid overlay on dark background
## - Pulsing blips for targets and assets
## - Click to select, right-click for COA menu
## - Zoom and pan with mouse wheel / drag
extends Control


const GRID_SIZE := 60.0
const GRID_COLOR := Color(0.08, 0.1, 0.14)
const GRID_MAJOR_COLOR := Color(0.1, 0.13, 0.18)
const GRID_MAJOR_EVERY := 5

const BLIP_COLORS := {
	"unknown": Color(0.95, 0.6, 0.1),    # Amber
	"hostile": Color(0.9, 0.2, 0.2),      # Red
	"friendly": Color(0.2, 0.8, 0.4),     # Green
	"asset": Color(0.3, 0.6, 0.9),        # Blue
	"neutralized": Color(0.3, 0.3, 0.3),  # Gray
}

var _camera_offset := Vector2.ZERO
var _zoom := 1.0
var _dragging := false
var _drag_start := Vector2.ZERO

var _blips: Dictionary = {}  # id -> BlipData
var _selected_blip: String = ""
var _hovered_blip: String = ""
var _time := 0.0

# Asset movement animations
var _moving_assets: Array = []  # [{asset_id, from, to, progress, speed}]


class BlipData:
	var id: String
	var pos: Vector2          # World position
	var blip_type: String     # "unknown", "hostile", "friendly", "asset", "neutralized"
	var label: String         # Short label shown below blip (e.g. "CONVOY")
	var radius: float = 12.0
	var pulse_phase: float = 0.0
	var classified: bool = false
	var handler_line: String = ""  # What handler says when clicked


func _ready() -> void:
	# Center the view
	_camera_offset = size / 2.0 if size.x > 0 else Vector2(960, 540)


func _process(delta: float) -> void:
	_time += delta

	# Pulse blips
	for blip in _blips.values():
		blip.pulse_phase = fmod(blip.pulse_phase + delta * 2.5, TAU)

	# Move assets
	for i in range(_moving_assets.size() - 1, -1, -1):
		var mv: Dictionary = _moving_assets[i]
		mv["progress"] += delta * mv.get("speed", 0.5)
		if mv["progress"] >= 1.0:
			mv["progress"] = 1.0
			# Asset arrived
			var asset_id: String = mv.get("asset_id", "")
			var target_id: String = mv.get("target_id", "")
			if asset_id in _blips:
				_blips[asset_id].pos = mv.get("to", Vector2.ZERO)
			EventBus.asset_arrived.emit(asset_id, target_id)
			_moving_assets.remove_at(i)
		else:
			var from: Vector2 = mv.get("from", Vector2.ZERO)
			var to: Vector2 = mv.get("to", Vector2.ZERO)
			if mv.get("asset_id", "") in _blips:
				_blips[mv["asset_id"]].pos = from.lerp(to, mv["progress"])

	queue_redraw()


func _draw() -> void:
	# Background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.035, 0.05))

	# Grid
	_draw_grid()

	# Blips
	for blip in _blips.values():
		_draw_blip(blip)

	# Asset movement trails
	for mv in _moving_assets:
		var from: Vector2 = _world_to_screen(mv.get("from", Vector2.ZERO))
		var current: Vector2 = _world_to_screen(
			(mv.get("from", Vector2.ZERO) as Vector2).lerp(mv.get("to", Vector2.ZERO), mv.get("progress", 0.0))
		)
		draw_dashed_line(from, current, Color(0.3, 0.6, 0.9, 0.4), 1.5, 4.0)

	# Selection indicator
	if _selected_blip in _blips:
		var blip: BlipData = _blips[_selected_blip]
		var screen_pos := _world_to_screen(blip.pos)
		var sel_radius: float = (blip.radius + 8) * _zoom
		draw_arc(screen_pos, sel_radius, 0, TAU, 32, Color.WHITE, 1.5)


func _draw_grid() -> void:
	var grid_step: float = GRID_SIZE * _zoom
	if grid_step < 10:
		return  # Too zoomed out, skip grid

	var offset_x := fmod(_camera_offset.x, grid_step)
	var offset_y := fmod(_camera_offset.y, grid_step)

	var grid_index_x := int(-_camera_offset.x / grid_step)
	var grid_index_y := int(-_camera_offset.y / grid_step)

	# Vertical lines
	var x := offset_x
	var ix := grid_index_x
	while x < size.x:
		var color := GRID_MAJOR_COLOR if ix % GRID_MAJOR_EVERY == 0 else GRID_COLOR
		draw_line(Vector2(x, 0), Vector2(x, size.y), color, 1.0)
		x += grid_step
		ix += 1

	# Horizontal lines
	var y := offset_y
	var iy := grid_index_y
	while y < size.y:
		var color := GRID_MAJOR_COLOR if iy % GRID_MAJOR_EVERY == 0 else GRID_COLOR
		draw_line(Vector2(0, y), Vector2(size.x, y), color, 1.0)
		y += grid_step
		iy += 1


func _draw_blip(blip: BlipData) -> void:
	var screen_pos := _world_to_screen(blip.pos)

	# Off-screen check
	if screen_pos.x < -50 or screen_pos.x > size.x + 50:
		return
	if screen_pos.y < -50 or screen_pos.y > size.y + 50:
		return

	var color: Color = BLIP_COLORS.get(blip.blip_type, BLIP_COLORS["unknown"])
	var r: float = blip.radius * _zoom

	# Pulse ring
	var pulse_r: float = r + sin(blip.pulse_phase) * 4.0 * _zoom
	draw_arc(screen_pos, pulse_r, 0, TAU, 24, Color(color.r, color.g, color.b, 0.3), 1.5)

	# Outer ring
	draw_arc(screen_pos, r, 0, TAU, 24, color, 2.0)

	# Inner fill
	draw_circle(screen_pos, r * 0.5, Color(color.r, color.g, color.b, 0.4))

	# Hover highlight
	if blip.id == _hovered_blip:
		draw_circle(screen_pos, r + 4 * _zoom, Color(1, 1, 1, 0.1))

	# Label below blip
	if blip.classified or blip.blip_type == "asset":
		draw_string(
			ThemeDB.fallback_font,
			screen_pos + Vector2(-r, r + 14 * _zoom),
			blip.label,
			HORIZONTAL_ALIGNMENT_CENTER,
			int(r * 2), int(10 * _zoom),
			Color(color.r, color.g, color.b, 0.7),
		)


# --- Public API ---

func add_blip(id: String, pos: Vector2, blip_type: String, label: String, handler_line: String = "") -> void:
	var blip := BlipData.new()
	blip.id = id
	blip.pos = pos
	blip.blip_type = blip_type
	blip.label = label
	blip.handler_line = handler_line
	blip.pulse_phase = randf() * TAU  # Random phase so they don't pulse in sync
	_blips[id] = blip
	EventBus.blip_spawned.emit(id)


func classify_blip(id: String, new_type: String, new_label: String) -> void:
	if id in _blips:
		_blips[id].blip_type = new_type
		_blips[id].label = new_label
		_blips[id].classified = true
		EventBus.blip_classified.emit(id, new_type)


func move_asset(asset_id: String, target_id: String, speed: float = 0.3) -> void:
	if asset_id not in _blips or target_id not in _blips:
		return
	_moving_assets.append({
		"asset_id": asset_id,
		"target_id": target_id,
		"from": _blips[asset_id].pos,
		"to": _blips[target_id].pos,
		"progress": 0.0,
		"speed": speed,
	})


func remove_blip(id: String) -> void:
	_blips.erase(id)


func get_blip(id: String) -> BlipData:
	return _blips.get(id)


# --- Coordinate conversion ---

func _world_to_screen(world_pos: Vector2) -> Vector2:
	return (world_pos * _zoom) + _camera_offset


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return (screen_pos - _camera_offset) / _zoom


# --- Input ---

func _gui_input(event: InputEvent) -> void:
	# Zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clamp(_zoom * 1.1, 0.3, 3.0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clamp(_zoom * 0.9, 0.3, 3.0)
			get_viewport().set_input_as_handled()

		# Pan start/stop
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_dragging = true
				_drag_start = event.position
			else:
				_dragging = false

		# Left click — select blip
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var clicked := _get_blip_at(event.position)
			if clicked:
				_selected_blip = clicked
				EventBus.blip_clicked.emit(clicked)
			else:
				_selected_blip = ""

		# Right click — COA menu
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var clicked := _get_blip_at(event.position)
			if clicked and _blips[clicked].classified:
				EventBus.coa_requested.emit(clicked)

	# Pan drag
	if event is InputEventMouseMotion:
		if _dragging:
			_camera_offset += event.relative
		else:
			_hovered_blip = _get_blip_at(event.position)


func _get_blip_at(screen_pos: Vector2) -> String:
	for blip in _blips.values():
		var blip_screen := _world_to_screen(blip.pos)
		if screen_pos.distance_to(blip_screen) <= (blip.radius + 6) * _zoom:
			return blip.id
	return ""
