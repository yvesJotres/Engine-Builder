extends SceneTree

const DT := 1.0 / 60.0

func _init() -> void:
	var spec := EngineSpec.new()
	for key in Presets.PRESETS["honda_cbr1000rrr_sp"].keys():
		spec.set(key, Presets.PRESETS["honda_cbr1000rrr_sp"][key])
	var sim := EngineSim.new()
	sim.audio_enabled = false
	for i in 240:
		sim.step(DT, spec, 0.0, true, i < 60, false, false, 1.0)
	sim.gear.gear = 0
	sim.clutch_pull = 1.0
	# hold the speed as a dynamometer does, and let the engine settle for a second at each point
	for rpm in [4000.0, 7000.0, 9000.0, 11000.0, 13000.0, 14500.0]:
		for i in 90:
			sim.rpm = rpm
			sim.omega = rpm * TAU / 60.0
			sim.step(DT, spec, 1.0, true, false, false, false, 1.0)
		var bmep: float = sim.bmep_pa() / 1e5
		var torque: float = bmep * 1e5 * (spec.displacement_cc * 1e-6) / (4.0 * PI)
		var hp: float = Units.w_to_hp(Units.power_w(torque, rpm))
		print("%5.0f rpm: bmep %6.2f bar -> %5.1f Nm, %5.1f hp | VE %3.0f%% | pmax %4.0f bar | egt %4.0f C | lambda %.2f" % [
			rpm, bmep, torque, hp, sim.volumetric_efficiency() * 100.0, sim.peak_pressure_pa() / 1e5, sim.exhaust_temp_c(), sim.o2_lambda()])
	print("real bike:     11,000 rpm: 113 Nm / 14.2 bar / 175 hp; 14,500: 214 hp; VE 1.0-1.15; pmax 70-80 bar; egt 800-900 C")
	quit(0)
