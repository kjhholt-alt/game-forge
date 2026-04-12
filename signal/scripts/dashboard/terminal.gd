## Hacking terminal — Hacknet-style command interface for BLACKSITE phase.
##
## The player types commands to navigate the target network, exploit
## vulnerabilities, and exfiltrate data. Commands resolve against the
## pre-generated NetworkTopology data — no AI at runtime.
extends Control


# ---------------------------------------------------------------------------
# Theme constants
# ---------------------------------------------------------------------------

const COLOR_DEFAULT := Color(0.2, 0.9, 0.3)     # Terminal green
const COLOR_ERROR := Color(0.9, 0.2, 0.2)        # Red
const COLOR_WARNING := Color(0.9, 0.7, 0.2)      # Yellow
const COLOR_INFO := Color(0.4, 0.7, 0.9)         # Cyan
const COLOR_SYSTEM := Color(0.5, 0.5, 0.5)       # Dim gray
const COLOR_SUCCESS := Color(0.3, 0.9, 0.5)      # Bright green

const MAX_HISTORY := 100
const PROMPT_PREFIX := "signal@proxy:~$ "


# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var output: RichTextLabel = $VBox/Output
@onready var input_line: LineEdit = $VBox/InputLine


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _command_history: Array[String] = []
var _history_index: int = -1
var _network_data: Dictionary = {}  # Full NetworkTopology from operation
var _hosts: Dictionary = {}         # host_id -> host data
var _connected_host: Dictionary = {}
var _current_path: String = "/"
var _enabled: bool = false


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	input_line.text_submitted.connect(_on_command_submitted)
	EventBus.phase_changed.connect(_on_phase_changed)
	EventBus.analyst_burned.connect(_on_burned)

	# Style the output
	output.scroll_following = true

	_print_system("SIGNAL Terminal v1.0")
	_print_system("Awaiting BLACKSITE authorization...")
	_set_enabled(false)


const ALL_COMMANDS := [
	"scan", "probe", "connect", "login", "exploit",
	"ls", "cat", "cd", "download", "decrypt",
	"disconnect", "talk", "contacts", "netmap",
	"status", "clear", "help",
]

