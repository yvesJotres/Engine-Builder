class_name FrameStats
extends RefCounted

# Frame rate and frame time averaged over the last 500 ms, plus RAM, VRAM and GPU time.
# Same readout as Flatframe's Show FPS overlay.

const WINDOW_MS := 500
const NOT_AVAILABLE := "n/a"

var stamps: Array = [] # frame times in ms, over the last WINDOW_MS
var fps = null # null until two frames have been seen
var frame_ms = null
var gpu_ms = null # GPU render time of the last measured frame, null until the engine reports it


func tick(now: int) -> void:
	stamps.append(now)
	while stamps.size() > 0 and now - stamps[0] > WINDOW_MS:
		stamps.pop_front()
	if stamps.size() >= 2:
		var span: float = stamps[stamps.size() - 1] - stamps[0]
		frame_ms = span / (stamps.size() - 1)
		fps = 1000.0 / frame_ms


static func ram_mb() -> int:
	return roundi(OS.get_static_memory_usage() / 1048576.0)


static func vram_mb() -> int:
	return roundi(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0)


static func with_commas(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" if value < 0 else "") + out


func format_line() -> String:
	var fps_text := NOT_AVAILABLE if fps == null else "%dfps" % roundi(fps)
	var time_text := NOT_AVAILABLE if frame_ms == null else "%.2fms" % frame_ms
	var gpu_text := NOT_AVAILABLE if gpu_ms == null else "%.2fms" % gpu_ms
	return "Frame Rate %s  Time %s  GPU %s  RAM %sMB  VRAM %sMB" % [
		fps_text, time_text, gpu_text, with_commas(ram_mb()), with_commas(vram_mb()),
	]
