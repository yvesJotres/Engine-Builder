extends SceneTree

# Diagnostic: the on-screen rectangles of the settings panel and the touch controls in the main scene, to check they do not
# overlap. Forces the touch controls visible. Print only.
func _init() -> void:
	await process_frame
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var panel: Control = null
	var touch: Control = null
	for child in main.get_children():
		if child is ControlPanel:
			panel = child.get_child(0)
		if child is TouchControls:
			touch = child
	touch.visible = true
	await process_frame
	await process_frame
	var panel_rect := panel.get_global_rect()
	print("settings panel: x %.0f to %.0f, y %.0f to %.0f" % [panel_rect.position.x, panel_rect.end.x, panel_rect.position.y, panel_rect.end.y])
	for node in touch.find_children("*", "", true, false):
		if node is Control and node.get_child_count() > 0 and node.get_child(0) is Label:
			var r: Rect2 = node.get_global_rect()
			var overlap := r.intersects(panel_rect)
			print("%-10s x %.0f to %.0f, y %.0f to %.0f  %s" % [node.get_child(0).text, r.position.x, r.end.x, r.position.y, r.end.y, "OVERLAPS PANEL" if overlap else "clear"])
	quit(0)
