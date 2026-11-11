class_name ExhaustIr
extends RefCounted

# Builds a per-engine exhaust body by modifying the recorded base impulse response with the engine's own pipe
# geometry. The recorded base keeps the diffuse texture; the early reflections, quarter-wave resonances and
# displacement-dependent damping make the effective body distinct for every engine. A measured per-bike IR can
# still replace this through EngineSpec.exhaust_ir_path.

const RATE := 44100.0
const SPEED_OF_SOUND := 343.0 # m/s, hot exhaust gas is faster; this is a stable reference
const MAX_TAPS := 16384
const MOD_GAIN := 0.5

static func modify(base: PackedFloat32Array, spec: EngineSpec, layout: ExhaustLayout) -> PackedFloat32Array:
	if base.is_empty() or layout == null or layout.pipes.is_empty():
		return base

	# Mean pipe length/area/loss by kind.
	var length_sum := {}
	var area_sum := {}
	var loss_sum := {}
	var count := {}
	var total_length := 0.0
	for pipe in layout.pipes:
		var kind := str(pipe.kind)
		var length := pipe.length_m()
		if length <= 0.0:
			continue
		length_sum[kind] = float(length_sum.get(kind, 0.0)) + length
		area_sum[kind] = float(area_sum.get(kind, 0.0)) + pipe.area_m2()
		loss_sum[kind] = float(loss_sum.get(kind, 0.0)) + pipe.loss * length
		count[kind] = int(count.get(kind, 0)) + 1
		total_length += length
	if total_length <= 0.0:
		return base

	var primary_length := _mean(length_sum, count, "primary")
	var primary_area := _mean(area_sum, count, "primary")
	if primary_area <= 0.0:
		primary_area = 1.0
	var max_delay := 0
	for kind in length_sum:
		var length := _mean(length_sum, count, kind)
		max_delay = maxi(max_delay, int(round(2.0 * length / SPEED_OF_SOUND * RATE)))

	var out := PackedFloat32Array()
	out.resize(mini(base.size() + max_delay, MAX_TAPS))
	for i in base.size():
		out[i] = base[i]

	# Early reflections at the pipe round-trip times, with the first open-end sign inversion.
	for kind in length_sum:
		var length := _mean(length_sum, count, kind)
		var area := _mean(area_sum, count, kind)
		var loss := float(loss_sum[kind]) / maxf(float(count[kind]), 1.0)
		var delay := int(round(2.0 * length / SPEED_OF_SOUND * RATE))
		var area_ratio := clampf(sqrt(area / primary_area), 0.25, 2.0)
		var amp := exp(-loss) * area_ratio * MOD_GAIN
		_add_tap(out, base, delay, amp)
		_add_tap(out, base, delay * 2, -amp * 0.6)
		if kind == "muffler":
			_add_tap(out, base, delay * 3, amp * 0.35)

	# Quarter-wave pipe resonances. These are the audible "body" of the exhaust, not a fixed filter.
	var f_primary := SPEED_OF_SOUND / maxf(4.0 * primary_length, 0.05)
	var f_total := SPEED_OF_SOUND / maxf(2.0 * total_length, 0.1)
	_add_resonance(out, f_primary, 0.18, 0.03)
	_add_resonance(out, f_total, 0.12, 0.04)

	# A short, deterministic diffuse tail. Larger engines breathe through a larger, darker canister.
	var displacement := clampf(spec.displacement_cc / 1000.0, 0.0, 1.0)
	var cutoff := clampf(2500.0 - 1500.0 * displacement, 700.0, 2500.0)
	var tau := clampf(0.02 + 0.00003 * spec.displacement_cc, 0.02, 0.08)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(spec, total_length)
	var alpha := 1.0 - exp(-TAU * cutoff / RATE)
	var low := 0.0
	for i in out.size():
		low += alpha * (rng.randf_range(-1.0, 1.0) - low)
		out[i] += low * exp(-float(i) / (tau * RATE)) * 0.12

	# Remove DC and normalize. The base kernel is normalized by sum-abs; keep this one peak-normalized because
	# the convolution stage expects an IR shape rather than an energy total.
	var mean := 0.0
	for v in out:
		mean += v
	mean /= maxf(float(out.size()), 1.0)
	var weight := 0.0
	for i in out.size():
		out[i] -= mean
		weight += absf(out[i])
	if weight <= 1e-9:
		return base
	# Match _kernel(): normalize by sum-abs, not by peak. The convolution stage expects the same IR gain as
	# the recorded base, or a peak-normalized body would be hundreds of times too loud.
	for i in out.size():
		out[i] /= weight
	return out


static func _mean(sums: Dictionary, counts: Dictionary, kind: String) -> float:
	if not sums.has(kind):
		return 0.0
	return float(sums[kind]) / maxf(float(counts[kind]), 1.0)


static func _add_tap(out: PackedFloat32Array, base: PackedFloat32Array, delay: int, amp: float) -> void:
	if delay <= 0 or delay >= out.size() or absf(amp) <= 1e-6:
		return
	var limit := mini(out.size(), base.size() + delay)
	for i in range(delay, limit):
		out[i] += base[i - delay] * amp


static func _add_resonance(out: PackedFloat32Array, hz: float, amp: float, decay_s: float) -> void:
	var f := clampf(hz, 40.0, RATE * 0.45)
	for i in out.size():
		var env := exp(-float(i) / (decay_s * RATE))
		if env < 1e-4:
			break
		out[i] += sin(TAU * f * float(i) / RATE) * env * amp


static func _seed(spec: EngineSpec, total_length: float) -> int:
	var key := "%d|%.2f|%.2f|%.2f|%s|%.2f|%s|%.2f|%.3f" % [
		spec.cylinders, spec.displacement_cc, spec.bore_mm, spec.stroke_mm, spec.header,
		spec.header_primary_mm, spec.muffler_style, spec.redline_rpm, total_length,
	]
	return absi(hash(key))
