extends SceneTree

func _init() -> void:
	var clutch := Clutch.new()
	root.add_child(clutch)
	clutch.build(Vector3.ZERO, EngineSpec.new(), 0.0)
	clutch.update(0.0, 1.0)
	var engaged_plate: float = clutch._pressure.position.x
	var engaged_spring: float = clutch._springs[0].scale.x
	var fixed_end: float = clutch._springs[0].position.x + 0.05 * engaged_spring
	clutch.update(0.0, 0.0)
	assert(clutch._pressure.position.x > engaged_plate)
	assert(clutch._springs[0].scale.x < engaged_spring)
	assert(is_equal_approx(clutch._springs[0].position.x + 0.05 * clutch._springs[0].scale.x, fixed_end))
	assert(is_equal_approx(clutch._release_rod.position.x, clutch._pressure.position.x))
	print("clutch release motion: PASS")
	quit()
