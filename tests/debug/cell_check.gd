extends SceneTree

# Loads the main scene, turns the dyno drum on, and prints what the cell shows: its readout, its sweep status, and the
# speed and economy text from the HUD. Print only. Run: godot --headless --path . -s tests/debug/cell_check.gd
func _init() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 60:
		await process_frame
	main._set_cell(true)
	for i in 240:
		await process_frame
	main._on_dyno_pressed()
	for i in 1500:
		await process_frame
	print("READOUT: " + main._cell._readout.text.replace("\n", " | "))
	print("STATUS: " + main._cell_status.text)
	print("DYNO: active %s ok %s status %s" % [str(main._dyno.active()), str(main._dyno.ok), main._dyno.status])
	print("FUEL FLOW g/s: %.4f  (the km/L readout stays at -- below 0.05)" % main._sim.fuel_flow)
	quit()
