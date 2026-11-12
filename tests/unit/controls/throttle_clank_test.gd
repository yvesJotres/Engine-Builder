extends SceneTree

# The throttle clank fires when the grip reaches its shut stop, gated on how far it was open and how fast it came back.
# Four things have to hold, and each one is a way the sound could go wrong in play:
#   - a real release from open clanks exactly once, at the moment the throttle reaches zero (not at release);
#   - a small blip does not clank, because a 5% opening does not slam the stop;
#   - a slow, eased close (the S key path, 1.5 full travel/s) does not clank, because the spring is not what closed it;
#   - opening again during the return cancels it, because the grip never reaches the stop.
# Run: godot --headless --path . -s res://tests/unit/controls/throttle_clank_test.gd (prints PASS or FAIL)

const DT := 1.0 / 120.0

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 4:
		await process_frame

	check(main.CLANK_STREAM != null, "the clank sample is loaded")
	check(main.CLANK_MIN_RATE < main.THROTTLE_RETURN_SPEED,
		"the rate gate lets the spring through (%.1f < %.1f)" % [main.CLANK_MIN_RATE, main.THROTTLE_RETURN_SPEED])
	check(main.CLANK_MIN_RATE > main.THROTTLE_SPEED,
		"the rate gate rejects the eased close (%.1f > %.1f)" % [main.CLANK_MIN_RATE, main.THROTTLE_SPEED])

	# ---- a real release, driven through the real spring in _process ----
	var plays_before: int = main._clank_plays
	main._throttle = 1.0
	main._throttle_last = 1.0
	var t := 0.0
	var plays_at_release := -1
	while main._throttle > 0.0 and t < 1.0:
		main._process(DT)
		if main._throttle > 0.0 and plays_at_release < 0 and main._clank_plays != plays_before:
			plays_at_release = int(t * 1000.0)  # fired before the throttle got home: a bug
		t += DT
	check(main._clank_plays == plays_before + 1,
		"a full release clanks once (got %d)" % (main._clank_plays - plays_before))
	check(plays_at_release < 0, "the clank waits for the stop, it does not fire on release (%d ms early)" % plays_at_release)
	check(abs(t - 0.075) < 0.02, "the grip takes the measured time to shut (%.3f s)" % t)
	check(main._clank_open == 0.0, "the owed clank is cleared after it fires")

	# ---- a blip: open 5%, below the opening gate ----
	var b: int = main._clank_plays
	main._throttle = 0.05
	main._throttle_last = 0.05
	main._throttle_springing = true
	for i in 20:
		main._process(DT)
	check(main._clank_plays == b, "a 5%% blip does not clank (got %d)" % (main._clank_plays - b))

	# ---- a slow close at the S-key rate: nothing slams ----
	var c: int = main._clank_plays
	main._throttle = 1.0
	main._throttle_last = 1.0
	main._throttle_springing = false
	for i in 120:
		main._throttle = maxf(main._throttle - main.THROTTLE_SPEED * DT, 0.0)
		main._update_throttle_clank(DT)
	check(main._clank_plays == c, "an eased close is silent (got %d)" % (main._clank_plays - c))
	check(main._clank_open == 0.0, "an eased close does not arm a clank")

	# ---- re-opened mid-return: cancelled ----
	var d: int = main._clank_plays
	main._throttle = 1.0
	main._throttle_last = 1.0
	main._throttle_springing = true
	main._throttle = maxf(1.0 - main.THROTTLE_RETURN_SPEED * DT, 0.0)
	main._update_throttle_clank(DT)
	check(main._clank_open > 0.0, "the release arm sets an owed clank")
	main._throttle_springing = false # rider twists it open again
	main._throttle = 0.95
	main._update_throttle_clank(DT)
	check(main._clank_open == 0.0 and main._clank_plays == d, "re-opening mid-return cancels the clank")

	# ---- level falls with the opening, but never to silence ----
	main._throttle = 0.0
	main._clank_open = 0.0
	main._sound_on = true
	main._play_clank(1.0)
	var loud: float = main._clank.volume_db
	main._play_clank(0.2)
	var soft: float = main._clank.volume_db
	check(loud > soft, "a full twist is louder than a 20%% blip (%.1f vs %.1f dB)" % [loud, soft])
	check(loud - soft < 20.0, "the level difference is musical, not a mute (%.1f dB)" % (loud - soft))

	if _fails == 0:
		print("throttle_clank_test: PASS (clank at the stop, gated on opening and return speed)")
	quit(0 if _fails == 0 else 1)
