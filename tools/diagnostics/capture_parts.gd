extends SceneTree

# Renders only the piston, connecting rod and crankshaft of the single-cylinder model to a PNG.
# Run windowed (not --headless): godot --path <project> -s res://tools/diagnostics/capture_parts.gd

const OUT := "res://capture_parts.png"

func _init() -> void:
	var spec := EngineSpec.new()
	var model := EngineModel.new()
	get_root().add_child(model)
	model.build(spec)
	model.update_crank(60.0)

	# keep only the moving parts: piston, rod, crank (with its flywheels and balancer)
	var keep: Array = [model._crank_node, model._rod] + model._pistons
	for child in model.get_children():
		if not keep.has(child):
			child.visible = false

	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.look_at_from_position(Vector3(-4.0, 1.0, 3.0), Vector3(0.0, -0.5, 0.0))
	cam.current = true

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	get_root().add_child(light)

	for i in 5:
		await process_frame
	var image := get_root().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT))
	print("saved ", ProjectSettings.globalize_path(OUT))
	quit(0)
