## Main controller — runs the full operation loop.
##
## Briefing → SIGNAL (evidence board) → BLACKSITE (terminal + SE) → Debrief.
## Loads campaign data through GameState, delegates phase-specific UI to child nodes.
extends Control


@onready var tactical_map: Control = $TacticalMap
@onready var hud: Control = $HUD
@onready var coa_cards: Control = $COACards
@onready var target_sidebar: PanelContainer = $TargetSidebar
@onready var info_card: Control = $InfoCard
@onready var timeline_bar: PanelContainer = $TimelineBar

# Phase overlay nodes — created dynamically or expected as children
var _briefing_overlay: Control = null
var _debrief_overlay: Control = null

# --- Mission state (tactical map layer) ---
var _mission_data: Dictionary = {}
var _assets: Dictionary = {}
var _budget: int = 50000
var _targets_neutralized: int = 0
var _total_targets: int = 0
var _active_missions: Dictionary = {}  # target_id -> {asset_id, coa_id, started_at}
var _classifications_done: int = 0  # Track for onboarding hints

# --- Campaign paths ---
const CAMPAIGN_PATH := "res://data/test_campaign.json"
const FALLBACK_MISSION_PATH := "res://data/test_mission.json"

# --- Detection costs for tactical COAs ---
const DETECTION_COSTS := {
	"surveil": 0.02,
	"intercept": 0.08,
	"strike": 0.15,
	"hack": 0.06,
	"capture": 0.12,
	"jam": 0.10,
	"monitor": 0.01,
}

const BUDGET_REWARDS := {
	"surveil": 3000,
	"intercept": 8000,
	"strike": 12000,
	"hack": 6000,
	"capture": 15000,
	"jam": 5000,
	"monitor": 2000,
}


func _ready() -> void:
	# Wire up tactical map signals
	EventBus.blip_clicked.connect(_on_blip_clicked)
	EventBus.coa_requested.connect(_on_coa_requested)
	EventBus.coa_selected.connect(_on_coa_selected)
	EventBus.asset_assigned.connect(_on_asset_assigned)
	EventBus.asset_arrived.connect(_on_asset_arrived)
	EventBus.asset_returned.connect(_on_asset_returned)

	# Wire up phase & campaign signals
	EventBus.file_exfiltrated.connect(_on_file_exfiltrated)
	EventBus.analyst_burned.connect(_on_analyst_burned)

	# Load standalone tactical mission directly — no campaign briefing walls
	_load_standalone_mission()


# ===========================================================================
# Phase state machine
# ===========================================================================

func _start_from_campaign() -> void:
	var op: Dictionary = GameState.get_current_operation()
	if op.is_empty():
		push_error("No operations in campaign")
		return

	# Load operation state
	OpState.load_operation(op)

	# Set HUD from campaign data
	var briefing: Dictionary = op.get("briefing", {})
	hud.set_codename(briefing.get("codename", "UNKNOWN"))

	_enter_briefing_phase(op)


func _enter_briefing_phase(op: Dictionary) -> void:
	GameState.set_phase("briefing")

	var briefing: Dictionary = op.get("briefing", {})
	var codename: String = briefing.get("codename", "UNKNOWN")
	var summary: String = briefing.get("summary", "No briefing available.")
	var objectives: Array = briefing.get("objectives", [])

	# Dim the tactical map
	tactical_map.modulate = Color(0.3, 0.3, 0.35, 1.0)

	# Create briefing overlay
	_briefing_overlay = _create_briefing_overlay(codename, summary, objectives)
	add_child(_briefing_overlay)
	move_child(_briefing_overlay, get_child_count() - 2)  # Before CRT overlay

	# Handler speaks the briefing
	await get_tree().create_timer(0.8).timeout
	VoiceHandler.speak("Operation %s. %s" % [codename, summary])

	# Warnings
	var warnings: Array = briefing.get("warnings", [])
	if not warnings.is_empty():
		await get_tree().create_timer(3.0).timeout
		VoiceHandler.speak("Be advised: %s" % warnings[0])


