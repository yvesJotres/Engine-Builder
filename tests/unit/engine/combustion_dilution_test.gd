extends SceneTree

# Residual dilution and the misfire gate.
#
# A charge lights only while its gas/fuel ratio stays below the researched limit (GAS_FUEL_MISFIRE, Shayler et al.,
# SAE 2000-01-1208). Because the fuel is metered on the fresh air alone, the gas/fuel ratio is stoichiometric AFR divided
# by the fresh fraction, so it is the residual fraction that decides ignition. This test pins the constant, derives the
# residual ceiling it implies, and checks the presets' exhaust closing against the physical window - the early exhaust
# closing on the V6 presets trapped a compressed charge, tripped this gate and stalled the engine.
#
# Run: godot --headless --path . -s tests/unit/engine/combustion_dilution_test.gd

const STOICH := 14.7 # petrol, as FuelTank.PROPERTIES

var _fails := 0
var _checks := 0


func _init() -> void:
	await process_frame
	_gate()
	_ceiling()
	_presets()
	if _fails == 0:
		print("combustion_dilution_test: PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("combustion_dilution_test: %d of %d checks failed" % [_fails, _checks])
		quit(1)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _near(value: float, want: float, tol: float, msg: String) -> void:
	_check(absf(value - want) <= tol, "%s (got %s, research %s plus/minus %s)" % [msg, value, want, tol])


func _within(value: float, lo: float, hi: float, msg: String) -> void:
	_check(value >= lo and value <= hi, "%s (got %s, research range %s to %s)" % [msg, value, lo, hi])


func _gate() -> void:
	_near(Cylinder.GAS_FUEL_MISFIRE, 24.0, 0.01, "the misfire gate is the researched gas/fuel ratio 24 [docs/engine_physics/07]")


func _ceiling() -> void:
	# A charge lights while trapped gas / fuel < GAS_FUEL_MISFIRE. With fuel = fresh / stoich and
	# trapped = fresh + residual, that is stoich / (1 - residual fraction) < 24, i.e. residual below the ceiling.
	var ceiling := 1.0 - STOICH / Cylinder.GAS_FUEL_MISFIRE
	_within(ceiling, 0.35, 0.42, "the residual-fraction ceiling at stoichiometric sits at 0.35 to 0.42")
	# A healthy idle runs a residual of roughly 5 to 25 percent, well inside the gate. If the gate is ever widened to
	# admit that range the check below still holds, so the two constants cannot drift apart silently.
	var idle_residual := 0.15
	_check(idle_residual < ceiling, "a 15 percent idle residual is inside the gate")


func _presets() -> void:
	for name in ["m276_de30la", "amg_m276_v6", "amg_v6_w17", "kawasaki_zx25r", "honda_cbr250rr", "yamaha_yzf_r1m"]:
		if not Presets.PRESETS.has(name):
			continue
		var spec := EngineSpec.new()
		var p: Dictionary = Presets.PRESETS[name]
		for key in p.keys():
			spec.set(key, p[key])
		var evc := float(spec.exhaust_close_deg())
		# The exhaust valve must close near or after exhaust TDC (phase 360). Closing it well before TDC traps the
		# exhaust stroke's pressure and drives the residual fraction past the gate. 330 deg leaves the small early-EVC
		# margin a real cam can use without trapping a compressed charge.
		_check(evc >= 330.0, "%s: exhaust close is near or after TDC, not before it (got %.1f deg)" % [name, evc])
		_within(evc, 330.0, 400.0, "%s: exhaust close stays inside the physical window" % name)
		# The engine must not spend its exhaust stroke with the valve already shut: exhaust opening before BDC is normal,
		# but the close has to be later than the open.
		_check(float(spec.exhaust_close_deg()) > float(spec.exhaust_open_deg()), "%s: exhaust closes after it opens" % name)
