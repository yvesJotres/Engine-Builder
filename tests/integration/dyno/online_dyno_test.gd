extends SceneTree

const ONLINE := preload("res://scripts/dyno/online_dyno.gd")

func _init() -> void:
	var reference := ONLINE.for_preset("honda_cbr1000rrr_sp")
	assert(reference.year == 2020 and reference.market == "UK")
	assert(ONLINE.for_preset("yamaha_yzf_r1m").is_empty())
	assert(ONLINE.for_preset("../honda_cbr1000rrr_sp").is_empty())
	var source := [{"rpm": 10000.0, "torque": 100.0, "hp": 140.0}]
	var wheel := ONLINE.wheel_estimate(source)
	assert(is_equal_approx(wheel[0].torque, 93.0) and is_equal_approx(wheel[0].hp, 130.2))
	assert(source[0].torque == 100.0 and source[0].hp == 140.0, "wheel display must not rewrite crank measurements")
	var normalization := ONLINE.comparison_factor(reference)
	assert(absf(normalization - 1.0113663762620013) < 1e-12, "DIN normalization must use the model's actual fixed air conditions")
	assert(ONLINE.comparison_factor({}) == 1.0)
	assert(is_equal_approx(ONLINE.wheel_estimate(source, normalization)[0].torque, 93.0 * normalization))
	var target := [{"rpm": 13900.0, "hp": 199.76, "torque": 100.0}, {"rpm": 12500.0, "hp": 180.0, "torque": 78.96 * 1.3558179483314}]
	var check := ONLINE.compare(target, reference)
	assert(check.power_pass and check.torque_pass and check.peak_rpm_pass)
	assert(absf(check.power_error) < 1e-8 and absf(check.torque_error) < 1e-8)
	var exact_curve := ONLINE.reference_curve(reference)
	var exact_check := ONLINE.compare(exact_curve, reference)
	assert(exact_check.curve_points_compared == 21 and exact_check.curve_pass)
	assert(is_zero_approx(exact_check.curve_power_rmse_fraction))
	exact_curve[2].hp += 20.0
	assert(not ONLINE.compare(exact_curve, reference).curve_pass, "matching peaks must not hide an incorrect midrange curve")
	for point in ONLINE.reference_curve(reference):
		assert(absf(point.torque * point.rpm * TAU / 60.0 - point.hp * 745.7) < 1e-6, "reference must obey P = torque * omega")
	var view := DynoView.new()
	view.reference_path = "user://online_dyno_test_no_reference.json"
	root.add_child(view)
	await process_frame
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	var dyno := DynoTest.new()
	dyno.start(spec, sim)
	dyno.reference_id = "honda_cbr1000rrr_sp"
	dyno._gear = 1
	sim.cycle_ready = true
	sim.cycle_mean_rpm = 10000.0
	sim.cycle_brake_torque = 100.0
	for i in 2:
		sim.cycle_index += 1
		dyno._record(sim)
	dyno.cancel()
	view.open()
	view.refresh(dyno)
	assert(view._basis.visible and view._basis.selected == 1)
	assert(is_equal_approx(view._graph._curve[0].torque, 93.0 * normalization))
	assert(view._graph._reference_power and view._reference_button.disabled)
	assert(view._peaks.text.begins_with("Estimated rear-wheel"))
	view._basis.select(0)
	view._basis.item_selected.emit(0)
	assert(is_equal_approx(view._graph._curve[0].torque, 100.0))
	assert(view._peaks.text.begins_with("Cycle-averaged crank"))
	# A short viewport must scroll rather than expand across the dashboard.
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	assert(view._panel.get_rect().end.y <= 720.0 - 250.0)
	var scroll: ScrollContainer = view._panel.get_child(0)
	assert(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page)
	dyno.reference_id = "yamaha_yzf_r1m"
	view.refresh(dyno)
	assert(not view._basis.visible and view._basis.selected == 0 and not view._online_status.visible)
	assert(not view._graph._reference_power and view._graph._reference.is_empty())
	view.free()
	print("Online dyno units, immutable crank data, view modes, scrolling and bike switching: PASS")
	quit()