func _enter_signal_phase() -> void:
	GameState.set_phase("signal")

	# Remove briefing overlay
	if _briefing_overlay and is_instance_valid(_briefing_overlay):
		_briefing_overlay.queue_free()
		_briefing_overlay = null

	# Restore tactical map
	var tween := create_tween()
	tween.tween_property(tactical_map, "modulate", Color.WHITE, 0.5)

	# Load tactical targets from mission data (if present)
	_load_tactical_targets()

	VoiceHandler.speak("SIGNAL phase. Review the evidence. Draw connections. When you're ready, go dark.")

	# The evidence board UI (Lane 2) will show itself when phase_changed fires


func _enter_blacksite_phase() -> void:
	GameState.set_phase("blacksite")

	# Compute and announce prep score
	var prep: float = OpState.compute_prep_score()
	EventBus.prep_score_updated.emit(prep)

	var prep_text: String
	if prep >= 0.8:
		prep_text = "Excellent prep. You know exactly where to look."
	elif prep >= 0.5:
		prep_text = "Decent prep. You have leads to follow."
	elif prep >= 0.2:
		prep_text = "Minimal prep. You're going in partially blind."
	else:
		prep_text = "No prep. You'll have to find everything yourself. Good luck."

	VoiceHandler.speak("Going dark. %s" % prep_text)

	# The terminal UI (Lane 3) and social eng UI (Lane 4) show themselves
	# when phase_changed fires. Dim tactical map slightly.
	var tween := create_tween()
	tween.tween_property(tactical_map, "modulate", Color(0.5, 0.5, 0.55, 1.0), 0.5)


func _enter_debrief_phase(result: String) -> void:
	GameState.set_phase("debrief")

	# Compute grade
	var grade: String
	var grade_color: Color
	var det: float = OpState.detection_value
	var exfil_count: int = OpState.exfiltrated_files.size()

	if result == "burned":
		grade = "BURNED"
		grade_color = Color(0.9, 0.1, 0.1)
	elif det < 0.15 and exfil_count > 0:
		grade = "SHADOW"
		grade_color = Color(0.2, 0.9, 0.4)
	elif det < 0.35 and exfil_count > 0:
		grade = "GHOST"
		grade_color = Color(0.3, 0.8, 0.5)
	elif det < 0.6:
		grade = "OPERATIVE"
		grade_color = Color(0.9, 0.7, 0.2)
	else:
		grade = "COMPROMISED"
		grade_color = Color(0.9, 0.4, 0.2)

	# Award XP based on performance
	if result != "burned":
		GameState.add_xp("sigint", 20 + int(OpState.prep_score * 30))
		if exfil_count > 0:
			GameState.add_xp("network_exploitation", 25)
		# SE XP based on secrets revealed
		var total_secrets := 0
		for emp_state in OpState.employee_states.values():
			total_secrets += emp_state.get("secrets_revealed", []).size()
		if total_secrets > 0:
			GameState.add_xp("social_engineering", total_secrets * 15)

	VoiceHandler.speak("Operation complete. Grade: %s." % grade)

	# Big floating grade
	Juice.float_text(tactical_map, grade, Vector2(size.x / 2 - 40, size.y / 2), grade_color)

	EventBus.mission_complete.emit(grade)

	# Create debrief overlay
	_debrief_overlay = _create_debrief_overlay(grade, grade_color, exfil_count, det)
	add_child(_debrief_overlay)
	move_child(_debrief_overlay, get_child_count() - 2)


# ===========================================================================
# Phase transition triggers
# ===========================================================================

func _on_file_exfiltrated(file_id: String) -> void:
	# Check if all required files have been exfiltrated
	var op: Dictionary = GameState.get_current_operation()
	var required: Array = op.get("required_exfil", [])
	if required.is_empty():
		return

	var all_found := true
	for req in required:
		if req not in OpState.exfiltrated_files:
			all_found = false
			break

	if all_found:
		VoiceHandler.speak("All targets acquired. Extract now.")
		await get_tree().create_timer(2.0).timeout
		_enter_debrief_phase("success")


