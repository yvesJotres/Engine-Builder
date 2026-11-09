extends SceneTree

# Per-frame cost at REST (engine stopped, nothing pressed) for two presets, to find what makes the ZX-25R slow when idle.
# Times: the sim step, the cylinder key check, the engine model's crank update, and how many nodes / meshes the model has.
# Run: godot --headless -s tools/diagnostics/rest_cost.gd
const FRAMES := 20
const PARTS := ["honda_cbr150r", "kawasaki_zx25r"] # preset ids, as listed by Presets.names()


func _init() -> void:
	await process_frame
	var names: Array = []
	print("presets available: ", Presets.names())
	for part in PARTS:
		for candidate in Presets.names():
			if str(candidate).contains(part):
				names.append(candidate)
				break
	for preset_name in names:
		var spec := EngineSpec.new()
		var p: Dictionary = Presets.PRESETS[preset_name]
		for key in p.keys():
			spec.set(key, p[key])
		var sim := EngineSim.new()
		print("%s: %d cylinders, settling..." % [preset_name, spec.cylinders])
		for i in 5: # settle: a stopped engine at rest
			var s0 := Time.get_ticks_usec()
			sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
			print("  settle frame %d: %.1f ms" % [i, float(Time.get_ticks_usec() - s0) / 1000.0])
		var t0 := Time.get_ticks_usec()
		for i in FRAMES:
			sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
		var step_us := float(Time.get_ticks_usec() - t0) / FRAMES
		print("  sim.step at rest: %.1f us per frame" % step_us)
		t0 = Time.get_ticks_usec()
		for i in FRAMES:
			sim._build_cylinders(spec)
		var key_us := float(Time.get_ticks_usec() - t0) / FRAMES
		var model := EngineModel.new()
		root.add_child(model)
		model.build(spec)
		await process_frame
		t0 = Time.get_ticks_usec()
		for i in FRAMES:
			model.update_crank(float(i))
		var crank_us := float(Time.get_ticks_usec() - t0) / FRAMES
		var counts := _count(model)
		print("%-26s cyl %d | sim.step at rest %7.1f us | key check %6.1f us | update_crank %6.1f us | nodes %d, meshes %d, surfaces %d" % [
			preset_name, spec.cylinders, step_us, key_us, crank_us, counts.x, counts.y, counts.z])
		model.queue_free()
	quit()


# x = nodes, y = MeshInstance3D count, z = mesh surfaces (each is a draw call)
func _count(node: Node) -> Vector3i:
	var n := 1
	var m := 0
	var s := 0
	if node is MeshInstance3D and node.mesh != null:
		m = 1
		s = node.mesh.get_surface_count()
	for child in node.get_children():
		var c := _count(child)
		n += c.x
		m += c.y
		s += c.z
	return Vector3i(n, m, s)
