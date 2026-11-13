extends Node

# Diagnostic runner: add this node to the running scene and it times one frame of the live app,
# phase by phase, on the device. The work is in frame_phases.gd; this file only starts it.
#
# From a phone with no keyboard, the pause menu's "Frame cost probe" button adds it. On a PC or
# with a hardware keyboard, F10 adds it too.

const PROBE := preload("res://scripts/diagnostics/frame_phases.gd")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		run()


func run() -> void:
	var main := get_tree().current_scene
	if main == null:
		print("frame probe: no current scene")
		return
	var probe := PROBE.new()
	probe.name = "FramePhasesProbe"
	main.add_child(probe)
