extends SceneTree

# Headless checks. Physics tests run EngineSim directly, with no scene, so they are fast and repeatable.
# Run: godot --headless -s tests/test_engine.gd   (writes PASS/FAIL lines, exit code 1 on any failure)

const DT := 1.0 / 60.0
const VD := 149.2e-6 # swept volume of the CBR150R, m³

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: " + msg)


func _run(sim: EngineSim, spec: EngineSpec, n: int, throttle: float, ignition: bool,
		starter: bool, clutch: bool, brake: bool) -> void:
	for i in n:
		sim.step(DT, spec, throttle, ignition, starter, clutch, brake, 1.0)


# Fuel the cylinder burns over about two crank revolutions at 3000 rpm, wide open. Returns kg used.
func _cycles_fuel(spec: EngineSpec, tank: FuelTank, lambda: float, firing: bool) -> float:
	var c := Cylinder.new()
	c.setup(spec.bore_mm, spec.stroke_mm, spec.compression_ratio, spec.reciprocating_kg(), spec.rod_over_crank_radius())
	var man := EngineAir.new()
	var dphi := 3000.0 * 6.0 * DT
	var ign := 720.0 - EngineAir.spark_advance_deg(3000.0)
	var used_from := tank.mass_kg
	for i in 300:
		var r := c.advance(dphi, DT, man.pressure, EngineAir.T0, ign, firing, tank, lambda)
		man.manifold_update(DT, 1.0, r.y / DT)
	return used_from - tank.mass_kg


