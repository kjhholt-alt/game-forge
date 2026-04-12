## Terminal UI — BLACKSITE hacking interface. Shows on phase == "blacksite".
extends Control

const C_BG := Color(0.02, 0.025, 0.03)
const C_GREEN := Color(0.2, 0.9, 0.4)
const C_AMBER := Color(0.9, 0.7, 0.2)
const C_RED := Color(0.9, 0.3, 0.2)
const C_WHITE := Color(0.8, 0.83, 0.87)
const C_DIM := Color(0.4, 0.45, 0.5)
const C_PANEL := Color(0.035, 0.04, 0.055, 0.95)

var _output: RichTextLabel
var _input: LineEdit
var _side_host: RichTextLabel
var _side_det: ProgressBar
var _side_hosts: RichTextLabel
var _side_creds: RichTextLabel
var _side_files: RichTextLabel
var _net: Dictionary = {}
var _by_ip: Dictionary = {}
var _by_id: Dictionary = {}
var _exploited: Dictionary = {}
var _authed: Dictionary = {}
var _hist: Array[String] = []
var _hist_i: int = -1
var _cmds: PackedStringArray = ["help","scan","probe","exploit","connect","login","ls","cat","download","decrypt","netmap","contacts","talk","clear"]

func _ready() -> void:
	visible = false; anchors_preset = Control.PRESET_FULL_RECT; mouse_filter = MOUSE_FILTER_STOP
	EventBus.phase_changed.connect(_on_phase)
	EventBus.detection_changed.connect(_on_det)
	_build()

func _build() -> void:
	var root := HBoxContainer.new()
	root.anchors_preset = Control.PRESET_FULL_RECT
	add_child(root)
	# Terminal panel (75%)
	var tp := PanelContainer.new()
	tp.size_flags_horizontal = SIZE_EXPAND_FILL; tp.size_flags_stretch_ratio = 3.0
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = C_BG; tsb.content_margin_left = 12; tsb.content_margin_right = 12
	tsb.content_margin_top = 8; tsb.content_margin_bottom = 8
	tp.add_theme_stylebox_override("panel", tsb); root.add_child(tp)
	var tv := VBoxContainer.new(); tv.add_theme_constant_override("separation", 4); tp.add_child(tv)
	_output = RichTextLabel.new()
	_output.bbcode_enabled = true; _output.scroll_following = true; _output.selection_enabled = true
	_output.size_flags_vertical = SIZE_EXPAND_FILL
	_output.add_theme_font_size_override("normal_font_size", 13)
	_output.add_theme_color_override("default_color", C_GREEN); tv.add_child(_output)
	var ir := HBoxContainer.new(); ir.add_theme_constant_override("separation", 4); tv.add_child(ir)
	var pl := Label.new(); pl.text = "> "; pl.add_theme_font_size_override("font_size", 14)
	pl.add_theme_color_override("font_color", C_GREEN); ir.add_child(pl)
	_input = LineEdit.new(); _input.size_flags_horizontal = SIZE_EXPAND_FILL
	_input.add_theme_font_size_override("font_size", 13)
	_input.add_theme_color_override("font_color", C_GREEN)
	_input.add_theme_color_override("caret_color", C_GREEN)
	var isb := StyleBoxFlat.new(); isb.bg_color = Color(0.03, 0.035, 0.04); isb.set_border_width_all(0)
	isb.content_margin_left = 4; isb.content_margin_top = 2; isb.content_margin_bottom = 2
	_input.add_theme_stylebox_override("normal", isb); _input.add_theme_stylebox_override("focus", isb)
	_input.text_submitted.connect(_on_submit); ir.add_child(_input)
	# Side panel (25%)
	var sp := PanelContainer.new()
	sp.size_flags_horizontal = SIZE_EXPAND_FILL; sp.size_flags_stretch_ratio = 1.0
	var ssb := StyleBoxFlat.new(); ssb.bg_color = C_PANEL; ssb.border_color = Color(0.1, 0.13, 0.18)
	ssb.border_width_left = 1; ssb.content_margin_left = 12; ssb.content_margin_right = 12
	ssb.content_margin_top = 10; ssb.content_margin_bottom = 10
	sp.add_theme_stylebox_override("panel", ssb); root.add_child(sp)
	var sv := VBoxContainer.new(); sv.add_theme_constant_override("separation", 10); sp.add_child(sv)
	_sec(sv, "CONNECTED HOST"); _side_host = _rtl(sv, 55)
	_sec(sv, "DETECTION")
	_side_det = ProgressBar.new(); _side_det.min_value = 0.0; _side_det.max_value = 1.0
	_side_det.show_percentage = true; _side_det.custom_minimum_size = Vector2(0, 18)
	var df := StyleBoxFlat.new(); df.bg_color = Color(0.2, 0.7, 0.3); df.set_corner_radius_all(2)
	_side_det.add_theme_stylebox_override("fill", df)
	var db := StyleBoxFlat.new(); db.bg_color = Color(0.06, 0.07, 0.09); db.set_corner_radius_all(2)
	_side_det.add_theme_stylebox_override("background", db); sv.add_child(_side_det)
	_sec(sv, "DISCOVERED HOSTS"); _side_hosts = _rtl(sv, 90)
	_sec(sv, "CREDENTIALS"); _side_creds = _rtl(sv, 70)
	_sec(sv, "EXFILTRATED"); _side_files = _rtl(sv, 70)

