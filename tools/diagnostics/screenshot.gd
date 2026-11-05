extends SceneTree

# Saves a PNG of the full main scene, so the layout can be checked without a person at the screen.
# Run windowed (not --headless):
#   godot --path "<project>" -s res://tools/diagnostics/screenshot.gd
# Output: screenshot.png in the project folder.

const OUT := "res://screenshot.png"
const FRAMES_TO_WAIT := 30 # lets the first frames build the scene and settle

func _init() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	_capture.call_deferred(FRAMES_TO_WAIT)


func _capture(frames: int) -> void:
	for i in frames:
		await process_frame
	var image := get_root().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT)
	image.save_png(path)
	print("saved ", path)
	quit(0)