func _on_analyst_burned() -> void:
	VoiceHandler.speak_now("Burned. They know who you are. Get out.")
	Juice.pulse_color(tactical_map, Color(0.9, 0.1, 0.1, 0.3), 1.0)
	await get_tree().create_timer(2.0).timeout
	_enter_debrief_phase("burned")


# ===========================================================================
# Input — phase transitions via keyboard
# ===========================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ENTER:
				if GameState.current_phase == "briefing":
					_enter_signal_phase()
			KEY_TAB:
				if GameState.current_phase == "signal":
					_enter_blacksite_phase()
			KEY_ESCAPE:
				if GameState.current_phase == "blacksite":
					_enter_debrief_phase("extract")
			KEY_SLASH:
				# ? key — ask handler for advice
				_ask_for_advice()


func _ask_for_advice() -> void:
	VoiceHandler.speak("Analyzing situation...")
	ClaudeDM.get_advice(_build_game_state(), func(ai_text: String):
		if not ai_text.is_empty():
			VoiceHandler.speak(ai_text)
		else:
			VoiceHandler.speak("No advisory available.")
	)


# ===========================================================================
# Tactical map operations (same as before, works in SIGNAL + BLACKSITE)
# ===========================================================================

func _load_tactical_targets() -> void:
	# Try campaign mission data first, fall back to standalone
	if _mission_data.is_empty():
		_load_standalone_mission()
		return

	_apply_mission_data()


func _load_standalone_mission() -> void:
	var file := FileAccess.open(FALLBACK_MISSION_PATH, FileAccess.READ)
	if not file:
		push_error("Failed to load: %s" % FALLBACK_MISSION_PATH)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("JSON error: %s" % json.get_error_message())
		return
	file.close()
	_mission_data = json.data
	_apply_mission_data()


func _apply_mission_data() -> void:
	_budget = _mission_data.get("budget", 50000)
	hud.set_codename(_mission_data.get("codename", "UNKNOWN"))
	EventBus.budget_changed.emit(_budget)

	var base_pos := Vector2(_mission_data.get("base_x", 100), _mission_data.get("base_y", 400))
	tactical_map.set_base_pos(base_pos)

	# === STAGGERED INTRODUCTION ===
	# Don't dump everything at once. Introduce one element at a time.
	# The handler voice IS the tutorial.

	# Beat 1 (0.8s): Handler speaks, map is empty
	await get_tree().create_timer(0.8).timeout
	VoiceHandler.speak("Operations center online. Stand by for contacts.")

	# Beat 2 (2.5s): First target appears with drama
	await get_tree().create_timer(2.0).timeout
	var targets: Array = _mission_data.get("targets", [])
	if targets.size() > 0:
		var t0: Dictionary = targets[0]
		var t0_id: String = t0.get("id", "")
		tactical_map.add_blip(t0_id, Vector2(t0.get("x", 0), t0.get("y", 0)), "unknown", "UNKNOWN", t0.get("handler_detect", "Contact."))
		target_sidebar.add_entry(t0_id, "UNKNOWN CONTACT", "unknown")
		_total_targets += 1
		hud.update_objectives(_targets_neutralized, _total_targets)
		if t0.get("type", "") == "hostile":
			tactical_map.add_threat_zone(Vector2(t0.get("x", 0), t0.get("y", 0)), t0.get("threat_radius", 100))
		await get_tree().create_timer(0.5).timeout
		VoiceHandler.speak("Contact detected. Click on it to identify.")

	# Beat 3 (5s): Wait for player to click first blip, then introduce rest
	# (We wait up to 15s for them to click, then add remaining anyway)
	var _waited := 0.0
	while _waited < 15.0:
		await get_tree().create_timer(0.5).timeout
		_waited += 0.5
		# Check if they classified the first target
		if targets.size() > 0:
			var first_blip = tactical_map.get_blip(targets[0].get("id", ""))
			if first_blip and first_blip.classified:
				break

	# Beat 4: After first classification, add remaining targets one by one
	await get_tree().create_timer(1.0).timeout
	if targets.size() > 1:
		VoiceHandler.speak("More contacts appearing.")
	for i in range(1, targets.size()):
		await get_tree().create_timer(1.2).timeout
		var t: Dictionary = targets[i]
		var tid: String = t.get("id", "")
		tactical_map.add_blip(tid, Vector2(t.get("x", 0), t.get("y", 0)), "unknown", "UNKNOWN", t.get("handler_detect", "Contact."))
		target_sidebar.add_entry(tid, "UNKNOWN CONTACT", "unknown")
		_total_targets += 1
		hud.update_objectives(_targets_neutralized, _total_targets)
		if t.get("type", "") == "hostile":
			tactical_map.add_threat_zone(Vector2(t.get("x", 0), t.get("y", 0)), t.get("threat_radius", 100))

	# Beat 5: Introduce assets at base
	await get_tree().create_timer(1.5).timeout
	VoiceHandler.speak("Your assets are at base. Drag them to a target, or right-click a target for options.")
	var offset := Vector2.ZERO
	for asset in _mission_data.get("assets", []):
		await get_tree().create_timer(0.6).timeout
		var aid: String = asset.get("id", "")
		tactical_map.add_blip(aid, base_pos + offset, "asset", asset.get("label", "UNIT"))
		target_sidebar.add_entry(aid, asset.get("label", "UNIT"), "asset")
		_assets[aid] = asset
		offset.x += 60

	# Delayed targets
	if _mission_data.has("delayed_targets"):
		_spawn_delayed_targets()


