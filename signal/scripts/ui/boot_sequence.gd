## Boot sequence — cold-open terminal animation before the briefing.
##
## Plays a series of "system boot" lines that set the atmosphere.
## Fades out when complete, revealing the briefing screen.
extends Control


signal boot_complete


@onready var output: RichTextLabel = $VBox/Output
@onready var cursor_blink: Timer = $CursorBlink

var _lines := [
	{"text": "SIGNAL Intelligence Analysis System v4.2.1", "delay": 0.1, "color": "#33aa55"},
	{"text": "Initializing secure channel...", "delay": 0.4, "color": "#667788"},
	{"text": "[OK] Encryption layer: AES-256-GCM", "delay": 0.15, "color": "#667788"},
	{"text": "[OK] Authentication: CLASSIFIED//NOFORN", "delay": 0.15, "color": "#667788"},
	{"text": "[OK] Satellite uplink: ACTIVE", "delay": 0.15, "color": "#667788"},
	{"text": "[OK] SIGINT feed: CONNECTED", "delay": 0.15, "color": "#667788"},
	{"text": "[OK] Database: OPERATIONAL", "delay": 0.15, "color": "#667788"},
	{"text": "", "delay": 0.3, "color": "#667788"},
	{"text": "Analyst credentials verified.", "delay": 0.5, "color": "#33aa55"},
	{"text": "Codename: %CODENAME%", "delay": 0.2, "color": "#66ccff"},
	{"text": "Clearance: TOP SECRET // SCI // SIGNAL", "delay": 0.2, "color": "#cc8844"},
	{"text": "", "delay": 0.3, "color": "#667788"},
	{"text": "Loading operation briefing...", "delay": 0.8, "color": "#33aa55"},
]

var _current_line := 0
var _cursor_visible := true


func _ready() -> void:
	visible = true
	output.text = ""

	# Cursor blink timer
	cursor_blink.wait_time = 0.5
	cursor_blink.timeout.connect(_toggle_cursor)
	cursor_blink.start()

	_play_boot()


func _play_boot() -> void:
	for i in range(_lines.size()):
		var line: Dictionary = _lines[i]
		var text: String = line["text"]
		var color: String = line["color"]
		var delay: float = line["delay"]

		# Replace placeholders
		text = text.replace("%CODENAME%", GameState.analyst.get("codename", "WRAITH"))

		if text.is_empty():
			output.append_text("\n")
		else:
			output.append_text("[color=%s]%s[/color]\n" % [color, text])

		await get_tree().create_timer(delay).timeout

	# Pause then fade out
	await get_tree().create_timer(0.5).timeout

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		visible = false
		boot_complete.emit()
	)


func _toggle_cursor() -> void:
	# Blinking cursor at the end of output (purely visual)
	_cursor_visible = !_cursor_visible