func _init() -> void:
	# firing order and crank angles
	check(FiringOrders.order_for(4) == [1, 3, 4, 2], "I4 firing order")
	check(FiringOrders.fire_angles(4) == [0.0, 540.0, 180.0, 360.0], "I4 fire angles")
	check(FiringOrders.fire_angles(2, 360.0) == [0.0, 360.0], "360 twin fires evenly")
	check(FiringOrders.fire_angles(2, 270.0) == [0.0, 270.0], "270 twin fires at its pin angle")
	check(FiringOrders.fire_angles(2, 180.0) == [0.0, 180.0], "180 twin fires at its pin angle")
	check(FiringOrders.fire_angles(4, 360.0, true) == [0.0, 450.0, 270.0, 540.0], "crossplane four fires 270/180/90/180 apart")
	check(FiringOrders.fire_angles(4, 360.0, false, true) == [0.0, 630.0, 480.0, 390.0], "Panigale V4 split-pin fires at 0/630/480/390 (engine-sim ignition wiring)")
	check(FiringOrders.fired_between(-1.0, 1.0, 0.0), "cylinder at 0 fires when crank passes 0")
	check(not FiringOrders.fired_between(100.0, 200.0, 0.0), "no fire mid-cycle")
	check(FiringOrders.fired_between(700.0, 730.0, 0.0), "fires again on 720 wrap")

	# bore x stroke against displacement
	var spec := EngineSpec.new()
	spec.cylinders = 4
	spec.bore_mm = 86.0
	spec.stroke_mm = 86.0
	spec.displacement_cc = 2000.0
	check(absf(spec.calc_displacement_cc() - 1998.2) < 1.0, "bore x stroke displacement")
	check(spec.validation_warning() == "", "no warning when bore x stroke matches")
	spec.displacement_cc = 1000.0
	check(spec.validation_warning() != "", "warning when bore x stroke mismatch")

	var cbr := EngineSpec.new() # defaults are the CBR150R
	check(cbr.validation_warning() == "", "CBR150R defaults agree with 149.2 cc")

	# presets agree with their own bore x stroke
	for name in Presets.PRESETS:
		var p: Dictionary = Presets.PRESETS[name]
		var pre := EngineSpec.new()
		pre.cylinders = p.cylinders
		pre.bore_mm = p.bore_mm
		pre.stroke_mm = p.stroke_mm
		pre.displacement_cc = p.displacement_cc
		check(pre.validation_warning() == "", "preset agrees with bore x stroke: " + name)

	# flywheel: ½·m·r² plus the rest of the rotating assembly
	var fly := EngineSpec.new()
	fly.bore_mm = 57.3
	fly.flywheel_radius_mm = 57.3 # pinned: the default radius is now 75 mm, see engine_spec.gd
	fly.flywheel_kg = 2.5
	check(absf(fly.rotating_inertia() - 0.00593) < 0.0002, "CBR total rotating inertia with 2.5 kg flywheel, got %.5f" % fly.rotating_inertia())
	var inertia_before := fly.rotating_inertia()
	fly.bore_mm = 80.0
	check(absf(fly.rotating_inertia() - inertia_before) < 0.0001, "flywheel inertia no longer follows the bore")
	fly.bore_mm = 57.3
	fly.flywheel_kg = 5.0
	check(absf(fly.rotating_inertia() - 0.01003) < 0.0002, "total rotating inertia with 5 kg flywheel, got %.5f" % fly.rotating_inertia())

	# connecting rod: piston and small end move with the piston; the rod's big end turns with the crank
	check(absf(cbr.reciprocating_kg() - 0.21) < 0.001, "reciprocating mass: piston plus rod small end, got %.3f" % cbr.reciprocating_kg())
	check(absf(cbr.crank_inertia() - 0.00163) < 0.00005, "crankshaft inertia from its geometry, got %.5f" % cbr.crank_inertia())
	check(absf(cbr.rotating_inertia() - 0.00886) < 0.0002, "rotating inertia with crank, rod, reciprocating mass and balancer, got %.5f" % cbr.rotating_inertia())
	check(absf(cbr.rod_kg + cbr.crank_mass_kg() - 2.5) < 0.1, "crank plus rod about 2.5 kg (catalogue), got %.2f" % (cbr.rod_kg + cbr.crank_mass_kg()))

	# slant: the engine leans about the crankshaft, so the crank stays put for the chain and clutch
	var slant_upright := EngineSpec.new()
	slant_upright.slant_deg = 0.0
	var slant_model := EngineModel.new()
	get_root().add_child(slant_model)
	slant_model.build(slant_upright)
	var crank_upright := slant_model.crank_position()
	var slant_leaned := EngineSpec.new()
	slant_leaned.slant_deg = 20.0
	slant_model.build(slant_leaned)
	check((slant_model.crank_position() - crank_upright).length() < 0.0001, "crank stays in place when the engine leans")
	check(slant_model.transform.basis.y.z > 0.3, "cylinder leans toward the front")
	slant_model.queue_free()

	# clutch pack: friction × spring force × radius × faces, about 25 N·m
	var clutch_sim := EngineSim.new()
	var clutch_spec := EngineSpec.new()
	check(absf(clutch_sim.clutch_capacity(clutch_spec) - 25.2) < 0.5, "clutch capacity from plates and springs, got %.1f" % clutch_sim.clutch_capacity(clutch_spec))
	clutch_spec.displacement_cc = 998.0
	check(clutch_sim.clutch_capacity(clutch_spec) > 90.0, "a 1000 cc engine gets a bigger clutch than the 150 cc default")

	# drivetrain: 130/70-17 tyre, 15T and 45T sprockets at 5/8 inch pitch, 3:1 final drive
	check(absf(Drivetrain.tire_outer_radius() - 3.069) < 0.01, "130/70-17 outer radius, got %.3f" % Drivetrain.tire_outer_radius())
	check(absf(Drivetrain.sprocket_radius(15) - 0.305) < 0.005, "15T sprocket pitch radius for 428 chain")
	check(absf(Drivetrain.sprocket_radius(45) - 0.909) < 0.005, "45T sprocket pitch radius for 428 chain")
	var chain_len := Drivetrain.CHAIN_LINKS * Drivetrain.CHAIN_PITCH
	var rz := Drivetrain.rear_axle_z(2.0, Drivetrain.sprocket_radius(15), Drivetrain.sprocket_radius(45), chain_len)
	var c := sqrt(4.0 + rz * rz)
	check(absf(Drivetrain.loop_length(c, Drivetrain.sprocket_radius(15), Drivetrain.sprocket_radius(45)) - chain_len) < 0.001,
		"128-link chain closes around both sprockets")
	check(absf(Drivetrain.FINAL_DRIVE - 3.0) < 0.001, "final drive 45/15")
	check(absf(Drivetrain.WHEELBASE - 13.1) < 0.0001, "wheelbase 1310 mm is 13.1 scene units")
	check(absf(Drivetrain.front_tire_outer_radius() - 2.959) < 0.01, "100/80-17 front tyre radius, got %.3f" % Drivetrain.front_tire_outer_radius())
	for t in [15, 45]:
		var pts := Sprocket.outline(t)
		check(pts.size() == (2 + Sprocket.SEAT_POINTS) * t, "sprocket %dT has tip and seat points per tooth" % t)
		var ok := true
		for p in pts:
			if p.length() > Sprocket.tip_radius(t) + 0.001 or p.length() < Sprocket.pitch_radius(t) - Sprocket.ROLLER_RADIUS * Sprocket.SEAT_SCALE - 0.002:
				ok = false
		check(ok, "sprocket %dT outline sits between the seat and the tip radius" % t)
	check(absf(Sprocket.tip_radius(15) - 0.337) < 0.001, "15T tip radius from P·(0.6+cot(180/N))/2, got %.4f" % Sprocket.tip_radius(15))

	# units: conversions and calculations
	check(absf(Units.displacement_cc(57.3, 57.8, 1) - 149.05) < 0.1, "CBR displacement from bore and stroke")
	check(absf(Units.rpm_to_rad_s(60.0) - TAU) < 0.0001, "60 rpm is one revolution per second")
	check(absf(Units.c_to_k(0.0) - 273.15) < 0.0001, "0 °C is 273.15 K")
	check(absf(Units.kmh_to_ms(36.0) - 10.0) < 0.0001, "36 km/h is 10 m/s")
	check(absf(Units.km_per_litre(40.0, 0.0, 745.0)) < 0.0001, "no fuel flow gives 0 km/L")

	# gearbox: a drum like a motorcycle's, 1st - neutral - 2nd - ... - 6th
	var gb := Gearbox.new()
	check(gb.gear == 0 and gb.label() == "N", "the bike starts in neutral")
	gb.shift_down()
	check(gb.gear == 1, "down from neutral is 1st")
	gb.shift_down()
	check(gb.gear == 1, "nothing below 1st")
	gb.shift_up()
	check(gb.gear == 0, "up from 1st is neutral, the half click")
	gb.shift_up()
	check(gb.gear == 2, "up from neutral is 2nd")
	gb.shift_down()
	check(gb.gear == 0, "down from 2nd is neutral")
	gb.shift_up()
	for i in 8:
		gb.shift_up()
	check(gb.gear == 6 and gb.label() == "6", "top gear stops at 6")
	var gear_ratios := Gearbox.ratios()
	check(absf(gear_ratios[0] - 37.0 / 12.0) < 0.001 and absf(gear_ratios[5] - 24.0 / 26.0) < 0.001, "gear ratios from the parts catalogue")
	check(absf(gear_ratios[1] - 33.0 / 17.0) < 0.001 and absf(gear_ratios[3] - 27.0 / 22.0) < 0.001, "2nd and 4th ratios from the catalogue")

	# single cylinder model builds and animates without errors
	var single := EngineSpec.new()
	single.cylinders = 1
	var model := EngineModel.new()
	get_root().add_child(model)
	model.build(single)
	model.update_crank(0.0)
	model.update_crank(180.0)
	model.update_crank(540.0)
	check(model.exhaust_ports().size() == 1 and model.highest_y() > model.crank_position().y, "single cylinder model builds with its port and a throttle body above the crank")
	model.queue_free()

	# every cylinder count uses the same unit design: build, animate, and check one rod per cylinder
	for count in [2, 4]:
		var multi := EngineSpec.new()
		multi.cylinders = count
		var multi_model := EngineModel.new()
		get_root().add_child(multi_model)
		multi_model.build(multi)
		multi_model.update_crank(90.0)
		check(multi_model._rods.size() == count and multi_model._pistons.size() == count, "%d-cylinder model has one rod and piston per cylinder" % count)
		multi_model.queue_free()

	# fuel: E85 burns 14.7/9.8 times the mass of petrol per kg of air; empty tank and lean misfire make no combustion
	var petrol := FuelTank.new()
	var e85 := FuelTank.new()
	e85.set_kind("e85")
	var p0 := petrol.mass_kg
	var e0 := e85.mass_kg
	var petrol_used := _cycles_fuel(cbr, petrol, 1.0, true)
	var e85_used := _cycles_fuel(cbr, e85, 1.0, true)
	var ratio := petrol_used / e85_used
	check(ratio > 0.6 and ratio < 0.73, "petrol uses 0.67x the E85 mass for the same air, got %.2f" % ratio)
	var empty := FuelTank.new()
	empty.mass_kg = 0.0
	check(_cycles_fuel(cbr, empty, 1.0, true) <= 0.0, "empty tank burns nothing")
	check(_cycles_fuel(cbr, FuelTank.new(), 1.4, true) <= 0.0, "lean misfire burns nothing")
	check(p0 > 0.0 and e0 > 0.0, "both tanks start with fuel")

	# engine: catch, idle, full throttle limiter, stop (neutral, no vehicle)
	var sim := EngineSim.new()
	_run(sim, cbr, 600, 0.0, true, true, true, false)
	check(sim.running, "engine catches and runs after cranking")
	_run(sim, cbr, 1200, 0.0, true, false, true, false)
	# no published idle speed for the K45 was found; the one owner report (xBHP) gives 1,100 to 1,200 warm and 1,300 to 1,600 cold
	check(sim.rpm > 1100.0 and sim.rpm < 1600.0, "idle in the owner-reported range (1,100 to 1,600), got %.0f" % sim.rpm)
	_run(sim, cbr, 2400, 1.0, true, false, true, false)
	var redline := cbr.redline_rpm
	check(sim.rpm <= redline * 1.01 and sim.rpm > redline * 0.88, "full throttle held at the fuel cut, got %.0f" % sim.rpm)
	_run(sim, cbr, 3600, 0.0, false, false, true, false)
	check(sim.rpm < 1.0 and not sim.running, "ignition off stops the engine")

	# spark advance grows with rpm, as the sweep expects
	check(EngineAir.spark_advance_deg(7000.0) > EngineAir.spark_advance_deg(1400.0), "spark advance grows with rpm")

	# peak torque check against the published 13.7 N·m at 7,000 rpm for the 2017+ K45 (cyclechaos, moto-data; reported, not a pass/fail gate yet)
	# cylinder model at a fixed 7000 rpm, wide open: average gas torque over the last second
	var torque_cyl := Cylinder.new()
	torque_cyl.setup(cbr.bore_mm, cbr.stroke_mm, cbr.compression_ratio)
	var man := EngineAir.new()
	var torque_tank := FuelTank.new()
	var dphi := 7000.0 * 6.0 * DT
	var ign := 720.0 - EngineAir.spark_advance_deg(7000.0)
	var torque_sum := 0.0
	var torque_n := 0
	for i in 300:
		var r := torque_cyl.advance(dphi, DT, man.pressure, EngineAir.T0, ign, true, torque_tank, 1.0)
		man.manifold_update(DT, 1.0, r.y / DT)
		if i >= 240:
			torque_sum += r.x
			torque_n += 1
	print("INFO: engine torque at 7000 rpm, wide open = %.2f N·m (published: 13.7 N·m)" % (torque_sum / torque_n))


	# diagnostic: idle with the throttle closed, manifold settled
	var idle_cyl := Cylinder.new()
	idle_cyl.setup(cbr.bore_mm, cbr.stroke_mm, cbr.compression_ratio)
	var idle_man := EngineAir.new()
	var idle_tank := FuelTank.new()
	var idle_dphi := 1400.0 * 6.0 * DT
	var idle_ign := 720.0 - EngineAir.spark_advance_deg(1400.0)
	var idle_sum := 0.0
	var idle_n := 0
	for i in 600:
		var r := idle_cyl.advance(idle_dphi, DT, idle_man.pressure, EngineAir.T0, idle_ign, true, idle_tank, 1.0)
		idle_man.manifold_update(DT, 0.0, r.y / DT)
		if i >= 540:
			idle_sum += r.x
			idle_n += 1
	print("INFO: idle at 1400 rpm, throttle closed: torque %.3f N·m, manifold %.1f kPa" % [idle_sum / idle_n, idle_man.pressure / 1000.0])

	# vehicle: pulls away in first gear with the clutch feathered in
	var rider := EngineSim.new()
	_run(rider, cbr, 600, 0.0, true, true, true, false)
	rider.gear.gear = 1
	for i in 1200:
		var eng := minf(1.0, i / 60.0)
		rider.clutch_engage = eng
		rider.step(DT, cbr, 1.0, true, false, false, false, 1.0)
	check(rider.speed > 2.0, "bike pulls away in first gear, got %.2f m/s at %.0f rpm" % [rider.speed, rider.rpm])

	# wheels add a few percent to the mass that accelerates, and the driveline loses some of the torque
	var wheel_kg := cbr.wheel_equivalent_kg()
	check(wheel_kg > 8.0 and wheel_kg < 20.0, "wheel inertia adds 8 to 20 kg equivalent, got %.1f" % wheel_kg)
	var coast := EngineSim.new() # clutch locked in 2nd, ignition off: engine braking drags the bike down faster than the road alone
	coast.gear.gear = 2
	coast.speed = 15.0
	var free := EngineSim.new() # same bike in neutral
	free.speed = 15.0
	for i in 120:
		coast.step(DT, cbr, 0.0, false, false, false, false, 1.0)
		free.step(DT, cbr, 0.0, false, false, true, false, 1.0)
	check(coast.speed < free.speed, "engine braking slows the bike more than coasting in neutral")

	# brakes: 10 m/s comes to a stop within 1.5 s with the brake held
	var brk := EngineSim.new()
	brk.speed = 10.0
	brk.brake = 1.0
	for i in 90:
		brk.step(DT, cbr, 0.0, false, false, false, true, 1.0)
	check(brk.speed < 0.5, "brakes stop the bike, got %.2f m/s" % brk.speed)

	_test_exhaust(cbr)
	_test_layout(cbr)

	print("tests finished, failures: %d" % _fails)
	quit(1 if _fails > 0 else 0)


