extends Node
# Use the global ServerSettings class directly (class_name in server_settings.gd)
## Hot fixes: the app downloads a finished game patch (a Godot .pck of the game's scripts, scenes and data)
## from the server, and loads it the next time the app starts. The engine and the Android parts stay as
## they are, so a patch is a few megabytes instead of a new APK.
##
## What the player sees: while the app runs it checks the server about once a minute. When a final patch is
## ready it shows "Update ongoing" with a progress bar, then "Update ready" with Restart and Ignore.
## - Restart reopens the app by itself (on Android it asks for a new start, then ends this process); the
##   patch is applied when it opens.
## - Ignore hides the prompt; the patch is applied the next time the app starts anyway.
##
## Rules, so a bad patch cannot break the game:
## - Only patches the server marks as final are offered. Draft patches stay on the server.
## - A patch loads only if it was built for the same Godot version as the app.
## - A patch must match the checksum the server gave for it, or it is deleted.
## - If a patch fails to load, it is deleted and the built-in game runs.
## - Keep the class names the same across patches: a patch cannot add new class_name scripts that the
##   built-in cache does not know about. Publish a new APK for those.

const PATCH_DIR := "user://patch"
const PATCH_FILE := "user://patch/game.pck"
const PARTIAL_FILE := "user://patch/game.pck.part"
const STATE_FILE := "user://patch/state.json"  # {version, sha256, engine, delta} of the patches on disk
const DELTA_FILE := "user://patch/delta.pck"  # a small patch on top of the base: only the changed files
const DELTA_PARTIAL := "user://patch/delta.pck.part"
const CHECK_SECONDS := 30.0  # how often the app asks the server for a new patch while it runs
const SERVER_SETTINGS := preload("res://scripts/platform/user/server_settings.gd")
# The update key's public half (server/make_signing_key.py). Only patches signed with the private key are loaded.
const PUBLIC_KEY := """-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxSd7mHNZeGw/awip9yZJ
eB91dXxvGAVmP1NqaJ5MxZVDegVCDRRrKIEc5i99CvzjpKP8qtni3O4TW9D+izYg
Llycx6khEgMZekpWwMzEjrqVMf5kqdtA+VL6KNv/5ugq+Ue0xQeR6meTpsE1k4Jl
mRUYznPfTOsvzwWGeAxBZgaN4XJ8Drxt6IkVElvb9kKuBVSWbDuj1ZRbYVqpM0ez
mAQF+Vbg76V3I7OCotW3t9xPBYyrbr8b9YugLmtRg6t88EKWY9gfz3HV58MnF/yo
asn5BEskzSmEELlhmULCtArWQLiK7qmpTSBEw+9Si/WOU+DH/1Vl9UCXmhoztClm
hQIDAQAB
-----END PUBLIC KEY-----"""

var _http: HTTPRequest
var _offered := {}  # the server's description of the patch being downloaded
var _installed := {}  # the patch on disk, if any
var _busy := false  # a request to the server is in progress
var _check_wait := 5.0  # seconds until the next check (the first one comes soon after start)
var _panel: PanelContainer
var _blocker: ColorRect # full-screen, stops taps behind the update notice
var _title: Label
var _body: Label
var _bar: ProgressBar
var _restart_button: Button
var _ignore_button: Button
var _startup := false  # the check when the app starts: a new version restarts the game by itself
# The launcher (scenes/launcher.tscn) runs the check and the download itself, with a PLAY button at the end.
# It opens on every platform except the editor, and not after a PLAY that followed an update (Windows only).
signal launcher_no_update
signal launcher_offline  # the server could not be asked, so no update was checked
signal launcher_update_found(size_bytes: int)
signal launcher_finished(ok: bool)
var launcher_mode := not OS.has_feature("editor") and not OS.get_cmdline_user_args().has("--play")
var launcher_hold := launcher_mode  # no background checks while the launcher is open
var launcher_updated := false  # an update was downloaded while the launcher was open
var progress_got := 0  # the running download, for the launcher's progress bar
var progress_total := 0
var progress_speed := 0.0
# The start-up check shows on the game's loading bar: the loading screen reads these while it waits
var _pending_reload := false  # an update is downloaded and waits for the main menu to be applied
var startup_busy := false  # the check or its download is still running
var startup_text := ""  # what the loading screen says, such as "Downloading update 40%"
var startup_fraction := 0.0  # how far the start-up download has got, 0 to 1
var _speed := 0.0  # download speed in bytes per second, measured about once a second
var _speed_msec := 0
var _speed_bytes := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PATCH_DIR))
	_load_installed()
	_http = HTTPRequest.new()
	_http.timeout = 120.0
	add_child(_http)
	_build_panel()
	# The start-up check keeps running while the game is paused for it
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not launcher_mode and not _skip_patches():
		_startup_check()


