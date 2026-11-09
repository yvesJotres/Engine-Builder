extends SceneTree

# Diagnostic: idle exhaust level and sharp-edge content from the waveguide (no fabricated click).
const DT := 1.0 / 60.0
const FRAME_SAMPLES := 735

func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	sim.exhaust_solver = true
	var sound := EngineSound.new()
	root.add_child(sound)
	sound.setup(spec)
	var out := PackedFloat32Array()
	for i in 600:
		sim.step(DT, spec, 0.0, true, i < 60, false, false, 1.0)
		sound.rpm = sim.rpm
		if sim.exhaust != null:
			sound.push_flow(sim.exhaust.take_flow())
		for frame in sound.render(FRAME_SAMPLES):
			if i >= 300:
				out.append(frame.x)
	var rms := 0.0
	var edge := 0.0
	var peak := 0.0
	for k in range(1, out.size()):
		rms += out[k] * out[k]
		var d := out[k] - out[k - 1]
		edge += d * d
		peak = maxf(peak, absf(out[k]))
	rms = sqrt(rms / out.size())
	edge = sqrt(edge / out.size())
	print("idle %.0f rpm  overall rms %.4f  sharp-edge rms %.4f  edge/overall %.2f  peak %.3f" % [sim.rpm, rms, edge, edge / maxf(rms, 1e-9), peak])
	quit(0)
