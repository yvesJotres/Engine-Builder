extends SceneTree

# Every bike gets a header that suits its engine: no 250 four wearing a litre bike's 48 mm primary, no 999 four wearing a
# 4.8 mm capillary. The band is loose because primary sizing is a judgement call (a Harley runs a deliberately fat pipe,
# a big-bore dirt single a deliberately small one), but it catches the two failure modes that actually happened: the unit
# bug that made every preset 10x too small, and presets sharing one borrowed number.
# Run: godot --headless --path . -s tests/unit/exhaust/header_size_test.gd

const MIN_OD := 24.0
const MAX_OD := 52.0
const BAND_LO := 0.35 # primary OD as a share of bore
const BAND_HI := 0.62

var _fails := 0
var _checked := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	for file in DirAccess.get_files_at("res://assets/engines"):
		if not file.ends_with(".json"):
			continue
		var id := file.get_basename()
		var spec := EngineSpec.new()
		var preset: Dictionary = Presets.PRESETS.get(id, {})
		if preset.is_empty():
			continue
		for key in preset.keys():
			spec.set(key, preset[key])
		var layout := ExhaustLayout.build(spec, [], Vector3(0.0, 2.0, 0.0), Ground.Y, Vector3(0.0, 3.0, -5.95))
		var primary: ExhaustLayout.Pipe = null
		var secondary: ExhaustLayout.Pipe = null
		var collector: ExhaustLayout.Pipe = null
		var tail: ExhaustLayout.Pipe = null
		for pipe in layout.pipes:
			match pipe.kind:
				"primary":
					if primary == null:
						primary = pipe
				"secondary":
					secondary = pipe
				"collector":
					collector = pipe
				"tail":
					tail = pipe
		if primary == null:
			continue
		_checked += 1
		var od: float = primary.radii[0] * 200.0 # scene radius -> mm diameter
		var bore: float = spec.bore_mm
		check(od >= MIN_OD and od <= MAX_OD, "%s: primary %.1f mm is outside %.0f-%.0f mm" % [id, od, MIN_OD, MAX_OD])
		if bore > 0.0:
			check(od >= bore * BAND_LO and od <= bore * BAND_HI,
				"%s: primary %.1f mm is %.2f of its %.1f mm bore (allowed %.2f-%.2f)" % [id, od, od / bore, bore, BAND_LO, BAND_HI])
		if secondary != null:
			check(secondary.radii[0] >= primary.radii[0] * 0.99,
				"%s: the secondary (%.1f mm) is not smaller than the primary (%.1f mm)" % [id, secondary.radii[0] * 200.0, od])
		if collector != null:
			check(collector.radii[0] >= primary.radii[0] * 1.05,
				"%s: the collector (%.1f mm) should be bigger than the primary (%.1f mm)" % [id, collector.radii[0] * 200.0, od])
		if tail != null:
			var tail_od: float = tail.radii[0] * 200.0
			check(tail_od >= 28.0 and tail_od <= 60.0, "%s: tailpipe %.1f mm is outside 28-60 mm" % [id, tail_od])
		print("%-24s bore %5.1f  primary %5.1f mm (%.2f bore)  collector %5.1f  tail %5.1f" % [
			id, bore, od, od / maxf(bore, 1.0), (collector.radii[0] * 200.0) if collector != null else 0.0,
			(tail.radii[0] * 200.0) if tail != null else 0.0])

	# a spec with no header figure of its own falls back to the generic tube the sim's own exhaust model assumes, not to
	# a guess - every preset that ships is expected to carry a figure, and this test is what enforces it
	var bare := EngineSpec.new()
	var bare_layout := ExhaustLayout.build(bare, [], Vector3(0.0, 2.0, 0.0), Ground.Y, Vector3(0.0, 3.0, -5.95))
	var bare_od := 0.0
	for pipe in bare_layout.pipes:
		if pipe.kind == "primary":
			bare_od = pipe.radii[0] * 200.0
			break
	check(absf(bare_od - 32.0) < 1.0, "a spec with no header figure should fall back to the 32 mm tube, got %.1f" % bare_od)
	# and no shipped preset may be relying on that fallback
	for file in DirAccess.get_files_at("res://assets/engines"):
		if not file.ends_with(".json"):
			continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/engines/" + file))
		check(float(data.get("valvetrain", {}).get("header_primary_mm", 0.0)) > 0.0,
			"%s has no header_primary_mm of its own" % file)

	print("checked %d presets" % _checked)
	print("RESULT: " + ("PASS" if _fails == 0 else "%d failed" % _fails))
	quit(0 if _fails == 0 else 1)
