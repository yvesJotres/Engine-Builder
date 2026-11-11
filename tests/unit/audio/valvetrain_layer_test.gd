extends SceneTree

# The valvetrain layer: bounded and finite across the rpm sweep, silent when stopped or two-stroke, clicks follow rpm,
# repeatable, and no clipping at block edges. Exits 1 on any failure.
# Run: godot --headless --path . -s res://tests/unit/audio/valvetrain_layer_test.gd

const LAYER := preload("res://scripts/audio/layers/valvetrain_layer.gd")
const RATE := 44100

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func ctx(rpm: float) -> SoundContext:
	var c := SoundContext.new()
	c.rpm = rpm
	c.running = true
	c.four_stroke = true
	c.cylinders = 4
	c.valves_per_cylinder = 4
	return c


# Renders seconds of audio from a fresh layer, in blocks of block frames.
func render(c: SoundContext, seconds: float, block: int) -> PackedFloat32Array:
	var layer = LAYER.new()
	var total := int(seconds * RATE)
	var all := PackedFloat32Array()
	all.resize(total)
	var done := 0
	while done < total:
		var n := mini(block, total - done)
		var part: PackedFloat32Array = layer.render(n, c)
		for i in n:
			all[done + i] = part[i]
		done += n
	return all


func max_abs(s: PackedFloat32Array) -> float:
	var peak := 0.0
	for x in s:
		peak = maxf(peak, absf(x))
	return peak


func rms(s: PackedFloat32Array) -> float:
	var acc := 0.0
	for x in s:
		acc += x * x
	return sqrt(acc / maxf(float(s.size()), 1.0))


func count_over(s: PackedFloat32Array, level: float) -> int:
	var n := 0
	for x in s:
		if absf(x) > level:
			n += 1
	return n


func _init() -> void:
	# 1: finite and bounded across the rpm sweep
	for rpm in [600.0, 1500.0, 4000.0, 9000.0]:
		var s := render(ctx(rpm), 2.0, 441)
		var all_finite := true
		for x in s:
			if not is_finite(x):
				all_finite = false
		check(all_finite, "non-finite sample at %s rpm" % str(rpm))
		check(max_abs(s) <= 0.25, "peak %s at %s rpm is above 0.25" % [str(max_abs(s)), str(rpm)])

	# 2: silent when the engine is stopped, and for a two-stroke
	var stopped := ctx(3000.0)
	stopped.running = false
	check(max_abs(render(stopped, 0.5, 441)) == 0.0, "not silent when the engine is stopped")
	var two := ctx(3000.0)
	two.four_stroke = false
	check(max_abs(render(two, 0.5, 441)) == 0.0, "not silent for a two-stroke")

	# 3: there is sound at idle
	check(rms(render(ctx(1200.0), 1.0, 441)) > 0.0, "no sound at idle")

	# 4: more valve events at 6000 rpm than at 1200 rpm
	var fast := count_over(render(ctx(6000.0), 1.0, 441), 0.05)
	var slow := count_over(render(ctx(1200.0), 1.0, 441), 0.05)
	check(fast > slow, "6000 rpm has %d samples over 0.05, 1200 rpm has %d; expected more at 6000" % [fast, slow])

	# 5: same context, same output
	var first := render(ctx(2500.0), 1.0, 441)
	var second := render(ctx(2500.0), 1.0, 441)
	check(first == second, "two fresh instances give different output")

	# 6: block size does not change the level, so no clipping at block edges
	var small := render(ctx(3000.0), 1.0, 441)
	var big := render(ctx(3000.0), 1.0, 2205)
	check(max_abs(small) <= 0.25 and max_abs(big) <= 0.25, "block edges exceed 0.25 (441: %s, 2205: %s)" % [str(max_abs(small)), str(max_abs(big))])

	# 7: configured cam timing with live cylinder phases still renders cleanly
	var spec := EngineSpec.new()
	spec.cylinders = 4
	spec.valves_per_cylinder = 4
	var phased_layer = LAYER.new()
	phased_layer.configure(spec)
	var phased_ctx := ctx(1500.0)
	phased_ctx.cylinder_phase_deg = PackedFloat32Array([0.0, 180.0, 540.0, 360.0])
	var phased := PackedFloat32Array()
	for i in 100:
		phased.append_array(phased_layer.render(441, phased_ctx))
	check(max_abs(phased) <= 0.25, "phased valve events peak at %s, above 0.25" % str(max_abs(phased)))
	check(rms(phased) > 0.0, "phased valve events make no sound")

	print("valvetrain_layer_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
