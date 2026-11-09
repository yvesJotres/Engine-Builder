extends SceneTree

func _init() -> void:
	for id in ["honda_cbr150r", "honda_cbr250rr", "kawasaki_zx25r"]:
		for mode in ["open", "stock", "sport", "short"]:
			var spec := EngineSpec.new()
			for key in Presets.PRESETS[id]:
				spec.set(key, Presets.PRESETS[id][key])
			spec.muffler_style = "stock" if mode == "open" else mode
			var sim := EngineSim.new()
			sim.exhaust_solver = mode != "open"
			sim.audio_enabled = false
			var start := Time.get_ticks_usec()
			var pressure_sum := 0.0
			var torque_sum := 0.0
			for i in 120:
				sim.rpm = 6000.0
				sim.omega = 6000.0 * TAU / 60.0
				sim.step(1.0 / 60.0, spec, 0.8, true, false, true, false, 1.0)
				if i >= 60:
					pressure_sum += sim.exhaust.port_pressure(0)
					torque_sum += sim.torque
			print("%s %s avg_port=%.1f kPa torque=%.2f Nm cost=%.2f ms/frame" % [id, mode, pressure_sum / 60000.0, torque_sum / 60.0, (Time.get_ticks_usec() - start) / 120000.0])
	quit()