func _input(event: InputEvent) -> void:
	if not _enabled:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			_navigate_history(-1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DOWN:
			_navigate_history(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB:
			_autocomplete()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func load_network(network: Dictionary) -> void:
	_network_data = network
	_hosts.clear()

	for host in network.get("hosts", []):
		_hosts[host.get("id", "")] = host

	# Make entry points visible
	for entry_id in network.get("entry_points", []):
		if entry_id in _hosts:
			OpState.discovered_hosts[entry_id] = _hosts[entry_id]


func activate() -> void:
	_set_enabled(true)
	output.clear()
	_print_system("BLACKSITE PHASE — TERMINAL ACTIVE")
	_print_system("Type 'help' for available commands.")
	_print_color("", COLOR_DEFAULT)
	_show_prompt()


func deactivate() -> void:
	_set_enabled(false)


# ---------------------------------------------------------------------------
# Command execution
# ---------------------------------------------------------------------------

func _on_command_submitted(text: String) -> void:
	var cmd := text.strip_edges()
	input_line.clear()

	if cmd.is_empty():
		_show_prompt()
		return

	# Add to history
	_command_history.push_front(cmd)
	if _command_history.size() > MAX_HISTORY:
		_command_history.resize(MAX_HISTORY)
	_history_index = -1

	# Echo the command
	_print_color(PROMPT_PREFIX + cmd, COLOR_DEFAULT)

	# Parse command and args
	var parts := cmd.split(" ", false)
	var command := parts[0].to_lower()
	var args: Array = parts.slice(1)

	EventBus.terminal_command.emit(command, args)

	match command:
		"help":
			_cmd_help()
		"scan":
			_cmd_scan(args)
		"probe":
			_cmd_probe(args)
		"connect":
			_cmd_connect(args)
		"login":
			_cmd_login(args)
		"exploit":
			_cmd_exploit(args)
		"ls":
			_cmd_ls()
		"cat":
			_cmd_cat(args)
		"cd":
			_cmd_cd(args)
		"download":
			await _cmd_download(args)
		"decrypt":
			_cmd_decrypt(args)
		"disconnect":
			_cmd_disconnect()
		"talk":
			_cmd_talk(args)
		"contacts":
			_cmd_contacts()
		"netmap":
			_cmd_netmap()
		"clear":
			output.clear()
		"status":
			_cmd_status()
		_:
			_print_error("Unknown command: %s" % command)
			_print_system("Type 'help' for available commands.")

	_show_prompt()


# ---------------------------------------------------------------------------
# Command implementations
# ---------------------------------------------------------------------------

func _cmd_help() -> void:
	_print_info("=== SIGNAL Terminal v1.0 ===")
	_print_color("", COLOR_DEFAULT)
	_print_color("  [color=#4488cc]RECON[/color]", COLOR_DEFAULT)
	output.push_color(COLOR_DEFAULT)
	output.append_text("  scan <subnet>             Scan subnet for hosts\n")
	output.append_text("  probe <host>              Show services on a host\n")
	output.append_text("  netmap                    Show discovered network map\n")
	output.append_text("\n")
	output.append_text("  [color=#4488cc]ACCESS[/color]\n")
	output.append_text("  connect <host> <port>     Connect to host service\n")
	output.append_text("  login <host> <user> <pw>  Login with credentials\n")
	output.append_text("  exploit <host> <cve>      Use exploit on vuln service\n")
	output.append_text("  disconnect                Disconnect from host\n")
	output.append_text("\n")
	output.append_text("  [color=#4488cc]FILES[/color]\n")
	output.append_text("  ls                        List files on host\n")
	output.append_text("  cat <file>                Read file contents\n")
	output.append_text("  cd <dir>                  Change directory\n")
	output.append_text("  download <file>           Exfiltrate file\n")
	output.append_text("  decrypt <file>            Decrypt encrypted file\n")
	output.append_text("\n")
	output.append_text("  [color=#4488cc]HUMINT[/color]\n")
	output.append_text("  contacts                  List known employees\n")
	output.append_text("  talk <name>               Social engineer an employee\n")
	output.append_text("\n")
	output.append_text("  [color=#4488cc]SYSTEM[/color]\n")
	output.append_text("  status                    Show connection & detection\n")
	output.append_text("  clear                     Clear terminal\n")
	output.append_text("  help                      Show this help\n")
	output.pop()


func _cmd_scan(args: Array) -> void:
	if args.is_empty():
		_print_error("Usage: scan <subnet>")
		return

	var target_subnet: String = args[0]
	OpState.add_detection("scan")

	_print_info("Scanning %s..." % target_subnet)

	var found := false
	for subnet in _network_data.get("subnets", []):
		if subnet.get("cidr", "") == target_subnet or subnet.get("name", "").to_lower() == target_subnet.to_lower():
			found = true
			_print_color("[+] Subnet: %s (%s)" % [subnet.get("cidr"), subnet.get("name")], COLOR_SUCCESS)

			for host_id in subnet.get("hosts", []):
				if host_id in _hosts:
					var host: Dictionary = _hosts[host_id]
					OpState.discovered_hosts[host_id] = host
					_print_color(
						"  [+] %s - %s (%s)" % [
							host.get("ip", "?.?.?.?"),
							host.get("hostname", "unknown"),
							host.get("description", host.get("os", "unknown")),
						],
						COLOR_DEFAULT,
					)
					EventBus.host_discovered.emit(host_id)

	if not found:
		_print_warning("No results for subnet: %s" % target_subnet)
		_print_system("Available subnets may be discoverable through evidence analysis.")


func _cmd_probe(args: Array) -> void:
	if args.is_empty():
		_print_error("Usage: probe <hostname|ip>")
		return

	var target: String = args[0]
	var host: Dictionary = _find_host(target)

	if host.is_empty():
		_print_error("Host not found: %s" % target)
		return

	OpState.add_detection("probe")

	_print_info("Probing %s (%s)..." % [host.get("hostname"), host.get("ip")])

	var services: Array = host.get("services", [])
	if services.is_empty():
		_print_warning("No open services detected.")
		return

	for svc in services:
		var port: int = svc.get("port", 0)
		var svc_type: String = svc.get("service_type", "unknown")
		var banner: String = svc.get("banner", "")
		var version: String = svc.get("version", "")

		var line := "  [+] %d/%s" % [port, svc_type]
		if version:
			line += " (%s)" % version
		if svc.get("vulnerable", false):
			_print_color(line + " [VULNERABLE]", COLOR_WARNING)
		else:
			_print_color(line, COLOR_DEFAULT)

		if banner:
			_print_color("      Banner: %s" % banner, COLOR_SYSTEM)


func _cmd_connect(args: Array) -> void:
	if args.size() < 2:
		_print_error("Usage: connect <hostname|ip> <port>")
		return

	var host: Dictionary = _find_host(args[0])
	if host.is_empty():
		_print_error("Host not found: %s" % args[0])
		return

	var port: int = int(args[1])
	_print_info("Connecting to %s:%d..." % [host.get("hostname"), port])

	if host.get("requires_credentials", true):
		_print_error("Connection refused — authentication required.")
		_print_system("Try: login <host> <user> <pass>")
	else:
		_connect_to_host(host)


func _cmd_login(args: Array) -> void:
	if args.size() < 3:
		_print_error("Usage: login <hostname|ip> <username> <password>")
		return

	var host: Dictionary = _find_host(args[0])
	if host.is_empty():
		_print_error("Host not found: %s" % args[0])
		return

	var username: String = args[1]
	var password: String = args[2]

	# Check credentials against host's credential list
	var valid := false
	for cred in host.get("credentials", []):
		if cred.get("username", "") == username and cred.get("password", "") == password:
			valid = true
			break

	# Also check credentials found during the operation
	for cred in OpState.found_credentials:
		if cred.get("host_id", "") == host.get("id", "") and cred.get("username", "") == username and cred.get("password", "") == password:
			valid = true
			break

	if valid:
		_print_success("Authentication successful.")
		_connect_to_host(host)
	else:
		OpState.add_detection("login_fail")
		_print_error("Authentication failed.")


func _cmd_exploit(args: Array) -> void:
	if args.size() < 2:
		_print_error("Usage: exploit <hostname|ip> <cve-id>")
		return

	var host: Dictionary = _find_host(args[0])
	if host.is_empty():
		_print_error("Host not found: %s" % args[0])
		return

	var cve: String = args[1]

	# Check if any service is vulnerable to this CVE
	var exploited := false
	for svc in host.get("services", []):
		if svc.get("vulnerable", false) and svc.get("cve_id", "") == cve:
			exploited = true
			OpState.add_detection("exploit_success")
			_print_success("Exploit successful — %s on port %d" % [svc.get("service_type"), svc.get("port")])
			_connect_to_host(host)
			break

	if not exploited:
		OpState.add_detection("exploit_fail")
		_print_error("Exploit failed — no matching vulnerability.")


func _cmd_ls() -> void:
	if _connected_host.is_empty():
		_print_error("Not connected to any host. Use 'login' or 'exploit' first.")
		return

	var files: Array = _connected_host.get("files", [])
	if files.is_empty():
		_print_system("(empty directory)")
		return

	for f in files:
		var path: String = f.get("path", "")
		# Only show files in current directory
		if path.begins_with(_current_path) or _current_path == "/":
			var display := path
			var size: int = f.get("size_kb", 1)
			var encrypted: String = " [ENCRYPTED]" if f.get("encrypted", false) else ""
			var target: String = " [TARGET]" if f.get("is_target", false) else ""
			_print_color("  %s  %dKB%s%s" % [display, size, encrypted, target], COLOR_DEFAULT)


func _cmd_cat(args: Array) -> void:
	if _connected_host.is_empty():
		_print_error("Not connected to any host.")
		return

	if args.is_empty():
		_print_error("Usage: cat <filepath>")
		return

	var target_path: String = args[0]
	var found := false

	for f in _connected_host.get("files", []):
		if f.get("path", "").ends_with(target_path) or f.get("path", "") == target_path:
			found = true
			if f.get("encrypted", false):
				_print_warning("File is encrypted (%s). Use: decrypt %s" % [f.get("cipher", "unknown"), target_path])
			else:
				_print_color(f.get("content", "(empty file)"), COLOR_DEFAULT)

				# Check if this file contains credentials
				var content: String = f.get("content", "")
				if "password" in content.to_lower() or "credential" in content.to_lower():
					_print_info("[*] Potential credentials detected in file.")
			break

	if not found:
		_print_error("File not found: %s" % target_path)


func _cmd_cd(args: Array) -> void:
	if _connected_host.is_empty():
		_print_error("Not connected to any host.")
		return

	if args.is_empty():
		_current_path = "/"
	else:
		_current_path = args[0]

	_print_system("Changed directory to: %s" % _current_path)


func _cmd_download(args: Array) -> void:
	if _connected_host.is_empty():
		_print_error("Not connected to any host.")
		return

	if args.is_empty():
		_print_error("Usage: download <filepath>")
		return

	var target_path: String = args[0]

	for f in _connected_host.get("files", []):
		if f.get("path", "").ends_with(target_path) or f.get("path", "") == target_path:
			if f.get("encrypted", false):
				_print_error("Cannot download encrypted file. Decrypt it first.")
				return

			OpState.add_detection("download")
			var file_id: String = f.get("path", target_path)
			var size_kb: int = f.get("size_kb", 1)
			_print_info("Downloading %s (%dKB)..." % [target_path, size_kb])

			# Animated progress bar
			var steps := 20
			var delay := max(0.05, min(0.15, size_kb / 1000.0))
			for i in range(steps + 1):
				var filled := "█".repeat(i)
				var empty := "░".repeat(steps - i)
				var pct := int(float(i) / steps * 100)
				output.push_color(COLOR_SUCCESS)
				# Use set_line to update in place if possible, otherwise just append
				if i < steps:
					output.append_text("\r  [%s%s] %d%%" % [filled, empty, pct])
				else:
					output.append_text("\n  [%s] 100%%\n" % filled)
				output.pop()
				await get_tree().create_timer(delay).timeout

			_print_success("File exfiltrated: %s" % target_path)
			OpState.exfiltrate_file(file_id)

			if f.get("is_target", false):
				_print_color("", COLOR_WARNING)
				_print_color("  ╔═══════════════════════════════╗", COLOR_WARNING)
				_print_color("  ║    TARGET FILE ACQUIRED       ║", COLOR_WARNING)
				_print_color("  ╚═══════════════════════════════╝", COLOR_WARNING)
				EventBus.handler_message.emit("Target file acquired. Consider exfiltrating now.", "warning")

			return

	_print_error("File not found: %s" % target_path)


func _cmd_decrypt(args: Array) -> void:
	if _connected_host.is_empty():
		_print_error("Not connected to any host.")
		return

	if args.is_empty():
		_print_error("Usage: decrypt <filepath>")
		return

	var target_path: String = args[0]
	var crypto_level: int = GameState.get_skill_level("cryptography")

	for f in _connected_host.get("files", []):
		if f.get("path", "").ends_with(target_path) or f.get("path", "") == target_path:
			if not f.get("encrypted", false):
				_print_system("File is not encrypted.")
				return

			var cipher: String = f.get("cipher", "unknown")
			# Check if player has sufficient Cryptography skill or a decrypt tool
			if crypto_level >= 2:
				f["encrypted"] = false
				_print_success("Decrypted %s (%s)" % [target_path, cipher])
				GameState.add_xp("cryptography", 20)
			else:
				_print_error("Insufficient Cryptography skill (need level 2+, have %d)." % crypto_level)
				_print_system("Find a decryption tool or level up Cryptography.")

			return

	_print_error("File not found: %s" % target_path)


func _cmd_talk(args: Array) -> void:
	if args.is_empty():
		_print_error("Usage: talk <employee name>")
		_print_system("Use 'contacts' to see available employees.")
		return

	var query: String = " ".join(args).to_lower()
	var op: Dictionary = GameState.get_current_operation()
	var target: Dictionary = op.get("blacksite_target", {})

	for emp in target.get("employees", []):
		var name: String = emp.get("name", "").to_lower()
		if query in name or name.begins_with(query):
			_print_info("Initiating contact with %s..." % emp.get("name"))
			_print_system("Opening secure channel...")
			EventBus.se_conversation_started.emit(emp.get("id", ""))
			GameState.add_xp("humint", 5)
			return

	_print_error("Employee not found: %s" % " ".join(args))
	_print_system("Use 'contacts' to see available employees.")


func _cmd_contacts() -> void:
	var op: Dictionary = GameState.get_current_operation()
	var target: Dictionary = op.get("blacksite_target", {})
	var employees: Array = target.get("employees", [])

	if employees.is_empty():
		_print_system("No employee profiles available.")
		return

	_print_info("=== Known Employees (%s) ===" % target.get("org_name", "Target"))

	for emp in employees:
		var name: String = emp.get("name", "Unknown")
		var role: String = emp.get("role", "Unknown")
		var state: Dictionary = OpState.employee_states.get(emp.get("id", ""), {})
		var trust: int = state.get("trust", 0)
		var suspicion: int = state.get("suspicion", 0)

		var trust_str := ""
		if trust > 0:
			trust_str = " [T:%d]" % trust

		var susp_color := COLOR_DEFAULT
		var susp_str := ""
		if suspicion >= 7:
			susp_str = " [SUSPICIOUS]"
			susp_color = COLOR_WARNING

		output.push_color(COLOR_INFO)
		output.append_text("  %s" % name)
		output.pop()
		output.push_color(COLOR_SYSTEM)
		output.append_text(" — %s" % role)
		output.pop()
		if trust_str:
			output.push_color(COLOR_SUCCESS)
			output.append_text(trust_str)
			output.pop()
		if susp_str:
			output.push_color(susp_color)
			output.append_text(susp_str)
			output.pop()
		output.append_text("\n")


func _cmd_netmap() -> void:
	_print_info("=== Network Topology ===")
	_print_color("", COLOR_DEFAULT)

	var subnets: Array = _network_data.get("subnets", [])
	if subnets.is_empty():
		_print_system("No network data available. Run 'scan' first.")
		return

	for subnet in subnets:
		var cidr: String = subnet.get("cidr", "???")
		var name: String = subnet.get("name", "")
		var discovered_in_subnet := 0
		var total_in_subnet: int = subnet.get("hosts", []).size()

		for host_id in subnet.get("hosts", []):
			if host_id in OpState.discovered_hosts:
				discovered_in_subnet += 1

		if discovered_in_subnet == 0:
			_print_color("  ┌─ %s (%s) [UNDISCOVERED]" % [cidr, name], COLOR_SYSTEM)
			continue

		_print_color("  ┌─ %s (%s) [%d/%d hosts]" % [cidr, name, discovered_in_subnet, total_in_subnet], COLOR_INFO)

		var host_ids: Array = subnet.get("hosts", [])
		for i in range(host_ids.size()):
			var host_id: String = host_ids[i]
			var is_last: bool = (i == host_ids.size() - 1)
			var prefix := "  └── " if is_last else "  ├── "

			if host_id in OpState.discovered_hosts:
				var host: Dictionary = OpState.discovered_hosts[host_id]
				var hostname: String = host.get("hostname", "???")
				var ip: String = host.get("ip", "?.?.?.?")
				var connected_marker := " ◄── CONNECTED" if host.get("id") == OpState.connected_host_id else ""

				var host_color := COLOR_SUCCESS if connected_marker else COLOR_DEFAULT
				_print_color("%s%s (%s)%s" % [prefix, hostname, ip, connected_marker], host_color)

				# Show services if probed
				var services: Array = host.get("services", [])
				for svc in services:
					var svc_prefix := "  │   " if not is_last else "      "
					var port: int = svc.get("port", 0)
					var svc_type: String = svc.get("service_type", "?")
					var vuln := " [VULN]" if svc.get("vulnerable", false) else ""
					var svc_color := COLOR_WARNING if vuln else COLOR_SYSTEM
					_print_color("%s  :%d/%s%s" % [svc_prefix, port, svc_type, vuln], svc_color)
			else:
				_print_color("%s[undiscovered host]" % prefix, COLOR_SYSTEM)

		_print_color("", COLOR_DEFAULT)


func _cmd_disconnect() -> void:
	if _connected_host.is_empty():
		_print_system("Not connected to any host.")
		return

	var hostname: String = _connected_host.get("hostname", "unknown")
	_connected_host = {}
	_current_path = "/"
	OpState.connected_host_id = ""
	_print_system("Disconnected from %s." % hostname)


func _cmd_status() -> void:
	_print_info("=== Status ===")

	if _connected_host.is_empty():
		_print_system("  Host: (not connected)")
	else:
		_print_color("  Host: %s (%s)" % [_connected_host.get("hostname"), _connected_host.get("ip")], COLOR_DEFAULT)
		_print_color("  Path: %s" % _current_path, COLOR_DEFAULT)

	_print_color("  Detection: %.0f%%" % (OpState.detection_value * 100), _get_detection_color())
	_print_color("  Files exfiltrated: %d" % OpState.exfiltrated_files.size(), COLOR_DEFAULT)
	_print_color("  Hosts discovered: %d" % OpState.discovered_hosts.size(), COLOR_DEFAULT)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_host(query: String) -> Dictionary:
	for host in OpState.discovered_hosts.values():
		if host.get("hostname", "") == query or host.get("ip", "") == query or host.get("id", "") == query:
			return host
	return {}


func _connect_to_host(host: Dictionary) -> void:
	_connected_host = host
	_current_path = "/"
	OpState.connected_host_id = host.get("id", "")
	EventBus.host_connected.emit(host.get("id", ""))
	_print_color("Connected to %s (%s)" % [host.get("hostname"), host.get("ip")], COLOR_SUCCESS)
	GameState.add_xp("network_exploitation", 10)


func _set_enabled(enabled: bool) -> void:
	_enabled = enabled
	input_line.editable = enabled
	if enabled:
		input_line.grab_focus()


func _show_prompt() -> void:
	if _connected_host.is_empty():
		input_line.placeholder_text = PROMPT_PREFIX
	else:
		input_line.placeholder_text = "%s@%s:%s$ " % [
			"root",
			_connected_host.get("hostname", "proxy"),
			_current_path,
		]


func _autocomplete() -> void:
	var text: String = input_line.text.strip_edges()
	if text.is_empty():
		return

	var parts := text.split(" ", false)
	if parts.size() == 1:
		# Autocomplete command name
		var partial: String = parts[0].to_lower()
		var matches: Array[String] = []
		for cmd in ALL_COMMANDS:
			if cmd.begins_with(partial):
				matches.append(cmd)

		if matches.size() == 1:
			input_line.text = matches[0] + " "
			input_line.caret_column = input_line.text.length()
		elif matches.size() > 1:
			_print_system("  ".join(matches))

	elif parts.size() >= 2:
		# Autocomplete arguments (hostnames, file paths, employee names)
		var cmd: String = parts[0].to_lower()
		var partial: String = parts[-1].to_lower()

		match cmd:
			"scan":
				# Autocomplete subnet CIDRs
				var subnets: Array[String] = []
				for subnet in _network_data.get("subnets", []):
					var cidr: String = subnet.get("cidr", "")
					if cidr.to_lower().begins_with(partial) or subnet.get("name", "").to_lower().begins_with(partial):
						subnets.append(cidr)
				_apply_autocomplete(parts, subnets)

			"probe", "connect", "login", "exploit":
				# Autocomplete hostnames/IPs
				var hosts: Array[String] = []
				for host in OpState.discovered_hosts.values():
					var hostname: String = host.get("hostname", "")
					var ip: String = host.get("ip", "")
					if hostname.to_lower().begins_with(partial):
						hosts.append(hostname)
					elif ip.begins_with(partial):
						hosts.append(ip)
				_apply_autocomplete(parts, hosts)

			"cat", "download", "decrypt":
				# Autocomplete file paths
				if not _connected_host.is_empty():
					var paths: Array[String] = []
					for f in _connected_host.get("files", []):
						var path: String = f.get("path", "")
						if path.to_lower().find(partial) >= 0:
							paths.append(path)
					_apply_autocomplete(parts, paths)

			"talk":
				# Autocomplete employee names
				var names: Array[String] = []
				var op: Dictionary = GameState.get_current_operation()
				var target: Dictionary = op.get("blacksite_target", {})
				for emp in target.get("employees", []):
					var name: String = emp.get("name", "")
					if name.to_lower().begins_with(partial) or name.split(" ")[0].to_lower().begins_with(partial):
						names.append(name.split(" ")[0])
				_apply_autocomplete(parts, names)


func _apply_autocomplete(parts: Array, matches: Array[String]) -> void:
	if matches.size() == 1:
		parts[-1] = matches[0]
		input_line.text = " ".join(parts) + " "
		input_line.caret_column = input_line.text.length()
	elif matches.size() > 1:
		_print_system("  ".join(matches))


func _navigate_history(direction: int) -> void:
	if _command_history.is_empty():
		return

	_history_index = clamp(_history_index + direction, -1, _command_history.size() - 1)

	if _history_index == -1:
		input_line.text = ""
	else:
		input_line.text = _command_history[_history_index]
		input_line.caret_column = input_line.text.length()


func _get_detection_color() -> Color:
	match OpState.detection_level:
		"green": return COLOR_SUCCESS
		"yellow": return COLOR_WARNING
		"red": return COLOR_ERROR
		"black": return Color(0.9, 0.1, 0.1)
	return COLOR_DEFAULT


# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

func _print_color(text: String, color: Color) -> void:
	output.push_color(color)
	output.append_text(text + "\n")
	output.pop()
	EventBus.terminal_output.emit(text, "")

func _print_error(text: String) -> void:
	_print_color("[!] " + text, COLOR_ERROR)

func _print_warning(text: String) -> void:
	_print_color("[!] " + text, COLOR_WARNING)

func _print_info(text: String) -> void:
	_print_color("[*] " + text, COLOR_INFO)

func _print_system(text: String) -> void:
	_print_color("--- " + text, COLOR_SYSTEM)

func _print_success(text: String) -> void:
	_print_color("[+] " + text, COLOR_SUCCESS)


# ---------------------------------------------------------------------------
# Phase handler
# ---------------------------------------------------------------------------

func _on_phase_changed(new_phase: String) -> void:
	match new_phase:
		"blacksite":
			activate()
		_:
			deactivate()


func _on_burned() -> void:
	_print_color("", COLOR_ERROR)
	_print_color("╔══════════════════════════════════════╗", COLOR_ERROR)
	_print_color("║          ANALYST BURNED              ║", COLOR_ERROR)
	_print_color("║   Cover identity compromised.        ║", COLOR_ERROR)
	_print_color("║   Connection terminated.             ║", COLOR_ERROR)
	_print_color("╚══════════════════════════════════════╝", COLOR_ERROR)
	_set_enabled(false)
