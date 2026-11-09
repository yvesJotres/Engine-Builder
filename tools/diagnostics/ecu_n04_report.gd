extends SceneTree

# Read-only report for the verified Indonesia CBR250RR N04 ECU flash.
# Run: Godot --headless --path . -s tools/diagnostics/ecu_n04_report.gd

const BIN := "res://ecu_bins/CBR250RR-38770-K64-N04_BIN.bin"


func _init() -> void:
	await process_frame
	var parser := ECUBinaryParser.new()
	if not parser.load_binary(BIN):
		quit(1)
		return
	var data := parser.parse_all()
	if data.is_empty():
		quit(1)
		return

	print("ECU layout: %s" % parser.get_layout())
	print("RPM axis: %s" % str(data["rpm_axis"]))
	print("TPS axis raw: %s" % str(data["tps_axis"]))
	print("TPS axis %%: %s" % str(_scaled(data["tps_axis"], ECUBinaryParser.CONVERSIONS["tps_percent"])))
	print("MAP axis raw: %s" % str(data["map_axis"]))
	print("TBW axis raw: %s" % str(data["tbw_axis"]))
	print("Limiter tables: %s" % str(_table_subset(data, ["limiter_1", "limiter_2", "limiter_3", "limiter_4", "limiter_5", "limiter_6"])))
	print("Speed limit tables km/h: %s / %s" % [str(data["speed_limiter_1"]), str(data["speed_limiter_2"])])
	print("Flags: %s" % str(data["flags"]))

	for family in ["fuel", "ign"]:
		for map_index in range(1, 6):
			var key_1 := "%s_%d_cyl1" % [family, map_index]
			var key_2 := "%s_%d_cyl2" % [family, map_index]
			if not data.has(key_1) or not data.has(key_2):
				continue
			var a: Dictionary = _stats(data[key_1])
			var b: Dictionary = _stats(data[key_2])
			print("%s %d: cyl1 min %.3f max %.3f mean %.3f | cyl2 min %.3f max %.3f mean %.3f | max delta %.3f" % [
				family, map_index, a.min, a.max, a.mean, b.min, b.max, b.mean, _max_delta(data[key_1], data[key_2])])

	print("Fuel balance IAP/TPS: %s" % str(data["fuel_balance_iap_tps"]))
	var fuel_5_stats := _stats(data["fuel_5_tps_rpm"])
	print("Fuel 5 TPS/RPM: min %.3f max %.3f mean %.3f" % [fuel_5_stats.min, fuel_5_stats.max, fuel_5_stats.mean])
	for family in ["tbw_sport", "tbw_comfort"]:
		for i in range(1, 7):
			var values: Array = data["%s_%d" % [family, i]]
			var stats := _stats(values)
			print("%s %d: min %.1f max %.1f mean %.1f" % [family, i, stats.min, stats.max, stats.mean])

	var torque: Array = data["torque_limiter_gear"]
	for gear in torque[0].size():
		var column: Array = []
		for row in torque:
			column.append(row[gear])
		var stats := _stats(column)
		print("Torque limiter gear %d: min %.0f max %.0f mean %.1f" % [gear + 1, stats.min, stats.max, stats.mean])
	quit(0)


func _scaled(values: Array, factor: float) -> Array:
	var out: Array = []
	for value in values:
		out.append(snappedf(float(value) / factor, 0.01))
	return out


func _table_subset(data: Dictionary, keys: Array) -> Dictionary:
	var out := {}
	for key in keys:
		out[key] = data[key]
	return out


func _stats(values: Array) -> Dictionary:
	var low := INF
	var high := -INF
	var total := 0.0
	var count := 0
	for value in values:
		if value is Array:
			var nested := _stats(value)
			low = minf(low, nested.min)
			high = maxf(high, nested.max)
			total += nested.total
			count += nested.count
		else:
			var number := float(value)
			low = minf(low, number)
			high = maxf(high, number)
			total += number
			count += 1
	return {"min": low, "max": high, "mean": total / maxf(count, 1), "total": total, "count": count}


func _max_delta(first: Array, second: Array) -> float:
	var maximum := 0.0
	for row in first.size():
		for column in first[row].size():
			maximum = maxf(maximum, absf(float(first[row][column]) - float(second[row][column])))
	return maximum
