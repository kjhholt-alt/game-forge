extends CanvasLayer
## Dialogue system. Receives DialogueTree data (from Python schemas) and runs it.
## Displays speaker text and branching player choices.

# -----------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------

signal dialogue_finished(npc_id: String, choices_made: Array)

# -----------------------------------------------------------------------
# State
# -----------------------------------------------------------------------

var current_tree: Dictionary = {}
var current_node_id: String = ""
var choices_made: Array = []
var is_active: bool = false
var _npc_id: String = ""

# -----------------------------------------------------------------------
# UI references (created dynamically)
# -----------------------------------------------------------------------

var _panel: PanelContainer
var _speaker_label: Label
var _text_label: RichTextLabel
var _options_container: VBoxContainer
var _advance_timer: Timer

# -----------------------------------------------------------------------
# Settings
# -----------------------------------------------------------------------

const TEXT_SPEED := 30.0  # Characters per second for typewriter effect
const AUTO_ADVANCE_DELAY := 0.5  # Seconds to wait before allowing advance

var _displayed_chars: int = 0
var _full_text: String = ""
var _is_typing: bool = false

# -----------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------

func _ready() -> void:
	layer = 100
	visible = false
	_build_ui()


func _build_ui() -> void:
	# Create the dialogue panel at the bottom of the screen
	_panel = PanelContainer.new()
	_panel.name = "DialoguePanel"
	_panel.anchor_left = 0.1
	_panel.anchor_right = 0.9
	_panel.anchor_top = 0.7
	_panel.anchor_bottom = 0.95
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	_panel.add_child(vbox)

	# Speaker name
	_speaker_label = Label.new()
	_speaker_label.name = "SpeakerLabel"
	_speaker_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_speaker_label)

	# Dialogue text
	_text_label = RichTextLabel.new()
	_text_label.name = "TextLabel"
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_text_label)

	# Options container
	_options_container = VBoxContainer.new()
	_options_container.name = "OptionsContainer"
	vbox.add_child(_options_container)

	# Advance timer
	_advance_timer = Timer.new()
	_advance_timer.name = "AdvanceTimer"
	_advance_timer.one_shot = true
	_advance_timer.wait_time = AUTO_ADVANCE_DELAY
	add_child(_advance_timer)


func _input(event: InputEvent) -> void:
	if not is_active:
		return

	if event.is_action_pressed("interact") or event.is_action_pressed("cancel"):
		if _is_typing:
			# Skip typewriter, show full text
			_displayed_chars = _full_text.length()
			_text_label.text = _full_text
			_is_typing = false
		elif _options_container.get_child_count() == 0:
			# No choices — advance to next node or end
			var node: Dictionary = _get_current_node()
			var auto_next: String = node.get("auto_next", "")
			if not auto_next.is_empty():
				_show_node(auto_next)
			else:
				_end_dialogue()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _is_typing:
		_displayed_chars += int(TEXT_SPEED * delta)
		if _displayed_chars >= _full_text.length():
			_displayed_chars = _full_text.length()
			_is_typing = false
		_text_label.visible_characters = _displayed_chars

# -----------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------

func start_dialogue(tree_data: Dictionary) -> void:
	## tree_data matches schemas.quest.DialogueTree JSON structure:
	## {id, npc_id, context, root_node_id, nodes: [{id, speaker, text, emotion, options, auto_next}]}
	current_tree = tree_data
	_npc_id = tree_data.get("npc_id", "unknown")
	choices_made = []
	is_active = true
	visible = true

	var root_id: String = tree_data.get("root_node_id", "")
	if root_id.is_empty() and tree_data.get("nodes", []).size() > 0:
		root_id = tree_data["nodes"][0].get("id", "")

	EventBus.dialogue_started.emit(_npc_id)
	_show_node(root_id)

# -----------------------------------------------------------------------
# Internal
# -----------------------------------------------------------------------

func _show_node(node_id: String) -> void:
	current_node_id = node_id
	var node: Dictionary = _get_current_node()

	if node.is_empty():
		push_warning("Dialogue node not found: " + node_id)
		_end_dialogue()
		return

	# Set speaker
	var speaker: String = node.get("speaker", "???")
	_speaker_label.text = speaker

	# Set text with typewriter effect
	_full_text = node.get("text", "")
	_text_label.text = _full_text
	_text_label.visible_characters = 0
	_displayed_chars = 0
	_is_typing = true

	# Clear old options
	for child in _options_container.get_children():
		child.queue_free()

	# Add options (if any)
	var options: Array = node.get("options", [])
	if options.size() > 0:
		for i in range(options.size()):
			var option: Dictionary = options[i]
			# Check conditions
			if not _check_conditions(option.get("conditions", {})):
				continue
			var btn := Button.new()
			btn.text = "%d. %s" % [i + 1, option.get("text", "...")]
			btn.pressed.connect(_on_option_selected.bind(i))
			_options_container.add_child(btn)


func _on_option_selected(option_index: int) -> void:
	var node: Dictionary = _get_current_node()
	var options: Array = node.get("options", [])

	if option_index < 0 or option_index >= options.size():
		_end_dialogue()
		return

	var option: Dictionary = options[option_index]
	choices_made.append({
		"node_id": current_node_id,
		"option_index": option_index,
		"option_text": option.get("text", ""),
	})

	# Apply effects
	_apply_effects(option.get("effects", {}))

	# Navigate to next node
	var next_id: String = option.get("next_node_id", "")
	if next_id.is_empty():
		_end_dialogue()
	else:
		_show_node(next_id)


func _end_dialogue() -> void:
	is_active = false
	visible = false
	current_tree = {}
	current_node_id = ""
	EventBus.dialogue_ended.emit(_npc_id)
	dialogue_finished.emit(_npc_id, choices_made)


func _get_current_node() -> Dictionary:
	var nodes: Array = current_tree.get("nodes", [])
	for node in nodes:
		if node is Dictionary and node.get("id", "") == current_node_id:
			return node
	return {}


func _check_conditions(conditions: Dictionary) -> bool:
	## Check whether all conditions are met (flags, stats, items).
	for key in conditions:
		var required = conditions[key]
		# Check flags
		if key.begins_with("flag_"):
			var flag_name: String = key.substr(5)
			if GameState.get_flag(flag_name) != required:
				return false
		# Check stats
		elif key.begins_with("stat_"):
			var stat_name: String = key.substr(5)
			if GameState.player_stats.get(stat_name, 0) < required:
				return false
		# Check items
		elif key.begins_with("has_item_"):
			var item_id: String = key.substr(9)
			if not GameState.has_item(item_id):
				return false
	return true


func _apply_effects(effects: Dictionary) -> void:
	## Apply dialogue effects: set flags, give items, modify stats/relationships.
	for key in effects:
		var value = effects[key]
		if key.begins_with("flag_"):
			GameState.set_flag(key.substr(5), value)
		elif key.begins_with("give_item_"):
			var item_id: String = key.substr(10)
			GameState.add_item({"id": item_id, "name": str(value), "count": 1})
		elif key.begins_with("stat_"):
			var stat_name: String = key.substr(5)
			GameState.modify_stat(stat_name, value)
		elif key.begins_with("gold"):
			GameState.gold += value
		elif key.begins_with("relationship_"):
			# relationship_npc_id_stat format
			var parts: PackedStringArray = key.substr(13).rsplit("_", true, 1)
			if parts.size() == 2:
				GameState.modify_relationship(parts[0], parts[1], value)
