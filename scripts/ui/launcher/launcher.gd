extends Control
## The main menu and the first screen of the app. It checks the server for an update, asks first when the connection is
## mobile or metered, downloads the update with a progress bar, and ends with a PLAY button.
## The update itself is the Patcher's job (scripts/updates/patcher.gd); this scene only shows it.
## After a download PLAY restarts the exe ("-- --play") so every script loads from the new patch.

const GAME_SCENE := "res://scenes/main.tscn"
const PatchInfo := preload("res://scripts/updates/patch_info.gd")
const ServerSettings := preload("res://scripts/user/server_settings.gd")
const SingleInstance := preload("res://scripts/app/single_instance.gd")
const ACCENT := Color(1, 0.42, 0.208)
const GOLD := Color(1, 0.843, 0.541)
const BACKGROUND := Color(0.055, 0.067, 0.09)
const PANEL := Color(0.094, 0.118, 0.173)
const MUTED := Color(0.62, 0.66, 0.73)

var _status: Label
var _bar: ProgressBar
var _play: Button
var _ask: ConfirmationDialog
var _size_bytes := 0
var _downloading := false


func _ready() -> void:
	if await SingleInstance.guard(get_tree()):
		return
	_build()
	Patcher.launcher_no_update.connect(_on_up_to_date)
	# Looked up by name: this launcher can arrive in a patch, and an installed app's Patcher may predate this signal
	if Patcher.has_signal("launcher_offline"):
		Patcher.connect("launcher_offline", _on_offline)
	Patcher.launcher_update_found.connect(_on_update_found)
	Patcher.launcher_finished.connect(_on_finished)
	_status.text = "CHECKING FOR UPDATES..."
	Patcher.launcher_check()


func _process(_delta: float) -> void:
	if not _downloading:
		return
	var got: int = Patcher.progress_got
	var total := maxi(Patcher.progress_total, _size_bytes)
	_bar.value = 100.0 * got / total if total > 0 else 0.0
	var speed: float = Patcher.progress_speed
	var left := "" if speed < 1.0 else "  ~" + _duration((total - got) / speed)
	_status.text = "DOWNLOADING UPDATES...\n%s/s    %s of %s%s" % [_megabytes(int(speed)), _megabytes(got), _megabytes(total), left]


# No answer from the server: the next address is tried on the next start, and the player can play now
func _on_offline() -> void:
	ServerSettings.next_url()
	# A patch already on the phone still plays: only the check for a newer one failed
	var installed := PatchInfo.label()
	if installed == "BUILT-IN":
		_show_play("NO CONNECTION TO THE UPDATE SERVER.\nPLAYING THE BUILT-IN VERSION")
	else:
		_show_play("NO CONNECTION TO THE UPDATE SERVER.\nUSING %s (LATEST KNOWN)" % installed)


# The server answered and this platform has no newer patch: the player is up to date
func _on_up_to_date() -> void:
	_show_play("UP TO DATE\n%s" % PatchInfo.label())


func _on_update_found(size_bytes: int) -> void:
	_size_bytes = size_bytes
	if _connection_metered():
		_ask.dialog_text = "You are currently connected to a mobile or metered network and your data plan will be used for this %s download. Do you want to continue?" % _megabytes(size_bytes)
		_ask.popup_centered()
	else:
		_start_download()


func _start_download() -> void:
	_downloading = true
	_bar.visible = true
	Patcher.launcher_download()


func _on_finished(ok: bool) -> void:
	_downloading = false
	_show_play("UPDATE COMPLETE" if ok else "COULD NOT UPDATE.\nPLAYING THE INSTALLED VERSION")


func _show_play(text: String) -> void:
	_status.text = text
	_bar.visible = false
	_play.visible = true
	_play.grab_focus()


