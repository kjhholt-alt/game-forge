extends Control
## Inventory UI and management. Renders items from GameState.inventory.
## Provides item selection, usage, equipping, and dropping.

# -----------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------

signal item_selected(item_data: Dictionary)
signal item_action_taken(action: String, item_data: Dictionary)

# -----------------------------------------------------------------------
# UI references
# -----------------------------------------------------------------------

var _panel: PanelContainer
var _title_label: Label
var _item_list: ItemList
var _detail_panel: PanelContainer
var _detail_name: Label
var _detail_desc: RichTextLabel
var _detail_stats: Label
var _action_container: HBoxContainer
var _use_button: Button
var _equip_button: Button
var _drop_button: Button
var _close_button: Button
var _gold_label: Label

# -----------------------------------------------------------------------
# State
# -----------------------------------------------------------------------

var _selected_index: int = -1
var _visible_items: Array[Dictionary] = []

# -----------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------

func _ready() -> void:
	visible = false
	_build_ui()
	GameState.inventory_changed.connect(refresh_display)


func _build_ui() -> void:
	# Main panel
	_panel = PanelContainer.new()
	_panel.name = "InventoryPanel"
	_panel.anchor_left = 0.1
	_panel.anchor_right = 0.9
	_panel.anchor_top = 0.05
	_panel.anchor_bottom = 0.95
	add_child(_panel)

	var main_vbox := VBoxContainer.new()
	_panel.add_child(main_vbox)

	# Header
	var header := HBoxContainer.new()
	main_vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Inventory"
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_gold_label = Label.new()
	_gold_label.text = "Gold: 0"
	_gold_label.add_theme_font_size_override("font_size", 18)
	header.add_child(_gold_label)

	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.pressed.connect(_on_close_pressed)
	header.add_child(_close_button)

	# Content split
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content)

	# Item list (left)
	_item_list = ItemList.new()
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_list.size_flags_stretch_ratio = 0.6
	_item_list.item_selected.connect(_on_item_selected)
	content.add_child(_item_list)

	# Detail panel (right)
	_detail_panel = PanelContainer.new()
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_panel.size_flags_stretch_ratio = 0.4
	content.add_child(_detail_panel)

	var detail_vbox := VBoxContainer.new()
	_detail_panel.add_child(detail_vbox)

	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 20)
	detail_vbox.add_child(_detail_name)

	_detail_desc = RichTextLabel.new()
	_detail_desc.bbcode_enabled = true
	_detail_desc.fit_content = true
	_detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_vbox.add_child(_detail_desc)

	_detail_stats = Label.new()
	detail_vbox.add_child(_detail_stats)

	# Action buttons
	_action_container = HBoxContainer.new()
	detail_vbox.add_child(_action_container)

	_use_button = Button.new()
	_use_button.text = "Use"
	_use_button.pressed.connect(_on_use_pressed)
	_action_container.add_child(_use_button)

	_equip_button = Button.new()
	_equip_button.text = "Equip"
	_equip_button.pressed.connect(_on_equip_pressed)
	_action_container.add_child(_equip_button)

	_drop_button = Button.new()
	_drop_button.text = "Drop"
	_drop_button.pressed.connect(_on_drop_pressed)
	_action_container.add_child(_drop_button)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		visible = !visible
		if visible:
			refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cancel") and visible:
		visible = false
		get_viewport().set_input_as_handled()

# -----------------------------------------------------------------------
# Display
# -----------------------------------------------------------------------

func refresh_display() -> void:
	_item_list.clear()
	_visible_items.clear()
	_gold_label.text = "Gold: %d" % GameState.gold

	for item in GameState.inventory:
		var display_name: String = item.get("name", "Unknown")
		var count: int = item.get("count", 1)
		if count > 1:
			display_name += " (x%d)" % count
		var rarity: String = item.get("rarity", "common")
		_item_list.add_item(display_name)

		# Color by rarity
		var idx: int = _item_list.item_count - 1
		match rarity:
			"uncommon":
				_item_list.set_item_custom_fg_color(idx, Color(0.2, 0.8, 0.2))
			"rare":
				_item_list.set_item_custom_fg_color(idx, Color(0.3, 0.5, 1.0))
			"epic":
				_item_list.set_item_custom_fg_color(idx, Color(0.7, 0.3, 0.9))
			"legendary":
				_item_list.set_item_custom_fg_color(idx, Color(1.0, 0.7, 0.0))

		_visible_items.append(item)

	# Clear detail if selection is gone
	if _selected_index >= _visible_items.size():
		_selected_index = -1
		_clear_detail()

