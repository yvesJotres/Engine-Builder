extends SceneTree

# P0: the RD350 must crank on the GAME path, not only in a probe that calls sim.step itself.
# Boots scenes/main.tscn, picks yamaha_rd350 through the panel's own dropdown handler
# (_on_preset_selected, the one wired to _preset_button.item_selected), then holds the starter
# through the _panel_starter bool the button writes, and releases it after 3 s.
# Prints, once a second: gear, ignition, wants_start, in_neutral_or_pulled, rpm, running,
# the cylinder class the sim actually built, and delta.
# Exits 1 if rpm never passes 800 while the starter is held.
# Run: godot --headless --path . -s res://tests/integration/game/two_stroke_start_test.gd

const DT := 1.0 / 60.0
const PRESET := "yamaha_rd350"
const HOLD_S := 3.0
const TAIL_S := 2.0 # after release, so a stall is visible in the same trace

var _fails := 0
var _main: Node


func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1


func _cylinder_class() -> String:
	if _main._sim.cylinders.is_empty():
		return "<none>"
	var c: Object = _main._sim.cylinders[0]
	var s: Script = c.get_script()
	return "<none>" if s == null else s.resource_path.get_file().get_basename()


func _row(t: float, label: String, delta: float) -> void:
	var wants_start: bool = _main._panel_starter or _main._touch_starter
	var in_neutral_or_pulled: bool = _main._sim.gear.gear == 0 or _main._clutch_held
	print("%5.1f s %-8s gear %d  ign %s  wants_start %s  neutral_or_pulled %s  rpm %7.0f  running %-5s  cyl %s  delta %.4f" % [
		t, label, _main._sim.gear.gear, str(_main._ignition), str(wants_start),
		str(in_neutral_or_pulled), _main._sim.rpm, str(_main._sim.running), _cylinder_class(), delta])


func _init() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame

	_main._ignition = true
	_main._paused = false

	# ---- the dropdown path, exactly as a click runs it ----
	# Picking from the dropdown writes user://last_engine.cfg, which is what the game opens with next time.
	# Snapshot it here and put it back at the end, so a test run does not change what the player sees.
	var _saved_engine := PanelPresets.last_engine()
	var ids: Array = _main._panel._preset_ids
	var index: int = ids.find(PRESET)
	check(index >= 0, "%s is in the panel dropdown (%d presets)" % [PRESET, ids.size()])
	if index < 0:
		print("dropdown: %s" % str(ids))
		print("RESULT: FAIL")
		quit(1)
		return
	_main._panel._on_preset_selected(index)
	for i in 30: # let the rebuild debounce fire and the scene rebuild
		_main._process(DT)
	_main.flush_rebuild()
	_main._process(DT)

	print("selected %s: stroke_type %s, idle_target_rpm %.0f, cylinders %d, cyl class %s" % [
		PRESET, str(_main.spec.stroke_type), _main.spec.idle_target_rpm,
		_main._sim.cylinders.size(), _cylinder_class()])
	check(str(_main.spec.stroke_type) == "two_stroke", "the panel applied the two-stroke spec (stroke_type %s)" % str(_main.spec.stroke_type))
	check(_cylinder_class() == "two_stroke_cylinder", "the sim built a TwoStrokeCylinder (got %s)" % _cylinder_class())
	check(_main._sim.gear.gear == 0, "the gearbox is in neutral (gear %d)" % _main._sim.gear.gear)

	# ---- the game's spec comes from the panel, not straight from the JSON: print every key the
	# panel changed, because the probe runs the JSON and the game runs this ----
	var preset: Dictionary = Presets.PRESETS[PRESET]
	var changed := []
	for key in preset.keys():
		var want: Variant = preset[key]
		var got: Variant = _main.spec.get(key)
		if typeof(want) == typeof(got) and (typeof(want) == TYPE_FLOAT or typeof(want) == TYPE_INT):
			if absf(float(want) - float(got)) > 0.0001:
				changed.append("%s %s -> %s" % [key, str(want), str(got)])
		elif str(want) != str(got):
			changed.append("%s %s -> %s" % [key, str(want), str(got)])
	print("panel vs preset: %d of %d keys differ: %s" % [changed.size(), preset.size(), ", ".join(changed) if changed.size() > 0 else "none"])

	# ---- hold the starter for 3 s, as the button does ----
	_main._panel.starter_changed.emit(true)
	_main._process(DT)
	_row(0.0, "press", DT)
	var peak := 0.0
	for frame in int(HOLD_S / DT):
		_main._process(DT)
		peak = maxf(peak, _main._sim.rpm)
		if (frame + 1) % 60 == 0:
			_row((frame + 1) * DT, "starter", DT)
	var cranked: float = _main._sim.rpm
	check(peak > 800.0, "the starter cranks it past 800 rpm within %.0f s (peak %.0f, %s)" % [
		HOLD_S, peak, "running" if _main._sim.running else "not running"])

	# ---- release, then watch it for 2 s: the defect was that it fired on the starter and died
	# the moment the starter let go, which the crank assertion alone does not catch ----
	_main._panel.starter_changed.emit(false)
	var died := false
	for frame in int(TAIL_S / DT):
		_main._process(DT)
		died = died or not _main._sim.running
		if (frame + 1) % 60 == 0:
			_row(HOLD_S + (frame + 1) * DT, "released", DT)
	check(not died, "%s keeps running for %.0f s after the starter releases (rpm %.0f)" % [PRESET, TAIL_S, _main._sim.rpm])
	print("after release: rpm %.0f from %.0f at the release, running %s" % [_main._sim.rpm, cranked, str(_main._sim.running)])

	# ---- diagnostic only, no assertion: does it run at all with a little throttle? ----
	_main._touch_throttle = 0.15
	_main._panel.starter_changed.emit(true)
	for frame in int(1.5 / DT):
		_main._process(DT)
		if (frame + 1) % 30 == 0:
			print("rescue  throttle 0.15 starter held: rpm %.0f, running %s" % [_main._sim.rpm, str(_main._sim.running)])
	_main._panel.starter_changed.emit(false)
	for frame in int(1.5 / DT):
		_main._process(DT)
		if (frame + 1) % 30 == 0:
			print("rescue  throttle 0.15 released:     rpm %.0f, running %s" % [_main._sim.rpm, str(_main._sim.running)])
	_main._touch_throttle = 0.0

	if _saved_engine.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PanelPresets.LAST_ENGINE_FILE))
	else:
		PanelPresets.remember_engine(_saved_engine)
	print("last_engine restored to \"%s\"" % _saved_engine)
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
