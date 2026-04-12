## Detection system — manages the BLACKSITE alert level.
##
## Wraps OpState.detection_value with visual feedback and events.
## The detection meter is the core tension mechanic of BLACKSITE.
extends Node


## Detection level thresholds
const THRESHOLDS := {
	"green": 0.0,
	"yellow": 0.25,
	"red": 0.50,
	"black": 0.75,
}


func _ready() -> void:
	EventBus.terminal_command.connect(_on_terminal_command)


func _on_terminal_command(command: String, _args: Array) -> void:
	"""Some commands passively affect detection even if they succeed."""
	# XP gains for terminal usage
	match command:
		"scan", "probe", "connect", "exploit", "login":
			GameState.add_xp("network_exploitation", 5)
		"decrypt":
			GameState.add_xp("cryptography", 10)


func get_level_description(level: String) -> String:
	"""Get a human-readable description of the detection level."""
	match level:
		"green": return "UNDETECTED — No anomalies flagged."
		"yellow": return "ANOMALY — Automated systems have flagged unusual activity."
		"red": return "INVESTIGATION — Security team is actively investigating."
		"black": return "BURNED — Your identity has been compromised."
	return "UNKNOWN"