func _spawn_delayed_targets() -> void:
	await get_tree().create_timer(_mission_data.get("delay_seconds", 30.0)).timeout
	for dt in _mission_data.get("delayed_targets", []):
		tactical_map.add_blip(
			dt.get("id", ""), Vector2(dt.get("x", 0), dt.get("y", 0)),
			"unknown", "UNKNOWN", dt.get("handler_detect", "New contact."),
		)
		_total_targets += 1
		hud.update_objectives(_targets_neutralized, _total_targets)
		VoiceHandler.speak(dt.get("handler_detect", "New contact. Click to identify."))


# ===========================================================================
# Tactical signal handlers (blip clicks, COA, assets)
# ===========================================================================

func _on_blip_clicked(blip_id: String) -> void:
	var blip = tactical_map.get_blip(blip_id)
	if not blip:
		return

	if blip.blip_type == "unknown":
		var td := _find_target(blip_id)
		if td.is_empty():
			return
		var target_label: String = td.get("label", "TARGET")
		var target_type: String = td.get("type", "hostile")
		tactical_map.classify_blip(blip_id, target_type, target_label)
		_classifications_done += 1

		# Update sidebar
		target_sidebar.update_entry(blip_id, target_label, target_type)

		# Show rich info card near the blip (Maven-style analysis)
		var card_pos: Vector2 = tactical_map._world_to_screen(blip.pos) + tactical_map.global_position
		var analysis: Dictionary = td.get("analysis", {})
		var card_data := {
			"label": target_label,
			"type": target_type,
			"classification": analysis.get("classification", "Target classified"),
			"threat": analysis.get("threat", "unknown"),
			"details": analysis.get("details", []),
			"recommendation": analysis.get("recommendation", ""),
		}
		info_card.show_card(card_pos, card_data)

		# Claude intel assessment — or fall back to pre-written line
		var fallback_line: String = td.get("handler_classify", "Target classified.")
		ClaudeDM.get_intel_assessment(td, _build_game_state(), func(ai_text: String):
			VoiceHandler.speak(ai_text if not ai_text.is_empty() else fallback_line)
		)

		# Onboarding hint after first classification
		if _classifications_done == 1:
			get_tree().create_timer(3.5).timeout.connect(func():
				VoiceHandler.speak("Right-click that target for options. Or drag an asset directly to it.")
			)

		Juice.float_text(
			tactical_map, target_label,
			tactical_map._world_to_screen(blip.pos) + Vector2(0, -40),
			Color(0.95, 0.6, 0.1),
		)

	elif blip.blip_type == "asset" and not blip.busy:
		VoiceHandler.speak("Drag %s onto a red target." % blip.label)


