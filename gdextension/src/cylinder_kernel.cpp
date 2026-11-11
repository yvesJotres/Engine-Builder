#include "cylinder_kernel.h"

#include <algorithm>
#include <cmath>

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// A line-for-line port of scripts/engine/cylinder.gd. Keep the two in step: when the GDScript changes, change this too, and
// run tests/unit/engine/cylinder_native_test.gd, which compares the two over a long run.
namespace {

constexpr double PI_ = 3.14159265358979323846;
constexpr double TAU_ = 2.0 * PI_;
constexpr double G = 1.4;
constexpr double R = 287.0;
constexpr double CV = R / (G - 1.0);
constexpr double CV_BURNT = 960.0;
constexpr double P0 = 101325.0;
constexpr double CD_VALVE = 0.7; // reference coefficient, valve_cd is scaled against it
// Discharge coefficient against L/D: low at small lift, rising to the knee (SAE 820154; SAE 962527). Mirrors cylinder.gd.
constexpr double CD_CURVE_LOW = 0.30;
constexpr double CD_CURVE_KNEE = 0.42;
constexpr double LD_KNEE = 0.25;
constexpr double COMBUSTION_EFFICIENCY = 0.95;
// gas/fuel ratio where partial burning starts, warm engine (Shayler et al., SAE 2000-01-1208). Mirrors cylinder.gd.
constexpr double MISFIRE_LAMBDA = 1.35; // too lean to light: fuel is not injected at all
constexpr double GAS_FUEL_MISFIRE = 24.0;
constexpr double BURN_DEG_BASE = 45.0;
constexpr double BURN_DEG_PER_RPM = 0.002;
constexpr double WIEBE_A = 6.908;
constexpr double WIEBE_M = 2.0;
// Woschni (1967, SAE 670931) gas-side heat transfer, SI form as in Heywood (see woschni_h)
constexpr double WOSCHNI_H = 3.26;
constexpr double WOSCHNI_C1 = 2.28;
constexpr double WOSCHNI_C1_GAS = 6.18;
constexpr double WOSCHNI_C2 = 0.00324;
constexpr double WALL_TEMP = 420.0;
constexpr double INTAKE_PORT_AREA = 2.0 * PI_ * 0.0125 * 0.0125;
constexpr double EXHAUST_PORT_AREA = 2.0 * PI_ * 0.0105 * 0.0105;
constexpr double RUNNER_AREA = 6.6e-4;
constexpr double PORT_VOLUME = 0.5e-4;
constexpr double RUNNER_LOSS = 1.5;
constexpr double MAX_FLOW_DT = 2.5e-4;
constexpr double OVERLAP_RETURN_BELOW = 0.9;
constexpr double AUTO_IGNITE_K = 900.0;
constexpr double BACKFIRE_BURN = 0.5;
constexpr int EXHAUST_FLOW_BINS = 90;
constexpr double FILM_DEPOSIT = 0.3; // share of the sprayed fuel that lands on the port wall, estimate
constexpr double FILM_EVAP_CYCLES = 3.0; // cycles for the port-wall film to evaporate, estimate
constexpr double CHECK_LIFT_M = 0.00127;
constexpr double LARGE_RUNNER_STEP_DEG = 1.0;
constexpr int PROFILE_HALF_SINE = 0;
constexpr int PROFILE_CUSTOM = 2;

inline double deg_to_rad(double d) { return d * (PI_ / 180.0); }
inline double clampf(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline double maxf(double a, double b) { return a > b ? a : b; }
// shortcut: flat above L/D 0.25; SAE 820154 says Cd falls at high lift, upgrade when a measured curve is available
inline double discharge_cd(double lift, double d) {
	double ld = lift / maxf(d, 1e-6);
	double t = clampf(ld / LD_KNEE, 0.0, 1.0);
	return CD_CURVE_LOW + (CD_CURVE_KNEE - CD_CURVE_LOW) * t;
}
inline double minf(double a, double b) { return a < b ? a : b; }
inline int maxi(int a, int b) { return a > b ? a : b; }
inline int mini(int a, int b) { return a < b ? a : b; }
inline int ceili(double v) { return (int)std::ceil(v); }
inline int floori(double v) { return (int)std::floor(v); }

// Godot's Math::fposmod
inline double fposmod(double x, double y) {
	double value = std::fmod(x, y);
	if ((value < 0 && y > 0) || (value > 0 && y < 0)) {
		value += y;
	}
	value += 0.0;
	return value;
}

inline int posmod(int a, int b) {
	int value = a % b;
	if ((value < 0 && b > 0) || (value > 0 && b < 0)) {
		value += b;
	}
	return value;
}

struct Cfg {
	double bore, piston_area, stroke, swept, clearance, recip_kg, rod_ratio;
	double intake_open, intake_close, exhaust_open, exhaust_close, intake_lift, exhaust_lift;
	double intake_valve_d, exhaust_valve_d, runner_length, wall_heat_scale, valve_cd, runner_area;
	int intake_profile, exhaust_profile;
	double intake_open_ramp, intake_close_ramp, exhaust_open_ramp, exhaust_close_ramp, intake_dur050, exhaust_dur050;
	const double *icurve;
	int icurve_pairs;
	const double *ecurve;
	int ecurve_pairs;
	double flow_step_deg;
	double tank_afr, tank_lhv;
};

struct Cyl {
	double phi, mass, temp, pressure, burn_energy_left, burn_energy, port_p, runner_q, exhaust_temp, peak_temp,
			last_peak_temp, last_lambda;
	bool fired;
		double intake_mdot;
	double fuel_unburnt_kg, port_heat, backfire_j, residual_kg, overlap_out, burnt, wall_loss_j, u, enthalpy_in_j,
			enthalpy_out_j, exhaust_mdot, exhaust_power, cycle_work, cycle_deg, cycle_peak_p, cycle_max_dp, cycle_p, ca10,
			ca50, ca90, last_imep, last_peak_pressure, last_dp_dtheta, last_ca10, last_ca50, last_ca90, last_burn_10_90,
			last_fresh_kg, last_ivc_temp, last_residual_fraction, tank_mass, film_kg;
	double ivc_p, ivc_v, ivc_t; // intake-closing state, the Woschni reference
	double residual_temp = 300.0; // K, the burnt gas left at exhaust closing: it is hot, not fresh charge
};

double curve_lift(const double *curve, int pairs, double deg) {
	if (pairs < 2) {
		return 0.0;
	}
	for (int i = 0; i < pairs - 1; i++) {
		double d1 = curve[2 * i];
		double d2 = curve[2 * (i + 1)];
		if (deg >= d1 && deg <= d2) {
			double span = d2 - d1;
			if (span <= 0.0) {
				return curve[2 * i + 1] * 0.001;
			}
			double t = (deg - d1) / span;
			double a = curve[2 * i + 1];
			double b = curve[2 * (i + 1) + 1];
			return (a + (b - a) * t) * 0.001;
		}
	}
	return 0.0;
}

// EngineSpec.seat_ramps
// The GDScript returns a Vector2, which holds 32-bit floats, so the ramp lengths are rounded to float there. Do the same here
// or the lifts differ in the 7th digit and the two paths drift apart.
inline void seat_ramps(double seat_deg, double duration_050, double open_ramp, double close_ramp, double &rx, double &ry) {
	if (open_ramp > 0.0 || close_ramp > 0.0) {
		double opening = open_ramp > 0.0 ? open_ramp : close_ramp;
		double closing = close_ramp > 0.0 ? close_ramp : open_ramp;
		double cap = seat_deg * 0.45;
		rx = (double)(float)minf(opening, cap);
		ry = (double)(float)minf(closing, cap);
		return;
	}
	double at_050 = duration_050 > 0.0 ? duration_050 : seat_deg / 1.14;
	at_050 = clampf(at_050, seat_deg * 0.5, seat_deg);
	double ramp = (double)(float)((seat_deg - at_050) * 0.5);
	rx = ramp;
	ry = ramp;
}

double lobe_lift(double phi_deg, double open_deg, double close_deg, double peak_m, int profile, const double *curve,
		int curve_pairs, double open_ramp, double close_ramp, double duration_050) {
	double p = fposmod(phi_deg, 720.0);
	if (profile == PROFILE_CUSTOM) {
		return curve_lift(curve, curve_pairs, p);
	}
	if (p < open_deg || p > close_deg || close_deg <= open_deg || peak_m <= 0.0) {
		return 0.0;
	}
	double seat = close_deg - open_deg;
	if (profile == PROFILE_HALF_SINE) {
		return peak_m * std::sin(PI_ * (p - open_deg) / seat);
	}
	double rx, ry;
	seat_ramps(seat, duration_050, open_ramp, close_ramp, rx, ry);
	double check_open = open_deg + rx;
	double check_close = close_deg - ry;
	double check_m = minf(CHECK_LIFT_M, peak_m * 0.5);
	if (rx > 0.05 && p < check_open) {
		return check_m * (p - open_deg) / rx;
	}
	if (ry > 0.05 && p > check_close) {
		return check_m * (close_deg - p) / ry;
	}
	double half = maxf((check_close - check_open) * 0.5, 0.5);
	double centre = (check_open + check_close) * 0.5;
	double cos_arg = clampf(2.0 * check_m / peak_m - 1.0, -1.0, 1.0);
	double omega = std::acos(cos_arg) / half;
	return peak_m * 0.5 * (std::cos(omega * (p - centre)) + 1.0);
}

inline double intake_lift_at(const Cfg &c, double phase) {
	return lobe_lift(phase, c.intake_open, c.intake_close, c.intake_lift, c.intake_profile, c.icurve, c.icurve_pairs,
			c.intake_open_ramp, c.intake_close_ramp, c.intake_dur050);
}

inline double exhaust_lift_at(const Cfg &c, double phase) {
	return lobe_lift(phase, c.exhaust_open, c.exhaust_close, c.exhaust_lift, c.exhaust_profile, c.ecurve, c.ecurve_pairs,
			c.exhaust_open_ramp, c.exhaust_close_ramp, c.exhaust_dur050);
}

inline double exhaust_valve_area(const Cfg &c, double phase) {
	double lift_m = exhaust_lift_at(c, phase);
	return minf(2.0 * PI_ * c.exhaust_valve_d * lift_m, 0.5 * PI_ * c.exhaust_valve_d * c.exhaust_valve_d);
}

inline double intake_area(const Cfg &c, double phase) {
	double lift_m = intake_lift_at(c, phase);
	return minf(2.0 * PI_ * c.intake_valve_d * lift_m, 0.5 * PI_ * c.intake_valve_d * c.intake_valve_d);
}

double subsonic(double area, double p_up, double t_up, double p_down) {
	double pr = p_down / p_up;
	double k = CD_VALVE * area * p_up / std::sqrt(R * t_up);
	double crit = std::pow(2.0 / (G + 1.0), G / (G - 1.0));
	if (pr <= crit) {
		return k * std::sqrt(G * std::pow(2.0 / (G + 1.0), (G + 1.0) / (G - 1.0)));
	}
	return k * std::sqrt(2.0 * G / (G - 1.0) * (std::pow(pr, 2.0 / G) - std::pow(pr, (G + 1.0) / G)));
}

inline double mass_flow(double area, double p1, double t1, double p2, double t2) {
	if (area <= 0.0) {
		return 0.0;
	}
	if (p1 >= p2) {
		return subsonic(area, p1, t1, p2);
	}
	return -subsonic(area, p2, t2, p1);
}

// Woschni (1967) gas-side heat transfer coefficient, W/(m²·K), mirrors woschni_h in scripts/engine/cylinder.gd.
// Gas speed w = C1 Sp + C2 (Vd Tr)/(pr Vr) (p - p0); p0 is the motored pressure, isentropic from intake closing.
inline double woschni_h(const Cfg &c, const Cyl &y, double w_rad, double v, bool burning, bool gas_exchange) {
	const double sp = c.stroke * w_rad / PI_; // mean piston speed, m/s
	double gas_speed = (gas_exchange ? WOSCHNI_C1_GAS : WOSCHNI_C1) * sp;
	if (burning && !gas_exchange && y.ivc_v > 0.0) {
		const double p0 = y.ivc_p * std::pow(y.ivc_v / v, G);
		gas_speed += WOSCHNI_C2 * c.swept * y.ivc_t / (y.ivc_p * y.ivc_v) * (y.pressure - p0);
	}
	return WOSCHNI_H * std::pow(c.bore, -0.2) * std::pow(y.pressure / 1000.0, 0.8) * std::pow(y.temp, -0.55) * std::pow(maxf(gas_speed, 1.0), 0.8);
}

inline double volume_at(const Cfg &c, double phi_deg) {
	double angle = deg_to_rad(phi_deg);
	double crank_radius = c.stroke * 0.5;
	double rod_length = c.rod_ratio * crank_radius;
	double crank_offset = crank_radius * std::sin(angle);
	double displacement = crank_radius * (1.0 - std::cos(angle)) + rod_length -
			std::sqrt(rod_length * rod_length - crank_offset * crank_offset);
	return c.clearance + c.piston_area * displacement;
}

int flow_steps(const Cfg &c, const Cyl &y, double dphi, double dt, double pm, double tm, double p_ex, double t_ex) {
	double max_deg = c.runner_area > RUNNER_AREA ? minf(c.flow_step_deg, LARGE_RUNNER_STEP_DEG) : c.flow_step_deg;
	int steps = maxi(1, maxi(ceili(std::fabs(dphi) / max_deg), ceili(dt / MAX_FLOW_DT)));
	if (dt <= 0.0 || y.mass < 1e-7) {
		return steps;
	}
	double mid = y.phi + dphi * 0.5;
	double end = y.phi + dphi;
	double cd = c.valve_cd / CD_VALVE;
	double ex_area = maxf(exhaust_valve_area(c, y.phi), maxf(exhaust_valve_area(c, mid), exhaust_valve_area(c, end))) * cd;
	double in_area = maxf(intake_area(c, y.phi), maxf(intake_area(c, mid), intake_area(c, end))) * cd;
	int finer = steps;
	double mdot = std::fabs(mass_flow(ex_area, maxf(y.pressure, p_ex), maxf(y.temp, 250.0), minf(y.pressure, p_ex), t_ex));
	mdot = maxf(mdot, std::fabs(mass_flow(in_area, maxf(y.port_p, pm), maxf(tm, 250.0), minf(y.pressure, pm), y.temp)));
	double cap = 0.1 * y.mass;
	if (mdot * dt > cap * (double)finer) {
		finer = maxi(finer, ceili(mdot * dt / cap));
	}
	double opening = maxf(ex_area, in_area);
	if (opening > 0.0) {
		double vol = y.mass * R * maxf(y.temp, 250.0) / maxf(y.pressure, 1000.0);
		double wave = std::sqrt(G * R * maxf(y.temp, 250.0));
		double dt_ok = 0.2 * vol / (opening * wave);
		if (dt_ok > 0.0) {
			finer = maxi(finer, ceili(dt / dt_ok));
		}
	}
	return mini(finer, maxi(steps, 24));
}

inline bool crossed(double a, double b, double at) {
	return std::floor((b - at) / 720.0) > std::floor((a - at) / 720.0);
}

inline bool in_window(double p, double start, double length) {
	double rel = std::fmod(p - start + 720.0, 720.0);
	return rel < length;
}

inline double burn_duration_deg(double rpm) { return BURN_DEG_BASE + BURN_DEG_PER_RPM * rpm; }

inline double wiebe(double rel, double burn_deg) {
	return 1.0 - std::exp(-WIEBE_A * std::pow(clampf(rel / burn_deg, 0.0, 1.0), WIEBE_M + 1.0));
}

void close_cycle(const Cfg &c, Cyl &y) {
	if (y.cycle_deg >= 400.0 && c.swept > 0.0) {
		y.last_imep = y.cycle_work / c.swept;
		y.last_peak_pressure = y.cycle_peak_p;
		y.last_dp_dtheta = y.cycle_max_dp;
		y.last_ca10 = y.ca10 >= 0.0 ? fposmod(y.ca10, 720.0) : -1.0;
		y.last_ca50 = y.ca50 >= 0.0 ? fposmod(y.ca50, 720.0) : -1.0;
		y.last_ca90 = y.ca90 >= 0.0 ? fposmod(y.ca90, 720.0) : -1.0;
		y.last_burn_10_90 = (y.ca10 >= 0.0 && y.ca90 >= y.ca10) ? y.ca90 - y.ca10 : 0.0;
	}
	y.cycle_work = 0.0;
	y.cycle_deg = 0.0;
	y.cycle_peak_p = 0.0;
	y.cycle_max_dp = 0.0;
	y.ca10 = -1.0;
	y.ca50 = -1.0;
	y.ca90 = -1.0;
}

void fuel_charge(const Cfg &c, Cyl &y, double lambda, bool spark, bool limiter_cut, double pm) {
	double trapped = y.mass;
	double came_back = 0.0;
	if (pm < P0 * OVERLAP_RETURN_BELOW) {
		came_back = minf(y.overlap_out, maxf(trapped - y.residual_kg, 0.0));
	}
	y.overlap_out = 0.0;
	y.last_fresh_kg = maxf(trapped - y.residual_kg - came_back, 0.0);
	y.last_ivc_temp = y.temp;
	y.last_residual_fraction = (y.residual_kg + came_back) / maxf(trapped, 1.0e-12);
	y.burn_energy = 0.0;
	y.burn_energy_left = 0.0;
	y.last_lambda = 1.0;
	if (limiter_cut) {
		return;
	}
	if (lambda >= MISFIRE_LAMBDA) {
		return; // too lean to light
	}
	double fresh = y.last_fresh_kg;
	double wanted = fresh / (c.tank_afr * lambda);
	bool lit = (bool)spark;
	double sprayed = minf(wanted, y.tank_mass);
	y.tank_mass -= sprayed;
	double evap = y.film_kg / FILM_EVAP_CYCLES;
	y.film_kg += FILM_DEPOSIT * sprayed - evap;
	double supplied = (1.0 - FILM_DEPOSIT) * sprayed + evap;
	y.mass += supplied;
	y.u += supplied * CV * y.temp;
	// The residual is burnt gas at exhaust temperature, not cold air. Mixing the charge at one temperature charges the
	// residual to the fresh gas temperature, so at intake closing the chamber reads far colder (and so far denser) than it
	// really is. That error is small at a steady idle and lethal on the first cycles of a start, which then read too lean to
	// light. Put the residual's own enthalpy back into the mixed state (air-gas mixture of the same heat capacity).
	{
		const double mixed = y.mass; // fuel already added above, as in cylinder.gd _fuel_charge
		if (mixed > 1.0e-12) {
			const double air_before = maxf(mixed - y.residual_kg, 0.0);
			const double held = air_before * y.temp + y.residual_kg * y.residual_temp;
			const double fixed = held / mixed;
			y.u += mixed * CV * (fixed - y.temp);
			y.temp = std::min(std::max(fixed, 200.0), 4000.0);
		}
	}
	if (!lit) {
		y.fuel_unburnt_kg = supplied;
		return;
	}
	y.fuel_unburnt_kg = 0.0;
	if (supplied > 0.0) {
		y.last_lambda = fresh / (c.tank_afr * supplied);
	}
	double burnable = minf(supplied, fresh / c.tank_afr);
	y.burn_energy = burnable * c.tank_lhv * COMBUSTION_EFFICIENCY;
	y.burn_energy_left = y.burn_energy;
	y.fired = supplied > 0.0;
}

void load(const double *s, Cyl &y) {
	y.phi = s[CylinderKernel::S_PHI];
	y.mass = s[CylinderKernel::S_MASS];
	y.temp = s[CylinderKernel::S_TEMP];
	y.pressure = s[CylinderKernel::S_PRESSURE];
	y.burn_energy_left = s[CylinderKernel::S_BURN_ENERGY_LEFT];
	y.burn_energy = s[CylinderKernel::S_BURN_ENERGY];
	y.port_p = s[CylinderKernel::S_PORT_P];
	y.runner_q = s[CylinderKernel::S_RUNNER_Q];
	y.intake_mdot = s[CylinderKernel::S_INTAKE_MDOT];
	y.exhaust_temp = s[CylinderKernel::S_EXHAUST_TEMP];
	y.peak_temp = s[CylinderKernel::S_PEAK_TEMP];
	y.last_peak_temp = s[CylinderKernel::S_LAST_PEAK_TEMP];
	y.last_lambda = s[CylinderKernel::S_LAST_LAMBDA];
	y.fired = s[CylinderKernel::S_FIRED] != 0.0;
	y.fuel_unburnt_kg = s[CylinderKernel::S_FUEL_UNBURNT_KG];
	y.port_heat = s[CylinderKernel::S_PORT_HEAT];
	y.backfire_j = s[CylinderKernel::S_BACKFIRE_J];
	y.residual_kg = s[CylinderKernel::S_RESIDUAL_KG];
	y.film_kg = s[CylinderKernel::S_FILM_KG];
	y.overlap_out = s[CylinderKernel::S_OVERLAP_OUT];
	y.burnt = s[CylinderKernel::S_BURNT];
	y.wall_loss_j = s[CylinderKernel::S_WALL_LOSS_J];
	y.u = s[CylinderKernel::S_U];
	y.enthalpy_in_j = s[CylinderKernel::S_ENTHALPY_IN_J];
	y.enthalpy_out_j = s[CylinderKernel::S_ENTHALPY_OUT_J];
	y.exhaust_mdot = s[CylinderKernel::S_EXHAUST_MDOT];
	y.exhaust_power = s[CylinderKernel::S_EXHAUST_POWER];
	y.cycle_work = s[CylinderKernel::S_CYCLE_WORK];
	y.cycle_deg = s[CylinderKernel::S_CYCLE_DEG];
	y.cycle_peak_p = s[CylinderKernel::S_CYCLE_PEAK_P];
	y.cycle_max_dp = s[CylinderKernel::S_CYCLE_MAX_DP];
	y.cycle_p = s[CylinderKernel::S_CYCLE_P];
	y.ca10 = s[CylinderKernel::S_CA10];
	y.ca50 = s[CylinderKernel::S_CA50];
	y.ca90 = s[CylinderKernel::S_CA90];
	y.last_imep = s[CylinderKernel::S_LAST_IMEP];
	y.last_peak_pressure = s[CylinderKernel::S_LAST_PEAK_PRESSURE];
	y.last_dp_dtheta = s[CylinderKernel::S_LAST_DP_DTHETA];
	y.last_ca10 = s[CylinderKernel::S_LAST_CA10];
	y.last_ca50 = s[CylinderKernel::S_LAST_CA50];
	y.last_ca90 = s[CylinderKernel::S_LAST_CA90];
	y.last_burn_10_90 = s[CylinderKernel::S_LAST_BURN_10_90];
	y.last_fresh_kg = s[CylinderKernel::S_LAST_FRESH_KG];
	y.last_ivc_temp = s[CylinderKernel::S_LAST_IVC_TEMP];
	y.ivc_p = s[CylinderKernel::S_IVC_P];
	y.ivc_v = s[CylinderKernel::S_IVC_V];
	y.ivc_t = s[CylinderKernel::S_IVC_T];
	y.residual_temp = s[CylinderKernel::S_RESIDUAL_TEMP];
	y.last_residual_fraction = s[CylinderKernel::S_LAST_RESIDUAL_FRACTION];
	y.tank_mass = s[CylinderKernel::S_TANK_MASS];
}

void store(double *s, const Cyl &y) {
	s[CylinderKernel::S_PHI] = y.phi;
	s[CylinderKernel::S_MASS] = y.mass;
	s[CylinderKernel::S_TEMP] = y.temp;
	s[CylinderKernel::S_PRESSURE] = y.pressure;
	s[CylinderKernel::S_BURN_ENERGY_LEFT] = y.burn_energy_left;
	s[CylinderKernel::S_BURN_ENERGY] = y.burn_energy;
	s[CylinderKernel::S_PORT_P] = y.port_p;
	s[CylinderKernel::S_RUNNER_Q] = y.runner_q;
	s[CylinderKernel::S_INTAKE_MDOT] = y.intake_mdot;
	s[CylinderKernel::S_EXHAUST_TEMP] = y.exhaust_temp;
	s[CylinderKernel::S_PEAK_TEMP] = y.peak_temp;
	s[CylinderKernel::S_LAST_PEAK_TEMP] = y.last_peak_temp;
	s[CylinderKernel::S_LAST_LAMBDA] = y.last_lambda;
	s[CylinderKernel::S_FIRED] = y.fired ? 1.0 : 0.0;
	s[CylinderKernel::S_FUEL_UNBURNT_KG] = y.fuel_unburnt_kg;
	s[CylinderKernel::S_PORT_HEAT] = y.port_heat;
	s[CylinderKernel::S_BACKFIRE_J] = y.backfire_j;
	s[CylinderKernel::S_RESIDUAL_KG] = y.residual_kg;
	s[CylinderKernel::S_FILM_KG] = y.film_kg;
	s[CylinderKernel::S_OVERLAP_OUT] = y.overlap_out;
	s[CylinderKernel::S_BURNT] = y.burnt;
	s[CylinderKernel::S_WALL_LOSS_J] = y.wall_loss_j;
	s[CylinderKernel::S_U] = y.u;
	s[CylinderKernel::S_ENTHALPY_IN_J] = y.enthalpy_in_j;
	s[CylinderKernel::S_ENTHALPY_OUT_J] = y.enthalpy_out_j;
	s[CylinderKernel::S_EXHAUST_MDOT] = y.exhaust_mdot;
	s[CylinderKernel::S_EXHAUST_POWER] = y.exhaust_power;
	s[CylinderKernel::S_CYCLE_WORK] = y.cycle_work;
	s[CylinderKernel::S_CYCLE_DEG] = y.cycle_deg;
	s[CylinderKernel::S_CYCLE_PEAK_P] = y.cycle_peak_p;
	s[CylinderKernel::S_CYCLE_MAX_DP] = y.cycle_max_dp;
	s[CylinderKernel::S_CYCLE_P] = y.cycle_p;
	s[CylinderKernel::S_CA10] = y.ca10;
	s[CylinderKernel::S_CA50] = y.ca50;
	s[CylinderKernel::S_CA90] = y.ca90;
	s[CylinderKernel::S_LAST_IMEP] = y.last_imep;
	s[CylinderKernel::S_LAST_PEAK_PRESSURE] = y.last_peak_pressure;
	s[CylinderKernel::S_LAST_DP_DTHETA] = y.last_dp_dtheta;
	s[CylinderKernel::S_LAST_CA10] = y.last_ca10;
	s[CylinderKernel::S_LAST_CA50] = y.last_ca50;
	s[CylinderKernel::S_LAST_CA90] = y.last_ca90;
	s[CylinderKernel::S_LAST_BURN_10_90] = y.last_burn_10_90;
	s[CylinderKernel::S_LAST_FRESH_KG] = y.last_fresh_kg;
	s[CylinderKernel::S_LAST_IVC_TEMP] = y.last_ivc_temp;
	s[CylinderKernel::S_IVC_P] = y.ivc_p;
	s[CylinderKernel::S_IVC_V] = y.ivc_v;
	s[CylinderKernel::S_IVC_T] = y.ivc_t;
	s[CylinderKernel::S_RESIDUAL_TEMP] = y.residual_temp;
	s[CylinderKernel::S_LAST_RESIDUAL_FRACTION] = y.last_residual_fraction;
	s[CylinderKernel::S_TANK_MASS] = y.tank_mass;
}

} // namespace

void CylinderKernel::_bind_methods() {
	ClassDB::bind_static_method("CylinderKernel",
			D_METHOD("advance", "state", "cfg", "icurve", "ecurve", "dphi", "dt", "pm", "tm", "ign_phi", "firing", "tank_afr",
					"tank_lhv", "lambda", "spark", "limiter_cut", "p_ex", "t_ex", "flow_step_deg"),
			&CylinderKernel::advance);
	ClassDB::bind_static_method("CylinderKernel", D_METHOD("state_size"), &CylinderKernel::state_size);
	ClassDB::bind_static_method("CylinderKernel", D_METHOD("config_size"), &CylinderKernel::config_size);
}

PackedFloat64Array CylinderKernel::advance(PackedFloat64Array state, const PackedFloat64Array &cfg,
		const PackedFloat64Array &icurve, const PackedFloat64Array &ecurve, double dphi, double dt, double pm, double tm,
		double ign_phi, bool firing, double tank_afr, double tank_lhv, double lambda, bool spark, bool limiter_cut,
		double p_ex, double t_ex, double flow_step_deg) {
	if (state.size() < S_SIZE || cfg.size() < C_RUNNER_AREA) {
		return state;
	}
	const double *k = cfg.ptr();
	Cfg c;
	c.bore = k[C_BORE];
	c.piston_area = k[C_PISTON_AREA];
	c.stroke = k[C_STROKE];
	c.swept = k[C_SWEPT];
	c.clearance = k[C_CLEARANCE];
	c.recip_kg = k[C_RECIP_KG];
	c.rod_ratio = k[C_ROD_RATIO];
	c.intake_open = k[C_INTAKE_OPEN];
	c.intake_close = k[C_INTAKE_CLOSE];
	c.exhaust_open = k[C_EXHAUST_OPEN];
	c.exhaust_close = k[C_EXHAUST_CLOSE];
	c.intake_lift = k[C_INTAKE_LIFT];
	c.exhaust_lift = k[C_EXHAUST_LIFT];
	c.intake_valve_d = k[C_INTAKE_VALVE_D];
	c.exhaust_valve_d = k[C_EXHAUST_VALVE_D];
	c.runner_length = k[C_RUNNER_LENGTH];
	c.runner_area = cfg.size() > C_RUNNER_AREA ? k[C_RUNNER_AREA] : RUNNER_AREA;
	c.wall_heat_scale = k[C_WALL_HEAT_SCALE];
	c.valve_cd = k[C_VALVE_CD];
	c.intake_profile = (int)k[C_INTAKE_PROFILE];
	c.exhaust_profile = (int)k[C_EXHAUST_PROFILE];
	c.intake_open_ramp = k[C_INTAKE_OPEN_RAMP];
	c.intake_close_ramp = k[C_INTAKE_CLOSE_RAMP];
	c.exhaust_open_ramp = k[C_EXHAUST_OPEN_RAMP];
	c.exhaust_close_ramp = k[C_EXHAUST_CLOSE_RAMP];
	c.intake_dur050 = k[C_INTAKE_DURATION_050];
	c.exhaust_dur050 = k[C_EXHAUST_DURATION_050];
	c.icurve = icurve.ptr();
	c.icurve_pairs = (int)(icurve.size() / 2);
	c.ecurve = ecurve.ptr();
	c.ecurve_pairs = (int)(ecurve.size() / 2);
	c.flow_step_deg = flow_step_deg;
	c.tank_afr = tank_afr;
	c.tank_lhv = tank_lhv;

	double *s = state.ptrw();
	Cyl y;
	load(s, y);

	const int steps = flow_steps(c, y, dphi, dt, pm, tm, p_ex, t_ex);
	const double sd = dphi / steps;
	const double sdt = dt / steps;
	double work = 0.0;
	double theta = 0.0;
	double drawn = 0.0;
	const double w = dt > 0.0 ? deg_to_rad(dphi) / dt : 0.0;
	const double crank_r = c.stroke * 0.5;
	const double burn_deg = burn_duration_deg(w * 60.0 / TAU_);
	double previous_volume = volume_at(c, y.phi);
	double ex_mass = 0.0;
	double ex_energy = 0.0;
	for (int i = 0; i < steps; i++) {
		double p0 = y.phi;
		double p1 = y.phi + sd;
		double next_volume = volume_at(c, p1);
		double dv = next_volume - previous_volume;
		if (crossed(p0, p1, c.intake_open)) {
			close_cycle(c, y);
			y.last_peak_temp = y.peak_temp;
			y.peak_temp = y.temp;
			y.burnt = 0.0;
		}

		double v_run = y.runner_q / (c.runner_area * 1.2);
		double drag = 0.5 * RUNNER_LOSS * 1.2 * v_run * std::fabs(v_run);
		// fresh air through the intake port loses its dynamic pressure, as the runner does, lagged from the last step
		double port_v = maxf(y.intake_mdot, 0.0) / (1.2 * INTAKE_PORT_AREA);
		double port_loss = 0.5 * RUNNER_LOSS * 1.2 * port_v * port_v;
		double intake_lift_now = intake_lift_at(c, p0);
		double m_in = mass_flow(minf(2.0 * PI_ * c.intake_valve_d * intake_lift_now, 0.5 * PI_ * c.intake_valve_d * c.intake_valve_d) * c.valve_cd * discharge_cd(intake_lift_now, c.intake_valve_d) / (CD_VALVE * CD_VALVE),
							  y.port_p - port_loss, tm, y.pressure, y.temp) *
				sdt;
		if (sdt > 0.0) {
			y.intake_mdot = m_in / sdt;
		}
		double exhaust_lift_now = exhaust_lift_at(c, p0);
		if (m_in < 0.0 && exhaust_lift_now > 0.0) {
			y.overlap_out -= m_in;
		}
		// Solve runner inertia and port pressure together, as in cylinder.gd.
		double air_a = c.runner_area / c.runner_length * sdt;
		double port_c = R * tm / PORT_VOLUME;
		double k = port_c * air_a * sdt;
		double dp = (port_c * sdt * y.runner_q + k * (pm - y.port_p - drag) - port_c * m_in) / (1.0 + k);
		y.runner_q += air_a * (pm - y.port_p - drag - dp);
		y.port_p = clampf(y.port_p + dp, 1000.0, 3.0 * P0);
		double m_out = mass_flow(minf(2.0 * PI_ * c.exhaust_valve_d * exhaust_lift_now, 0.5 * PI_ * c.exhaust_valve_d * c.exhaust_valve_d) * c.valve_cd * discharge_cd(exhaust_lift_now, c.exhaust_valve_d) / (CD_VALVE * CD_VALVE),
							   y.pressure, y.temp, p_ex, t_ex) *
				sdt;
		if (sdt > 0.0) {
			int first_bin = floori(p0 * EXHAUST_FLOW_BINS / 720.0);
			int last_bin = floori(p1 * EXHAUST_FLOW_BINS / 720.0);
			for (int bin_index = first_bin; bin_index <= last_bin; bin_index++) {
				// stored as a 32-bit float, as the GDScript PackedFloat32Array does
				s[S_BINS + posmod(bin_index, EXHAUST_FLOW_BINS)] = (double)(float)(m_out / sdt);
			}
		}

		if (crossed(p0, p1, c.exhaust_open)) {
			if (y.fuel_unburnt_kg > 0.0) {
				if (y.port_heat > AUTO_IGNITE_K) {
					y.backfire_j += y.fuel_unburnt_kg * c.tank_lhv * BACKFIRE_BURN;
				}
				y.port_heat = 300.0; // T0
			}
			y.fuel_unburnt_kg = 0.0;
		}
		if (y.fired && crossed(p0, p1, c.exhaust_open)) {
			y.exhaust_temp = y.temp;
			y.port_heat = y.temp;
		}
		if (crossed(p0, p1, c.exhaust_close)) {
			y.residual_kg = y.mass;
			// The gas left at exhaust closing is burnt products, not air, and it is hot. Carry its temperature, or the
			// residual is later counted as cold fresh charge and the first cycles of a start read far too lean to light.
			y.residual_temp = y.temp;
		}

		if (crossed(p0, p1, c.intake_close)) {
			y.ivc_p = y.pressure;
			y.ivc_v = next_volume;
			y.ivc_t = y.temp;
			y.fired = false;
			if (firing) {
				fuel_charge(c, y, lambda, spark, limiter_cut, pm);
			} else {
				y.overlap_out = 0.0;
			}
		}

		double dq = 0.0;
		if (spark && y.burn_energy_left > 0.0 && in_window(p0, ign_phi, burn_deg)) {
			double rel = std::fmod(p0 - ign_phi + 720.0, 720.0);
			dq = minf(y.burn_energy_left, y.burn_energy * (wiebe(rel + sd, burn_deg) - wiebe(rel, burn_deg)));
			y.burn_energy_left -= dq;
			y.burnt = 1.0 - y.burn_energy_left / y.burn_energy;
		} else if (!spark && y.burn_energy_left > 0.0 && in_window(p0, ign_phi, burn_deg)) {
			// the spark was cut after this charge got its fuel: the fuel never burns, and it leaves unlit into the exhaust, where it pops
			y.fuel_unburnt_kg += y.burn_energy_left / (c.tank_lhv * COMBUSTION_EFFICIENCY);
			y.burn_energy_left = 0.0;
		}

		double liner = (next_volume - c.clearance) / c.piston_area;
		double wall_area = 2.0 * c.piston_area + PI_ * c.bore * maxf(liner, 0.0);
		const bool gas_exchange = in_window(p0, c.intake_open, c.intake_close - c.intake_open) || in_window(p0, c.exhaust_open, c.exhaust_close - c.exhaust_open);
		const double h_wall = woschni_h(c, y, w, next_volume, y.burnt > 0.0, gas_exchange);
		double q_loss = h_wall * wall_area * (y.temp - WALL_TEMP) * sdt;
		y.wall_loss_j += q_loss;

		double cv = CV + y.burnt * (CV_BURNT - CV);
		double cp = cv + R;
		double h_in = cp * (m_in >= 0.0 ? tm : y.temp) * m_in;
		y.enthalpy_in_j += h_in;
		double h_ex = cp * (m_out >= 0.0 ? y.temp : t_ex) * m_out;
		y.enthalpy_out_j += h_ex;
		ex_mass += m_out;
		ex_energy += h_ex;
		double old_pressure = y.pressure;
		double source_energy = y.u + dq + h_in - h_ex - q_loss;
		double u = (source_energy - 0.5 * old_pressure * dv) / (1.0 + 0.5 * R / cv * dv / next_volume);
		y.mass = maxf(y.mass + m_in - m_out, 1e-12);
		y.temp = clampf(u / (y.mass * cv), 200.0, 4000.0);
		y.u = y.mass * cv * y.temp;
		y.peak_temp = maxf(y.peak_temp, y.temp);
		y.pressure = clampf(y.mass * R * y.temp / next_volume, 1000.0, 1.0e7);
		if (sd > 0.0 && y.cycle_deg > 0.0) {
			y.cycle_max_dp = maxf(y.cycle_max_dp, (y.pressure - y.cycle_p) / sd);
		}
		y.cycle_p = y.pressure;
		y.cycle_peak_p = maxf(y.cycle_peak_p, y.pressure);
		double boundary_work = 0.5 * (old_pressure + y.pressure) * dv;
		y.cycle_work += boundary_work;
		y.cycle_deg += sd;
		if (y.ca10 < 0.0 && y.burnt >= 0.1) {
			y.ca10 = p1;
		}
		if (y.ca50 < 0.0 && y.burnt >= 0.5) {
			y.ca50 = p1;
		}
		if (y.ca90 < 0.0 && y.burnt >= 0.9) {
			y.ca90 = p1;
		}

		double dtheta = sd * PI_ / 180.0;
		work += boundary_work - P0 * dv;
		double phi_r = deg_to_rad(p0);
		double accel_term = std::cos(phi_r) + std::cos(2.0 * phi_r) / c.rod_ratio;
		work += -c.recip_kg * crank_r * crank_r * w * w * accel_term * std::sin(phi_r) * dtheta;
		theta += dtheta;
		drawn += y.runner_q * sdt;
		y.phi = p1;
		previous_volume = next_volume;
	}
	y.exhaust_mdot = dt > 0.0 ? ex_mass / dt : 0.0;
	y.exhaust_power = dt > 0.0 ? ex_energy / dt : 0.0;
	store(s, y);
	s[S_OUT_TORQUE] = theta > 0.0 ? work / theta : 0.0;
	s[S_OUT_DRAWN] = drawn;
	return state;
}