# The patch on disk is loaded before the game starts, so its scripts and scenes replace the built-in ones
# Run from the editor, the scripts on disk must run as written: a patch the installed game left in this PC's user
# data would replace them, and the app would download and restart for patches here. A test that needs the patch
# flow passes "-- --use-patch".
static func _skip_patches() -> bool:
	return OS.get_name() == "Linux" or (OS.has_feature("editor") and not OS.get_cmdline_user_args().has("--use-patch"))


func _load_installed() -> void:
	if _skip_patches():
		return
	_installed = _read_state()
	if _installed.is_empty() or not FileAccess.file_exists(PATCH_FILE):
		return
	if FileAccess.get_sha256(PATCH_FILE) != str(_installed.get("sha256", "")) or str(_installed.get("engine", "")) != _engine_version() \
			or not signature_ok(PATCH_FILE, str(_installed.get("signature", ""))):
		_discard()
		return
	if not ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(PATCH_FILE), true):
		push_warning("Patch %s would not load; using the built-in game" % str(_installed.get("version", "")))
		_discard()
		return
	_mount_delta()
	print("Patch %s loaded" % str(_installed.get("version", "")))


func _process(delta: float) -> void:
	# A downloaded update waits for the main menu, then is applied there
	if _pending_reload and _on_main_menu():
		_restart_app()
	if _busy:
		if _panel.visible or _startup:
			_show_progress()
		return
	if launcher_hold:
		return
	_check_wait -= delta
	if _check_wait <= 0.0:
		_check_wait = CHECK_SECONDS
		_check_server()


# Shows the download's size, percentage and speed in the update panel, about once a frame
func _show_progress() -> void:
	var got := _http.get_downloaded_bytes()
	var total := _http.get_body_size()
	var now := Time.get_ticks_msec()
	if now - _speed_msec >= 1000:
		_speed = float(got - _speed_bytes) * 1000.0 / float(maxi(now - _speed_msec, 1))
		_speed_msec = now
		_speed_bytes = got
	progress_got = got
	progress_total = total
	progress_speed = _speed
	if _startup:
		startup_fraction = float(got) / float(total) if total > 0 else 0.0
		startup_text = "Update ongoing\nPatch %d: %s of %s (%d%%), %s/s. You can keep playing." % [
			int(_offered.get("version", 0)), _megabytes(got), _megabytes(maxi(total, 0)),
			int(startup_fraction * 100.0), _megabytes(int(_speed))]
		return
	if total > 0:
		_bar.value = 100.0 * float(got) / float(total)
		_body.text = "Patch %d: %s of %s (%d%%), %s/s. You can keep playing." % [
			int(_offered.get("version", 0)), _megabytes(got), _megabytes(total), int(_bar.value), _megabytes(int(_speed))]
	else:
		_body.text = "Patch %d: %s so far, %s/s. You can keep playing." % [
			int(_offered.get("version", 0)), _megabytes(got), _megabytes(int(_speed))]


static func _megabytes(bytes: int) -> String:
	return "%.2f MB" % (float(bytes) / 1048576.0)


