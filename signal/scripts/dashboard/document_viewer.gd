## Document viewer — displays the full text of selected evidence items.
##
## Right-side panel that shows intercepted content when the player
## clicks an evidence node on the board.
extends Control


@onready var title_label: Label = $VBox/TitleBar/Title
@onready var classification_label: Label = $VBox/TitleBar/Classification
@onready var type_label: Label = $VBox/TitleBar/Type
@onready var content_text: RichTextLabel = $VBox/Content
@onready var timestamp_label: Label = $VBox/Footer/Timestamp
@onready var source_label: Label = $VBox/Footer/Source


const CLASSIFICATION_COLORS := {
	"unclassified": Color(0.5, 0.5, 0.5),
	"confidential": Color(0.3, 0.5, 0.9),
	"secret": Color(0.9, 0.7, 0.2),
	"top_secret": Color(0.9, 0.2, 0.2),
}


func _ready() -> void:
	EventBus.document_opened.connect(_on_document_opened)
	EventBus.document_closed.connect(_on_document_closed)
	_show_empty_state()


func _on_document_opened(evidence_id: String) -> void:
	var item: Dictionary = OpState.evidence_items.get(evidence_id, {})
	if item.is_empty():
		return

	var ev_type: String = item.get("evidence_type", "document")
	var classification: String = item.get("classification", "confidential")

	title_label.text = item.get("title", "Untitled")
	classification_label.text = "[%s]" % classification.to_upper()
	classification_label.add_theme_color_override(
		"font_color",
		CLASSIFICATION_COLORS.get(classification, Color.GRAY),
	)
	type_label.text = ev_type.replace("_", " ").to_upper()

	# Format content based on evidence type
	var content: String = item.get("content", "")
	var redacted_level: int = item.get("redacted_level", 0)

	if redacted_level > 0:
		content = _apply_redaction(content, redacted_level)

	content_text.text = _format_content(content, ev_type)

	timestamp_label.text = item.get("timestamp", "")
	source_label.text = item.get("source", "")


func _on_document_closed() -> void:
	_show_empty_state()


func _show_empty_state() -> void:
	title_label.text = "No Document Selected"
	classification_label.text = ""
	type_label.text = ""
	content_text.text = "[color=#555555]Select an evidence item from the board to view its contents.[/color]"
	timestamp_label.text = ""
	source_label.text = ""


func _format_content(content: String, ev_type: String) -> String:
	match ev_type:
		"email":
			# Highlight email headers
			var lines := content.split("\n")
			var formatted := ""
			for line in lines:
				if line.begins_with("From:") or line.begins_with("To:") or line.begins_with("Subject:") or line.begins_with("Date:") or line.begins_with("RE:") or line.begins_with("CC:"):
					formatted += "[color=#6699cc]%s[/color]\n" % line
				elif line.begins_with("---") or line.begins_with("___"):
					formatted += "[color=#444444]%s[/color]\n" % line
				else:
					formatted += line + "\n"
			return formatted
		"phone_transcript":
			# Highlight speaker labels
			var lines := content.split("\n")
			var formatted := ""
			for line in lines:
				if ":" in line and line.find(":") < 20:
					var colon_pos := line.find(":")
					formatted += "[color=#88cc88]%s[/color]%s\n" % [line.substr(0, colon_pos + 1), line.substr(colon_pos + 1)]
				elif line.begins_with("[") and "]" in line:
					formatted += "[color=#666666]%s[/color]\n" % line
				else:
					formatted += line + "\n"
			return formatted
		"financial_record":
			# Highlight dollar amounts
			return content  # TODO: regex highlight $amounts
		"surveillance_log":
			# Highlight timestamps
			return content  # TODO: regex highlight timestamps
		_:
			return content


func _apply_redaction(content: String, level: int) -> String:
	var words := content.split(" ")
	var redacted_words: Array[String] = []

	# Redact a percentage of words based on level
	var redact_chance := level * 0.15  # 15%/30%/45%

	for word in words:
		if randf() < redact_chance and word.length() > 3:
			redacted_words.append("[color=#333333][█████][/color]")
		else:
			redacted_words.append(word)

	return " ".join(redacted_words)