func _sec(p: VBoxContainer, t: String) -> void:
	var l := Label.new(); l.text = t; l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", C_DIM); p.add_child(l)

func _rtl(p: VBoxContainer, h: float) -> RichTextLabel:
	var r := RichTextLabel.new(); r.bbcode_enabled = true; r.scroll_following = true
	r.custom_minimum_size = Vector2(0, h); r.add_theme_font_size_override("normal_font_size", 11)
	r.add_theme_color_override("default_color", C_WHITE); p.add_child(r); return r

# --- Phase / detection ---
func _on_phase(p: String) -> void:
	if p == "blacksite":
		_load_net(); visible = true; _input.grab_focus(); _banner()
	else:
		visible = false

func _load_net() -> void:
	var op := GameState.get_current_operation()
	_net = op.get("blacksite_target", {}).get("network", {})
	_by_ip.clear(); _by_id.clear()
	for h in _net.get("hosts", []):
		_by_ip[h.get("ip", "")] = h; _by_id[h.get("id", "")] = h
	for ep in _net.get("entry_points", []):
		if _by_id.has(ep): OpState.discovered_hosts[ep] = _by_id[ep]
	_sidebar()

func _on_det(_lv: String, val: float) -> void:
	_side_det.value = val
	var f := StyleBoxFlat.new(); f.set_corner_radius_all(2)
	if val < 0.25: f.bg_color = Color(0.2, 0.7, 0.3)
	elif val < 0.50: f.bg_color = Color(0.9, 0.7, 0.2)
	elif val < 0.75: f.bg_color = Color(0.9, 0.3, 0.2)
	else: f.bg_color = Color(0.9, 0.1, 0.1)
	_side_det.add_theme_stylebox_override("fill", f)

# --- Input ---
func _on_submit(text: String) -> void:
	var t := text.strip_edges()
	if t.is_empty(): _input.clear(); return
	_hist.append(t); _hist_i = -1; _pl("> " + t, C_GREEN); _input.clear(); _parse(t)

func _gui_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed: return
	if event.keycode == KEY_UP and not _hist.is_empty():
		_hist_i = _hist.size() - 1 if _hist_i == -1 else max(0, _hist_i - 1)
		_input.text = _hist[_hist_i]; _input.caret_column = _input.text.length(); accept_event()
	elif event.keycode == KEY_DOWN:
		if _hist_i >= 0 and _hist_i < _hist.size() - 1:
			_hist_i += 1; _input.text = _hist[_hist_i]
		else: _hist_i = -1; _input.text = ""
		_input.caret_column = _input.text.length(); accept_event()
	elif event.keycode == KEY_TAB:
		_tab(); accept_event()

func _tab() -> void:
	var parts := _input.text.strip_edges().split(" ", false)
	if parts.is_empty(): return
	if parts.size() <= 1:
		var m: PackedStringArray = []
		for c in _cmds:
			if c.begins_with(parts[0]): m.append(c)
		if m.size() == 1: _input.text = m[0] + " "; _input.caret_column = _input.text.length()
		elif m.size() > 1: _pl("  ".join(m), C_DIM)
	else:
		var ip_p: String = parts[parts.size() - 1]
		var m: PackedStringArray = []
		for hid in OpState.discovered_hosts:
			var ip: String = OpState.discovered_hosts[hid].get("ip", "")
			if ip.begins_with(ip_p): m.append(ip)
		if m.size() == 1:
			parts[parts.size() - 1] = m[0]
			_input.text = " ".join(parts) + " "; _input.caret_column = _input.text.length()
		elif m.size() > 1: _pl("  ".join(m), C_DIM)

