extends SceneTree

# Runs the ZX-25R sweep to the end and prints its peak torque and power. Print only. Run: godot --headless --path . -s tests/debug/zx_dyno_result.gd
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
	var frames := 0
	while dyno.active() and frames < 60 * 240:
		dyno.advance(1.0 / 60.0, sim, spec, 1.0, true)
		frames += 1
	var r: Dictionary = dyno.result()
	print("RESULT " + str(r))
	quit()
