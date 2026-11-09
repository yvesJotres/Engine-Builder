extends SceneTree

# Launch control on the ZX-25R. Pulling the lever in at full throttle arms it, and the engine is held near the launch rpm.
# Letting the lever go starts the launch: the clutch slips at its target and the bike pulls away while the rpm stays at the
# target. The launch ends at the launch speed. Exits 1 on any failure.
# Run: godot --headless --path . -s res://tests/unit/ecu/launch_control_test.gd

const DT := 1.0 / 60.0
const RPM_TOLERANCE := 0.15 # the rpm hold must stay within 15% of the target while launch is active

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS["kawasaki_zx25r"]
	for key in preset.keys():
		spec.set(key, preset[key])
	spec.launch_control = true
	var sim := EngineSim.new()
	sim.audio_enabled = false

	for i in 180:
		sim.step(DT, spec, 0.0, true, true, false, false, 1.0)
	check(sim.running, "the engine starts")
	sim.gear.gear = 1

	# arm: lever in, throttle wide open, until the rpm reaches the launch target
	sim.clutch_pull = 1.0
	var armed := false
	for i in 120:
		sim.step(DT, spec, 1.0, true, false, false, false, 1.0)
		if sim.ecu.is_launch_active():
			armed = true
			break
	check(armed, "pulling the lever in at full throttle arms launch control")
	var target: float = sim.ecu.get_launch_target_rpm()
	for i in 60:
		sim.step(DT, spec, 1.0, true, false, false, false, 1.0)
	check(absf(sim.rpm - target) < target * RPM_TOLERANCE, "the rpm settles near the launch target while the lever is in, rpm %.0f target %.0f" % [sim.rpm, target])

	# launch: let the lever go, and the clutch slips while the rpm holds
	sim.clutch_pull = 0.0
	var worst := 0.0
	var ended_at := -1.0
	var speed_at_start: float = sim.speed
	for i in 300:
		sim.step(DT, spec, 1.0, true, false, false, false, 1.0)
		if sim.ecu.is_launch_active():
			# the target ramps up as the bike gains speed, so the hold is measured against the live target
			var live: float = sim.ecu.get_launch_target_rpm()
			worst = maxf(worst, absf(sim.rpm - live) / live)
		elif ended_at < 0.0:
			ended_at = i * DT
	check(ended_at < 0.0 or sim.speed * 3.6 >= spec.launch_speed_kmh - 0.5, "the launch does not end before the launch speed")
	check(worst < RPM_TOLERANCE, "letting the lever go keeps the rpm within %d%% of the target, worst %.1f%%" % [int(RPM_TOLERANCE * 100), worst * 100.0])
	check(sim.speed > speed_at_start + 2.0 / 3.6, "the bike pulls away from the launch, speed %.1f km/h" % (sim.speed * 3.6))
	check(ended_at >= 0.0, "the launch ends once the bike reaches the launch speed")

	print("launch_control_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
