## Main controller — bootstraps the game and manages top-level flow.
##
## Loads the test campaign, presents the briefing, then hands off
## to the dashboard for SIGNAL → BLACKSITE → Debrief.
extends Control


@onready var briefing_panel: Control = $BriefingPanel
@onready var briefing_codename: Label = $BriefingPanel/VBox/Codename
@onready var briefing_summary: RichTextLabel = $BriefingPanel/VBox/Summary
@onready var briefing_objectives: RichTextLabel = $BriefingPanel/VBox/Objectives
@onready var briefing_warnings: RichTextLabel = $BriefingPanel/VBox/Warnings
@onready var briefing_handler: RichTextLabel = $BriefingPanel/VBox/HandlerNotes
@onready var start_button: Button = $BriefingPanel/VBox/StartButton

@onready var dashboard: Control = $Dashboard
@onready var debrief: Control = $Debrief

const TEST_CAMPAIGN_PATH := "res://data/test_campaign.json"


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	EventBus.debrief_complete.connect(_on_debrief_complete)
	EventBus.phase_changed.connect(_on_phase_changed)

	# Load the test campaign
	_load_campaign()


func _load_campaign() -> void:
	"""Load the test campaign and show the briefing."""
	var success := GameState.load_campaign(TEST_CAMPAIGN_PATH)
	if not success:
		push_error("Failed to load test campaign!")
		return

	var op: Dictionary = GameState.get_current_operation()
	if op.is_empty():
		push_error("No operations in campaign!")
		return

	_show_briefing(op)


func _show_briefing(op: Dictionary) -> void:
	"""Display the operation briefing screen."""
	briefing_panel.visible = true
	dashboard.visible = false
	debrief.visible = false

	var briefing: Dictionary = op.get("briefing", {})

	briefing_codename.text = "OPERATION: %s" % briefing.get("codename", "UNKNOWN")

	briefing_summary.text = briefing.get("summary", "No summary available.")

	var obj_text := "[b]OBJECTIVES:[/b]\n"
	for obj in briefing.get("objectives", []):
		obj_text += "  • %s\n" % obj
	briefing_objectives.text = obj_text

	var warn_text := ""
	var warnings: Array = briefing.get("warnings", [])
	if not warnings.is_empty():
		warn_text = "[b]WARNINGS:[/b]\n"
		for w in warnings:
			warn_text += "  ⚠ %s\n" % w
	briefing_warnings.text = warn_text

	var handler_notes: String = briefing.get("handler_notes", "")
	if handler_notes:
		briefing_handler.text = "[i]Handler: %s[/i]" % handler_notes
	else:
		briefing_handler.text = ""

	GameState.set_phase("briefing")


func _on_start_pressed() -> void:
	"""Player starts the operation — transition to SIGNAL phase."""
	briefing_panel.visible = false
	dashboard.visible = true

	var op: Dictionary = GameState.get_current_operation()
	dashboard.load_operation(op)


func _on_phase_changed(new_phase: String) -> void:
	match new_phase:
		"debrief":
			# Debrief handles itself via EventBus.blacksite_ended
			pass


func _on_debrief_complete(_result: Dictionary) -> void:
	"""Debrief is done — for now, just show a completion message."""
	# In full game: advance to next op, show campaign map, etc.
	# For MVP: show a simple "Operation Complete" and option to replay
	briefing_panel.visible = true
	dashboard.visible = false
	debrief.visible = false

	briefing_codename.text = "OPERATION COMPLETE"
	briefing_summary.text = "The intelligence has been secured. Stand by for next assignment."
	briefing_objectives.text = ""
	briefing_warnings.text = ""
	briefing_handler.text = "[i]Good work, analyst. We'll be in touch.[/i]"
	start_button.text = "REPLAY"
