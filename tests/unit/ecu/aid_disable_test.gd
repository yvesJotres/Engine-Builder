extends SceneTree

func _init() -> void:
	var spec := EngineSpec.new()
	spec.quickshifter = true
	spec.launch_control = true
	var ecu := ECU.new()
	ecu.update(0.001, 6000.0, 1.0, true, spec, 0.0, 1.0, 1)
	assert(ecu.is_launch_active())
	assert(ecu.trigger_quickshifter(spec))
	spec.quickshifter = false
	spec.launch_control = false
	ecu.update(0.001, 6000.0, 1.0, true, spec, 0.0, 1.0, 1)
	assert(not ecu.is_quickshifter_active())
	assert(not ecu.is_launch_active())
	spec.quickshifter = true
	assert(ecu.trigger_quickshifter_downshift(spec))
	spec.quickshifter = false
	assert(ecu.update(0.001, 6000.0, 1.0, true, spec) < 0.0)
	assert(not ecu.is_quickshifter_blip_active())
	print("aid_disable_test: PASS")
	quit()
