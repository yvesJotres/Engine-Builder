extends SceneTree

func _init() -> void:
	for cylinders in [1, 2, 4]:
		for header in ["stock", "4-1", "4-2-1"]:
			var spec := EngineSpec.new()
			spec.cylinders = cylinders
			spec.header = header
			var gas := ExhaustGas.new()
			gas.build(ExhaustLayout.build(spec))
			gas.record_audio = false
			for i in 100:
				gas.advance(0.001)
			for i in gas._n:
				if absf(gas._pressure(i) - ExhaustGas.P0) > 10.0 or absf(gas._velocity(i)) > 0.01:
					push_error("collector rest drift: %d cylinders %s cell %d pressure %.1f velocity %.3f" % [cylinders, header, i, gas._pressure(i), gas._velocity(i)])
					quit(1)
					return
	print("collector_rest_test: PASS")
	quit(0)
