extends SceneTree

# A backfire is an event on top of the exhaust note, not a replacement for it. The bug this pins: pops used to be written
# into the volume flow, so a decel crackle (30+ pops a second, each 20 ms of loud sine) took over most of the stream and the
# shaper's gain pulled the engine's own note down behind it - turning Decel Pops on muted everything else.
# Run: godot --headless --path . --quit-after 3000 -s res://tests/unit/audio/pop_mix_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _rms(frames: PackedVector2Array) -> float:
	var sum := 0.0
	for f in frames:
		sum += f.x * f.x
	return sqrt(sum / maxf(frames.size(), 1))


# A steady four-cylinder pulse train: one exhaust pulse per cylinder per 720 degrees, at a fixed level.
func _feed(sound: EngineSound, blocks: int) -> void:
	for block in blocks:
		var pulse := PackedFloat32Array()
		pulse.resize(EngineSound.RATE / 60) # one frame at 60 Hz
		for i in pulse.size():
			var phase := fposmod((block * pulse.size() + i) / float(EngineSound.RATE) * 4.0 * 41.0, 1.0)
			pulse[i] = 0.05 * exp(-6.0 * phase) # sharp pulse, decaying: an exhaust blowdown
		sound.push_flow(pulse)


func _init() -> void:
	var spec := EngineSpec.new()
	var sound := EngineSound.new()
	root.add_child(sound)
	sound.setup(spec)
	sound.audio_enabled = true
	sound.rpm = 4000.0

	# the note on its own
	var quiet := 0.0
	for block in 30:
		_feed(sound, 1)
		quiet += _rms(sound.render(EngineSound.RATE / 60))
	quiet /= 30.0

	# the same note with a decel crackle over it: 30 pops a second for a second
	var cracked := 0.0
	var flow_before := sound._flow.size()
	for block in 30:
		_feed(sound, 1)
		for n in 5: # ~30 pops a second at 60 blocks/s
			sound.backfire(300.0)
		cracked += _rms(sound.render(EngineSound.RATE / 60))
	cracked /= 30.0
	print("engine note %.4f, note with a crackle over it %.4f (%.0f%% of it)" % [quiet, cracked, 100.0 * cracked / maxf(quiet, 1.0e-9)])
	check(cracked >= quiet, "a crackle does not duck the engine note (%.4f >= %.4f)" % [cracked, quiet])

	# and it must not be hiding in the flow, which is what made the shaper pull the note down
	sound.backfire(300.0)
	check(sound._flow.size() == flow_before, "a pop adds nothing to the flow queue (%d vs %d)" % [sound._flow.size(), flow_before])

	# once the pops stop, the note comes back to exactly where it was
	var after := 0.0
	for block in 30:
		_feed(sound, 1)
		after += _rms(sound.render(EngineSound.RATE / 60))
	after /= 30.0
	print("after the crackle stops: %.4f (%.1f%% of the clean note)" % [after, 100.0 * after / maxf(quiet, 1.0e-9)])
	check(absf(after - quiet) < quiet * 0.1, "the note returns to its level (%.4f vs %.4f)" % [after, quiet])

	sound.free()
	print("pop_mix_test: %s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
