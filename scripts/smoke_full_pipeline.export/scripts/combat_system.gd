extends Node
## Turn-based combat engine. Receives Encounter data from Python schemas.
## Manages turn order, actions, damage, status effects, and rewards.

# -----------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------

signal combat_finished(result: String, rewards: Dictionary)
signal turn_started(combatant: Dictionary)
signal damage_dealt(target_name: String, amount: int, damage_type: String)
signal status_applied(target_name: String, status_name: String)

# -----------------------------------------------------------------------
# State
# -----------------------------------------------------------------------

enum CombatState { IDLE, PLAYER_TURN, ENEMY_TURN, ANIMATING, VICTORY, DEFEAT }

var state: CombatState = CombatState.IDLE
var party: Array[Dictionary] = []
var enemies: Array[Dictionary] = []
var turn_order: Array = []
var current_turn_index: int = 0
var _encounter_data: Dictionary = {}

# -----------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------

func _ready() -> void:
	pass

# -----------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------

func start_combat(encounter_data: Dictionary, party_data: Array) -> void:
	## encounter_data: {id, enemies: [{name, hp, max_hp, attack, defense, speed, abilities, loot}], ...}
	## party_data: array of character stat dicts (usually just [GameState.player_stats])
	_encounter_data = encounter_data

	# Build party combatants
	party.clear()
	for member in party_data:
		var combatant: Dictionary = member.duplicate(true)
		combatant["is_player"] = true
		combatant["status_effects"] = []
		combatant["alive"] = true
		party.append(combatant)

	# Build enemy combatants
	enemies.clear()
	var enemy_defs: Array = encounter_data.get("enemies", [])
	for i in range(enemy_defs.size()):
		var enemy: Dictionary = enemy_defs[i].duplicate(true)
		enemy["is_player"] = false
		enemy["status_effects"] = []
		enemy["alive"] = true
		if not enemy.has("hp"):
			enemy["hp"] = enemy.get("max_hp", 50)
		if not enemy.has("combat_id"):
			enemy["combat_id"] = enemy.get("name", "enemy") + "_" + str(i)
		enemies.append(enemy)

	state = CombatState.IDLE
	EventBus.combat_started.emit(encounter_data)
	_calculate_turn_order()
	_next_turn()


func submit_player_action(action: Dictionary) -> void:
	## Called by UI when the player selects an action.
	## action: {type: "attack"/"skill"/"item"/"flee", target_index: int, ability: {}, item: {}}
	if state != CombatState.PLAYER_TURN:
		push_warning("Not the player's turn")
		return
	state = CombatState.ANIMATING
	_execute_player_action(action)
	_apply_status_effects()
	var result := _check_combat_end()
	if result == "ongoing":
		current_turn_index = (current_turn_index + 1) % turn_order.size()
		_next_turn()
	else:
		_end_combat(result)

# -----------------------------------------------------------------------
# Turn management
# -----------------------------------------------------------------------

func _calculate_turn_order() -> void:
	## Sort all living combatants by speed (descending).
	turn_order.clear()
	var all_combatants: Array = []
	all_combatants.append_array(party)
	all_combatants.append_array(enemies)

	# Filter dead
	var living: Array = []
	for c in all_combatants:
		if c.get("alive", true):
			living.append(c)

	# Sort by speed descending
	living.sort_custom(func(a, b): return a.get("speed", 5) > b.get("speed", 5))
	turn_order = living
	current_turn_index = 0


func _next_turn() -> void:
	## Advance to the next living combatant's turn.
	if turn_order.is_empty():
		_end_combat("defeat")
		return

	# Skip dead combatants
	var attempts: int = 0
	while attempts < turn_order.size():
		var combatant: Dictionary = turn_order[current_turn_index]
		if combatant.get("alive", true):
			turn_started.emit(combatant)
			if combatant.get("is_player", false):
				state = CombatState.PLAYER_TURN
			else:
				state = CombatState.ENEMY_TURN
				_execute_enemy_action(combatant)
				_apply_status_effects()
				var result := _check_combat_end()
				if result == "ongoing":
					current_turn_index = (current_turn_index + 1) % turn_order.size()
					_next_turn()
				else:
					_end_combat(result)
			return
		current_turn_index = (current_turn_index + 1) % turn_order.size()
		attempts += 1

	# All dead somehow
	_end_combat("defeat")

