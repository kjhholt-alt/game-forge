extends Control

const Data := preload("res://scripts/generated/game_project_data.gd")
const QuestRuntime := preload("res://scripts/generated/quest_runtime.gd")

var project: Dictionary = {}
var runtime := QuestRuntime.new()
var current_space: int = 0
var log_lines: Array[String] = []

var title_label: Label
var detail_label: RichTextLabel
var space_list: VBoxContainer
var quest_list: VBoxContainer
var inventory_list: VBoxContainer
var npc_list: VBoxContainer
var qa_list: VBoxContainer
var status_label: Label
var log_label: RichTextLabel

func _ready() -> void:
	project = Data.load_project()
	_build_layout()
	_refresh_all()

func _build_layout() -> void:
	var root := HBoxContainer.new()
	root.name = "GameForgeRuntime"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	root.add_child(left)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(center)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(360, 0)
	root.add_child(right)

	title_label = Label.new()
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 28)
	center.add_child(title_label)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(status_label)

	detail_label = RichTextLabel.new()
	detail_label.fit_content = true
	detail_label.bbcode_enabled = false
	detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(detail_label)

	var action_row := HBoxContainer.new()
	center.add_child(action_row)
	_add_button(action_row, "Explore", _on_explore)
	_add_button(action_row, "Solve", _on_solve)
	_add_button(action_row, "Collect", _on_collect)
	_add_button(action_row, "Next Room", _on_next_space)

	log_label = RichTextLabel.new()
	log_label.custom_minimum_size = Vector2(0, 150)
	log_label.fit_content = false
	center.add_child(log_label)

	left.add_child(_section_label("Rooms"))
	space_list = VBoxContainer.new()
	left.add_child(space_list)

	right.add_child(_section_label("Quests"))
	quest_list = VBoxContainer.new()
	right.add_child(quest_list)
	right.add_child(_section_label("Inventory Seeds"))
	inventory_list = VBoxContainer.new()
	right.add_child(inventory_list)
	right.add_child(_section_label("NPCs"))
	npc_list = VBoxContainer.new()
	right.add_child(npc_list)
	right.add_child(_section_label("Still Unfinished"))
	qa_list = VBoxContainer.new()
	right.add_child(qa_list)

func _refresh_all() -> void:
	var concept: Dictionary = project.get("concept", {})
	title_label.text = "%s" % concept.get("title", "Generated Game")
	status_label.text = _status_text()
	_refresh_spaces()
	_refresh_detail()
	_refresh_quests()
	_refresh_items()
	_refresh_npcs()
	_refresh_qa()
	_refresh_log()

func _refresh_spaces() -> void:
	_clear(space_list)
	var spaces: Array = _spaces()
	for i in range(spaces.size()):
		var space: Dictionary = spaces[i]
		var b := Button.new()
		b.text = "%s. %s" % [i + 1, space.get("name", "Room")]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			current_space = i
			_refresh_detail()
		)
		space_list.add_child(b)

func _refresh_detail() -> void:
	var spaces := _spaces()
	var concept: Dictionary = project.get("concept", {})
	if spaces.is_empty():
		detail_label.text = concept.get("setting", "")
		return
	current_space = clamp(current_space, 0, spaces.size() - 1)
	var space: Dictionary = spaces[current_space]
	var text: String = "[%s]\n\n%s\n\nMood: %s\n\nCore loop:\n%s" % [
		space.get("kind", "space"),
		space.get("description", ""),
		concept.get("target_mood", ""),
		_bullets(concept.get("core_mechanics", []), 5),
	]
	detail_label.text = text

func _refresh_quests() -> void:
	_clear(quest_list)
	for quest in project.get("quests", []).slice(0, 5):
		var id := str(quest.get("id", quest.get("title", "quest")))
		var b := Button.new()
		b.text = "%s%s" % [
			"[done] " if runtime.completed_quests.has(id) else "",
			quest.get("title", "Quest"),
		]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			runtime.complete_quest(id)
			_log("Quest advanced: " + str(quest.get("title", id)))
			_refresh_all()
		)
		quest_list.add_child(b)

