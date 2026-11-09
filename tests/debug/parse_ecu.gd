extends SceneTree

# Parse all CBR250RR ECU binaries and print key data

func _init() -> void:
	var parser_script: Script = load("res://scripts/ecu/ecu_binary_parser.gd") as Script
	var parser: RefCounted = parser_script.new()
	
	var bins: Array = [
		"res://ecu_bins/38770-K64-N01.bin",        # Thailand
		"res://ecu_bins/38770-K64-R02.bin",        # HRC
		"res://ecu_bins/CBR250RR-38770-K64-N04_BIN.bin",  # Indonesia N04
		"res://ecu_bins/CBR250RR-38770-K64-ND1_BIN.bin",  # Indonesia ND1 (SP QS)
	]
	
	for path in bins:
		print("\n=== Parsing: " + path + " ===")
		if not parser.load_binary(path):
			continue
		var data: Dictionary = parser.parse_all()
		
		# Print key info
		var limiter_1: Array = data.get("limiter_1", [])
		print("RPM Limiter (limiter_1): " + str(limiter_1))
		
		var speed_lim_1: Array = data.get("speed_limiter_1", [])
		print("Speed Limiter 1: " + str(speed_lim_1))
		
		var flags: Dictionary = data.get("flags", {})
		print("Flags: " + str(flags))
		
		# TPS axis (should be 0-661 raw -> 0-100%)
		var tps_axis: Array = data.get("tps_axis", [])
		if tps_axis.size() > 0:
			print("TPS axis range: " + str(tps_axis[0]) + " - " + str(tps_axis[-1]) + " (raw) -> 0 - " + str(tps_axis[-1]/6.61) + "%")
		
		# RPM axis
		var rpm_axis: Array = data.get("rpm_axis", [])
		if rpm_axis.size() > 0:
			print("RPM axis range: " + str(rpm_axis[0]) + " - " + str(rpm_axis[-1]))
		
		# MAP axis
		var map_axis: Array = data.get("map_axis", [])
		if map_axis.size() > 0:
			print("MAP axis range: " + str(map_axis[0]) + " - " + str(map_axis[-1]))
		
		# Fuel map sample (cyl 1, map 1)
		var fuel: Array = data.get("fuel_1_cyl1", [])
		if fuel.size() > 0 and fuel[0].size() > 0:
			print("Fuel 1 cyl 1 [0][0]: " + str(fuel[0][0]) + " µs")
			print("Fuel 1 cyl 1 [12][17] (mid): " + str(fuel[12][17]) + " µs")
		
		# Ignition map sample
		var ign: Array = data.get("ign_1_cyl1", [])
		if ign.size() > 0 and ign[0].size() > 0:
			print("Ign 1 cyl 1 [0][0]: " + str(ign[0][0]) + " deg")
			print("Ign 1 cyl 1 [12][17] (mid): " + str(ign[12][17]) + " deg")
		
		# Torque limiter by gear
		var tq: Array = data.get("torque_limiter_gear", [])
		if tq.size() > 0:
			print("Torque limiter by gear shape: " + str(tq.size()) + "x" + str(tq[0].size()))
			var row0: Array = []
			for i in range(min(6, tq[0].size())):
				row0.append(tq[0][i])
			print("  Gear 1 (row 0): " + str(row0))
	
	quit(0)