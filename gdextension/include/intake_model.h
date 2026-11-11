#ifndef INTAKE_MODEL_H
#define INTAKE_MODEL_H

// Port of scripts/intake/engine_air.gd (manifold, orifices, ram air, legacy boost spool, compressor call).
// Plain C++ structs, nothing registered. The spec is passed in as IntakeSpec, a subset of EngineSpec with the
// same field names and default values; the lead must copy the values across from the real spec.

#include "compressor_map.h"

#include <memory>
#include <string>

namespace engine_sim {

namespace intake {
constexpr double P0 = 101325.0;   // atmosphere, Pa
constexpr double T0 = 300.0;      // intake air temperature, K
constexpr double R_AIR = 287.0;   // J/(kg K)
constexpr double GAMMA = 1.4;
constexpr double CD = 0.8;        // discharge coefficient for plate and bypass orifices
constexpr double THROTTLE_AREA = 3.14159265358979323846 * 0.015 * 0.015;   // from a 30 mm bore
constexpr double BYPASS_AREA = 3.14159265358979323846 * 0.00087 * 0.00087; // idle bypass radius 0.87 mm
constexpr double MANIFOLD_VOLUME = 5e-4; // m^3, manifold plus airbox
constexpr double MIN_PRESSURE = 5000.0;  // Pa, floor so the vacuum stays finite
constexpr double RAM_AIR_RECOVERY = 0.15;
} // namespace intake

struct IntakeSpec {
    bool electric_compressor = false;
    std::string compressor_map_id; // empty = no map
    double max_boost_ratio = 1.0;
    double compressor_battery_wh = 40.0;
    double compressor_power_w = 2000.0;
    double compressor_charge_w = 1000.0;
    double boost_spool_time = 0.6;
    double compressor_inertia_kgm2 = 0.00005;
    std::string wastegate_type = "internal"; // internal, external, none
    double wastegate_pressure_ratio = 0.0;
    double turbine_efficiency = 0.70;
    double intake_area_scale = 1.0;
    double throttle_bore_mm = 30.0;
    int throttle_count = 1;
    double manifold_volume_scale = 1.0;
};

struct IntakeModel {
    double pressure = intake::P0;           // manifold pressure, Pa
    double bypass_area = intake::BYPASS_AREA; // m^2, the simulator scales it with displacement
    bool limiter_cut = false;
    double boost_ratio = 1.0;
    double compressor_charge = 1.0;
    double compressor_load = 0.0;
    double ram_air_boost = 1.0;

    // Compressor state, written by turbo::update_map
    std::shared_ptr<const CompressorMap> compressor_map; // null when no map
    double compressor_speed_rpm = 0.0;
    double compressor_pr = 1.0;
    double compressor_eff = 0.7;
    int surge_count = 0;
    int choke_count = 0;
    double flow_avg = 0.0; // engine air flow averaged over turbo::FLOW_AVG_TIME, kg/s

    // Loads the map (if any) and resets the compressor state, like EngineAir.setup.
    void setup(const IntakeSpec &spec, std::shared_ptr<const CompressorMap> map);

    // Moves the manifold for dt seconds. spec may be null (plain atmospheric manifold).
    void manifold_update(double dt, double throttle, double drawn_kg_s, const IntakeSpec *spec = nullptr,
                         double rpm = 0.0, bool engine_running = true, double bike_speed_ms = 0.0);

    // Compressible mass flow through an orifice from atmosphere into the manifold, kg/s.
    double orifice(double area, double upstream_pressure = intake::P0) const;
};

} // namespace engine_sim

#endif // INTAKE_MODEL_H
