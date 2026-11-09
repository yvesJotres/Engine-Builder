class_name OnlineDyno
extends RefCounted

# Measured references are used for comparison only; never fed into EngineSim.
const NM_PER_LB_FT := 1.3558179483314

static func for_preset(id: String) -> Dictionary:
	if id.is_empty() or id != id.validate_filename():
		return {}
	var path := "res://assets/dyno/%s.json" % id
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("preset_id", "") != id or data.get("basis", "") != "rear_wheel":
		return {}
	return data


static func reference_curve(reference: Dictionary) -> Array:
	var result := []
	for sample in reference.get("power_samples", []):
		var rpm := float(sample[0])
		var hp := float(sample[1])
		if rpm > 0.0:
			result.append({"rpm": rpm, "hp": hp, "torque": hp * 745.7 / (rpm * TAU / 60.0)})
	return result


# Naturally aspirated DIN display normalization, not an engine-output adjustment.
# Dynojet's DIN reference: 1013 mbar, 20 C, dry air. The live cylinder model
# currently uses fixed P0/T0; editable weather metadata does not change its air.
# https://docs.dynojet.com/Support/SoftwareHelpFiles/PowerCoreHelp/en-US/2.1.0/DataCenter/DataCenter/DataCenter/To_Apply_Correction_Factors.htm
static func comparison_factor(reference: Dictionary) -> float:
	return (101300.0 / Cylinder.P0) * sqrt(Cylinder.T0 / 293.15) if str(reference.get("correction", "")).begins_with("DIN") else 1.0


static func wheel_estimate(crank_curve: Array, normalization := 1.0) -> Array:
	var result: Array = crank_curve.duplicate(true)
	for point in result:
		for key in ["torque", "hp", "corrected_torque", "corrected_hp", "torque_stdev"]:
			if point.has(key):
				point[key] = float(point[key]) * EngineSim.DRIVE_EFFICIENCY * normalization
	return result


static func compare(wheel_curve: Array, reference: Dictionary) -> Dictionary:
	if wheel_curve.is_empty() or reference.is_empty():
		return {}
	var peak_hp := {"hp": -INF, "rpm": 0.0}
	var peak_torque := {"torque": -INF, "rpm": 0.0}
	for point in wheel_curve:
		if float(point.hp) > float(peak_hp.hp):
			peak_hp = point
		if float(point.torque) > float(peak_torque.torque):
			peak_torque = point
	var power_error := float(peak_hp.hp) / float(reference.peak_power_hp) - 1.0
	var torque_error := float(peak_torque.torque) / (float(reference.peak_torque_lb_ft) * NM_PER_LB_FT) - 1.0
	var squared_error := 0.0
	var max_error := 0.0
	var compared := 0
	for sample in reference.get("power_samples", []):
		var rpm := float(sample[0])
		for i in range(1, wheel_curve.size()):
			var a: Dictionary = wheel_curve[i - 1]
			var b: Dictionary = wheel_curve[i]
			if float(a.rpm) <= rpm and float(b.rpm) >= rpm and float(b.rpm) > float(a.rpm):
				var hp := lerpf(float(a.hp), float(b.hp), (rpm - float(a.rpm)) / (float(b.rpm) - float(a.rpm)))
				var error := (hp - float(sample[1])) / float(reference.peak_power_hp)
				squared_error += error * error
				max_error = maxf(max_error, absf(error))
				compared += 1
				break
	return {"power_hp": peak_hp.hp, "power_rpm": peak_hp.rpm, "torque_nm": peak_torque.torque, "torque_rpm": peak_torque.rpm,
		"power_error": power_error, "torque_error": torque_error,
		"power_pass": absf(power_error) <= 0.03, "torque_pass": absf(torque_error) <= 0.05,
		"peak_rpm_pass": absf(float(peak_hp.rpm) - float(reference.peak_power_rpm)) <= 600.0,
		"curve_points_compared": compared, "curve_power_rmse_fraction": sqrt(squared_error / compared) if compared > 0 else null,
		"curve_power_max_error_fraction": max_error if compared > 0 else null,
		"curve_pass": compared == reference.get("power_samples", []).size() and compared > 0 and max_error <= 0.03,
		"basis": "estimated rear wheel; existing 93% drivetrain efficiency; comparison uses reference correction basis"}


static func wheel_result(crank: Dictionary, normalization := 1.0) -> Dictionary:
	var result: Dictionary = crank.duplicate(true)
	result.curve = wheel_estimate(crank.curve, normalization)
	for point in [result.peak_hp, result.peak_torque] + result.gears:
		for key in ["hp", "torque", "corrected", "stdev"]:
			if point.has(key):
				point[key] = float(point[key]) * EngineSim.DRIVE_EFFICIENCY * normalization
	return result