# --- Command dispatch ---
func _parse(raw: String) -> void:
	var parts := raw.split(" ", false)
	if parts.is_empty(): return
	var cmd: String = parts[0].to_lower()
	var args: Array = []
	for i in range(1, parts.size()): args.append(parts[i])
	EventBus.terminal_command.emit(cmd, args)
	match cmd:
		"help": _cmd_help()
		"scan": _cmd_scan(args)
		"probe": _cmd_probe(args)
		"exploit": _cmd_exploit(args)
		"connect": _cmd_connect(args)
		"login": _cmd_login(args)
		"ls": _cmd_ls(args)
		"cat": _cmd_cat(args)
		"download": _cmd_download(args)
		"decrypt": _cmd_decrypt(args)
		"netmap": _cmd_netmap()
		"contacts": _cmd_contacts()
		"talk": _cmd_talk(args)
		"clear": _output.clear()
		_: _pl("Unknown command: %s  (type 'help')" % cmd, C_RED)

func _cmd_help() -> void:
	_pl("--- BLACKSITE TERMINAL ---", C_AMBER)
	for l in ["  help                    Show this help","  scan <ip>               Scan host for services",
		"  probe <ip> <port>       Probe a specific service","  exploit <ip> <port>     Exploit a vulnerable service",
		"  connect <ip>            Connect to a host","  login <user> <pass>     Authenticate on connected host",
		"  ls [path]               List files","  cat <path>              Read a file",
		"  download <path>         Exfiltrate a file","  decrypt <path>          Decrypt an encrypted file",
		"  netmap                  ASCII network topology","  contacts                List known employees",
		"  talk <id>               Social engineer employee","  clear                   Clear terminal"]:
		_pl(l, C_WHITE)

func _cmd_scan(args: Array) -> void:
	if args.is_empty(): _pl("Usage: scan <ip>", C_RED); return
	var host := _by_ip.get(args[0], {}) as Dictionary
	if host.is_empty(): _pl("No route to host %s" % args[0], C_RED); return
	OpState.add_detection("scan")
	_progress("SCANNING %s" % args[0], 1.0, func():
		OpState.discovered_hosts[host.get("id", "")] = host
		_pl("  PORT    SERVICE    VERSION", C_DIM)
		for svc in host.get("services", []):
			var vt := ""
			if svc.get("vulnerable", false):
				vt = " [color=#e64d33][VULNERABLE: %s][/color]" % svc.get("cve_id", "???")
			_bb("  %-7s %-10s %s%s" % [str(svc.get("port", 0)), svc.get("service_type", "?"), svc.get("version", "?"), vt])
		_sidebar(); GameState.add_xp("network_exploitation", 5))

func _cmd_probe(args: Array) -> void:
	if args.size() < 2: _pl("Usage: probe <ip> <port>", C_RED); return
	var host := _by_ip.get(args[0], {}) as Dictionary
	if host.is_empty(): _pl("No route to host %s" % args[0], C_RED); return
	var svc := _svc(host, int(args[1]))
	if svc.is_empty(): _pl("No service on port %s" % args[1], C_RED); return
	OpState.add_detection("probe")
	_progress("PROBING %s:%s" % [args[0], args[1]], 0.7, func():
		_pl("Service: %s" % svc.get("service_type", "?"), C_WHITE)
		_pl("Version: %s" % svc.get("version", "?"), C_WHITE)
		_pl("Banner:  %s" % svc.get("banner", ""), C_DIM)
		if svc.get("vulnerable", false): _pl("STATUS:  VULNERABLE (%s)" % svc.get("cve_id", ""), C_RED)
		else: _pl("STATUS:  No known vulnerabilities", C_GREEN)
		GameState.add_xp("network_exploitation", 3))

