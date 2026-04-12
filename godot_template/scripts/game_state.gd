extends Node
## Global game state singleton. All state changes go through here.
## The Python orchestrator reads/writes this via MCP.

# -----------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------

signal state_changed(key: String, value: Variant)
signal quest_updated(quest_id: String)
signal inventory_changed()
signal player_stats_changed()

# -----------------------------------------------------------------------
# Player stats
# -----------------------------------------------------------------------

var player_stats: Dictionary = {
	"name": "Hero",
	"level": 1,
	"xp": 0,
	"xp_to_next": 100,
	"hp": 100,
	"max_hp": 100,
	"mp": 50,
	"max_mp": 50,
	"str": 10,
	"dex": 10,
	"int": 10,
	"con": 10,
	"wis": 10,
	"cha": 10,
	"attack": 5,
	"defense": 5,
	"speed": 5,
}

# -----------------------------------------------------------------------
# Collections
# -----------------------------------------------------------------------

var inventory: Array[Dictionary] = []      # [{id, name, count, type, ...}]
var equipment: Dictionary = {}             # {slot_name: item_data}
var quests: Dictionary = {}                # {quest_id: {status, objectives, ...}}
var flags: Dictionary = {}                 # Arbitrary game flags set by scripts/agents
var npc_relationships: Dictionary = {}     # {npc_id: {trust: int, fear: int, ...}}
var current_location: String = ""
var gold: int = 0
var play_time_seconds: float = 0.0

# -----------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------

const SAVE_DIR := "user://saves/"
const XP_GROWTH_FACTOR := 1.5

# -----------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------

func _ready() -> void:
	# Ensure save directory exists
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _process(delta: float) -> void:
	play_time_seconds += delta

# -----------------------------------------------------------------------
# Flags
# -----------------------------------------------------------------------

func set_flag(key: String, value: Variant) -> void:
	flags[key] = value
	state_changed.emit(key, value)


func get_flag(key: String, default: Variant = null) -> Variant:
	return flags.get(key, default)

# -----------------------------------------------------------------------
# Inventory
# -----------------------------------------------------------------------

func add_item(item_data: Dictionary) -> void:
	# If stackable and already exists, increase count
	var item_id: String = item_data.get("id", "")
	for i in range(inventory.size()):
		if inventory[i].get("id", "") == item_id:
			inventory[i]["count"] = inventory[i].get("count", 1) + item_data.get("count", 1)
			inventory_changed.emit()
			return
	# New item
	if not item_data.has("count"):
		item_data["count"] = 1
	inventory.append(item_data)
	inventory_changed.emit()


func remove_item(item_id: String, count: int = 1) -> bool:
	for i in range(inventory.size()):
		if inventory[i].get("id", "") == item_id:
			var current_count: int = inventory[i].get("count", 1)
			if current_count < count:
				return false
			elif current_count == count:
				inventory.remove_at(i)
			else:
				inventory[i]["count"] = current_count - count
			inventory_changed.emit()
			return true
	return false


func has_item(item_id: String, count: int = 1) -> bool:
	for item in inventory:
		if item.get("id", "") == item_id:
			return item.get("count", 1) >= count
	return false


func get_item(item_id: String) -> Dictionary:
	for item in inventory:
		if item.get("id", "") == item_id:
			return item
	return {}

# -----------------------------------------------------------------------
# Equipment
# -----------------------------------------------------------------------

func equip_item(slot: String, item_data: Dictionary) -> Dictionary:
	## Equips item_data into the given slot. Returns the previously equipped item (or {}).
	var old_item: Dictionary = equipment.get(slot, {})
	equipment[slot] = item_data

	# Remove from inventory
	remove_item(item_data.get("id", ""), 1)

	# Put old item back in inventory if there was one
	if not old_item.is_empty():
		add_item(old_item)

	_recalculate_equipment_stats()
	inventory_changed.emit()
	return old_item


