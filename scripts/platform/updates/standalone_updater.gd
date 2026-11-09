extends Node
## Standalone patch updater for already-installed Engine Builder
## Can be run separately: godot --headless --script res://scripts/platform/updates/standalone_updater.gd

const PATCH_DIR := "user://patch"
const STATE_FILE := "user://patch/state.json"
const PUBLIC_KEY := """-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxSd7mHNZeGw/awip9yZJ
eB91dXxvGAVmP1NqaJ5MxZVDegVCDRRrKIEc5i99CvzjpKP8qtni3O4TW9D+izYg
Llycx6khEgMZekpWwMzEjrqVMf5kqdtA+VL6KNv/5ugq+Ue0xQeR6meTpsE1k4Jl
mRUYznPfTOsvzwWGeAxBZgaN4XJ8Drxt6IkVElvb9kKuBVSWbDuj1ZRbYVqpM0ez
mAQF+Vbg76V3I7OCotW3t9xPBYyrbr8b9YugLmtRg6t88EKWY9gfz3HV58MnF/yo
asn5BEskzSmEELlhmULCtArWQLiK7qmpTSBEw+9Si/WOU+DH/1Vl9UCXmhoztClm
hQIDAQAB
-----END PUBLIC KEY-----"""

const CHECK_URL := "https://your-server.com/engine-builder/patches/manifest.json"

var _http: HTTPRequest
var _patch_key := ""
var _patch_url: String
var _patch_version: String
var _patch_size: int
var _patch_sha256: String
var _manifest: Dictionary

func _ready() -> void:
	print("[Updater] Starting standalone patch check...")
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_manifest_response)
	
	var headers = ["Accept: application/json"]
	_http.request(CHECK_URL, headers, HTTPClient.METHOD_GET)
	await get_tree().create_timer(30.0).timeout
	print("[Updater] Timeout - no response")
	get_tree().quit(1)
func _on_manifest_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		print("[Updater] Request failed: %s" % "result %d" % result)
		get_tree().quit(1)
	
	if response_code != 200:
		print("[Updater] HTTP %d" % response_code)
		get_tree().quit(1)
	
	var json = JSON.parse_string(body.get_string_from_utf8())
	if not json or not json is Dictionary:
		print("[Updater] Invalid manifest JSON")
		get_tree().quit(1)
	
	_manifest = json
	var current_version = ProjectSettings.get_setting("application/config/version", "0.1.0")
	print("[Updater] Current version: %s, Latest: %s" % [current_version, _manifest.latest_version])
	
	if _version_compare(current_version, _manifest.latest_version) >= 0:
		print("[Updater] Already up to date")
		get_tree().quit(0)
	
	# Find applicable patch
	var patches = _manifest.patches
	var patch_key = ""
	for key in patches:
		if _version_compare(current_version, key) >= 0:
			patch_key = key
	
	if patch_key == "":
		print("[Updater] No delta patch available for %s, need full installer" % current_version)
		print("[Updater] Full installer: %s" % _manifest.full_installer)
		get_tree().quit(2)  # Exit code 2 = full installer needed
	
	_patch_url = "%s/%s" % [_manifest.base_url, patches[patch_key]]
	_patch_version = _manifest.latest_version
	_patch_size = _manifest.patch_sizes[patch_key] if _manifest.has("patch_sizes") else 0
	_patch_sha256 = _manifest.patch_sha256[patch_key] if _manifest.has("patch_sha256") else ""
	
	_patch_key = patch_key
	print("[Updater] Found delta patch from %s to %s (%s bytes)" % [patch_key, _patch_version, _patch_size])
	_download_patch()

func _download_patch() -> void:
	var partial_path = ProjectSettings.globalize_path("%s/game.pck.part" % PATCH_DIR)
	var final_path = ProjectSettings.globalize_path("%s/game.pck" % PATCH_DIR)
	
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PATCH_DIR))
	
	var file = FileAccess.open(partial_path, FileAccess.WRITE)
	if not file:
		print("[Updater] Cannot create patch file")
		get_tree().quit(1)
	file.close()
	
	_http.request_completed.disconnect(_on_manifest_response)
	_http.request_completed.connect(_on_patch_downloaded)
	
	var headers = ["Accept: application/octet-stream"]
	_http.request(_patch_url, headers, HTTPClient.METHOD_GET)
	print("[Updater] Downloading patch...")
	await get_tree().create_timer(300.0).timeout
	print("[Updater] Download timeout")
	get_tree().quit(1)

func _on_patch_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		print("[Updater] Download failed: %s" % "result %d" % result)
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/game.pck.part" % PATCH_DIR))
		get_tree().quit(1)
	
	if response_code != 200:
		print("[Updater] HTTP %d" % response_code)
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/game.pck.part" % PATCH_DIR))
		get_tree().quit(1)
	
	var partial_path = ProjectSettings.globalize_path("%s/game.pck.part" % PATCH_DIR)
	var final_path = ProjectSettings.globalize_path("%s/game.pck" % PATCH_DIR)
	
	var file = FileAccess.open(partial_path, FileAccess.WRITE)
	if not file:
		print("[Updater] Cannot write patch")
		get_tree().quit(1)
	file.store_buffer(body)
	file.close()
	
	# Verify checksum
	if _patch_sha256 != "":
		var hashing = HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(body)
		var actual = hashing.finish().hex_encode()
		if actual != _patch_sha256:
			print("[Updater] Checksum mismatch! Expected %s, got %s" % [_patch_sha256, actual])
			DirAccess.remove_absolute(partial_path)
			get_tree().quit(1)
	
	# Verify signature
	if not _verify_signature(partial_path, _manifest.signatures[_patch_key] if _manifest.has("signatures") else ""):
		print("[Updater] Signature verification failed")
		DirAccess.remove_absolute(partial_path)
		get_tree().quit(1)
	
	# Move to final location
	DirAccess.remove_absolute(final_path)
	DirAccess.rename_absolute(partial_path, final_path)
	
	# Write state
	var state = {
		"version": _patch_version,
		"sha256": _patch_sha256,
		"engine": _engine_version(),
		"delta": true
	}
	_write_state(state)
	
	print("[Updater] Patch applied successfully! Version: %s" % _patch_version)
	print("[Updater] Restart the application to load the update")
	get_tree().quit(0)

func _verify_signature(path: String, signature_b64: String) -> bool:
	if signature_b64 == "":
		return false
	var key = CryptoKey.new()
	if key.load_from_string(PUBLIC_KEY, true) != OK:
		return false
	var hashing = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(FileAccess.get_file_as_bytes(path))
	return Crypto.new().verify(HashingContext.HASH_SHA256, hashing.finish(), Marshalls.base64_to_raw(signature_b64), key)

func _engine_version() -> String:
	var v = Engine.get_version_info()
	return "%d.%d.%d" % [v["major"], v["minor"], v["patch"]]

func _version_compare(a: String, b: String) -> int:
	var va: Array = Array(a.split(".")).map(func(s): return int(s))
	var vb: Array = Array(b.split(".")).map(func(s): return int(s))
	for i in range(3):
		if va[i] < vb[i]: return -1
		if va[i] > vb[i]: return 1
	return 0

func _write_state(state: Dictionary) -> void:
	var file = FileAccess.open(ProjectSettings.globalize_path(STATE_FILE), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(state))
		file.close()