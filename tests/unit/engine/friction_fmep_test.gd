extends SceneTree

# docs/engine_physics/09: the four-stroke friction uses the Chen–Flynn form. The implemented
# coefficient set is Reitz (2018), and this test fixes the form and its monotonicity.
func _init() -> void:
	var spec := EngineSpec.new()
	spec.bore_mm = 62.3
	spec.stroke_mm = 41.4
	spec.displacement_cc = 249.7
	var low := EngineSim.fmep_pa_for(spec, 3000.0, 40.0e5)
	var high := EngineSim.fmep_pa_for(spec, 13000.0, 60.0e5)
	var high_low_pressure := EngineSim.fmep_pa_for(spec, 13000.0, 40.0e5)
	var ok := low > 0.0
	ok = ok and high > low
	ok = ok and high > high_low_pressure
	var low_bar := low / 1e5
	var high_bar := high / 1e5
	var low_expected := 0.25 + 0.005 * 40.0 + 0.1 * (2.0 * 0.0414 * 3000.0 / 60.0)
	var high_expected := 0.25 + 0.005 * 60.0 + 0.1 * (2.0 * 0.0414 * 13000.0 / 60.0)
	ok = ok and absf(low_bar - low_expected) < 1e-6 and absf(high_bar - high_expected) < 1e-6
	print("FMEP 3000 rpm %.3f bar, 13000 rpm %.3f bar, 13000/40 bar %.3f bar" % [low_bar, high_bar, high_low_pressure / 1e5])
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