func _cmd_exploit(args: Array) -> void:
	if args.size() < 2: _pl("Usage: exploit <ip> <port>", C_RED); return
	var host := _by_ip.get(args[0], {}) as Dictionary
	if host.is_empty(): _pl("No route to host %s" % args[0], C_RED); return
	var svc := _svc(host, int(args[1]))
	if svc.is_empty(): _pl("No service on port %s" % args[1], C_RED); return
	if not svc.get("vulnerable", false):
		OpState.add_detection("exploit_fail")
		_progress("EXPLOITING %s:%s" % [args[0], args[1]], 1.5, func():
			_pl("[FAILED] Service is not vulnerable.", C_RED)
			EventBus.handler_speak.emit("Careful. Failed exploits draw attention.", "normal"))
		return
	OpState.add_detection("exploit_success")
	_progress("EXPLOITING %s" % svc.get("cve_id", ""), 2.0, func():
		_exploited[host.get("id", "")] = true
		_pl("[SUCCESS] Shell access gained on %s (%s)" % [host.get("hostname", "?"), args[0]], C_GREEN)
		GameState.add_xp("network_exploitation", 15); _sidebar()
		EventBus.handler_speak.emit("You're in. Move fast.", "normal"))

func _cmd_connect(args: Array) -> void:
	if args.is_empty(): _pl("Usage: connect <ip>", C_RED); return
	var host := _by_ip.get(args[0], {}) as Dictionary
	if host.is_empty(): _pl("No route to host %s" % args[0], C_RED); return
	var hid: String = host.get("id", "")
	if host.get("requires_credentials", false) and not _exploited.has(hid) and not _authed.has(hid):
		_pl("Connection refused -- authentication required.", C_RED)
		_pl("Use 'login <user> <pass>' or exploit a service first.", C_AMBER); return
	OpState.connected_host_id = hid; OpState.current_path = "/"
	_pl("Connected to %s (%s) -- %s" % [host.get("hostname","?"), args[0], host.get("os","?").to_upper()], C_GREEN)
	_sidebar()

func _cmd_login(args: Array) -> void:
	if args.size() < 2: _pl("Usage: login <user> <pass>", C_RED); return
	var tid: String = OpState.connected_host_id
	if tid.is_empty():
		for hid in OpState.discovered_hosts:
			for c in OpState.discovered_hosts[hid].get("credentials", []):
				if c.get("username","") == args[0] and c.get("password","") == args[1]: tid = hid; break
			if not tid.is_empty(): break
	if tid.is_empty(): _pl("Not connected. Use 'connect <ip>' first.", C_RED); return
	var host: Dictionary = _by_id.get(tid, {})
	var ok := false
	for c in host.get("credentials", []):
		if c.get("username","") == args[0] and c.get("password","") == args[1]: ok = true; break
	if ok:
		_authed[tid] = true; OpState.connected_host_id = tid; OpState.current_path = "/"
		OpState.add_credential(args[0], args[1], tid)
		_pl("[LOGIN SUCCESS] Authenticated as %s on %s" % [args[0], host.get("hostname","?")], C_GREEN)
		GameState.add_xp("network_exploitation", 10); _sidebar()
	else:
		OpState.add_detection("login_fail")
		_pl("[LOGIN FAILED] Invalid credentials.", C_RED)
		EventBus.handler_speak.emit("Wrong credentials. That got logged.", "normal")

func _cmd_ls(args: Array) -> void:
	if OpState.connected_host_id.is_empty(): _pl("Not connected.", C_RED); return
	var host: Dictionary = _by_id.get(OpState.connected_host_id, {})
	var fp: String = args[0] if not args.is_empty() else ""
	var exfil: Array = _net.get("exfil_target_ids", [])
	for f in host.get("files", []):
		var p: String = f.get("path", "")
		if not fp.is_empty() and not p.begins_with(fp): continue
		var tags := ""
		if f.get("is_target", false) or p in exfil: tags += " [color=#e6b833][TARGET][/color]"
		if f.get("encrypted", false): tags += " [color=#cc5533][ENCRYPTED][/color]"
		if p in OpState.exfiltrated_files: tags += " [color=#33e666][DONE][/color]"
		_bb("  %s (%d KB)%s" % [p.get_file(), f.get("size_kb", 0), tags])

func _cmd_cat(args: Array) -> void:
	if OpState.connected_host_id.is_empty(): _pl("Not connected.", C_RED); return
	if args.is_empty(): _pl("Usage: cat <path>", C_RED); return
	var fd := _file(_by_id.get(OpState.connected_host_id, {}), args[0])
	if fd.is_empty(): _pl("File not found: %s" % args[0], C_RED); return
	if fd.get("encrypted", false): _pl("[ENCRYPTED] Use 'decrypt %s' first." % args[0], C_AMBER); return
	for line in fd.get("content", "").split("\n"): _pl(line, C_WHITE)
	_discover_ips(fd.get("content", "")); GameState.add_xp("network_exploitation", 2)

