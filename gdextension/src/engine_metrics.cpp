#include "engine_metrics.h"

#include <algorithm>
#include <cmath>

namespace engine_physics {

namespace {

constexpr double KELVIN_OFFSET = 273.15;
constexpr double PI_D = 3.14159265358979323846;
constexpr double TAU_D = 2.0 * PI_D;

// Units.rpm_to_rad_s and Units.power_w from scripts/app/units.gd.
double rpm_to_rad_s(double rpm) {
    return rpm * TAU_D / 60.0;
}

double power_w(double torque_nm, double rpm) {
    return torque_nm * rpm_to_rad_s(rpm);
}

// Mean of the values that are >= 0, or -1 when none are.
double mean_nonneg_angle(const SimMetricsState &sim, double CylinderMetricsState::*field) {
    double sum = 0.0;
    int n = 0;
    for (const auto &c : sim.cylinders) {
        double angle = c.*field;
        if (angle >= 0.0) {
            sum += angle;
            n += 1;
        }
    }
    return n > 0 ? sum / n : -1.0;
}

double shaft_torque(const SimMetricsState &sim) {
    return sim.cycle_brake_torque != 0.0 ? sim.cycle_brake_torque : sim.torque;
}

double thermal_efficiency(const SimMetricsState &sim, double power) {
    double fuel_w = sim.fuel_flow * 0.001 * sim.fuel_lhv;
    if (power <= 0.0 || fuel_w <= 0.0) {
        return 0.0;
    }
    return power / fuel_w;
}

} // namespace

// Exhaust gas temperature sensor, °C: the average of the cylinders' exhaust gas as their exhaust valves open.
double exhaust_temp_c(const SimMetricsState &sim) {
    if (sim.cylinders.empty()) {
        return 0.0;
    }
    double sum = 0.0;
    for (const auto &c : sim.cylinders) {
        sum += c.exhaust_temp;
    }
    return sum / sim.cylinders.size() - KELVIN_OFFSET;
}

// Chamber temperature sensor, °C: the hottest gas each cylinder reached in its last complete cycle, averaged over the cylinders.
double chamber_peak_c(const SimMetricsState &sim) {
    if (sim.cylinders.empty()) {
        return 0.0;
    }
    double sum = 0.0;
    for (const auto &c : sim.cylinders) {
        sum += c.last_peak_temp;
    }
    return sum / sim.cylinders.size() - KELVIN_OFFSET;
}

// Exhaust port temperatures, °C, one per cylinder: the gas each one last sent out (what each header runner carries).
std::vector<double> port_temps_c(const SimMetricsState &sim) {
    std::vector<double> out;
    for (const auto &c : sim.cylinders) {
        out.push_back(c.exhaust_temp - KELVIN_OFFSET);
    }
    return out;
}

// O2 sensor, relative to stoichiometric: the average mixture the cylinders burned on their last cycle. 1.0 is exact.
double o2_lambda(const SimMetricsState &sim) {
    if (sim.cylinders.empty()) {
        return 0.0;
    }
    double sum = 0.0;
    int n = 0;
    for (const auto &c : sim.cylinders) {
        if (c.last_lambda < 50.0) {
            sum += c.last_lambda;
            n += 1;
        }
    }
    return n > 0 ? sum / n : 99.0;
}

double swept_m3(const SimMetricsState &sim) {
    double volume = 0.0;
    for (const auto &c : sim.cylinders) {
        volume += c.swept;
    }
    return volume;
}

// Net indicated mean effective pressure, Pa: the closed-cycle ∮P dV divided by swept volume, averaged over the cylinders.
double imep_pa(const SimMetricsState &sim) {
    double sum = 0.0;
    int n = 0;
    for (const auto &c : sim.cylinders) {
        if (c.last_imep != 0.0) {
            sum += c.last_imep;
            n += 1;
        }
    }
    return n > 0 ? sum / n : 0.0;
}

// Brake mean effective pressure, Pa, from the mean shaft torque of the last closed cycle.
double bmep_pa(const SimMetricsState &sim) {
    double volume = swept_m3(sim);
    if (volume <= 0.0) {
        return 0.0;
    }
    return shaft_torque(sim) * 4.0 * PI_D / volume;
}

// Friction mean effective pressure, Pa: what the net indicated pressure loses before it reaches the shaft.
double fmep_pa(const SimMetricsState &sim) {
    return imep_pa(sim) - bmep_pa(sim);
}

double indicated_power_w(const SimMetricsState &sim) {
    if (sim.rpm <= 0.0) {
        return 0.0;
    }
    return imep_pa(sim) * swept_m3(sim) * sim.rpm / 120.0;
}

double brake_power_w(const SimMetricsState &sim) {
    return power_w(shaft_torque(sim), sim.rpm);
}

// g/kWh. Zero when the shaft is not delivering power.
double bsfc_g_kwh(const SimMetricsState &sim) {
    double power_kw = brake_power_w(sim) / 1000.0;
    if (power_kw <= 0.05) {
        return 0.0;
    }
    return sim.fuel_flow * 3600.0 / power_kw;
}

double isfc_g_kwh(const SimMetricsState &sim) {
    double power_kw = indicated_power_w(sim) / 1000.0;
    if (power_kw <= 0.05) {
        return 0.0;
    }
    return sim.fuel_flow * 3600.0 / power_kw;
}

double brake_thermal_efficiency(const SimMetricsState &sim) {
    return thermal_efficiency(sim, brake_power_w(sim));
}

double indicated_thermal_efficiency(const SimMetricsState &sim) {
    return thermal_efficiency(sim, indicated_power_w(sim));
}

// Trapped fresh air at intake closing divided by the swept volume filled at ambient density.
double volumetric_efficiency(const SimMetricsState &sim) {
    double rho = CYLINDER_P0 / (CYLINDER_R * CYLINDER_T0);
    double sum = 0.0;
    int n = 0;
    for (const auto &c : sim.cylinders) {
        if (c.swept <= 0.0 || c.last_fresh_kg <= 0.0) {
            continue;
        }
        sum += c.last_fresh_kg / (c.swept * rho);
        n += 1;
    }
    return n > 0 ? sum / n : 0.0;
}

double mechanical_efficiency(const SimMetricsState &sim) {
    double indicated = imep_pa(sim);
    if (indicated <= 0.0) {
        return 0.0;
    }
    return bmep_pa(sim) / indicated;
}

double peak_pressure_pa(const SimMetricsState &sim) {
    double peak = 0.0;
    for (const auto &c : sim.cylinders) {
        peak = std::max(peak, c.last_peak_pressure);
    }
    return peak;
}

// Steepest pressure rise of the last cycle, Pa per crank degree.
double peak_dp_dtheta(const SimMetricsState &sim) {
    double peak = 0.0;
    for (const auto &c : sim.cylinders) {
        peak = std::max(peak, c.last_dp_dtheta);
    }
    return peak;
}

// Mean CA50 over the cylinders that report one, -1 when none do.
double ca50_deg(const SimMetricsState &sim) {
    return mean_nonneg_angle(sim, &CylinderMetricsState::last_ca50);
}

double burn_10_90_deg(const SimMetricsState &sim) {
    double sum = 0.0;
    int n = 0;
    for (const auto &c : sim.cylinders) {
        if (c.last_burn_10_90 > 0.0) {
            sum += c.last_burn_10_90;
            n += 1;
        }
    }
    return n > 0 ? sum / n : 0.0;
}

double ivc_temp_c(const SimMetricsState &sim) {
    if (sim.cylinders.empty()) {
        return 0.0;
    }
    double sum = 0.0;
    for (const auto &c : sim.cylinders) {
        sum += c.last_ivc_temp;
    }
    return sum / sim.cylinders.size() - KELVIN_OFFSET;
}

double residual_fraction(const SimMetricsState &sim) {
    if (sim.cylinders.empty()) {
        return 0.0;
    }
    double sum = 0.0;
    for (const auto &c : sim.cylinders) {
        sum += c.last_residual_fraction;
    }
    return sum / sim.cylinders.size();
}

} // namespace engine_physics
