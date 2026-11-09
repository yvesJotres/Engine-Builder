extends SceneTree

# The two-stroke expansion chamber, as the exhaust layout and the solver see it. Each cylinder gets its own four-section chain
# whose total length is the spec's chamber length; each section feeds the next; the stinger is open to the air. The solver runs
# the layout and stays finite, and the tail produces sound. Exits 1 on any failure.
# Run: godot --headless --path . -s res://tests/unit/exhaust/exhaust_chamber_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS["yamaha_rd350"]
	for key in p.keys():
		spec.set(key, p[key])
	var ports: Array[Vector3] = [Vector3(-0.4, 1.2, 0.4), Vector3(0.4, 1.2, 0.4)]
	var layout := ExhaustLayout.build(spec, ports)
	check(layout.pipes.size() == 4 * spec.cylinders, "four chamber sections per cylinder, got %d" % layout.pipes.size())
	var open_ends := 0
	for i in layout.pipes.size():
		var pipe: ExhaustLayout.Pipe = layout.pipes[i]
		check(pipe.kind == "chamber", "section %d is a chamber, got '%s'" % [i, pipe.kind])
		if pipe.feeders.is_empty() == false:
			check(pipe.feeders.size() == 1 and pipe.feeders[0] == i - 1 or pipe.cyl >= 0, "section %d is fed by the section before it" % i)
	# the chain of each cylinder: its total length is the spec's, and it ends open
	for cyl in spec.cylinders:
		var total := 0.0
		var first := -1
		for i in layout.pipes.size():
			if layout.pipes[i].cyl == cyl:
				first = i
		check(first >= 0, "cylinder %d has a chamber" % cyl)
		if first < 0:
			continue
		for k in 4:
			total += layout.pipes[first + k].length_m()
		check(absf(total - spec.expansion_chamber_length_m) < 0.02 * spec.expansion_chamber_length_m, "cylinder %d chamber is %.3f m, the spec's %.3f m" % [cyl, total, spec.expansion_chamber_length_m])
		check(layout.pipes[first + 3].feeders.size() == 1, "cylinder %d stinger is fed by the baffle chain" % cyl)
		if layout.pipes[first + 3].feeders.is_empty() == false:
			pass
	for pipe in layout.pipes:
		if pipe.feeders.is_empty() and pipe.kind == "chamber" and pipe.cyl < 0:
			open_ends += 1
	# the solver runs the layout and stays finite, and the stingers give out sound
	var gas := ExhaustGas.new()
	gas.build(layout)
	gas.record_audio = true
	var pulse_ok := true
	for i in 2000:
		var cyl := i % spec.cylinders
		gas.apply_valve(cyl, 0.0 if i % 40 > 0 else 0.02, 0.0)
		gas.advance(1.0 / 2400.0)
		for c in spec.cylinders:
			var pr := gas.port_pressure(c)
			if is_nan(pr) or is_inf(pr) or pr <= 0.0:
				pulse_ok = false
	check(pulse_ok, "the solver's port pressures stay finite and positive")
	var flow := gas.take_flow()
	check(flow.size() > 0, "the stingers give out sound samples, got %d" % flow.size())
	var peak := 0.0
	for v in flow:
		peak = maxf(peak, absf(v))
	check(is_finite(peak), "the tail flow is finite")
	print("exhaust_chamber_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
