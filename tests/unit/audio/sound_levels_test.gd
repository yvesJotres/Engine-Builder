extends SceneTree

# The panel's sound levels reach the engine sound: a layer scale of 0 silences it, a scale of 2 doubles its tuned gain, and the
# rasp and intake levels are stored for the mix. Exits 1 on any failure.
# Run: godot --headless --path . -s res://tests/unit/audio/sound_levels_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	var spec := EngineSpec.new()
	spec.sound_knock = 0.0
	spec.sound_turbo = 2.0
	spec.sound_rasp = 0.5
	spec.sound_intake = 0.0
	var sound := EngineSound.new()
	sound.setup(spec)
	var gains: Array = sound._layers._gains
	var names: Array = sound._layers._names
	var tuned: Array = sound._layers._tuned
	var knock := names.find("knock")
	check(knock >= 0 and gains[knock] == 0.0, "knock off at level 0")
	check(sound._layers._names.find("turbo") < 0 or is_equal_approx(gains[names.find("turbo")], tuned[names.find("turbo")] * 2.0), "turbo doubled when its level is 2")
	check(is_equal_approx(sound._rasp_scale, 0.5), "rasp level is stored, got %s" % str(sound._rasp_scale))
	check(sound._intake_scale == 0.0, "intake level is stored, got %s" % str(sound._intake_scale))

	# a live change from the panel reaches the sound without a setup
	spec.sound_knock = 1.5
	sound.apply_levels(spec)
	gains = sound._layers._gains
	check(is_equal_approx(gains[knock], tuned[knock] * 1.5), "a live knock level of 1.5 scales the tuned gain")

	sound.free()
	print("sound_levels_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