func _on_coa_requested(blip_id: String) -> void:
	var td := _find_target(blip_id)
	if td.is_empty():
		return
	var coas: Array = td.get("coas", [])
	if coas.is_empty():
		return
	VoiceHandler.speak(td.get("handler_coa", "Options available."))
	coa_cards.show_options(blip_id, coas)


func _on_coa_selected(blip_id: String, coa_id: String) -> void:
	var td := _find_target(blip_id)
	var coa := _find_coa(td, coa_id)
	if coa.is_empty():
		return

	var best_asset := _find_free_asset()
	if best_asset.is_empty():
		VoiceHandler.speak("No assets available. Wait for one to return.")
		return

	_start_tactical_mission(blip_id, coa_id, best_asset, coa)


func _on_asset_assigned(asset_id: String, target_id: String) -> void:
	var td := _find_target(target_id)
	if td.is_empty():
		return

	if tactical_map.is_asset_busy(asset_id):
		VoiceHandler.speak("That asset is busy.")
		return

	var coas: Array = td.get("coas", [])
	if coas.is_empty():
		return

	VoiceHandler.speak(td.get("handler_coa", "Options."))
	coa_cards.show_options(target_id, coas)
	_active_missions["_pending_asset"] = {"asset_id": asset_id}


func _start_tactical_mission(target_id: String, coa_id: String, asset_id: String, coa: Dictionary) -> void:
	# Detection cost
	var det_cost: float = DETECTION_COSTS.get(coa_id, 0.05)
	OpState.add_detection(coa_id)

	# Claude handler commentary — or fall back to pre-written line
	var fallback_assign: String = coa.get("handler_assign", "Asset assigned.")
	ClaudeDM.get_handler_commentary("assign", _build_game_state(), func(ai_text: String):
		VoiceHandler.speak(ai_text if not ai_text.is_empty() else fallback_assign)
	)

	var speed: float = _assets.get(asset_id, {}).get("speed", 0.4)
	tactical_map.move_asset(asset_id, target_id, speed)

	_active_missions[target_id] = {
		"asset_id": asset_id,
		"coa_id": coa_id,
		"started_at": Time.get_ticks_msec(),
	}

	EventBus.mission_started.emit(target_id, coa_id, asset_id)

	# Add to timeline bar
	var asset_label: String = _assets.get(asset_id, {}).get("label", "UNIT")
	timeline_bar.add_mission(target_id, asset_label, coa_id)

	# Schedule complication
	var complication: Dictionary = coa.get("complication", {})
	if not complication.is_empty():
		var delay: float = complication.get("delay", 2.0)
		var timer := get_tree().create_timer(delay)
		timer.timeout.connect(func(): _trigger_complication(target_id, complication))


