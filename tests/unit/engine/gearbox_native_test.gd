extends SceneTree

# GearboxNative (gdextension/src/gearbox_native.cpp) must match Gearbox (scripts/drivetrain/gearbox.gd) exactly.
# Run: godot --headless --path . -s tests/unit/engine/gearbox_native_test.gd
const REL_TOL := 1.0e-9

var failures := 0


func _init() -> void:
	await process_frame
	if not ClassDB.class_exists("GearboxNative"):
		print("SKIP: GearboxNative is not loaded, nothing to compare")
		quit(2)
		return
	_compare_ratios()
	_compare_shifts([])
	_compare_shifts([3.2, 2.1, 1.5, 1.1]) # a custom four-speed set
	_compare_shifts([2.0]) # a one-speed set: up from neutral stops at gear 1
	print("gearbox_native_test: %s" % ("PASSED" if failures == 0 else "FAILED (%d problems)" % failures))
	quit(0 if failures == 0 else 1)


func _close(a: float, b: float) -> bool:
	return absf(a - b) <= REL_TOL * maxf(1.0, maxf(absf(a), absf(b)))


func _compare_ratios() -> void:
	var gd := Gearbox.ratios()
	var nat := GearboxNative.ratios()
	if gd.size() != nat.size():
		failures += 1
		print("FAIL ratios size: %d vs %d" % [gd.size(), nat.size()])
		return
	for i in gd.size():
		if not _close(gd[i], nat[i]):
			failures += 1
			print("FAIL ratio %d: gdscript %.12g native %.12g" % [i + 1, gd[i], nat[i]])
	var box := GearboxNative.new()
	if box.get_gear() != 0 or box.label() != "N" or box.ratio() != 0.0:
		failures += 1
		print("FAIL a new gearbox should be in neutral")
	if box.get_gear_ratios().size() != gd.size():
		failures += 1
		print("FAIL default gear_ratios size %d" % box.get_gear_ratios().size())


func _compare_shifts(custom: Array) -> void:
	var gd := Gearbox.new()
	var nat := GearboxNative.new()
	if not custom.is_empty():
		gd.gear_ratios = custom
		nat.set_gear_ratios(PackedFloat64Array(custom))
	# Walk up past the top, down past first, and a mixed sequence, comparing after every step.
	var steps: Array = []
	for i in 10:
		steps.append(true)
	for i in 10:
		steps.append(false)
	for s in [true, true, false, false, false, true, false, true, true, true, false, false, false, false]:
		steps.append(s)
	var n := 0
	for up in steps:
		if up:
			gd.shift_up()
			nat.shift_up()
		else:
			gd.shift_down()
			nat.shift_down()
		n += 1
		if gd.gear != nat.get_gear() or gd.label() != nat.label() or not _close(gd.ratio(), nat.ratio()):
			failures += 1
			print("FAIL step %d (custom=%s): gdscript gear %d '%s' ratio %.12g, native gear %d '%s' ratio %.12g" % [n, custom.size(),
				gd.gear, gd.label(), gd.ratio(), nat.get_gear(), nat.label(), nat.ratio()])
	# set_gear then ratio for every gear, including neutral.
	for g in range(0, gd.gear_ratios.size() + 1):
		gd.gear = g
		nat.set_gear(g)
		if not _close(gd.ratio(), nat.ratio()) or gd.label() != nat.label():
			failures += 1
			print("FAIL set_gear %d: gdscript %.12g native %.12g" % [g, gd.ratio(), nat.ratio()])
