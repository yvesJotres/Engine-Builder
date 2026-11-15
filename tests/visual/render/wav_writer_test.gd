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
	_check_sample_values(path)
	_check_unwritten_file_closes(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)


# The header checks above never look at the samples. The full-scale ones matter most: +1.0 and -1.0 have different
# room in two's complement, so a value scaled the same way on both sides wraps (clipping to a loud click).
func _check_sample_values(path: String) -> void:
	var values := [1.0, 0.5, 0.0, -0.5, -1.0, 1.5, -1.5]
	var frames := PackedVector2Array()
	for v in values:
		frames.append(Vector2(v, v))
	for depth in [16, 24]:
		var writer := WavWriter.new()
		writer.open(path, 44100, 2, depth)
		writer.write_header()
		writer.store_samples(frames)
		writer.finish()
		var bytes := FileAccess.get_file_as_bytes(path)
		var full: int = 32767 if depth == 16 else 8388607
		var size: int = 2 if depth == 16 else 3
		var got: Array = []
		for i in values.size():
			var off := 44 + i * size * 2 # stereo: left then right, both the same value here
			var v: int = bytes.decode_s16(off) if depth == 16 else _s24(bytes, off)
			got.append(v)
		var label := "%d-bit sample values" % depth
		check(got[0] == full, label + ": +1.0 is full scale (%d, got %d)" % [full, got[0]])
		check(got[4] == -(full + 1), label + ": -1.0 is full scale (%d, got %d)" % [-(full + 1), got[4]])
		check(got[1] > 0 and got[3] < 0, label + ": the sign is kept")
		check(got[5] == full and got[6] == -(full + 1), label + ": a value past full scale clamps instead of wrapping")


# A signed 24-bit little-endian sample, read by hand: PackedByteArray has no s24 decoder.
func _s24(bytes: PackedByteArray, offset: int) -> int:
	var v: int = bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16)
	return v - 16777216 if v >= 8388608 else v


# A WAV opened but never given samples must still close its file, or the handle leaks and the file stays locked.
func _check_unwritten_file_closes(path: String) -> void:
	var writer := WavWriter.new()
	writer.open(path, 44100, 2, 16)
	writer.finish()
	check(writer.file == null or not writer.file.is_open(), "finish() on an empty WAV closes the file")

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

# The expected integer for a sample. Two's complement has room for one more negative step than positive, so a
# negative sample is scaled by that limit: scaling -1.0 by +32767 and masking it would expect the 32769 that
# wraps when written as an int16, which is the click this test used to bless.
func _expected(value: float, full: int) -> int:
	return int(value * full) if value >= 0.0 else int(value * (full + 1))


func _check_sample(file: FileAccess, value: float, depth: int, label: String) -> void:
	if depth == 16:
		check(file.get_16() == _expected(value, 32767) & 0xFFFF, label + " sample")
	elif depth == 24:
		var expected := _expected(value, 8388607)
		check(file.get_8() == (expected & 0xFF), label + " low byte")
		check(file.get_8() == ((expected >> 8) & 0xFF), label + " middle byte")
		check(file.get_8() == ((expected >> 16) & 0xFF), label + " high byte")
	else:
		check(is_equal_approx(file.get_float(), value), label + " float sample")

func check(ok: bool, message: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + message)