func _check_server() -> void:
	var base := SERVER_SETTINGS.url()
	if base == "" or _busy or _skip_patches():
		return  # no server: the built-in game only
	_busy = true
	_http.request_completed.connect(_on_info, CONNECT_ONE_SHOT)
	if _http.request(base + _channel_path("info"), _headers(), HTTPClient.METHOD_GET) != OK:
		_busy = false
		_http.request_completed.disconnect(_on_info)


func _on_info(result: int, code: int, _resp_headers: PackedStringArray, raw: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return  # offline or no patch published
	var info = JSON.parse_string(raw.get_string_from_utf8())
	var offer := choose_offer(info, _installed, _engine_version())
	if offer.is_empty():
		return
	_offered = offer
	_download()


# What to take from the server: a delta on top of the base the app has, or the full base when the app is behind it.
# Old apps only read the top-level base, so they keep taking full patches as before.
static func choose_offer(info, installed: Dictionary, engine: String) -> Dictionary:
	if not (info is Dictionary) or not bool(info.get("final", false)) or str(info.get("engine", "")) != engine:
		return {}
	var base_now := int(installed.get("version", 0))
	var delta = info.get("delta")
	if delta is Dictionary and bool(delta.get("final", false)) and int(delta.get("base_version", -1)) == base_now:
		var have_delta := int((installed.get("delta", {}) as Dictionary).get("version", 0))
		if int(delta.get("version", 0)) > have_delta and str(delta.get("signature", "")) != "":
			return {"kind": "delta", "version": int(delta["version"]), "sha256": str(delta["sha256"]), "engine": engine, "signature": str(delta.get("signature", ""))}
		return {}  # this delta is already on the base; the full base would only repeat the download
	if int(info.get("version", 0)) > base_now and str(info.get("signature", "")) != "":
		return {"kind": "full", "version": int(info["version"]), "sha256": str(info["sha256"]), "engine": engine, "signature": str(info.get("signature", ""))}
	return {}


# The base patch, then the delta on top of it when the delta was made for this base
func _mount_patches() -> bool:
	if not ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(PATCH_FILE), true):
		return false
	_mount_delta()
	return true


func _mount_delta() -> void:
	var delta = _installed.get("delta")
	if not (delta is Dictionary) or int(delta.get("base_version", -1)) != int(_installed.get("version", 0)):
		return
	if not FileAccess.file_exists(DELTA_FILE) or FileAccess.get_sha256(DELTA_FILE) != str(delta.get("sha256", "")) \
			or not signature_ok(DELTA_FILE, str(delta.get("signature", ""))):
		_installed.erase("delta")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DELTA_FILE))
		return
	if not ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(DELTA_FILE), true):
		push_warning("Delta patch %s would not load; using the base patch" % str(delta.get("version", 0)))


# At start-up the game waits for this check (8 seconds at most). A newer version is downloaded with the
# progress shown, then the game restarts by itself. With no server, or no newer version, the game starts.
func _startup_check() -> void:
	var base := SERVER_SETTINGS.url()
	if base == "":
		return
	_startup = true
	startup_busy = true
	startup_text = "Checking for updates"
	_busy = true
	_http.timeout = 8.0
	_http.request_completed.connect(_on_startup_info, CONNECT_ONE_SHOT)
	if _http.request(base + _channel_path("info"), _headers(), HTTPClient.METHOD_GET) != OK:
		_http.request_completed.disconnect(_on_startup_info)
		_finish_startup()


func _on_startup_info(result: int, code: int, _resp_headers: PackedStringArray, raw: PackedByteArray) -> void:
	_busy = false
	var info = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		info = JSON.parse_string(raw.get_string_from_utf8())
	var offer := choose_offer(info, _installed, _engine_version())
	if not offer.is_empty():
		_offered = offer
		_download()
	else:
		_finish_startup()


# Lets the game run again after the start-up check
func _finish_startup() -> void:
	_busy = false
	_startup = false
	startup_busy = false
	startup_text = ""
	_panel.visible = false
	_set_blocker(false)


