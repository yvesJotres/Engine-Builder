extends SceneTree

func _init() -> void:
	await process_frame
	var spec = EngineSpec.new()
	spec.cylinders = 1
	spec.displacement_cc = 149.2
	spec.bore_mm = 57.3
	spec.stroke_mm = 57.8
	spec.rod_ratio = 1.6
	spec.layout = "inline"
	spec.header = "stock"
	spec.fuel = "ron95"
	spec.redline_rpm = 10600.0
	spec.flywheel_kg = 2.5
	spec.flywheel_radius_mm = 75.0
	spec.compression_ratio = 11.3
	spec.primary_ratio = 3.26
	spec.final_drive = 3.0
	spec.gear_ratios = [3.0833, 1.9412, 1.5, 1.2273, 1.0417, 0.9231]
	spec.intake_centre_deg = 470.0
	spec.intake_duration_deg = 240.0
	spec.intake_lift_mm = 6.0
	spec.exhaust_centre_deg = 255.0
	spec.exhaust_duration_deg = 230.0
	spec.exhaust_lift_mm = 5.0
	spec.ignition_offset_deg = 0.0
	spec.flywheel_radius_mm = 75.0
	spec.vehicle_kg = 215.0
	
	var sim = EngineSim.new()
	var fuel = FuelTank.new()
	fuel.set_kind("ron95")
	sim.fuel = fuel
	
	print("=== CBR150R TEMPERATURE TEST ===")
	print("Spec: 149.2cc, 11.3:1 CR, RON95, 10600 rpm redline")
	print()
	
	# CRANK THE ENGINE TO START IT
	print("--- CRANKING (starter held, ignition on) ---")
	for i in 300:
		sim.step(0.01, spec, 0.0, true, true, false, false, 1.0)
		if i % 50 == 0:
			print("  Crank RPM: " + str(int(sim.rpm)))
	
	print("After cranking - RPM: " + str(int(sim.rpm)))
	print("Running: " + str(sim.running))
	print()
	
	# Now let it run at idle (no starter, ignition on, throttle closed)
	print("--- IDLE WARMUP (ignition on, no starter, throttle 0%) ---")
	for i in 300:
		sim.step(0.01, spec, 0.0, true, false, false, false, 1.0)
	
	print("--- IDLE (throttle 0%, target 1200 rpm) ---")
	print("RPM: " + str(int(sim.rpm)))
	print("Exhaust temp: " + str(int(sim.exhaust_temp_c())) + " °C")
	print("Chamber peak: " + str(int(sim.chamber_peak_c())) + " °C")
	var ports = sim.port_temps_c()
	var port_str = ""
	for t in ports:
		port_str += str(int(t)) + " "
	print("Port temps: " + port_str + "°C")
	print("Intake pressure: " + str(sim.intake.pressure / 1000.0) + " kPa")
	print("Lambda: " + str(sim.o2_lambda()))
	print("Fuel flow: " + str(sim.fuel_flow) + " g/s")
	print()
	
	# Run at wide open throttle
	print("--- WOT HIGH RPM (throttle 100%) ---")
	for i in 400:
		sim.step(0.01, spec, 1.0, true, false, false, false, 1.0)
	
	print("RPM: " + str(int(sim.rpm)))
	print("Exhaust temp: " + str(int(sim.exhaust_temp_c())) + " °C")
	print("Chamber peak: " + str(int(sim.chamber_peak_c())) + " °C")
	ports = sim.port_temps_c()
	port_str = ""
	for t in ports:
		port_str += str(int(t)) + " "
	print("Port temps: " + port_str + "°C")
	print("Intake pressure: " + str(sim.intake.pressure / 1000.0) + " kPa")
	print("Lambda: " + str(sim.o2_lambda()))
	print("Fuel flow: " + str(sim.fuel_flow) + " g/s")
	print("Torque: " + str(sim.torque) + " Nm")
	print("Power: " + str(sim.torque * sim.rpm * 2 * PI / 60 / 746) + " hp")
	print()
	
	# Run at redline
	print("--- REDLINE (10600 rpm) ---")
	for i in 300:
		sim.step(0.01, spec, 1.0, true, false, false, false, 1.0)
	
	print("RPM: " + str(int(sim.rpm)))
	print("Exhaust temp: " + str(int(sim.exhaust_temp_c())) + " °C")
	print("Chamber peak: " + str(int(sim.chamber_peak_c())) + " °C")
	ports = sim.port_temps_c()
	port_str = ""
	for t in ports:
		port_str += str(int(t)) + " "
	print("Port temps: " + port_str + "°C")
	print("Intake pressure: " + str(sim.intake.pressure / 1000.0) + " kPa")
	print("Lambda: " + str(sim.o2_lambda()))
	print("Fuel flow: " + str(sim.fuel_flow) + " g/s")
	print("Torque: " + str(sim.torque) + " Nm")
	print("Power: " + str(sim.torque * sim.rpm * 2 * PI / 60 / 746) + " hp")
	
	print("RESULT: PASS")
	quit(0)