# -----------------------------------------------------------------------
# Actions
# -----------------------------------------------------------------------

func _execute_player_action(action: Dictionary) -> void:
	var action_type: String = action.get("type", "attack")
	var target_index: int = action.get("target_index", 0)

	match action_type:
		"attack":
			if target_index >= 0 and target_index < enemies.size():
				var attacker: Dictionary = party[0]  # Assuming single player for now
				var target: Dictionary = enemies[target_index]
				var dmg: int = _apply_damage(attacker, target, {})
				damage_dealt.emit(target.get("name", "Enemy"), dmg, "physical")
		"skill":
			var ability: Dictionary = action.get("ability", {})
			if target_index >= 0 and target_index < enemies.size():
				var attacker: Dictionary = party[0]
				var target: Dictionary = enemies[target_index]
				var dmg: int = _apply_damage(attacker, target, ability)
				damage_dealt.emit(target.get("name", "Enemy"), dmg, ability.get("damage_type", "magical"))
				# MP cost
				var mp_cost: int = ability.get("mp_cost", 0)
				attacker["mp"] = max(0, attacker.get("mp", 0) - mp_cost)
		"item":
			var item: Dictionary = action.get("item", {})
			_use_combat_item(item)
		"flee":
			_attempt_flee()


func _execute_enemy_action(enemy: Dictionary) -> void:
	## Simple AI: pick a random living party member and attack.
	var targets: Array = []
	for i in range(party.size()):
		if party[i].get("alive", true):
			targets.append(i)

	if targets.is_empty():
		return

	var target_idx: int = targets[randi() % targets.size()]
	var target: Dictionary = party[target_idx]

	# Check if enemy has abilities; 30% chance to use one
	var abilities: Array = enemy.get("abilities", [])
	var ability: Dictionary = {}
	if abilities.size() > 0 and randf() < 0.3:
		ability = abilities[randi() % abilities.size()]

	var dmg: int = _apply_damage(enemy, target, ability)
	var ability_name: String = ability.get("name", "Attack")
	damage_dealt.emit(target.get("name", "Hero"), dmg, ability.get("damage_type", "physical"))


func _apply_damage(attacker: Dictionary, target: Dictionary, ability: Dictionary) -> int:
	## Calculate and apply damage. Returns final damage dealt.
	var base_power: int = ability.get("power", 0)
	if base_power == 0:
		base_power = attacker.get("attack", 5)

	var atk: int = attacker.get("attack", 5) + base_power
	var def_val: int = target.get("defense", 5)

	# Damage formula: (attack * 2 - defense) with some randomness, minimum 1
	var raw_damage: int = maxi(1, atk * 2 - def_val)
	var variance: float = randf_range(0.85, 1.15)
	var final_damage: int = maxi(1, int(raw_damage * variance))

	target["hp"] = maxi(0, target.get("hp", 0) - final_damage)

	if target["hp"] <= 0:
		target["alive"] = false
		if not target.get("is_player", false):
			EventBus.enemy_defeated.emit(target.get("combat_id", target.get("name", "")))

	return final_damage


func _use_combat_item(item: Dictionary) -> void:
	## Use a consumable item in combat.
	var effect: String = item.get("effect", "heal")
	var value: int = item.get("value", 20)

	match effect:
		"heal":
			if party.size() > 0:
				var target: Dictionary = party[0]
				target["hp"] = mini(target.get("hp", 0) + value, target.get("max_hp", 100))
		"mana":
			if party.size() > 0:
				var target: Dictionary = party[0]
				target["mp"] = mini(target.get("mp", 0) + value, target.get("max_mp", 50))

	# Remove from inventory
	GameState.remove_item(item.get("id", ""), 1)


func _attempt_flee() -> void:
	## 50% base chance to flee, modified by speed difference.
	var player_speed: int = 5
	if party.size() > 0:
		player_speed = party[0].get("speed", 5)

	var avg_enemy_speed: int = 0
	var count: int = 0
	for e in enemies:
		if e.get("alive", true):
			avg_enemy_speed += e.get("speed", 5)
			count += 1
	if count > 0:
		avg_enemy_speed /= count

	var flee_chance: float = 0.5 + (player_speed - avg_enemy_speed) * 0.05
	flee_chance = clampf(flee_chance, 0.1, 0.9)

	if randf() < flee_chance:
		_end_combat("fled")
	else:
		EventBus.notification.emit("Failed to flee!", "warning")

