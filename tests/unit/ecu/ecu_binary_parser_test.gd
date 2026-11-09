extends SceneTree

# Regression test for the Keihin K64 reader.  N04 is the sole verified map
# layout.  Other K64 dumps must fail closed rather than yield maps using N04
# offsets.  Run: Godot --headless --path . -s tests/unit/ecu/ecu_binary_parser_test.gd

const N04 := "res://ecu_bins/CBR250RR-38770-K64-N04_BIN.bin"
const OTHER_DUMPS := [
	"res://ecu_bins/38770-K64-N01.bin",
	"res://ecu_bins/38770-K64-R02.bin",
	"res://ecu_bins/CBR250RR-38770-K64-ND1_BIN.bin",
]


func _init() -> void:
	await process_frame
	var failures := 0
	var parser := ECUBinaryParser.new()
	failures += _check(parser.load_binary(N04), "N04 binary loads")
	failures += _check(parser.get_layout() == ECUBinaryParser.N04_LAYOUT, "N04 layout is identified")
	var data := parser.parse_all()
	var tps: Array = data.get("tps_axis", [])
	var rpm: Array = data.get("rpm_axis", [])
	var map: Array = data.get("map_axis", [])
	failures += _check(tps.size() == 25 and tps[0] == 0 and tps[-1] == 661, "N04 TPS axis is valid")
	failures += _check(rpm.size() == 35 and rpm[0] == 700 and rpm[-1] == 14500, "N04 RPM axis is valid")
	failures += _check(map.size() == 25 and map[0] == 118 and map[-1] == 594, "N04 MAP axis is valid")

	for path in OTHER_DUMPS:
		var unsupported := ECUBinaryParser.new()
		failures += _check(not unsupported.load_binary(path), path.get_file() + " is refused as an unverified layout")
		failures += _check(unsupported.get_parsed().is_empty(), path.get_file() + " returns no fabricated maps")

	if failures == 0:
		print("ecu_binary_parser_test: PASSED")
		quit(0)
	else:
		push_error("ecu_binary_parser_test: %d failures" % failures)
		quit(1)


func _check(condition: bool, message: String) -> int:
	if condition:
		return 0
	push_error("ecu_binary_parser_test: " + message)
	return 1
