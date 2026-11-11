extends SceneTree

# Renders the exhaust sound on one preset, driven by the real engine simulation.
# A start, then a throttle sweep from idle to redline in neutral. Output goes to calibration/ as a WAV file.
# Run with: godot --headless --path . -s tools/diagnostics/render_calibration.gd

const PRESET := "honda_cbr250rr"
const DT := 1.0 / 60.0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://calibration")
	var spec := _spec(PRESET)
	var snd := EngineSound.new()
	snd.setup(spec)
	var sim := EngineSim.new()
	sim.exhaust_solver = true
	sim.fuel.set_kind(spec.fuel)
	var mono := PackedFloat32Array()
	var t := 0.0
	while t < 14.0:
		var throttle := 0.0
		var starter := not sim.running and t < 6.0
		if t >= 6.0:
			throttle = clampf((t - 6.0) / 6.0, 0.0, 1.0)
		sim.step(DT, spec, throttle, true, starter, false, false, 1.0)
		snd.rpm = sim.rpm
		if sim.exhaust != null:
			snd.push_flow(sim.exhaust.take_flow())
		for f in snd.render(int(EngineSound.RATE * DT)):
			mono.append(f.x)
		t += DT
	_write_wav("res://calibration/sim_cbr250.wav", mono)
	print("wrote calibration/sim_cbr250.wav")
	snd.free()
	quit()


# Builds the spec the same way the sim does, so the sound uses the preset's cylinders and firing.
func _spec(name: String) -> EngineSpec:
	var s := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS[name]
	s.cylinders = p.cylinders
	s.bore_mm = p.bore_mm
	s.stroke_mm = p.stroke_mm
	s.displacement_cc = Units.displacement_cc(s.bore_mm, s.stroke_mm, s.cylinders)
	s.twin_pin_deg = p.get("twin_pin_deg", 360.0)
	s.crossplane = p.get("crossplane", false)
	s.header = p.header
	s.fuel = p.fuel
	s.redline_rpm = p.redline_rpm
	s.rod_ratio = p.rod_ratio
	s.compression_ratio = p.get("compression_ratio", 11.3)
	s.flywheel_kg = p.flywheel_kg
	s.flywheel_radius_mm = p.flywheel_radius_mm
	s.vehicle_kg = p.get("vehicle_kg", 215.0)
	return s


# Writes 16-bit mono PCM at the sound's sample rate.
func _write_wav(path: String, samples: PackedFloat32Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	var data_bytes := samples.size() * 2
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data_bytes)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(int(EngineSound.RATE))
	f.store_32(int(EngineSound.RATE) * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data_bytes)
	for s in samples:
		f.store_16(int(clampf(s, -1.0, 1.0) * 32767.0))
	f.close()
