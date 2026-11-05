extends SceneTree

# Wide-open torque and power sweep of the CBR150R cylinder model, to compare with the published curve
# (published for the 2017+ K45: 13.7 N·m at 7,000 rpm, 17.1 hp (12.6 kW) at 9,000 rpm, from cyclechaos and moto-data;
# the 13.3 N·m at 7,560 rpm and 15.1 PS at 9,040 rpm figures are wheel dyno numbers, not crank).
# Run: godot --headless -s tools/diagnostics/dyno_sweep.gd

const DPHI := 30.0 # crank step, 24 per cycle, so the averaging window is whole cycles


func _init() -> void:
	var spec := EngineSpec.new()
	for rpm in range(2000, 11001, 1000):
		var c := Cylinder.new()
		c.setup(spec.bore_mm, spec.stroke_mm, spec.compression_ratio, spec.reciprocating_kg(), spec.rod_over_crank_radius())
		var man := EngineAir.new()
		var tank := FuelTank.new()
		var dphi := DPHI
		var dt := DPHI / (rpm * 6.0)
		var ign := 720.0 - EngineAir.spark_advance_deg(rpm)
		var sum := 0.0
		var n := 0
		var drawn := 0.0
		var pm := 0.0
		var cycles := 16
		var steps := int(cycles * 720.0 / dphi)
		var start := steps - 6 * int(720.0 / dphi) # last six whole cycles
		for i in steps:
			var r := c.advance(dphi, dt, man.pressure, EngineAir.T0, ign, true, tank, 1.0)
			man.manifold_update(dt, 1.0, r.y / dt)
			if i >= start:
				sum += r.x
				n += 1
				drawn += r.y
				pm += man.pressure
		var gas := sum / n
		var friction := EngineSim.FRICTION_BASE + 2.0 * EngineSim.MAIN_BEARING_FRICTION + EngineSim.BALANCER_FRICTION + EngineSim.FRICTION_PER_RPM * rpm
		var shaft := gas - friction
		var per_cycle := drawn / (n * dphi / 720.0)
		print("%5d rpm  gas %6.2f  shaft %6.2f N·m  %5.2f kW  VE %3.0f%%  manifold %5.1f kPa" % [rpm, gas, shaft, shaft * rpm * TAU / 60.0 / 1000.0, 100.0 * per_cycle / (Cylinder.P0 * c.swept / (Cylinder.R * EngineAir.T0)), pm / n / 1000.0])
	quit()
