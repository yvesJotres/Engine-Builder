extends SceneTree

# The exhaust hardware a real system bolts on with: a flange at every port with its two studs and nuts, a crush gasket
# behind each flange, springs at the slip joints, a lambda boss on the collector, a hanger on the canister and a shield
# over the catalyst. Geometry only - the gas model is covered in tests/unit/exhaust/.
# Run: godot --headless --path . -s tests/unit/model/pipe/exhaust_hardware_test.gd

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


func build(spec: EngineSpec) -> Array:
	var layout := ExhaustLayout.build(spec, [], Vector3(0.0, 2.0, 0.0), Ground.Y, Vector3(0.0, 3.0, -5.95))
	var exhaust := Exhaust.new()
	root.add_child(exhaust)
	exhaust.build(layout, null)
	return [exhaust, layout]


func primaries(layout: ExhaustLayout) -> Array:
	var found := []
	for pipe in layout.pipes:
		if pipe.kind == "primary":
			found.append(pipe)
	return found


func pipe_of(layout: ExhaustLayout, kind: String) -> ExhaustLayout.Pipe:
	for pipe in layout.pipes:
		if pipe.kind == kind:
			return pipe
	return null


func _init() -> void:
	await process_frame
	var spec := spec_of("honda_cbr1000rrr_sp")
	var built := build(spec)
	var exhaust := built[0] as Exhaust
	var layout := built[1] as ExhaustLayout
	var prim := primaries(layout)
	check(prim.size() == 4, "the inline-four has four primaries (%d found)" % prim.size())

	# ---- one flange per port, sitting ON the port, no gap ----
	var flanges := 0
	for pipe in prim:
		var tag: String = pipe.name.trim_prefix("primary ")
		var flange := exhaust.get_node_or_null("Flange_%s" % tag) as Node3D
		check(flange != null, "a flange on %s" % pipe.name)
		if flange == null:
			continue
		flanges += 1
		var port: Vector3 = pipe.pts[0]
		check(flange.global_position.distance_to(port) < 1.0e-4,
			"%s: the flange is on the port (%.4f away)" % [pipe.name, flange.global_position.distance_to(port)])
		check(flange.get_node_or_null("Gasket") != null, "%s: the flange has a gasket behind it" % pipe.name)
		check(flange.get_node_or_null("Stud0") != null and flange.get_node_or_null("Stud1") != null,
			"%s: the flange has two studs" % pipe.name)
		check(flange.get_node_or_null("Stud0/Nut") != null and flange.get_node_or_null("Stud1/Nut") != null,
			"%s: both studs carry a nut" % pipe.name)
	check(flanges == prim.size(), "every primary got its flange (%d of %d)" % [flanges, prim.size()])

	# ---- a spring either side of every slip joint ----
	var joints := 0
	for kind in ["collector", "muffler"]:
		var pipe := pipe_of(layout, kind)
		if pipe == null or pipe.pts.size() < 2:
			continue
		for i in 2:
			joints += 1
			check(exhaust.get_node_or_null("%sSpring%d" % [kind.capitalize(), i]) != null,
				"a spring on the %s joint (%d)" % [kind, i])
	check(joints > 0, "the layout produced joints to spring")

	# ---- the O2 sensor: a boss on the collector with a sensor screwed into it ----
	var boss := exhaust.get_node_or_null("LambdaBoss") as Node3D
	check(boss != null, "the collector carries a lambda boss")
	if boss != null:
		check(boss.get_node_or_null("Sensor") != null, "a sensor is screwed into the boss")
		var collector := pipe_of(layout, "collector")
		if collector != null and collector.pts.size() >= 2:
			var on_pipe: Vector3 = collector.pts[1]
			check(boss.global_position.distance_to(on_pipe) < 0.30,
				"the boss sits on the collector (%.3f from its second point)" % boss.global_position.distance_to(on_pipe))

	# ---- the canister hangs off the bike ----
	var hanger := exhaust.get_node_or_null("MufflerHanger") as Node3D
	check(hanger != null, "the canister is hung off the bike, not floating")
	if hanger != null:
		check(hanger.get_node_or_null("Bobbin") != null, "the hanger has a rubber bobbin")
		var canister := pipe_of(layout, "muffler")
		if canister != null and canister.pts.size() >= 2:
			# The hanger is welded to the top of the canister at its mid-length station, so it is measured
			# against the path point it was placed on, not the straight chord between the ends: the canister
			# climbs, and the chord cuts the corner the strap actually follows.
			var best := 0
			var best_d := INF
			for index in canister.pts.size():
				var flat: Vector3 = canister.pts[index] - hanger.global_position
				flat.y = 0.0
				if flat.length() < best_d:
					best_d = flat.length()
					best = index
			var station := float(best) / float(maxi(canister.pts.size() - 1, 1))
			var radius: float = canister.radii[mini(best, canister.radii.size() - 1)]
			var lift: float = hanger.global_position.y - canister.pts[best].y
			check(best_d < 0.05, "the hanger stands on the canister axis (%.3f units off it)" % best_d)
			check(station > 0.35 and station < 0.75,
				"the hanger picks the canister up at mid-length (station %.2f)" % station)
			check(absf(lift - radius) < 0.05,
				"the hanger sits on the canister's top surface (%.3f up, radius %.3f)" % [lift, radius])

	# ---- the catalyst is shrouded ----
	var shield := exhaust.get_node_or_null("CatalystShield") as MeshInstance3D
	check(shield != null, "the catalyst is shrouded, as a real one is")
	if shield != null:
		var cat := pipe_of(layout, "catalyst")
		if cat != null:
			check(shield.get_aabb().size.length() > cat.radii[0] * 2.0,
				"the shield stands off the catalyst shell")

	print("flanges %d, springs %d, boss %s, hanger %s, shield %s" % [
		flanges, joints, boss != null, hanger != null, shield != null])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
