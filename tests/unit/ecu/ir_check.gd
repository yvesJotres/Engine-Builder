extends SceneTree

# Smoke-tests the exhaust tail flow: finite output, audible mid/high band, and a render-time print.
# Run: godot --headless -s tests/unit/ecu/ir_check.gd (exit code 1 on failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: " + msg)


func _init() -> void:
	await process_frame # autoloads are registered after _init
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	sim.exhaust_solver = true
	var sound := EngineSound.new()
	root.add_child(sound)
	sound.setup(spec)
	for frame in 180:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
		if sim.exhaust != null:
			sim.exhaust.take_flow()
	var start := Time.get_ticks_usec()
	for frame in 12:
		sim.step(1.0 / 60.0, spec, 0.3, true, false, false, false, 1.0)
		sound.rpm = sim.rpm
		if sim.exhaust != null:
			sound.push_flow(sim.exhaust.take_flow())
	var output := sound.render(4410)
	var elapsed_ms := (Time.get_ticks_usec() - start) / 1000.0
	var rms := _rms(output)
	var finite := true
	for frame in output:
		if is_nan(frame.x) or is_inf(frame.x):
			finite = false
	check(finite, "output is finite")
	check(rms > 0.0, "generated output is not silent")
	var mid_s := 0.0
	var mid_c := 0.0
	var high_s := 0.0
	var high_c := 0.0
	for index in output.size():
		var value: float = output[index].x
		var mid := TAU * 2000.0 * index / EngineSound.RATE
		var high := TAU * 4000.0 * index / EngineSound.RATE
		mid_s += value * sin(mid)
		mid_c += value * cos(mid)
		high_s += value * sin(high)
		high_c += value * cos(high)
	var mid_band := sqrt(mid_s * mid_s + mid_c * mid_c)
	var high_band := sqrt(high_s * high_s + high_c * high_c)
	# The check is on a band of 12 frequencies, not on one: the magnitude at a single frequency of a pulse train swings by 10 times with
	# the exact pulse timing, which the fuel film changes during a tip-in. A band stays put, and an over-filtered response would send it near 0.
	var mid_avg := _band(output, 1500.0, 2500.0)
	var high_avg := _band(output, 3500.0, 4500.0)
	check(mid_avg > 0.05, "simulated exhaust retains audible 2 kHz content")
	check(high_avg > 0.02, "simulated exhaust retains audible 4 kHz content")
	print("generated RMS %.3f, 2 kHz probe %.3f, 4 kHz probe %.3f, 2 kHz band %.3f, 4 kHz band %.3f, render 0.1 s %.2f ms" % [rms, mid_band, high_band, mid_avg, high_avg, elapsed_ms])
	sound.free()
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)


static func _rms(frames: PackedVector2Array) -> float:
	var sum := 0.0
	for frame in frames:
		sum += frame.x * frame.x
	return sqrt(sum / maxf(frames.size(), 1))


# Mean magnitude over 12 evenly spaced frequencies from lo to hi (Hz).
static func _band(frames: PackedVector2Array, lo: float, hi: float) -> float:
	var total := 0.0
	var count := 12
	for k in count:
		var f := lo + (hi - lo) * float(k) / float(count - 1)
		var sc := 0.0
		var cc := 0.0
		for i in frames.size():
			var w := TAU * f * i / EngineSound.RATE
			sc += frames[i].x * sin(w)
			cc += frames[i].x * cos(w)
		total += sqrt(sc * sc + cc * cc)
	return total / count
