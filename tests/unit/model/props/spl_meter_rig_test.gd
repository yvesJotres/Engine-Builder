extends SceneTree

# The sound level meter stand has to stand exactly where the reading is taken: its capsule on main._spl_mic, the point
# SplMeter defines (0.5 m from the outlet, 45 degrees off the flow, at the outlet's height or the standard's floor).
# Feet on the floor, display showing the same number the dashboard prints, and the whole rig following the pipe when
# the bike is rebuilt and the outlet moves.
# Run: godot --headless --path . -s tests/unit/geometry/spl_meter_rig_test.gd (exit code 1 on failure)

const MAIN_SCENE := "res://scenes/main.tscn"

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	var scene: PackedScene = load(MAIN_SCENE)
	var game := scene.instantiate()
	root.add_child(game)
	for i in 6:
		await process_frame

	var rig = game._spl_rig
	check(rig != null, "the game builds a sound level meter rig")
	if rig == null:
		print("RESULT: FAIL")
		quit(1)
		return
	_check_placement(game, rig, "first layout")

	# the display shows the number the dashboard prints, and reads "--" with nothing to measure
	check(rig.display_text() == SplMeter.text(game._spl_db),
		"display shows the live reading ('%s' vs '%s')" % [rig.display_text(), SplMeter.text(game._spl_db)])
	game._sound_on = false
	game._spl_db = -100.0
	await process_frame
	check(rig.display_text() == "-- dB", "a stopped engine reads '-- dB', got '%s'" % rig.display_text())
	check(rig.display_text() == SplMeter.text(game._spl_db), "and the display still matches SplMeter.text")
	game._sound_on = true

	# a rebuild that moves the outlet: the rig has to follow it, not stay where it was. The geometry rebuild is
	# debounced (main.REBUILD_DELAY), so ask for it now the way the game does at startup rather than racing the timer
	# with a fixed number of frames.
	var tip_before: Vector3 = game._tail_tip
	var style := game._panel._controls["muffler_style"] as OptionButton
	style.select(1 if style.selected == 0 else 0)
	game._panel.changed.emit()
	game.flush_rebuild()
	for i in 2:
		await process_frame
	check(game._tail_tip.distance_to(tip_before) > 0.05,
		"the rebuild moved the outlet (%.2f units)" % game._tail_tip.distance_to(tip_before))
	_check_placement(game, rig, "second layout")

	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)


# Everything the placement promises, for whatever layout is in front of us.
func _check_placement(game, rig, label: String) -> void:
	var capsule: Vector3 = rig.capsule_position()
	var tip: Vector3 = game._tail_tip
	var offset: Vector3 = capsule - tip
	var flat := Vector3(offset.x, 0.0, offset.z)
	var flow: Vector3 = Vector3(game._tail_dir.x, 0.0, game._tail_dir.z).normalized()
	var angle: float = rad_to_deg(flat.angle_to(flow)) if flat.length() > 0.001 else 0.0
	var behind: float = flat.dot(flow)
	print("%s: capsule %s, outlet %s, %.3f units away (%.1f deg off the flow, %.2f units downstream), mast %.3f units (%.0f mm)" % [
		label, capsule, tip, offset.length(), angle, behind, rig.mast_height(), rig.mast_height() * 100.0])
	check(absf(offset.length() - SplMeter.MIC_DISTANCE) < 0.05,
		"%s: the capsule is %.3f units from the outlet, not %.1f" % [label, offset.length(), SplMeter.MIC_DISTANCE])
	check(absf(angle - SplMeter.MIC_ANGLE_DEG) < 0.5,
		"%s: the capsule stands %.1f degrees off the flow, not %.0f" % [label, angle, SplMeter.MIC_ANGLE_DEG])
	check(behind > SplMeter.MIC_DISTANCE * cos(deg_to_rad(SplMeter.MIC_ANGLE_DEG)) * 0.95,
		"%s: the capsule is downstream of the outlet (%.3f units)" % [label, behind])
	check(capsule.distance_to(game._spl_mic) < 0.05,
		"%s: the capsule is on main._spl_mic (%.3f away)" % [label, capsule.distance_to(game._spl_mic)])
	check(absf(rig.feet_y() - Ground.Y) < 0.05, "%s: the feet are on the floor (%.3f vs %.3f)" % [label, rig.feet_y(), Ground.Y])
	check(rig.mast_height() > 0.5, "%s: the mast lifts the capsule off the floor (%.3f units)" % [label, rig.mast_height()])
	# the boom points back at the outlet: the head sits behind the capsule, on the line out to the pipe
	var to_tip := Vector3(tip.x - capsule.x, 0.0, tip.z - capsule.z)
	var to_head: Vector3 = rig.get_node("Head").global_position - capsule
	to_head.y = 0.0
	check(to_head.length() > 0.5 and to_head.normalized().dot(-to_tip.normalized()) > 0.99,
		"%s: the boom points back at the outlet" % label)
