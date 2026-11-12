extends SceneTree

# The layout rule from docs/LAYOUT.md, checked mechanically. A refactor that leaves one stale path behind fails here,
# which is the whole point: the suite notices, not a reviewer.
# Run: godot --headless --path . -s tests/unit/structure/layout_test.gd

const REQUIRED := [
	"res://scripts/model/engine/engine_model.gd",
	"res://scripts/model/engine/crankshaft.gd",
	"res://scripts/model/engine/intake_model.gd",
	"res://scripts/model/bike/drivetrain.gd",
	"res://scripts/model/bike/car_model.gd",
	"res://scripts/model/bike/clutch.gd",
	"res://scripts/model/bike/gearbox_model.gd",
	"res://scripts/model/bike/parts/sprocket.gd",
	"res://scripts/model/bike/parts/tire_tread.gd",
	"res://scripts/model/pipe/exhaust.gd",
	"res://scripts/model/props/dyno_cell.gd",
	"res://scripts/model/props/spl_meter_rig.gd",
	"res://scripts/model/props/ground.gd",
	"res://scripts/model/props/fuel_tank_model.gd",
	"res://scripts/model/props/fuel_line.gd",
	"res://scripts/ui/motion_blur.gd",
	"res://docs/LAYOUT.md",
]

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	# 1. every geometry file sits where the rule says it does
	for path in REQUIRED:
		check(FileAccess.file_exists(path) or ResourceLoader.exists(path), "missing %s" % path)

	# 2. no code is left under assets/, and none is referenced from it
	for file in _walk("res://assets"):
		if file.ends_with(".gd"):
			check(false, "code under assets/: %s" % file)

	# 3. nothing anywhere still points at the old home
	for folder in ["res://scripts", "res://tests", "res://scenes", "res://tools"]:
		for file in _walk(folder):
			if not (file.ends_with(".gd") or file.ends_with(".tscn")):
				continue
			if file == "res://tests/unit/structure/layout_test.gd":
				continue # this file names the old path once, to look for it
			var text := FileAccess.get_file_as_string(file)
			check(not text.contains("assets/3d/generated"), "%s still references assets/3d/generated" % file)

	# 4. no empty source folders left over from the abandoned reorganisation
	for stale in ["res://scripts/drawing", "res://scripts/ignition", "res://scripts/render"]:
		check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(stale)),
			"empty folder left behind: %s" % stale)

	# 5. the one file this plan splits actually got smaller
	var drivetrain := FileAccess.get_file_as_string("res://scripts/model/bike/drivetrain.gd")
	var lines := drivetrain.count("\n")
	check(lines > 0 and lines < 700, "drivetrain.gd is %d lines; the split target is under 700" % lines)

	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)


# Every file under dir, recursively.
func _walk(dir: String) -> Array[String]:
	var found: Array[String] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return found
	for folder in DirAccess.get_directories_at(dir):
		if folder.begins_with("."):
			continue
		found.append_array(_walk(dir + "/" + folder))
	for file in DirAccess.get_files_at(dir):
		found.append(dir + "/" + file)
	return found