func _on_play_pressed() -> void:
	Patcher.launcher_hold = false
	if not Patcher.launcher_updated:
		get_tree().change_scene_to_file(GAME_SCENE)
	# A downloaded update is applied in place: the game loads with the patch and the app stays open. Killing the
	# app and waiting for the OS to start it again is only the fallback, since the new start may never come.
	elif not Patcher._reload_game():
		Patcher.relaunch()


# "<cost> <is mobile data>" from Windows, such as "Unrestricted False"; anything but that is a metered link
static func metered_from(text: String) -> bool:
	var parts := text.strip_edges().split(" ")
	return parts.size() == 2 and (parts[0] != "Unrestricted" or parts[1] == "True")


# Asks the OS whether the connection is metered (mobile data or a capped plan). No answer counts as unmetered.
func _connection_metered() -> bool:
	if OS.get_name() == "Android":
		var context = JavaClassWrapper.wrap("android.app.ActivityThread").currentApplication()
		return context != null and context.getSystemService("connectivity").isActiveNetworkMetered()
	if OS.get_name() != "Windows":
		return false
	var script := "$p=[Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]::GetInternetConnectionProfile(); if($p){$p.GetConnectionCost().NetworkCostType.ToString()+' '+$p.IsWwanConnectionProfile}else{'none'}"
	var output := []
	if OS.execute("powershell.exe", ["-NoProfile", "-Command", script], output) != 0 or output.is_empty():
		return false
	return metered_from(str(output[0]))


static func _megabytes(bytes: int) -> String:
	return "%.1f MB" % (float(bytes) / 1048576.0)


static func _duration(seconds: float) -> String:
	if seconds < 90.0:
		return "%d s" % int(seconds)
	if seconds < 5400.0:
		return "%d min" % int(seconds / 60.0)
	return "%.1f hours" % (seconds / 3600.0)


# Layout: one centred column, so it fits a phone in either orientation. Text and buttons are sized for touch.
func _build() -> void:
	var back := ColorRect.new()
	back.color = BACKGROUND
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(560, 0)
	column.add_theme_constant_override("separation", 18)
	centre.add_child(column)

	var title := Label.new()
	title.text = "ENGINE BUILDER"
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var tagline := Label.new()
	tagline.text = "ENGINE SIMULATOR"
	tagline.add_theme_font_size_override("font_size", 20)
	tagline.add_theme_color_override("font_color", ACCENT)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(tagline)

	var version := Label.new()
	version.text = "v%s  |  %s" % [str(ProjectSettings.get_setting("application/config/version", "")), PatchInfo.label()]
	version.add_theme_font_size_override("font_size", 15)
	version.add_theme_color_override("font_color", MUTED)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(version)

	var rule := ColorRect.new()
	rule.color = ACCENT
	rule.custom_minimum_size = Vector2(0, 3)
	column.add_child(rule)

	# The status card: the message, the progress bar and the PLAY button
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(14)
	style.set_content_margin_all(24)
	card.add_theme_stylebox_override("panel", style)
	column.add_child(card)

	var inside := VBoxContainer.new()
	inside.add_theme_constant_override("separation", 16)
	card.add_child(inside)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 20)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inside.add_child(_status)

	_bar = ProgressBar.new()
	_bar.visible = false
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 18)
	_bar.max_value = 100.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(6)
	_bar.add_theme_stylebox_override("fill", fill)
	inside.add_child(_bar)

	_play = Button.new()
	_play.text = "PLAY"
	_play.visible = false
	_play.custom_minimum_size = Vector2(0, 72)
	_play.add_theme_font_size_override("font_size", 28)
	_play.add_theme_color_override("font_color", GOLD)
	_play.pressed.connect(_on_play_pressed)
	inside.add_child(_play)

	_ask = ConfirmationDialog.new()
	_ask.title = "Download"
	_ask.ok_button_text = "YES"
	_ask.cancel_button_text = "NO"
	_ask.exclusive = true
	_ask.confirmed.connect(_start_download)
	_ask.canceled.connect(_show_play.bind("UPDATE SKIPPED.\nPLAYING THE INSTALLED VERSION"))
	add_child(_ask)
