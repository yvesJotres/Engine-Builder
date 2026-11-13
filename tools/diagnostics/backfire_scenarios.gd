extends SceneTree

const DT := 1.0 / 60.0

func _spec(limiter_spark: bool, overrun: bool) -> EngineSpec:
	var spec := EngineSpec.new()
	for key in Presets.PRESETS["honda_cbr1000rrr_sp"].keys():
		spec.set(key, Presets.PRESETS["honda_cbr1000rrr_sp"][key])
	spec.quickshifter = true
	spec.limiter_spark_cut = limiter_spark
	spec.overrun_pop = overrun
	return spec

func _warm(spec: EngineSpec, sim: EngineSim) -> void:
	for i in 240:
		sim.step(DT, spec, 0.0, true, i < 60, false, false, 1.0)
	sim.gear.gear = 0
	sim.clutch_pull = 1.0
	var redline: float = spec.redline_rpm
	spec.redline_rpm = 22000.0
	for i in 1200:
		sim.step(DT, spec, 1.0, true, false, false, false, 1.0)
	spec.redline_rpm = redline

func _collect(sim: EngineSim, frames: int, throttle: float, spec: EngineSpec, tag: String) -> void:
	var last := sim.backfire_count
	var lo := 1e9
	var hi := 0.0
	var n := 0
	var energy := 0.0
	for i in frames:
		sim.step(DT, spec, throttle, true, false, false, false, 1.0)
		if sim.backfire_count > last:
			var e: float = sim.last_backfire_j
			lo = minf(lo, e)
			hi = maxf(hi, e)
			energy += e
			n += 1
		last = sim.backfire_count
	var seconds := frames / 60.0
	if n == 0:
		print("%s: %d pops in %.1f s (%.0f rpm)" % [tag, n, seconds, sim.rpm])
	else:
		print("%s: %d pops in %.1f s (%.1f/s), %.0f-%.0f J each, %.0f W of bang (%.0f rpm)" % [
			tag, n, seconds, n / seconds, lo, hi, energy / seconds, sim.rpm])

func _init() -> void:
	# 1. held on the limiter, spark cut: a rev bomb
	var spec_a := _spec(true, false)
	var a := EngineSim.new()
	a.audio_enabled = false
	_warm(spec_a, a)
	_collect(a, 240, 1.0, spec_a, "limiter hold, spark cut ")

	# same bike, stock fuel-cut limiter
	var spec_b := _spec(false, false)
	var b := EngineSim.new()
	b.audio_enabled = false
	_warm(spec_b, b)
	_collect(b, 240, 1.0, spec_b, "limiter hold, fuel cut ")

	# 2. rev bombing in neutral at a standstill: blip to the stop, off, blip again
	var spec_c := _spec(true, false)
	var c := EngineSim.new()
	c.audio_enabled = false
	_warm(spec_c, c)
	var last := c.backfire_count
	var n := 0
	var lo := 1e9
	var hi := 0.0
	for blip in 6:
		for i in 45: # throttle on to the limiter
			c.step(DT, spec_c, 1.0, true, false, false, false, 1.0)
			if c.backfire_count > last:
				lo = minf(lo, c.last_backfire_j)
				hi = maxf(hi, c.last_backfire_j)
				n += 1
			last = c.backfire_count
		for i in 25: # off
			c.step(DT, spec_c, 0.0, true, false, false, false, 1.0)
			if c.backfire_count > last:
				lo = minf(lo, c.last_backfire_j)
				hi = maxf(hi, c.last_backfire_j)
				n += 1
			last = c.backfire_count
	print("rev bombing, 6 blips    : %d pops (%.1f per blip), %.0f-%.0f J (%.0f rpm)" % [n, n / 6.0, lo, hi, c.rpm])

	# 3. decelerating: wide open, then shut
	var spec_d := _spec(false, true)
	var d := EngineSim.new()
	d.audio_enabled = false
	_warm(spec_d, d)
	_collect(d, 60, 1.0, spec_d, "winding up               ")
	_collect(d, 240, 0.0, spec_d, "decelerating, overrun pops")

	# 4. upshift: quickshifter cut with the pipe hot
	var spec_e := _spec(false, false)
	var e := EngineSim.new()
	e.audio_enabled = false
	_warm(spec_e, e)
	for i in 60:
		e.step(DT, spec_e, 0.45, true, false, false, false, 1.0)
	var last2 := e.backfire_count
	var m := 0
	for shift in 6:
		e.gear.gear = minf(e.gear.gear + 1.0, 6.0)
		e.ecu.trigger_quickshifter(spec_e)
		for i in 40:
			e.step(DT, spec_e, 0.45, true, false, false, false, 1.0)
			if e.backfire_count > last2:
				m += 1
			last2 = e.backfire_count
	print("upshifts, 6 shifts      : %d pops (%.1f per shift) at %.0f rpm, pipe %.0f K" % [m, m / 6.0, e.rpm, e.cylinders[0]._port_heat])
	quit(0)
