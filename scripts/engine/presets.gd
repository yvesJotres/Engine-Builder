class_name Presets
extends RefCounted

# Engine presets loader. Each vehicle preset lives in its own JSON file under assets/engines/.
# Add a new .json file there with the preset data to register a preset.
# Schema: scripts/engine/presets/schema.json

const ENGINES_DIR := "res://assets/engines/"

# Populate PRESETS at script load time (runs once when this script is first loaded)
static var PRESETS: Dictionary = _build_presets()

static func _build_presets() -> Dictionary:
	var dict := {}
	var dir = DirAccess.open(ENGINES_DIR)
	if dir == null:
		push_error("Failed to open engines directory: " + ENGINES_DIR)
		return dict
	
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			var path = ENGINES_DIR + fname
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null:
				push_error("Failed to open preset: " + path)
			else:
				var json_str: String = file.get_as_text()
				file.close()
				var parsed: Variant = JSON.parse_string(json_str)
				if parsed is Dictionary:
					var data: Dictionary = parsed
					if _validate_preset(data, path):
						var flat := _flatten_preset(data)
						# Use stable ID from filename (without .json)
						var id: String = fname.get_basename()
						flat["id"] = id
						dict[id] = flat
					else:
						push_error("Preset validation failed for " + path)
				else:
					push_error("Invalid JSON in preset: " + path)
		fname = dir.get_next()
	return dict

static func _flatten_preset(data: Dictionary) -> Dictionary:
	var flat: Dictionary = {}
	# Copy display_name
	if data.has("display_name"):
		flat["display_name"] = data["display_name"]
	# Flatten geometry
	if data.has("geometry"):
		for key in data["geometry"]:
			flat[key] = data["geometry"][key]
	# Flatten valvetrain
	if data.has("valvetrain"):
		for key in data["valvetrain"]:
			flat[key] = data["valvetrain"][key]
	# Flatten drivetrain
	if data.has("drivetrain"):
		for key in data["drivetrain"]:
			flat[key] = data["drivetrain"][key]
	# Flatten ecu
	if data.has("ecu"):
		for key in data["ecu"]:
			flat[key] = data["ecu"][key]
	# Revision prevents an older server cache from undoing corrected factory data.
	if int(data.get("metadata", {}).get("revision", 0)) > 0:
		flat["preset_revision"] = int(data.metadata.revision)
	# Store raw ecu binary path for EngineSim
	if data.has("ecu") and data["ecu"].has("binary_path"):
		flat["ecu_binary"] = data["ecu"]["binary_path"]
	return flat

static func _validate_preset(data: Dictionary, path: String) -> bool:
	# Required top-level keys
	for key in ["display_name", "geometry", "valvetrain", "drivetrain", "ecu", "metadata"]:
		if not data.has(key):
			push_error("%s: missing required key '%s'" % [path, key])
			return false
	
	# Geometry validation
	var geo: Dictionary = data.get("geometry", {})
	if not geo.has("cylinders") or not geo.has("displacement_cc"):
		push_error("%s: geometry missing cylinders/displacement" % path)
		return false
	
	# Verify fire_deg matches cylinders
	if geo.has("fire_deg") and geo.has("cylinders"):
		var fire_deg: Array = geo["fire_deg"]
		if fire_deg.size() != geo["cylinders"]:
			push_error("%s: fire_deg length (%d) != cylinders (%d)" % [path, fire_deg.size(), geo["cylinders"]])
			return false
	
	# Verify gear_ratios is array
	var drv: Dictionary = data.get("drivetrain", {})
	if drv.has("gear_ratios") and drv["gear_ratios"] is not Array:
		push_error("%s: gear_ratios must be array" % path)
		return false
	
	# ECU binary path
	if not data.has("ecu") or not data["ecu"].has("binary_path"):
		push_error("%s: ecu.binary_path missing" % path)
		return false
	
	return true

# Populate PRESETS at script load time (runs once when this script is first loaded)

# Convenience: list of preset names in load order
static func names() -> Array:
	return PRESETS.keys()

# Lookup by display name
static func get_preset(name: String) -> Dictionary:
	return PRESETS.get(name, {})
