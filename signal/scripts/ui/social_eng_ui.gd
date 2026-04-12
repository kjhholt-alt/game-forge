## Social engineering chat — modal conversation UI for extracting secrets.
##
## Keyword-based dialogue. Build trust via small talk, extract secrets when
## trust >= threshold. Too much probing raises suspicion (5 = blown).
## Opened via open_chat(employee_id) from the terminal "talk" command.
extends Control

const C_BG := Color(0.035, 0.04, 0.055, 0.98)
const C_BORDER := Color(0.15, 0.2, 0.3)
const C_TRUST := Color(0.2, 0.8, 0.4)
const C_SUSP := Color(0.9, 0.3, 0.2)
const C_SECRET := Color(0.95, 0.8, 0.2)
const C_HDR := Color(0.04, 0.05, 0.07)
const C_TEXT := Color(0.75, 0.8, 0.85)
const C_DIM := Color(0.45, 0.5, 0.58)
const C_PLR := Color(0.4, 0.75, 0.95)
const MW := 700; const MH := 500; const MAX_S := 5

const KW_SM := ["how are you","busy","long day","weather","weekend","thanks",
	"appreciate","good morning","what's up","hey","nice","great","cool","rough day"]
const KW_WK := ["server","network","system","computer","security","database",
	"backup","infrastructure","firewall","software","hardware","deploy","migrate"]
const KW_PR := ["password","credentials","login","access","confidential",
	"secret","mitchell","helios","classified","private","hidden","admin"]
const KW_AG := ["tell me","you must","i need you to","now","immediately",
	"or else","listen","do it","right now","hurry"]

const T := {
	"ct": { # casual tech
		"sm": ["Yeah, it's been crazy. Three tickets already this morning.",
			"Not bad. Just keeping the lights blinking green, y'know?",
			"Weekend? I was patching servers at 2 AM Saturday.",
			"Could be worse. At least the coffee machine works today."],
		"wk": ["Oh that? Yeah, %s. Just migrated it last week.",
			"Sure -- %s. Pretty standard config.",
			"Mm-hm, %s. Been meaning to document that better.",
			"Yeah I set that up. %s. Should be stable now."],
		"pl": ["Um, I can't really share that kind of info...",
			"That's... above my pay grade. Maybe ask management?",
			"I don't think I'm supposed to talk about that.",
			"Whoa, that's sensitive. Let me focus on my tickets."],
		"ph": ["Okay look, between us? %s",
			"Since you've been cool about it... %s",
			"Don't tell anyone I told you this, but %s"],
		"ag": ["Hey, take it easy. I'm just doing my job.",
			"That's not how we talk to each other around here.",
			"I don't respond to pressure. Try asking nicely.",
			"Dude, chill. Not gonna work on me."],
		"vn": ["Honestly? That means a lot. Nobody notices how slammed we are.",
			"You get it. I've been pulling doubles all month.",
			"Yeah, it's been brutal. Thanks for actually asking.",
			"I appreciate that. Most people just dump more tickets on me."],
		"fb": ["Hm, not sure what you mean. Anything else?",
			"So was there something IT-related you needed?",
			"Right. My queue isn't getting any shorter.",
			"I'm not following. What do you need exactly?"],
	},
	"ft": { # friendly talkative
		"sm": ["Hey! Yeah man, another day right? Haha.",
			"Oh dude, my weekend was great! Went fishing.",
			"Honestly just vibing. This job's pretty chill.",
			"No worries! I love meeting new people around the office."],
		"wk": ["Oh yeah! So %s. Pretty cool right?",
			"Man, %s. I remember when they set that up, total chaos.",
			"Sure thing! %s. Happy to help!",
			"Oh for sure, %s. Lemme know if you need anything else!"],
		"pl": ["Uhh I dunno about that, I just work the desk y'know?",
			"That's above my clearance level if you know what I mean.",
			"I probably shouldn't go there. Don't wanna get in trouble!",
			"That's kinda hush-hush, right? Maybe ask somebody higher up?"],
		"ph": ["Okay so don't tell anyone but... %s",
			"Alright since you asked nicely -- %s",
			"Dude okay, between us though... %s"],
		"ag": ["Whoa, easy! No need to get intense about it.",
			"Hey man, I'm just the front desk guy, please don't...",
			"That's a little aggressive, don't you think?",
			"I'm gonna need you to tone it down a notch."],
		"vn": ["Aw, you're too nice! It can be lonely here sometimes.",
			"Finally someone who appreciates the little guys!",
			"That's so cool of you to say! Most people walk right past.",
			"You know what, yeah! I know more than people give me credit for."],
		"fb": ["Haha, sure! So uh... anything else going on?",
			"Gotcha gotcha. Well I'm here if you need anything!",
			"Ha, right. So what brings you by today?",
			"Oh okay! Anyway, how about that weather right?"],
	},
	"rp": { # reserved professional
		"sm": ["Fine, thank you. How can I help you?",
			"Busy as always. Is there something you need?",
			"We're in the middle of Q2 close. Time is short.",
			"Good, thanks. I have a meeting in fifteen, let's be quick."],
		"wk": ["Yes, %s. That's in the internal wiki.",
			"Correct. %s. Was there a specific request?",
			"Indeed -- %s. Submit a formal request if you need access.",
			"That's accurate. %s. Standard procedure."],
		"pl": ["I'm not at liberty to discuss that.",
			"That's need-to-know. Do you have authorization?",
			"I'd need a written request from your supervisor.",
			"That falls outside what I can share casually."],
		"ph": ["Given our rapport... %s", "Off the record: %s",
			"I trust your discretion. %s"],
		"ag": ["I don't appreciate being spoken to that way.",
			"That tone is inappropriate. This ends if it continues.",
			"I will not be pressured. Compose yourself.",
			"I'm going to pretend you didn't just say that."],
		"vn": ["...you noticed? The workload has been considerable. Thank you.",
			"I appreciate the courtesy. Challenging quarter.",
			"That's perceptive. Not many see past the calm exterior.",
			"The restructuring has put pressure on everyone."],
		"fb": ["Is there something specific I can help with?",
			"If there's nothing else, I should get back to work.",
			"Was there a particular matter you wanted to discuss?",
			"Let me know if you need something concrete."],
	},
}