func _on_asset_arrived(asset_id: String, target_id: String) -> void:
	if target_id == "_base_return":
		return

	var td := _find_target(target_id)
	var mission: Dictionary = _active_missions.get(target_id, {})
	var coa_id: String = mission.get("coa_id", "")

	var coa := _find_coa(td, coa_id)
	var risk: float = coa.get("risk", 0.5)
	var success: bool = randf() > risk * 0.5

	if success:
		VoiceHandler.speak(td.get("handler_resolve", "Mission complete."))
		tactical_map.classify_blip(target_id, "neutralized", "DONE")
		target_sidebar.update_entry(target_id, "NEUTRALIZED", "neutralized")

		var reward: int = BUDGET_REWARDS.get(coa_id, 5000)
		_budget += reward
		EventBus.budget_changed.emit(_budget)

		var blip = tactical_map.get_blip(target_id)
		if blip:
			Juice.float_text(
				tactical_map, "+$%dK" % (reward / 1000),
				tactical_map._world_to_screen(blip.pos) + Vector2(0, -30),
				Color(0.2, 0.9, 0.4),
			)

		_targets_neutralized += 1
		hud.update_objectives(_targets_neutralized, _total_targets)

		if _targets_neutralized >= _total_targets:
			await get_tree().create_timer(1.5).timeout
			VoiceHandler.speak("All targets neutralized. Good work.")
	else:
		VoiceHandler.speak("Mission failed. Asset taking fire.")
		OpState.add_detection("exploit_fail")

		var blip = tactical_map.get_blip(target_id)
		if blip:
			Juice.float_text(
				tactical_map, "FAILED",
				tactical_map._world_to_screen(blip.pos) + Vector2(0, -30),
				Color(0.9, 0.2, 0.2),
			)

	_active_missions.erase(target_id)
	tactical_map.return_asset_to_base(asset_id)


func _on_asset_returned(asset_id: String) -> void:
	VoiceHandler.speak("%s back at base." % _assets.get(asset_id, {}).get("label", "Unit"))


func _trigger_complication(target_id: String, complication: Dictionary) -> void:
	if target_id not in _active_missions:
		return

	VoiceHandler.speak_now(complication.get("handler_text", "Complication."))

	if complication.has("spawn_blip"):
		var sb: Dictionary = complication["spawn_blip"]
		tactical_map.add_blip(
			sb.get("id", "comp-%d" % randi()),
			Vector2(sb.get("x", 0), sb.get("y", 0)),
			"unknown", "?",
		)
		_total_targets += 1
		hud.update_objectives(_targets_neutralized, _total_targets)

	OpState.add_detection("scan")
	Juice.pulse_color(tactical_map, Color(0.9, 0.7, 0.2, 0.15), 0.4)


# ===========================================================================
# UI builders (briefing + debrief overlays)
# ===========================================================================

func _create_briefing_overlay(codename: String, summary: String, objectives: Array) -> Control:
	var overlay := Control.new()
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	# Dark backdrop
	var bg := ColorRect.new()
	bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.color = Color(0.02, 0.025, 0.04, 0.85)
	overlay.add_child(bg)

	# Center panel
	var panel := PanelContainer.new()
	panel.anchors_preset = Control.PRESET_CENTER
	panel.offset_left = -320
	panel.offset_top = -200
	panel.offset_right = 320
	panel.offset_bottom = 200
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.95)
	sb.border_color = Color(0.15, 0.2, 0.3)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 32
	sb.content_margin_right = 32
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", sb)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	# Classification header
	var header := Label.new()
	header.text = "// CLASSIFIED //"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.9, 0.3, 0.2, 0.8))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	# Codename
	var title := Label.new()
	title.text = codename
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Summary
	var desc := Label.new()
	desc.text = summary
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.55, 0.6, 0.68))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(560, 0)
	vbox.add_child(desc)

	# Objectives
	if not objectives.is_empty():
		var obj_header := Label.new()
		obj_header.text = "OBJECTIVES"
		obj_header.add_theme_font_size_override("font_size", 11)
		obj_header.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6))
		vbox.add_child(obj_header)

		for i in range(objectives.size()):
			var obj := Label.new()
			obj.text = "  %d. %s" % [i + 1, objectives[i]]
			obj.add_theme_font_size_override("font_size", 12)
			obj.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
			obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(obj)

	# Prompt
	var prompt := Label.new()
	prompt.text = "[ENTER] BEGIN ANALYSIS"
	prompt.add_theme_font_size_override("font_size", 12)
	prompt.add_theme_color_override("font_color", Color(0.3, 0.7, 0.5, 0.7))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(prompt)

	# Pulse the prompt
	var tween := prompt.create_tween().set_loops()
	tween.tween_property(prompt, "modulate:a", 0.4, 1.0)
	tween.tween_property(prompt, "modulate:a", 1.0, 1.0)

	panel.add_child(vbox)

	return overlay


