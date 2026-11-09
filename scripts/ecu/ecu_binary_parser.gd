extends RefCounted

# CBR250RR ECU Binary Parser (Keihin 38770-K64-xxx)
# Parses raw ECU flash binary using known addresses from Kelvin Valencia's XDF definition
# Renesas SH7058, 1 MB flash, big-endian 16-bit values

class_name ECUBinaryParser

const FLASH_SIZE: int = 1048576  # 1 MB

# The addresses below are verified only for the Indonesia N04 flash.  Keihin K64
# files share the same size and part-family name but not necessarily the same
# map layout; applying this layout to them used to return convincing-looking,
# but invalid, values.  Add a layout only after its axes have been verified.
const N04_LAYOUT := "Keihin 38770-K64-N04 (Indonesia)"
const N04_TPS_FIRST := 0
const N04_TPS_LAST := 661
const N04_RPM_FIRST := 700
const N04_RPM_LAST := 14500
const N04_MAP_FIRST := 118
const N04_MAP_LAST := 594

# Known addresses from XDF (N04 Indonesia version as baseline)
const MAP_ADDRESSES: Dictionary = {
	"map_axis": 0x41222,
	"rpm_axis": 0x41254,
	"tps_axis": 0x411F0,
	"tbw_axis": 0x50CF6,
	"fuel_1_cyl1": 0x4129A,
	"fuel_1_cyl2": 0x41970,
	"fuel_2_cyl1": 0x42046,
	"fuel_2_cyl2": 0x4271C,
	"fuel_3_cyl1": 0x42DF2,
	"fuel_3_cyl2": 0x434C8,
	"fuel_4_cyl1": 0x43B9E,
	"fuel_4_cyl2": 0x44274,
	"fuel_5_tps_rpm": 0x50100,
	"fuel_balance_iap_tps": 0x5AC2C,
	"soi_map": 0x4FF50,
	"ign_1_cyl1": 0x45E5C,
	"ign_1_cyl2": 0x46532,
	"ign_2_cyl1": 0x479B4,
	"ign_2_cyl2": 0x4808A,
	"ign_3_cyl1": 0x4950C,
	"ign_3_cyl2": 0x49BE2,
	"ign_4_cyl1": 0x4B064,
	"ign_4_cyl2": 0x4B73A,
	"ign_5_cyl1": 0x4E84C,
	"ign_5_cyl2": 0x4EF22,
	"limiter_1": 0x44DD8,
	"limiter_2": 0x452A4,
	"limiter_3": 0x455F2,
	"limiter_4": 0x455FC,
	"limiter_5": 0x45944,
	"limiter_6": 0x4594C,
	"speed_limiter_1": 0x5D92C,
	"speed_limiter_2": 0x5D928,
	"torque_limiter_gear": 0x4DA5C,
	"tbw_sport_1": 0x51E1A,
	"tbw_sport_2": 0x535E4,
	"tbw_sport_3": 0x54DAE,
	"tbw_sport_4": 0x56578,
	"tbw_sport_5": 0x57D42,
	"tbw_sport_6": 0x5950C,
	"tbw_comfort_1": 0x50D66,
	"tbw_comfort_2": 0x52530,
	"tbw_comfort_3": 0x53D00,
	"tbw_comfort_4": 0x554CA,
	"tbw_comfort_5": 0x56C94,
	"tbw_comfort_6": 0x5845E,
}

