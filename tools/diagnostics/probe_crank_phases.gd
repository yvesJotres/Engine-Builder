extends SceneTree

# Diagnostic: what one frame costs WHILE THE STARTER IS CRANKING, phase by phase, versus a frame of
# the same bike running. The phone drops to a few frames a second the moment the starter is held, so
# this splits the frame up and prints both cases side by side.
#
# Run headless:  godot --headless --path . -s res://tools/diagnostics/probe_crank_cost.gd

const FRAMES := 60
const BIKES := ["honda_cbr150r"]


func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	for bike in BIKES:
		_measure(main, bike)
	main.free()
	quit(0)


func _time(label: String, count: int, fn: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	for i in count:
		fn.call()
	return (Time.get_ticks_usec() - t0) / 1000.0 / float(count)


func _phases(main, starter: bool) -> void:
	var spec = main.spec
	var sim: EngineSim = main._sim
	var d := 1.0 / 60.0
	main._touch_starter = starter
	main._throttle = 0.0 if starter else 1.0
	for i in 20:
		main._process(d)
	print("  %s  rpm %.0f" % ["CRANKING" if starter else "RUNNING", sim.rpm])
	var parts := {
		"sim.step": func() -> void: sim.step(d, spec, main._throttle, true, starter, false, false, main._panel.lambda()),
		"model": func() -> void:
			main._model.set_throttle(main._throttle)
			main._model.update_crank(main._crank)
			main._model.update_combustion(sim.cylinders, d),
		"wheels": func() -> void: main._update_vehicle_wheels(d),
		"sound": func() -> void:
			main._sound.drive.update_from(sim, spec, main._throttle)
			main._sound.set_conditions(sim.o2_lambda(), sim.exhaust_temp_c(), sim.backpressure_pa())
			main._sound.push_flow(sim.exhaust.take_flow() if sim.uses_pipe_sound() else sim.take_blowdown())
			main._sound.push_intake_flow(sim.take_intake_flow()),
		"exhaust+plume": func() -> void:
			main._exhaust.update_heat(sim.exhaust_temp_c(), d)
			main._backfire_flame.update(d)
			main._exhaust_fume.update(sim.exhaust_temp_c() + 273.15, sim.exhaust_mass_flow(), sim.o2_lambda(), d),
		"spl": func() -> void: main._update_spl_meter(d),
		"stats": func() -> void: main._stats.set_engine_data("x"),
		"hud": func() -> void: main._hud.update(sim, spec, main._clutch_held, main._throttle, main._spl_db),
	}
	var total := 0.0
	for name in parts:
		var ms: float = _time(name, FRAMES, parts[name])
		total += ms
		print("    %-14s %7.3f ms" % [name, ms])
	print("    %-14s %7.3f ms" % ["sum", total])


func _measure(main, bike: String) -> void:
	var index: int = main._panel._preset_ids.find(bike)
	if index < 0:
		return
	main._panel._on_preset_selected(index)
	main._panel.apply_to(main.spec)
	main.flush_rebuild()
	main._paused = false
	_phases(main, true)
	var whole_crank: float = _time("crank", FRAMES, func() -> void: main._process(1.0 / 60.0))
	print("  full _process while cranking: %.3f ms" % whole_crank)
	_phases(main, false)
	var whole_run: float = _time("run", FRAMES, func() -> void: main._process(1.0 / 60.0))
	print("  full _process while running: %.3f ms" % whole_run)
