#include "intake_model.h"
#include "turbo_model.h"

#include <algorithm>
#include <cmath>
#include <utility>

namespace engine_sim {

namespace {
constexpr double kPi = 3.14159265358979323846;

double clampd(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
} // namespace

void IntakeModel::setup(const IntakeSpec &spec, std::shared_ptr<const CompressorMap> map) {
    if (!spec.compressor_map_id.empty()) {
        compressor_map = std::move(map);
        compressor_speed_rpm = 0.0;
        compressor_pr = 1.0;
        compressor_eff = 0.7;
        surge_count = 0;
        choke_count = 0;
    }
}

// Moves the manifold for dt seconds: throttle and bypass inflow, drawn_kg_s out to the cylinders.
void IntakeModel::manifold_update(double dt, double throttle, double drawn_kg_s, const IntakeSpec *spec, double rpm,
                                  bool engine_running, double bike_speed_ms) {
    // The mass leaving the manifold must equal what entered the cylinder runners.
    const double drawn_scaled = drawn_kg_s;
    double target_boost = 1.0;
    double volume_scale = 1.0;
    double area_scale = 1.0;

    if (spec != nullptr) {
        double speed_factor = clampd((rpm - 1500.0) / 3500.0, 0.0, 1.0);
        compressor_load = 0.0;

        if (spec->electric_compressor || !spec->compressor_map_id.empty()) {
            // Map-based compressor model
            turbo::update_map(*this, dt, *spec, drawn_scaled, throttle, engine_running);
            target_boost = compressor_pr;
            speed_factor = 1.0; // map handles speed dependence
        } else {
            // Legacy electric compressor model
            const double available = clampd(compressor_charge / 0.1, 0.0, 1.0);
            compressor_load = engine_running ? clampd(throttle, 0.0, 1.0) * available : 0.0;
            speed_factor = engine_running ? available : 0.0;
            const double draw = compressor_load * std::max(spec->compressor_power_w, 0.0);
            const double charging = engine_running ? std::max(spec->compressor_charge_w, 0.0) : 0.0;
            compressor_charge = clampd(
                compressor_charge + (charging - draw) * dt / (std::max(spec->compressor_battery_wh, 0.1) * 3600.0),
                0.0, 1.0);
        }

        if (spec->compressor_map_id.empty() && !spec->electric_compressor) {
            // Legacy boost spool for non-map turbos
            target_boost += std::max(spec->max_boost_ratio - 1.0, 0.0) * speed_factor * clampd(throttle, 0.0, 1.0);
            boost_ratio += (target_boost - boost_ratio) *
                           (1.0 - std::exp(-dt / std::max(spec->boost_spool_time, 0.01)));
        } else {
            boost_ratio = target_boost;
        }

        volume_scale = std::max(spec->manifold_volume_scale, 0.01);
        area_scale = std::max(spec->intake_area_scale, 0.01);
    } else {
        boost_ratio = 1.0;
    }

    // Ram-air: dynamic pressure recovery at speed. 0.5 * rho * v^2 * recovery_factor
    if (spec != nullptr && bike_speed_ms > 0.0) {
        const double dynamic_pressure = 0.5 * 1.2 * bike_speed_ms * bike_speed_ms; // rho * v^2 / 2
        ram_air_boost = 1.0 + (dynamic_pressure * intake::RAM_AIR_RECOVERY / intake::P0);
    } else {
        ram_air_boost = 1.0;
    }

    const double supply_pressure = intake::P0 * boost_ratio * ram_air_boost;
    double inlet_area = intake::THROTTLE_AREA;
    if (spec != nullptr) {
        const double r = std::max(spec->throttle_bore_mm, 1.0) * 0.0005;
        inlet_area = kPi * std::pow(r, 2.0) * std::max(spec->throttle_count, 1);
    }
    const double plate_area = inlet_area * area_scale * (1.0 - std::cos(clampd(throttle, 0.0, 1.0) * kPi / 2.0));
    const double inflow = orifice(plate_area, supply_pressure) + orifice(bypass_area, supply_pressure);
    pressure = clampd(pressure + intake::R_AIR * intake::T0 / (intake::MANIFOLD_VOLUME * volume_scale) *
                                     (inflow - drawn_scaled) * dt,
                      intake::MIN_PRESSURE, supply_pressure);
}

// Compressible mass flow through an orifice from atmosphere into the manifold, kg/s.
double IntakeModel::orifice(double area, double upstream_pressure) const {
    const double pr = pressure / upstream_pressure;
    if (pr >= 1.0 || area <= 0.0) {
        return 0.0;
    }
    const double g = intake::GAMMA;
    const double k = intake::CD * area * upstream_pressure / std::sqrt(intake::R_AIR * intake::T0);
    const double critical = std::pow(2.0 / (g + 1.0), g / (g - 1.0));
    if (pr <= critical) {
        return k * std::sqrt(g * std::pow(2.0 / (g + 1.0), (g + 1.0) / (g - 1.0)));
    }
    return k * std::sqrt(2.0 * g / (g - 1.0) * (std::pow(pr, 2.0 / g) - std::pow(pr, (g + 1.0) / g)));
}

} // namespace engine_sim
