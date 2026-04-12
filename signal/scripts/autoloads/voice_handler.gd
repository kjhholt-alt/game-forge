## Voice handler — speaks handler dialogue via Godot native TTS.
##
## Queues lines and speaks them in order. No reading required.
## Uses DisplayServer.tts_speak() for zero-cost, zero-latency voice.
extends Node


var _queue: Array[Dictionary] = []  # [{text, priority}]
var _speaking := false
var _voice_id: String = ""
var _enabled := true

## Subtitle display (optional, toggled by player)
var subtitle_enabled := true


func _ready() -> void:
	# Pick a voice — prefer a deeper/male voice for the handler feel
	var voices := DisplayServer.tts_get_voices()
	for v in voices:
		var name_lower: String = v.get("name", "").to_lower()
		# Prefer: David, Mark, Daniel, or any male-sounding English voice
		if "david" in name_lower or "mark" in name_lower or "daniel" in name_lower:
			_voice_id = v.get("id", "")
			break
	# Fallback to first English voice
	if _voice_id.is_empty() and voices.size() > 0:
		for v in voices:
			var lang: String = v.get("language", "")
			if lang.begins_with("en"):
				_voice_id = v.get("id", "")
				break
	# Last resort: any voice
	if _voice_id.is_empty() and voices.size() > 0:
		_voice_id = voices[0].get("id", "")

	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_speech_done)
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, _on_speech_done)


func speak(text: String, priority: String = "normal") -> void:
	if not _enabled or text.is_empty():
		return

	_queue.append({"text": text, "priority": priority})

	if subtitle_enabled:
		EventBus.handler_subtitle.emit(text)

	if not _speaking:
		_speak_next()


func speak_now(text: String, priority: String = "critical") -> void:
	## Interrupts current speech for urgent messages
	DisplayServer.tts_stop()
	_speaking = false
	_queue.push_front({"text": text, "priority": priority})

	if subtitle_enabled:
		EventBus.handler_subtitle.emit(text)

	_speak_next()


func stop() -> void:
	DisplayServer.tts_stop()
	_queue.clear()
	_speaking = false


func _speak_next() -> void:
	if _queue.is_empty():
		_speaking = false
		EventBus.handler_subtitle.emit("")
		return

	_speaking = true
	var entry: Dictionary = _queue.pop_front()
	var text: String = entry.get("text", "")

	# Speak via native TTS
	DisplayServer.tts_speak(text, _voice_id, 60, 1.0, 1.1)  # volume, pitch, rate


func _on_speech_done(_utterance_id: int) -> void:
	_speaking = false
	# Small pause between lines
	await get_tree().create_timer(0.3).timeout
	_speak_next()
