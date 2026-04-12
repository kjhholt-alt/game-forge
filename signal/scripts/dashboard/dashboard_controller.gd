## Dashboard controller — manages the 4-panel layout and phase transitions.
##
## The main scene that contains all dashboard panels:
## Evidence Board | Document Viewer
## Terminal       | Comms
##
## Panel visibility and sizing changes based on the current phase.
extends Control


# ---------------------------------------------------------------------------
# Node references — assigned in the scene tree
# ---------------------------------------------------------------------------

@onready var top_bar: Control = $TopBar
@onready var phase_label: Label = $TopBar/PhaseLabel
@onready var op_label: Label = $TopBar/OpLabel
@onready var detection_bar: ProgressBar = $TopBar/DetectionBar
@onready var clock_label: Label = $TopBar/ClockLabel

@onready var main_split: HSplitContainer = $MainSplit
@onready var left_split: VSplitContainer = $MainSplit/LeftSplit
@onready var right_split: VSplitContainer = $MainSplit/RightSplit

@onready var evidence_board: GraphEdit = $MainSplit/LeftSplit/EvidenceBoard
@onready var terminal: Control = $MainSplit/LeftSplit/Terminal
@onready var document_viewer: Control = $MainSplit/RightSplit/DocumentViewer
@onready var comms_panel: Control = $MainSplit/RightSplit/CommsPanel

@onready var go_dark_button: Button = $TopBar/GoDarkButton


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _current_phase: String = "briefing"
var _op_data: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	EventBus.phase_changed.connect(_on_phase_changed)
	EventBus.detection_changed.connect(_on_detection_changed)
	EventBus.analyst_burned.connect(_on_analyst_burned)
	go_dark_button.pressed.connect(_on_go_dark_pressed)

	# Style the detection bar
	detection_bar.min_value = 0.0
	detection_bar.max_value = 1.0
	detection_bar.value = 0.0

	_apply_phase_layout("briefing")


func _process(_delta: float) -> void:
	# Update clock
	clock_label.text = Time.get_time_string_from_system().substr(0, 5)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func load_operation(op_data: Dictionary) -> void:
	"""Load an operation and set up all panels."""
	_op_data = op_data

	# Update top bar
	var briefing: Dictionary = op_data.get("briefing", {})
	op_label.text = "OP: %s" % briefing.get("codename", "UNKNOWN")

	# Load operation state
	OpState.load_operation(op_data)

	# Load evidence onto the board
	var signal_data: Dictionary = op_data.get("signal_data", {})
	evidence_board.load_evidence(signal_data.get("items", []))

	# Load network data into terminal
	var target: Dictionary = op_data.get("blacksite_target", {})
	var network: Dictionary = target.get("network", {})
	terminal.load_network(network)

	# Transition to SIGNAL phase
	GameState.set_phase("signal")


# ---------------------------------------------------------------------------
# Phase transitions
# ---------------------------------------------------------------------------

func _on_phase_changed(new_phase: String) -> void:
	_current_phase = new_phase
	_apply_phase_layout(new_phase)


func _apply_phase_layout(phase: String) -> void:
	"""Adjust panel visibility and sizing for the current phase."""
	match phase:
		"briefing":
			phase_label.text = "[BRIEFING]"
			phase_label.add_theme_color_override("font_color", Color(0.4, 0.7, 0.9))
			terminal.visible = false
			evidence_board.visible = false
			go_dark_button.visible = false
			detection_bar.visible = false

		"signal":
			phase_label.text = "[SIGNAL]"
			phase_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
			evidence_board.visible = true
			terminal.visible = false
			go_dark_button.visible = true
			go_dark_button.text = "GO DARK"
			detection_bar.visible = false

			# Expand evidence board to full left side
			left_split.split_offset = left_split.size.y

		"blacksite":
			phase_label.text = "[BLACKSITE]"
			phase_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
			evidence_board.visible = true
			terminal.visible = true
			go_dark_button.visible = true
			go_dark_button.text = "EXFIL"
			detection_bar.visible = true

			# Split left side between evidence board (top) and terminal (bottom)
			left_split.split_offset = int(left_split.size.y * 0.35)

		"debrief":
			phase_label.text = "[DEBRIEF]"
			phase_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			terminal.visible = false
			evidence_board.visible = false
			go_dark_button.visible = false
			detection_bar.visible = false


func _on_detection_changed(level: String, value: float) -> void:
	"""Update the detection bar."""
	detection_bar.value = value

	var bar_style := StyleBoxFlat.new()
	match level:
		"green":
			bar_style.bg_color = Color(0.2, 0.7, 0.3)
		"yellow":
			bar_style.bg_color = Color(0.9, 0.7, 0.2)
		"red":
			bar_style.bg_color = Color(0.9, 0.3, 0.2)
		"black":
			bar_style.bg_color = Color(0.9, 0.1, 0.1)

	detection_bar.add_theme_stylebox_override("fill", bar_style)


func _on_go_dark_pressed() -> void:
	"""Handle Go Dark / Exfil button."""
	match _current_phase:
		"signal":
			# Compute prep score and transition to BLACKSITE
			var score := OpState.compute_prep_score()
			EventBus.go_dark_requested.emit(score)
			GameState.set_phase("blacksite")

		"blacksite":
			# End BLACKSITE — check if required exfil targets are collected
			var required: Array = _op_data.get("required_exfil", [])
			var success := true
			for req_file in required:
				if req_file not in OpState.exfiltrated_files:
					success = false
					break

			var burned: bool = OpState.detection_level == "black"
			EventBus.blacksite_ended.emit(success, burned)
			GameState.set_phase("debrief")


func _on_analyst_burned() -> void:
	"""Handle analyst burn — disable interaction, show burn screen."""
	go_dark_button.text = "BURNED"
	go_dark_button.disabled = true
