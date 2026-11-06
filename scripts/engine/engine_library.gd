class_name EngineLibrary
extends RefCounted

## Fetches and caches the engine library (presets) from the server.
## Falls back to the built-in Presets.PRESETS when the server is unreachable.

const CACHE_FILE := "user://engine_library.json"
const FETCH_TIMEOUT := 10.0 # seconds

var _http: HTTPRequest
var _library: Dictionary = {}
var _loading := false
var _ready := false
var _fallback_used := false

signal library_ready(library: Dictionary) # emitted when library is loaded (from server or fallback)

static var _instance: EngineLibrary

static func get_instance() -> EngineLibrary:
	if _instance == null:
		_instance = EngineLibrary.new()
	return _instance

func _init() -> void:
	_load_cache()
	_ready = not _library.is_empty()
	if _ready:
		call_deferred("_emit_ready")

func _emit_ready() -> void:
	library_ready.emit(_library)

# Starts fetching the library from the server. Does nothing if already loading or ready with server data.
func fetch() -> void:
	if _loading or (_ready and not _fallback_used):
		return
	var base: String = ServerSettings.url()
	if base == "":
		_use_fallback()
		return
	_loading = true
	_http = HTTPRequest.new()
	_http.timeout = FETCH_TIMEOUT
	# Don't add as child - RefCounted can't have children. Just keep reference.
	_http.request_completed.connect(_on_fetched, CONNECT_ONE_SHOT)
	if _http.request(base + "/patch/library", ServerSettings.headers(), HTTPClient.METHOD_GET) != OK:
		_loading = false
		_use_fallback()

func _on_fetched(result: int, code: int, _headers: PackedStringArray, raw: PackedByteArray) -> void:
	_loading = false
	if _http != null:
		_http.free()
		_http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_use_fallback()
		return
	var lib = JSON.parse_string(raw.get_string_from_utf8())
	if not (lib is Dictionary) or lib.is_empty():
		_use_fallback()
		return
	_library = lib
	_save_cache()
	_fallback_used = false
	_ready = true
	call_deferred("_emit_ready")

func _use_fallback() -> void:
	if _ready and not _fallback_used:
		return # already have server data
	_library = Presets.PRESETS
	_fallback_used = true
	_ready = true
	call_deferred("_emit_ready")

func get_library() -> Dictionary:
	return _library

func is_using_fallback() -> bool:
	return _fallback_used

func is_ready() -> bool:
	return _ready

func _load_cache() -> void:
	var file := FileAccess.open(CACHE_FILE, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if data is Dictionary and not data.is_empty():
		_library = data

func _save_cache() -> void:
	var file := FileAccess.open(CACHE_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_library))
