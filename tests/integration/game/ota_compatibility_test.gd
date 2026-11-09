extends SceneTree

var _fails := 0

func _init() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() == 3 and arguments[0] == "--verify-signature":
		var updater_script = load("res://scripts/updates/patcher.gd")
		var verified: bool = updater_script.signature_ok(arguments[1], arguments[2])
		print("LEGACY_SIGNATURE_VALID=", verified)
		quit(0 if verified else 1)
		return
	if arguments.size() == 2 and arguments[0] == "--inspect-config":
		if not ProjectSettings.load_resource_pack(arguments[1], true):
			print("FAIL could not mount Android patch")
			quit(1)
			return
		print("LOCAL_CONFIG_PRESENT=", FileAccess.file_exists("res://config/server.local.cfg"))
		quit()
		return
	if arguments.size() == 1 and arguments[0] == "--legacy-updater":
		var updater_script = load("res://scripts/updates/patcher.gd")
		if updater_script == null:
			print("FAIL could not load installed updater")
			quit(1)
			return
		var updater = updater_script.new()
		for method in ["choose_offer", "_mount_delta", "launcher_check", "launcher_download", "_reload_game", "relaunch"]:
			print("UPDATER ", method, "=", updater.has_method(method))
		for signal_name in ["launcher_no_update", "launcher_offline", "launcher_update_found", "launcher_finished"]:
			print("UPDATER ", signal_name, "=", updater.has_signal(signal_name))
		var properties := []
		for property in updater.get_property_list():
			properties.append(property.name)
		for property_name in ["progress_got", "progress_total", "progress_speed", "launcher_hold", "launcher_updated"]:
			print("UPDATER ", property_name, "=", properties.has(property_name))
		updater.free()
		quit()
		return
	for pack_path in arguments:
		if not ProjectSettings.load_resource_pack(pack_path, true):
			print("FAIL could not mount Android patch")
			quit(1)
			return
	await process_frame
	var engine_library = load("res://scripts/engine/engine_library.gd")
	var presets = load("res://scripts/engine/presets.gd")
	var library = engine_library.get_instance()
	library._library = presets.PRESETS
	library._ready = true
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main._panel._on_library_ready(presets.PRESETS)
	var index: int = presets.names().find("bugatti_centodieci")
	check(index >= 0, "Centodieci preset is available")
	if index >= 0:
		main._panel._on_preset_selected(index)
		check(main.spec.vehicle_type == "car" and main._car._wheels.size() == 4, "car preset loads with four wheels")
		main._sim.step(1.0 / 60.0, main.spec, 0.0, true, true, false, false, 1.0)
		check(main._sim.cylinders.size() == 16, "W16 simulation loads")
	main._panel.dyno_pressed.emit()
	check(main._dyno.active() and main._dyno_view.is_open(), "dyno scripts load")
	main._dyno.cancel()
	check(main._audio_renderer != null, "audio renderer loads")
	main.free()
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + message)