# Size of the tone at f Hz in a signal sampled at WG_RATE (Hann-windowed single-bin DFT).
func _tone(x: PackedFloat32Array, f: float) -> float:
	var re := 0.0
	var im := 0.0
	var n := x.size()
	for i in n:
		var w := TAU * f * i / EngineSound.WG_RATE
		var win := 0.5 - 0.5 * cos(TAU * i / n)
		re += x[i] * win * cos(w)
		im += x[i] * win * sin(w)
	return sqrt(re * re + im * im)


func _test_exhaust(cbr: EngineSpec) -> void:
	# layout: each header type routes real pipes that end in one open tail
	var tails := {}
	for cfg in [[1, "stock", 5], [1, "4-1", 5], [4, "stock", 9], [4, "4-1", 9], [4, "4-2-1", 11]]:
		var sp := EngineSpec.new()
		sp.cylinders = cfg[0]
		sp.displacement_cc = 150.0 * cfg[0]
		sp.header = cfg[1]
		var lay := ExhaustLayout.build(sp)
		check(lay.pipes.size() == cfg[2], "%d cyl %s exhaust has %d pipes, got %d" % [cfg[0], cfg[1], cfg[2], lay.pipes.size()])
		var primaries := 0
		for i in lay.pipes.size():
			var pipe := lay.pipes[i]
			check(pipe.length_m() > 0.02 and pipe.area_m2() > 0.0, "%s has a length and a bore" % pipe.name)
			for f in pipe.feeders:
				check(f < i, "pipes are listed upstream first")
			if pipe.kind == "primary":
				primaries += 1
				check(pipe.length_m() > 0.2 and pipe.length_m() < 0.8, "%s primary is %.2f m, expected 0.2 to 0.8 m" % [cfg[1], pipe.length_m()])
		check(primaries == cfg[0], "one primary per cylinder")
		check(lay.pipes[-1].kind == "tail", "the last pipe is the tailpipe")
		var muffler: ExhaustLayout.Pipe = lay.pipes[-2]
		check(muffler.area_m2() > 4.0 * lay.pipes[-3].area_m2(), "the muffler is much wider than the pipe feeding it")
		tails[cfg[1] + str(cfg[0])] = lay.total_length_m()
		# what the eye checks: nothing inside the rear tyre or the ground, and the muffler does not stick out behind the tyre
		var tyre_r := Drivetrain.tire_outer_radius()
		var axle := Vector3(0.0, Ground.Y + tyre_r, -5.95)
		var clearance := 99.0
		var intrusion := 0.0
		for pipe in lay.pipes:
			for k in pipe.pts.size():
				var q: Vector3 = pipe.pts[k]
				clearance = minf(clearance, q.y - pipe.radii[k] - Ground.Y)
				var rad := Vector2(q.y - axle.y, q.z - axle.z).length()
				if absf(q.x) < ExhaustLayout.TYRE_HALF_WIDTH + pipe.radii[k]:
					intrusion = maxf(intrusion, tyre_r + pipe.radii[k] - rad)
		check(clearance > 0.1, "%d cyl %s exhaust clears the ground, got %.2f units" % [cfg[0], cfg[1], clearance])
		check(intrusion <= 0.0, "%d cyl %s exhaust stays out of the rear tyre, got %.2f units inside" % [cfg[0], cfg[1], intrusion])
		check(lay.pipes[-1].pts[-1].z > axle.z - tyre_r - 0.35, "%d cyl %s muffler ends within the tyre's rear edge, at z %.2f" % [cfg[0], cfg[1], lay.pipes[-1].pts[-1].z])
	check(tails["4-14"] > tails["stock4"], "a 4-1 header is longer than the stock manifold")
	check(tails["4-14"] > 0.8 and tails["4-14"] < 3.5, "total exhaust length is plausible, got %.2f m" % tails["4-14"])

	# physics of the pipe: a closed-open tube of length L rings at c/4L and its odd multiples, with no even multiples
	for length_m: float in [0.5, 0.8]:
		var layout := ExhaustLayout.new()
		var pipe := ExhaustLayout.Pipe.new()
		pipe.kind = "primary"
		pipe.cyl = 0
		pipe.loss = 0.05
		pipe.pts = PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, -length_m * 10.0)])
		pipe.radii = PackedFloat32Array([0.2, 0.2])
		layout.pipes.append(pipe)
		var tube := EngineSound.new()
		tube.setup(cbr, layout)
		tube._p_age[0] = 0.0
		tube._p_len[0] = 4.0
		tube._p_amp[0] = 1.0
		var x := PackedFloat32Array()
		x.resize(4096)
		for i in x.size():
			x[i] = tube._wg_step()
		var f1: float = EngineSound.SOUND_SPEED / (4.0 * length_m)
		check(_tone(x, f1) > 0.005, "%.1f m pipe rings at c/4L = %.0f Hz" % [length_m, f1])
		check(_tone(x, 3.0 * f1) > 0.005, "%.1f m pipe rings at 3 c/4L" % length_m)
		check(_tone(x, 2.0 * f1) < 0.05 * _tone(x, f1), "%.1f m pipe has no even harmonic" % length_m)
		tube.free()

	# a whole exhaust at full rpm stays finite and inside the output range, and a different header sounds different
	var rendered := {}
	for header in ["stock", "4-2-1"]:
		var sp := EngineSpec.new()
		sp.cylinders = 4
		sp.displacement_cc = 600.0
		sp.header = header
		var snd := EngineSound.new()
		snd.setup(sp)
		snd.rpm = 12000.0
		var peak := 0.0
		var energy := 0.0
		var bad := 0
		var frames := snd.render(44100 * 3)
		for fr in frames:
			if is_nan(fr.x) or is_inf(fr.x):
				bad += 1
			peak = maxf(peak, absf(fr.x))
			energy += fr.x * fr.x
		check(bad == 0 and peak <= 1.0, "%s header sound is finite and bounded, peak %.2f" % [header, peak])
		check(energy > 1.0, "%s header makes sound at 12,000 rpm" % header)
		rendered[header] = energy
		snd.free()
	check(absf(rendered["stock"] - rendered["4-2-1"]) > 0.02 * rendered["stock"], "stock and 4-2-1 headers do not sound the same")


