extends SceneTree

# Traces spark timing in a wide-open sweep near 12,000 rpm: the advance the sim asks for, and the burn start, centre and end
# of the last few cycles of cylinder 0. Print only.
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
	var printed := 0
	var frames := 0
	while dyno.active() and frames < 60 * 240 and printed < 12:
		dyno.advance(1.0 / 60.0, sim, spec, 1.0, true)
		frames += 1
		if sim.rpm > 11800.0 and sim.rpm < 12200.0:
			var c = sim.cylinders[0]
			if c.last_ca10 >= 0.0 and frames % 37 == 0:
				var adv := EngineAir.spark_advance_deg(sim.rpm, spec.ignition_offset_deg)
				print("rpm %5.0f | spark asked %5.1f deg BTDC | last cycle CA10 %5.1f  CA50 %5.1f  CA90 %5.1f ATDC | burn 10-90 %5.1f deg" % [sim.rpm, adv, c.last_ca10, c.last_ca50, c.last_ca90, c.last_burn_10_90])
				printed += 1
	quit()
