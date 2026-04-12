extends Control
## Quest tracker. Reads quest state from GameState, displays objectives.
## Shows active quests in a sidebar with expandable details.

# -----------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------

signal quest_selected(quest_id: String)

# -----------------------------------------------------------------------
# UI references
# -----------------------------------------------------------------------

var _panel: PanelContainer
var _title_label: Label
var _quest_list: ItemList
var _detail_panel: PanelContainer
var _detail_title: Label
var _detail_desc: RichTextLabel
var _objectives_container: VBoxContainer
var _rewards_label: Label
var _close_button: Button

# -----------------------------------------------------------------------
# State
# -----------------------------------------------------------------------

var _visible_quests: Array[Dictionary] = []
var _selected_index: int = -1

# -----------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------

func _ready() -> void:
	visible = false
	_build_ui()
	GameState.quest_updated.connect(_on_quest_updated)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.05
	_panel.anchor_right = 0.95
	_panel.anchor_top = 0.05
	_panel.anchor_bottom = 0.95
	add_child(_panel)

	var main_vbox := VBoxContainer.new()
	_panel.add_child(main_vbox)

	# Header
	var header := HBoxContainer.new()
	main_vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Quest Journal"
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.pressed.connect(func(): visible = false)
	header.add_child(_close_button)

	# Content
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content)

	# Quest list (left)
	_quest_list = ItemList.new()
	_quest_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_list.size_flags_stretch_ratio = 0.4
	_quest_list.item_selected.connect(_on_quest_selected)
	content.add_child(_quest_list)

	# Detail panel (right)
	_detail_panel = PanelContainer.new()
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_panel.size_flags_stretch_ratio = 0.6
	content.add_child(_detail_panel)

	var detail_vbox := VBoxContainer.new()
	_detail_panel.add_child(detail_vbox)

	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 20)
	detail_vbox.add_child(_detail_title)

	_detail_desc = RichTextLabel.new()
	_detail_desc.bbcode_enabled = true
	_detail_desc.fit_content = true
	_detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_vbox.add_child(_detail_desc)

	# Objectives
	var obj_label := Label.new()
	obj_label.text = "Objectives:"
	obj_label.add_theme_font_size_override("font_size", 16)
	detail_vbox.add_child(obj_label)

	_objectives_container = VBoxContainer.new()
	detail_vbox.add_child(_objectives_container)

	_rewards_label = Label.new()
	_rewards_label.add_theme_font_size_override("font_size", 14)
	detail_vbox.add_child(_rewards_label)


func _input(event: InputEvent) -> void:
	# Toggle with J key (or could be mapped to a custom input)
	if event is InputEventKey and event.pressed and event.keycode == KEY_J:
		visible = !visible
		if visible:
			refresh_quests()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cancel") and visible:
		visible = false
		get_viewport().set_input_as_handled()

# -----------------------------------------------------------------------
# Display
# -----------------------------------------------------------------------

func refresh_quests() -> void:
	_quest_list.clear()
	_visible_quests.clear()

	# Active quests first, then completed
	var active: Array[Dictionary] = GameState.get_active_quests()
	var completed: Array[Dictionary] = GameState.get_completed_quests()

	for quest in active:
		var title: String = quest.get("title", quest.get("name", "Unknown Quest"))
		var status: String = quest.get("status", "active")
		var prefix: String = "[!] " if status == "ready_to_complete" else "[ ] "
		_quest_list.add_item(prefix + title)
		var idx: int = _quest_list.item_count - 1
		if status == "ready_to_complete":
			_quest_list.set_item_custom_fg_color(idx, Color(1.0, 0.9, 0.2))
		_visible_quests.append(quest)

	for quest in completed:
		var title: String = quest.get("title", quest.get("name", "Unknown Quest"))
		_quest_list.add_item("[X] " + title)
		var idx: int = _quest_list.item_count - 1
		_quest_list.set_item_custom_fg_color(idx, Color(0.5, 0.5, 0.5))
		_visible_quests.append(quest)


func _on_quest_selected(index: int) -> void:
	_selected_index = index
	if index < 0 or index >= _visible_quests.size():
		return
	var quest: Dictionary = _visible_quests[index]
	_update_objective_display(quest)
	quest_selected.emit(quest.get("id", ""))


func _update_objective_display(quest_data: Dictionary) -> void:
	_detail_title.text = quest_data.get("title", quest_data.get("name", "Unknown"))
	_detail_desc.text = quest_data.get("description", "No description.")

	# Clear old objectives
	for child in _objectives_container.get_children():
		child.queue_free()

	# Build objective checklist
	var objectives: Array = quest_data.get("objectives", [])
	for obj in objectives:
		if obj is Dictionary:
			var check := CheckBox.new()
			var desc: String = obj.get("description", "???")
			var completed: bool = obj.get("completed", false)
			var optional: bool = obj.get("optional", false)

			var current: int = obj.get("current_count", 0)
			var total: int = obj.get("count", 1)
			if total > 1:
				desc += " (%d/%d)" % [current, total]
			if optional:
				desc += " [Optional]"

			check.text = desc
			check.button_pressed = completed
			check.disabled = true
			if completed:
				check.modulate = Color(0.5, 1.0, 0.5)
			_objectives_container.add_child(check)

	# Rewards
	var rewards: Dictionary = quest_data.get("rewards", {})
	var reward_parts: PackedStringArray = []
	if rewards.has("xp") and rewards["xp"] > 0:
		reward_parts.append("%d XP" % rewards["xp"])
	if rewards.has("gold") and rewards["gold"] > 0:
		reward_parts.append("%d Gold" % rewards["gold"])
	if rewards.has("items"):
		for item in rewards["items"]:
			if item is String:
				reward_parts.append(item)
			elif item is Dictionary:
				reward_parts.append(item.get("name", "Item"))

	if reward_parts.size() > 0:
		_rewards_label.text = "Rewards: " + ", ".join(reward_parts)
	else:
		_rewards_label.text = ""


func _on_quest_updated(_quest_id: String) -> void:
	if visible:
		refresh_quests()
