extends SceneTree

# Trace: gas temperature through one full-throttle cycle, sampled every few steps, to check the exhaust temperature sensor
# against the chamber peak. Usage: godot --headless --path . -s res://tools/diagnostics/cycle_temp_trace.gd

func _init() -> void:
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	for i in 720:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
	for i in 600:
		sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)
	var c = sim.cylinders[0]
	print("rpm %.0f" % sim.rpm)
	print("phi_deg  temp_K  peak_K  last_peak_K  exhaust_temp_K")
	for i in 400:
		sim.step(1.0 / 6000.0, spec, 1.0, true, false, false, false, 1.0)
		if i % 8 == 0:
			print("%7.1f  %6.0f  %6.0f  %11.0f  %14.0f" % [c.phi, c.temp, c.peak_temp, c.last_peak_temp, c.exhaust_temp])
	quit(0)
