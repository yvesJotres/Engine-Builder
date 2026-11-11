class_name DynoRunner
extends RefCounted

# Runs the automatic dyno headless for a bundled preset. The same steps as the dyno screen, without the UI.

const DT := 1.0 / 60.0 # the frame step the dyno screen uses
const MAX_FRAMES := 200000 # safety cap: well above a full six-gear pull at the game's frame rate


# The bundled preset as an EngineSpec, or null when the preset does not exist.
static func spec_for(preset_id: String) -> EngineSpec:
	var flat: Dictionary = Presets.get_preset(preset_id)
	if flat.is_empty():
		return null
	var spec := EngineSpec.new()
	for key in flat:
		if key in spec:
			spec.set(key, flat[key])
	return spec


static func display_name_for(preset_id: String) -> String:
	return str(Presets.get_preset(preset_id).get("display_name", preset_id))


# A full dyno pull through every gear at wide-open throttle. Returns DynoTest.result().
static func run(spec: EngineSpec, reference_id: String) -> Dictionary:
	var sim := EngineSim.new()
	sim.fuel.set_kind(spec.fuel)
	var dyno := DynoTest.new()
	dyno.reference_id = reference_id
	dyno.start(spec, sim)
	var frames := 0
	while dyno.active() and frames < MAX_FRAMES:
		dyno.advance(DT, sim, spec, 1.0, true)
		frames += 1
	return dyno.result()