var _emp: Dictionary; var _eid: String; var _trust: int; var _susp: int
var _rev: Array; var _ki: int; var _sty: String; var _on := false
var _log: RichTextLabel; var _inp: LineEdit
var _tb: ProgressBar; var _sb: ProgressBar
var _sl: VBoxContainer; var _modal: PanelContainer

func _ready() -> void:
	visible = false; mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchors_preset = Control.PRESET_FULL_RECT

func _unhandled_input(ev: InputEvent) -> void:
	if _on and ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		_close(); get_viewport().set_input_as_handled()

# --- Public API ---

func open_chat(employee_id: String) -> void:
	var op: Dictionary = GameState.get_current_operation()
	var emps: Array = op.get("blacksite_target", {}).get("employees", [])
	_emp = {}
	for e in emps:
		if e.get("id", "") == employee_id: _emp = e; break
	if _emp.is_empty():
		push_warning("SocialEngUI: employee '%s' not found" % employee_id); return
	_eid = employee_id
	var st: Dictionary = OpState.employee_states.get(_eid, {})
	_trust = st.get("trust", 0); _susp = st.get("suspicion", 0)
	_rev = st.get("secrets_revealed", []).duplicate(); _ki = 0
	_sty = _style()
	if _susp >= MAX_S:
		EventBus.handler_speak.emit("That contact is burned. Don't go back.", "normal"); return
	_on = true; mouse_filter = Control.MOUSE_FILTER_STOP; visible = true
	_build()
	_sys("Connected to %s (%s)" % [_emp.get("name", "?"), _emp.get("department", "")])
	_npc(["Hi there, can I help you?", "Hey. What can I do for you?",
		"Yes? How can I help?"][randi() % 3])
	VoiceHandler.speak("You're talking to %s. Tread carefully." % _emp.get("name", "someone"))
	await get_tree().process_frame
	if is_instance_valid(_inp): _inp.grab_focus()

# --- UI ---

