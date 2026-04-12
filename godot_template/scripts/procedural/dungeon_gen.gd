extends Node
## Orchestrates dungeon generation. Takes DungeonLayout data, creates the full scene.
## Combines tilemap generation, entity placement, and exit wiring into a playable dungeon.

# -----------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------

signal generation_complete(dungeon_scene: Node)

# -----------------------------------------------------------------------
# Preload references
# -----------------------------------------------------------------------

# These would normally be preloaded scenes — using placeholder paths
const NPC_SCENE_PATH := "res://scenes/characters/npc.tscn"
const ITEM_PICKUP_SCENE_PATH := "res://scenes/world/item_pickup.tscn"

# -----------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------

const TILE_SIZE := 16

# -----------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------

func generate_dungeon(layout_data: Dictionary) -> Node:
	## Takes a DungeonLayout (from schemas.world) and builds a complete scene tree.
	## Returns the root Node2D of the dungeon.
	var root := Node2D.new()
	root.name = layout_data.get("name", "Dungeon").replace(" ", "_")

	# 1. Create and populate the tilemap
	var tilemap := _create_tilemap(layout_data)
	root.add_child(tilemap)

	# 2. Create room scenes (areas with collision for room detection)
	var rooms: Array = layout_data.get("rooms", [])
	_create_room_scenes(root, rooms)

	# 3. Connect rooms (corridor pathfinding is handled by the tilemap)
	var connections: Array = layout_data.get("connections", [])
	_connect_rooms(root, connections, rooms)

	# 4. Place entities in rooms (NPCs, items, enemies)
	_place_entities(root, rooms)

	# 5. Place entry and exit markers
	var entry_id: String = layout_data.get("entry_room_id", "")
	var exit_id: String = layout_data.get("exit_room_id", "")
	_place_exits(root, rooms, entry_id, exit_id)

	generation_complete.emit(root)
	return root

# -----------------------------------------------------------------------
# Tilemap creation
# -----------------------------------------------------------------------

func _create_tilemap(layout_data: Dictionary) -> TileMapLayer:
	var tilemap_gen_script = load("res://scripts/procedural/tilemap_gen.gd")
	var tilemap := TileMapLayer.new()
	tilemap.name = "DungeonTilemap"
	tilemap.set_script(tilemap_gen_script)

	# Generate tiles
	if tilemap.has_method("generate_from_layout"):
		tilemap.generate_from_layout(layout_data)

	return tilemap

# -----------------------------------------------------------------------
# Room scenes
# -----------------------------------------------------------------------

func _create_room_scenes(root: Node, rooms: Array) -> void:
	## Create Area2D nodes for each room so we can detect when the player enters.
	for room_data in rooms:
		if not room_data is Dictionary:
			continue

		var room_id: String = room_data.get("id", "room")
		var room_name: String = room_data.get("name", room_id)
		var pos: Array = room_data.get("position", [0, 0])
		var width: int = room_data.get("width", 5)
		var height: int = room_data.get("height", 5)

		var room_area := Area2D.new()
		room_area.name = "Room_" + room_id
		room_area.position = Vector2(
			(pos[0] if pos.size() > 0 else 0) * TILE_SIZE,
			(pos[1] if pos.size() > 1 else 0) * TILE_SIZE,
		)

		# Create collision for the room area
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(width * TILE_SIZE, height * TILE_SIZE)
		collision.shape = shape
		collision.position = Vector2(width * TILE_SIZE / 2.0, height * TILE_SIZE / 2.0)
		room_area.add_child(collision)

		# Connect body entered signal for room detection
		room_area.body_entered.connect(
			func(body):
				if body.is_in_group("player"):
					GameState.current_location = room_id
					EventBus.room_entered.emit(room_id)
		)
		room_area.body_exited.connect(
			func(body):
				if body.is_in_group("player"):
					EventBus.room_exited.emit(room_id)
		)

		# Store room data as metadata
		room_area.set_meta("room_data", room_data)

		root.add_child(room_area)

# -----------------------------------------------------------------------
# Room connections
# -----------------------------------------------------------------------

