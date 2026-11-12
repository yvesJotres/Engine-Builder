extends SceneTree

# Every preset leaves runner_bore_mm unset, so Cylinder falls back to RUNNER_AREA = 6.6e-4 m2 - a single 29 mm tube -
# for the 250s AND for a 1000cc four whose intake valves are 32.5 mm across and which runs one throttle body per cylinder.
# This sweeps the runner bore to see whether the missing area is what makes volumetric efficiency FALL with rpm
# (0.895 at 4000 -> 0.807 at 13500 on the CBR1000RR-R) where a real engine's climbs.
#
# Prints VE and rear-wheel hp at 4000 and 13500 rpm for each bore, next to the measured figures.
# Run: godot --headless --path . -s res://tools/diagnostics/probe_runner_area.gd

const BORES := [29.0, 34.0, 38.0, 42.0, 46.0]
const CASES := [
	["honda_cbr1000rrr_sp", 33.0, 199.76], # 4000 rpm hp, 13900 rpm hp (measured)
	["yamaha_yzf_r1m", 40.1, 177.10],
	["kawasaki_ninja_300", 8.5, 33.0],
	["honda_cbr250rr_2020", 7.83, 35.1],
]


func _hold(sim: EngineSim, spec: EngineSpec, rpm: float) -> Dictionary:
	var dt := sim.physics_dt
	var revs := 0.0
	sim.running = true
	while revs < 12.0:
		sim.omega = rpm * TAU / 60.0
		sim.rpm = rpm
		sim.step(dt, spec, 1.0, true, false, true, false, 1.0)
		revs += rpm * dt / 60.0
	var hp := Units.power_kw(sim.cycle_brake_torque, rpm) / 0.7457 * EngineSim.DRIVE_EFFICIENCY
	return {"ve": EngineMetrics.volumetric_efficiency(sim), "hp": hp}


func _init() -> void:
	await process_frame
	for case in CASES:
		var id: String = case[0]
		var measured_low: float = case[1]
		var measured_high: float = case[2]
		var preset: Dictionary = Presets.PRESETS[id]
		print("")
		print("== %s   measured: %.1f hp @4000, %.1f hp @top" % [id, measured_low, measured_high])
		print("   %6s %7s %8s %8s %7s %8s" % ["bore", "VE 4k", "hp 4k", "VE top", "hp top", "vs meas"])
		for bore in BORES:
			var spec := EngineSpec.new()
			for key in preset:
				spec.set(key, preset[key])
			spec.runner_bore_mm = bore
			var sim := EngineSim.new()
			sim.audio_enabled = false
			sim.physics_dt = 1.0 / 2400.0
			var low := _hold(sim, spec, 4000.0)
			var high := _hold(sim, spec, spec.redline_rpm * 0.93)
			print("   %6.0f %7.3f %8.2f %8.3f %7.1f %+7.1f%%" % [
				bore, low.ve, low.hp, high.ve, high.hp, (high.hp / measured_high - 1.0) * 100.0])
	quit(0)