func _sb_flat(bg: Color, border := Color.TRANSPARENT, bw := 0, cr := 0,
		ml := 0, mr := 0, mt := 0, mb := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border; s.set_border_width_all(bw)
	s.set_corner_radius_all(cr)
	s.content_margin_left = ml; s.content_margin_right = mr
	s.content_margin_top = mt; s.content_margin_bottom = mb
	return s

func _mk_lbl(txt: String, sz: int, col: Color) -> Label:
	var l := Label.new(); l.text = txt
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col); return l

func _mk_bar(mx: int, col: Color) -> ProgressBar:
	var b := ProgressBar.new(); b.min_value = 0; b.max_value = mx
	b.show_percentage = false; b.custom_minimum_size = Vector2(0, 8)
	var f := StyleBoxFlat.new(); f.bg_color = col; f.set_corner_radius_all(2)
	b.add_theme_stylebox_override("fill", f)
	var g := StyleBoxFlat.new(); g.bg_color = Color(0.08, 0.09, 0.12); g.set_corner_radius_all(2)
	b.add_theme_stylebox_override("background", g); return b

func _build() -> void:
	for c in get_children(): c.queue_free()
	# Backdrop
	var bg := ColorRect.new(); bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.color = Color(0, 0, 0, 0.65); bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	# Modal
	_modal = PanelContainer.new(); _modal.anchors_preset = Control.PRESET_CENTER
	_modal.anchor_left = 0.5; _modal.anchor_top = 0.5
	_modal.anchor_right = 0.5; _modal.anchor_bottom = 0.5
	_modal.offset_left = -MW / 2; _modal.offset_top = -MH / 2
	_modal.offset_right = MW / 2; _modal.offset_bottom = MH / 2
	_modal.add_theme_stylebox_override("panel", _sb_flat(C_BG, C_BORDER, 1, 6))
	var root := VBoxContainer.new(); root.add_theme_constant_override("separation", 0)
	# Header
	var hdr := PanelContainer.new(); hdr.custom_minimum_size = Vector2(0, 44)
	var hs := _sb_flat(C_HDR, C_BORDER, 0, 0, 12, 12, 6, 6)
	hs.border_width_bottom = 1; hs.corner_radius_top_left = 6; hs.corner_radius_top_right = 6
	hdr.add_theme_stylebox_override("panel", hs)
	var hr := HBoxContainer.new()
	var inf := VBoxContainer.new(); inf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inf.add_theme_constant_override("separation", 0)
	inf.add_child(_mk_lbl(_emp.get("name", "UNKNOWN"), 15, C_TEXT))
	inf.add_child(_mk_lbl("%s | %s" % [_emp.get("role", ""), _emp.get("department", "")], 10, C_DIM))
	hr.add_child(inf)
	var xb := Button.new(); xb.text = "X"; xb.custom_minimum_size = Vector2(32, 32)
	xb.pressed.connect(_close); hr.add_child(xb)
	hdr.add_child(hr); root.add_child(hdr)
	# Body
	var body := HBoxContainer.new(); body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	# Chat (65%)
	var cw := PanelContainer.new(); cw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cw.size_flags_stretch_ratio = 0.65
	cw.add_theme_stylebox_override("panel", _sb_flat(Color(0.025, 0.03, 0.04, 0.5), Color.TRANSPARENT, 0, 0, 8, 8, 8, 8))
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log = RichTextLabel.new(); _log.bbcode_enabled = true; _log.fit_content = true
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _log.scroll_following = true
	_log.add_theme_color_override("default_color", C_TEXT)
	_log.add_theme_font_size_override("normal_font_size", 12)
	sc.add_child(_log); cw.add_child(sc); body.add_child(cw)
	# Profile (35%)
	var pf := PanelContainer.new(); pf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pf.size_flags_stretch_ratio = 0.35; pf.custom_minimum_size = Vector2(220, 0)
	var ps := _sb_flat(Color(0.03, 0.035, 0.05, 0.7), C_BORDER, 0, 0, 10, 10, 10, 10)
	ps.border_width_left = 1; pf.add_theme_stylebox_override("panel", ps)
	var pv := VBoxContainer.new(); pv.add_theme_constant_override("separation", 6)
	var ph := _mk_lbl(_emp.get("photo_description", "No photo available"), 10, C_DIM)
	ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; pv.add_child(ph)
	pv.add_child(_mk_lbl("TRUST", 9, C_DIM))
	_tb = _mk_bar(_emp.get("trust_threshold", 3), C_TRUST); _tb.value = _trust; pv.add_child(_tb)
	pv.add_child(_mk_lbl("SUSPICION", 9, C_DIM))
	_sb = _mk_bar(MAX_S, C_SUSP); _sb.value = _susp; pv.add_child(_sb)
	pv.add_child(_mk_lbl("TRAITS", 9, C_DIM))
	var fl := HFlowContainer.new()
	for t in _emp.get("personality_traits", []):
		var bd := PanelContainer.new()
		bd.add_theme_stylebox_override("panel", _sb_flat(Color(0.08, 0.1, 0.15, 0.8), C_BORDER, 1, 3, 6, 6, 2, 2))
		bd.add_child(_mk_lbl(t, 9, C_DIM)); fl.add_child(bd)
	pv.add_child(fl)
	pv.add_child(_mk_lbl("SECRETS", 9, C_DIM))
	_sl = VBoxContainer.new(); _sl.add_theme_constant_override("separation", 2)
	_ref_sec(); pv.add_child(_sl)
	pf.add_child(pv); body.add_child(pf); root.add_child(body)
	# Input
	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 8); mg.add_theme_constant_override("margin_right", 8)
	mg.add_theme_constant_override("margin_bottom", 8); mg.add_theme_constant_override("margin_top", 4)
	var ir := HBoxContainer.new(); ir.add_theme_constant_override("separation", 6)
	_inp = LineEdit.new(); _inp.placeholder_text = "Type a message..."
	_inp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inp.custom_minimum_size = Vector2(0, 32)
	_inp.add_theme_font_size_override("font_size", 12); _inp.text_submitted.connect(_send)
	ir.add_child(_inp)
	var sn := Button.new(); sn.text = "SEND"; sn.custom_minimum_size = Vector2(60, 32)
	sn.pressed.connect(func(): _send(_inp.text)); ir.add_child(sn)
	mg.add_child(ir); root.add_child(mg)
	_modal.add_child(root); add_child(_modal)
	_modal.modulate.a = 0.0
	create_tween().tween_property(_modal, "modulate:a", 1.0, 0.15)

