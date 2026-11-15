extends SceneTree

# The SPL meter: a microphone where a real exhaust noise test puts one - 0.5 m from the outlet, 45 degrees off the flow,
# at the outlet's height, outboard of the bike, never lower than 0.2 m off the ground. Five things have to hold for the
# number on the dash to mean anything:
#   - the microphone really is at that point, measured against the pipe's own exit direction;
#   - the scale is the decibel it claims: 94 dB SPL at full scale on the reference distance, 6.02 dB per halving of
#     distance, 6.02 dB per doubling of the engine's level - and it does NOT inherit the playback near-field cap, which
#     would make a 0.5 m reading identical to a 1 m one;
#   - it reads the ENGINE, not the mixer: the value follows EngineSound.output_rms, and muting takes it to a dash;
#   - it stands on the side the pipe is on, so the bodywork does not shadow it;
#   - it lands on the dashboard.
# Run: godot --headless --path . -s res://tests/unit/audio/spl_meter_test.gd   (prints PASS or FAIL)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame

	# ---- the scale ----
	var falloff: float = SpatialFalloff.free_field_db(SplMeter.MIC_DISTANCE, EngineSound.UNIT_SIZE)
	print("microphone at %.1f units (%.1f m): %+.2f dB of free field from the reference distance"
		% [SplMeter.MIC_DISTANCE, SplMeter.MIC_DISTANCE / 10.0, falloff])
	check(absf(SplMeter.level_db(1.0) - (SplMeter.REFERENCE_DB + falloff)) < 0.01,
		"full scale at the meter reads %.2f dB SPL" % SplMeter.level_db(1.0))
	var halved: float = SplMeter.level_db(1.0) - (SplMeter.REFERENCE_DB + SpatialFalloff.free_field_db(10.0, EngineSound.UNIT_SIZE))
	print("same engine at 0.5 m instead of 1 m: %+.2f dB" % halved)
	check(absf(halved - 6.0206) < 0.02, "halving the distance gains 6.02 dB (%.2f)" % halved)
	var capped: float = SpatialFalloff.attenuation_db(SplMeter.MIC_DISTANCE, EngineSound.UNIT_SIZE, EngineSound.MAX_DB)
	check(falloff - capped > 5.0,
		"the meter ignores the playback near-field cap: free field %+.2f dB, capped %+.2f dB" % [falloff, capped])
	var doubled: float = SplMeter.level_db(0.2) - SplMeter.level_db(0.1)
	print("twice the engine level: %+.2f dB" % doubled)
	check(absf(doubled - 6.0206) < 0.01, "the scale is decibels (%.2f per doubling)" % doubled)
	check(SplMeter.text(0.0) == "-- dB", "silence reads as a dash, not a number below the floor")

	# ---- where the microphone stands ----
	var tail: Vector3 = main._tail_tip
	var mic: Vector3 = main._spl_mic
	var flow: Vector3 = Vector3(main._tail_dir.x, 0.0, main._tail_dir.z).normalized()
	var offset: Vector3 = mic - tail
	var flat_offset: Vector3 = Vector3(offset.x, 0.0, offset.z)
	print("tail %s  flow %s  mic %s" % [tail, flow, mic])
	print("microphone %.2f units from the outlet, %.1f degrees off the flow, %.2f units above its height, y %.2f"
		% [offset.length(), rad_to_deg(flat_offset.angle_to(flow)), mic.y - tail.y, mic.y])
	check(absf(offset.length() - 5.0) < 0.02, "the microphone is 0.5 m from the outlet (%.3f units)" % offset.length())
	check(absf(rad_to_deg(flat_offset.angle_to(flow)) - 45.0) < 0.5,
		"it stands 45 degrees off the exhaust flow (%.2f degrees)" % rad_to_deg(flat_offset.angle_to(flow)))
	check(absf(mic.y - tail.y) < 0.01 or absf(mic.y - (Ground.Y + SplMeter.MIC_MIN_HEIGHT)) < 0.01,
		"it stands at the outlet's height, or on the standard's 0.2 m floor (%.2f units off)" % (mic.y - tail.y))
	check(mic.y >= Ground.Y + SplMeter.MIC_MIN_HEIGHT - 0.01, "it is never below 0.2 m off the ground (%.2f)" % (mic.y - Ground.Y))
	# outboard: on the pipe's side of the bike, so the body does not block the source
	var side: Vector3 = flow.cross(Vector3.UP).normalized()
	var lateral: float = flat_offset.dot(side)
	print("lateral offset from the pipe axis: %.2f units (pipe tip x %.2f)" % [lateral, tail.x])
	check(absf(lateral) > 2.0, "the microphone is off the pipe's axis, not in the blast (%.2f units)" % lateral)
	check(signf(tail.x) == 0.0 or signf(lateral) == signf(tail.x) or absf(tail.x) < 0.5,
		"it stands on the side the pipe exits (tip x %.2f, lateral %.2f)" % [tail.x, lateral])

	# ---- it reads the engine, and the mixer's volume is not part of it ----
	main._paused = false
	main._sound_on = true
	main._sound.output_rms = 0.1
	main._update_spl_meter(1.0) # one second of attack time: the reading has settled
	var want: float = SplMeter.level_db(0.1)
	print("engine at RMS 0.1: meter reads %.1f dB SPL, model %.1f" % [main._spl_db, want])
	check(absf(main._spl_db - want) < 0.1, "the meter follows EngineSound.output_rms (%.1f vs %.1f)" % [main._spl_db, want])
	main._hud.update(main._sim, main.spec, false, 0.0, main._spl_db)
	check(absf(main._hud._panel.spl - main._spl_db) < 0.01, "the dashboard carries the reading")
	check(SplMeter.text(main._hud._panel.spl).ends_with("dB"), "the dashboard prints it as dB")

	main._sound_on = false
	main._update_spl_meter(2.0)
	print("sound off: meter falls to %.1f dB SPL (%s)" % [main._spl_db, SplMeter.text(main._spl_db)])
	check(SplMeter.text(main._spl_db) == "-- dB", "muting the sound takes the reading to a dash")
	main._sound_on = true

	if _fails == 0:
		print("spl_meter_test: PASS (0.5 m at 45 degrees, calibrated to the free-field law)")
	quit(0 if _fails == 0 else 1)