# -----------------------------------------------------------------------
# Selection and actions
# -----------------------------------------------------------------------

func _on_item_selected(index: int) -> void:
	_selected_index = index
	if index < 0 or index >= _visible_items.size():
		_clear_detail()
		return
	var item: Dictionary = _visible_items[index]
	_show_detail(item)
	item_selected.emit(item)


func _show_detail(item_data: Dictionary) -> void:
	_detail_name.text = item_data.get("name", "Unknown")
	_detail_desc.text = item_data.get("description", "No description.")

	# Stats
	var stats: Dictionary = item_data.get("stats", {})
	var stat_lines: PackedStringArray = []
	for key in stats:
		var val = stats[key]
		if val > 0:
			stat_lines.append("%s: +%d" % [key.capitalize(), val])
		elif val < 0:
			stat_lines.append("%s: %d" % [key.capitalize(), val])
	_detail_stats.text = "\n".join(stat_lines) if stat_lines.size() > 0 else ""

	# Show/hide action buttons based on item type
	var item_type: String = item_data.get("item_type", item_data.get("type", ""))
	_use_button.visible = item_type == "consumable"
	_equip_button.visible = item_type in ["weapon", "armor", "accessory"]
	_drop_button.visible = item_type != "key_item"


func _clear_detail() -> void:
	_detail_name.text = ""
	_detail_desc.text = ""
	_detail_stats.text = ""
	_use_button.visible = false
	_equip_button.visible = false
	_drop_button.visible = false


func use_item(item_data: Dictionary) -> void:
	var effects: Array = item_data.get("effects", [])
	for effect in effects:
		if effect is String:
			match effect:
				"heal_small":
					GameState.modify_stat("hp", 20)
				"heal_medium":
					GameState.modify_stat("hp", 50)
				"heal_large":
					GameState.modify_stat("hp", 100)
				"mana_small":
					GameState.modify_stat("mp", 15)
				"mana_medium":
					GameState.modify_stat("mp", 35)
				"mana_large":
					GameState.modify_stat("mp", 75)
				_:
					# Generic effect application via flags
					GameState.set_flag("item_effect_" + effect, true)
	GameState.remove_item(item_data.get("id", ""), 1)
	EventBus.item_used.emit(item_data)
	EventBus.notification.emit("Used %s" % item_data.get("name", "item"), "info")
	item_action_taken.emit("use", item_data)
	refresh_display()


func equip_item(item_data: Dictionary) -> void:
	var item_type: String = item_data.get("item_type", item_data.get("type", ""))
	var slot: String = ""
	match item_type:
		"weapon":
			slot = "weapon"
		"armor":
			slot = "armor"
		"accessory":
			slot = "accessory"
		_:
			EventBus.notification.emit("Cannot equip this item", "warning")
			return
	GameState.equip_item(slot, item_data)
	EventBus.notification.emit("Equipped %s" % item_data.get("name", "item"), "info")
	item_action_taken.emit("equip", item_data)
	refresh_display()


func drop_item(item_data: Dictionary) -> void:
	GameState.remove_item(item_data.get("id", ""), 1)
	EventBus.notification.emit("Dropped %s" % item_data.get("name", "item"), "info")
	item_action_taken.emit("drop", item_data)
	refresh_display()

# -----------------------------------------------------------------------
# Button callbacks
# -----------------------------------------------------------------------

func _on_use_pressed() -> void:
	if _selected_index >= 0 and _selected_index < _visible_items.size():
		use_item(_visible_items[_selected_index])


func _on_equip_pressed() -> void:
	if _selected_index >= 0 and _selected_index < _visible_items.size():
		equip_item(_visible_items[_selected_index])


func _on_drop_pressed() -> void:
	if _selected_index >= 0 and _selected_index < _visible_items.size():
		drop_item(_visible_items[_selected_index])


func _on_close_pressed() -> void:
	visible = false