func _connect_rooms(root: Node, connections: Array, rooms: Array) -> void:
	## Create door/gate markers at connection points between rooms.
	var room_lookup: Dictionary = {}
	for room in rooms:
		if room is Dictionary:
			room_lookup[room.get("id", "")] = room

	for conn in connections:
		if not conn is Dictionary:
			continue

		var from_id: String = conn.get("from_id", "")
		var to_id: String = conn.get("to_id", "")
		var locked: bool = conn.get("locked", false)
		var lock_key: String = conn.get("lock_key", "")

		if not room_lookup.has(from_id) or not room_lookup.has(to_id):
			continue

		var from_room: Dictionary = room_lookup[from_id]
		var to_room: Dictionary = room_lookup[to_id]

		# Calculate midpoint between room centers for door placement
		var from_center := _room_center_world(from_room)
		var to_center := _room_center_world(to_room)
		var midpoint := (from_center + to_center) / 2.0

		if locked:
			var door := Area2D.new()
			door.name = "Door_%s_%s" % [from_id, to_id]
			door.position = midpoint

			var collision := CollisionShape2D.new()
			var shape := RectangleShape2D.new()
			shape.size = Vector2(TILE_SIZE, TILE_SIZE)
			collision.shape = shape
			door.add_child(collision)

			door.set_meta("locked", true)
			door.set_meta("lock_key", lock_key)
			door.set_meta("from_room", from_id)
			door.set_meta("to_room", to_id)

			# Interaction: check if player has key
			door.body_entered.connect(
				func(body):
					if body.is_in_group("player"):
						if lock_key.is_empty() or GameState.has_item(lock_key):
							door.set_meta("locked", false)
							EventBus.notification.emit("Door unlocked!", "info")
						else:
							EventBus.notification.emit("This door is locked. You need: " + lock_key, "warning")
			)

			root.add_child(door)

# -----------------------------------------------------------------------
# Entity placement
# -----------------------------------------------------------------------

func _place_entities(root: Node, rooms: Array) -> void:
	## Place NPCs, items, and enemies in rooms based on entity lists.
	for room_data in rooms:
		if not room_data is Dictionary:
			continue

		var entities: Array = room_data.get("entities", [])
		var pos: Array = room_data.get("position", [0, 0])
		var width: int = room_data.get("width", 5)
		var height: int = room_data.get("height", 5)

		var base_x: float = (pos[0] if pos.size() > 0 else 0) * TILE_SIZE
		var base_y: float = (pos[1] if pos.size() > 1 else 0) * TILE_SIZE

		for i in range(entities.size()):
			var entity_id = entities[i]
			# Place entities spread within the room
			var offset_x: float = (i % width + 1) * TILE_SIZE
			var offset_y: float = (i / width + 1) * TILE_SIZE
			offset_x = clampf(offset_x, TILE_SIZE, (width - 1) * TILE_SIZE)
			offset_y = clampf(offset_y, TILE_SIZE, (height - 1) * TILE_SIZE)

			var entity_pos := Vector2(base_x + offset_x, base_y + offset_y)

			# Create a placeholder marker for the entity
			# The actual scene instantiation depends on entity type
			var marker := Marker2D.new()
			marker.name = "Entity_" + str(entity_id)
			marker.position = entity_pos
			marker.set_meta("entity_id", entity_id)
			root.add_child(marker)

# -----------------------------------------------------------------------
# Entry / Exit placement
# -----------------------------------------------------------------------

func _place_exits(root: Node, rooms: Array, entry_id: String, exit_id: String) -> void:
	for room_data in rooms:
		if not room_data is Dictionary:
			continue

		var room_id: String = room_data.get("id", "")
		var center := _room_center_world(room_data)

		if room_id == entry_id:
			var entry_marker := Marker2D.new()
			entry_marker.name = "EntryPoint"
			entry_marker.position = center
			entry_marker.set_meta("is_entry", true)
			root.add_child(entry_marker)

		if room_id == exit_id:
			var exit_area := Area2D.new()
			exit_area.name = "ExitPoint"
			exit_area.position = center

			var collision := CollisionShape2D.new()
			var shape := CircleShape2D.new()
			shape.radius = TILE_SIZE
			collision.shape = shape
			exit_area.add_child(collision)

			exit_area.body_entered.connect(
				func(body):
					if body.is_in_group("player"):
						EventBus.notification.emit("You found the exit!", "info")
						# Signal that the dungeon is complete
						EventBus.room_entered.emit("__dungeon_exit__")
			)

			root.add_child(exit_area)

# -----------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------

func _room_center_world(room_data: Dictionary) -> Vector2:
	## Returns the world-space center position of a room.
	var pos: Array = room_data.get("position", [0, 0])
	var room_x: float = (pos[0] if pos.size() > 0 else 0) * TILE_SIZE
	var room_y: float = (pos[1] if pos.size() > 1 else 0) * TILE_SIZE
	var width: float = room_data.get("width", 5) * TILE_SIZE
	var height: float = room_data.get("height", 5) * TILE_SIZE
	return Vector2(room_x + width / 2.0, room_y + height / 2.0)
