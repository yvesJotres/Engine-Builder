extends SceneTree

# The crankshaft the drawing builds is the crankshaft the physics adds up: a nose pulley, main journals that run in the
# cases, a crank pin with a counterweight either side of it, and the flywheel flange the flywheel bolts to. That shape
# is what makes the drawn inertia match EngineSpec.crank_inertia().
# Run: godot --headless --path . -s tests/unit/engine/crankshaft_test.gd (exit code 1 on failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func spec_of(id: String) -> EngineSpec:
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS[id]
	for key in preset.keys():
		spec.set(key, preset[key])
	return spec


func _init() -> void:
	await process_frame
	var spec := spec_of("honda_cbr250rr")
	var model := EngineModel.new()
	root.add_child(model)
	model.build(spec)
	var crank := model._crank_node as Crankshaft
	check(crank != null, "the engine draws its crank with the Crankshaft node")
	if crank == null:
		quit(1)
		return
	check(crank.throws.size() == spec.cylinders, "one crank throw per cylinder, got %d" % crank.throws.size())
	check(crank.crank_pins.size() == crank.throws.size(), "every throw carries a crank pin")
	check(crank.counterweights.size() == 2 * crank.throws.size(), "two counterweights per crank pin")
	check(crank.journals.size() == crank.throws.size() + 1, "a main journal either side of the throws, got %d" % crank.journals.size())
	check(crank.has_node("Pulley") and crank.has_node("FlywheelFlange"), "the crank has a nose pulley and a flywheel flange")
	check(crank.flywheel != null and crank.flywheel.has_node("TimingMark"), "the flywheel bolts to the flange with its timing mark")

	# sizes: the drawing uses the spec's own journals, not a nominal shaft
	var m := Units.M_TO_SCENE
	var journal_mesh := crank.journals[0].mesh as CylinderMesh
	var pin_mesh := crank.crank_pins[0].mesh as CylinderMesh
	check(absf(journal_mesh.bottom_radius - EngineSpec.MAIN_JOURNAL_RADIUS * m) < 0.001, "main journal is the specced Ø28 mm")
	check(absf(pin_mesh.bottom_radius - EngineSpec.CRANK_PIN_RADIUS * m) < 0.001, "crank pin is the specced Ø27 mm")
	check(journal_mesh.bottom_radius > pin_mesh.bottom_radius, "the main journal is the larger of the two")
	check(absf(crank.crank_pins[0].position.y - spec.crank_throw_m() * m) < 0.0005, "the pin sits at the crank radius")
	var fw_disc := crank.flywheel.get_node("FlywheelDisc") as MeshInstance3D
	check(absf((fw_disc.mesh as CylinderMesh).bottom_radius - spec.flywheel_radius_m() * m) < 0.001, "the flywheel disc is the specced radius")

	# the pulley sits on the nose, outboard of every journal and web; the flange at the other end, inboard of the flywheel
	var left_end := 1e9
	var right_end := -1e9
	for journal in crank.journals:
		left_end = minf(left_end, journal.position.x - (journal.mesh as CylinderMesh).height * 0.5)
		right_end = maxf(right_end, journal.position.x + (journal.mesh as CylinderMesh).height * 0.5)
	check(crank.pulley.position.x < left_end + 0.001, "the pulley is on the crank nose")
	check(crank.flywheel_flange.position.x > right_end - 0.001, "the flywheel flange is on the flywheel end")
	check(crank.flywheel.position.x > crank.flywheel_flange.position.x, "the flywheel is outboard of its flange")

	# a web is one solid plate: arm past the pin on the pin side, balance mass on the far side
	var outline := Crankshaft.counterweight_outline(spec.web_arm_radius_m() * m, spec.counterweight_radius_m() * m,
		EngineSpec.COUNTERWEIGHT_ARM_DEG, EngineSpec.COUNTERWEIGHT_SPAN_DEG)
	var max_y := -1e9
	var min_y := 1e9
	for p in outline:
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	check(absf(max_y - spec.web_arm_radius_m() * m) < 0.001, "the web arm reaches its specced radius on the pin side")
	check(max_y > (spec.crank_throw_m() + EngineSpec.CRANK_PIN_RADIUS) * m, "so the web carries the crank pin, not floats off it")
	check(absf(-min_y - spec.counterweight_radius_m() * m) < 0.001, "the balance mass reaches its specced radius opposite the pin")
	check(-min_y > max_y, "the balance side is the heavier of the two")

	# nothing floats: every part along the crank shares a face with the part next to it
	var parts: Array = [] # [name, from_x, to_x]
	for j in crank.journals:
		var h := (j.mesh as CylinderMesh).height
		parts.append(["journal", j.position.x - h * 0.5, j.position.x + h * 0.5])
	for c in crank.counterweights:
		# a web is a child of its throw, so its position is along the throw, not the crank
		var cx: float = (c.get_parent() as Node3D).position.x + c.position.x
		parts.append(["web", cx - c.depth * 0.5, cx + c.depth * 0.5])
	for t in crank.throws.size():
		var pin := crank.crank_pins[t]
		var w := (pin.mesh as CylinderMesh).height * 0.5
		var x: float = crank.throws[t].position.x
		parts.append(["pin%d" % t, x - w, x + w])
	var pul_w := (crank.pulley.mesh as CylinderMesh).height
	parts.append(["pulley", crank.pulley.position.x - pul_w * 0.5, crank.pulley.position.x + pul_w * 0.5])
	var fl_w := (crank.flywheel_flange.mesh as CylinderMesh).height
	parts.append(["flange", crank.flywheel_flange.position.x - fl_w * 0.5, crank.flywheel_flange.position.x + fl_w * 0.5])
	for part in parts:
		var touches := false
		for other in parts:
			if other == part:
				continue
			if absf(part[1] - other[2]) < 0.001 or absf(part[2] - other[1]) < 0.001:
				touches = true
		check(touches, "%s at %.3f..%.3f is joined to the crank" % [part[0], part[1], part[2]])

	# one cylinder: two webs, two journals, still a pulley and a flange
	var single := spec_of("honda_cbr150r")
	var bare := EngineModel.new()
	root.add_child(bare)
	bare.build(single)
	var bare_crank := bare._crank_node as Crankshaft
	check(bare_crank.throws.size() == 1 and bare_crank.counterweights.size() == 2, "a single has one throw and two webs")
	check(bare_crank.journals.size() == 2, "a single has two main journals")
	check(bare_crank.has_node("Pulley") and bare_crank.has_node("FlywheelFlange"), "a single has the nose and the flange too")

	# every preset draws a crank whose bay fits inside its station pitch
	for name in Presets.PRESETS:
		for c in root.get_children():
			if c is EngineModel:
				root.remove_child(c)
				c.free()
		var s := spec_of(name)
		var mdl := EngineModel.new()
		root.add_child(mdl)
		mdl.build(s)
		var ck := mdl._crank_node as Crankshaft
		check(ck != null and ck.journals.size() >= 2, "%s: crank built" % name)
		check(s.crank_bay_m() < s.cylinder_pitch_m(), "%s: crank bay fits the cylinder pitch" % name)
		check(s.main_journal_width_m() > 0.011, "%s: main journal stays a real width" % name)
		root.remove_child(mdl)
		mdl.free()

	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