const MAP_SIZES: Dictionary = {
	"fuel_1_cyl1": [25, 35],
	"fuel_1_cyl2": [25, 35],
	"fuel_2_cyl1": [25, 35],
	"fuel_2_cyl2": [25, 35],
	"fuel_3_cyl1": [25, 35],
	"fuel_3_cyl2": [25, 35],
	"fuel_4_cyl1": [25, 35],
	"fuel_4_cyl2": [25, 35],
	"fuel_5_tps_rpm": [25, 35],
	"ign_1_cyl1": [25, 35],
	"ign_1_cyl2": [25, 35],
	"ign_2_cyl1": [25, 35],
	"ign_2_cyl2": [25, 35],
	"ign_3_cyl1": [25, 35],
	"ign_3_cyl2": [25, 35],
	"ign_4_cyl1": [25, 35],
	"ign_4_cyl2": [25, 35],
	"ign_5_cyl1": [25, 35],
	"ign_5_cyl2": [25, 35],
	"fuel_balance_iap_tps": [25, 1],
	"torque_limiter_gear": [35, 6],
	"map_axis": 25,
	"rpm_axis": 35,
	"tps_axis": 25,
	"tbw_axis": 29,
	"soi_map": 1,
	"limiter_1": 3,
	"limiter_2": 2,
	"limiter_3": 2,
	"limiter_4": 2,
	"limiter_5": 2,
	"limiter_6": 1,
	"speed_limiter_1": 2,
	"speed_limiter_2": 1,
}

const CONVERSIONS: Dictionary = {
	"fuel": 1000.0,
	"tps_percent": 6.61,
	"speed_limit": 90.09,
	"tbw": 132.38,
	"ignition": 10.0,  # raw/10 - 36
	"ignition_offset": -36.0,
	"rpm_raw": 1.0,
	"map_raw": 1.0,
}

var _data: PackedByteArray
var _parsed: Dictionary
var _layout := ""
var _error := ""

