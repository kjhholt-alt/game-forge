extends CharacterBody2D
## NPC controller. Handles movement, interaction, and AI-driven behavior.
## Attach to any NPC scene. The Python orchestrator populates npc_data via MCP.

# -----------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------

@export var npc_id: String = ""
@export var npc_data: Dictionary = {}
@export var wander_radius: float = 100.0
@export var interaction_radius: float = 50.0
@export var move_speed: float = 40.0

# -----------------------------------------------------------------------
# State
# -----------------------------------------------------------------------

var is_interactable: bool = true
var current_state: String = "idle"  # idle, wandering, talking, following

var _origin_position: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
var _wander_interval: float = 3.0
var _bark_label: Label = null
var _bark_timer: float = 0.0
var _interaction_area: Area2D = null

# -----------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------

func _ready() -> void:
	_origin_position = global_position
	_wander_target = global_position

	# Create interaction area
	_interaction_area = Area2D.new()
	_interaction_area.name = "InteractionArea"
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = interaction_radius
	collision.shape = shape
	_interaction_area.add_child(collision)
	add_child(_interaction_area)

	# Create bark label (floating text above NPC)
	_bark_label = Label.new()
	_bark_label.name = "BarkLabel"
	_bark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bark_label.position = Vector2(-50, -40)
	_bark_label.size = Vector2(100, 20)
	_bark_label.visible = false
	add_child(_bark_label)

	# Apply data from npc_data if present
	if npc_data.has("name"):
		_bark_label.text = npc_data.get("name", "")

	# Randomize wander interval slightly per NPC
	_wander_interval = randf_range(2.0, 5.0)


func _physics_process(delta: float) -> void:
	match current_state:
		"idle":
			_idle_behavior(delta)
		"wandering":
			_wander(delta)
		"talking":
			# Stay still while in conversation
			velocity = Vector2.ZERO
		"following":
			_follow_behavior(delta)

	move_and_slide()

	# Bark timer
	if _bark_timer > 0:
		_bark_timer -= delta
		if _bark_timer <= 0:
			_bark_label.visible = false


func _idle_behavior(delta: float) -> void:
	velocity = Vector2.ZERO
	_wander_timer += delta
	if _wander_timer >= _wander_interval:
		_wander_timer = 0.0
		# Decide whether to wander (60% chance)
		if randf() < 0.6:
			current_state = "wandering"
			_pick_wander_target()


func _follow_behavior(delta: float) -> void:
	# Follow behavior — follow the nearest player (placeholder)
	# In a full game, you'd get the player node reference
	velocity = Vector2.ZERO

# -----------------------------------------------------------------------
# Wandering
# -----------------------------------------------------------------------

func _wander(delta: float) -> void:
	var direction: Vector2 = (_wander_target - global_position).normalized()
	var distance: float = global_position.distance_to(_wander_target)

	if distance < 5.0:
		# Arrived at target
		current_state = "idle"
		velocity = Vector2.ZERO
		return

	velocity = direction * move_speed


func _pick_wander_target() -> void:
	var angle: float = randf() * TAU
	var dist: float = randf_range(20.0, wander_radius)
	_wander_target = _origin_position + Vector2(cos(angle), sin(angle)) * dist

# -----------------------------------------------------------------------
# Schedule (time-based behavior)
# -----------------------------------------------------------------------

func _follow_schedule() -> void:
	## Override in derived scripts for time-based NPC behavior.
	## Check in-game time and move to appropriate location.
	var schedule: Array = npc_data.get("schedule", [])
	if schedule.is_empty():
		return

	# Schedule entries: {time_start, time_end, location, activity}
	var current_time: float = GameState.play_time_seconds
	for entry in schedule:
		if entry is Dictionary:
			var start: float = entry.get("time_start", 0.0)
			var end: float = entry.get("time_end", 0.0)
			if current_time >= start and current_time <= end:
				var loc: Vector2 = Vector2(
					entry.get("location_x", _origin_position.x),
					entry.get("location_y", _origin_position.y),
				)
				_wander_target = loc
				current_state = "wandering"
				return

# -----------------------------------------------------------------------
# Interaction
# -----------------------------------------------------------------------

func interact() -> void:
	## Triggered by player proximity + input.
	if not is_interactable:
		return
	if current_state == "talking":
		return

	current_state = "talking"
	EventBus.npc_interacted.emit(npc_id)

	# Check for dialogue data
	var dialogue: Array = npc_data.get("dialogue", [])
	if dialogue.size() > 0:
		# Find the appropriate dialogue tree
		var tree: Dictionary = _pick_dialogue_tree(dialogue)
		if not tree.is_empty():
			# Get dialogue system and start dialogue
			var dialogue_system = get_tree().get_first_node_in_group("dialogue_system")
			if dialogue_system and dialogue_system.has_method("start_dialogue"):
				dialogue_system.start_dialogue(tree)
				await dialogue_system.dialogue_finished
			current_state = "idle"
			return

	# Fallback: show a bark
	set_bark("greeting")
	current_state = "idle"


func set_bark(situation: String) -> void:
	## Show contextual bark text above the NPC.
	var barks: Dictionary = npc_data.get("barks", {})
	var bark_options: Array = barks.get(situation, [])

	var text: String = ""
	if bark_options.size() > 0:
		text = bark_options[randi() % bark_options.size()]
	else:
		# Default barks
		match situation:
			"greeting":
				text = "Hello, traveler."
			"farewell":
				text = "Safe travels."
			"busy":
				text = "I'm busy right now."
			_:
				text = "..."

	_bark_label.text = text
	_bark_label.visible = true
	_bark_timer = 3.0

# -----------------------------------------------------------------------
# Data access
# -----------------------------------------------------------------------

func get_disposition() -> String:
	return npc_data.get("disposition", "neutral")


func get_role() -> String:
	return npc_data.get("role", "")


func get_display_name() -> String:
	return npc_data.get("name", npc_id)
