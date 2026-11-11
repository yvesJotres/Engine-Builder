extends SceneTree

# Phase 1 of the C++ physics migration: a deterministic trace of the current GDScript simulation.
# The native EngineSimCore must reproduce this before it becomes the production path.
# Run: godot --headless --path . -s tools/diagnostics/sim_golden_trace.gd

const PRESETS := ["honda_cbr150r", "kawasaki_zx25r", "yamaha_yzf_r1m"]
const OUT := "res://tests/fixtures/sim_golden_trace.json"


func spec_of(id: String) -> EngineSpec:
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS[id]
	for key in p.keys():
		spec.set(key, p[key])
	return spec


func trace(id: String) -> Array:
	var spec := spec_of(id)
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 1200.0
	var rows := []
	# 1.2 s crank, 1.8 s idle, 1.2 s wide open, 0.6 s closed throttle.
	for i in 240:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, true, false, 1.0)
	for i in 108:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, true, false, 1.0)
	for i in 72:
		sim.step(1.0 / 60.0, spec, 1.0, true, false, true, false, 1.0)
	for i in 36:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, true, false, 1.0)
		rows.append({
			"i": i,
			"rpm": sim.rpm,
			"torque": sim.torque,
			"speed": sim.speed,
			"fuel": sim.fuel_flow,
			"running": sim.running,
			"clutch": sim.clutch_engage,
			"intake_pa": sim.intake.pressure,
			"coolant_c": sim.coolant_c,
			"oil_c": sim.oil_c,
		})
	return rows


func _init() -> void:
	var out := {}
	for id in PRESETS:
		out[id] = trace(id)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		push_error("cannot write " + OUT)
		quit(1)
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("wrote " + OUT)
	quit(0)