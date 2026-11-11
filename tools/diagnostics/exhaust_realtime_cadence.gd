extends SceneTree

# Real-time cadence check for the 1D exhaust solver. It runs the same ExhaustGas the live loop uses, with no cylinder flow,
# at the live step size, and prints port pressure, hottest cell and peak gas speed. A sealed pipe must stay at ambient.
# Run: godot --headless --path . -s tools/diagnostics/exhaust_realtime_cadence.gd
const DT := 1.0 / 60.0


func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS["honda_cbr250rr"]
	for key in preset.keys():
		spec.set(key, preset[key])
	var layout := ExhaustLayout.build(spec)
	for mode in ["hold", "wave"]:
		var g := ExhaustGas.new()
		g.build(layout)
		if mode == "wave": # a 20 kPa pulse near the valve end
			for i in g._n:
				if i < g._n / 6:
					g._re[i] *= 1.2 / 1.0
		var line := "%-5s cells %d cfl %.2e s" % [mode, g._n, g._cfl_dt]
		var sub := 1.0 / 2400.0
		for frame in 120:
			g.advance(4.0 * sub)
			if frame % 20 == 0 or frame == 119:
				var tmax := 0.0
				var vmax := 0.0
				for i in g._n:
					tmax = maxf(tmax, (g._re[i] - 0.5 * g._ru[i] * g._ru[i] / g._rho[i]) / g._rho[i] * 0.4)
					vmax = maxf(vmax, absf(g._ru[i] / g._rho[i]))
				line += " [f%d p %.1f kPa T %.0f K v %.0f]" % [frame, g.port_pressure(0) / 1000.0, tmax, vmax]
		print(line)
	quit(0)
