extends SceneTree

# Spatial audio model. A point source in a free field spreads its power over a sphere, so the INTENSITY falls as 1/r^2;
# intensity is pressure squared, so the PRESSURE the mixer carries falls as 1/r, i.e. 6.0206 dB per doubling. That is
# the model (written down, with the reasoning, in scripts/audio/spatial_falloff.gd); Godot's inverse-SQUARE model
# applies the intensity exponent to the amplitude and would drop the exhaust twice as fast.
#
# This test does not trust the formula, it MEASURES it: a real AudioStreamPlayer3D, the game's camera as the listener,
# and an AudioEffectCapture on a bus, in headless Godot. A 1 kHz mono tone is also the band a phone speaker keeps
# (500 Hz - 5 kHz), so the same numbers say the tuning does not bury the part of the clank that survives on a phone.
#
# Four things are checked, each one a way the change could be wrong:
#   - the engine's level follows the model at 11, 30 and 80 units (the seat, the middle, and past the old cull);
#   - it really is 6.02 dB per doubling in the field, measured without the formula;
#   - the clank, now a 3D player at the throttle housing, is at the same level at the default seat as the 2D player it
#     replaced, and falls with distance as the camera orbits away;
#   - both players go silent at their cull radius, not at 8 m as the exhaust used to.
# A mono 3D source is panned with an equal-power law, 1/sqrt(2) per channel (measured here as -3.01 dB against the
# same stream on a non-positional player), so a 3D level is compared against the model plus SpatialFalloff.PAN_LAW_DB.
#
# Run: godot --headless --path . -s res://tests/unit/controls/spatial_audio_test.gd   (prints PASS or FAIL)

const BUS := "SpatialProbe"
const RATE := 44100.0
const TONE_FRAMES := 11025 # 0.25 s of tone per measurement
const TOL_DB := 0.35 # measured vs model: capture window edges, mixing chunks, 44.1 kHz resampling
const SEAT := 11.0 # the default camera orbit distance, scene units

var _fails := 0
var _cap: AudioEffectCapture
var _tone: AudioStreamWAV
var _ref := 0.0 # mean(L^2+R^2) of the mono tone on a non-positional player: the 0 dB reference
var _main: Node


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _db(ratio: float) -> float:
	return 10.0 * log(maxf(ratio, 1e-20)) / log(10.0)


