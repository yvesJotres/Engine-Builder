extends SceneTree

# Indicated (gas) mean pressure, shaft torque and the friction between them, against rpm, in a wide-open sweep. Print only.
const BIN := 1000.0


func _init() -> void:
	Cylinder.use_native = false # the GDScript cylinder, so the change under test is what runs
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS["kawasaki_zx25r"]
	for key in p.keys():
		spec.set(key, p[key])
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 2400.0
	sim.fuel.set_kind(spec.fuel)
	var dyno = DynoTest.new()
	dyno.start(spec, sim)
	var sums := {}
	var counts := {}
	var frames := 0
	while dyno.active() and frames < 60 * 240:
		dyno.advance(1.0 / 60.0, sim, spec, 1.0, true)
		frames += 1
		if sim.rpm > 9000.0:
			var b := int(floor(sim.rpm / BIN))
			var v := [sim.imep_pa() / 1.0e5, sim.torque, sim.mechanical_efficiency(), sim.intake.pressure / 1.0e5]
			if not sums.has(b):
				sums[b] = [0.0, 0.0, 0.0, 0.0]
				counts[b] = 0
			for i in 4:
				sums[b][i] += v[i]
			counts[b] += 1
	var keys := sums.keys()
	keys.sort()
	for b in keys:
		var n := float(counts[b])
		print("IMEP %5.0f rpm: IMEP %5.2f bar | shaft %5.2f N·m | mech eff %3.0f %% | intake %4.2f bar  (%d frames)" % [b * BIN, sums[b][0] / n, sums[b][1] / n, 100.0 * sums[b][2] / n, sums[b][3] / n, counts[b]])
	quit()