# -----------------------------------------------------------------------
# Status effects
# -----------------------------------------------------------------------

func _apply_status_effects() -> void:
	## Process all active status effects on all combatants.
	var all_combatants: Array = []
	all_combatants.append_array(party)
	all_combatants.append_array(enemies)

	for combatant in all_combatants:
		if not combatant.get("alive", true):
			continue
		var effects: Array = combatant.get("status_effects", [])
		var to_remove: Array = []
		for i in range(effects.size()):
			var effect: Dictionary = effects[i]
			var effect_type: String = effect.get("type", "")
			var potency: int = effect.get("potency", 0)
			match effect_type:
				"poison":
					combatant["hp"] = maxi(0, combatant.get("hp", 0) - potency)
					if combatant["hp"] <= 0:
						combatant["alive"] = false
				"regen":
					combatant["hp"] = mini(
						combatant.get("hp", 0) + potency,
						combatant.get("max_hp", 100)
					)
				"burn":
					combatant["hp"] = maxi(0, combatant.get("hp", 0) - potency)
					if combatant["hp"] <= 0:
						combatant["alive"] = false

			# Reduce duration
			effect["duration"] = effect.get("duration", 0) - 1
			if effect["duration"] <= 0:
				to_remove.append(i)

		# Remove expired effects (reverse order)
		to_remove.reverse()
		for idx in to_remove:
			effects.remove_at(idx)

# -----------------------------------------------------------------------
# Combat resolution
# -----------------------------------------------------------------------

func _check_combat_end() -> String:
	## Returns "ongoing", "victory", or "defeat".
	var any_player_alive: bool = false
	for p in party:
		if p.get("alive", true):
			any_player_alive = true
			break

	if not any_player_alive:
		return "defeat"

	var any_enemy_alive: bool = false
	for e in enemies:
		if e.get("alive", true):
			any_enemy_alive = true
			break

	if not any_enemy_alive:
		return "victory"

	return "ongoing"


func _distribute_rewards(encounter_data: Dictionary) -> Dictionary:
	## Calculate and return rewards from the encounter.
	var rewards: Dictionary = {
		"xp": 0,
		"gold": 0,
		"items": [],
	}

	for enemy in enemies:
		rewards["xp"] += enemy.get("xp_reward", 10)
		rewards["gold"] += enemy.get("gold_reward", 5)
		var loot: Array = enemy.get("loot", [])
		for item in loot:
			if item is Dictionary:
				var drop_chance: float = item.get("drop_chance", 0.5)
				if randf() < drop_chance:
					rewards["items"].append(item)

	# Also check encounter-level rewards
	var enc_rewards: Dictionary = encounter_data.get("rewards", {})
	rewards["xp"] += enc_rewards.get("xp", 0)
	rewards["gold"] += enc_rewards.get("gold", 0)
	var enc_items: Array = enc_rewards.get("items", [])
	rewards["items"].append_array(enc_items)

	return rewards


func _end_combat(result: String) -> void:
	var rewards: Dictionary = {}

	if result == "victory":
		rewards = _distribute_rewards(_encounter_data)
		GameState.add_xp(rewards.get("xp", 0))
		GameState.gold += rewards.get("gold", 0)
		for item in rewards.get("items", []):
			if item is Dictionary:
				GameState.add_item(item)
		state = CombatState.VICTORY
	elif result == "defeat":
		state = CombatState.DEFEAT
		EventBus.player_died.emit()
	else:
		state = CombatState.IDLE

	# Sync HP/MP back to GameState from party
	if party.size() > 0:
		GameState.player_stats["hp"] = party[0].get("hp", GameState.player_stats["hp"])
		GameState.player_stats["mp"] = party[0].get("mp", GameState.player_stats["mp"])
		GameState.player_stats_changed.emit()

	EventBus.combat_ended.emit(result)
	combat_finished.emit(result, rewards)

	# Clean up
	party.clear()
	enemies.clear()
	turn_order.clear()
	_encounter_data = {}
