extends RefCounted
## Reads the accounts server's address and secret from config/server.local.cfg (not committed to Git).
## Kept in its own file, not on CloudSync, so the patched scripts work with the copy of CloudSync in the app.

const LOCAL_CONFIG := "res://config/server.local.cfg"
const ADDRESSES_FILE := "res://config/server_addresses.json"  # the addresses to try, in order; no secret here
const CHOSEN_FILE := "user://server.json"  # the address that answered last time


# The server's address without a trailing slash, or "" when there is no server.
# This is the address the game is using now: the one that answered last time, else the first in the list.
# Passwords and the secret go with every request, so only an encrypted address (https) is used.
# Plain http is allowed for localhost only, for tests on this PC.
static func url() -> String:
	var list := urls()
	var address := _chosen()
	if not list.has(address):
		address = str(list[0]) if not list.is_empty() else ""
	address = address.rstrip("/")
	if address == "" or _is_secure(address):
		return address
	if not _warned:
		push_warning("Server address must start with https://; the server is not used")
		_warned = true
	return ""


# Every address the game may use: the one in server.local.cfg first, then the list in server_addresses.json
static func urls() -> Array:
	var list: Array = []
	var primary := _setting("url").rstrip("/")
	if primary != "":
		list.append(primary)
	var file := FileAccess.open(ADDRESSES_FILE, FileAccess.READ)
	if file != null:
		var data = JSON.parse_string(file.get_as_text())
		if data is Dictionary and data.get("addresses") is Array:
			for address in data["addresses"]:
				var text := str(address).rstrip("/")
				if text != "" and not list.has(text):
					list.append(text)
	return list


# Called when the server does not answer: the next address is tried the next time, and the choice is remembered
static func next_url() -> void:
	var list := urls()
	if list.size() < 2:
		return
	var index := list.find(url())
	_remember(str(list[(index + 1) % list.size()]))


# The address that failed recently is skipped for a while. Otherwise the first address (the Tailscale one) wins again,
# so a phone that once fell back to the public address goes back to the tailnet, where tester logins are known.
const FALLBACK_SECONDS := 300.0

static func _chosen() -> String:
	var file := FileAccess.open(CHOSEN_FILE, FileAccess.READ)
	if file == null:
		return ""
	var data = JSON.parse_string(file.get_as_text())
	if not (data is Dictionary) or Time.get_unix_time_from_system() - float(data.get("at", 0.0)) > FALLBACK_SECONDS:
		return ""
	return str(data.get("url", ""))


static func _remember(address: String) -> void:
	var file := FileAccess.open(CHOSEN_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"url": address, "at": Time.get_unix_time_from_system()}))


static var _warned := false  # the warning is shown once, not on every request


# https, or a local address on this PC. The local address must end there, so localhost.example.com does not pass.
static func _is_secure(address: String) -> bool:
	if address.begins_with("https://"):
		return true
	for local in ["http://localhost", "http://127.0.0.1"]:
		if address == local or address.begins_with(local + ":") or address.begins_with(local + "/"):
			return true
	return false


# The secret the server expects with every request, or "" when the server has none
static func secret() -> String:
	return _setting("secret")


static func _setting(key: String) -> String:
	var config := ConfigFile.new()
	if config.load(LOCAL_CONFIG) != OK:
		return ""
	return str(config.get_value("server", key, ""))