func unequip_slot(slot: String) -> Dictionary:
	## Removes item from slot and returns it to inventory. Returns the item (or {}).
	if not equipment.has(slot):
		return {}
	var item: Dictionary = equipment[slot]
	equipment.erase(slot)
	add_item(item)
	_recalculate_equipment_stats()
	inventory_changed.emit()
	return item


func _recalculate_equipment_stats() -> void:
	## Recalculate derived stats from base stats + equipment bonuses.
	var base_attack: int = player_stats.get("str", 10)
	var base_defense: int = player_stats.get("con", 10)
	var bonus_attack: int = 0
	var bonus_defense: int = 0

	for slot in equipment:
		var item: Dictionary = equipment[slot]
		var stats: Dictionary = item.get("stats", {})
		bonus_attack += stats.get("attack", 0)
		bonus_defense += stats.get("defense", 0)

	player_stats["attack"] = base_attack + bonus_attack
	player_stats["defense"] = base_defense + bonus_defense
	player_stats_changed.emit()

# -----------------------------------------------------------------------
# Quests
# -----------------------------------------------------------------------

func start_quest(quest_data: Dictionary) -> void:
	var quest_id: String = quest_data.get("id", "")
	if quest_id.is_empty():
		push_warning("Cannot start quest without an id")
		return
	quest_data["status"] = "active"
	# Initialize objective completion tracking
	var objectives: Array = quest_data.get("objectives", [])
	for i in range(objectives.size()):
		if objectives[i] is Dictionary:
			objectives[i]["completed"] = false
			objectives[i]["current_count"] = 0
	quests[quest_id] = quest_data
	quest_updated.emit(quest_id)


func complete_quest_objective(quest_id: String, objective_id: String) -> void:
	if not quests.has(quest_id):
		push_warning("Quest not found: " + quest_id)
		return
	var quest: Dictionary = quests[quest_id]
	var objectives: Array = quest.get("objectives", [])
	for i in range(objectives.size()):
		if objectives[i] is Dictionary and objectives[i].get("id", "") == objective_id:
			objectives[i]["completed"] = true
			objectives[i]["current_count"] = objectives[i].get("count", 1)
			break
	# Check if all non-optional objectives are complete
	var all_complete: bool = true
	for obj in objectives:
		if obj is Dictionary and not obj.get("optional", false) and not obj.get("completed", false):
			all_complete = false
			break
	if all_complete:
		quest["status"] = "ready_to_complete"
	quest_updated.emit(quest_id)


func complete_quest(quest_id: String) -> void:
	if not quests.has(quest_id):
		push_warning("Quest not found: " + quest_id)
		return
	quests[quest_id]["status"] = "completed"
	# Apply rewards
	var rewards: Dictionary = quests[quest_id].get("rewards", {})
	if rewards.has("xp"):
		add_xp(rewards["xp"])
	if rewards.has("gold"):
		gold += rewards["gold"]
	if rewards.has("items"):
		for item in rewards["items"]:
			if item is Dictionary:
				add_item(item)
	quest_updated.emit(quest_id)


func get_active_quests() -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	for quest_id in quests:
		if quests[quest_id].get("status", "") == "active" or quests[quest_id].get("status", "") == "ready_to_complete":
			active.append(quests[quest_id])
	return active


func get_completed_quests() -> Array[Dictionary]:
	var completed: Array[Dictionary] = []
	for quest_id in quests:
		if quests[quest_id].get("status", "") == "completed":
			completed.append(quests[quest_id])
	return completed

# -----------------------------------------------------------------------
# XP / Leveling
# -----------------------------------------------------------------------

func add_xp(amount: int) -> void:
	player_stats["xp"] += amount
	while player_stats["xp"] >= player_stats["xp_to_next"]:
		_level_up()
	player_stats_changed.emit()


