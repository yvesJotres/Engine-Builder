extends SceneTree

func _init() -> void:
	var spec := EngineSpec.new()
	var gas := ExhaustGas.new()
	gas.build(ExhaustLayout.build(spec))
	print("cells %d" % gas._n)
	for i in gas._n:
		print("cell %d area %.6f dx %.3f" % [i, gas._area[i], gas._dx[i]])
	for f in gas._nf:
		print("face %d kind %d L %d R %d sl %.3f sr %.3f" % [f, gas._fk[f], gas._fl[f], gas._fr[f], gas._sl[f], gas._sr[f]])
	for n in 20:
		gas.advance(0.001)
		print("t %d port %.0f Pa u0 %.2f utail %.2f Q %.4f" % [n, gas.port_pressure(0), gas._velocity(0), gas._velocity(gas._n - 1), gas.tail_volume_flow()])
	var sim := EngineSim.new()
	sim.exhaust_solver = true
	sim.physics_dt = 1.0 / 1200.0
	sim.omega = 1400.0 * TAU / 60.0
	sim.rpm = 1400.0
	sim.running = true
	for i in 800:
		sim.step(sim.physics_dt, spec, 0.2, true, false, true, false, 1.0)
		if sim.exhaust != null:
			sim.exhaust.take_flow()
	var flow := PackedFloat32Array()
	for i in 1200:
		sim.step(sim.physics_dt, spec, 0.2, true, false, true, false, 1.0)
		if sim.exhaust == null:
			continue
		var chunk := sim.exhaust.take_flow()
		var base := flow.size()
		flow.resize(base + chunk.size())
		for j in chunk.size():
			flow[base + j] = chunk[j]
	var mean := 0.0
	for s in flow:
		mean += s
	mean /= maxf(flow.size(), 1)
	var fires := sim.rpm / 120.0
	var ac0 := 0.0
	var ac := 0.0
	var lag := int(round(44100.0 / maxf(fires, 1.0)))
	if lag > 10 and lag < flow.size() / 2:
		for i in range(0, flow.size() - lag, 4):
			var a := flow[i] - mean
			ac0 += a * a
			ac += a * (flow[i + lag] - mean)
	print("run rpm %.0f samples %d mean %.5f fire %.1f Hz autocorr %.3f" % [sim.rpm, flow.size(), mean, fires, ac / maxf(ac0, 1e-12)])
	var sound := EngineSound.new()
	sound.setup(spec)
	sound.push_flow(flow)
	var audio := sound.render(mini(flow.size(), 44100))
	var a0 := 0.0
	var a1 := 0.0
	if lag > 10 and lag < audio.size() / 2:
		for i in range(0, audio.size() - lag, 4):
			a0 += audio[i].x * audio[i].x
			a1 += audio[i].x * audio[i + lag].x
	print("audio autocorr %.3f" % (a1 / maxf(a0, 1e-12)))
	quit(0)
