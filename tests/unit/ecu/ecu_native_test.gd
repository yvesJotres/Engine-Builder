extends SceneTree

# The native ECU (gdextension/src/ecu_model.cpp, wrapped by EcuNative) must give the same answers as scripts/ecu/ecu.gd.
# Both run on identical scripted inputs at dt 1/2400: an idle hold, a throttle blip, an overrun, a quickshifter up and down
# shift, and launch control, on a plain preset and on one with quickshifter and launch control. Every step compares the
# update() return, trim, air_factor, overrun and the quickshifter, blip and launch flags.
# Exit code 2 when EcuNative is not loaded, 1 on a mismatch.
# Run: godot --headless --path . -s res://tests/unit/ecu/ecu_native_test.gd

const DT := 1.0 / 2400.0
const REL_TOL := 1.0e-9
const SPEC_KEYS := ["quickshifter", "quickshifter_cut_time", "quickshifter_cut_profile", "quickshifter_blip_time",
	"quickshifter_blip_throttle", "quickshifter_flat_shift", "flat_shift_throttle", "launch_control", "launch_rpm",
	"launch_throttle", "launch_speed_kmh", "redline_rpm", "speed_limit_enabled", "speed_limit_kmh"]

var failures := 0


func _init() -> void:
	await process_frame
	if not ClassDB.class_exists("EcuNative"):
		print("SKIP: EcuNative is not loaded, nothing to compare")
		quit(2)
		return
	for preset in ["honda_cbr150r", "kawasaki_zx25r"]:
		var spec := EngineSpec.new()
		var p: Dictionary = Presets.PRESETS[preset]
		for key in p.keys():
			spec.set(key, p[key])
		if preset == "kawasaki_zx25r":
			spec.quickshifter = true
			spec.launch_control = true
			spec.quickshifter_cut_profile = [[], [], [[3000, 80], [9000, 40], [12000, 30]]]
		for scenario in ["idle", "blip", "overrun", "qs_up", "qs_down", "qs_flat", "launch", "limiter"]:
			if failures == 0:
				_run(preset, spec, scenario)
	print("ecu_native_test: %s" % ("PASSED" if failures == 0 else "FAILED"))
	quit(0 if failures == 0 else 1)


func _close(a: float, b: float) -> bool:
	return absf(a - b) <= REL_TOL * maxf(1.0, maxf(absf(a), absf(b)))


func _spec_dict(spec: EngineSpec) -> Dictionary:
	var d := {}
	for k in SPEC_KEYS:
		d[k] = spec.get(k)
	return d


func _run(preset: String, spec_in: EngineSpec, scenario: String) -> void:
	var spec: EngineSpec = spec_in.duplicate()
	if scenario == "qs_flat":
		spec.quickshifter_flat_shift = true
	if scenario == "limiter":
		spec.speed_limit_enabled = true
		spec.speed_limit_kmh = 100.0
	var d := _spec_dict(spec)
	var gd := ECU.new()
	var nat = ClassDB.instantiate("EcuNative")
	gd.target_rpm = 1200.0
	nat.target_rpm = 1200.0
	gd.set_power_mode("M")
	nat.set_power_mode("M")
	var steps := int(4.0 / DT)
	var gear := 3
	for i in steps:
		var t := i * DT
		var rpm := 1250.0 + 150.0 * sin(t * 3.0)
		var thr := 0.0
		var clutch := 0.0
		var speed := 0.0
		match scenario:
			"blip":
				thr = 0.5 if (t > 1.0 and t < 1.5) else 0.0
				rpm = 1250.0 + 150.0 * sin(t * 3.0) + (3000.0 * (t - 1.0) if thr > 0.0 else 0.0)
			"overrun":
				rpm = 1200.0 * 2.4 - 1080.0 * t / 4.0 * 1.6 # 2880 falling through the cut and the resume points
				if t > 2.5:
					rpm = 1700.0 - 300.0 * (t - 2.5) / 1.5
			"qs_up", "qs_down", "qs_flat":
				thr = 0.8
				rpm = 7000.0 + 200.0 * sin(t * 2.0)
				speed = 20.0
			"launch":
				thr = 1.0
				clutch = 1.0 if t < 1.0 else 0.0
				rpm = 7500.0 + 500.0 * sin(t * 5.0)
				speed = 0.0 if t < 1.0 else minf(15.0 * (t - 1.0), 14.0)
			"limiter":
				thr = 0.6
				rpm = 6000.0
				speed = 26.0 + 2.0 * sin(t * 4.0) # about 100 km/h with the 2 km/h hysteresis crossed both ways
		var a: float = gd.update(DT, rpm, thr, true, spec, speed, clutch, gear)
		var b: float = nat.update(DT, rpm, thr, true, d, speed, clutch, gear)
		var cut_i := int(1.0 / DT)
		# the triggers go in after the step, as the sim does
		if i == cut_i:
			if scenario == "qs_up" or scenario == "qs_flat":
				if gd.trigger_quickshifter(spec) != nat.trigger_quickshifter(d):
					_fail(preset, scenario, i, "trigger_quickshifter", 0.0, 0.0)
			elif scenario == "qs_down":
				if gd.trigger_quickshifter_downshift(spec) != nat.trigger_quickshifter_downshift(d):
					_fail(preset, scenario, i, "trigger_quickshifter_downshift", 0.0, 0.0)
		if not _same(preset, scenario, i, a, b, gd, nat):
			return


func _same(preset: String, scenario: String, i: int, a: float, b: float, gd: ECU, nat) -> bool:
	var floats := {"update": [a, b], "trim": [gd.trim, nat.trim], "air_factor": [gd.air_factor(), nat.air_factor()],
		"launch_target_rpm": [gd.get_launch_target_rpm(), nat.get_launch_target_rpm()],
		"lambda_mult": [gd.get_power_mode_lambda_mult(), nat.get_power_mode_lambda_mult()],
		"timing_offset": [gd.get_power_mode_timing_offset(), nat.get_power_mode_timing_offset()]}
	for k in floats:
		if not _close(floats[k][0], floats[k][1]):
			_fail(preset, scenario, i, k, floats[k][0], floats[k][1])
			return false
	var flags := {"overrun": [gd.overrun(), nat.overrun()], "qs_active": [gd.is_quickshifter_active(), nat.is_quickshifter_active()],
		"qs_cut": [gd.quickshifter_cut_active(), nat.quickshifter_cut_active()],
		"blip": [gd.is_quickshifter_blip_active(), nat.is_quickshifter_blip_active()],
		"blip2": [gd.quickshifter_blip_active(), nat.quickshifter_blip_active()],
		"launch": [gd.is_launch_active(), nat.is_launch_active()]}
	for k in flags:
		if flags[k][0] != flags[k][1]:
			_fail(preset, scenario, i, k, float(flags[k][0]), float(flags[k][1]))
			return false
	return true


func _fail(preset: String, scenario: String, i: int, what: String, gd_v: float, nat_v: float) -> void:
	failures += 1
	print("FAIL %s %s step %s %s: gd=%s native=%s" % [preset, scenario, str(i), what, str(gd_v), str(nat_v)])
