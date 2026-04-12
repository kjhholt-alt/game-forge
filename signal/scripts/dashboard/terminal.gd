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

@onready var output: RichTextLabel = $Output
@onready var input_line: LineEdit = $InputLine


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


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func load_network(network: Dictionary) -> void:
	"""Load network topology data for command resolution."""
	_network_data = network
	_hosts.clear()

	for host in network.get("hosts", []):
		_hosts[host.get("id", "")] = host

	# Make entry points visible
	for entry_id in network.get("entry_points", []):
		if entry_id in _hosts:
			OpState.discovered_hosts[entry_id] = _hosts[entry_id]


func activate() -> void:
	"""Enable the terminal for BLACKSITE phase."""
	_set_enabled(true)
	output.clear()
	_print_system("BLACKSITE PHASE — TERMINAL ACTIVE")
	_print_system("Type 'help' for available commands.")
	_print_color("", COLOR_DEFAULT)
	_show_prompt()


func deactivate() -> void:
	"""Disable the terminal."""
	_set_enabled(false)


# ---------------------------------------------------------------------------
# Command execution
# ---------------------------------------------------------------------------

func _on_command_submitted(text: String) -> void:
	"""Parse and execute a terminal command."""
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
			_cmd_download(args)
		"decrypt":
			_cmd_decrypt(args)
		"disconnect":
			_cmd_disconnect()
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
	_print_info("=== SIGNAL Terminal Commands ===")
	_print_color("  scan <subnet>           Scan subnet for hosts", COLOR_DEFAULT)
	_print_color("  probe <host>            Show services on a host", COLOR_DEFAULT)
	_print_color("  connect <host> <port>   Connect to host service", COLOR_DEFAULT)
	_print_color("  login <host> <user> <pass>  Login with credentials", COLOR_DEFAULT)
	_print_color("  exploit <host> <cve>    Use exploit on vulnerable service", COLOR_DEFAULT)
	_print_color("  ls                      List files on connected host", COLOR_DEFAULT)
	_print_color("  cat <file>              Read file contents", COLOR_DEFAULT)
	_print_color("  cd <dir>                Change directory", COLOR_DEFAULT)
	_print_color("  download <file>         Exfiltrate file (takes time)", COLOR_DEFAULT)
	_print_color("  decrypt <file>          Decrypt encrypted file", COLOR_DEFAULT)
	_print_color("  disconnect              Disconnect from current host", COLOR_DEFAULT)
	_print_color("  status                  Show connection and detection status", COLOR_DEFAULT)
	_print_color("  clear                   Clear terminal", COLOR_DEFAULT)
	_print_color("  help                    Show this help", COLOR_DEFAULT)


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
			_print_info("Downloading %s..." % target_path)
			_print_color("[████████████████████] 100%%", COLOR_SUCCESS)
			_print_success("File exfiltrated: %s" % target_path)
			OpState.exfiltrate_file(file_id)

			if f.get("is_target", false):
				_print_color("[!] TARGET FILE ACQUIRED", COLOR_WARNING)

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
	"""Find a host by hostname, IP, or ID in discovered hosts."""
	for host in OpState.discovered_hosts.values():
		if host.get("hostname", "") == query or host.get("ip", "") == query or host.get("id", "") == query:
			return host
	return {}


func _connect_to_host(host: Dictionary) -> void:
	"""Establish connection to a host."""
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


func _navigate_history(direction: int) -> void:
	"""Navigate command history with up/down arrows."""
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