# Sizes and positions of the drawn parts against the simulation and the real bike.
func _test_layout(cbr: EngineSpec) -> void:
	var model := EngineModel.new()
	get_root().add_child(model)
	model.build(cbr)
	var crank := model.crank_position()
	var height_cm := (crank.y - Ground.Y) * 10.0
	check(height_cm > 25.0 and height_cm < 33.0, "crank sits 25 to 33 cm above the ground, got %.1f cm" % height_cm)
	check(crank.y - EngineModel.ENGINE_LOW > Ground.Y + ExhaustLayout.GROUND_CLEARANCE + 2.0 * ExhaustLayout.COLLECTOR_R, "the engine sits above the exhaust, which keeps the ground clearance")

	# primary drive: the teeth give the spec reduction, and the clutch sits a gear-centre-distance behind the crank
	var teeth := GearboxModel.primary_teeth(cbr)
	var ratio := float(teeth.y) / teeth.x
	check(absf(ratio / cbr.primary_ratio - 1.0) < 0.01, "primary gears give the spec ratio %.2f, got %.3f" % [cbr.primary_ratio, ratio])
	var main := GearboxModel.mainshaft_position(crank, cbr)
	var counter := GearboxModel.countershaft_position(crank, cbr)
	check(absf((crank.z - main.z) - GearboxModel.MODULE * (teeth.x + teeth.y) * 0.5) < 0.001, "mainshaft is the primary centre distance behind the crank")
	check(counter.z < main.z, "the front sprocket sits behind the clutch, so the chain leaves toward the rear wheel")
	for i in Gearbox.MAIN_TEETH.size():
		var centre: float = GearboxModel.MODULE * (Gearbox.MAIN_TEETH[i] + Gearbox.COUNTER_TEETH[i]) * 0.5
		check(absf(centre - GearboxModel.SHAFT_GAP) < 0.03, "gear pair %d meshes at the shaft spacing, centre distance %.3f" % [i + 1, centre])

	# the chain runs outside the tyre, and the tank holds the simulated fuel
	check(Drivetrain.CHAIN_X > ExhaustLayout.TYRE_HALF_WIDTH + 0.1, "the chain plane is outside the rear tyre")

	# valves open by the Cylinder lift at the Cylinder timing: shut at firing TDC, intake open mid-intake, exhaust open mid-exhaust
	model.update_crank(0.0)
	check(absf(model.valve_lift(0)) < 0.0001 and absf(model.valve_lift(2)) < 0.0001, "valves are shut at firing top dead centre")
	model.update_crank(0.5 * (Cylinder.INTAKE_OPEN + Cylinder.INTAKE_CLOSE))
	check(absf(model.valve_lift(0) - Cylinder.INTAKE_LIFT * 10.0) < 0.001 and absf(model.valve_lift(2)) < 0.0001, "intake valves reach their peak lift mid-intake, exhaust shut")
	model.update_crank(0.5 * (Cylinder.EXHAUST_OPEN + Cylinder.EXHAUST_CLOSE))
	check(absf(model.valve_lift(2) - Cylinder.EXHAUST_LIFT * 10.0) < 0.001 and absf(model.valve_lift(0)) < 0.0001, "exhaust valves reach their peak lift mid-exhaust, intake shut")
	# the cam lobes are the lift curve: base circle, plus the peak lift at the nose
	for intake in [true, false]:
		var lo := INF
		var hi := 0.0
		for p in EngineModel._lobe_outline(intake):
			lo = minf(lo, p.length())
			hi = maxf(hi, p.length())
		var peak: float = Cylinder.INTAKE_LIFT if intake else Cylinder.EXHAUST_LIFT
		check(absf(lo - EngineModel.CAM_BASE) < 0.001 and absf(hi - EngineModel.CAM_BASE - peak * 10.0) < 0.01, "%s cam lobe is the base circle plus the valve lift" % ("intake" if intake else "exhaust"))
	var tank := FuelTankModel.new()
	var litres := tank.size.x * tank.size.y * tank.size.z # scene units are 10 cm, so a cubic unit is one litre
	check(absf(litres - FuelTank.TANK_LITRES) < 0.3, "the tank box holds %.1f L, expected %.0f L" % [litres, FuelTank.TANK_LITRES])
	tank.free()
	model.queue_free()
