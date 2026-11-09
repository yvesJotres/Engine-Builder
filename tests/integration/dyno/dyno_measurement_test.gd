extends SceneTree

func _init() -> void:
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	sim.gear.gear = 1
	var dyno := DynoTest.new()
	dyno.start(spec, sim) # formerly an infinite shift-down loop from first
	assert(sim.gear.gear == 0)
	dyno.cancel()
	sim.physics_dt = 1.0 / 7200.0
	dyno.start(spec, sim)
	assert(is_equal_approx(sim.physics_dt, 1.0 / 7200.0), "dyno must retain the selected high accuracy")
	dyno.cancel()
	assert(is_equal_approx(sim.physics_dt, 1.0 / 7200.0), "dyno must restore the previous accuracy")
	sim.physics_dt = 1.0 / 1200.0
	# Only independent completed cycles may enter the curve; RPM is the mean
	# during that measured cycle, not the newer instantaneous crank RPM.
	dyno.start(spec, sim)
	dyno._gear = 1
	sim.cycle_ready = true
	sim.cycle_index = 1
	sim.cycle_mean_rpm = 3000.0
	sim.rpm = 6000.0
	sim.cycle_brake_torque = 12.0
	dyno._record(sim)
	for i in 100:
		dyno._record(sim)
	var index := dyno._bins + int(3000.0 / DynoTest.BIN_RPM)
	assert(dyno._count[index] == 1.0)
	sim.cycle_index += 1
	dyno._record(sim)
	var result := dyno.result()
	assert(result.curve.size() == 1 and is_equal_approx(result.curve[0].rpm, 3000.0))
	assert(is_equal_approx(result.curve[0].hp * 745.7, 12.0 * TAU * 3000.0 / 60.0))
	dyno.cancel()
	# Cycle boundaries retain their remainder, including 360-degree two-strokes.
	var two := EngineSim.new()
	two._accumulate_cycle(10.0, 350.0, 0.035, 360.0)
	two._accumulate_cycle(20.0, 20.0, 0.002, 360.0)
	assert(two.cycle_index == 1 and is_equal_approx(two._rev_deg, 10.0))
	assert(is_equal_approx(two.cycle_brake_torque, (350.0 * 10.0 + 10.0 * 20.0) / 360.0))
	# At identical speed/inertia a roller has no road aerodynamic load.
	var roller := EngineSim.new()
	roller.cell_mass_kg = spec.road_mass_kg()
	roller.speed = 50.0
	roller._advance_driveline(0.01, spec, 0.0, 0.1, 0.0, 0.3)
	assert(is_equal_approx(roller.speed, 50.0))
	roller.cell_load_n = 100.0
	roller._advance_driveline(0.01, spec, 0.0, 0.1, 0.0, 0.3)
	assert(roller.speed < 50.0)
	# Exercise the actual coupling path, not just the standalone impulse helper.
	roller.speed = 5.0
	roller.omega = 300.0
	roller.cell_load_n = 0.0
	spec.clutch_capacity_nm = 100000.0
	var inertia := 0.03
	var mass := roller.cell_mass_kg + spec.wheel_equivalent_kg()
	var before := 0.5 * inertia * roller.omega * roller.omega + 0.5 * mass * roller.speed * roller.speed
	roller._advance_driveline(1.0 / 1200.0, spec, 0.0, inertia, 9.0, 0.3)
	var after := 0.5 * inertia * roller.omega * roller.omega + 0.5 * mass * roller.speed * roller.speed
	var expected_slip := 150.0 / (1.0 + (1.0 / 1200.0) * EngineSim.CLUTCH_STIFFNESS * (1.0 / inertia + 900.0 * EngineSim.DRIVE_EFFICIENCY / mass))
	assert(absf(roller.omega - roller.speed * 9.0 / 0.3 - expected_slip) < 0.00001)
	assert(after <= before)
	print("dyno independent cycles, neutral start and roller loads: PASS")
	quit()