func _cmd_download(args: Array) -> void:
	if OpState.connected_host_id.is_empty(): _pl("Not connected.", C_RED); return
	if args.is_empty(): _pl("Usage: download <path>", C_RED); return
	var fd := _file(_by_id.get(OpState.connected_host_id, {}), args[0])
	if fd.is_empty(): _pl("File not found: %s" % args[0], C_RED); return
	if args[0] in OpState.exfiltrated_files: _pl("Already exfiltrated.", C_AMBER); return
	OpState.add_detection("download")
	var path: String = args[0]
	_progress("DOWNLOADING %s" % path.get_file(), 1.5, func():
		OpState.exfiltrate_file(path)
		if fd.get("is_target", false):
			_pl("[EXFILTRATED] Target file acquired.", C_GREEN)
			EventBus.handler_speak.emit("Got it. That's what we came for.", "normal")
			GameState.add_xp("network_exploitation", 25)
		else:
			_pl("[DOWNLOADED] %s saved." % path.get_file(), C_GREEN)
			GameState.add_xp("network_exploitation", 5)
		_sidebar())

func _cmd_decrypt(args: Array) -> void:
	if OpState.connected_host_id.is_empty(): _pl("Not connected.", C_RED); return
	if args.is_empty(): _pl("Usage: decrypt <path>", C_RED); return
	var fd := _file(_by_id.get(OpState.connected_host_id, {}), args[0])
	if fd.is_empty(): _pl("File not found: %s" % args[0], C_RED); return
	if not fd.get("encrypted", false): _pl("File is not encrypted.", C_AMBER); return
	_progress("DECRYPTING (%s)" % fd.get("cipher", "unknown").to_upper(), 2.0, func():
		fd["encrypted"] = false; _pl("[DECRYPTED] %s" % args[0], C_GREEN)
		var c: String = fd.get("content", "")
		if c.begins_with("[ENCRYPTED"):
			var nl := c.find("\n")
			if nl >= 0: c = c.substr(nl + 1).strip_edges()
		for line in c.split("\n"): _pl(line, C_WHITE)
		GameState.add_xp("cryptography", 20))

func _cmd_netmap() -> void:
	_pl("=== NETWORK TOPOLOGY ===", C_AMBER)
	for sn in _net.get("subnets", []):
		_pl("[%s] %s" % [sn.get("name","?"), sn.get("cidr","?")], C_AMBER)
		for hid in sn.get("hosts", []):
			var h: Dictionary = _by_id.get(hid, {})
			var disc: bool = OpState.discovered_hosts.has(hid)
			var conn: bool = OpState.connected_host_id == hid
			var tag := " [color=#33e666]<< CONNECTED >>[/color]" if conn else (" [color=#e6b833][KNOWN][/color]" if disc else " [color=#666666][???][/color]")
			if disc: _bb("  |-- %s (%s)%s" % [h.get("hostname","?"), h.get("ip","?"), tag])
			else: _bb("  |-- ??? (???.???.???.???)%s" % tag)

func _cmd_contacts() -> void:
	var emps: Array = GameState.get_current_operation().get("blacksite_target", {}).get("employees", [])
	if emps.is_empty(): _pl("No employee profiles available.", C_DIM); return
	_pl("=== KNOWN EMPLOYEES ===", C_AMBER)
	for e in emps:
		_bb("  [color=#e6b833]%s[/color]  %s - %s (%s)" % [e.get("id",""), e.get("name","?"), e.get("role","?"), e.get("department","?")])
	_pl("Use 'talk <id>' to initiate contact.", C_DIM)

func _cmd_talk(args: Array) -> void:
	if args.is_empty(): _pl("Usage: talk <employee_id>", C_RED); return
	var emps: Array = GameState.get_current_operation().get("blacksite_target", {}).get("employees", [])
	var found := false
	for e in emps:
		if e.get("id","") == args[0]: found = true; break
	if not found: _pl("Unknown employee: %s" % args[0], C_RED); return
	_pl("[OPENING SOCIAL ENGINEERING CHANNEL: %s]" % args[0], C_AMBER)
	EventBus.handler_speak.emit("Initiating contact with %s. Be careful." % args[0], "normal")