# A 1 kHz mono tone as a looping stream: no asset, and the band that matters on a phone speaker.
func _make_tone() -> AudioStreamWAV:
	var n := 44100
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(round(sin(TAU * 1000.0 * float(i) / RATE) * 0.5 * 32767.0)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(RATE)
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


# Energy of both channels over `frames` frames, as a mean of L^2+R^2: pan-independent, so moving the camera round the
# bike changes the distance and not the reading.
func _measure(p: Node, frames: int) -> float:
	_cap.clear_buffer()
	p.call("play")
	for i in 8:
		await process_frame
	_cap.clear_buffer() # drop whatever the mixer queued before the stream was steady
	# Twice the window and meter only the second half: the mixer fills the capture buffer a chunk at a time, so the
	# first frames after a clear can still hold audio the server had already mixed (the previous player's tail).
	var got := PackedVector2Array()
	while got.size() < frames * 2:
		await process_frame
		got.append_array(_cap.get_buffer(_cap.get_frames_available()))
	p.call("stop")
	var acc := 0.0
	for i in range(frames, frames * 2):
		acc += got[i].x * got[i].x + got[i].y * got[i].y
	return acc / float(frames)


# A reference player at a fixed distance, with the attenuation settings under test.
func _player(unit_size: float, max_distance: float, max_db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _tone
	p.bus = BUS
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = unit_size
	p.max_db = max_db
	p.max_distance = max_distance
	# The attenuation filter is Godot's distance-driven high shelf (the engine keeps it as a tone choice, the clank
	# has it off so its 14-19 kHz half survives). It is not part of the distance law, and its skirt reaches down into
	# the 1 kHz measurement by up to 1 dB at 80 units, so the law is measured without it.
	p.attenuation_filter_db = 0.0
	root.add_child(p)
	return p


# Measured level in dB relative to the non-positional reference. A 3D player also carries the pan law, so the model it
# is compared against is gain_db + PAN_LAW_DB.
func _level(p: Node) -> float:
	return _db(await _measure(p, TONE_FRAMES) / _ref)


func _init() -> void:
	await process_frame
	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, BUS)
	_cap = AudioEffectCapture.new()
	_cap.buffer_length = 3.0
	AudioServer.add_bus_effect(bus, _cap)

	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	for i in 4:
		await process_frame

	_tone = _make_tone()
	var flat := AudioStreamPlayer.new() # non-positional: exactly 0 dB, and no pan law
	flat.stream = _tone
	flat.bus = BUS
	root.add_child(flat)
	_ref = await _measure(flat, TONE_FRAMES)
	check(_ref > 0.001, "the capture bus hears the reference tone (%.5f)" % _ref)

	var pan_db: float = await _pan_law()
	print("pan law: a positional mono source is %+.2f dB against the same stream on a 2D player" % pan_db)
	check(absf(pan_db - SpatialFalloff.PAN_LAW_DB) < 0.1,
		"the equal-power pan law is %.2f dB, not 0 (measured %+.2f)" % [SpatialFalloff.PAN_LAW_DB, pan_db])

	# ---- the engine: is the level the model says it is? ----
	var eu: float = EngineSound.UNIT_SIZE
	var emax: float = EngineSound.MAX_DISTANCE
	var emdb: float = EngineSound.MAX_DB
	var engine_levels := {}
	for d in [11.0, 22.0, 30.0, 44.0, 80.0, 88.0]:
		var p := _player(eu, emax, emdb)
		_place(p, d)
		var got: float = await _level(p)
		var want: float = SpatialFalloff.gain_db(d, eu, emax, emdb) + SpatialFalloff.PAN_LAW_DB
		engine_levels[d] = got
		print("engine %5.1f units: measured %+7.2f dB, model %+7.2f dB" % [d, got, want])
		check(absf(got - want) < TOL_DB,
			"engine at %.0f units is %.2f dB, model says %.2f" % [d, got, want])
		p.queue_free()

	# Nothing in the formula here: two doublings in the open field must each lose 6.02 dB. Both pairs are outside the
	# near-field ceiling (inside 12.7 units the model is deliberately flat, which is why 11 does not double to 22).
	for pair in [[22.0, 44.0], [44.0, 88.0]]:
		var drop: float = engine_levels[pair[0]] - engine_levels[pair[1]]
		print("1/r check %.0f -> %.0f units: %.2f dB per doubling" % [pair[0], pair[1], drop])
		# 6.02 dB of free field plus up to a quarter dB of Godot's cull fade, which grows with distance.
		check(absf(drop - 6.0206) < TOL_DB * 2.0,
			"%.0f -> %.0f units drops %.2f dB, free field is 6.02" % [pair[0], pair[1], drop])

	# ---- the clank: its own reference distance, its own cull ----
	var cu: float = _main.CLANK_UNIT_SIZE
	var cmax: float = _main.CLANK_MAX_DISTANCE
	var cmdb: float = _main.CLANK_MAX_DB
	var clank_levels := {}
	for d in [11.0, 22.0, 30.0, 80.0]:
		var p := _player(cu, cmax, cmdb)
		_place(p, d)
		var got: float = await _level(p)
		var want: float = SpatialFalloff.gain_db(d, cu, cmax, cmdb) + SpatialFalloff.PAN_LAW_DB
		clank_levels[d] = got
		print("clank  %5.1f units: measured %+7.2f dB, model %+7.2f dB" % [d, got, want])
		check(absf(got - want) < TOL_DB,
			"clank at %.0f units is %.2f dB, model says %.2f" % [d, got, want])
		p.queue_free()

	# ---- past the cull it is silent, not merely quiet ----
	var far := _player(cu, cmax, cmdb)
	_place(far, cmax)
	var far_energy: float = await _measure(far, TONE_FRAMES)
	print("clank at the cull (%.0f units): energy %.6f" % [cmax, far_energy])
	check(far_energy < 1e-6, "the clank is silent at its %.0f-unit cull (energy %.6f)" % [cmax, far_energy])
	check(SpatialFalloff.gain_db(cmax, cu, cmax, cmdb) == -INF, "the model says -inf at the cull radius")
	far.queue_free()

	# ---- the real clank player, at the seat and with the camera orbited out ----
	var clank: AudioStreamPlayer3D = _main._clank
	var saved_stream = clank.stream
	clank.stream = _tone # same player, same position, a steady level to meter instead of a 0.267 s transient
	clank.bus = BUS
	check(clank.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE,
		"the clank uses the 1/r model")
	check(clank.unit_size == cu and clank.max_distance == cmax and clank.max_db == cmdb,
		"the clank carries the calibrated constants")

	var housing: Vector3 = _main._drivetrain.throttle_housing_position()
	check(clank.global_position.distance_to(housing) < 0.01,
		"the clank sits at the throttle housing (%.2f units off)" % clank.global_position.distance_to(housing))
	check(clank.global_position.distance_to(_main._tail_tip) > 2.0,
		"the clank is at the bars, not at the tailpipe (%.2f units apart)" % clank.global_position.distance_to(_main._tail_tip))

	# the level the old non-positional player had: the same stream, the same gain, no distance term
	var parity_ref := AudioStreamPlayer.new()
	parity_ref.stream = _tone
	parity_ref.bus = BUS
	parity_ref.volume_db = _main.CLANK_GAIN_DB
	root.add_child(parity_ref)
	var ref_energy: float = await _measure(parity_ref, TONE_FRAMES)
	parity_ref.queue_free()

	clank.volume_db = _main.CLANK_GAIN_DB + _main.CLANK_PAN_DB
	var seat := _seat_distance(clank)
	var seat_energy: float = await _measure(clank, TONE_FRAMES)
	var seat_db: float = _db(seat_energy / ref_energy)
	var seat_want: float = SpatialFalloff.gain_db(seat, cu, cmax, cmdb)
	print("clank at the seat (%.2f units from the camera): %+.2f dB against the 2D player, model %+.2f dB"
		% [seat, seat_db, seat_want])
	check(absf(seat_db - seat_want) < TOL_DB,
		"the clank at the default seat is unchanged (%+.2f dB, model %+.2f)" % [seat_db, seat_want])
	check(absf(seat_db) < 1.0,
		"the clank at the default seat is within a dB of the level it had as a 2D player (%+.2f dB)" % seat_db)

	# orbit the camera out: the tick must fall away like everything else, by the same law
	_main._orbit.distance = 30.0
	for i in 3:
		await process_frame
	var out := _seat_distance(clank)
	var out_energy: float = await _measure(clank, TONE_FRAMES)
	var out_db: float = _db(out_energy / ref_energy)
	var out_want: float = SpatialFalloff.gain_db(out, cu, cmax, cmdb)
	print("clank with the camera at 30 units (%.2f units from the bars): %+.2f dB against the 2D player, model %+.2f dB"
		% [out, out_db, out_want])
	check(absf(out_db - out_want) < TOL_DB,
		"the clank falls with the orbit (%+.2f dB, model %+.2f)" % [out_db, out_want])
	check(out_db < seat_db - 5.0, "a 30-unit camera pulls the clank down %.1f dB" % (seat_db - out_db))
	_main._orbit.distance = SEAT

	# ---- settings the calibration rests on ----
	check(_main._sound.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE,
		"the engine uses the 1/r model (pressure, not intensity)")
	check(_main._sound.unit_size == eu and _main._sound.max_distance == emax and _main._sound.max_db == emdb,
		"the engine carries the calibrated constants")
	check(emax >= SEAT * SpatialFalloff.CULL_FACTOR,
		"the exhaust is not culled inside the camera's range (cull %.0f, camera stops at 40)" % emax)
	check(clank.attenuation_filter_db == 0.0,
		"the clank has no distance-dependent high shelf, so the phone band is never trimmed")
	check(clank.max_polyphony == 3, "the clank keeps its polyphony")

	clank.stream = saved_stream
	if _fails == 0:
		print("spatial_audio_test: PASS (1/r falloff measured, engine and clank calibrated at the seat)")
	quit(0 if _fails == 0 else 1)


# The pan law on its own: the same tone on a 3D player with attenuation off, against the 2D reference.
func _pan_law() -> float:
	var p := AudioStreamPlayer3D.new()
	p.stream = _tone
	p.bus = BUS
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	p.position = Vector3(0.0, 0.0, -SEAT)
	root.add_child(p)
	var db: float = await _level(p)
	p.queue_free()
	return db


# Put a reference player exactly d units from the listener. The model needs the real listener distance, and the game's
# camera does not sit at the origin: it orbits 11 units from the bike's centre.
func _place(p: Node3D, d: float) -> void:
	p.global_position = _main._orbit.camera.global_position + Vector3(0.0, 0.0, -d)


func _seat_distance(p: Node3D) -> float:
	return _main._orbit.camera.global_position.distance_to(p.global_position)
