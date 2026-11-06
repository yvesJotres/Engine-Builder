extends SceneTree

# Diagnostic: the idle sound's overall level and its sharp-edge (click) content, for the current spark click level. Print only.
const DT := 1.0 / 60.0
const FRAME_SAMPLES := 735

func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	var sound := EngineSound.new()
	root.add_child(sound)
	sound.setup(spec)
	var max_air := Units.AIR_DENSITY * spec.displacement_cc * 1.0e-6 * (spec.redline_rpm / 120.0)
	var max_fuel := max_air / float(FuelTank.PROPERTIES[sim.fuel.kind].afr) * 1000.0
	var out := PackedFloat32Array()
	for i in 600:
		sim.step(DT, spec, 0.0, true, i < 60, false, false, 1.0)
		sound.rpm = sim.rpm
		sound.firing = sim.running and not sim.limiter_active
		sound.energy = sqrt(clampf(sim.fuel_flow / max_fuel, 0.0, 1.0))
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
	print("click level %.4f: idle %.0f rpm  overall rms %.4f  sharp-edge rms %.4f  edge/overall %.2f  peak %.3f" % [EngineSound.CLICK_LEVEL, sim.rpm, rms, edge, edge / maxf(rms, 1e-9), peak])
	quit(0)