# The launcher's check: finds out whether a newer patch exists and how big it is, without downloading it
func launcher_check() -> void:
	if OS.get_name() == "Linux":
		launcher_offline.emit.call_deferred()
		return
	var base := SERVER_SETTINGS.url()
	if base == "":
		launcher_offline.emit.call_deferred()
		return
	_busy = true
	_http.timeout = 8.0
	_http.request_completed.connect(_on_launcher_info, CONNECT_ONE_SHOT)
	if _http.request(base + _channel_path("info"), _headers(), HTTPClient.METHOD_GET) != OK:
		_busy = false
		_http.request_completed.disconnect(_on_launcher_info)
		launcher_offline.emit.call_deferred()


func _on_launcher_info(result: int, code: int, _resp_headers: PackedStringArray, raw: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		launcher_offline.emit()  # no answer: this is not the same as "up to date"
		return
	if code == 404:
		launcher_no_update.emit()  # the server answered: this platform has no patch yet
		return
	if code != 200:
		launcher_offline.emit()
		return
	var info = JSON.parse_string(raw.get_string_from_utf8())
	var offer := choose_offer(info, _installed, _engine_version())
	if offer.is_empty():
		launcher_no_update.emit()
		return
	_offered = offer
	var described: Dictionary = info["delta"] if str(offer["kind"]) == "delta" else info
	launcher_update_found.emit(int(described.get("size", 0)))


# The launcher's download of the patch found by launcher_check; launcher_finished says how it went
func launcher_download() -> void:
	_startup = true  # progress goes to the launcher, not to the in-game panel
	_download()


func _download() -> void:
	var base := SERVER_SETTINGS.url()
	var is_delta := str(_offered.get("kind", "full")) == "delta"
	_http.timeout = 120.0
	_busy = true
	_bar.value = 0.0
	_speed_msec = Time.get_ticks_msec()
	_speed_bytes = 0
	_title.text = "Update ongoing"
	_body.text = "Patch %d: starting the download. You can keep playing." % int(_offered["version"])
	_restart_button.visible = false
	_ignore_button.visible = false
	_panel.visible = not _startup  # a start-up download shows on the loading bar instead
	_set_blocker(not _startup)
	_http.download_file = ProjectSettings.globalize_path(DELTA_PARTIAL if is_delta else PARTIAL_FILE)
	_http.request_completed.connect(_on_downloaded, CONNECT_ONE_SHOT)
	if _http.request(base + _channel_path("delta.pck" if is_delta else "game.pck"), _headers(), HTTPClient.METHOD_GET) != OK:
		_busy = false
		_fail_download()


func _on_downloaded(result: int, code: int, _response_headers: PackedStringArray, _raw: PackedByteArray) -> void:
	_busy = false
	_http.download_file = ""
	var is_delta := str(_offered.get("kind", "full")) == "delta"
	var partial := ProjectSettings.globalize_path(DELTA_PARTIAL if is_delta else PARTIAL_FILE)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(partial)
		_fail_download()
		return
	if FileAccess.get_sha256(DELTA_PARTIAL if is_delta else PARTIAL_FILE) != str(_offered.get("sha256", "")):
		push_warning("Patch download failed its checksum; it was discarded")
		DirAccess.remove_absolute(partial)
		_fail_download()
		return
	if not signature_ok(DELTA_PARTIAL if is_delta else PARTIAL_FILE, str(_offered.get("signature", ""))):
		push_warning("Patch download is not signed by the update key; it was discarded")
		DirAccess.remove_absolute(partial)
		_fail_download()
		return
	var version := int(_offered["version"])
	if is_delta:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DELTA_FILE))
		DirAccess.rename_absolute(partial, ProjectSettings.globalize_path(DELTA_FILE))
		_installed["delta"] = {"version": version, "sha256": str(_offered["sha256"]), "signature": str(_offered["signature"]), "base_version": int(_installed.get("version", 0))}
		_write_state(_installed)
	else:
		# A new base: the old base and any delta made for it are replaced
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATCH_FILE))
		DirAccess.rename_absolute(partial, ProjectSettings.globalize_path(PATCH_FILE))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DELTA_FILE))
		_write_state({"version": version, "sha256": str(_offered["sha256"]), "engine": str(_offered["engine"]), "signature": str(_offered["signature"])})
	_installed = _read_state()
	print("Patch %d downloaded (%s)" % [version, str(_offered.get("kind", "full"))])
	if _startup and launcher_mode:
		_startup = false
		launcher_updated = true
		launcher_finished.emit(true)
		return
	if _startup:
		startup_fraction = 1.0
		startup_text = "Update ready\nPatch %d downloaded, restarting" % version
		# Start-up update: the app restarts with the new version straight away
		_restart_app()
		return
	# During play it waits for the main menu, so no screen is lost in the middle of a task
	_pending_reload = true
	_show_ready()


