extends SceneTree

# Step-by-step trace of start and idle with the pipe solver on and off, to see where the engine dies with pipes.
# Run: godot --headless --path . -s tools/diagnostics/pipe_start_trace.gd
const DT := 1.0 / 60.0


func _init() -> void:
	await process_frame
	var p: Dictionary = Presets.PRESETS["honda_cbr250rr"]
	var spec := EngineSpec.new()
	for key in p.keys():
		spec.set(key, p[key])
	var layout := ExhaustLayout.build(spec)
	for pipe in [false, true]:
		var sim := EngineSim.new()
		sim.exhaust_solver = pipe
		sim.set_audio_layout(layout, spec.cylinders)
		print("--- pipe %s" % str(pipe))
		var t := 0.0
		var frame := 0
		while t < 4.0:
			sim.step(DT, spec, 0.0, true, t < 1.5, false, false, 1.0)
			if frame % 6 == 0:
				var bp := 0.0
				if sim.exhaust != null:
					bp = sim.exhaust.port_pressure(0) - Cylinder.P0
				print("t %.2f rpm %5.1f run %s gas %+8.2f port %+8.1f kPa limiter %s" % [t, sim.rpm, str(sim.running), sim._gas_torque, bp / 1000.0, str(sim.limiter_active)])
			t += DT
			frame += 1
	quit(0)
