extends TileMapLayer
## Generates tilemaps from room/dungeon data provided by the Python orchestrator.
## Converts DungeonLayout JSON into placed tiles on this TileMapLayer.

# -----------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------

const TILE_SIZE := 16  # Pixels per tile
const WALL_SOURCE_ID := 0
const FLOOR_SOURCE_ID := 0
const WALL_ATLAS := Vector2i(0, 0)
const FLOOR_ATLAS := Vector2i(1, 0)
const DOOR_ATLAS := Vector2i(2, 0)
const DECORATION_ATLAS := Vector2i(3, 0)

# -----------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------

func generate_from_layout(layout_data: Dictionary) -> void:
	## layout_data matches schemas.world.DungeonLayout JSON:
	## {id, name, theme, difficulty, rooms: [...], connections: [...], entry_room_id, exit_room_id}
	clear()

	var rooms: Array = layout_data.get("rooms", [])
	var connections: Array = layout_data.get("connections", [])

	# First pass: place rooms
	for room in rooms:
		if room is Dictionary:
			_place_room(room)

	# Second pass: connect rooms with corridors
	var room_lookup: Dictionary = {}
	for room in rooms:
		if room is Dictionary:
			room_lookup[room.get("id", "")] = room

	for conn in connections:
		if conn is Dictionary:
			var from_id: String = conn.get("from_id", "")
			var to_id: String = conn.get("to_id", "")
			if room_lookup.has(from_id) and room_lookup.has(to_id):
				var from_room: Dictionary = room_lookup[from_id]
				var to_room: Dictionary = room_lookup[to_id]
				var from_center := _room_center(from_room)
				var to_center := _room_center(to_room)
				_place_corridor(from_center, to_center)

				# Place door at corridor entrance if connection is locked
				if conn.get("locked", false):
					_place_tile(from_center, FLOOR_SOURCE_ID, DOOR_ATLAS)

	# Third pass: place walls around all floor tiles
	_place_walls()

	# Fourth pass: decorations
	for room in rooms:
		if room is Dictionary:
			_place_decorations(room)

# -----------------------------------------------------------------------
# Room placement
# -----------------------------------------------------------------------

func _place_room(room_data: Dictionary) -> void:
	var pos: Array = room_data.get("position", [0, 0])
	var room_x: int = pos[0] if pos.size() > 0 else 0
	var room_y: int = pos[1] if pos.size() > 1 else 0
	var width: int = room_data.get("width", 5)
	var height: int = room_data.get("height", 5)

	# Fill room interior with floor tiles
	for x in range(room_x, room_x + width):
		for y in range(room_y, room_y + height):
			_place_tile(Vector2i(x, y), FLOOR_SOURCE_ID, FLOOR_ATLAS)

# -----------------------------------------------------------------------
# Corridor placement
# -----------------------------------------------------------------------

func _place_corridor(from_pos: Vector2i, to_pos: Vector2i) -> void:
	## L-shaped corridor: horizontal first, then vertical.
	var current := from_pos

	# Horizontal segment
	var x_dir: int = 1 if to_pos.x > from_pos.x else -1
	while current.x != to_pos.x:
		_place_tile(current, FLOOR_SOURCE_ID, FLOOR_ATLAS)
		current.x += x_dir

	# Vertical segment
	var y_dir: int = 1 if to_pos.y > from_pos.y else -1
	while current.y != to_pos.y:
		_place_tile(current, FLOOR_SOURCE_ID, FLOOR_ATLAS)
		current.y += y_dir

	# Place the final tile
	_place_tile(current, FLOOR_SOURCE_ID, FLOOR_ATLAS)

# -----------------------------------------------------------------------
# Wall placement
# -----------------------------------------------------------------------

func _place_walls() -> void:
	## Place wall tiles around all floor tiles that don't have neighbors.
	var floor_cells: Array[Vector2i] = []
	for cell in get_used_cells():
		floor_cells.append(cell)

	var floor_set: Dictionary = {}
	for cell in floor_cells:
		floor_set[cell] = true

	var wall_positions: Dictionary = {}
	var neighbors := [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1, 0),                    Vector2i(1, 0),
		Vector2i(-1, 1),  Vector2i(0, 1),  Vector2i(1, 1),
	]

	for cell in floor_cells:
		for offset in neighbors:
			var neighbor: Vector2i = cell + offset
			if not floor_set.has(neighbor):
				wall_positions[neighbor] = true

	for wall_pos in wall_positions:
		_place_tile(wall_pos, WALL_SOURCE_ID, WALL_ATLAS)

# -----------------------------------------------------------------------
# Decorations
# -----------------------------------------------------------------------

func _place_decorations(room_data: Dictionary) -> void:
	## Place decorative tiles based on room type and properties.
	var room_type: String = room_data.get("room_type", "")
	var pos: Array = room_data.get("position", [0, 0])
	var room_x: int = pos[0] if pos.size() > 0 else 0
	var room_y: int = pos[1] if pos.size() > 1 else 0
	var width: int = room_data.get("width", 5)
	var height: int = room_data.get("height", 5)

	match room_type:
		"treasure":
			# Place a decoration in the center of treasure rooms
			var center := Vector2i(room_x + width / 2, room_y + height / 2)
			_place_tile(center, FLOOR_SOURCE_ID, DECORATION_ATLAS)
		"boss":
			# Decorations in corners of boss rooms
			_place_tile(Vector2i(room_x + 1, room_y + 1), FLOOR_SOURCE_ID, DECORATION_ATLAS)
			_place_tile(Vector2i(room_x + width - 2, room_y + 1), FLOOR_SOURCE_ID, DECORATION_ATLAS)
			_place_tile(Vector2i(room_x + 1, room_y + height - 2), FLOOR_SOURCE_ID, DECORATION_ATLAS)
			_place_tile(Vector2i(room_x + width - 2, room_y + height - 2), FLOOR_SOURCE_ID, DECORATION_ATLAS)
		"rest":
			# Central decoration for rest rooms
			var center := Vector2i(room_x + width / 2, room_y + height / 2)
			_place_tile(center, FLOOR_SOURCE_ID, DECORATION_ATLAS)
		_:
			# Random sparse decorations for other rooms
			for x in range(room_x + 1, room_x + width - 1):
				for y in range(room_y + 1, room_y + height - 1):
					if randf() < 0.05:  # 5% chance per tile
						_place_tile(Vector2i(x, y), FLOOR_SOURCE_ID, DECORATION_ATLAS)

# -----------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------

func _place_tile(pos: Vector2i, source_id: int, atlas_coords: Vector2i) -> void:
	set_cell(pos, source_id, atlas_coords)


func _room_center(room_data: Dictionary) -> Vector2i:
	var pos: Array = room_data.get("position", [0, 0])
	var room_x: int = pos[0] if pos.size() > 0 else 0
	var room_y: int = pos[1] if pos.size() > 1 else 0
	var width: int = room_data.get("width", 5)
	var height: int = room_data.get("height", 5)
	return Vector2i(room_x + width / 2, room_y + height / 2)
