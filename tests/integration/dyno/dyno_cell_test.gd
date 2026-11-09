extends SceneTree

# The dyno cell's load must do what it says: with the drum on, the same wide-open pull in first gear reaches a lower speed
# than on the road, and a higher brake load reaches a lower speed still. Print only on failure; exits 1 if a check fails.
# Run: godot --headless --path . -s tests/integration/dyno/dyno_cell_test.gd
const MAX_LOAD_N := 1000.0
const DRUM_MASS_KG := 80.0
const SECONDS := 4.0


func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS["honda_cbr150r"]
	for key in p.keys():
		spec.set(key, p[key])
	var road := _pull(spec, DRUM_MASS_KG, 0.0) # the drum with no brake: the reference for every loaded run
	var light := _pull(spec, DRUM_MASS_KG, MAX_LOAD_N * 0.2)
	var heavy := _pull(spec, DRUM_MASS_KG, MAX_LOAD_N * 0.75)
	var stopped := _pull(spec, DRUM_MASS_KG, MAX_LOAD_N * 1.0)
	print("road %.2f m/s, drum light load %.2f m/s, drum heavy load %.2f m/s" % [road, light, heavy])
	print("full brake %.2f m/s" % stopped)
	# more load must always mean a lower speed; full brake on this bike should stop it
	var ok := road > light and light > heavy and heavy > stopped and heavy > 0.5
	print("dyno_cell_test: %s" % ("PASSED" if ok else "FAILED"))
	quit(0 if ok else 1)


# Speed after SECONDS of wide-open throttle in first gear, starting from a warm idle, with the given drum mass and brake force
func _pull(spec: EngineSpec, drum_mass: float, load_n: float) -> float:
	var sim := EngineSim.new()
	sim.cell_mass_kg = drum_mass
	sim.cell_load_n = 0.0 # the brake comes on above launch speed, as the game does
	for i in 900: # crank until it fires, then idle
		sim.step(1.0 / 60.0, spec, 0.2, true, i < 600, false, false, 1.0)
	sim.gear.gear = 2 # second: the limiter does not cap the speed, so the brake shows
	var frames := int(SECONDS * 60.0)
	for i in frames:
		sim.cell_load_n = load_n if sim.rpm > 2500.0 else 0.0
		sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)
	if sim.speed < 0.01:
		print("  no motion: rpm %.0f, gear %d, clutch %.2f" % [sim.rpm, sim.gear.gear, sim.clutch_engage])
	return sim.speed
