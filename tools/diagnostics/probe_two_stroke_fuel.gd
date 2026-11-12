extends SceneTree

# Does the two-stroke ever get fuel? _residual_kg is re-read on BOTH transfer-port crossings and then _fuel_charge sizes
# the fuel from (mass - residual). If the closing edge overwrites the residual with the already-scavenged mass, the
# difference is zero, no fuel is injected, and burn_energy stays 0 for every cycle.
# Run: godot --headless --path . -s res://tools/diagnostics/probe_two_stroke_fuel.gd

const DT := 1.0 / 120.0
const P0 := 101325.0


func _init() -> void:
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS["yamaha_rd350"]
	for key in preset:
		spec.set(key, preset[key])
	var cyl := TwoStrokeCylinder.new()
	cyl.setup(spec)
	cyl.start_at(0.0)
	var tank := FuelTank.new()
	print("transfer open %.0f close %.0f, exhaust open %.0f close %.0f" % [
		cyl.transfer_open, cyl.transfer_close, cyl.exhaust_open, cyl.exhaust_close])
	print("%6s %8s %10s %10s %10s %10s %8s" % ["step", "phi", "mass", "residual", "fresh", "burn_J", "lambda"])
	var dphi := 6000.0 * 6.0 * DT
	var last_phi := cyl.phi
	for i in 240:
		var before := cyl.mass
		var r := cyl.advance(dphi, DT, P0, 300.0, 340.0, true, tank, 1.0, true, false, 1.4 * P0, 700.0)
		var phi_now := cyl.phi - 360.0 if cyl.phi >= 360.0 else cyl.phi
		# print every step that crosses a transfer edge
		var crossed := (last_phi < cyl.transfer_open and phi_now >= cyl.transfer_open) or (last_phi <= cyl.transfer_close and phi_now > cyl.transfer_close)
		if crossed:
			print("%6d %8.1f %10.6f %10.6f %10.6f %10.4f %8.3f" % [
				i, phi_now, cyl.mass, cyl._residual_kg, cyl.last_fresh_kg, cyl.burn_energy, cyl.last_lambda])
		last_phi = phi_now
		if absf(r.y) > 0.0:
			pass
	print("after 240 steps: burn_energy %.4f J, tank %.6f kg, last_fresh %.6f kg, residual frac %.3f" % [
		cyl.burn_energy, tank.mass_kg, cyl.last_fresh_kg, cyl.last_residual_fraction])
	quit(0)
