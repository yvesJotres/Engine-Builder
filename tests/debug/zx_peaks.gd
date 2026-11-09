extends SceneTree

# ZX-25R sweep peaks on the GDScript cylinder, at the live step set in cylinder.gd. Print only.
func _init() -> void:
	Cylinder.use_native = false
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS["kawasaki_zx25r"]
	for key in p.keys():
		spec.set(key, p[key])
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 2400.0
	sim.fuel.set_kind(spec.fuel)
	var dyno = DynoTest.new()
	dyno.start(spec, sim)
	var frames := 0
	while dyno.active() and frames < 60 * 240:
		dyno.advance(1.0 / 60.0, sim, spec, 1.0, true)
		frames += 1
	var r = dyno.result()
	print("PEAKS torque %.2f N·m at %.0f rpm | power %.2f hp at %.0f rpm | ok %s" % [r.peak_torque.torque, r.peak_torque.rpm, r.peak_hp.hp, r.peak_hp.rpm, str(r.ok)])
	quit()
