extends SceneTree


func _init() -> void:
	var fails := 0
	for count in [1, 2, 4, 8, 16]:
		var spec := EngineSpec.new()
		spec.cylinders = count
		var sim := EngineSim.new()
		var layout := ExhaustLayout.build(spec)
		sim.set_audio_layout(layout, count)
		if sim._runner_delays.size() != count:
			print("FAIL routing for ", count, " cylinders")
			fails += 1
			continue
		sim._build_cylinders(spec)
		for c in sim.cylinders:
			c.exhaust_mdot = 0.0
		sim.cylinders[0].exhaust_mdot = 1.0
		var delay: int = sim._runner_delays[0]
		for i in delay + 2:
			var value: float = sim._route_exhaust_flow()
			if (i == delay and value <= 0.0) or (i != delay and absf(value) > 0.00001):
				print("FAIL pulse timing ", count, " at ", i)
				fails += 1
			sim.cylinders[0].exhaust_mdot = 0.0
		sim.cylinders[0].exhaust_mdot = 1.0
		sim._route_exhaust_flow()
		sim.set_audio_layout(layout, count)
		sim.cylinders[0].exhaust_mdot = 0.0
		for i in sim._runner_stride:
			if absf(sim._route_exhaust_flow()) > 0.00001:
				print("FAIL stale pulse ", count)
				fails += 1
	var spec := EngineSpec.new()
	spec.cylinders = 2
	var sim := EngineSim.new()
	var layout := ExhaustLayout.build(spec)
	sim.set_audio_layout(layout, 2)
	var original := sim._runner_delays[0]
	var primary := layout.pipes[0]
	primary.pts[0] += Vector3(0, 0, 10.0)
	sim.set_audio_layout(layout, 2)
	if sim._runner_delays[0] <= original:
		print("FAIL longer runner does not delay pulse")
		fails += 1
	sim.set_audio_layout(ExhaustLayout.new(), 2)
	if not sim._runner_delays.is_empty():
		print("FAIL invalid layout fallback")
		fails += 1
	for config in [[1, false], [2, false], [4, false], [4, true], [8, false], [16, false]]:
		var sp := EngineSpec.new()
		sp.cylinders = config[0]
		sp.crossplane = config[1]
		var routed := EngineSim.new()
		var baseline := EngineSim.new()
		routed.set_audio_layout(ExhaustLayout.build(sp), sp.cylinders)
		for frame in 12:
			var throttle: float = [0.0, 0.6, 1.0, 0.0][int(frame / 3)]
			for engine in [routed, baseline]:
				engine.rpm = 3000.0
				engine.omega = 3000.0 * TAU / 60.0
				engine.running = true
				engine.step(1.0 / 60.0, sp, throttle, true, false, true, false, 1.0)
			if absf(routed.torque - baseline.torque) > 0.00001:
				print("FAIL audio routing changed physics ", config)
				fails += 1
			for sample in routed.take_blowdown():
				if not is_finite(sample):
					print("FAIL non-finite output ", config)
					fails += 1
			baseline.take_blowdown()
			routed.take_intake_flow()
			baseline.take_intake_flow()
		routed.audio_enabled = false
		routed.step(1.0 / 60.0, sp, 0.0, true, false, true, false, 1.0)
		if not routed.take_blowdown().is_empty():
			print("FAIL muted output ", config)
			fails += 1
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	quit(0 if fails == 0 else 1)
