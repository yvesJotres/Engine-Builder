#ifndef CYLINDER_H
#define CYLINDER_H

#include "engine_sim.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <vector>

namespace engine_sim {

using namespace godot;

class FuelTank;
class EngineSpec;

class Cylinder : public RefCounted {
    GDCLASS(Cylinder, RefCounted);

public:
    static constexpr float G = 1.4f;
    static constexpr float R = 287.0f;
    static constexpr float CV = R / (G - 1.0f);
    static constexpr float CP = G * R / (G - 1.0f);
    static constexpr float CV_BURNT = 960.0f;
    static constexpr float P0 = 101325.0f;
    static constexpr float T0 = 300.0f;
    static constexpr float CD_VALVE = 0.7f;
    static constexpr float COMBUSTION_EFFICIENCY = 0.95f;
    static constexpr float MISFIRE_LAMBDA = 1.35f;
    static constexpr float BURN_DEG_BASE = 45.0f;
    static constexpr float BURN_DEG_PER_RPM = 0.002f;
    static constexpr float CA50_TARGET = 10.0f;
    static constexpr float WIEBE_CA50 = 0.465f;
    static constexpr float WIEBE_A = 6.908f;
    static constexpr float WIEBE_M = 2.0f;
    static constexpr float STEP_DEG = 7.5f;
    static constexpr float WALL_HEAT = 1000.0f;
    static constexpr float WALL_REF_W = 314.0f;
    static constexpr float WALL_TEMP = 420.0f;
    static constexpr float INTAKE_OPEN = 350.0f;
    static constexpr float INTAKE_CLOSE = 590.0f;
    static constexpr float EXHAUST_OPEN = 140.0f;
    static constexpr float EXHAUST_CLOSE = 370.0f;
    static constexpr float INTAKE_LIFT = 0.006f;
    static constexpr float EXHAUST_LIFT = 0.005f;
    static constexpr float INTAKE_VALVE_D = 0.020f;
    static constexpr float EXHAUST_VALVE_D = 0.017f;
    static constexpr float INTAKE_PORT_AREA = 2.0f * Math::PI * 0.0125f * 0.0125f;
    static constexpr float EXHAUST_PORT_AREA = 2.0f * Math::PI * 0.0105f * 0.0105f;
    static constexpr float RUNNER_AREA = 6.6e-4f;
    static constexpr float RUNNER_LENGTH = 0.25f;
    static constexpr float PORT_VOLUME = 0.5e-4f;
    static constexpr float RUNNER_LOSS = 1.5f;
    static constexpr float MAX_FLOW_DT = 2.5e-4f;
    static constexpr float OVERLAP_RETURN_BELOW = 0.9f;
    static constexpr float AUTO_IGNITE_K = 900.0f;
    static constexpr float BACKFIRE_BURN = 0.5f;
    static constexpr int EXHAUST_FLOW_BINS = 180;
    static constexpr float CHECK_LIFT_M = 0.00127f;
    static constexpr float SEAT_OVER_050 = 1.14f;

    // Public interface
    void setup(float bore_mm, float stroke_mm, float compression_ratio, float recip_kg = 0.15f, float rod_lambda = 1.6f);
    void set_cams(const EngineSpec *spec);
    void start_at(float phase_deg);
    float volume(float phi_deg) const;
    static float lift(float phi_deg, float open_deg, float close_deg, float peak);
    static float mass_flow(float area, float p1, float t1, float p2, float t2);
    Vector2 advance(float dphi, float dt, float pm, float tm, float ign_phi, bool firing,
                    FuelTank *tank, float lambda, bool spark = true, bool limiter_cut = false,
                    float p_ex = P0, float t_ex = T0);
    static float burn_duration_deg(float rpm);
    float _lift(float phi_deg, float open_deg, float close_deg, float peak,
                int profile, const Array &lift_curve, float flat_frac,
                float open_ramp_deg, float close_ramp_deg, float duration_050) const;
    float exhaust_valve_area(float phase_deg) const;
    float _intake_area(float phase_deg) const;
    int _flow_steps(float dphi, float dt, float pm, float tm, float p_ex, float t_ex) const;
    void _fuel_charge(FuelTank *tank, float lambda, bool spark, bool limiter_cut, float pm);
    float _wiebe(float rel, float burn_deg) const;
    static bool _crossed(float a, float b, float at);
    static bool _in_window(float p, float start, float length);

