class_name EngineLibrary
extends RefCounted

## Fetches and caches the engine library (presets) from the server.
## Merges server extras on top of built-in Presets.PRESETS.

# v2 caches only the server's data. The old file also stored bundled presets, which went stale when they changed.
const CACHE_FILE := "user://engine_library_v2.json"
const FETCH_TIMEOUT := 10.0 # seconds
const SERVER_SETTINGS := preload("res://scripts/platform/user/server_settings.gd")

var _http: HTTPRequest
var _library: Dictionary = {}
var _server_data: Dictionary = {} # the server's entries as last received; the only thing cached
var _loading := false
var _ready := false

signal library_ready(library: Dictionary) # emitted when library is loaded (bundled + server extras)

static var _instance

static func get_instance():
	if _instance == null:
		_instance = load("res://scripts/presets/engine_library.gd").new()
	return _instance

func _init() -> void:
	_load_bundled()
	_load_cache()
	_ready = true
	call_deferred("_emit_ready")

func _emit_ready() -> void:
	library_ready.emit(get_library())

func _load_bundled() -> void:
	_library = Presets.PRESETS.duplicate(true)

# Starts fetching server extras. Does nothing if already loading.
func fetch() -> void:
	if _loading:
		return
	var base: String = SERVER_SETTINGS.url()
	if base == "":
		return
	_loading = true
	call_deferred("_start_request", base)

func _start_request(base: String) -> void:
	_http = HTTPRequest.new()
	_http.timeout = FETCH_TIMEOUT
	(Engine.get_main_loop() as SceneTree).root.add_child(_http)
	_http.request_completed.connect(_on_fetched, CONNECT_ONE_SHOT)
	if _http.request(base + "/patch/library", SERVER_SETTINGS.headers(), HTTPClient.METHOD_GET) != OK:
		_loading = false
		_http.free()
		_http = null

func _on_fetched(result: int, code: int, _headers: PackedStringArray, raw: PackedByteArray) -> void:
	_loading = false
	if _http != null:
		_http.queue_free()
		_http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var lib = JSON.parse_string(raw.get_string_from_utf8())
	if not (lib is Dictionary) or lib.is_empty():
		return
	# Server entries keyed by id replace the bundled preset. An older copy keyed by
	# display name is the same engine and is left out, so the menu does not list it twice.
	_server_data = lib
	_library = _merge_extras(lib)
	_save_cache()
	# Library already emitted on init; merged update is silent

func get_library() -> Dictionary:
	if _library.is_empty():
		return {}
	return _library.duplicate(true)

func is_ready() -> bool:
	return _ready

func _load_cache() -> void:
	var file := FileAccess.open(CACHE_FILE, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if data is Dictionary and not data.is_empty():
		_server_data = data
		_library = _merge_extras(data)


# Bundled presets stay keyed by id. An incoming entry with the same id replaces one.
# An entry whose name is already present under a different key is an old duplicate.
func _merge_extras(extra: Dictionary) -> Dictionary:
	var merged := Presets.PRESETS.duplicate(true)
	var known_names := {}
	for id in merged:
		var preset: Dictionary = merged[id]
		known_names[str(preset.get("display_name", id))] = true
	for key in extra:
		var entry = extra[key]
		if not (entry is Dictionary):
			continue
		if merged.has(key):
			var revision: Variant = entry.get("preset_revision", 0)
			var incoming_revision := int(revision) if revision is int or revision is float else 0
			if incoming_revision < int(merged[key].get("preset_revision", 0)):
				continue
			# Older server library entries may predate the bundled tyre dimensions.
			# Keep explicit server values, while retaining missing bundled dimensions.
			var combined: Dictionary = entry.duplicate(true)
			for field in ["throttle_bore_mm", "throttle_count", "runner_bore_mm", "rider_kg", "vehicle_mass_includes_rider"]:
				if not combined.has(field) and merged[key].has(field):
					combined[field] = merged[key][field]
			for field in ["wheelbase_mm", "front_tire_width_mm", "rear_tire_width_mm", "front_tire_aspect", "rear_tire_aspect", "front_rim_in", "rear_rim_in"]:
				if not combined.has(field) and merged[key].has(field):
					combined[field] = merged[key][field]
			merged[key] = combined
			known_names[str(entry.get("display_name", key))] = true
			continue
		var name := str(entry.get("display_name", key))
		if known_names.has(name):
			continue
		merged[key] = entry
		known_names[name] = true
	return merged

func _save_cache() -> void:
	var file := FileAccess.open(CACHE_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_server_data))
