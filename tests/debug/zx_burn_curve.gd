extends SceneTree

# Burn timing against rpm in a wide-open sweep: CA50 (degrees after top dead centre), the 10-90% burn duration,
# and the spark advance. Print only.
const BIN := 1000.0


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
		if sim.rpm > 9000.0:
			var b := int(floor(sim.rpm / BIN))
			var ca50: float = sim.ca50_deg()
			var burn: float = sim.burn_10_90_deg()
			if ca50 < 0.0:
				continue
			if not sums.has(b):
				sums[b] = [0.0, 0.0, 0.0]
				counts[b] = 0
			sums[b][0] += ca50
			sums[b][1] += burn
			sums[b][2] += sim.peak_pressure_pa() / 1.0e5
			counts[b] += 1
	var keys := sums.keys()
	keys.sort()
	for b in keys:
		var n := float(counts[b])
		print("BURN %5.0f rpm: CA50 %5.1f deg ATDC | burn 10-90 %5.1f deg | peak pressure %5.1f bar  (%d frames)" % [b * BIN, sums[b][0] / n, sums[b][1] / n, sums[b][2] / n, counts[b]])
	quit()
