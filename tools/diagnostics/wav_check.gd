extends SceneTree

func _init() -> void:
	for name in ["1_limiter.wav", "2_rev_bomb_idle.wav", "3_decel.wav", "4_upshift.wav"]:
		var wav := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://audio_demos/" + name))
		if wav == null:
			print("%s: missing" % name)
			continue
		var data := wav.data
		var n := data.size() / 2
		var energy := 0.0
		var hf := 0.0
		var prev := 0.0
		var peak := 0.0
		var loud := 0
		for i in n:
			var v := data.decode_s16(i * 2) / 32768.0
			energy += v * v
			var d := v - prev
			hf += d * d
			prev = v
			peak = maxf(peak, absf(v))
			# count sample-level spikes: a crack is a steep transient, a hum is not
			if absf(d) > 0.02:
				loud += 1
		print("%-22s peak %.2f, hf/energy %.4f, %d steep transients" % [name, peak, hf / maxf(energy, 1.0e-9), loud])
	quit(0)
