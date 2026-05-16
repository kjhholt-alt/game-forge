extends RefCounted

var completed_quests: Dictionary = {}
var collected_items: Dictionary = {}

func complete_quest(quest_id: String) -> void:
	completed_quests[quest_id] = true

func collect_item(item_id: String) -> void:
	collected_items[item_id] = collected_items.get(item_id, 0) + 1

func completion_summary(total_quests: int, total_items: int) -> String:
	return "%d/%d quests, %d/%d items" % [
		completed_quests.size(),
		total_quests,
		collected_items.size(),
		total_items,
	]
