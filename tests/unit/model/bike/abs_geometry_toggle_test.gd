extends SceneTree

# The ABS hardware follows the switch. Turning ABS on adds the tone rings, the two wheel-speed pickups and the hydraulic
# module to a bike that was drawn without them, and switching it off takes them away again. A bike that came from the
# factory with ABS keeps the metal parts whatever the rider switch says - EngineSpec.abs_hardware() is the rule, and this
# is the same call main.gd makes when it rebuilds the bike.
# Run: godot --headless --path . -s tests/unit/geometry/abs_geometry_toggle_test.gd

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


# What main.gd does: build the drivetrain with whatever abs_hardware() says.
func build_with(spec: EngineSpec) -> Drivetrain:
	var dt := Drivetrain.new()
	root.add_child(dt)
	dt.build(Ground.Y, Vector3.ZERO, Vector3(0.0, 4.0, 0.0), 1.5, spec.abs_hardware())
	return dt


func parts_of(dt: Drivetrain) -> Dictionary:
	var rings := 0
	for wheel in [dt._front_wheel, dt._wheel_pivot]:
		if wheel.find_child("ABSToneRing", true, false) != null:
			rings += 1
	return {
		"rings": rings,
		"front_pickup": dt.find_child("FrontABSSensor", true, false) != null,
		"rear_pickup": dt.find_child("RearABSSensor", true, false) != null,
		"module": dt.find_child("ABSModule", true, false) != null,
	}


func _init() -> void:
	await process_frame

	# ---- a bike built without ABS: no hardware, and the switch is what changes that ----
	var plain := spec_of("honda_cbr150r")
	check(not plain.has_abs and not plain.abs_enabled, "the 150 has no ABS from the factory and the switch is off")
	check(not plain.abs_hardware(), "so there is no ABS hardware to draw")
	var bare := parts_of(build_with(plain))
	print("switch off: %d rings, pickups %s/%s, module %s" % [bare.rings, bare.front_pickup, bare.rear_pickup, bare.module])
	check(bare.rings == 0, "no tone ring on either disc (%d found)" % bare.rings)
	check(not bare.front_pickup and not bare.rear_pickup, "no wheel-speed pickups")
	check(not bare.module, "no hydraulic module")

	# ---- the rider turns the switch on: the hardware appears ----
	plain.abs_enabled = true
	check(plain.abs_hardware(), "turning ABS on puts the hardware on the bike")
	var fitted := parts_of(build_with(plain))
	print("switch on : %d rings, pickups %s/%s, module %s" % [fitted.rings, fitted.front_pickup, fitted.rear_pickup, fitted.module])
	check(fitted.rings == 2, "both discs carry a tone ring (%d found)" % fitted.rings)
	check(fitted.front_pickup, "the front wheel has a pickup")
	check(fitted.rear_pickup, "the rear wheel has a pickup")
	check(fitted.module, "the hydraulic module is plumbed in")

	# ---- the switch off again takes them away ----
	plain.abs_enabled = false
	var again := parts_of(build_with(plain))
	check(again.rings == 0 and not again.module, "switching ABS off removes the hardware again")

	# ---- a factory ABS bike keeps the metal parts with the rider switch off ----
	var factory := spec_of("honda_cbr1000rrr_sp")
	factory.abs_enabled = false
	check(factory.has_abs and factory.abs_hardware(), "a factory ABS bike still has the hardware with the switch off")
	var kept := parts_of(build_with(factory))
	check(kept.rings == 2 and kept.module, "its tone rings and module are still drawn")

	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