# A download that failed: the game carries on with the version it has
func _fail_download() -> void:
	_panel.visible = false
	_set_blocker(false)
	if _startup:
		_finish_startup()
		if launcher_mode:
			launcher_finished.emit(false)


func _show_ready() -> void:
	_title.text = "Update ready"
	_body.text = "Patch %d is ready. Restart now to use it, or keep playing and it applies next time." % int(_offered.get("version", 0))
	_bar.visible = false
	_restart_button.visible = true
	_ignore_button.visible = true
	_ignore_button.text = "Later"
	_panel.visible = true
	_set_blocker(true)


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	# Blocks taps to everything below (game, pads, pause menu) while the update notice is up
	var blocker := ColorRect.new()
	blocker.color = Color(0.0, 0.0, 0.0, 0.55)
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.visible = false
	layer.add_child(blocker)
	_panel = PanelContainer.new()
	_panel.visible = false
	_set_blocker(false)
	# In the middle of the screen, so the download is clearly in view
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(minf(520 * _ui_scale(), get_viewport().get_visible_rect().size.x - 48.0), 0)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(_panel)
	var padding := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		padding.add_theme_constant_override(side, int(24 * _ui_scale() / 2.0))
	_panel.add_child(padding)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	padding.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", int(22 * _ui_scale()))
	box.add_child(_title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", int(16 * _ui_scale()))
	box.add_child(_body)
	_bar = ProgressBar.new()
	_bar.max_value = 100.0
	_bar.show_percentage = true
	_bar.custom_minimum_size.y = 20.0 * _ui_scale()
	_bar.add_theme_font_size_override("font_size", int(16 * _ui_scale()))
	box.add_child(_bar)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(buttons)
	_ignore_button = Button.new()
	_ignore_button.text = "Ignore"
	_ignore_button.pressed.connect(_hide_notice)
	buttons.add_child(_ignore_button)
	_restart_button = Button.new()
	_restart_button.text = "Restart now"
	# Restarts the app: the patch is applied when it opens again
	_restart_button.pressed.connect(_restart_app)
	buttons.add_child(_restart_button)
	# Phones: bigger buttons that are easy to press with a thumb
	for button in [_ignore_button, _restart_button]:
		button.add_theme_font_size_override("font_size", int(18 * _ui_scale()))
		button.custom_minimum_size = Vector2(120.0 * _ui_scale(), 56.0 * _ui_scale())
	_blocker = blocker


# The notice's blocker only exists once the panel is built; updates can run before that
func _set_blocker(on: bool) -> void:
	if _blocker != null:
		_blocker.visible = on


# Closes the update notice and lets the player back to the game
func _hide_notice() -> void:
	_panel.visible = false
	_set_blocker(false)


# Phones have a small screen for the game's size, so the update panel is drawn larger there
func _ui_scale() -> float:
	return 1.6 if OS.has_feature("mobile") else 1.0


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.094, 0.118, 0.173, 0.98)
	style.set_corner_radius_all(12)
	style.set_border_width_all(2)
	style.border_color = Color(1, 0.42, 0.208)
	return style


