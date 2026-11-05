extends SceneTree

# Checks that the fuel choice changes performance: E85 cools the intake charge, so a cylinder makes more torque on E85 than on
# petrol, and E85 tolerates more ignition advance before it knocks. Run: godot --headless -s tests/fuel_effect_test.gd
# (exit code 1 on failure)

const DT := 1.0 / 60.0
var _fails := 0


func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1


# Wide-open torque of one cylinder at 7,000 rpm on this fuel, with the intake charge cooled by its evaporation.
func _torque(kind: String) -> float:
	var spec := EngineSpec.new()
	var tank := FuelTank.new()
	tank.set_kind(kind)
	var cyl := Cylinder.new()
	cyl.setup(spec.bore_mm, spec.stroke_mm, spec.compression_ratio)
	cyl.set_cams(spec)
	var man := EngineAir.new()
	var dphi := 7000.0 * 6.0 * DT
	var ign := 720.0 - EngineAir.spark_advance_deg(7000.0)
	var tm := EngineAir.T0 - EngineSim.charge_cooling_k(tank.latent, tank.afr, 1.0)
	var sum := 0.0
	var n := 0
	for i in 300:
		var r := cyl.advance(dphi, DT, man.pressure, tm, ign, true, tank, 1.0)
		man.manifold_update(DT, 1.0, r.y / DT)
		if i >= 240:
			sum += r.x
			n += 1
	return sum / n


# Runs the engine at a wide-open throttle for ten seconds on this fuel, with the ignition advanced by offset, and counts knocks.
func _knocks(kind: String, offset: float) -> int:
	var spec := EngineSpec.new()
	spec.ignition_offset_deg = offset
	var sim := EngineSim.new()
	sim.fuel.set_kind(kind)
	for i in 720:
		sim.step(DT, spec, 0.0, true, true, false, false, 1.0)
	for i in 600:
		sim.step(DT, spec, 0.5, true, false, false, false, 1.0)
	return sim.knock_count


func _init() -> void:
	await process_frame
	var petrol := _torque("petrol")
	var e85 := _torque("e85")
	print("torque at 7000 rpm: petrol %.2f N·m, E85 %.2f N·m" % [petrol, e85])
	check(e85 > petrol * 1.01, "E85 makes more torque than petrol from its cooler charge (%.2f vs %.2f)" % [e85, petrol])
	var petrol_limit := EngineSim.knock_limit_deg(95.0, 11.3)
	var e85_limit := EngineSim.knock_limit_deg(105.0, 11.3)
	check(e85_limit > petrol_limit + 3.0, "E85 tolerates more advance than petrol (limit %.1f vs %.1f deg)" % [e85_limit, petrol_limit])
	var petrol_knocks := _knocks("petrol", 5.0)
	var e85_knocks := _knocks("e85", 5.0)
	check(petrol_knocks > 0, "petrol knocks with +5 deg advance (%d knocks)" % petrol_knocks)
	check(e85_knocks == 0, "E85 does not knock with +5 deg advance (%d knocks)" % e85_knocks)
	check(_knocks("petrol", 0.0) == 0, "stock timing does not knock on petrol")
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