func _ref_sec() -> void:
	if not is_instance_valid(_sl): return
	for c in _sl.get_children(): c.queue_free()
	if _rev.is_empty():
		_sl.add_child(_mk_lbl("None yet", 9, C_DIM))
	else:
		for s in _rev:
			var l := _mk_lbl("* %s" % s.left(48), 9, C_SECRET)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD; _sl.add_child(l)

# --- Chat ---

func _plr(t: String) -> void:
	_log.append_text("\n[right][color=#%s]> %s[/color][/right]" % [C_PLR.to_html(false), t])
func _npc(t: String) -> void:
	var f: String = _emp.get("name", "???").split(" ")[0]
	_log.append_text("\n[color=#%s]%s:[/color] [color=#%s]%s[/color]" % [
		C_TRUST.to_html(false), f, C_TEXT.to_html(false), t])
func _sys(t: String) -> void:
	_log.append_text("\n[center][color=#%s]--- %s ---[/color][/center]" % [C_DIM.to_html(false), t])
func _sec_msg(t: String) -> void:
	_log.append_text("\n[color=#%s][b]%s[/b][/color]" % [C_SECRET.to_html(false), t])
	_log.append_text("\n[center][color=#%s][SECRET REVEALED][/color][/center]" % [C_SECRET.to_html(false)])

# --- Engine ---

func _send(text: String) -> void:
	var t := text.strip_edges()
	if t.is_empty(): return
	_inp.text = ""; _plr(t)
	var lo := t.to_lower(); var thr: int = _emp.get("trust_threshold", 3)
	if _kw(lo, KW_AG): _do_ag()
	elif _vm(lo): _do_vn()
	elif _kw(lo, KW_PR): _do_pr(thr)
	elif _kw(lo, KW_WK): _do_wk()
	elif _kw(lo, KW_SM): _do_sm()
	else: _do_fb()
	await _chk(); _sync(); _ub()
	if _on and is_instance_valid(_inp):
		await get_tree().process_frame; _inp.grab_focus()

