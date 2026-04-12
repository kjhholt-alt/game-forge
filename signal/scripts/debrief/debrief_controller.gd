## Debrief screen — post-operation summary and grade.
##
## Shows mission result, stats, XP breakdown, and exfiltrated intel.
extends Control


@onready var grade_label: Label = $VBox/GradeSection/GradeLabel
@onready var codename_label: Label = $VBox/Header/CodenameLabel
@onready var status_label: Label = $VBox/Header/StatusLabel
@onready var summary_text: RichTextLabel = $VBox/SummaryText
@onready var stats_container: VBoxContainer = $VBox/StatsContainer
@onready var continue_button: Button = $VBox/ContinueButton


const GRADE_CONFIG := {
	"SHADOW": {"color": Color(0.2, 0.9, 0.4), "msg": "ZERO FOOTPRINT — No trace of your presence."},
	"GHOST": {"color": Color(0.3, 0.8, 0.5), "msg": "MINIMAL TRACE — A professional operation."},
	"OPERATIVE": {"color": Color(0.9, 0.7, 0.2), "msg": "MISSION COMPLETE — Some detection occurred."},
	"COMPROMISED": {"color": Color(0.9, 0.4, 0.2), "msg": "INCOMPLETE — Target data not fully acquired."},
	"BURNED": {"color": Color(0.9, 0.1, 0.1), "msg": "ANALYST COMPROMISED — Cover blown."},
}


func _ready() -> void:
	EventBus.blacksite_ended.connect(_on_blacksite_ended)
	continue_button.pressed.connect(_on_continue)
	visible = false


func _on_blacksite_ended(success: bool, burned: bool) -> void:
	visible = true
	_build_debrief(success, burned)


func _build_debrief(success: bool, burned: bool) -> void:
	var op: Dictionary = GameState.get_current_operation()
	var briefing: Dictionary = op.get("briefing", {})

	codename_label.text = briefing.get("codename", "UNKNOWN")

	# Determine grade
	var grade: String
	if burned:
		grade = "BURNED"
	elif not success:
		grade = "COMPROMISED"
	elif OpState.detection_value < 0.1:
		grade = "SHADOW"
	elif OpState.detection_value < 0.25:
		grade = "GHOST"
	else:
		grade = "OPERATIVE"

	var config: Dictionary = GRADE_CONFIG.get(grade, GRADE_CONFIG["OPERATIVE"])
	grade_label.text = grade
	grade_label.add_theme_color_override("font_color", config["color"])
	grade_label.add_theme_font_size_override("font_size", 36)
	status_label.text = config["msg"]
	status_label.add_theme_color_override("font_color", config["color"])

	# Build rich summary
	var summary := ""
	summary += "[color=#667788]OPERATION DEBRIEF[/color]\n"
	summary += "[color=#667788]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n\n"

	# Prep score
	var prep_pct := int(OpState.prep_score * 100)
	var prep_color := "#22dd55" if prep_pct >= 60 else "#ddaa22" if prep_pct >= 30 else "#dd4422"
	summary += "[b]SIGNAL ANALYSIS[/b]  [color=%s]%d%%[/color] prep score\n" % [prep_color, prep_pct]
	summary += "  Evidence connections: %d\n" % OpState.connections.size()
	summary += "\n"

	# Detection
	var det_pct := int(OpState.detection_value * 100)
	var det_color := "#22dd55" if det_pct < 25 else "#ddaa22" if det_pct < 50 else "#dd4422"
	summary += "[b]BLACKSITE[/b]  Peak detection: [color=%s]%d%% (%s)[/color]\n" % [
		det_color, det_pct, OpState.detection_level.to_upper()
	]
	summary += "  Hosts compromised: %d\n" % OpState.discovered_hosts.size()
	summary += "\n"

	# Files exfiltrated
	summary += "[b]EXFILTRATED FILES[/b]\n"
	if OpState.exfiltrated_files.is_empty():
		summary += "  [color=#dd4422](none)[/color]\n"
	else:
		for f in OpState.exfiltrated_files:
			var is_target: bool = f in op.get("required_exfil", [])
			if is_target:
				summary += "  [color=#22dd55]★ %s[/color]  [TARGET]\n" % f
			else:
				summary += "  • %s\n" % f
	summary += "\n"

	# Social engineering
	var se_contacts := 0
	var se_secrets := 0
	for state in OpState.employee_states.values():
		if state.get("trust", 0) > 0:
			se_contacts += 1
		se_secrets += state.get("secrets_revealed", []).size()
	if se_contacts > 0:
		summary += "[b]HUMINT[/b]\n"
		summary += "  Contacts made: %d\n" % se_contacts
		summary += "  Secrets extracted: %d\n" % se_secrets
		summary += "\n"

	summary_text.text = summary

	# Clear and rebuild stats
	for child in stats_container.get_children():
		child.queue_free()

	# Continue button
	if burned:
		continue_button.text = "NEW ANALYST"
	else:
		continue_button.text = "CONTINUE"


func _on_continue() -> void:
	visible = false
	EventBus.debrief_complete.emit({
		"grade": grade_label.text,
		"exfiltrated": OpState.exfiltrated_files.duplicate(),
		"detection": OpState.detection_value,
		"prep_score": OpState.prep_score,
	})
