extends Node
## Spawns encounters in rooms based on Encounter data from Python schemas.
## Creates enemy sprites and positions them according to formation patterns.

# -----------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------

const TILE_SIZE := 16

# Formation patterns (normalized positions, scaled to room size)
const FORMATIONS := {
	"line": [
		Vector2(0.3, 0.5), Vector2(0.5, 0.5), Vector2(0.7, 0.5),
		Vector2(0.2, 0.5), Vector2(0.8, 0.5),
	],
	"v_shape": [
		Vector2(0.5, 0.3), Vector2(0.3, 0.5), Vector2(0.7, 0.5),
		Vector2(0.2, 0.7), Vector2(0.8, 0.7),
	],
	"circle": [
		Vector2(0.5, 0.3), Vector2(0.7, 0.5), Vector2(0.5, 0.7),
		Vector2(0.3, 0.5), Vector2(0.5, 0.5),
	],
	"scattered": [
		Vector2(0.2, 0.3), Vector2(0.7, 0.2), Vector2(0.4, 0.6),
		Vector2(0.8, 0.7), Vector2(0.3, 0.8),
	],
	"boss": [
		Vector2(0.5, 0.4),  # Boss in center-front
		Vector2(0.3, 0.6), Vector2(0.7, 0.6),  # Minions flanking
		Vector2(0.2, 0.8), Vector2(0.8, 0.8),
	],
}

# -----------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------

func spawn_encounter(encounter_data: Dictionary, room_node: Node) -> void:
	## encounter_data: {id, enemies: [{name, hp, max_hp, attack, defense, speed, abilities, ...}], formation, ...}
	## room_node: the Node2D or Area2D representing the room
	var enemies: Array = encounter_data.get("enemies", [])
	var formation: String = encounter_data.get("formation", "scattered")

	# Get room dimensions from metadata if available
	var room_data: Dictionary = {}
	if room_node.has_meta("room_data"):
		room_data = room_node.get_meta("room_data")

	var room_width: float = room_data.get("width", 8) * TILE_SIZE
	var room_height: float = room_data.get("height", 8) * TILE_SIZE

	var enemy_nodes: Array[Node] = []
	for i in range(enemies.size()):
		var enemy_data: Dictionary = enemies[i]
		var enemy_node := _create_enemy_scene(enemy_data)
		room_node.add_child(enemy_node)
		enemy_nodes.append(enemy_node)

	_position_enemies(enemy_nodes, formation, room_width, room_height)

# -----------------------------------------------------------------------
# Enemy scene creation
# -----------------------------------------------------------------------

func _create_enemy_scene(enemy_data: Dictionary) -> Node:
	## Create a visual representation of an enemy.
	## In a full implementation this would load a specific scene per enemy type.
	var enemy_root := CharacterBody2D.new()
	enemy_root.name = enemy_data.get("name", "Enemy").replace(" ", "_")
	enemy_root.add_to_group("enemies")

	# Store combat data
	enemy_root.set_meta("enemy_data", enemy_data)
	enemy_root.set_meta("combat_id", enemy_data.get("combat_id", enemy_data.get("name", "enemy")))

	# Visual: colored rectangle as placeholder sprite
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	# Create a simple colored texture as placeholder
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var enemy_color := _get_enemy_color(enemy_data)
	img.fill(enemy_color)
	sprite.texture = ImageTexture.create_from_image(img)
	enemy_root.add_child(sprite)

	# Collision
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(14, 14)
	collision.shape = shape
	enemy_root.add_child(collision)

	# Name label
	var label := Label.new()
	label.text = enemy_data.get("name", "Enemy")
	label.position = Vector2(-30, -20)
	label.add_theme_font_size_override("font_size", 10)
	enemy_root.add_child(label)

	# HP bar (simple ColorRect)
	var hp_bg := ColorRect.new()
	hp_bg.name = "HPBarBG"
	hp_bg.size = Vector2(20, 3)
	hp_bg.position = Vector2(-10, -12)
	hp_bg.color = Color(0.3, 0.0, 0.0)
	enemy_root.add_child(hp_bg)

	var hp_fill := ColorRect.new()
	hp_fill.name = "HPBarFill"
	hp_fill.size = Vector2(20, 3)
	hp_fill.position = Vector2(-10, -12)
	hp_fill.color = Color(0.8, 0.1, 0.1)
	enemy_root.add_child(hp_fill)

	return enemy_root

# -----------------------------------------------------------------------
# Positioning
# -----------------------------------------------------------------------

func _position_enemies(enemy_nodes: Array[Node], formation: String, room_width: float, room_height: float) -> void:
	## Position enemies according to the formation pattern.
	var positions: Array = FORMATIONS.get(formation, FORMATIONS["scattered"])

	for i in range(enemy_nodes.size()):
		if i < positions.size():
			var norm_pos: Vector2 = positions[i]
			enemy_nodes[i].position = Vector2(
				norm_pos.x * room_width,
				norm_pos.y * room_height,
			)
		else:
			# Overflow: random position within the room
			enemy_nodes[i].position = Vector2(
				randf_range(0.2, 0.8) * room_width,
				randf_range(0.2, 0.8) * room_height,
			)

# -----------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------

func _get_enemy_color(enemy_data: Dictionary) -> Color:
	## Assign a color based on enemy difficulty / type.
	var hp: int = enemy_data.get("max_hp", enemy_data.get("hp", 50))
	if hp >= 200:
		return Color(0.8, 0.1, 0.8)  # Purple — boss/elite
	elif hp >= 100:
		return Color(0.8, 0.2, 0.1)  # Red — strong
	elif hp >= 50:
		return Color(0.8, 0.5, 0.1)  # Orange — medium
	else:
		return Color(0.2, 0.6, 0.2)  # Green — weak
