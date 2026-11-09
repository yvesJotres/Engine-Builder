extends SceneTree

var _fails := 0

func _init() -> void:
	var path := "user://wav_writer_test_%d.wav" % Time.get_ticks_usec()
	var frames := PackedVector2Array([Vector2(-1.0, 0.5), Vector2(0.0, 1.0), Vector2(1.0, -0.5)])
	for channels in [1, 2]:
		for depth in [16, 24, 32]:
			_check_file(path, frames, channels, depth)
	var invalid := WavWriter.new()
	check(invalid.open(path, 0, 2, 16) != "", "reject invalid sample rate")
	check(invalid.open(path, 44100, 3, 16) != "", "reject invalid channel count")
	check(invalid.open(path, 44100, 2, 8) != "", "reject unsupported bit depth")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)

func _check_file(path: String, frames: PackedVector2Array, channels: int, depth: int) -> void:
	var writer := WavWriter.new()
	if writer.open(path, 44100, channels, depth) != "":
		check(false, "open WAV")
		return
	writer.write_header()
	writer.store_samples(frames)
	writer.finish()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		check(false, "read WAV")
		return
	var bytes_per_frame := channels * depth / 8
	var payload_size := frames.size() * bytes_per_frame
	var label := "%d-bit %d-channel" % [depth, channels]
	check(file.get_buffer(4).get_string_from_ascii() == "RIFF", label + " RIFF")
	check(file.get_32() == 36 + payload_size + payload_size % 2, label + " RIFF size")
	check(file.get_buffer(4).get_string_from_ascii() == "WAVE", label + " WAVE")
	check(file.get_buffer(4).get_string_from_ascii() == "fmt ", label + " format chunk")
	check(file.get_32() == 16, label + " format size")
	check(file.get_16() == (3 if depth == 32 else 1), label + " format")
	check(file.get_16() == channels, label + " channels")
	check(file.get_32() == 44100, label + " sample rate")
	check(file.get_32() == 44100 * bytes_per_frame, label + " byte rate")
	check(file.get_16() == bytes_per_frame, label + " block alignment")
	check(file.get_16() == depth, label + " bit depth")
	check(file.get_buffer(4).get_string_from_ascii() == "data", label + " data chunk")
	check(file.get_32() == payload_size, label + " data size")
	check(file.get_length() == 44 + payload_size + payload_size % 2, label + " file size")
	for frame in frames:
		_check_sample(file, frame.x, depth, label)
		if channels == 2:
			_check_sample(file, frame.y, depth, label)
	if payload_size % 2 != 0:
		check(file.get_8() == 0, label + " padding")
	file.close()

func _check_sample(file: FileAccess, value: float, depth: int, label: String) -> void:
	if depth == 16:
		check(file.get_16() == (int(value * 32767.0) & 0xFFFF), label + " sample")
	elif depth == 24:
		var expected := int(value * 8388607.0)
		check(file.get_8() == (expected & 0xFF), label + " low byte")
		check(file.get_8() == ((expected >> 8) & 0xFF), label + " middle byte")
		check(file.get_8() == ((expected >> 16) & 0xFF), label + " high byte")
	else:
		check(is_equal_approx(file.get_float(), value), label + " float sample")

func check(ok: bool, message: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + message)