func _create_debrief_overlay(grade: String, grade_color: Color, exfil_count: int, detection: float) -> Control:
	var overlay := Control.new()
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.color = Color(0.02, 0.025, 0.04, 0.9)
	overlay.add_child(bg)

	var panel := PanelContainer.new()
	panel.anchors_preset = Control.PRESET_CENTER
	panel.offset_left = -250
	panel.offset_top = -180
	panel.offset_right = 250
	panel.offset_bottom = 180
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.95)
	sb.border_color = grade_color * Color(1, 1, 1, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 32
	sb.content_margin_right = 32
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", sb)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)

	var header := Label.new()
	header.text = "// DEBRIEF //"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var grade_label := Label.new()
	grade_label.text = grade
	grade_label.add_theme_font_size_override("font_size", 36)
	grade_label.add_theme_color_override("font_color", grade_color)
	grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(grade_label)

	var stats := Label.new()
	stats.text = "Files exfiltrated: %d\nDetection level: %d%%\nPrep score: %d%%" % [
		exfil_count,
		int(detection * 100),
		int(OpState.prep_score * 100),
	]
	stats.add_theme_font_size_override("font_size", 13)
	stats.add_theme_color_override("font_color", Color(0.55, 0.6, 0.68))
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats)

	# Skill XP summary
	var xp_text := "XP Gained:\n"
	for skill_type in GameState.analyst.skills:
		var skill: Dictionary = GameState.analyst.skills[skill_type]
		xp_text += "  %s: Lv%d (%d/%d XP)\n" % [
			skill_type.to_upper(), skill.get("level", 1),
			skill.get("xp", 0), skill.get("xp_to_next", 100),
		]
	var xp_label := Label.new()
	xp_label.text = xp_text
	xp_label.add_theme_font_size_override("font_size", 11)
	xp_label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6))
	vbox.add_child(xp_label)

	panel.add_child(vbox)

	return overlay


# ===========================================================================
# Helpers
# ===========================================================================

func _find_target(blip_id: String) -> Dictionary:
	for t in _mission_data.get("targets", []):
		if t.get("id", "") == blip_id:
			return t
	if _mission_data.has("delayed_targets"):
		for t in _mission_data.get("delayed_targets", []):
			if t.get("id", "") == blip_id:
				return t
	return {}


func _find_coa(target_data: Dictionary, coa_id: String) -> Dictionary:
	for coa in target_data.get("coas", []):
		if coa.get("id", "") == coa_id:
			return coa
	return {}


func _find_free_asset() -> String:
	for aid in _assets:
		if not tactical_map.is_asset_busy(aid):
			return aid
	return ""


func _build_game_state() -> Dictionary:
	var targets_info := []
	for t in _mission_data.get("targets", []):
		var tid: String = t.get("id", "")
		var blip = tactical_map.get_blip(tid)
		var status := "unknown"
		if blip:
			status = blip.blip_type
		targets_info.append({
			"id": tid,
			"label": t.get("label", ""),
			"status": status,
		})

	var assets_info := []
	for aid in _assets:
		assets_info.append({
			"id": aid,
			"label": _assets[aid].get("label", ""),
			"busy": tactical_map.is_asset_busy(aid),
		})

	return {
		"codename": _mission_data.get("codename", ""),
		"phase": GameState.current_phase,
		"detection": OpState.detection_value,
		"budget": _budget,
		"targets_neutralized": _targets_neutralized,
		"total_targets": _total_targets,
		"targets": targets_info,
		"assets": assets_info,
		"active_missions": _active_missions.size(),
	}
