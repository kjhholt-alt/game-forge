## Per-operation state — evidence board, detection, terminal session.
##
## Reset when a new operation begins. Tracks everything that happens
## during a single SIGNAL → BLACKSITE → Debrief cycle.
extends Node


# ---------------------------------------------------------------------------
# Evidence board state
# ---------------------------------------------------------------------------

## All evidence items for this operation { id -> item_dict }
var evidence_items: Dictionary = {}

## Player-drawn connections [ { id, from_id, to_id, type, note } ]
var connections: Array = []

## Evidence items currently pinned to the board
var pinned_ids: Array = []

## Computed prep score (0.0 - 1.0)
var prep_score: float = 0.0


# ---------------------------------------------------------------------------
# Detection state (BLACKSITE)
# ---------------------------------------------------------------------------

## Detection value (0.0 - 1.0)
var detection_value: float = 0.0

## Current detection level string
var detection_level: String = "green"

## Detection threshold that triggers burn (lower = harder op)
var burn_threshold: float = 1.0

## Detection increments per action type
const DETECTION_COSTS := {
	"scan": 0.05,
	"probe": 0.03,
	"exploit_success": 0.10,
	"exploit_fail": 0.20,
	"login_fail": 0.08,
	"download": 0.07,
	"se_suspicious": 0.12,
	"se_failed": 0.15,
}


# ---------------------------------------------------------------------------
# Terminal state (BLACKSITE)
# ---------------------------------------------------------------------------

## Hosts the player has discovered { host_id -> host_dict }
var discovered_hosts: Dictionary = {}

## Hosts the player is currently connected to
var connected_host_id: String = ""

## Current working directory on connected host
var current_path: String = "/"

## Credentials the player has found [ { username, password, host_id } ]
var found_credentials: Array = []

## Files the player has exfiltrated [ file_id ]
var exfiltrated_files: Array = []


# ---------------------------------------------------------------------------
# Social engineering state
# ---------------------------------------------------------------------------

## Employee trust/suspicion states { employee_id -> { trust, suspicion, secrets_revealed } }
var employee_states: Dictionary = {}


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func reset() -> void:
	"""Reset all state for a new operation."""
	evidence_items.clear()
	connections.clear()
	pinned_ids.clear()
	prep_score = 0.0
	detection_value = 0.0
	detection_level = "green"
	burn_threshold = 1.0
	discovered_hosts.clear()
	connected_host_id = ""
	current_path = "/"
	found_credentials.clear()
	exfiltrated_files.clear()
	employee_states.clear()


func load_operation(op_data: Dictionary) -> void:
	"""Load operation data and populate evidence items."""
	reset()

	burn_threshold = op_data.get("max_detection_threshold", 1.0)

	# Load evidence items from signal_data
	var signal_data: Dictionary = op_data.get("signal_data", {})
	for item in signal_data.get("items", []):
		evidence_items[item.get("id", "")] = item

	# Load employee profiles for social engineering state
	var target: Dictionary = op_data.get("blacksite_target", {})
	for emp in target.get("employees", []):
		var emp_id: String = emp.get("id", "")
		employee_states[emp_id] = {
			"trust": 0,
			"suspicion": 0,
			"secrets_revealed": [],
		}


func add_detection(action_type: String) -> void:
	"""Increase detection based on action type. May trigger burn."""
	var cost: float = DETECTION_COSTS.get(action_type, 0.05)

	# Network Exploitation skill reduces detection
	var net_level: int = GameState.get_skill_level("network_exploitation")
	cost *= (1.0 - (net_level - 1) * 0.08)  # 8% reduction per level above 1

	detection_value = min(1.0, detection_value + cost)
	_update_detection_level()


func _update_detection_level() -> void:
	"""Update detection level string based on current value."""
	var old_level := detection_level

	if detection_value < 0.25:
		detection_level = "green"
	elif detection_value < 0.50:
		detection_level = "yellow"
	elif detection_value < 0.75:
		detection_level = "red"
	else:
		detection_level = "black"

	if detection_level != old_level:
		EventBus.detection_changed.emit(detection_level, detection_value)

		if detection_level == "black":
			EventBus.analyst_burned.emit()


func compute_prep_score() -> float:
	"""Score the evidence board based on correct connections.

	Returns a value between 0.0 and 1.0 representing board quality.
	"""
	if connections.is_empty():
		prep_score = 0.0
		return prep_score

	var correct_count := 0
	var total_possible := 0

	# Count how many clue items exist (items with is_clue=true)
	for item in evidence_items.values():
		if item.get("is_clue", false):
			total_possible += len(item.get("clue_target_ids", []))

	if total_possible == 0:
		prep_score = 0.5  # No clues means default mid-score
		return prep_score

	# Check each player connection against actual clue targets
	for conn in connections:
		var from_item: Dictionary = evidence_items.get(conn.get("from_id", ""), {})
		var to_id: String = conn.get("to_id", "")
		if from_item.get("is_clue", false) and to_id in from_item.get("clue_target_ids", []):
			correct_count += 1

	prep_score = clamp(float(correct_count) / float(total_possible), 0.0, 1.0)
	return prep_score


func add_credential(username: String, password: String, host_id: String) -> void:
	"""Add a discovered credential."""
	found_credentials.append({
		"username": username,
		"password": password,
		"host_id": host_id,
	})


func exfiltrate_file(file_id: String) -> void:
	"""Mark a file as exfiltrated."""
	if file_id not in exfiltrated_files:
		exfiltrated_files.append(file_id)
		EventBus.file_exfiltrated.emit(file_id)
