extends SceneTree

func _init() -> void:
	var spec := EngineSpec.new()
	var air := EngineAir.new()
	air.pressure = 70000.0
	var dt := 0.00001
	var draw := 0.002
	var inlet := air._orifice(EngineAir.THROTTLE_AREA) + air._orifice(air.bypass_area)
	var expected := air.pressure + EngineAir.R_AIR * EngineAir.T0 / EngineAir.MANIFOLD_VOLUME * (inlet - draw) * dt
	spec.ve_scale = 2.0 # legacy value must not remove air the cylinders did not receive
	air.manifold_update(dt, 1.0, draw, spec)
	assert(absf(air.pressure - expected) < 0.001, "manifold mass accounting")
	var single := EngineAir.new()
	var twin := EngineAir.new()
	single.pressure = 70000.0
	twin.pressure = single.pressure
	single.bypass_area = 0.0
	twin.bypass_area = 0.0
	spec.throttle_count = 1
	single.manifold_update(dt, 1.0, 0.0, spec)
	spec.throttle_count = 2
	twin.manifold_update(dt, 1.0, 0.0, spec)
	assert(is_equal_approx(twin.pressure - 70000.0, 2.0 * (single.pressure - 70000.0)), "parallel throttle mass flow")
	print("intake conservation: PASS")
	quit()