func _do_sm() -> void:
	_trust = mini(_trust + 1, 10); _npc(_tp("sm"))
	EventBus.se_trust_changed.emit(_eid, _trust)

func _do_wk() -> void:
	_trust = mini(_trust + 1, 10)
	var kn: Array = _emp.get("knowledge_set", [])
	if kn.is_empty(): _npc(_tp("fb")); return
	var info: String = kn[_ki % kn.size()]; _ki += 1
	_npc(_tp("wk") % info); EventBus.se_trust_changed.emit(_eid, _trust)

func _do_pr(thr: int) -> void:
	if _trust >= thr:
		var secs: Array = _emp.get("secrets", [])
		var pool: Array = []
		for s in secs:
			if s not in _rev: pool.append(s)
		if pool.is_empty():
			_npc("I've told you everything I know about that."); return
		var sec: String = pool[0]; _rev.append(sec)
		_npc(_tp("ph") % sec); _sec_msg(sec)
		EventBus.se_secret_revealed.emit(_eid, sec)
		EventBus.handler_speak.emit("Good work. That could be useful.", "normal")
		if is_instance_valid(_modal):
			Juice.float_text(_modal, "+SECRET", Vector2(MW / 2 - 40, MH / 2 - 20), C_SECRET)
		_ref_sec()
	else:
		_susp = mini(_susp + 1, MAX_S); _npc(_tp("pl"))

func _do_ag() -> void:
	_susp = mini(_susp + 2, MAX_S); _trust = maxi(_trust - 1, 0)
	_npc(_tp("ag")); EventBus.se_trust_changed.emit(_eid, _trust)

func _do_vn() -> void:
	_trust = mini(_trust + 2, 10); _npc(_tp("vn"))
	EventBus.se_trust_changed.emit(_eid, _trust)
	EventBus.handler_speak.emit("You found a pressure point. Keep going.", "normal")

func _do_fb() -> void: _npc(_tp("fb"))

# --- Suspicion ---

func _chk() -> void:
	if _susp == 3:
		_sys("They seem uncomfortable"); _npc("You're asking a lot of questions...")
	elif _susp == 4:
		_sys("Suspicion is critical"); _npc("I don't think I should be telling you this.")
	elif _susp >= MAX_S:
		_sys("BLOWN -- employee will report this conversation")
		_npc("I'm going to report this conversation.")
		OpState.add_detection("se_failed")
		EventBus.handler_speak.emit("Cover's blown. We lost that contact.", "critical")
		_sync()
		await get_tree().create_timer(1.5).timeout
		_close()

# --- Helpers ---

func _kw(i: String, w: Array) -> bool:
	for k in w:
		if k in i: return true
	return false

func _vm(i: String) -> bool:
	for v in _emp.get("vulnerabilities", []):
		for w in v.get("exploit_vector", "").to_lower().split(" "):
			if w.length() >= 4 and w in i: return true
	return false

func _tp(cat: String) -> String:
	var p: Dictionary = T.get(_sty, T["ct"])
	var a: Array = p.get(cat, ["..."]); return a[randi() % a.size()]

func _style() -> String:
	var traits_str: String = " ".join(PackedStringArray(_emp.get("personality_traits", [])))
	var c: String = (traits_str + " " + _emp.get("speech_pattern", "")).to_lower()
	if "talkative" in c or "friendly" in c or "chatty" in c: return "ft"
	if "reserved" in c or "formal" in c or "precise" in c: return "rp"
	return "ct"

func _sync() -> void:
	OpState.employee_states[_eid] = {"trust": _trust, "suspicion": _susp,
		"secrets_revealed": _rev.duplicate()}

func _ub() -> void:
	if is_instance_valid(_tb): _tb.value = _trust
	if is_instance_valid(_sb): _sb.value = _susp

func _close() -> void:
	if not _on: return
	_on = false; _sync()
	if is_instance_valid(_modal):
		var tw := create_tween()
		tw.tween_property(_modal, "modulate:a", 0.0, 0.12)
		tw.tween_callback(func():
			visible = false; mouse_filter = Control.MOUSE_FILTER_IGNORE
			for ch in get_children(): ch.queue_free())
	else: visible = false; mouse_filter = Control.MOUSE_FILTER_IGNORE
