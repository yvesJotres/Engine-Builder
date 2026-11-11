extends SceneTree

# Per-frame trace of the dyno pull's rider inputs (throttle, clutch lever, phase, gear) at the game's frame step.
# It lists every throttle or clutch jump inside one frame so the in-game motion can be checked.
# Run: godot --headless --path . -s tools/diagnostics/dyno_trace.gd -- honda_cbr250rr_sp_qs [max_gears]

const DT := 1.0 / 60.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var preset_id := args[0] if args.size() > 0 else "honda_cbr250rr_sp_qs"
	var max_gears := int(args[1]) if args.size() > 1 else 3
	var spec := DynoRunner.spec_for(preset_id)
	if spec == null:
		print("Unknown preset: %s" % preset_id)
		quit(2)
		return
	var sim := EngineSim.new()
	sim.fuel.set_kind(spec.fuel)
	var dyno := DynoTest.new()
	dyno.max_gears = max_gears
	dyno.start(spec, sim)

	var prev_throttle := 0.0
	var prev_clutch := 0.0
	var prev_phase := -1
	var prev_rpm := 0.0
	var frames := 0
	var big_throttle_jumps := 0
	var big_clutch_jumps := 0
	var throttle_reversals := 0
	var last_dir := 0
	var max_throttle_step := 0.0
	var max_clutch_step := 0.0
	var last_gear := 0
	var rpm_before_shift := 0.0
	var shift_window_end := -1
	var shift_min_rpm := 0.0
	print("frame  t(s)   phase  gear  rpm     throttle  clutch_lever  clutch_engage  speed_kmh")
	while dyno.active() and frames < 200000:
		dyno.advance(DT, sim, spec, 1.0, true)
		frames += 1
		var t := frames * DT
		var throttle_step := absf(dyno.throttle - prev_throttle)
		var clutch_step := absf(dyno.clutch_pull - prev_clutch)
		max_throttle_step = maxf(max_throttle_step, throttle_step)
		max_clutch_step = maxf(max_clutch_step, clutch_step)
		if throttle_step > 0.2:
			big_throttle_jumps += 1
		if clutch_step > 0.2:
			big_clutch_jumps += 1
		var dir := signi(int(signf(dyno.throttle - prev_throttle) * 1000.0))
		if dir != 0 and last_dir != 0 and dir != last_dir and throttle_step > 0.01:
			throttle_reversals += 1
		if dir != 0:
			last_dir = dir
		if sim.gear.gear != last_gear and sim.gear.gear > 0 and last_gear > 0:
			rpm_before_shift = prev_rpm
			shift_min_rpm = sim.rpm
			shift_window_end = frames + 18 # 0.3 s at the frame step
			print("gear %d -> %d at frame %d: rpm %.0f, throttle %.2f, clutch lever %.2f" % [last_gear, sim.gear.gear, frames, rpm_before_shift, dyno.throttle, dyno.clutch_pull])
		if sim.gear.gear > 0:
			last_gear = sim.gear.gear
		if shift_window_end >= 0:
			shift_min_rpm = minf(shift_min_rpm, sim.rpm)
			if frames >= shift_window_end:
				print("  lowest rpm in the 0.3 s after the shift: %.0f (drop %.0f rpm)" % [shift_min_rpm, rpm_before_shift - shift_min_rpm])
				shift_window_end = -1
		var phase_changed: bool = dyno.phase != prev_phase
		if phase_changed or throttle_step > 0.2 or clutch_step > 0.2:
			print("%5d  %5.2f  %5d  %4d  %6.0f  %8.2f  %12.2f  %13.2f  %9.1f  prev throttle %.2f lever %.2f phase %d%s" % [
				frames, t, dyno.phase, sim.gear.gear, sim.rpm, dyno.throttle, dyno.clutch_pull, sim.clutch_engage,
				sim.speed * 3.6, prev_throttle, prev_clutch, prev_phase, "   <- phase change" if phase_changed else ""])
		prev_throttle = dyno.throttle
		prev_clutch = dyno.clutch_pull
		prev_phase = dyno.phase
		prev_rpm = sim.rpm

	print("")
	print("Frames: %d  (%.1f s of game time)" % [frames, frames * DT])
	print("Largest throttle change in one frame: %.2f" % max_throttle_step)
	print("Largest clutch lever change in one frame: %.2f" % max_clutch_step)
	print("Throttle jumps above 0.2 in one frame: %d" % big_throttle_jumps)
	print("Clutch lever jumps above 0.2 in one frame: %d" % big_clutch_jumps)
	print("Throttle direction reversals: %d" % throttle_reversals)
	print("Final status: %s" % dyno.status)
	quit(0)
