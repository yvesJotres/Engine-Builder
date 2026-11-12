extends SceneTree

# Reports what Godot knows about the pad(s): name, every axis with the distinct values it showed, and every button index
# that was pressed. That is the complete binding picture - which axis each trigger is on, and which index A/RB/LB/Y are
# - for a pad whose layout Godot has no mapping for (common over Bluetooth, where SDL can fall back to raw HID).
# Writes tools/diagnostics/pad_census.txt and quits.

const SECONDS := 20.0


func _init() -> void:
	var pads := Input.get_connected_joypads()
	var lines := PackedStringArray()
	lines.append("pads: %s" % [pads])
	for p in pads:
		lines.append("pad %d name='%s' guid=%s" % [p, Input.get_joy_name(p), Input.get_joy_guid(p)])
	lines.append("")
	lines.append("watched for %d s - squeeze both triggers slowly and press every button while it runs" % int(SECONDS))
	lines.append("")

	var seen := {}
	var buttons := {}
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(SECONDS * 1000.0):
		await process_frame
		for p in pads:
			for a in 10:
				var v := Input.get_joy_axis(p, a)
				var key := "%d:%d" % [p, a]
				if not seen.has(key):
					seen[key] = {}
				seen[key][snappedf(v, 0.01)] = true
			for b in 20:
				if Input.is_joy_button_pressed(p, b):
					buttons["%d:%d" % [p, b]] = true

	for p in pads:
		lines.append("--- pad %d ---" % p)
		for a in 10:
			var key := "%d:%d" % [p, a]
			var values: Array = seen.get(key, {}).keys()
			values.sort()
			var shown := PackedStringArray()
			for i in min(values.size(), 6):
				shown.append("%.2f" % values[i])
			lines.append("  axis %d: %d distinct value(s)  %s%s" % [
				a, values.size(), ", ".join(shown), " ..." if values.size() > 6 else ""])
		var pressed := PackedStringArray()
		for b in 20:
			if buttons.has("%d:%d" % [p, b]):
				pressed.append(str(b))
		lines.append("  buttons pressed: [%s]" % ",".join(pressed))
		lines.append("")

	var path := ProjectSettings.globalize_path("res://tools/diagnostics/pad_census.txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	print("census written")
	quit(0)
