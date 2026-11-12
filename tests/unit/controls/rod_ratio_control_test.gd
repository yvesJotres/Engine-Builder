extends SceneTree

# The conrod ratio has a row on the Engine page and it reaches the engine. It used to be a preset-only value with no
# control, so a builder could not touch it; the row must carry the preset's value, pass it to the spec, and change what
# the simulation does.
# Run: godot --headless --path . -s tests/unit/controls/rod_ratio_control_test.gd (prints PASS or FAIL)

const BIKE := "yamaha_mt07"

var _fails := 0


func _init() -> void:
	await process_frame
	var panel := ControlPanel.new()
	root.add_child(panel)
	await process_frame

	# 1. the row is on the Engine page, beside bore and stroke
	check(panel._controls.has("rod_ratio"), "the panel has a conrod ratio control")
	if panel._controls.has("rod_ratio"):
		check(panel._controls["rod_ratio"] is SpinBox, "the conrod ratio is a spin box")
		check(panel._controls["rod_ratio"].get_parent() == panel._controls["bore"].get_parent(), "the conrod ratio sits on the Engine page")
		check(is_equal_approx(panel._controls["rod_ratio"].step, 0.01), "the conrod ratio steps in hundredths")

	# 2. choosing an engine puts that engine's conrod ratio on the row
	var index: int = panel._preset_ids.find(BIKE)
	check(index >= 0, "the MT-07 preset is in the library")
	if index >= 0:
		panel._on_preset_selected(index)
		var want := float(Presets.PRESETS[BIKE]["rod_ratio"])
		check(is_equal_approx(panel._controls["rod_ratio"].value, want), "the MT-07 puts its %.2f conrod ratio on the row, got %.2f" % [want, panel._controls["rod_ratio"].value])

	# 3. the row reaches the spec
	var spec := EngineSpec.new()
	panel._controls["rod_ratio"].value = 2.2
	panel.apply_to(spec)
	check(is_equal_approx(spec.rod_ratio, 2.2), "the row's value is in the spec (%.2f)" % spec.rod_ratio)
	check(spec.validation_warning() == "", "2.2 passes the engine's own validation")

	# and a value outside the engine's range is refused by validation, so the row cannot quietly make a bad engine
	var bad := EngineSpec.new()
	bad.rod_ratio = 0.5
	check(bad.validation_warning() != "", "an impossible conrod ratio is rejected")

	# 4. it reaches the engine: the simulation builds its cylinders with the ratio, and the piston geometry at a given
	#    crank angle changes with it (a longer rod holds the piston higher for the same crank angle)
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 1200.0
	sim.step(sim.physics_dt, spec, 0.0, true, false, false, false, 1.0)
	check(is_equal_approx(sim.cylinders[0].rod_ratio, spec.rod_over_crank_radius()), "the cylinders are built with the row's rod ratio (%.2f)" % sim.cylinders[0].rod_ratio)
	var short_rod := _cylinder_volume_at(1.4)
	var long_rod := _cylinder_volume_at(2.4)
	check(absf(short_rod - long_rod) > 1.0e-7, "the ratio changes the cylinder volume at 45° of crank (%.6f vs %.6f m³)" % [short_rod, long_rod])

	panel.queue_free()
	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL"))
	quit(1 if _fails > 0 else 0)


# Cylinder volume at 45° of crank for the MT-07's bore and stroke with this conrod ratio: the piston sits higher in
# the bore for the same crank angle when the rod is longer.
func _cylinder_volume_at(rod_ratio: float) -> float:
	var preset: Dictionary = Presets.PRESETS[BIKE]
	var c := Cylinder.new()
	c.setup(float(preset["bore_mm"]), float(preset["stroke_mm"]), float(preset["compression_ratio"]), 0.15, rod_ratio * 2.0)
	return c.volume(45.0)


func check(ok: bool, message: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + message)
