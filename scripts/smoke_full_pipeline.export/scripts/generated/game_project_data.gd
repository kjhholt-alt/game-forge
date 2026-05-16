extends Node

const PROJECT_PATH := "res://game_project.json"

static func load_project() -> Dictionary:
	if not FileAccess.file_exists(PROJECT_PATH):
		push_warning("Missing GameForge project manifest: " + PROJECT_PATH)
		return {}
	var raw := FileAccess.get_file_as_string(PROJECT_PATH)
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("GameForge project manifest is not a Dictionary")
		return {}
	return parsed
