extends SceneTree

const WRITER := preload("res://scripts/audio/wav_writer.gd")

func _init() -> void:
	var preset: Dictionary = Presets.PRESETS["honda_v3r900"]
	var spec := EngineSpec.new()
	for property in spec.get_property_list():
		if preset.has(property.name):
			spec.set(property.name, preset[property.name])
	var model := EngineModel.new()
	root.add_child(model)
	model.build(spec)
	var layout := ExhaustLayout.build(spec, model.exhaust_ports(), model.crank_position(), Ground.Y, Vector3(0, Ground.Y + 3.0, -5.0))
	var dir := ProjectSettings.globalize_path("res://tools/diagnostics/samples")
	DirAccess.make_dir_recursive_absolute(dir)
	for scenario in [["idle", 1200.0, 0.0], ["steady", 5000.0, 0.35], ["blip", 6000.0, 0.8]]:
		var sim := EngineSim.new()
		sim.set_audio_layout(layout, spec.cylinders)
		sim.fuel.set_kind(spec.fuel)
		var sound := EngineSound.new()
		sound.setup(spec, layout)
		var writer := WRITER.new()
		var path := dir.path_join("v3r_%s.wav" % scenario[0])
		if writer.open(path, int(EngineSound.RATE), 1, 16) != "":
			push_error("Unable to create " + path)
			quit(1)
			return
		var peak := 0.0
		for frame in 120:
			var throttle: float = scenario[2]
			var target_rpm: float = scenario[1]
			if scenario[0] == "blip":
				var pulse := maxf(0.0, 1.0 - absf(float(frame) - 90.0) / 24.0)
				throttle = pulse
				target_rpm = 2000.0 + 5000.0 * pulse
			sim.rpm = target_rpm
			sim.omega = sim.rpm * TAU / 60.0
			sim.running = true
			sim.step(1.0 / 60.0, spec, throttle, true, false, true, false, 1.0)
			sound.compressor_load = sim.intake.compressor_load
			sound.push_flow(sim.take_blowdown())
			sound.push_intake_flow(sim.take_intake_flow())
			var samples := sound.render(735)
			if frame >= 60:
				writer.store_samples(samples)
				for sample in samples:
					peak = maxf(peak, absf(sample.x))
		writer.finish()
		print("V3R sample ", path, " peak=", peak)
		sound.free()
	model.free()
	quit()
