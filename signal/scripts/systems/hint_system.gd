## Hint system — sends contextual handler nudges when the player is stuck.
##
## Tracks player activity and sends appropriate hints after inactivity.
extends Node


const SIGNAL_HINT_DELAY := 45.0  # seconds of inactivity before hint
const BLACKSITE_HINT_DELAY := 30.0

var _last_activity_time: float = 0.0
var _hints_sent: Dictionary = {}
var _active := false


func _ready() -> void:
	EventBus.phase_changed.connect(_on_phase_changed)
	EventBus.evidence_connected.connect(func(_a, _b, _c): _record_activity())
	EventBus.terminal_command.connect(func(_a, _b): _record_activity())
	EventBus.se_message_sent.connect(func(_a, _b): _record_activity())
	EventBus.document_opened.connect(func(_a): _record_activity())


func _process(delta: float) -> void:
	if not _active:
		return

	var idle_time := Time.get_ticks_msec() / 1000.0 - _last_activity_time

	match GameState.current_phase:
		"signal":
			if idle_time > SIGNAL_HINT_DELAY:
				_send_signal_hint()
		"blacksite":
			if idle_time > BLACKSITE_HINT_DELAY:
				_send_blacksite_hint()


func _record_activity() -> void:
	_last_activity_time = Time.get_ticks_msec() / 1000.0


func _on_phase_changed(phase: String) -> void:
	_record_activity()
	_active = phase in ["signal", "blacksite"]
	_hints_sent.clear()


func _send_signal_hint() -> void:
	var hint_key := ""
	var hint_text := ""

	if OpState.connections.is_empty() and not _hints_sent.has("connect_evidence"):
		hint_key = "connect_evidence"
		hint_text = "Try drawing connections between evidence items. Drag from one node's port to another."
	elif OpState.connections.size() < 3 and not _hints_sent.has("more_connections"):
		hint_key = "more_connections"
		hint_text = "Look for relationships between documents — names, account numbers, dates, organizations."
	elif not _hints_sent.has("go_dark_ready"):
		hint_key = "go_dark_ready"
		hint_text = "When you're ready, hit GO DARK to enter BLACKSITE. More connections = better prep."

	if hint_key and not _hints_sent.has(hint_key):
		_hints_sent[hint_key] = true
		EventBus.handler_hint.emit(hint_text)
		_record_activity()


func _send_blacksite_hint() -> void:
	var hint_key := ""
	var hint_text := ""

	if OpState.discovered_hosts.size() <= 1 and not _hints_sent.has("scan_first"):
		hint_key = "scan_first"
		hint_text = "Start with 'scan' to discover hosts on the network. Check evidence for subnet info."
	elif OpState.connected_host_id.is_empty() and OpState.discovered_hosts.size() > 1 and not _hints_sent.has("try_connect"):
		hint_key = "try_connect"
		hint_text = "Use 'probe' to check for vulnerabilities, then 'exploit' or 'login' to connect."
	elif OpState.exfiltrated_files.is_empty() and not OpState.connected_host_id.is_empty() and not _hints_sent.has("find_files"):
		hint_key = "find_files"
		hint_text = "Use 'ls' to list files, 'cat' to read them, 'download' to exfiltrate target data."
	elif not _hints_sent.has("try_se"):
		hint_key = "try_se"
		hint_text = "Don't forget HUMINT — 'contacts' to see employees, 'talk <name>' to social engineer."

	if hint_key and not _hints_sent.has(hint_key):
		_hints_sent[hint_key] = true
		EventBus.handler_hint.emit(hint_text)
		_record_activity()
