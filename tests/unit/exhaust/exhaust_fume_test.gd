extends SceneTree

# The plume at the pipe, driven by the engine rather than by a timer: water vapour while the gas is still cool, carbon only
# while the mixture is rich, both scaled by mass flow, and nothing at all when the engine is not running.
# Run: godot --headless --path . --quit-after 3000 -s res://tests/unit/exhaust/exhaust_fume_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	await process_frame
	var fume := ExhaustFume.new()
	holder.add_child(fume)
	fume.build()
	fume.place(Vector3(1.0, 0.5, -2.0), Vector3(0.0, 0.0, -1.0))

	# engine off: nothing comes out
	fume.update(300.0, 0.0, 1.0, 1.0 / 60.0)
	check(not fume.emitting_now(), "a stopped engine shows nothing")
	check(fume.density() == 0.0, "and its density is zero (%.3f)" % fume.density())

	# cold start: cool gas at low flow is a white plume
	fume.update(400.0, 0.008, 1.0, 1.0 / 60.0)
	print("cold idle 400 K, 0.008 kg/s: vapour %.2f, soot %.2f, density %.2f" % [fume.vapour(), fume.soot(), fume.density()])
	check(fume.emitting_now(), "a cold engine makes vapour")
	check(fume.vapour() == 1.0, "full vapour below VAPOUR_FULL_K (%.2f)" % fume.vapour())
	check(fume.soot() == 0.0, "and no soot on a clean mixture (%.2f)" % fume.soot())

	# hot and clean: the plume is gone
	fume.update(1100.0, 0.05, 1.0, 1.0 / 60.0)
	print("hot 1100 K, 0.05 kg/s, lambda 1.00: vapour %.2f, soot %.2f, density %.2f" % [fume.vapour(), fume.soot(), fume.density()])
	check(not fume.emitting_now(), "a hot exhaust is dry")
	check(fume.density() == 0.0, "no particles at full temperature (%.3f)" % fume.density())

	# rich: soot builds, and clears again when the mixture comes back
	for i in 240:
		fume.update(1200.0, 0.04, 0.6, 1.0 / 60.0)
	var built := fume.soot()
	print("4 s rich (lambda 0.60): soot %.2f, density %.2f" % [built, fume.density()])
	check(built > 0.5, "a rich mixture makes soot (%.2f)" % built)
	check(fume.emitting_now(), "and it shows")
	for i in 600:
		fume.update(1200.0, 0.04, 1.0, 1.0 / 60.0)
	print("10 s clean afterwards: soot %.2f" % fume.soot())
	check(fume.soot() < built * 0.5, "the soot clears once the mixture is back (%.2f -> %.2f)" % [built, fume.soot()])

	# more flow, more plume
	fume.update(450.0, 0.01, 1.0, 1.0 / 60.0)
	var light := fume.density()
	fume.update(450.0, 0.04, 1.0, 1.0 / 60.0)
	var heavy := fume.density()
	print("cold at 0.010 kg/s density %.2f, at 0.040 kg/s density %.2f" % [light, heavy])
	check(heavy > light * 2.0, "density follows mass flow (%.2f vs %.2f)" % [light, heavy])

	# the plume leaves the outlet, not the inside of the pipe
	check(fume.global_position.z < -2.0, "the plume starts outside the outlet (z %.3f)" % fume.global_position.z)
	holder.free()

	print("exhaust_fume_test: %s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
