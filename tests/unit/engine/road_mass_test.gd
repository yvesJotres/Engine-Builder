extends SceneTree

func _init() -> void:
	var spec := EngineSpec.new()
	spec.vehicle_kg = 165.0
	spec.rider_kg = 75.0
	spec.vehicle_mass_includes_rider = false
	assert(is_equal_approx(spec.road_mass_kg(), 240.0))
	spec.vehicle_mass_includes_rider = true
	assert(is_equal_approx(spec.road_mass_kg(), 165.0))
	# A neutral coast must obey F=ma using the combined road mass, without
	# transmitting crankshaft torque to the wheel.
	spec.vehicle_mass_includes_rider = false
	var sim := EngineSim.new()
	sim.audio_enabled = false
	sim.speed = 20.0
	var dt := 1.0 / 7200.0
	sim.physics_dt = dt
	var expected := 20.0 - (0.5 * 1.2 * spec.drag_area_m2 * 20.0 * 20.0 + 0.015 * 240.0 * 9.81) / (240.0 + spec.wheel_equivalent_kg()) * dt
	sim.step(dt, spec, 0.0, false, false, false, false, 1.0)
	assert(absf(sim.speed - expected) < 0.000001, "road mass is used in Newton's law")
	print("road mass: PASS")
	quit()
