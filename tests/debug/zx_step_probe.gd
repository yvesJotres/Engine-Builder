extends SceneTree

# Runs the ZX-25R sweep on the GDScript cylinder and reports torque and intake pressure through the sweep. Print only.
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
	var lo := 1e9
	var hi := -1e9
	var bad := 0
	while dyno.active() and frames < 60 * 240:
		dyno.advance(1.0 / 60.0, sim, spec, 1.0, true)
		frames += 1
		if sim.rpm > 9000.0 and dyno.phase == DynoTest.Phase.PULL if dyno.get("phase") != null else false:
			lo = minf(lo, sim.torque)
			hi = maxf(hi, sim.torque)
			if sim.intake.pressure < 0.6e5:
				bad += 1
		if frames % 900 == 0:
			print("t %5.1f s | rpm %6.0f | torque %7.2f | intake %4.2f bar | %s" % [frames / 60.0, sim.rpm, sim.torque, sim.intake.pressure / 1.0e5, dyno.status_text()])
	print("END ok %s status %s | torque range in pulls above 9000 rpm %.1f .. %.1f N·m | frames with intake below 0.6 bar %d" % [str(dyno.ok), dyno.status, lo, hi, bad])
	quit()