    // Public state for sensors
    float exhaust_temp = 300.0f;
    float peak_temp = 300.0f;
    float last_peak_temp = 300.0f;
    float last_lambda = 1.0f;
    float backfire_j = 0.0f;
    float last_dp_dtheta = 0.0f;
    float last_ca50 = -1.0f;
    float last_burn_10_90 = 0.0f;
    float last_ivc_temp = 0.0f;
    float last_residual_fraction = 0.0f;
    float last_imep = 0.0f;

protected:
    static void _bind_methods();

private:
    // Valve events (crank degrees after firing TDC)
    float intake_open = INTAKE_OPEN;
    float intake_close = INTAKE_CLOSE;
    float exhaust_open = EXHAUST_OPEN;
    float exhaust_close = EXHAUST_CLOSE;
    float intake_lift = INTAKE_LIFT;
    float exhaust_lift = EXHAUST_LIFT;
    float intake_valve_d = INTAKE_VALVE_D;
    float exhaust_valve_d = EXHAUST_VALVE_D;
    float intake_port_area = INTAKE_PORT_AREA;
    float exhaust_port_area = EXHAUST_PORT_AREA;
    float runner_length = RUNNER_LENGTH;

    // Cam profile parameters
    int _intake_profile = 0;
    int _exhaust_profile = 0;
    Array _intake_lift_curve;
    Array _exhaust_lift_curve;
    float _intake_flat_frac = 0.3f;
    float _exhaust_flat_frac = 0.3f;
    float _intake_open_ramp = 0.0f;
    float _intake_close_ramp = 0.0f;
    float _exhaust_open_ramp = 0.0f;
    float _exhaust_close_ramp = 0.0f;
    float _intake_duration_050 = 0.0f;
    float _exhaust_duration_050 = 0.0f;
    float valve_cd = CD_VALVE;

    // Geometry
    float swept = 0.0f;
    float clearance = 0.0f;
    float bore = 0.0f;
    float piston_area = 0.0f;
    float stroke = 0.0f;
    float recip_kg = 0.15f;
    float rod_ratio = 1.6f;
    float wall_heat_scale = 1.0f;

    // State
    float phi = 0.0f;
    float mass = 0.0f;
    float temp = T0;
    float pressure = P0;
    float burn_energy_left = 0.0f;
    float burn_energy = 0.0f;
    float port_p = P0;
    float runner_q = 0.0f;
    float _fired = false;
    float fuel_unburnt_kg = 0.0f;
    float _port_heat = T0;
    float _residual_kg = 0.0f;
    float _burnt = 0.0f;
    float _u = 0.0f;
    float enthalpy_in_j = 0.0f;
    float enthalpy_out_j = 0.0f;
    float wall_loss_j = 0.0f;

    // Exhaust flow recording
    PackedFloat32Array _exhaust_flow_cycle;
    float _cycle_max_dp = 0.0f;
    float _cycle_p = 0.0f;
    float _cycle_peak_p = 0.0f;
    float _cycle_work = 0.0f;
    float _cycle_deg = 0.0f;

    // Internal helpers
    void _close_cycle();
    static float _subsonic(float area, float p_up, float t_up, float p_down);
    void _fuel_charge(FuelTank *tank, float lambda, bool spark, bool limiter_cut, float pm);
    static float _wiebe(float rel, float burn_deg);
    static bool _crossed(float a, float b, float at);
    static bool _in_window(float p, float start, float length);
};

} // namespace engine_sim

#endif // CYLINDER_H