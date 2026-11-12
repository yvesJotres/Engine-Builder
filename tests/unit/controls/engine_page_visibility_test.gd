extends SceneTree

# The engine page shows only what the fitted engine can use. A single cylinder has no bank, no crank-pin
# arrangement and no firing order, so those rows must not be on screen: on the CBR150R they were shown at
# "inline / 90° / 360°", reading as settings that did something.
# Run: godot --headless --path . -s tests/unit/controls/engine_page_visibility_test.gd (prints PASS or FAIL)

var _fails := 0
var _panel


func _init() -> void:
	await process_frame
	_panel = ControlPanel.new()
	root.add_child(_panel)
	await process_frame

	# ---- one cylinder: nothing that arranges several of them ----
	_apply("honda_cbr150r")
	check(_panel._controls["cyl"].value == 1.0, "the CBR150R is one cylinder")
	check(not _panel._controls["layout"].visible, "a single cylinder hides the layout dropdown")
	check(_panel._layout_label != null and not _panel._layout_label.visible, "a single cylinder hides the layout label")
	check(not _panel._controls["bank_angle"].visible and not _panel._bank_label.visible, "a single cylinder hides the bank angle")
	check(not _panel._controls["shared_pins"].visible, "a single cylinder hides the crank-pin preset")
	check(not _panel._controls["twin"].visible and not _panel._custom_pin_label.visible, "a single cylinder hides the crank pin and custom pin")
	check(not _panel._controls["crank"].visible, "a single cylinder hides the crank layout")
	var firing_hidden := true
	for node in _panel._firing_rows:
		if node.visible:
			firing_hidden = false
	check(firing_hidden, "a single cylinder hides the firing order")
	# the rows a single cylinder does keep
	check(_panel._controls["cyl"].visible and _panel._controls["bore"].visible, "cylinder count and bore stay on screen")
	check(_panel._controls["stroke_type"].visible, "stroke type stays on screen")
	check(_validate() == "", "the single-cylinder preset still validates")
	# A row that exists twice is a row the hide logic cannot reach: the schema used to build a second copy of
	# bank angle, crankpins, crank pin and custom pin, and those copies stayed on screen.
	for label in ["Bank angle (°)", "Crank pins", "Crank pin", "Custom pin (°)"]:
		check(_row_count(label) == 1, "exactly one %s row on the engine page" % label)

	# ---- a V twin: the bank angle is the whole point ----
	_apply("harley_sportster_883")
	check(int(_panel._controls["cyl"].value) == 2, "the Sportster is a twin")
	check(_panel._controls["layout"].visible and _panel._layout_label.visible, "a twin shows the layout dropdown")
	check(_panel._controls["bank_angle"].visible and _panel._bank_label.visible, "a V twin shows the bank angle")
	check(_panel._controls["shared_pins"].visible, "a V twin shows the crank-pin preset")
	check(_row_count("Bank angle (°)") == 1 and _row_count("Crank pins") == 1, "the V twin shows one bank angle row and one crank-pins row")

	# ---- an inline four: the crank layout, no bank ----
	_apply("kawasaki_zx25r")
	check(int(_panel._controls["cyl"].value) == 4, "the ZX-25R is an inline four")
	check(_panel._controls["layout"].visible, "an inline four shows the layout dropdown")
	check(not _panel._controls["bank_angle"].visible, "an inline four has no bank angle on screen")
	check(_panel._controls["crank"].visible, "an inline four shows the crank layout")

	# ---- an inline twin: the 180/270/360 crank pin applies ----
	_apply("kawasaki_ninja_300")
	check(int(_panel._controls["cyl"].value) == 2, "the Ninja 300 is a twin")
	check(_panel._controls["twin"].visible, "an inline twin shows the crank pin")

	_panel.queue_free()
	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL"))
	quit(1 if _fails > 0 else 0)


func _apply(preset_id: String) -> void:
	var index: int = _panel._preset_ids.find(preset_id)
	if index < 0:
		check(false, "preset %s is in the library" % preset_id)
		return
	_panel._on_preset_selected(index)


func _validate() -> String:
	var spec := EngineSpec.new()
	_panel.apply_to(spec)
	return spec.validation_warning()


# How many rows on the engine page carry this label. More than one means a duplicate control nobody can hide.
func _row_count(text: String) -> int:
	var page: Control = _panel._controls["cyl"].get_parent()
	var n := 0
	for child in page.get_children():
		if child is Label and (child as Label).text == text:
			n += 1
	return n


func check(ok: bool, message: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + message)
