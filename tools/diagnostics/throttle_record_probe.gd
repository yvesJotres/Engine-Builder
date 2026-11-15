extends SceneTree

# Runs the REAL app windowed (not --headless), presses W with a real key event, and records what the panel shows every
# frame: wall-clock time, real frame delta, fps, the plate value, the rpm and the HUD string, plus a PNG of the window
# every 3rd frame. Headless stepping and the live render loop are not the same thing, and this is the only way to see
# which one the player is actually in.
# Run: godot --path . -s res://tools/diagnostics/throttle_record_probe.gd
# Writes: user://throttle_record/frame_XXXX.png and prints a CSV to stdout.

const DT_CAP := 0.25
var _rows: Array[String] = []


func _init() -> void:
	Engine.max_fps = 0 # uncapped, so the real delta tells us the true frame time
	var dir := "user://throttle_record"
	DirAccess.make_dir_recursive_absolute(dir)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame

	main._hud.mode = 1

	# start the engine with the panel starter, exactly as a player would
	main._touch_starter = true
	for i in 40:
		await process_frame
	main._touch_starter = false
	for i in 40:
		await process_frame

	var press := InputEventKey.new()
	press.physical_keycode = KEY_W
	press.keycode = KEY_W
	press.pressed = true

	var t0 := Time.get_ticks_usec()
	Input.parse_input_event(press)
	_rows.append("frame;wall_ms;delta_ms;fps;throttle;rpm;hud")

	var save_frames := OS.get_environment("SAVE_FRAMES") == "1" # writing PNGs from the main thread stalls the frame
	var n := 0
	var saved := 0
	var last_us := Time.get_ticks_usec()
	while n < 240:                     # up to 4 s at 60 fps, or as many frames as fit in ~4 s
		await process_frame
		var now := Time.get_ticks_usec()
		var delta := float(now - last_us) / 1000000.0
		last_us = now
		var wall := float(now - t0) / 1000000.0
		_rows.append("%d;%.1f;%.2f;%d;%.3f;%.0f;%s" % [n, wall * 1000.0,
			minf(delta, DT_CAP) * 1000.0, Engine.get_frames_per_second(),
			main._throttle, main._sim.rpm, main._hud._panel.info])
		if save_frames and n % 3 == 0 and saved < 80:
			var img := root.get_texture().get_image()
			if img != null:
				img.save_png("%s/frame_%04d.png" % [dir, saved])
				saved += 1
		n += 1
		if wall > 4.0:
			break

	var release := InputEventKey.new()
	release.physical_keycode = KEY_W
	release.keycode = KEY_W
	release.pressed = false
	Input.parse_input_event(release)

	print("=== CSV ===")
	for r in _rows:
		print(r)
	var path := ProjectSettings.globalize_path("user://throttle_record")
	print("=== frames saved to %s ===" % path)
	quit(0)
