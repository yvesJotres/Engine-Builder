extends SceneTree


func heat_loss(wall_temp: float, native: bool) -> float:
	Cylinder.use_native = native
	var spec := EngineSpec.new()
	var cylinder := Cylinder.new()
	cylinder.setup(spec.bore_mm, spec.stroke_mm, spec.compression_ratio, spec.reciprocating_kg(), spec.rod_over_crank_radius())
	cylinder.set_cams(spec)
	cylinder.start_at(180.0)
	cylinder.temp = 600.0
	cylinder.pressure = 200000.0
	cylinder.mass = cylinder.pressure * cylinder.volume(cylinder.phi) / (Cylinder.R * cylinder.temp)
	cylinder._u = cylinder.mass * GasProperties.u(0.0, cylinder.temp)
	cylinder.wall_temp_k = wall_temp
	var tank := FuelTank.new()
	cylinder.advance(2.0, 1.0 / 6000.0, Cylinder.P0, 300.0, 720.0, false, tank, 1.0, false)
	return cylinder.wall_loss_j


func _init() -> void:
	var cold := heat_loss(320.0, false)
	var warm := heat_loss(500.0, false)
	assert(cold > warm and warm > 0.0)
	assert(absf(heat_loss(500.0, true) - warm) < 1.0e-9)
	Cylinder.use_native = true
	print("wall_temperature_test: PASS")
	quit()
