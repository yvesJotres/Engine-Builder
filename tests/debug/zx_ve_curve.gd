extends SceneTree

# Volumetric efficiency of the ZX-25R against rpm, read during a wide-open sweep (each frame's value, averaged per 500 rpm). Print only.
const BIN := 500.0


func _init() -> void:
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
		if sim.rpm > 1000.0:
			var b := int(floor(sim.rpm / BIN))
			sums[b] = sums.get(b, 0.0) + sim.volumetric_efficiency()
			counts[b] = counts.get(b, 0) + 1
	var keys := sums.keys()
	keys.sort()
	for b in keys:
		print("VE %6.0f rpm: %5.1f %%  (%d frames)" % [b * BIN, 100.0 * sums[b] / counts[b], counts[b]])
	quit()
