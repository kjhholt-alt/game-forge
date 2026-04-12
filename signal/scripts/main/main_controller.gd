## Main controller — loads mission, drops player on the tactical map instantly.
##
## No boot. No briefing wall. Map appears. Blips pulse. Handler speaks.
## Player clicks. That's the game.
extends Control


@onready var tactical_map: Control = $TacticalMap
@onready var hud: Control = $HUD
@onready var coa_cards: Control = $COACards

var _mission_data: Dictionary = {}
var _assets: Dictionary = {}  # id -> asset data

const TEST_MISSION_PATH := "res://data/test_mission.json"


func _ready() -> void:
	EventBus.blip_clicked.connect(_on_blip_clicked)
	EventBus.coa_requested.connect(_on_coa_requested)
	EventBus.coa_selected.connect(_on_coa_selected)
	EventBus.asset_arrived.connect(_on_asset_arrived)

	_load_mission()


func _load_mission() -> void:
	var file := FileAccess.open(TEST_MISSION_PATH, FileAccess.READ)
	if not file:
		push_error("Failed to load mission: %s" % TEST_MISSION_PATH)
		return

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("JSON parse error: %s" % json.get_error_message())
		return

	_mission_data = json.data

	# Set HUD
	hud.set_codename(_mission_data.get("codename", "UNKNOWN"))
	EventBus.budget_changed.emit(_mission_data.get("budget", 50000))

	# Spawn target blips
	for target in _mission_data.get("targets", []):
		var pos := Vector2(target.get("x", 0), target.get("y", 0))
		tactical_map.add_blip(
			target.get("id", ""),
			pos,
			"unknown",
			"?",
			target.get("handler_detect", "Contact detected."),
		)

	# Spawn asset blips at base
	var base_pos := Vector2(
		_mission_data.get("base_x", 100),
		_mission_data.get("base_y", 400),
	)
	for asset in _mission_data.get("assets", []):
		var asset_id: String = asset.get("id", "")
		tactical_map.add_blip(asset_id, base_pos, "asset", asset.get("label", "UNIT"))
		_assets[asset_id] = asset
		base_pos.x += 40  # Stagger asset positions

	# Handler opens the mission
	await get_tree().create_timer(0.5).timeout
	VoiceHandler.speak(_mission_data.get("handler_open", "New operation. Targets on screen."))


func _on_blip_clicked(blip_id: String) -> void:
	var blip = tactical_map.get_blip(blip_id)
	if not blip:
		return

	# If it's an unclassified target, classify it on click
	if blip.blip_type == "unknown":
		var target_data := _find_target(blip_id)
		if target_data.is_empty():
			return

		# Classify the blip
		tactical_map.classify_blip(
			blip_id,
			target_data.get("type", "hostile"),
			target_data.get("label", "TARGET"),
		)

		# Handler speaks the classification
		var line: String = target_data.get("handler_classify", "Target classified.")
		VoiceHandler.speak(line)

		# Juice
		Juice.float_text(tactical_map, target_data.get("label", ""), tactical_map._world_to_screen(blip.pos) + Vector2(0, -30), Color(0.9, 0.6, 0.1))


func _on_coa_requested(blip_id: String) -> void:
	var target_data := _find_target(blip_id)
	if target_data.is_empty():
		return

	# Get COA options for this target
	var coas: Array = target_data.get("coas", [])
	if coas.is_empty():
		VoiceHandler.speak("No options available for this target.")
		return

	# Handler speaks the options summary
	var coa_line: String = target_data.get("handler_coa", "Options available.")
	VoiceHandler.speak(coa_line)

	# Show COA cards
	coa_cards.show_options(blip_id, coas)


func _on_coa_selected(blip_id: String, coa_id: String) -> void:
	var target_data := _find_target(blip_id)
	var coa_data := {}
	for coa in target_data.get("coas", []):
		if coa.get("id", "") == coa_id:
			coa_data = coa
			break

	if coa_data.is_empty():
		return

	# Find which asset to assign (for now, first available)
	var assigned_asset := ""
	for asset_id in _assets:
		assigned_asset = asset_id
		break

	if assigned_asset.is_empty():
		VoiceHandler.speak("No assets available.")
		return

	# Handler confirms
	var asset_label: String = _assets[assigned_asset].get("label", "Unit")
	VoiceHandler.speak(coa_data.get("handler_assign", "%s assigned." % asset_label))

	# Move asset toward target
	var speed: float = _assets[assigned_asset].get("speed", 0.4)
	tactical_map.move_asset(assigned_asset, blip_id, speed)
	EventBus.mission_started.emit(blip_id, coa_id, assigned_asset)


func _on_asset_arrived(asset_id: String, target_id: String) -> void:
	var target_data := _find_target(target_id)
	if target_data.is_empty():
		return

	# Resolve — for now, simple success
	VoiceHandler.speak(target_data.get("handler_resolve", "Mission complete."))

	# Mark target as neutralized
	tactical_map.classify_blip(target_id, "neutralized", "DONE")

	var blip = tactical_map.get_blip(target_id)
	if blip:
		Juice.float_text(
			tactical_map,
			"COMPLETE",
			tactical_map._world_to_screen(blip.pos) + Vector2(0, -30),
			Color(0.2, 0.9, 0.4),
		)

	# Return asset to base
	# (for now just leave it there — Phase 1 adds proper asset return)


func _find_target(blip_id: String) -> Dictionary:
	for target in _mission_data.get("targets", []):
		if target.get("id", "") == blip_id:
			return target
	return {}
