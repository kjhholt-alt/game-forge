## Skill system — manages the 5 analyst skill trees.
##
## Wraps GameState.analyst.skills with gameplay effects.
## Skills affect what the player can see (SIGNAL) and do (BLACKSITE).
extends Node


## Skill descriptions for UI
const SKILL_INFO := {
	"sigint": {
		"name": "SIGINT",
		"description": "Signals Intelligence — intercepting and analyzing communications.",
		"signal_effect": "Cleaner intercepts, less redaction",
		"blacksite_effect": "Passive network monitoring alerts",
	},
	"humint": {
		"name": "HUMINT",
		"description": "Human Intelligence — understanding and leveraging people.",
		"signal_effect": "More employee profile detail, relationship hints",
		"blacksite_effect": "More dialogue options in social engineering",
	},
	"cryptography": {
		"name": "Cryptography",
		"description": "Breaking codes and encrypting communications.",
		"signal_effect": "Can read encrypted intercepts, spot cipher patterns",
		"blacksite_effect": "Decrypt command, faster decryption",
	},
	"social_engineering": {
		"name": "Social Engineering",
		"description": "Manipulating people into revealing information.",
		"signal_effect": "NPC vulnerability hints in profiles",
		"blacksite_effect": "Lower trust thresholds, spoof command",
	},
	"network_exploitation": {
		"name": "Network Exploitation",
		"description": "Hacking networks and exploiting vulnerabilities.",
		"signal_effect": "Network topology hints in intercepts",
		"blacksite_effect": "More terminal commands, lower detection per action",
	},
}


func get_redaction_reduction(sigint_level: int) -> int:
	"""How much redaction is removed based on SIGINT skill.

	Returns the number of redaction levels to remove (0-2).
	"""
	if sigint_level >= 4:
		return 2
	elif sigint_level >= 2:
		return 1
	return 0


func get_trust_threshold_modifier(se_level: int) -> int:
	"""How much easier social engineering is based on SE skill.

	Returns a negative modifier to NPC trust thresholds.
	"""
	return -(se_level - 1)  # Level 1=0, Level 2=-1, Level 5=-4


func get_detection_modifier(net_level: int) -> float:
	"""Detection cost multiplier based on Network Exploitation.

	Returns a multiplier (lower = less detection per action).
	"""
	return 1.0 - (net_level - 1) * 0.08  # 8% reduction per level above 1
