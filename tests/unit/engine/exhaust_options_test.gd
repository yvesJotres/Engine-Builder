extends SceneTree

func _init() -> void:
	var spec := EngineSpec.new()
	var lengths := []
	for style in ["stock", "sport", "short"]:
		spec.muffler_style = style
		var layout := ExhaustLayout.build(spec)
		var muffler = null
		var tail = null
		for pipe in layout.pipes:
			if pipe.kind == "muffler": muffler = pipe
			if pipe.kind == "tail": tail = pipe
		assert(muffler != null and tail != null)
		# The outlet pipe is recessed into the canister so the mouth has depth (TAIL_RECESS, 2.5 cm), so its mouth sits
		# inside the can's end face instead of flush with it. Assert the recess is the declared one, and that the tailpipe
		# is still wired onto the muffler it slides into.
		var recess: float = muffler.pts[-1].distance_to(tail.pts[0])
		assert(is_equal_approx(recess, ExhaustLayout.TAIL_RECESS))
		assert(tail.feeders.size() == 1 and layout.pipes[tail.feeders[0]] == muffler)
		lengths.append(muffler.length_m())
		var visual := Exhaust.new()
		root.add_child(visual)
		visual.build(layout)
		assert(visual.get_child_count() > 0)
		visual.free()
	assert(lengths[0] > lengths[1] and lengths[1] > lengths[2])
	spec.stroke_type = "two_stroke"
	spec.muffler_style = "stock"
	var stock := ExhaustLayout.build(spec).total_length_m()
	spec.muffler_style = "short"
	assert(is_equal_approx(stock, ExhaustLayout.build(spec).total_length_m()))
	print("exhaust_options_test: PASS")
	quit()
