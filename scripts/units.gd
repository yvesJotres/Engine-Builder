class_name Units
extends RefCounted

# One place for units, conversions, physical constants and the small calculations built on them.
# Everything inside the simulation uses SI units: metres, kilograms, seconds, kelvin, pascals,
# joules, watts. Only the UI and the scene use other units, and they convert through here.
# Scene units: 1 unit = 10 cm, so 1 mm = 0.01 unit.

# ---- length ----
const MM_TO_M := 0.001
const CM_TO_M := 0.01
const IN_TO_M := 0.0254
const M_TO_SCENE := 10.0 # scene units per metre
const MM_TO_SCENE := 0.01

# ---- mass ----
const G_TO_KG := 0.001
const LB_TO_KG := 0.45359237

# ---- time ----
const MS_TO_S := 0.001
const MIN_TO_S := 60.0
const HOUR_TO_S := 3600.0

# ---- temperature ----
const C_TO_K_OFFSET := 273.15

# ---- pressure ----
const BAR_TO_PA := 100000.0
const KPA_TO_PA := 1000.0
const ATM_TO_PA := 101325.0
const PSI_TO_PA := 6894.757

# ---- energy and power ----
const KJ_TO_J := 1000.0
const MJ_TO_J := 1000000.0
const KWH_TO_J := 3600000.0
const LB_FT_TO_NM := 1.3558179
const PS_TO_KW := 0.7354988
const HP_TO_W := 745.7 # mechanical horsepower

# ---- volume ----
const CC_TO_M3 := 1.0e-6
const LITRE_TO_M3 := 0.001

# ---- physical constants ----
const GRAVITY := 9.81 # m/s²
const AIR_GAS_CONSTANT := 287.0 # J/(kg·K), dry air
const AIR_GAMMA := 1.4 # ratio of specific heats, air
const AIR_DENSITY := 1.2 # kg/m³ at about 20 °C and 1 atm
const ATMOSPHERE_PA := 101325.0
const AMBIENT_K := 300.0 # about 27 °C
const STEEL_DENSITY := 7800.0 # kg/m³
const PETROL_LHV := 44.0e6 # J/kg, lower heating value
const PETROL_AFR := 14.7 # stoichiometric air-fuel ratio by mass


# ---- conversions ----
static func c_to_k(celsius: float) -> float:
	return celsius + C_TO_K_OFFSET


static func k_to_c(kelvin: float) -> float:
	return kelvin - C_TO_K_OFFSET


static func rpm_to_rad_s(rpm: float) -> float:
	return rpm * TAU / 60.0


static func rad_s_to_rpm(rad_s: float) -> float:
	return rad_s * 60.0 / TAU


static func pa_to_psi(pa: float) -> float:
	return pa / PSI_TO_PA


static func w_to_hp(watts: float) -> float:
	return watts / HP_TO_W


static func kmh_to_ms(kmh: float) -> float:
	return kmh / 3.6


static func ms_to_kmh(ms: float) -> float:
	return ms * 3.6


# ---- calculations ----
# Swept volume of one cylinder, m³: π/4 · bore² · stroke. Bore and stroke in mm.
static func swept_volume_m3(bore_mm: float, stroke_mm: float) -> float:
	var bore := bore_mm * MM_TO_M
	return PI * 0.25 * bore * bore * stroke_mm * MM_TO_M


# Displacement of an n-cylinder engine, cc. Bore and stroke in mm.
static func displacement_cc(bore_mm: float, stroke_mm: float, cylinders: int) -> float:
	return swept_volume_m3(bore_mm, stroke_mm) * cylinders / CC_TO_M3


# Compression ratio from swept and clearance volumes.
static func compression_ratio(swept_m3: float, clearance_m3: float) -> float:
	return (swept_m3 + clearance_m3) / clearance_m3


# Ideal gas density, kg/m³, from pressure (Pa) and temperature (K).
static func gas_density(pressure_pa: float, temperature_k: float) -> float:
	return pressure_pa / (AIR_GAS_CONSTANT * temperature_k)


# Rotational kinetic energy ½·I·ω², J.
static func rotational_energy(inertia: float, rpm: float) -> float:
	var w := rpm_to_rad_s(rpm)
	return 0.5 * inertia * w * w


# Power from torque (N·m) and rpm, W.
static func power_w(torque_nm: float, rpm: float) -> float:
	return torque_nm * rpm_to_rad_s(rpm)


# Power in kW from torque (N·m) and rpm.
static func power_kw(torque_nm: float, rpm: float) -> float:
	return power_w(torque_nm, rpm) / 1000.0


# Fuel consumption in km per litre from speed (km/h) and fuel mass flow (g/s) and density (kg/m³).
static func km_per_litre(speed_kmh: float, fuel_g_s: float, density_kg_m3: float) -> float:
	var litres_per_hour := fuel_g_s / 1000.0 * HOUR_TO_S / (density_kg_m3 / 1000.0)
	return speed_kmh / litres_per_hour if litres_per_hour > 0.0 else 0.0
