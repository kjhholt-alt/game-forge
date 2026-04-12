## Central game state — campaign, analyst, and current operation data.
##
## Loaded from JSON files produced by the GameForge pipeline.
## This autoload is the single source of truth for all game data.
extends Node


# ---------------------------------------------------------------------------
# Campaign state
# ---------------------------------------------------------------------------

var campaign_data: Dictionary = {}
var current_op_index: int = 0
var campaign_loaded: bool = false

# ---------------------------------------------------------------------------
# Analyst state
# ---------------------------------------------------------------------------

var analyst: Dictionary = {
	"id": "",
	"codename": "",
	"name": "",
	"skills": {},       # skill_type -> { level, xp, xp_to_next }
	"toolkit": [],      # Array of toolkit item dicts
	"alive": true,
	"ops_completed": 0,
	"predecessors": [], # Previous analyst codenames
}

# ---------------------------------------------------------------------------
# Session state (reset per operation)
# ---------------------------------------------------------------------------

var current_phase: String = "briefing"  # briefing, signal, blacksite, debrief

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func load_campaign(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to load campaign: %s" % path)
		return false

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_error("Failed to parse campaign JSON: %s" % json.get_error_message())
		return false

	campaign_data = json.data
	current_op_index = campaign_data.get("current_op_index", 0)
	campaign_loaded = true

	# Load analyst
	var analyst_raw: Dictionary = campaign_data.get("analyst", {})
	if analyst_raw:
		analyst.id = analyst_raw.get("id", "")
		analyst.codename = analyst_raw.get("codename", "UNKNOWN")
		analyst.name = analyst_raw.get("name", "")
		analyst.alive = analyst_raw.get("alive", true)
		analyst.ops_completed = analyst_raw.get("ops_completed", 0)
		analyst.predecessors = analyst_raw.get("predecessor_codenames", [])

		# Parse skills
		for skill_data in analyst_raw.get("skills", []):
			var st: String = skill_data.get("skill_type", "")
			analyst.skills[st] = {
				"level": skill_data.get("level", 1),
				"xp": skill_data.get("xp", 0),
				"xp_to_next": skill_data.get("xp_to_next", 100),
			}

		# Parse toolkit
		analyst.toolkit = analyst_raw.get("toolkit", [])

	EventBus.campaign_loaded.emit(campaign_data.get("id", ""))
	return true


func get_current_operation() -> Dictionary:
	var ops: Array = campaign_data.get("operations", [])
	if current_op_index < ops.size():
		return ops[current_op_index]
	return {}


func get_operation(index: int) -> Dictionary:
	var ops: Array = campaign_data.get("operations", [])
	if index >= 0 and index < ops.size():
		return ops[index]
	return {}


func get_skill_level(skill_type: String) -> int:
	if analyst.skills.has(skill_type):
		return analyst.skills[skill_type].get("level", 1)
	return 1


func add_xp(skill_type: String, amount: int) -> void:
	if not analyst.skills.has(skill_type):
		analyst.skills[skill_type] = {"level": 1, "xp": 0, "xp_to_next": 100}

	var skill: Dictionary = analyst.skills[skill_type]
	skill.xp += amount
	EventBus.xp_gained.emit(skill_type, amount)

	# Check for level up (cap at 5)
	while skill.xp >= skill.xp_to_next and skill.level < 5:
		skill.xp -= skill.xp_to_next
		skill.level += 1
		skill.xp_to_next = int(skill.xp_to_next * 1.5)
		EventBus.skill_leveled_up.emit(skill_type, skill.level)


func set_phase(new_phase: String) -> void:
	current_phase = new_phase
	EventBus.phase_changed.emit(new_phase)
