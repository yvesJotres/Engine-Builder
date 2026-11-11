#include "turbo_model.h"

#include <algorithm>
#include <cmath>

namespace engine_sim {

namespace {
constexpr double kPi = 3.14159265358979323846;
constexpr double kTau = 2.0 * kPi;

double clampd(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
} // namespace

namespace turbo {

void update_map(IntakeModel &air, double dt, const IntakeSpec &spec, double m_dot_engine, double throttle,
                bool engine_running) {
    if (!air.compressor_map || air.compressor_map->speed_lines.empty()) {
        return;
    }
    const CompressorMap &map = *air.compressor_map;

    // Inlet conditions (pre-compressor)
    const double T_in = intake::T0;
    const double P_in = intake::P0;

    // Corrected flow from engine demand
    air.flow_avg += (m_dot_engine - air.flow_avg) * (1.0 - std::exp(-dt / FLOW_AVG_TIME));
    const double m_flow = air.flow_avg;
    const double corr_flow = map.correct_flow(m_flow, T_in, P_in);

    // Current corrected speed
    const double corr_speed = map.correct_speed(air.compressor_speed_rpm, T_in);

    // Map lookup
    MapLookup map_res = map.lookup(corr_speed, corr_flow);
    double target_pr = map_res.pr;
    // the map starts at its lowest speed line; a wheel slower than that makes proportionally less pressure, none at rest
    target_pr = 1.0 + (target_pr - 1.0) * clampd(corr_speed / map.speed_lines[0].speed_rpm, 0.0, 1.0);
    const double comp_eff = map_res.eff;

    // Compressor power required [W]
    const double gamma = intake::GAMMA;
    const double Cp = CP_AIR;
    const double T_out_ideal = T_in * std::pow(target_pr, (gamma - 1.0) / gamma);
    const double T_out_actual = T_in + (T_out_ideal - T_in) / comp_eff;
    const double P_comp = m_flow * Cp * (T_out_actual - T_in);

    // Turbine / motor power available
    double P_turbine = 0.0;
    if (spec.electric_compressor) {
        // Electric motor limited by battery & power rating
        const double batt_frac = air.compressor_charge;
        P_turbine = spec.compressor_power_w * batt_frac;
        const double charging = engine_running ? std::max(spec.compressor_charge_w, 0.0) : 0.0;
        const double battery_wh = std::max(spec.compressor_battery_wh, 0.1);
        air.compressor_charge =
            clampd(air.compressor_charge + (charging - P_turbine) * dt / (battery_wh * 3600.0), 0.0, 1.0);
    } else {
        // Exhaust turbine: simplified, turbine power ~ mass_flow * Cp * T * (1 - PR^(-(g-1)/g)) * eff
        const double exh_mass_flow = m_flow * (1.0 + 1.0 / 14.7); // approx with fuel at stoich
        const double exh_T = 900.0;                                // K, estimated exhaust temp
        // shortcut: exhaust pressure from the manifold, not the exhaust flow; the pipe solver would give the real value
        const double exh_P = std::max(air.pressure, intake::P0) * EXH_RATIO;
        const double turbine_pr = exh_P / P_in;
        if (turbine_pr > 1.0) {
            P_turbine = exh_mass_flow * Cp * exh_T * (1.0 - std::pow(turbine_pr, -(gamma - 1.0) / gamma)) *
                        spec.turbine_efficiency;
        }
        // Wastegate
        if (spec.wastegate_type != "none" && target_pr > spec.wastegate_pressure_ratio) {
            // the surplus exhaust bypasses the turbine: it keeps only the power that holds the wastegate pressure
            const double wg_power = m_flow * Cp * T_in *
                                    (std::pow(spec.wastegate_pressure_ratio, (gamma - 1.0) / gamma) - 1.0) / comp_eff;
            P_turbine = std::min(P_turbine, wg_power);
        }
    }

    // Shaft acceleration
    const double P_net = P_turbine - P_comp;
    // Motor torque model: constant torque up to base speed, then constant power
    if (spec.compressor_inertia_kgm2 > 0.0) {
        if (air.compressor_speed_rpm > 0.0) {
            // Power = torque * omega, so torque = P / omega
            const double omega = air.compressor_speed_rpm * kTau / 60.0;
            const double torque = P_net / std::max(omega, 1.0);
            const double accel = torque / spec.compressor_inertia_kgm2;
            air.compressor_speed_rpm += accel * dt * 60.0 / kTau;
        } else if (P_net > 0.0) {
            // At zero speed: use stall torque = rated_power / base_omega
            const double base_omega = BASE_SPEED_RPM * kTau / 60.0;
            double stall_torque = spec.compressor_power_w / base_omega;
            if (!spec.electric_compressor) {
                // a turbo has no motor: its own spare exhaust power starts it from rest
                stall_torque = P_net / START_OMEGA;
            }
            const double accel = stall_torque / spec.compressor_inertia_kgm2;
            air.compressor_speed_rpm += accel * dt * 60.0 / kTau;
        }
    }
    air.compressor_speed_rpm = std::max(0.0, air.compressor_speed_rpm);

    // Apply throttle modulation to PR (throttle downstream of compressor)
    air.compressor_pr = 1.0 + (target_pr - 1.0) * throttle;
    air.compressor_eff = comp_eff;

    // Surge/choke detection
    if (map.is_surge(corr_flow, target_pr)) {
        air.surge_count += 1;
        air.compressor_pr *= 0.95; // pressure collapse
    }
    if (map.is_choke(corr_flow, target_pr)) {
        air.choke_count += 1;
        // Flow limited, PR naturally limited by choke
    }
}

} // namespace turbo

} // namespace engine_sim
