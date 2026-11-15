extends SceneTree

# docs/EXHAUST_GEOMETRY.md is generated. This fails when the model and the committed report disagree, so a geometry change
# cannot leave a report describing the old pipe. It also checks the report describes a plausible system, so a report that
# is merely self-consistent still fails when the numbers are wrong.
# Run: godot --headless --path . -s tests/unit/model/pipe/exhaust_report_test.gd

const REPORT := preload("res://tools/diagnostics/exhaust_report.gd")
const DOC := "res://docs/EXHAUST_GEOMETRY.md"

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	var produced: String = REPORT.build_report()
	var committed := FileAccess.get_file_as_string(DOC)
	check(produced != "", "the generator produced nothing")
	if produced != committed:
		print("FAIL docs/EXHAUST_GEOMETRY.md is stale: regenerate it with")
		print("     godot --headless --path . -s res://tools/diagnostics/exhaust_report.gd")
		var want := produced.split("\n")
		var have := committed.split("\n")
		var shown := 0
		for i in mini(want.size(), have.size()):
			if want[i] != have[i] and shown < 5:
				print("  line %d: report has '%s', doc has '%s'" % [i + 1, want[i], have[i]])
				shown += 1
		_fails += 1

	# and the report has to describe a plausible system, not just a self-consistent one
	for id in ["honda_cbr250rr", "kawasaki_zx25r", "honda_cbr1000rrr_sp", "ducati_panigale_v4", "kawasaki_h2r"]:
		var data: Dictionary = REPORT.gather(id)
		check(int(data["rows"].size()) > 0, "%s: no pipes in the report" % id)
		for row in data["rows"]:
			match row["kind"]:
				"primary":
					check(row["bore_mm"] >= 24.0 and row["bore_mm"] <= 52.0,
						"%s: primary %.1f mm is outside 24-52 mm" % [id, row["bore_mm"]])
				"catalyst":
					check(row["shell_mm"] >= 50.0 and row["shell_mm"] <= 80.0,
						"%s: catalyst shell %.1f mm is outside 50-80 mm" % [id, row["shell_mm"]])
				"muffler":
					check(row["shell_mm"] >= 90.0 and row["shell_mm"] <= 130.0,
						"%s: canister %.1f mm is outside 90-130 mm" % [id, row["shell_mm"]])
				"tail":
					check(row["bore_mm"] >= 40.0 and row["bore_mm"] <= 70.0,
						"%s: outlet %.1f mm is outside 40-70 mm" % [id, row["bore_mm"]])
		# a system that is shorter than the bike's wheelbase cannot be an exhaust
		check(data["pipe_total_mm"] >= 1200.0 and data["pipe_total_mm"] <= 4500.0,
			"%s: total pipe length %.0f mm is implausible" % [id, data["pipe_total_mm"]])

	print("RESULT: " + ("PASS" if _fails == 0 else "%d failed" % _fails))
	quit(0 if _fails == 0 else 1)
