class_name GasProperties
extends RefCounted

# Specific heats of the cylinder charge as FUNCTIONS OF TEMPERATURE, which is what "thermodynamics" needs: the constant
# cv the model used before is only true near 300 K. Air's cp rises from 1.005 kJ/(kg·K) at 300 K to 1.27 at 2,000 K,
# and burned products sit above air at every temperature. That matters twice over: the energy a hot charge holds
# (u = the integral of cv, not cv·T) and the enthalpy carried in and out by the valves (h = u + R·T).
#
# THE TABLE (cp, J/(kg·K), 1 atm): Keenan and Kaye / Cengel, "Thermodynamics", Appendix tables for air and for the
# products of a stoichiometric hydrocarbon flame. Values are quoted to about 1%, which is the accuracy the rest of the
# gas model has; the test checks the table points back against these figures.
# R is kept at 287.05 J/(kg·K) for both gases: the products' molar mass is within 1% of air's, and the mixture R that
# goes into p = mRT/V is the same one the rest of the code uses.
const R := 287.05
const T_MIN := 300.0
const T_MAX := 3000.0
const STEP := 100.0
const CP_AIR := [1005.0, 1014.0, 1030.0, 1051.0, 1075.0, 1099.0, 1121.0, 1142.0, 1161.0, 1179.0, 1195.0, 1207.0,
	1219.0, 1231.0, 1242.0, 1252.0, 1261.0, 1270.0, 1278.0, 1285.0, 1291.0, 1297.0, 1301.0, 1305.0, 1309.0, 1313.0,
	1317.0, 1321.0, 1328.0]
const CP_BURNT := [1105.0, 1118.0, 1135.0, 1152.0, 1168.0, 1182.0, 1195.0, 1207.0, 1217.0, 1227.0, 1236.0, 1244.0,
	1251.0, 1258.0, 1264.0, 1270.0, 1276.0, 1282.0, 1287.0, 1292.0, 1297.0, 1302.0, 1307.0, 1312.0, 1317.0,
	1322.0, 1327.0, 1332.0, 1338.0]

static var _u_air := PackedFloat64Array() # J/kg from 300 K, the integral of cv
static var _u_burnt := PackedFloat64Array()


# Integrates the table once, with the trapezoid rule on the piecewise-linear cp, so u(T) and cv(T) always agree.
static func _ensure_tables() -> void:
	if not _u_air.is_empty():
		return
	_u_air = PackedFloat64Array()
	_u_burnt = PackedFloat64Array()
	_u_air.resize(CP_AIR.size())
	_u_burnt.resize(CP_BURNT.size())
	_u_air[0] = 0.0
	_u_burnt[0] = 0.0
	for i in range(1, CP_AIR.size()):
		_u_air[i] = _u_air[i - 1] + 0.5 * (CP_AIR[i - 1] + CP_AIR[i] - 2.0 * R) * STEP
		_u_burnt[i] = _u_burnt[i - 1] + 0.5 * (CP_BURNT[i - 1] + CP_BURNT[i] - 2.0 * R) * STEP


# Index and fraction of the table point for a temperature, clamped to the table.
static func _table_pos(temp: float) -> Array:
	_ensure_tables()
	var t := clampf(temp, T_MIN, T_MAX)
	var f := (t - T_MIN) / STEP
	var i := mini(int(f), CP_AIR.size() - 2)
	return [i, f - float(i)]


static func cp_air(temp: float) -> float:
	var p := _table_pos(temp)
	return lerpf(CP_AIR[p[0]], CP_AIR[p[0] + 1], p[1])


static func cp_burnt(temp: float) -> float:
	var p := _table_pos(temp)
	return lerpf(CP_BURNT[p[0]], CP_BURNT[p[0] + 1], p[1])


# cp and cv of the charge, by how much of it has burned (0 = fresh air, 1 = products).
static func cp(burnt: float, temp: float) -> float:
	burnt = clampf(burnt, 0.0, 1.0)
	return lerpf(cp_air(temp), cp_burnt(temp), burnt)


static func cv(burnt: float, temp: float) -> float:
	return cp(burnt, temp) - R


# Internal energy above 300 K, J/kg: the integral of cv, not cv(T)·T.
static func u(burnt: float, temp: float) -> float:
	_ensure_tables()
	burnt = clampf(burnt, 0.0, 1.0)
	var p := _table_pos(temp)
	var ua := lerpf(_u_air[p[0]], _u_air[p[0] + 1], p[1])
	var ub := lerpf(_u_burnt[p[0]], _u_burnt[p[0] + 1], p[1])
	# outside the table (a cold charge, a very hot one) extrapolate with the end slope, so u stays monotonic with T
	var u_tab := lerpf(ua, ub, burnt)
	if temp < T_MIN:
		return u_tab + cv(burnt, T_MIN) * (temp - T_MIN)
	if temp > T_MAX:
		return u_tab + cv(burnt, T_MAX) * (temp - T_MAX)
	return u_tab


# Enthalpy above the same reference, J/kg: h = u + R·T.
static func h(burnt: float, temp: float) -> float:
	return u(burnt, temp) + R * temp


# The temperature that holds this internal energy, by Newton on u(T) with cv as the slope.
static func temp_from_u(burnt: float, energy: float) -> float:
	var t := clampf(T_MIN + maxf(energy, 0.0) / 800.0, 200.0, 4000.0) # 800 J/(kg·K) is a fair first guess for cv
	for i in 5:
		t = clampf(t - (u(burnt, t) - energy) / maxf(cv(burnt, t), 1.0), 200.0, 4000.0)
	return t
