extends SceneTree

# Runs every test under tests/unit and tests/integration, each in its own Godot process, because each test ends by calling
# quit(). A test fails when it exits non-zero, prints a SCRIPT ERROR, or prints a FAIL line. Visual and debug scripts are not
# run here. Run: godot --headless --path . -s res://tests/test_runner.gd

const FOLDERS := ["res://tests/unit", "res://tests/integration"]


func _init() -> void:
	var project := ProjectSettings.globalize_path("res://")
	var failed: Array[String] = []
	var count := 0
	for folder in FOLDERS:
		for path in _scripts(folder):
			count += 1
			var out: Array = []
			var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", project, "-s", path], out, true)
			var text := "\n".join(out)
			var bad := code != 0 or "SCRIPT ERROR" in text or " FAIL" in text
			print("%s %s" % ["FAIL" if bad else "ok  ", path.trim_prefix("res://tests/")])
			if bad:
				failed.append(path)
	print("RESULT: %d of %d failed" % [failed.size(), count])
	quit(1 if failed.size() > 0 else 0)


# Every .gd file under dir, including subfolders, in a stable order.
func _scripts(dir: String) -> Array[String]:
	var found: Array[String] = []
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_scripts(dir + "/" + sub))
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			found.append(dir + "/" + file)
	found.sort()
	return found
