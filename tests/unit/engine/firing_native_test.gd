extends SceneTree

# FiringNative (gdextension/src/firing_native.cpp) must match FiringOrders (scripts/engine/firing_orders.gd) exactly.
# Run: godot --headless --path . -s tests/unit/engine/firing_native_test.gd
const REL_TOL := 1.0e-9

var failures := 0


func _init() -> void:
	await process_frame
	if not ClassDB.class_exists("FiringNative"):
		print("SKIP: FiringNative is not loaded, nothing to compare")
		quit(2)
		return
	_compare_order_for()
	_compare_fire_angles()
	_compare_fired_between()
	_compare_for_spec()
	print("firing_native_test: %s" % ("PASSED" if failures == 0 else "FAILED (%d problems)" % failures))
	quit(0 if failures == 0 else 1)


func _close(a: float, b: float) -> bool:
	return absf(a - b) <= REL_TOL * maxf(1.0, maxf(absf(a), absf(b)))


func _same_floats(label: String, gd: Array, nat: PackedFloat64Array) -> void:
	if gd.size() != nat.size():
		failures += 1
		print("FAIL %s size: %s vs %s" % [label, gd, nat])
		return
	for i in gd.size():
		if not _close(gd[i], nat[i]):
			failures += 1
			print("FAIL %s[%d]: gdscript %.12g native %.12g" % [label, i, gd[i], nat[i]])


func _compare_order_for() -> void:
	for c in range(1, 13):
		var gd := FiringOrders.order_for(c)
		var nat := FiringNative.order_for(c)
		if Array(nat) != gd:
			failures += 1
			print("FAIL order_for(%d): %s vs %s" % [c, gd, nat])


func _compare_fire_angles() -> void:
	for c in range(1, 13):
		_same_floats("fire_angles(%d)" % c, FiringOrders.fire_angles(c), FiringNative.fire_angles(c))
	for pin in [360.0, 270.0, 180.0, 90.0]:
		_same_floats("twin %s" % pin, FiringOrders.fire_angles(2, pin), FiringNative.fire_angles(2, pin))
	_same_floats("crossplane", FiringOrders.fire_angles(4, 360.0, true), FiringNative.fire_angles(4, 360.0, true))
	_same_floats("split v4", FiringOrders.fire_angles(4, 360.0, false, true), FiringNative.fire_angles(4, 360.0, false, true))
	_same_floats("crossplane 6 ignored", FiringOrders.fire_angles(6, 360.0, true), FiringNative.fire_angles(6, 360.0, true))


func _compare_fired_between() -> void:
	var n := 0
	for at in [0.0, 90.0, 270.0, 450.0, 630.0, 719.9]:
		for prev in range(-1500, 1500, 37):
			for step in [0.0, 0.5, 3.0, 25.0, 400.0, 719.0, 721.0]:
				var cur: float = prev + step
				var gd := FiringOrders.fired_between(prev, cur, at)
				if gd != FiringNative.fired_between(prev, cur, at):
					failures += 1
					n += 1
					if n < 10:
						print("FAIL fired_between(%s, %s, %s): gdscript %s" % [prev, cur, at, gd])


func _spec_dict(spec: EngineSpec) -> Dictionary:
	return {"cylinders": spec.cylinders, "fire_deg": spec.fire_deg, "twin_pin_deg": spec.twin_pin_deg,
		"split_pin_v4": spec.split_pin_v4, "shared_v_crankpins": spec.shared_v_crankpins, "crossplane": spec.crossplane,
		"layout": spec.layout, "bank_angle": spec.bank_angle, "v3r_style": spec.v3r_style}


func _check_spec(label: String, spec: EngineSpec) -> void:
	var gd: Array[float] = FiringOrders.for_spec(spec)
	_same_floats(label, gd, FiringNative.for_spec(_spec_dict(spec)))


func _compare_for_spec() -> void:
	# Every preset, as shipped.
	for name in Presets.PRESETS.keys():
		var spec := EngineSpec.new()
		var p: Dictionary = Presets.PRESETS[name]
		for key in p.keys():
			spec.set(key, p[key])
		_check_spec("preset " + str(name), spec)
	# Synthetic specs hitting the shared-crankpin branch for several counts, bank angles and the v3r flip, with and without
	# explicit wiring.
	for cyl in [2, 3, 4, 6, 8]:
		for bank in [60.0, 75.0, 90.0]:
			for v3r in [false, true]:
				for wired in [false, true]:
					var spec := EngineSpec.new()
					spec.cylinders = cyl
					spec.layout = "V"
					spec.bank_angle = bank
					spec.shared_v_crankpins = true
					spec.v3r_style = v3r
					if wired:
						var base := FiringOrders.fire_angles(cyl)
						var fd := []
						for i in cyl:
							fd.append(fposmod(base[i] + 90.0 * (i % 3), 720.0))
						spec.fire_deg = fd
					_check_spec("shared v cyl=%d bank=%s v3r=%s wired=%s" % [cyl, bank, v3r, wired], spec)
	# A wiring array of the wrong length falls back to the generic order.
	var bad := EngineSpec.new()
	bad.cylinders = 4
	bad.fire_deg = [0.0, 100.0]
	_check_spec("wrong-length wiring", bad)
	var zero := EngineSpec.new()
	zero.cylinders = 0
	_check_spec("zero cylinders", zero)
