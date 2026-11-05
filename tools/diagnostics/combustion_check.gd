extends SceneTree

# Per speed, at wide open throttle and steady state: peak gas temperature and pressure, the crank angle where the peak
# pressure falls, and CA50, the crank angle (after firing TDC) where half the charge is burnt. A typical petrol engine
# peaks near 2,700 to 3,000 K and 50 to 60 bar, with CA50 about 8 to 12 degrees after TDC at best torque. Run:
# godot --headless -s tools/diagnostics/combustion_check.gd


func _init() -> void:
	var spec := EngineSpec.new()
	for rpm in [1500.0, 3000.0, 6000.0, 9000.0]:
		var c := Cylinder.new()
		c.setup(spec.bore_mm, spec.stroke_mm, spec.compression_ratio, spec.reciprocating_kg(), spec.rod_over_crank_radius())
		var tank := FuelTank.new()
		tank.mass_kg = 10.0
		var man := EngineAir.new()
		var dphi := 2.5 # crank degrees per call, so CA50 is read to within about 2.5 degrees at every speed
		var dt: float = dphi / (float(rpm) * 6.0)
		var ign := 720.0 - EngineAir.spark_advance_deg(rpm)
		c.start_at(0.0)
		var max_t := 0.0
		var max_p := 0.0
		var p_angle := 0.0
		var ca50 := -1.0
		var calls := int(4.0 * 720.0 / dphi)
		var window := int(720.0 / dphi)
		var work := 0.0 # indicated work over the last cycle, J
		var fuel_j := 0.0 # fuel energy of that cycle, J
		var wall_j := 0.0 # heat lost to the walls over that cycle, J
		var out_j := 0.0 # gas enthalpy carried out over that cycle, J
		var in_j := 0.0 # gas enthalpy brought in over that cycle, J
		for i in calls:
			var before := [c.wall_loss_j, c.enthalpy_out_j, c.enthalpy_in_j]
			var r := c.advance(dphi, dt, man.pressure, EngineAir.T0, ign, true, tank, 1.0)
			man.manifold_update(dt, 1.0, r.y / dt)
			if i >= calls - window:
				work += r.x * deg_to_rad(dphi)
				fuel_j = c.burn_energy
				wall_j += c.wall_loss_j - before[0]
				out_j += c.enthalpy_out_j - before[1]
				in_j += c.enthalpy_in_j - before[2]
				if c.temp > max_t:
					max_t = c.temp
				if c.pressure > max_p:
					max_p = c.pressure
					p_angle = fmod(c.phi, 720.0)
				if ca50 < 0.0 and c._burnt >= 0.5:
					ca50 = fmod(c.phi, 720.0)
		print("%5.0f rpm: peak T %4.0f K, peak p %4.1f bar at %3.0f deg, CA50 %4.1f deg ATDC, spark %4.1f deg BTDC, indicated efficiency %.2f, wall loss %.2f, exhaust enthalpy %.2f, balance error %.2f" % [
			rpm, max_t, max_p / 100000.0, p_angle, ca50, EngineAir.spark_advance_deg(rpm), work / fuel_j if fuel_j > 0.0 else 0.0, wall_j / fuel_j if fuel_j > 0.0 else 0.0, (out_j - in_j) / fuel_j if fuel_j > 0.0 else 0.0, (fuel_j - work - wall_j - (out_j - in_j)) / fuel_j if fuel_j > 0.0 else 0.0])
	quit()