func _refresh_items() -> void:
	_clear(inventory_list)
	for item in project.get("items", []).slice(0, 5):
		var id := str(item.get("id", item.get("name", "item")))
		var b := Button.new()
		b.text = "%s%s" % [
			"* " if runtime.collected_items.has(id) else "+ ",
			item.get("name", "Item"),
		]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			runtime.collect_item(id)
			_log("Collected: " + str(item.get("name", id)))
			_refresh_all()
		)
		inventory_list.add_child(b)

func _refresh_npcs() -> void:
	_clear(npc_list)
	for npc in project.get("npcs", []).slice(0, 4):
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s - %s" % [npc.get("name", "NPC"), npc.get("role", "")]
		npc_list.add_child(label)

func _refresh_qa() -> void:
	_clear(qa_list)
	var qa: Dictionary = project.get("qa_report", {})
	var issues: Array = qa.get("issues", [])
	if issues.is_empty():
		var ok := Label.new()
		ok.text = "No QA issues captured."
		qa_list.add_child(ok)
		return
	for issue in issues.slice(0, 4):
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "[%s] %s" % [issue.get("severity", "?"), issue.get("description", "")]
		qa_list.add_child(label)

func _refresh_log() -> void:
	log_label.text = "\n".join(log_lines.slice(max(0, log_lines.size() - 6), log_lines.size()))

func _on_explore() -> void:
	var space: Dictionary = _spaces()[current_space]
	_log("Explored " + str(space.get("name", "the room")) + ".")
	_refresh_log()

func _on_solve() -> void:
	var quests: Array = project.get("quests", [])
	var quest_count: int = quests.size()
	if quest_count > 0:
		var quest: Dictionary = quests[runtime.completed_quests.size() % quest_count]
		runtime.complete_quest(str(quest.get("id", quest.get("title", "quest"))))
		_log("Solved a beat for " + str(quest.get("title", "a quest")) + ".")
	_refresh_all()

func _on_collect() -> void:
	var items: Array = project.get("items", [])
	if items.size() > 0:
		var item: Dictionary = items[runtime.collected_items.size() % items.size()]
		runtime.collect_item(str(item.get("id", item.get("name", "item"))))
		_log("Picked up " + str(item.get("name", "an item")) + ".")
	_refresh_all()

func _on_next_space() -> void:
	var spaces: Array = _spaces()
	if spaces.size() == 0:
		return
	current_space = (current_space + 1) % spaces.size()
	_refresh_detail()

func _status_text() -> String:
	return "%s | %s spaces | %s" % [
		project.get("concept", {}).get("genre", "game"),
		_spaces().size(),
		runtime.completion_summary(project.get("quests", []).size(), project.get("items", []).size()),
	]

func _spaces() -> Array:
	var out: Array = []
	var world: Dictionary = project.get("world", {})
	var overworld: Dictionary = world.get("overworld", {})
	for region in overworld.get("regions", []):
		out.append({"name": region.get("name", "Region"), "kind": "region", "description": region.get("description", "")})
		for room in region.get("rooms", []):
			out.append({"name": room.get("name", "Room"), "kind": room.get("room_type", "room"), "description": room.get("description", "")})
	for dungeon in world.get("dungeons", []):
		out.append({"name": dungeon.get("name", "Dungeon"), "kind": "dungeon", "description": dungeon.get("theme", "")})
		for room in dungeon.get("rooms", []):
			out.append({"name": room.get("name", "Room"), "kind": room.get("room_type", "room"), "description": room.get("description", "")})
	if out.is_empty():
		for quest in project.get("quests", []):
			out.append({"name": quest.get("title", "Quest"), "kind": "quest", "description": quest.get("description", "")})
	if out.is_empty():
		out.append({"name": project.get("concept", {}).get("title", "Generated Game"), "kind": "start", "description": project.get("concept", {}).get("setting", "")})
	return out.slice(0, 12)

func _bullets(items: Array, limit: int) -> String:
	var lines: Array[String] = []
	for item in items.slice(0, limit):
		lines.append("* " + str(item))
	return "\n".join(lines)

func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	return label

func _add_button(parent: Node, text: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	parent.add_child(b)

func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

func _log(text: String) -> void:
	log_lines.append(text)
