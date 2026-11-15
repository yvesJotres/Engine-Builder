extends SceneTree

# Things the app writes for the player belong in the app's own data folder, which exists on every machine and phone.
# The dyno graph used to be written into one developer's Downloads folder, so no other player could save one.
# Run: godot --headless --path . -s tests/integration/dyno/dyno_save_location_test.gd (prints PASS or FAIL)

var _fails := 0


func _init() -> void:
	await process_frame
	var src := FileAccess.get_file_as_string("res://scripts/dyno/dyno_view.gd")
	var folder := ""
	for line in src.split("
"):
		if line.begins_with("const GRAPH_FOLDER"):
			folder = line.split(":=")[1].strip_edges().trim_prefix('"').trim_suffix('"')
			break
	check(not folder.is_empty(), "the dyno screen declares where it saves graphs")
	check(folder.begins_with("user://"), "the graph folder is inside the app's own data folder, not an absolute path (%s)" % folder)
	check(not src.contains("C:/Users/"), "no developer's home folder is hard coded")

	# and it is really writable there
	check(DirAccess.make_dir_recursive_absolute(folder) == OK, "the graph folder can be created")
	var path := folder + "/save_location_probe.png"
	check(Image.create(4, 4, false, Image.FORMAT_RGBA8).save_png(path) == OK, "a graph can be written there")
	check(FileAccess.file_exists(path), "the written graph is on disk")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
