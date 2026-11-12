extends SceneTree

# Afterfire: a bike that keeps fuelling on the overrun but cuts the spark sends unlit mixture into a hot pipe, and it bangs.
# overrun_pop selects that behaviour; with the stock decel cut (fuel AND spark) there is nothing to bang. Both halves matter:
# the flag must produce pops, and its absence must produce none.
# Run: godot --headless --path . --quit-after 6000 -s res://tests/unit/engine/overrun_pop_test.gd

const DT := 1.0 / 60.0

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _spec(pop: bool) -> EngineSpec:
	var spec := EngineSpec.new()
	for key in Presets.PRESETS["harley_sportster_883"].keys():
		spec.set(key, Presets.PRESETS["harley_sportster_883"][key])
	spec.overrun_pop = pop
	spec.decel_cut = true # the stock overrun cut is on; overrun_pop is what changes its shape
	return spec


# Returns the pops in each of the four seconds after the throttle snaps shut, so the crackle's shape is measured and not
# just its existence: a real overrun bangs repeatedly and fades as the pipe cools.
func _run(pop: bool) -> Array:
	var spec := _spec(pop)
	var sim := EngineSim.new()
	sim.audio_enabled = false
	for i in 240:
		sim.step(DT, spec, 0.0, true, i < 60, false, false, 1.0)
	sim.gear.gear = 0
	sim.clutch_pull = 1.0
	for i in 600: # wind it up wide open so the port is hot
		sim.step(DT, spec, 1.0, true, false, false, false, 1.0)
	var at_snap := sim.rpm
	var per_second := [0, 0, 0, 0]
	var last := sim.backfire_count
	for second in 4: # then shut the throttle and coast
		for frame in 60:
			sim.step(DT, spec, 0.0, true, false, false, false, 1.0)
			if sim.backfire_count > last:
				per_second[second] += sim.backfire_count - last
			last = sim.backfire_count
	print("snap shut at %.0f rpm, overrun 4 s: %s pops per second (overrun_pop=%s)" % [at_snap, str(per_second), str(pop)])
	return per_second


func _init() -> void:
	var with_pop: Array = _run(true)
	var without: Array = _run(false)
	var total := 0
	for n in with_pop:
		total += n
	var without_total := 0
	for n in without:
		without_total += n
	check(total >= 10, "keeping the fuel and cutting the spark crackles down the overrun (%d pops in 4 s)" % total)
	check(with_pop[0] > 0, "it starts popping the moment the throttle shuts (%d in the first second)" % with_pop[0])
	check(without_total == 0, "the stock decel cut does not bang (%d pops)" % without_total)

	# and the rider can turn it on: the switch is on the panel and it drives the spec
	var panel := ControlPanel.new()
	panel.builds_path = "user://overrun_pop_test.cfg"
	root.add_child(panel)
	await process_frame
	var toggle: Control = panel._controls.get("overrun_pop")
	check(toggle != null, "the panel has a Decel Pops switch")
	if toggle != null:
		var from_panel := EngineSpec.new()
		toggle.select(1)
		panel.apply_to(from_panel)
		check(from_panel.overrun_pop, "the switch turns the pop on")
		toggle.select(0)
		panel.apply_to(from_panel)
		check(not from_panel.overrun_pop, "and off again")
	panel.free()
	print("overrun_pop_test: %s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
