extends SceneTree

# The speed limit set on the panel's Vehicle page reaches the spec the engine runs with: changing the value or switching the
# limiter changes what apply_to hands over, and a preset that fits no limiter starts with it off.
# Exits 1 on any failure. Run: godot --headless --path . -s res://tests/unit/controls/speed_limit_panel_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	var library = EngineLibrary.get_instance()
	library._library = Presets.PRESETS
	library._ready = true
	var panel := ControlPanel.new()
	root.add_child(panel)
	await process_frame
	var fireblade := panel._preset_ids.find("honda_cbr1000rrr_sp")
	check(fireblade >= 0, "the Fireblade is in the preset list")
	if fireblade < 0:
		print("speed_limit_panel_test: FAILED")
		quit(1)
		return
	panel._on_preset_selected(fireblade)
	var spec := EngineSpec.new()
	panel.apply_to(spec)
	check(spec.speed_limit_enabled and is_equal_approx(spec.speed_limit_kmh, 300.0), "the Fireblade starts with the limiter on at 300 km/h")
	panel._controls["speed_limit_kmh"].value = 250.0
	panel.apply_to(spec)
	check(is_equal_approx(spec.speed_limit_kmh, 250.0), "the panel's limit of 250 km/h reaches the spec, got %s" % spec.speed_limit_kmh)
	panel._controls["speed_limit_enabled"].select(0)
	panel.apply_to(spec)
	check(not spec.speed_limit_enabled, "switching the limiter off reaches the spec")
	panel._controls["speed_limit_enabled"].select(1)
	panel._controls["speed_limit_kmh"].value = 320.0
	panel.apply_to(spec)
	check(spec.speed_limit_enabled and is_equal_approx(spec.speed_limit_kmh, 320.0), "a 320 km/h limit reaches the spec")
	var other := panel._preset_ids.find("kawasaki_zx25r")
	if other >= 0:
		panel._on_preset_selected(other)
		panel.apply_to(spec)
		check(not spec.speed_limit_enabled, "a preset with no limiter starts with it off")
	print("speed_limit_panel_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
