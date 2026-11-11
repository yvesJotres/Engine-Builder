#ifndef ENGINE_METRICS_H
#define ENGINE_METRICS_H

#include <vector>

// Port of scripts/sim/engine_metrics.gd. Plain C++, no Godot types.
// The GDScript takes an EngineSim; here the same figures are computed from plain state structs.
// Field names match the GDScript fields they were read from. Units are as in the GDScript: temperatures in K on input,
// pressures in Pa, torque in N·m, rpm, fuel_flow in g/s, fuel_lhv in J/kg.
// Doubles are used throughout to match GDScript's float precision.

namespace engine_physics {

// Ideal gas and ambient constants, from scripts/engine/cylinder.gd (Cylinder.R, Cylinder.P0, Cylinder.T0).
constexpr double CYLINDER_R = 287.0;
constexpr double CYLINDER_P0 = 101325.0; // atmosphere, Pa
constexpr double CYLINDER_T0 = 300.0; // intake and ambient temperature, K

// The per-cylinder fields the metrics read from Cylinder (or TwoStrokeCylinder).
struct CylinderMetricsState {
    double swept = 0.0; // m³
    double exhaust_temp = 300.0; // K
    double last_peak_temp = 300.0; // K
    double last_lambda = 1.0;
    double last_imep = 0.0; // Pa
    double last_peak_pressure = 0.0; // Pa
    double last_dp_dtheta = 0.0; // Pa per crank degree
    double last_ca50 = -1.0; // crank degrees after firing TDC, -1 when not known
    double last_burn_10_90 = 0.0; // crank degrees
    double last_ivc_temp = 0.0; // K
    double last_residual_fraction = 0.0;
    double last_fresh_kg = 0.0; // kg
};

// The sim-level fields the metrics read from EngineSim.
struct SimMetricsState {
    std::vector<CylinderMetricsState> cylinders;
    double rpm = 0.0;
    double torque = 0.0; // N·m
    double cycle_brake_torque = 0.0; // N·m
    double fuel_flow = 0.0; // g/s
    double fuel_lhv = 0.0; // J/kg
};

// Exhaust gas temperature sensor, °C: the average of the cylinders' exhaust gas as their exhaust valves open.
double exhaust_temp_c(const SimMetricsState &sim);

// Chamber temperature sensor, °C: the hottest gas each cylinder reached in its last complete cycle, averaged over the cylinders.
double chamber_peak_c(const SimMetricsState &sim);

// Exhaust port temperatures, °C, one per cylinder: the gas each one last sent out (what each header runner carries).
std::vector<double> port_temps_c(const SimMetricsState &sim);

// O2 sensor, relative to stoichiometric: the average mixture the cylinders burned on their last cycle. 1.0 is exact.
double o2_lambda(const SimMetricsState &sim);

double swept_m3(const SimMetricsState &sim);

// Net indicated mean effective pressure, Pa: the closed-cycle ∮P dV divided by swept volume, averaged over the cylinders.
double imep_pa(const SimMetricsState &sim);

// Brake mean effective pressure, Pa, from the mean shaft torque of the last closed cycle.
double bmep_pa(const SimMetricsState &sim);

// Friction mean effective pressure, Pa: what the net indicated pressure loses before it reaches the shaft.
double fmep_pa(const SimMetricsState &sim);

double indicated_power_w(const SimMetricsState &sim);
double brake_power_w(const SimMetricsState &sim);

// g/kWh. Zero when the shaft is not delivering power.
double bsfc_g_kwh(const SimMetricsState &sim);
double isfc_g_kwh(const SimMetricsState &sim);

double brake_thermal_efficiency(const SimMetricsState &sim);
double indicated_thermal_efficiency(const SimMetricsState &sim);

// Trapped fresh air at intake closing divided by the swept volume filled at ambient density.
double volumetric_efficiency(const SimMetricsState &sim);

double mechanical_efficiency(const SimMetricsState &sim);
double peak_pressure_pa(const SimMetricsState &sim);

// Steepest pressure rise of the last cycle, Pa per crank degree.
double peak_dp_dtheta(const SimMetricsState &sim);

// Mean CA50 over the cylinders that report one, -1 when none do.
double ca50_deg(const SimMetricsState &sim);

double burn_10_90_deg(const SimMetricsState &sim);
double ivc_temp_c(const SimMetricsState &sim);
double residual_fraction(const SimMetricsState &sim);

} // namespace engine_physics

#endif // ENGINE_METRICS_H
