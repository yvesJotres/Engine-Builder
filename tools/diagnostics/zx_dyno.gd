extends SceneTree

# Diagnostic: the ZX-25R preset's wide-open shaft torque and power across the rev range, against the published 22.9 N·m
# at 14,500 rpm and 51 PS at 15,500 rpm. Same method as dyno_sweep.gd. Print only.
const DPHI := 30.0

func _init() -> void:
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS["kawasaki_zx25r"]
	for key in p.keys():
		spec.set(key, p[key])
	for rpm in [4000, 6000, 8000, 10000, 12000, 14000, 15000, 16000]:
		var c := Cylinder.new()
		c.setup(spec.bore_mm, spec.stroke_mm, spec.compression_ratio, spec.reciprocating_kg(), spec.rod_over_crank_radius())
		var man := EngineAir.new()
		var tank := FuelTank.new()
		var dt: float = DPHI / (rpm * 6.0)
		var ign := 720.0 - EngineAir.spark_advance_deg(rpm)
		var sum := 0.0
		var n := 0
		var steps := int(16 * 720.0 / DPHI)
		var start := steps - 6 * int(720.0 / DPHI)
		for i in steps:
			var r := c.advance(DPHI, dt, man.pressure, EngineAir.T0, ign, true, tank, 1.0)
			man.manifold_update(dt, 1.0, r.y / dt)
			if i >= start:
				sum += r.x
				n += 1
		var gas := sum / n
		var friction: float = EngineSim.FRICTION_BASE + 2.0 * EngineSim.MAIN_BEARING_FRICTION + EngineSim.BALANCER_FRICTION + EngineSim.FRICTION_PER_RPM * rpm + spec.cylinders * EngineSim.FRICTION_PER_CYLINDER * (spec.bore_mm / 57.3)
		var shaft: float = gas - friction
		print("%5d rpm  gas %6.2f  shaft %6.2f N·m  %6.2f kW  %5.1f PS" % [rpm, gas, shaft, shaft * rpm * TAU / 60.0 / 1000.0, shaft * rpm * TAU / 60.0 / 735.5])
	quit()
