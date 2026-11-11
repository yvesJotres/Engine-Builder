#include "two_stroke_kernel.h"

#include <cmath>

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// A line-for-line port of TwoStrokeCylinder.advance in scripts/engine/two_stroke_cylinder.gd. Keep the two in step: when the
// GDScript changes, change this too, and run tests/unit/engine/two_stroke_native_test.gd.
namespace {

constexpr double PI_ = 3.14159265358979323846;
constexpr double G = 1.4;
constexpr double R = 287.0;
constexpr double CV = R / (G - 1.0);
constexpr double CP = G * R / (G - 1.0);
constexpr double P0 = 101325.0;
constexpr double T0 = 300.0;
constexpr double CD_PORT = 0.7; // discharge coefficient for port flow
constexpr double COMBUSTION_EFFICIENCY = 0.93;
constexpr double MISFIRE_LAMBDA = 1.3;
constexpr double BURN_DEG_BASE = 35.0;
constexpr double BURN_DEG_PER_RPM = 0.0015;
constexpr double WIEBE_A = 6.908;
constexpr double WIEBE_M = 2.0;
constexpr double STEP_DEG = 5.0; // finer step for 2-stroke (360 deg cycle)
constexpr double WALL_HEAT = 1200.0; // higher heat transfer (more frequent combustion)
constexpr double WALL_REF_W = 314.0;
constexpr double WALL_TEMP = 450.0;

inline double deg_to_rad(double d) { return d * (PI_ / 180.0); }
inline double clampf(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline double maxf(double a, double b) { return a > b ? a : b; }
inline double minf(double a, double b) { return a < b ? a : b; }
inline int maxi(int a, int b) { return a > b ? a : b; }
inline int ceili(double v) { return (int)std::ceil(v); }

// Godot's Math::fposmod
inline double fposmod(double x, double y) {
	double value = std::fmod(x, y);
	if ((value < 0 && y > 0) || (value > 0 && y < 0)) {
		value += y;
	}
	value += 0.0;
	return value;
}

struct Cfg {
	double bore, piston_area, stroke, swept, clearance, recip_kg, rod_ratio;
	double transfer_open, transfer_close, exhaust_open, exhaust_close, intake_open, intake_close;
	double transfer_area, exhaust_area, intake_area, crankcase_volume, oil_ratio;
	int intake_type;
	double crank_radius;
	double tank_afr, tank_lhv;
};

double subsonic(double area, double p_up, double t_up, double p_down) {
	double pr = p_down / p_up;
	double k = CD_PORT * area * p_up / std::sqrt(R * t_up);
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

inline double displacement_at(const Cfg &c, double phi_deg) {
	double angle = deg_to_rad(phi_deg);
	double crank_radius = c.stroke * 0.5;
	double rod_length = c.rod_ratio * crank_radius;
	double crank_offset = crank_radius * std::sin(angle);
	return crank_radius * (1.0 - std::cos(angle)) + rod_length - std::sqrt(rod_length * rod_length - crank_offset * crank_offset);
}

inline double volume_at(const Cfg &c, double phi_deg) { return c.clearance + c.piston_area * displacement_at(c, phi_deg); }

// Crankcase volume is max at TDC, min at BDC (opposite of cylinder)
inline double crankcase_vol(const Cfg &c, double phi_deg) { return c.crankcase_volume - c.piston_area * displacement_at(c, phi_deg); }

inline double transfer_port_area(const Cfg &c, double phase_deg) {
	double p = fposmod(phase_deg, 360.0);
	if (p >= c.transfer_open && p <= c.transfer_close) {
		return c.transfer_area;
	}
	return 0.0;
}

inline double exhaust_port_area(const Cfg &c, double phase_deg) {
	double p = fposmod(phase_deg, 360.0);
	if (p >= c.exhaust_open && p <= c.exhaust_close) {
		return c.exhaust_area;
	}
	return 0.0;
}

inline double intake_port_area(const Cfg &c, double phase_deg) {
	if (c.intake_area <= 0.0) {
		return 0.0;
	}
	double p = fposmod(phase_deg, 360.0);
	if (p >= c.intake_open && p <= c.intake_close) {
		return c.intake_area;
	}
	return 0.0;
}

// Reed valve flow (simplified)
inline double reed_flow(const Cfg &c, double crankcase_pressure, double intake_p, double dt) {
	if (c.intake_area <= 0.0) {
		return 0.0;
	}
	double delta_p = intake_p - crankcase_pressure;
	if (delta_p <= 0.0) {
		return 0.0;
	}
	double rho = intake_p / (R * T0);
	return CD_PORT * c.intake_area * std::sqrt(2.0 * delta_p / rho) * rho * dt;
}

// 1 while the burn is under way: from the spark for the burn angle.
inline bool in_burn_window(double p, double start) {
	double burn_deg = BURN_DEG_BASE + BURN_DEG_PER_RPM * 5000.0;
	return std::fmod(p - start + 360.0, 360.0) < burn_deg;
}

inline double wiebe(double rel) {
	double burn_deg = BURN_DEG_BASE + BURN_DEG_PER_RPM * 5000.0;
	return 1.0 - std::exp(-WIEBE_A * std::pow(clampf(rel / burn_deg, 0.0, 1.0), WIEBE_M + 1.0));
}

} // namespace

void TwoStrokeKernel::_bind_methods() {
	ClassDB::bind_static_method("TwoStrokeKernel",
			D_METHOD("advance", "state", "cfg", "dphi", "dt", "intake_p", "intake_temp", "ign_phi", "running", "tank_afr",
					"tank_lhv", "lambda", "spark", "limiter_cut", "p_ex", "t_ex"),
			&TwoStrokeKernel::advance);
	ClassDB::bind_static_method("TwoStrokeKernel", D_METHOD("state_size"), &TwoStrokeKernel::state_size);
	ClassDB::bind_static_method("TwoStrokeKernel", D_METHOD("config_size"), &TwoStrokeKernel::config_size);
}

PackedFloat64Array TwoStrokeKernel::advance(PackedFloat64Array state, const PackedFloat64Array &cfg, double dphi, double dt,
		double intake_p, double intake_temp, double ign_phi, bool running, double tank_afr, double tank_lhv, double lambda,
		bool spark, bool limiter_cut, double p_ex, double t_ex) {
	(void)running; // advance takes it but never reads it
	if (state.size() < S_SIZE || cfg.size() < C_SIZE) {
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
	c.transfer_open = k[C_TRANSFER_OPEN];
	c.transfer_close = k[C_TRANSFER_CLOSE];
	c.exhaust_open = k[C_EXHAUST_OPEN];
	c.exhaust_close = k[C_EXHAUST_CLOSE];
	c.intake_open = k[C_INTAKE_OPEN];
	c.intake_close = k[C_INTAKE_CLOSE];
	c.transfer_area = k[C_TRANSFER_AREA];
	c.exhaust_area = k[C_EXHAUST_AREA];
	c.intake_area = k[C_INTAKE_AREA];
	c.crankcase_volume = k[C_CRANKCASE_VOLUME];
	c.oil_ratio = k[C_OIL_RATIO];
	c.intake_type = (int)k[C_INTAKE_TYPE];
	c.crank_radius = k[C_CRANK_RADIUS];
	c.tank_afr = tank_afr;
	c.tank_lhv = tank_lhv;

	// The state is worked in place; these are the GDScript member names.
	double *s = state.ptrw();
	double &phi = s[S_PHI];
	double &mass = s[S_MASS];
	double &temp = s[S_TEMP];
	double &pressure = s[S_PRESSURE];
	double &burn_energy_left = s[S_BURN_ENERGY_LEFT];
	double &burn_energy = s[S_BURN_ENERGY];
	double &peak_temp = s[S_PEAK_TEMP];
	double &last_lambda = s[S_LAST_LAMBDA];
	double &fuel_unburnt_kg = s[S_FUEL_UNBURNT_KG];
	double &residual_kg = s[S_RESIDUAL_KG];
	double &burnt = s[S_BURNT];
	double &wall_loss_j = s[S_WALL_LOSS_J];
	double &u = s[S_U];
	double &enthalpy_in_j = s[S_ENTHALPY_IN_J];
	double &enthalpy_out_j = s[S_ENTHALPY_OUT_J];
	double &exhaust_mdot = s[S_EXHAUST_MDOT];
	double &exhaust_power = s[S_EXHAUST_POWER];
	double &cycle_work = s[S_CYCLE_WORK];
	double &cycle_deg = s[S_CYCLE_DEG];
	double &cycle_peak_p = s[S_CYCLE_PEAK_P];
	double &cycle_max_dp = s[S_CYCLE_MAX_DP];
	double &cycle_p = s[S_CYCLE_P];
	double &ca10 = s[S_CA10];
	double &ca50 = s[S_CA50];
	double &ca90 = s[S_CA90];
	double &crankcase_mass = s[S_CRANKCASE_MASS];
	double &crankcase_temp = s[S_CRANKCASE_TEMP];
	double &crankcase_pressure = s[S_CRANKCASE_PRESSURE];
	double &oil_in_crankcase_kg = s[S_OIL_IN_CRANKCASE_KG];
	double &tank_mass = s[S_TANK_MASS];

	const int steps = maxi(1, maxi(ceili(std::fabs(dphi) / STEP_DEG), ceili(dt / 1e-4)));
	const double sd = dphi / steps;
	const double sdt = dt / steps;
	double work = 0.0;
	const double fuel_consumed = 0.0;

	for (int i = 0; i < steps; i++) {
		double p0 = phi;
		double p1 = phi + sd;
		double next_vol = volume_at(c, p1);
		double dv = next_vol - volume_at(c, p0);

		// Crankcase volume change
		double cc_vol0 = crankcase_vol(c, p0);
		double cc_vol1 = crankcase_vol(c, p1);
		double cc_dv = cc_vol1 - cc_vol0;

		// Check port events
		bool transfer_open_now = (p0 < c.transfer_open && p1 >= c.transfer_open) || (p0 <= c.transfer_close && p1 > c.transfer_close);

		// 1. Intake / Reed valve flow into crankcase
		if (c.intake_area > 0.0) {
			if (c.intake_type == 1) {
				// Reed valve flow
				double m_in = reed_flow(c, crankcase_pressure, intake_p, sdt);
				crankcase_mass += m_in;
				crankcase_pressure = crankcase_mass * R * crankcase_temp / cc_vol1;
				enthalpy_in_j += m_in * CP * intake_temp;
			} else if (c.intake_type == 2) {
				// Piston/rotary port - use port area function
				double a = intake_port_area(c, p0);
				if (a > 0.0) {
					double m_in = mass_flow(a, intake_p, intake_temp, crankcase_pressure, crankcase_temp) * sdt;
					crankcase_mass += m_in;
					crankcase_pressure = crankcase_mass * R * crankcase_temp / cc_vol1;
					enthalpy_in_j += m_in * CP * intake_temp;
				}
			}
		}

		// 2. Crankcase compression/expansion (adiabatic)
		if (cc_dv != 0.0) {
			// Adiabatic compression: P*V^gamma = const, so T2/T1 = (V1/V2)^(gamma-1)
			double t_ratio = std::pow(maxf(cc_vol0 / cc_vol1, 1e-6), G - 1.0);
			crankcase_temp *= t_ratio;
			crankcase_pressure = crankcase_mass * R * crankcase_temp / cc_vol1;
		}

		// 3. Transfer port flow (crankcase -> cylinder)
		double transfer_a = transfer_port_area(c, p0);
		if (transfer_a > 0.0) {
			double m_transfer = mass_flow(transfer_a, crankcase_pressure, crankcase_temp, pressure, temp) * sdt;
			// Oil mixes with transfer charge
			double oil_mass = c.oil_ratio > 0.0 ? m_transfer * (1.0 / c.oil_ratio) : 0.0;
			oil_in_crankcase_kg -= oil_mass;
			mass += m_transfer + oil_mass;
			crankcase_mass -= m_transfer;
			crankcase_pressure = crankcase_mass * R * crankcase_temp / cc_vol1;
			// Energy transfer
			double h_in = CP * crankcase_temp * m_transfer;
			u += h_in;
			enthalpy_in_j += h_in;
		}

		// 3b. Check if transfer ports just closed - inject fuel
		if (transfer_open_now) {
			// _fuel_charge
			double trapped = mass;
			double fresh = maxf(trapped - residual_kg, 0.0);
			s[S_LAST_FRESH_KG] = fresh;
			s[S_LAST_IVC_TEMP] = temp;
			s[S_LAST_RESIDUAL_FRACTION] = residual_kg / maxf(trapped, 1e-12);
			burn_energy = 0.0;
			burn_energy_left = 0.0;
			last_lambda = 1.0;

			if (!(limiter_cut || lambda >= MISFIRE_LAMBDA)) {
				double wanted = fresh / (c.tank_afr * lambda);
				double supplied = minf(wanted, tank_mass);
				tank_mass -= supplied;
				mass += supplied;
				u += supplied * CV * temp;

				if (!spark) {
					fuel_unburnt_kg = supplied;
				} else {
					fuel_unburnt_kg = 0.0;
					if (supplied > 0.0) {
						last_lambda = fresh / (c.tank_afr * supplied);
					}
					double burnable = minf(supplied, fresh / c.tank_afr);
					burn_energy = burnable * c.tank_lhv * COMBUSTION_EFFICIENCY;
					burn_energy_left = burn_energy;
					burnt = 0.0;
					s[S_FIRED] = supplied > 0.0 ? 1.0 : 0.0;
				}
			}
		}

		// 4. Exhaust port flow (cylinder -> expansion chamber / atmosphere)
		double exhaust_a = exhaust_port_area(c, p0);
		if (exhaust_a > 0.0) {
			double m_out = mass_flow(exhaust_a, pressure, temp, p_ex, t_ex) * sdt;
			mass -= m_out;
			// Energy out
			double h_out = CP * temp * m_out;
			u -= h_out;
			enthalpy_out_j += h_out;
			exhaust_mdot = m_out / sdt;
			exhaust_power = h_out / sdt;
		}

		// 5. Combustion
		double dq = 0.0;
		if (spark && burn_energy_left > 0.0 && in_burn_window(p0, ign_phi)) {
			double rel = std::fmod(p0 - ign_phi + 360.0, 360.0);
			dq = minf(burn_energy_left, burn_energy * (wiebe(rel + sd) - wiebe(rel)));
			burn_energy_left -= dq;
			u += dq; // the released heat goes into the gas: without it the burn never raised the pressure
			burnt = 1.0 - burn_energy_left / burn_energy;
		}

		// 6. Wall heat transfer
		double liner = (next_vol - c.clearance) / c.piston_area;
		double wall_area = 2.0 * c.piston_area + PI_ * c.bore * maxf(liner, 0.0);
		double w = std::fabs(phi * PI_ / 180.0); // rough crank speed estimate
		double h_wall = WALL_HEAT * std::pow(maxf(w, 1.0) / WALL_REF_W, 0.8);
		double q_loss = h_wall * wall_area * (temp - WALL_TEMP) * sdt;
		wall_loss_j += q_loss;
		u -= q_loss;

		// 7. First law
		mass = maxf(mass, 1e-12);
		temp = clampf(u / (mass * CV), 200.0, 4000.0);
		u = mass * CV * temp;
		peak_temp = maxf(peak_temp, temp);
		pressure = clampf(mass * R * temp / next_vol, 1000.0, 1.0e7);

		// Cycle work integral
		double dtheta = sd * PI_ / 180.0;
		work += (pressure - P0) * dv;
		// Inertia torque (c.crank_radius is the GDScript member, 0 unless _get_crank_radius ran)
		double phi_r = deg_to_rad(p0);
		double accel_term = std::cos(phi_r) + std::cos(2.0 * phi_r) / c.rod_ratio;
		work += -c.recip_kg * c.crank_radius * c.crank_radius * w * w * accel_term * std::sin(phi_r) * dtheta;

		// Track combustion phasing
		if (ca10 < 0.0 && burnt >= 0.1) {
			ca10 = p1;
		}
		if (ca50 < 0.0 && burnt >= 0.5) {
			ca50 = p1;
		}
		if (ca90 < 0.0 && burnt >= 0.9) {
			ca90 = p1;
		}

		cycle_work += pressure * dv;
		cycle_deg += sd;
		cycle_peak_p = maxf(cycle_peak_p, pressure);
		if (sd > 0.0) {
			cycle_max_dp = maxf(cycle_max_dp, (pressure - cycle_p) / sd);
		}
		cycle_p = pressure;

		phi = p1;
	}

	// Close cycle at 360 deg
	if (cycle_deg >= 300.0 && c.swept > 0.0) {
		s[S_LAST_IMEP] = cycle_work / c.swept;
		s[S_LAST_PEAK_PRESSURE] = cycle_peak_p;
		s[S_LAST_DP_DTHETA] = cycle_max_dp;
		s[S_LAST_CA10] = ca10 >= 0.0 ? fposmod(ca10, 360.0) : -1.0;
		s[S_LAST_CA50] = ca50 >= 0.0 ? fposmod(ca50, 360.0) : -1.0;
		s[S_LAST_CA90] = ca90 >= 0.0 ? fposmod(ca90, 360.0) : -1.0;
		s[S_LAST_BURN_10_90] = (ca10 >= 0.0 && ca90 >= ca10) ? ca90 - ca10 : 0.0;
		cycle_work = 0.0;
		cycle_deg = 0.0;
		cycle_peak_p = 0.0;
		cycle_max_dp = 0.0;
		cycle_p = 0.0;
		ca10 = -1.0;
		ca50 = -1.0;
		ca90 = -1.0;
	}

	s[S_OUT_WORK] = work;
	s[S_OUT_FUEL] = fuel_consumed;
	return state;
}
