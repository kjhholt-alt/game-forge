## Debrief screen — post-operation summary and grade.
##
## Shows what was exfiltrated, detection level, performance grade,
## XP gained, and conspiracy nodes revealed.
extends Control


@onready var grade_label: Label = $VBox/GradeSection/GradeLabel
@onready var codename_label: Label = $VBox/Header/CodenameLabel
@onready var status_label: Label = $VBox/Header/StatusLabel
@onready var summary_text: RichTextLabel = $VBox/SummaryText
@onready var stats_container: VBoxContainer = $VBox/StatsContainer
@onready var continue_button: Button = $VBox/ContinueButton


func _ready() -> void:
	EventBus.blacksite_ended.connect(_on_blacksite_ended)
	continue_button.pressed.connect(_on_continue)
	visible = false


func _on_blacksite_ended(success: bool, burned: bool) -> void:
	visible = true
	_build_debrief(success, burned)


func _build_debrief(success: bool, burned: bool) -> void:
	"""Build the debrief screen from operation results."""
	var op: Dictionary = GameState.get_current_operation()
	var briefing: Dictionary = op.get("briefing", {})

	codename_label.text = briefing.get("codename", "UNKNOWN")

	# Determine grade
	var grade: String
	var grade_color: Color

	if burned:
		grade = "BURNED"
		grade_color = Color(0.9, 0.1, 0.1)
		status_label.text = "MISSION FAILED — ANALYST COMPROMISED"
	elif not success:
		grade = "COMPROMISED"
		grade_color = Color(0.9, 0.5, 0.2)
		status_label.text = "MISSION INCOMPLETE — TARGET DATA NOT ACQUIRED"
	elif OpState.detection_value < 0.1:
		grade = "SHADOW"
		grade_color = Color(0.3, 0.9, 0.5)
		status_label.text = "MISSION COMPLETE — ZERO FOOTPRINT"
	elif OpState.detection_value < 0.25:
		grade = "GHOST"
		grade_color = Color(0.2, 0.8, 0.4)
		status_label.text = "MISSION COMPLETE — MINIMAL TRACE"
	else:
		grade = "OPERATIVE"
		grade_color = Color(0.9, 0.7, 0.2)
		status_label.text = "MISSION COMPLETE — SOME DETECTION"

	grade_label.text = grade
	grade_label.add_theme_color_override("font_color", grade_color)

	# Build summary
	var summary := ""
	summary += "[b]Prep Score:[/b] %.0f%%\n" % (OpState.prep_score * 100)
	summary += "[b]Detection Peak:[/b] %s (%.0f%%)\n" % [OpState.detection_level.to_upper(), OpState.detection_value * 100]
	summary += "[b]Files Exfiltrated:[/b] %d\n" % OpState.exfiltrated_files.size()
	summary += "[b]Hosts Compromised:[/b] %d\n" % OpState.discovered_hosts.size()

	summary_text.text = summary

	# Stats
	for child in stats_container.get_children():
		child.queue_free()

	# Files exfiltrated
	if not OpState.exfiltrated_files.is_empty():
		var files_label := Label.new()
		files_label.text = "Exfiltrated:"
		stats_container.add_child(files_label)
		for f in OpState.exfiltrated_files:
			var fl := Label.new()
			fl.text = "  • %s" % f
			fl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
			stats_container.add_child(fl)

	# Continue button
	if burned:
		continue_button.text = "NEW ANALYST"
	else:
		continue_button.text = "CONTINUE"


func _on_continue() -> void:
	visible = false
	EventBus.debrief_complete.emit({
		"grade": grade_label.text,
		"exfiltrated": OpState.exfiltrated_files,
		"detection": OpState.detection_value,
		"prep_score": OpState.prep_score,
	})
