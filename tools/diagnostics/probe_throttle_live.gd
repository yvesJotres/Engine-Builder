extends SceneTree

# Live trace of the gamepad -> throttle path, for when a trigger does nothing in game.
#
# It runs the real main scene and, every frame, records what Godot reports for the pad, what Gamepad.throttle()
# makes of it, and what the game then does with it. The last line is END so the launcher knows it finished.
#
# What to do while it runs (the window opens on the game):
#   1. squeeze RIGHT TRIGGER all the way in, hold 2 s, release
#   2. squeeze LEFT TRIGGER all the way in, hold 2 s, release
#   3. optionally press A, RB, LB, Y once each
#
# Read the trace: a row where axes[5=...] rises but gp_th stays 0 means the axis index is wrong; a row where gp_th
# rises but main_th stays 0 means the game is discarding it; both rising means the input is fine and the engine is
# the problem.

const SECONDS := 45.0
const OUT := "res://tools/diagnostics/throttle_live.txt"


func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame

	var path := ProjectSettings.globalize_path(OUT)
	var lines := PackedStringArray()
	lines.append("pads: %s" % [Input.get_connected_joypads()])
	lines.append("in game: paused=%s ignition=%s gear=%d" % [main._paused, main._ignition, main._sim.gear.gear])
	lines.append("")

	var started := Time.get_ticks_msec()
	var last := ""
	var frames := 0
	while Time.get_ticks_msec() - started < int(SECONDS * 1000.0):
		await process_frame
		frames += 1
		var pad: int = Gamepad.device()
		var axes := PackedStringArray()
		for a in 8:
			var v := Input.get_joy_axis(pad, a)
			if absf(v) > 0.02:
				axes.append("%d=%.2f" % [a, v])
		var buttons := PackedStringArray()
		for b in 16:
			if pad >= 0 and Input.is_joy_button_pressed(pad, b):
				buttons.append(str(b))
		var row := "axes[%s] btns[%s]  gp_throttle=%.2f gp_clutch=%.2f | main._throttle=%.2f rpm=%.0f" % [
			",".join(axes), ",".join(buttons),
			Gamepad.throttle(pad), Gamepad.clutch(pad),
			main._throttle, main._sim.rpm]
		# only store changes, plus a heartbeat so the file proves it was running
		if row != last or frames % 60 == 0:
			lines.append("%5.1fs  %s" % [(Time.get_ticks_msec() - started) / 1000.0, row])
			last = row
		if frames % 15 == 0:
			_write(path, lines)
	lines.append("")
	lines.append("END")
	_write(path, lines)
	quit(0)


func _write(path: String, lines: PackedStringArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
