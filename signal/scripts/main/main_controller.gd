## Main controller — bootstraps the game and manages top-level flow.
##
## Loads the test campaign, presents the briefing, then hands off
## to the dashboard for SIGNAL -> BLACKSITE -> Debrief.
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

# Screen flash overlay for detection events
var _flash_rect: ColorRect = null

const TEST_CAMPAIGN_PATH := "res://data/test_campaign.json"


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	EventBus.debrief_complete.connect(_on_debrief_complete)
	EventBus.phase_changed.connect(_on_phase_changed)
	EventBus.detection_changed.connect(_on_detection_flash)
	EventBus.analyst_burned.connect(_on_burn_flash)

	# Create screen flash overlay (always on top)
	_flash_rect = ColorRect.new()
	_flash_rect.anchors_preset = Control.PRESET_FULL_RECT
	_flash_rect.color = Color(0, 0, 0, 0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)
	move_child(_flash_rect, get_child_count() - 1)

	# Hide everything until boot completes
	briefing_panel.visible = false
	dashboard.visible = false

	var boot := get_node_or_null("BootSequence")
	if boot:
		boot.boot_complete.connect(func():
			_load_campaign()
		)
	else:
		_load_campaign()


func _input(event: InputEvent) -> void:
	# Escape key — close SE chat if open, or disconnect terminal
	if event.is_action_pressed("ui_cancel"):
		if GameState.current_phase == "blacksite":
			if $SEChat.visible:
				$SEChat.visible = false
			elif OpState.connected_host_id != "":
				OpState.connected_host_id = ""

	# Enter key on briefing screen
	if event.is_action_pressed("ui_accept") and briefing_panel.visible:
		_on_start_pressed()


func _load_campaign() -> void:
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
	briefing_panel.visible = true
	dashboard.visible = false
	debrief.visible = false

	var briefing: Dictionary = op.get("briefing", {})

	briefing_codename.text = "OPERATION: %s" % briefing.get("codename", "UNKNOWN")

	briefing_summary.text = briefing.get("summary", "No summary available.")

	var obj_text := "[b][color=#6699cc]OBJECTIVES:[/color][/b]\n"
	for obj in briefing.get("objectives", []):
		obj_text += "  [color=#aabbcc]>[/color] %s\n" % obj
	briefing_objectives.text = obj_text

	var warn_text := ""
	var warnings: Array = briefing.get("warnings", [])
	if not warnings.is_empty():
		warn_text = "[b][color=#cc8844]WARNINGS:[/color][/b]\n"
		for w in warnings:
			warn_text += "  [color=#cc8844]![/color] %s\n" % w
	briefing_warnings.text = warn_text

	var handler_notes: String = briefing.get("handler_notes", "")
	if handler_notes:
		briefing_handler.text = "[color=#667788][i]HANDLER: %s[/i][/color]" % handler_notes
	else:
		briefing_handler.text = ""

	GameState.set_phase("briefing")


func _on_start_pressed() -> void:
	briefing_panel.visible = false
	dashboard.visible = true

	var op: Dictionary = GameState.get_current_operation()
	dashboard.load_operation(op)


func _on_phase_changed(new_phase: String) -> void:
	match new_phase:
		"debrief":
			pass


func _on_debrief_complete(_result: Dictionary) -> void:
	briefing_panel.visible = true
	dashboard.visible = false
	debrief.visible = false

	briefing_codename.text = "OPERATION COMPLETE"
	briefing_summary.text = "[color=#88cc88]The intelligence has been secured.[/color]\n\nStand by for next assignment."
	briefing_objectives.text = ""
	briefing_warnings.text = ""
	briefing_handler.text = "[color=#667788][i]Good work, analyst. We'll be in touch.[/i][/color]"
	start_button.text = "REPLAY"


# ---------------------------------------------------------------------------
# Visual feedback
# ---------------------------------------------------------------------------

func _on_detection_flash(level: String, _value: float) -> void:
	match level:
		"yellow":
			_screen_flash(Color(0.9, 0.7, 0.1, 0.08), 0.4)
		"red":
			_screen_flash(Color(0.9, 0.2, 0.1, 0.12), 0.6)
		"black":
			_screen_flash(Color(0.9, 0.05, 0.05, 0.2), 1.0)


func _on_burn_flash() -> void:
	_screen_flash(Color(0.9, 0.0, 0.0, 0.3), 1.5)


func _screen_flash(color: Color, duration: float) -> void:
	if not _flash_rect:
		return
	_flash_rect.color = color
	var tween := create_tween()
	tween.tween_property(_flash_rect, "color:a", 0.0, duration).set_ease(Tween.EASE_OUT)
