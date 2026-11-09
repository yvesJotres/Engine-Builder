extends SceneTree

# Wall-clock cost of one second of engine time with the ZX-25R held at wide-open throttle in neutral (about 12,000 rpm and up),
# at each physics step rate, with the sound path off and on. If a second of engine time costs more than a second of wall time
# on a PC, a phone (several times slower) will run in slow motion and drop frames.
# Run: godot --headless --path . -s tools/diagnostics/high_rev_cost.gd
const PRESET := "kawasaki_zx25r"
const SECONDS := 2


func _init() -> void:
	await process_frame
	Cylinder.use_native = not OS.get_cmdline_user_args().has("--gd") # "-- --gd" times the GDScript loop
	print("cylinder path: ", "native" if Cylinder.native_available and Cylinder.use_native else "gdscript")
	var base := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS[PRESET]
	for key in p.keys():
		base.set(key, p[key])
	for audio in [false]: # the sound path adds little (see the first run); drop this to one value to save time
		for rate in [2400]:
			var sim := EngineSim.new()
			sim.physics_dt = 1.0 / rate
			sim.audio_enabled = audio
			for i in 240: # crank and fire at part throttle
				sim.step(1.0 / 60.0, base, 0.2, true, i < 120, false, false, 1.0)
			var guard := 0
			while sim.rpm < 12000.0 and guard < 1200: # wide open until it is revving high
				sim.step(1.0 / 60.0, base, 1.0, true, false, false, false, 1.0)
				guard += 1
			var rpm0 := sim.rpm
			var worst := 0.0
			var tq_sum := 0.0
			var t0 := Time.get_ticks_usec()
			for i in 60 * SECONDS:
				var f0 := Time.get_ticks_usec()
				sim.step(1.0 / 60.0, base, 1.0, true, false, false, false, 1.0)
				tq_sum += sim.torque
				worst = maxf(worst, float(Time.get_ticks_usec() - f0) / 1000.0)
				if audio: # the game drains these every frame
					sim.take_blowdown()
					sim.take_intake_flow()
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / SECONDS
			print("audio %-5s %4d steps/s | rpm %5.0f -> %5.0f | %6.1f ms wall per second of engine time (%.1f ms per 60 Hz frame, worst frame %.1f ms) | mean torque %.2f N·m" % [
				str(audio), rate, rpm0, sim.rpm, ms, ms / 60.0, worst, tq_sum / (60.0 * SECONDS)])
	quit()