func load_binary(path: String) -> bool:
	_error = ""
	_layout = ""
	_parsed = {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_error("Cannot open ECU binary: " + path)
		return false
	if file.get_length() != FLASH_SIZE:
		_set_error("Invalid ECU binary size: " + str(file.get_length()) + " (expected " + str(FLASH_SIZE) + ")")
		file.close()
		return false
	_data = file.get_buffer(FLASH_SIZE)
	file.close()
	_layout = _identify_layout()
	if _layout.is_empty():
		_set_error("Unsupported K64 ECU layout: the file is a valid 1 MB flash, but its axes do not match the verified N04 map addresses", false)
		return false
	return true


func _set_error(message: String, fatal := true) -> void:
	_error = message
	if fatal:
		push_error(message)
	else:
		push_warning(message)


func _identify_layout() -> String:
	# Read the boundary values directly.  This is deliberately strict: a wrong
	# layout must fail closed rather than feed nonsense into fuel or spark maps.
	var tps_last_addr := MAP_ADDRESSES["tps_axis"] + (MAP_SIZES["tps_axis"] - 1) * 2
	var rpm_last_addr := MAP_ADDRESSES["rpm_axis"] + (MAP_SIZES["rpm_axis"] - 1) * 2
	var map_last_addr := MAP_ADDRESSES["map_axis"] + (MAP_SIZES["map_axis"] - 1) * 2
	if _read_u16(MAP_ADDRESSES["tps_axis"]) == N04_TPS_FIRST \
			and _read_u16(tps_last_addr) == N04_TPS_LAST \
			and _read_u16(MAP_ADDRESSES["rpm_axis"]) == N04_RPM_FIRST \
			and _read_u16(rpm_last_addr) == N04_RPM_LAST \
			and _read_u16(MAP_ADDRESSES["map_axis"]) == N04_MAP_FIRST \
			and _read_u16(map_last_addr) == N04_MAP_LAST:
		return N04_LAYOUT
	return ""

func _read_u16(addr: int) -> int:
	if addr + 1 >= _data.size():
		return 0
	return (_data[addr] << 8) | _data[addr + 1]

func _read_u8(addr: int) -> int:
	if addr >= _data.size():
		return 0
	return _data[addr]

func _read_array_1d(addr: int, count: int) -> Array:
	var out: Array = []
	var i: int = 0
	while i < count:
		out.append(_read_u16(addr + i * 2))
		i += 1
	return out

func _read_array_2d(addr: int, rows: int, cols: int) -> Array:
	var out: Array = []
	var r: int = 0
	while r < rows:
		var row: Array = []
		var c: int = 0
		while c < cols:
			row.append(_read_u16(addr + (r * cols + c) * 2))
			c += 1
		out.append(row)
		r += 1
	return out

func _apply_conv_1d(arr: Array, factor: float) -> Array:
	var out: Array = []
	for v in arr:
		out.append(v / factor)
	return out

func _apply_conv_2d(arr: Array, factor: float) -> Array:
	var out: Array = []
	for row in arr:
		var new_row: Array = []
		for v in row:
			new_row.append(v / factor)
		out.append(new_row)
	return out

func parse_all() -> Dictionary:
	if _data.is_empty():
		_set_error("No binary loaded")
		return {}
	if _layout.is_empty():
		_set_error("No supported ECU layout identified", false)
		return {}
	
	var result: Dictionary = {}
	
	result["map_axis"] = _read_array_1d(MAP_ADDRESSES["map_axis"], MAP_SIZES["map_axis"])
	result["rpm_axis"] = _read_array_1d(MAP_ADDRESSES["rpm_axis"], MAP_SIZES["rpm_axis"])
	result["tps_axis"] = _read_array_1d(MAP_ADDRESSES["tps_axis"], MAP_SIZES["tps_axis"])
	result["tbw_axis"] = _read_array_1d(MAP_ADDRESSES["tbw_axis"], MAP_SIZES["tbw_axis"])
	
	for key in ["fuel_1_cyl1", "fuel_1_cyl2", "fuel_2_cyl1", "fuel_2_cyl2",
	            "fuel_3_cyl1", "fuel_3_cyl2", "fuel_4_cyl1", "fuel_4_cyl2"]:
		var addr: int = MAP_ADDRESSES[key]
		var size: Array = MAP_SIZES[key]
		var raw: Array = _read_array_2d(addr, size[0], size[1])
		result[key] = _apply_conv_2d(raw, CONVERSIONS["fuel"])
	
	var addr5: int = MAP_ADDRESSES["fuel_5_tps_rpm"]
	var size5: Array = MAP_SIZES["fuel_5_tps_rpm"]
	result["fuel_5_tps_rpm"] = _apply_conv_2d(_read_array_2d(addr5, size5[0], size5[1]), CONVERSIONS["fuel"])
	
	addr5 = MAP_ADDRESSES["fuel_balance_iap_tps"]
	size5 = MAP_SIZES["fuel_balance_iap_tps"]
	result["fuel_balance_iap_tps"] = _apply_conv_1d(_read_array_1d(addr5, size5[0]), CONVERSIONS["fuel"])
	
	for key in ["ign_1_cyl1", "ign_1_cyl2", "ign_2_cyl1", "ign_2_cyl2",
	            "ign_3_cyl1", "ign_3_cyl2", "ign_4_cyl1", "ign_4_cyl2",
	            "ign_5_cyl1", "ign_5_cyl2"]:
			var addr: int = MAP_ADDRESSES[key]
			var size: Array = MAP_SIZES[key]
			var raw: Array = _read_array_2d(addr, size[0], size[1])
			var converted: Array = _apply_conv_2d(raw, CONVERSIONS["ignition"])
			# Apply ignition offset: raw/10 - 36
			for row in converted:
				for i in range(row.size()):
					row[i] = row[i] + CONVERSIONS["ignition_offset"]
			result[key] = converted
	
	for i in range(1, 7):
		var key: String = "limiter_" + str(i)
		var addr: int = MAP_ADDRESSES[key]
		var count: int = MAP_SIZES[key]
		result[key] = _read_array_1d(addr, count)
	
	result["speed_limiter_1"] = _apply_conv_1d(_read_array_1d(MAP_ADDRESSES["speed_limiter_1"], MAP_SIZES["speed_limiter_1"]), CONVERSIONS["speed_limit"])
	result["speed_limiter_2"] = _apply_conv_1d(_read_array_1d(MAP_ADDRESSES["speed_limiter_2"], MAP_SIZES["speed_limiter_2"]), CONVERSIONS["speed_limit"])
	
	var tq_addr: int = MAP_ADDRESSES["torque_limiter_gear"]
	var tq_size: Array = MAP_SIZES["torque_limiter_gear"]
	result["torque_limiter_gear"] = _read_array_2d(tq_addr, tq_size[0], tq_size[1])
	
	for key in ["tbw_sport_1", "tbw_sport_2", "tbw_sport_3", "tbw_sport_4", "tbw_sport_5", "tbw_sport_6",
	            "tbw_comfort_1", "tbw_comfort_2", "tbw_comfort_3", "tbw_comfort_4", "tbw_comfort_5", "tbw_comfort_6"]:
		var addr: int = MAP_ADDRESSES[key]
		result[key] = _apply_conv_1d(_read_array_1d(addr, 100), CONVERSIONS["tbw"])
	
	var flags_addr: int = 0x500E4
	var flags_raw: int = _read_u16(flags_addr) | (_read_u16(flags_addr + 2) << 16)
	result["flags"] = {
		"immobilizer": (flags_raw >> 6) & 1,
		"ais": (flags_raw >> 15) & 1,
		"decel_cut": (flags_raw >> 9) & 1,
		"o2_sensor": flags_raw & 1,
		"o2_heater": (flags_raw >> 1) & 1,
	}
	var flags2: int = _read_u16(0x500EA)
	result["flags"]["disable_front_speed_sensor"] = (flags2 >> 10) & 1
	
	_parsed = result
	return result

func get_parsed() -> Dictionary:
	return _parsed


func get_layout() -> String:
	return _layout


func get_error() -> String:
	return _error

func get_fuel_map(cylinder: int, map_index: int) -> Array:
	var key: String = "fuel_" + str(map_index + 1) + "_cyl" + str(cylinder + 1)
	return _parsed.get(key, [])

func get_ignition_map(cylinder: int, map_index: int) -> Array:
	var key: String = "ign_" + str(map_index + 1) + "_cyl" + str(cylinder + 1)
	return _parsed.get(key, [])

func get_rpm_limiter(version: String = "indonesia") -> int:
	if version == "thailand":
		return 15000
	var lim: Array = _parsed.get("limiter_1", [])
	return lim[0] if lim.size() > 0 else 14000

func interpolate_2d(map_data: Array, x_axis: Array, y_axis: Array, x_val: float, y_val: float) -> float:
	if map_data.is_empty() or map_data[0].is_empty():
		return 0.0
	var rows: int = map_data.size()
	var cols: int = map_data[0].size()
	
	var x_idx: float = 0.0
	var i: int = 0
	while i < cols - 1:
		if x_val >= x_axis[i] and x_val <= x_axis[i + 1]:
			x_idx = i + (x_val - x_axis[i]) / (x_axis[i + 1] - x_axis[i])
			break
		i += 1
	if x_val <= x_axis[0]:
		x_idx = 0.0
	elif x_val >= x_axis[-1]:
		x_idx = float(cols - 1)
	
	var y_idx: float = 0.0
	i = 0
	while i < rows - 1:
		if y_val >= y_axis[i] and y_val <= y_axis[i + 1]:
			y_idx = i + (y_val - y_axis[i]) / (y_axis[i + 1] - y_axis[i])
			break
		i += 1
	if y_val <= y_axis[0]:
		y_idx = 0.0
	elif y_val >= y_axis[-1]:
		y_idx = float(rows - 1)
	
	var x0: int = int(floor(x_idx))
	var x1: int = min(x0 + 1, cols - 1)
	var y0: int = int(floor(y_idx))
	var y1: int = min(y0 + 1, rows - 1)
	
	var fx: float = x_idx - x0
	var fy: float = y_idx - y0
	
	var v00: float = map_data[y0][x0]
	var v01: float = map_data[y0][x1]
	var v10: float = map_data[y1][x0]
	var v11: float = map_data[y1][x1]
	
	var v0: float = v00 + (v01 - v00) * fx
	var v1: float = v10 + (v11 - v10) * fx
	return v0 + (v1 - v0) * fy