# Restarts the game without the player pressing its icon. On Android, a new start of the app is requested
# while it is still in front, then this process ends. If that cannot be requested, the app just closes.
# Reloads the game in place with the patch on disk, so the app stays open. Returns false if that is not possible.
# The Patcher itself is loaded before any patch, so changes to it still need a new APK.
func _reload_game() -> bool:
	if not FileAccess.file_exists(PATCH_FILE):
		return false
	if not _mount_patches():
		return false
	var scene = ResourceLoader.load("res://scenes/main.tscn", "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	if not (scene is PackedScene):
		return false
	_pending_reload = false
	_installed = _read_state()
	_startup = false
	_busy = false
	get_tree().paused = false
	_panel.visible = false
	_set_blocker(false)
	print("[restart] game reloaded in place with patch %d" % int(_installed.get("version", 0)))
	get_tree().change_scene_to_packed.call_deferred(scene)
	return true


# True while the main menu is on screen (the other screens hide it), which is when an update may be applied
func _on_main_menu() -> bool:
	for menu in get_tree().root.find_children("*", "MainMenu", true, false):
		if menu.is_visible_in_tree():
			return true
	return false


# Restarts the app so every script loads fresh. On Android the app asks Android for a new start, then this
# process ends. Only if that is not possible does it reload in place (not every script is replaced then).
func _restart_app() -> void:
	if await relaunch():
		return
	if _reload_game():
		return
	print("[restart] could not restart; just closing")
	get_tree().quit()


# Starts a fresh copy of the app, which loads the patch from the start, then ends this one. False if that is not possible.
func relaunch() -> bool:
	if OS.get_name() == "Windows":
		OS.create_process(OS.get_executable_path(), ["--", "--play"])
	elif not (OS.has_feature("android") and _schedule_relaunch()):
		return false
	print("[restart] new start requested; ending this one")
	# A moment for the OS to take the request, then this process ends so the new start gets a fresh one
	await get_tree().create_timer(0.4, true).timeout
	if OS.get_name() == "Windows":
		get_tree().quit()
	else:
		OS.kill(OS.get_process_id())
	return true


# The server's patch channel for this app: patches for Windows and for Android are built separately
func _channel_path(file: String) -> String:
	var channel := "windows" if OS.get_name() == "Windows" else "android"
	return "/patch/%s/%s" % [channel, file]


func _schedule_relaunch() -> bool:
	var context = JavaClassWrapper.wrap("android.app.ActivityThread").currentApplication()
	if context == null:
		print("[restart] no Android context")
		return false
	var intent = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName())
	if intent == null:
		print("[restart] no launch intent for this app")
		return false
	intent.addFlags(0x10000000 | 0x04000000)  # FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_CLEAR_TASK
	# The new start is requested while the app is still in front, which Android allows
	context.startActivity(intent)
	return true


func _discard() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATCH_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STATE_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DELTA_FILE))
	_installed = {}


# True only when the file was signed with the update key (see PUBLIC_KEY). A missing signature is refused.
static func signature_ok(path: String, signature_b64: String) -> bool:
	if signature_b64 == "":
		return false
	var key := CryptoKey.new()
	if key.load_from_string(PUBLIC_KEY, true) != OK:
		return false
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(FileAccess.get_file_as_bytes(path))
	return Crypto.new().verify(HashingContext.HASH_SHA256, hashing.finish(), Marshalls.base64_to_raw(signature_b64), key)


func _engine_version() -> String:
	var v := Engine.get_version_info()
	return "%d.%d.%d" % [v["major"], v["minor"], v["patch"]]


func _headers() -> PackedStringArray:
	var headers := PackedStringArray()
	if SERVER_SETTINGS.secret() != "":
		headers.append("X-Engine-Builder-Secret: " + SERVER_SETTINGS.secret())
	return headers


func _read_state() -> Dictionary:
	var data = _read_json(STATE_FILE)
	return data if data is Dictionary else {}


func _write_state(state: Dictionary) -> void:
	_write_json(STATE_FILE, state)


# Plain JSON on user:// (the Patcher's own state file); a missing or broken file reads as null
func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))