# --- Progress bar simulation ---
func _progress(label: String, dur: float, cb: Callable) -> void:
	_input.editable = false
	_bb("[color=#e6b833][%s...][/color]" % label)
	var steps := 20; var dt := dur / steps
	for i in range(steps + 1):
		if i < steps: await get_tree().create_timer(dt).timeout
	cb.call(); _input.editable = true; _input.grab_focus()

# --- IP discovery from file contents ---
func _discover_ips(content: String) -> void:
	var rx := RegEx.new(); rx.compile("\\b(10\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})\\b")
	var new_ips: PackedStringArray = []
	for m in rx.search_all(content):
		var ip: String = m.get_string(1)
		if _by_ip.has(ip):
			var hid: String = _by_ip[ip].get("id", "")
			if not OpState.discovered_hosts.has(hid):
				OpState.discovered_hosts[hid] = _by_ip[ip]; new_ips.append(ip)
	if not new_ips.is_empty():
		_bb("[color=#e6b833][NEW HOSTS DISCOVERED: %s][/color]" % ", ".join(new_ips))
		EventBus.handler_speak.emit("New hosts found. Expanding the attack surface.", "normal")
		_sidebar()

# --- Sidebar ---
func _sidebar() -> void:
	_side_host.clear()
	if OpState.connected_host_id.is_empty():
		_side_host.append_text("[color=#666666]Not connected[/color]")
	else:
		var h: Dictionary = _by_id.get(OpState.connected_host_id, {})
		_side_host.append_text("[color=#33e666]%s[/color]\n%s\n%s" % [h.get("hostname","?"), h.get("ip","?"), h.get("os","?").to_upper()])
	_side_det.value = OpState.detection_value
	_side_hosts.clear()
	if OpState.discovered_hosts.is_empty(): _side_hosts.append_text("[color=#666666]None[/color]")
	else:
		for hid in OpState.discovered_hosts:
			var h: Dictionary = OpState.discovered_hosts[hid]
			var c := "#33e666" if OpState.connected_host_id == hid else "#cccccc"
			_side_hosts.append_text("[color=%s]%s[/color] %s\n" % [c, h.get("ip","?"), h.get("hostname","?")])
	_side_creds.clear()
	if OpState.found_credentials.is_empty(): _side_creds.append_text("[color=#666666]None[/color]")
	else:
		for cr in OpState.found_credentials:
			_side_creds.append_text("[color=#e6b833]%s[/color]:%s\n" % [cr.get("username","?"), cr.get("password","?")])
	_side_files.clear()
	if OpState.exfiltrated_files.is_empty(): _side_files.append_text("[color=#666666]None[/color]")
	else:
		for fp in OpState.exfiltrated_files:
			_side_files.append_text("[color=#33e666]%s[/color]\n" % fp.get_file())

# --- Output helpers ---
func _pl(text: String, color: Color = C_GREEN) -> void:
	_output.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), text.replace("[", "[lb]").replace("]", "[rb]")])

func _bb(bbcode: String) -> void:
	_output.append_text(bbcode + "\n")

func _banner() -> void:
	for l in ["","  ____  _        _    ____ _  ______  ___ _____ _____",
		" | __ )| |      / \\  / ___| |/ / ___|/ _ \\_   _| ____|",
		" |  _ \\| |     / _ \\| |   | ' /\\___ \\ | | || | |  _|",
		" | |_) | |___ / ___ \\ |___| . \\ ___) | |_| || | | |___",
		" |____/|_____/_/   \\_\\____|_|\\_\\____/ \\___/ |_| |_____|","",
		"  >> BLACKSITE INTRUSION TERMINAL v2.1","  >> Type 'help' for available commands",""]:
		_pl(l, C_GREEN)
	for ep in _net.get("entry_points", []):
		var h: Dictionary = _by_id.get(ep, {})
		_pl("  Entry: %s (%s)" % [h.get("hostname","?"), h.get("ip","?")], C_AMBER)
	_pl("", C_GREEN)

# --- Lookup helpers ---
func _svc(host: Dictionary, port: int) -> Dictionary:
	for s in host.get("services", []):
		if s.get("port", 0) == port: return s
	return {}

func _file(host: Dictionary, path: String) -> Dictionary:
	for f in host.get("files", []):
		if f.get("path", "") == path: return f
	return {}
