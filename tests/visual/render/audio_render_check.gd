extends SceneTree

var output_path := ""
var error_message := ""

func _init() -> void:
	var directory := OS.get_environment("TEMP").path_join("engine-render-check-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var renderer := AudioRenderer.new()
	root.add_child(renderer)
	renderer.render_completed.connect(func(path: String) -> void: output_path = path)
	renderer.render_failed.connect(func(message: String) -> void: error_message = message)
	renderer.render(EngineSpec.new(), null, 0.05, 44100, 16, 1.0, directory)
	if output_path == "" or error_message != "":
		print("FAIL render: ", error_message)
		quit(1)
		return
	var file := FileAccess.open(output_path, FileAccess.READ)
	if file == null:
		print("FAIL exported file cannot be opened")
		quit(1)
		return
	file.seek(40)
	var payload_size := file.get_32()
	var ok := payload_size == int(0.05 * 44100) * 4 and file.get_length() == payload_size + 44
	file.close()
	DirAccess.remove_absolute(output_path)
	DirAccess.remove_absolute(directory)
	renderer.free()
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)