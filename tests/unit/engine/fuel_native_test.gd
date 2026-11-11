extends SceneTree

# FuelNative (gdextension/src/fuel_native.cpp) must match FuelTank (scripts/fuel/fuel.gd) exactly.
# Run: godot --headless --path . -s tests/unit/engine/fuel_native_test.gd
const REL_TOL := 1.0e-9

var failures := 0


func _init() -> void:
	await process_frame
	if not ClassDB.class_exists("FuelNative"):
		print("SKIP: FuelNative is not loaded, nothing to compare")
		quit(2)
		return
	_compare_tables()
	_compare_tanks()
	print("fuel_native_test: %s" % ("PASSED" if failures == 0 else "FAILED (%d problems)" % failures))
	quit(0 if failures == 0 else 1)


func _close(a: float, b: float) -> bool:
	return absf(a - b) <= REL_TOL * maxf(1.0, maxf(absf(a), absf(b)))


func _check(label: String, gd: float, nat: float) -> void:
	if not _close(gd, nat):
		failures += 1
		print("FAIL %s: gdscript %.12g native %.12g" % [label, gd, nat])


func _compare_tables() -> void:
	if Array(FuelNative.kinds()) != Array(FuelTank.KINDS):
		failures += 1
		print("FAIL kinds: %s vs %s" % [FuelTank.KINDS, FuelNative.kinds()])
	if Array(FuelNative.labels()) != Array(FuelTank.LABELS):
		failures += 1
		print("FAIL labels: %s vs %s" % [FuelTank.LABELS, FuelNative.labels()])
	for kind in FuelTank.KINDS:
		var gd: Dictionary = FuelTank.PROPERTIES[kind]
		var nat: Dictionary = FuelNative.properties(kind)
		for key in gd.keys():
			_check("properties %s.%s" % [kind, key], gd[key], nat.get(key, NAN))
	if not FuelNative.properties("nonsense").is_empty():
		failures += 1
		print("FAIL properties of an unknown kind should be empty")


func _same(label: String, gd: FuelTank, nat: FuelNative) -> void:
	if gd.kind != nat.get_kind():
		failures += 1
		print("FAIL %s kind: %s vs %s" % [label, gd.kind, nat.get_kind()])
	_check(label + " afr", gd.afr, nat.get_afr())
	_check(label + " lhv", gd.lhv, nat.get_lhv())
	_check(label + " latent", gd.latent, nat.get_latent())
	_check(label + " octane", gd.octane, nat.get_octane())
	_check(label + " mass_kg", gd.mass_kg, nat.get_mass_kg())
	_check(label + " capacity", gd.capacity_litres, nat.get_capacity_litres())
	_check(label + " fraction", gd.fraction(), nat.fraction())


func _compare_tanks() -> void:
	var gd := FuelTank.new()
	var nat := FuelNative.new()
	_same("default", gd, nat)
	for kind in FuelTank.KINDS:
		gd.set_kind(kind)
		nat.set_kind(kind)
		_same("set_kind " + kind, gd, nat)
		# Burn some fuel, then shrink and grow the tank: set_capacity keeps the level and clamps it to 0..1.
		gd.mass_kg *= 0.4
		nat.set_mass_kg(nat.get_mass_kg() * 0.4)
		_same("burnt " + kind, gd, nat)
		for litres in [5.0, 0.01, 20.0]:
			gd.set_capacity(litres)
			nat.set_capacity(litres)
			_same("capacity %s %s" % [litres, kind], gd, nat)
		# Overfull tank: the level clamps to 1 on the next set_capacity.
		gd.mass_kg *= 3.0
		nat.set_mass_kg(nat.get_mass_kg() * 3.0)
		gd.set_capacity(12.0)
		nat.set_capacity(12.0)
		_same("overfull " + kind, gd, nat)
		gd.refill()
		nat.refill()
		_same("refill " + kind, gd, nat)
	# Selecting the current kind does not refill.
	gd.mass_kg *= 0.5
	nat.set_mass_kg(nat.get_mass_kg() * 0.5)
	gd.set_kind(gd.kind)
	nat.set_kind(nat.get_kind())
	_same("same kind", gd, nat)
