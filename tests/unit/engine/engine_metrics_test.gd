extends SceneTree

# The cycle metrics have to agree with the shaft torque and the fuel the tank actually lost.
# Run: godot --headless -s tests/unit/engine/engine_metrics_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1


func _init() -> void:
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 2400.0
	var rpm := 6000.0
	for _i in 8000:
		sim.omega = rpm * TAU / 60.0
		sim.rpm = rpm
		sim.running = true
		sim.step(sim.physics_dt, spec, 0.6, true, false, true, false, 1.0)
	var volume := sim.swept_m3()
	var bmep := sim.cycle_brake_torque * 4.0 * PI / volume
	check(volume > 0.0 and absf(sim.bmep_pa() / bmep - 1.0) < 0.01, "BMEP is shaft torque times 4π over displacement (%.0f Pa)" % sim.bmep_pa())
	check(sim.imep_pa() > sim.bmep_pa(), "net IMEP is above BMEP (%.0f vs %.0f Pa)" % [sim.imep_pa(), sim.bmep_pa()])
	check(sim.fmep_pa() > 0.0, "FMEP is the gap between them (%.0f Pa)" % sim.fmep_pa())
	var ve := sim.volumetric_efficiency()
	check(ve > 0.5 and ve < 1.3, "measured volumetric efficiency is %.0f%%" % (ve * 100.0))
	var power_kw := sim.brake_power_w() / 1000.0
	check(power_kw > 1.0, "the shaft is making power (%.2f kW)" % power_kw)
	var bsfc := sim.fuel_flow * 3600.0 / power_kw
	check(absf(sim.bsfc_g_kwh() / bsfc - 1.0) < 0.01, "BSFC is fuel flow over brake power (%.0f g/kWh)" % sim.bsfc_g_kwh())
	check(sim.isfc_g_kwh() > 0.0 and sim.isfc_g_kwh() < sim.bsfc_g_kwh(), "ISFC is lower than BSFC (%.0f vs %.0f)" % [sim.isfc_g_kwh(), sim.bsfc_g_kwh()])
	var eta_b := sim.brake_thermal_efficiency()
	var eta_i := sim.indicated_thermal_efficiency()
	check(eta_b > 0.1 and eta_b < 0.5, "brake thermal efficiency is %.0f%%" % (eta_b * 100.0))
	check(eta_i > eta_b and eta_i < 0.6, "indicated thermal efficiency is above brake (%.0f%%)" % (eta_i * 100.0))
	check(sim.mechanical_efficiency() > 0.5 and sim.mechanical_efficiency() < 1.05, "mechanical efficiency is %.0f%%" % (sim.mechanical_efficiency() * 100.0))
	check(sim.peak_pressure_pa() > 1.5e6, "peak cylinder pressure is %.0f bar" % (sim.peak_pressure_pa() / 1.0e5))
	check(sim.peak_dp_dtheta() > 0.0, "peak pressure rise is %.2f bar/deg" % (sim.peak_dp_dtheta() / 1.0e5))
	check(sim.ca50_deg() > 0.0 and sim.ca50_deg() < 40.0, "CA50 is %.0f deg after firing top dead centre" % sim.ca50_deg())
	check(sim.burn_10_90_deg() > 5.0 and sim.burn_10_90_deg() < 80.0, "10-90 burn is %.0f deg" % sim.burn_10_90_deg())
	check(sim.ivc_temp_c() > 0.0 and sim.ivc_temp_c() < 150.0, "charge at intake closing is %.0f °C" % sim.ivc_temp_c())
	check(sim.residual_fraction() >= 0.0 and sim.residual_fraction() < 0.3, "residual gas fraction is %.0f%%" % (sim.residual_fraction() * 100.0))
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
