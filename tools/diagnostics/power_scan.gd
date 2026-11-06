extends SceneTree

# Diagnostic: the CBR150R's gas torque at 7,000 rpm wide open, against spark advance and mixture, with the friction split out.
# Same method as dyno_sweep.gd. Print only.
const DPHI := 30.0

func gas_at(rpm: float, offset: float, lam: float) -> float:
	var spec := EngineSpec.new()
	var c := Cylinder.new()
	c.setup(spec.bore_mm, spec.stroke_mm, spec.compression_ratio, spec.reciprocating_kg(), spec.rod_over_crank_radius())
	var man := EngineAir.new()
	var tank := FuelTank.new()
	var dt := DPHI / (rpm * 6.0)
	var ign := 720.0 - EngineAir.spark_advance_deg(rpm, offset)
	var sum := 0.0
	var n := 0
	var steps := int(16 * 720.0 / DPHI)
	var start := steps - 6 * int(720.0 / DPHI)
	for i in steps:
		var r := c.advance(DPHI, dt, man.pressure, EngineAir.T0, ign, true, tank, lam)
		man.manifold_update(dt, 1.0, r.y / dt)
		if i >= start:
			sum += r.x
			n += 1
	return sum / n

func _init() -> void:
	var rpm := 7000.0
	var friction := EngineSim.FRICTION_BASE + 2.0 * EngineSim.MAIN_BEARING_FRICTION + EngineSim.BALANCER_FRICTION + EngineSim.FRICTION_PER_RPM * rpm + 0.1
	print("friction at 7000 rpm (single cylinder, as the sim takes it): %.2f N·m" % friction)
	for offset in [-4.0, 0.0, 4.0, 8.0]:
		for lam in [0.9, 1.0, 1.1]:
			var g := gas_at(rpm, offset, lam)
			print("advance %+4.0f deg  lambda %.1f  gas %6.2f N·m  shaft %6.2f N·m" % [offset, lam, g, g - friction])
	quit()
