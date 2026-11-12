extends SceneTree

# End to end, through EngineSim: a hard stop with the ABS on is shorter than one with it off, the ABS never lets a wheel
# lock, and with the lever released the simulator behaves exactly as it did before the wheel model existed.
# Run: godot --headless --path . -s tests/unit/sim/abs_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func spec_of(id: String) -> EngineSpec:
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS[id]
	for key in preset.keys():
		spec.set(key, preset[key])
	return spec


# A hard stop from 30 m/s: returns [metres travelled, worst slip, ABS cycles].
func stop_from_30(spec: EngineSpec) -> Array:
	var sim := EngineSim.new()
	sim.speed = 30.0
	sim._sync_wheels(spec)
	var travelled := 0.0
	var worst := 0.0
	for i in 900: # 15 s at 60 fps
		sim.step(1.0 / 60.0, spec, 0.0, true, false, false, true, 1.0) # brake held
		travelled += sim.speed / 60.0
		# below about 5 m/s the ABS hands the lever back (real systems do, and a wheel that is nearly stopped has no
		# slip to speak of), so the lock-up contract is measured while there is speed to work with
		if sim.speed > 5.0:
			worst = minf(worst, sim.front_slip())
		if sim.speed < 0.1:
			break
	return [travelled, worst, sim.abs_cycles()]


func _init() -> void:
	await process_frame
	# ---- unbraked coasting is unchanged by any of this ----
	var on_spec := spec_of("honda_cbr1000rrr_sp")
	on_spec.abs_enabled = true
	var coast_off := EngineSim.new()
	var coast_on := EngineSim.new()
	for i in 240: # 4 s of closed throttle, no brake, in gear
		coast_off.step(1.0 / 60.0, spec_of("honda_cbr1000rrr_sp"), 0.0, true, false, false, false, 1.0)
		coast_on.step(1.0 / 60.0, on_spec, 0.0, true, false, false, false, 1.0)
	check(absf(coast_off.speed - coast_on.speed) < 1e-9,
		"the ABS does not touch an unbraked coast (%.6f vs %.6f m/s)" % [coast_off.speed, coast_on.speed])

	# ---- ABS on: short stop, no lock ----
	var on := stop_from_30(on_spec)
	# ---- ABS off with the same lever: the front locks and it takes longer ----
	var off_spec := spec_of("honda_cbr1000rrr_sp")
	off_spec.abs_enabled = false
	var off := stop_from_30(off_spec)
	print("ABS on : %.1f m, worst slip %.2f, %d cycles" % [on[0], on[1], on[2]])
	print("ABS off: %.1f m, worst slip %.2f" % [off[0], off[1]])
	check(on[0] > 35.0 and on[0] < 60.0, "the ABS stop is 35-60 m from 30 m/s (%.1f m)" % on[0])
	check(on[1] > -0.5, "the ABS never lets a wheel past half slip (%.2f)" % on[1])
	check(on[2] >= 3, "the ABS cycled at least three times (got %d)" % on[2])
	check(off[1] < -0.85, "without ABS the front wheel locks (%.2f)" % off[1])
	check(off[0] > on[0] * 1.15, "locking it costs distance (%.1f m vs %.1f m)" % [off[0], on[0]])

	# ---- the state the dash reads ----
	var hsim := EngineSim.new()
	hsim.speed = 20.0
	hsim._sync_wheels(on_spec)
	for i in 60:
		hsim.step(1.0 / 60.0, on_spec, 0.0, true, false, false, true, 1.0)
	check(hsim.abs_active(), "the sim reports the ABS as active while it is holding the slip")
	hsim.brake = 0.0
	hsim.step(1.0 / 60.0, off_spec, 0.0, true, false, false, false, 1.0)
	check(not hsim.abs_active(), "and inactive with the lever released")

	# ---- the dash actually prints it ----
	var braking := EngineSim.new()
	braking.speed = 25.0
	braking._sync_wheels(on_spec)
	for i in 40:
		braking.step(1.0 / 60.0, on_spec, 0.0, true, false, false, true, 1.0)
	var hud := Hud.new()
	root.add_child(hud)
	hud.update(braking, on_spec, false)
	check(hud._panel.info.contains("ABS"), "the dash reads ABS while the system modulates (%s)" % hud._panel.info)
	braking.brake = 0.0
	braking.step(1.0 / 60.0, on_spec, 0.0, true, false, false, false, 1.0)
	hud.update(braking, on_spec, false)
	check(not hud._panel.info.contains("ABS"), "and stops saying it with the lever released (%s)" % hud._panel.info)
	hud.queue_free()

	# ---- the factory ABS bikes actually get it, and the non-ABS bikes cannot fake it ----
	var sp := spec_of("honda_cbr1000rrr_sp")
	check(sp.has_abs, "the CBR1000RR-R SP has ABS")
	check(sp.brake_torque_nm > 900.0, "a litre bike gets litre-bike brakes (%.0f N·m)" % sp.brake_torque_nm)
	var h2 := spec_of("kawasaki_h2r")
	check(not h2.has_abs and not h2.abs_enabled, "the H2R has no ABS from the factory")
	var bare := stop_from_30(h2)
	h2.abs_enabled = true
	check(h2.abs_hardware(), "the builder can add ABS to it with the switch")
	var added := stop_from_30(h2)
	print("H2R : %.1f m locked, %.1f m with ABS added, %d cycles" % [bare[0], added[0], added[2]])
	check(bare[1] < -0.85, "without it the front locks (%.2f)" % bare[1])
	check(added[2] >= 3 and added[1] > -0.5, "with the switch on it modulates (%d cycles, worst slip %.2f)" % [added[2], added[1]])
	check(added[0] < bare[0], "and stops shorter (%.1f m vs %.1f m)" % [added[0], bare[0]])

	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
