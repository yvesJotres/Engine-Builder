extends SceneTree

# Renders one backfire situation at a time, on its own track. Two identical engine sounds get the same gas flow and only one
# of them is given the pops, so (with pops) - (without pops) is the pop track exactly; the engine note is then dropped to
# NOTE_LEVEL and the pops are mixed on at full level.
#
# Run headless: godot --headless --path . -s res://tools/diagnostics/backfire_audio.gd

const DT := 1.0 / 60.0
const BLOCK := 735 # 44100 / 60: one frame of audio per frame of simulation
const NOTE_LEVEL := 0.25 # the rest of the engine, -12 dB, so the pops stand alone
const OUT_DIR := "res://audio_demos/"

var _note: EngineSound
var _pops: EngineSound
var _out := PackedFloat32Array()
var _out_pops := PackedFloat32Array() # the isolated pop track on its own: what the spectrograms are made of
var _pops_seen := 0
var _pops_drawn := 0
var _pop_acc := 0.0 # the isolated pop track's energy, so the render can prove the pops are in the file
var _note_acc := 0.0


func _spec(limiter_spark: bool, overrun: bool) -> EngineSpec:
	var spec := EngineSpec.new()
	for key in Presets.PRESETS["honda_cbr1000rrr_sp"].keys():
		spec.set(key, Presets.PRESETS["honda_cbr1000rrr_sp"][key])
	spec.quickshifter = true
	spec.limiter_spark_cut = limiter_spark
	spec.overrun_pop = overrun
	return spec


func _fresh(spec: EngineSpec) -> EngineSim:
	_out = PackedFloat32Array()
	_out_pops = PackedFloat32Array()
	_pops_seen = 0
	_pops_drawn = 0
	_pop_acc = 0.0
	_note_acc = 0.0
	_note = EngineSound.new()
	_pops = EngineSound.new()
	for s in [_note, _pops]:
		root.add_child(s)
		s.setup(spec)
		s.audio_enabled = true
	var sim := EngineSim.new()
	sim.audio_enabled = true
	# warm the pipe without recording: a cold pipe does not bang, and the warm-up would be 20 s of nothing
	for i in 240:
		sim.step(DT, spec, 0.0, true, i < 60, false, false, 1.0)
	sim.gear.gear = 0
	sim.clutch_pull = 1.0
	var redline: float = spec.redline_rpm
	spec.redline_rpm = 22000.0
	for i in 1200:
		sim.step(DT, spec, 1.0, true, false, false, false, 1.0)
	spec.redline_rpm = redline
	return sim


func _frame(sim: EngineSim, spec: EngineSpec, throttle: float) -> void:
	sim.step(DT, spec, throttle, true, false, false, false, 1.0)
	var flow: PackedFloat32Array = sim.take_blowdown()
	var intake: PackedFloat32Array = sim.take_intake_flow()
	for s in [_note, _pops]:
		if not flow.is_empty():
			s.push_flow(flow)
		if not intake.is_empty():
			s.push_intake_flow(intake)
		s.rpm = sim.rpm
		s.drive.update_from(sim, spec, throttle)
		s.set_conditions(sim.o2_lambda(), sim.exhaust_temp_c(), sim.backpressure_pa())
	if _pops_seen != sim.backfire_count:
		_pops_seen = sim.backfire_count
		_pops.backfire(sim.last_backfire_j) # one pop voice per frame, however many cylinders fired
		_pops_drawn += 1
	var a: PackedVector2Array = _note.render(BLOCK)
	var b: PackedVector2Array = _pops.render(BLOCK)
	for i in BLOCK:
		var pop := b[i].x - a[i].x
		_pop_acc += pop * pop
		_note_acc += a[i].x * a[i].x
		_out.append(a[i].x * NOTE_LEVEL + pop)
		_out_pops.append(pop)


func _encode(samples: PackedFloat32Array) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	return data


func _save(samples: PackedFloat32Array, name: String) -> void:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = EngineSound.RATE
	wav.stereo = false
	wav.data = _encode(samples)
	wav.save_to_wav(OUT_DIR + name)


func _write(name: String) -> void:
	var peak := 0.0
	for i in _out.size():
		peak = maxf(peak, absf(_out[i]))
	_save(_out, name)
	_save(_out_pops, name.replace(".wav", "_pops.wav"))
	var n := maxf(_out.size(), 1.0)
	print("%-22s %.1f s, %d pops, peak %.2f, pop rms %.3f, note rms %.3f" % [
		name, _out.size() / float(EngineSound.RATE), _pops_drawn, peak,
		sqrt(_pop_acc / n), sqrt(_note_acc / n) * NOTE_LEVEL])
	for s in [_note, _pops]:
		s.free()


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# 1. held on the rev limiter with the spark cut: the rev bomb
	var s1 := _spec(true, false)
	var sim := _fresh(s1)
	for i in 150:
		_frame(sim, s1, 1.0)
	_write("1_limiter.wav")

	# 2. rev bombing standing still: blip to the stop, off, blip again
	var s2 := _spec(true, false)
	sim = _fresh(s2)
	for blip in 4:
		for i in 30:
			_frame(sim, s2, 1.0)
		for i in 20:
			_frame(sim, s2, 0.0)
	_write("2_rev_bomb_idle.wav")

	# 3. decelerating: wind it up, then shut the throttle
	var s3 := _spec(false, true)
	sim = _fresh(s3)
	for i in 60:
		_frame(sim, s3, 1.0)
	for i in 150:
		_frame(sim, s3, 0.0)
	_write("3_decel.wav")

	# 4. upshifts: six quickshifter cuts with the pipe hot
	var s4 := _spec(false, false)
	sim = _fresh(s4)
	for i in 60:
		_frame(sim, s4, 0.5)
	for shift in 6:
		sim.gear.gear = mini(sim.gear.gear + 1, 6)
		sim.ecu.trigger_quickshifter(s4)
		for i in 30:
			_frame(sim, s4, 0.5)
	_write("4_upshift.wav")
	quit(0)
