extends SceneTree

# Renders the pipe at the moment of a backfire, from the real scene, so the flash and the plume can be looked at.
# Run WITHOUT --headless (needs a renderer): godot --path . -s res://tools/diagnostics/backfire_render.gd

func _shot(main: Node, energy: float, path: String) -> void:
	main._sim.last_backfire_j = energy
	main._sim.backfire_count += 1
	# a hot pipe makes vapour; a rich one smokes
	main._exhaust_fume.update(760.0, 0.03, 0.62, 0.4)
	main._process(1.0 / 60.0)
	main._backfire_flame.update(1.0 / 240.0) # catch the flash a couple of frames in, near full size
	main._orbit._process(1.0 / 60.0)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("saved %s at %.0f J" % [path, energy])

func _init() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node = scene.instantiate()
	root.add_child(main)
	for i in 40:
		await process_frame
	var tail: Vector3 = main._tail_tip
	main._orbit.target = tail
	main._orbit.distance = 4.2
	main._orbit.yaw = -PI * 0.62
	main._orbit.pitch = 0.10
	main._orbit._process(1.0 / 60.0)
	for i in 6:
		await process_frame
	await _shot(main, 320.0, "res://backfire_limiter.png")
	await _shot(main, 78.0, "res://backfire_decel.png")
	quit(0)
