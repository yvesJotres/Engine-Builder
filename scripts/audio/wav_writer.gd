class_name WavWriter
extends RefCounted

# Writes a standard RIFF/PCM WAV file. Supports 16-bit, 24-bit and 32-bit float PCM,
# mono or stereo, any sample rate. Call write_header() once, then store_samples() for
# each block of frames, then finish().

const RIFF_ID := "RIFF"
const WAVE_ID := "WAVE"
const FMT_ID := "fmt "
const DATA_ID := "data"

var file: FileAccess
var sample_rate: int
var num_channels: int
var bits_per_sample: int
var byte_rate: int
var block_align: int
var data_size: int
var header_written := false

# Opens `path` for writing. Returns null on success, or an error string on failure.
func open(path: String, in_sample_rate: int, in_num_channels: int, in_bits_per_sample: int) -> String:
	if in_sample_rate <= 0 or in_num_channels not in [1, 2] or in_bits_per_sample not in [16, 24, 32]:
		return "Invalid WAV sample rate, channel count or bit depth"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Could not open %s for writing" % [path]
	file = f
	file.big_endian = false
	sample_rate = in_sample_rate
	num_channels = in_num_channels
	bits_per_sample = in_bits_per_sample
	byte_rate = int(sample_rate * num_channels * (bits_per_sample / 8.0))
	block_align = int(num_channels * (bits_per_sample / 8.0))
	data_size = 0
	header_written = false
	return ""

# Writes the RIFF header and format chunk. Must be called before any samples.
func write_header() -> void:
	if header_written:
		return
	var riff_chunk_size_placeholder := 0
	file.store_string("RIFF")
	file.store_32(riff_chunk_size_placeholder) # filled in by finish()
	file.store_string("WAVE")

	file.store_string("fmt ")
	file.store_32(16) # fmt chunk size for PCM
	var audio_format := 1 # PCM
	if bits_per_sample == 32:
		audio_format = 3 # IEEE float
	file.store_16(audio_format)
	file.store_16(num_channels)
	file.store_32(sample_rate)
	file.store_32(byte_rate)
	file.store_16(block_align)
	file.store_16(bits_per_sample)

	file.store_string("data")
	file.store_32(0) # data chunk size, filled in by finish()
	header_written = true

# Appends stereo float32 samples in [-1, 1]. Converts to the target bit depth.
func store_samples(frames: PackedVector2Array) -> void:
	if not header_written:
		write_header()
	var frame_count := frames.size()
	for i in frame_count:
		_store_sample(frames[i].x)
		if num_channels == 2:
			_store_sample(frames[i].y)
	data_size += frame_count * block_align

func _store_sample(value: float) -> void:
	value = clampf(value, -1.0, 1.0)
	if bits_per_sample == 16:
		file.store_16(int(value * 32767.0))
	elif bits_per_sample == 24:
		file.store_buffer(_i24_to_bytes(int(value * 8388607.0)))
	else:
		file.store_float(value)

# Finishes the WAV: patches the RIFF and data chunk sizes, closes the file.
func finish() -> void:
	if not header_written:
		return
	file.seek_end()
	var padding := data_size % 2
	if padding != 0:
		file.store_8(0)
	var riff_size := 36 + data_size + padding
	file.seek(4)
	file.store_32(riff_size)
	file.seek(40) # data chunk size offset
	file.store_32(data_size)
	file.close()

# Converts a signed 32-bit int to 3 little-endian bytes.
func _i24_to_bytes(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.append(v & 0xFF)
	b.append((v >> 8) & 0xFF)
	b.append((v >> 16) & 0xFF)
	return b