func _level_up() -> void:
	player_stats["xp"] -= player_stats["xp_to_next"]
	player_stats["level"] += 1
	player_stats["xp_to_next"] = int(player_stats["xp_to_next"] * XP_GROWTH_FACTOR)

	# Boost all base stats on level-up
	player_stats["max_hp"] += 10
	player_stats["hp"] = player_stats["max_hp"]
	player_stats["max_mp"] += 5
	player_stats["mp"] = player_stats["max_mp"]
	player_stats["str"] += 1
	player_stats["dex"] += 1
	player_stats["int"] += 1
	player_stats["con"] += 1
	player_stats["wis"] += 1
	player_stats["cha"] += 1

	_recalculate_equipment_stats()

	EventBus.notification.emit(
		"Level Up! Now level %d" % player_stats["level"],
		"info"
	)

# -----------------------------------------------------------------------
# Stat modification
# -----------------------------------------------------------------------

func modify_stat(stat: String, amount: int) -> void:
	if player_stats.has(stat):
		player_stats[stat] += amount
		# Clamp HP and MP
		if stat == "hp":
			player_stats["hp"] = clampi(player_stats["hp"], 0, player_stats["max_hp"])
		elif stat == "mp":
			player_stats["mp"] = clampi(player_stats["mp"], 0, player_stats["max_mp"])
		player_stats_changed.emit()
		state_changed.emit(stat, player_stats[stat])

# -----------------------------------------------------------------------
# NPC Relationships
# -----------------------------------------------------------------------

func modify_relationship(npc_id: String, stat: String, amount: int) -> void:
	if not npc_relationships.has(npc_id):
		npc_relationships[npc_id] = {"trust": 0, "fear": 0, "respect": 0}
	if npc_relationships[npc_id].has(stat):
		npc_relationships[npc_id][stat] += amount
	state_changed.emit("npc_" + npc_id + "_" + stat, npc_relationships[npc_id].get(stat, 0))


func get_relationship(npc_id: String) -> Dictionary:
	return npc_relationships.get(npc_id, {"trust": 0, "fear": 0, "respect": 0})

# -----------------------------------------------------------------------
# Save / Load
# -----------------------------------------------------------------------

func save_game(slot: int) -> void:
	var data: Dictionary = to_dict()
	var path: String = SAVE_DIR + "save_%d.json" % slot
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		EventBus.game_saved.emit(slot)
		EventBus.notification.emit("Game saved to slot %d" % slot, "info")
	else:
		push_error("Failed to save game to " + path)
		EventBus.notification.emit("Failed to save game!", "error")


func load_game(slot: int) -> void:
	var path: String = SAVE_DIR + "save_%d.json" % slot
	if not FileAccess.file_exists(path):
		push_warning("No save file at " + path)
		EventBus.notification.emit("No save file in slot %d" % slot, "warning")
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file:
		var text: String = file.get_as_text()
		file.close()
		var json := JSON.new()
		var err := json.parse(text)
		if err == OK:
			from_dict(json.data)
			EventBus.game_loaded.emit(slot)
			EventBus.notification.emit("Game loaded from slot %d" % slot, "info")
		else:
			push_error("Failed to parse save file: " + json.get_error_message())
	else:
		push_error("Failed to open save file: " + path)

# -----------------------------------------------------------------------
# Serialization
# -----------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"player_stats": player_stats.duplicate(true),
		"inventory": inventory.duplicate(true),
		"equipment": equipment.duplicate(true),
		"quests": quests.duplicate(true),
		"flags": flags.duplicate(true),
		"npc_relationships": npc_relationships.duplicate(true),
		"current_location": current_location,
		"gold": gold,
		"play_time_seconds": play_time_seconds,
	}


func from_dict(data: Dictionary) -> void:
	player_stats = data.get("player_stats", player_stats)
	inventory.assign(data.get("inventory", []))
	equipment = data.get("equipment", {})
	quests = data.get("quests", {})
	flags = data.get("flags", {})
	npc_relationships = data.get("npc_relationships", {})
	current_location = data.get("current_location", "")
	gold = data.get("gold", 0)
	play_time_seconds = data.get("play_time_seconds", 0.0)
	player_stats_changed.emit()
	inventory_changed.emit()
