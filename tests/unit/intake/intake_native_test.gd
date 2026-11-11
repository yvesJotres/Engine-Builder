extends SceneTree

# IntakeNative (gdextension/src/intake_native.cpp) must match the GDScript EngineAir step for step.
# Same spec, same throttle/rpm sweep, same drawn flow (taken from the GDScript manifold pressure and fed to both).
# Run: godot --headless --path . -s tests/unit/intake/intake_native_test.gd
const PRESETS := ["honda_cbr150r", "amg_m276_v6", "honda_v3r900"]
const THROTTLES := [0.0, 0.3, 1.0]
const RPMS := [1500.0, 6000.0, 9000.0]
const DT := 1.0 / 2400.0
const STEPS := 7200 # 3 s per combination
const REL_TOL := 1.0e-6
const SPEC_KEYS := ["electric_compressor", "compressor_map_id", "max_boost_ratio", "compressor_battery_wh", "compressor_power_w",
	"compressor_charge_w", "boost_spool_time", "compressor_inertia_kgm2", "wastegate_type", "wastegate_pressure_ratio",
	"turbine_efficiency", "intake_area_scale", "throttle_bore_mm", "throttle_count", "manifold_volume_scale"]

var failures := 0


func _init() -> void:
	await process_frame
	if not ClassDB.class_exists("IntakeNative"):
		print("SKIP: IntakeNative is not registered")
		quit(2)
		return
	for preset in PRESETS:
		for t in THROTTLES:
			for r in RPMS:
				_compare(preset, t, r)
	print("intake_native_test: %s" % ("PASSED" if failures == 0 else "FAILED (%d problems)" % failures))
	quit(0 if failures == 0 else 1)


func _close(a: float, b: float) -> bool:
	return absf(a - b) <= REL_TOL * maxf(absf(a), absf(b)) + 1.0e-12


func _compare(preset: String, throttle: float, rpm: float) -> void:
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS[preset]
	for key in p.keys():
		spec.set(key, p[key])
	var air := EngineAir.new()
	air.setup(spec)
	var spec_dict := {}
	for k in SPEC_KEYS:
		spec_dict[k] = spec.get(k)
	var map_dict := {}
	if spec.compressor_map_id != "":
		var f := FileAccess.open("res://assets/compressor_maps/" + spec.compressor_map_id + ".json", FileAccess.READ)
		map_dict = JSON.parse_string(f.get_as_text())
		f.close()
	var nat := IntakeNative.new()
	nat.setup(spec_dict, map_dict)
	var speed := 30.0 if rpm > 8000.0 else 0.0
	var tag := "%s thr=%.1f rpm=%d" % [preset, throttle, int(rpm)]
	for i in STEPS:
		var drawn := 0.02 * (rpm / 6000.0) * air.pressure / EngineAir.P0
		air.manifold_update(DT, throttle, drawn, spec, rpm, true, speed)
		nat.manifold_update(DT, throttle, drawn, rpm, true, speed)
		var pairs := [["pressure", air.pressure, nat.get_pressure()], ["boost_ratio", air.boost_ratio, nat.get_boost_ratio()],
			["compressor_pr", air.compressor_pr, nat.get_compressor_pr()],
			["compressor_speed_rpm", air.compressor_speed_rpm, nat.get_compressor_speed_rpm()]]
		for q in pairs:
			if not _close(q[1], q[2]):
				print("FAIL %s step %d %s: gd=%s native=%s" % [tag, i, q[0], q[1], q[2]])
				failures += 1
				return
