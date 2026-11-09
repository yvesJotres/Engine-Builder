extends SceneTree

# Extract ECU maps from N04 binary for CBR250RR preset

func _init() -> void:
	var parser_script: Script = load("res://scripts/ecu/ecu_binary_parser.gd") as Script
	var parser: RefCounted = parser_script.new()
	
	var path: String = "res://ecu_bins/CBR250RR-38770-K64-N04_BIN.bin"
	if not parser.load_binary(path):
		print("Failed to load binary")
		quit(1)
	
	var data: Dictionary = parser.parse_all()
	
	# Extract maps for preset
	var fuel_maps: Dictionary = {}
	var ign_maps: Dictionary = {}
	
	for i in range(4):  # fuel_1 to fuel_4
		var cyl1_key: String = "fuel_" + str(i + 1) + "_cyl1"
		var cyl2_key: String = "fuel_" + str(i + 1) + "_cyl2"
		if data.has(cyl1_key) and data.has(cyl2_key):
			fuel_maps["fuel_" + str(i + 1)] = {
				"cyl1": data[cyl1_key],
				"cyl2": data[cyl2_key]
			}
	
	for i in range(5):  # ign_1 to ign_5
		var cyl1_key: String = "ign_" + str(i + 1) + "_cyl1"
		var cyl2_key: String = "ign_" + str(i + 1) + "_cyl2"
		if data.has(cyl1_key) and data.has(cyl2_key):
			ign_maps["ign_" + str(i + 1)] = {
				"cyl1": data[cyl1_key],
				"cyl2": data[cyl2_key]
			}
	
	# Axes
	var rpm_axis: Array = data.get("rpm_axis", [])
	var map_axis: Array = data.get("map_axis", [])
	var tps_axis: Array = data.get("tps_axis", [])
	
	# Torque limiter
	var torque_limiter: Array = data.get("torque_limiter_gear", [])
	
	# Print as GDScript dictionary for preset
	print("fuel_maps = {")
	for key in fuel_maps:
		print("\t\"" + key + "\": {")
		print("\t\t\"cyl1\": " + str(fuel_maps[key]["cyl1"]) + ",")
		print("\t\t\"cyl2\": " + str(fuel_maps[key]["cyl2"]) + ",")
		print("\t},")
	print("}")
	
	print("\\nign_maps = {")
	for key in ign_maps:
		print("\t\"" + key + "\": {")
		print("\t\t\"cyl1\": " + str(ign_maps[key]["cyl1"]) + ",")
		print("\t\t\"cyl2\": " + str(ign_maps[key]["cyl2"]) + ",")
		print("\t},")
	print("}")
	
	print("\\nrpm_axis = " + str(rpm_axis))
	print("map_axis = " + str(map_axis))
	print("tps_axis = " + str(tps_axis))
	print("torque_limiter_gear = " + str(data.get("torque_limiter_gear", [])))
	
	quit(0)