#include "cylinder.h"
#include "engine_spec.h"
#include "fuel_tank.h"
#include <godot_cpp/variant/utility_functions.hpp>
#include <cmath>
#include <algorithm>

namespace engine_sim {

using namespace godot;

void Cylinder::_bind_methods() {
    ClassDB::bind_method(D_METHOD("setup", "bore_mm", "stroke_mm", "compression_ratio", "recip_kg", "rod_lambda"), &Cylinder::setup);
    ClassDB::bind_method(D_METHOD("set_cams", "spec"), &Cylinder::set_cams);
    ClassDB::bind_method(D_METHOD("start_at", "phase_deg"), &Cylinder::start_at);
    ClassDB::bind_method(D_METHOD("volume", "phi_deg"), &Cylinder::volume);
    ClassDB::bind_method(D_METHOD("lift", "phi_deg", "open_deg", "close_deg", "peak"), &Cylinder::lift);
    ClassDB::bind_method(D_METHOD("mass_flow", "area", "p1", "t1", "p2", "t2"), &Cylinder::mass_flow);
    ClassDB::bind_method(D_METHOD("advance", "dphi", "dt", "pm", "tm", "ign_phi", "firing", "tank", "lambda", "spark", "limiter_cut", "p_ex", "t_ex"), &Cylinder::advance);
    ClassDB::bind_method(D_METHOD("burn_duration_deg", "rpm"), &Cylinder::burn_duration_deg);
    ClassDB::bind_method(D_METHOD("_lift", "phi_deg", "open_deg", "close_deg", "peak", "profile", "lift_curve", "flat_frac", "open_ramp_deg", "close_ramp_deg", "duration_050"), &Cylinder::_lift);
    ClassDB::bind_method(D_METHOD("exhaust_valve_area", "phase_deg"), &Cylinder::exhaust_valve_area);
    ClassDB::bind_method(D_METHOD("_intake_area", "phase_deg"), &Cylinder::_intake_area);
    ClassDB::bind_method(D_METHOD("_flow_steps", "dphi", "dt", "pm", "tm", "p_ex", "t_ex"), &Cylinder::_flow_steps);
    ClassDB::bind_method(D_METHOD("_fuel_charge", "tank", "lambda", "spark", "limiter_cut", "pm"), &Cylinder::_fuel_charge);
    ClassDB::bind_method(D_METHOD("_wiebe", "rel", "burn_deg"), &Cylinder::_wiebe);
    ClassDB::bind_method(D_METHOD("_crossed", "a", "b", "at"), &Cylinder::_crossed);
    ClassDB::bind_method(D_METHOD("_in_window", "p", "start", "length"), &Cylinder::_in_window);

    // Sensor properties
    ClassDB::bind_method(D_METHOD("get_exhaust_temp"), &Cylinder::get_exhaust_temp);
    ClassDB::bind_method(D_METHOD("get_peak_temp"), &Cylinder::get_peak_temp);
    ClassDB::bind_method(D_METHOD("get_last_peak_temp"), &Cylinder::get_last_peak_temp);
    ClassDB::bind_method(D_METHOD("get_last_lambda"), &Cylinder::get_last_lambda);
    ClassDB::bind_method(D_METHOD("get_backfire_j"), &Cylinder::get_backfire_j);
    ClassDB::bind_method(D_METHOD("get_last_dp_dtheta"), &Cylinder::get_last_dp_dtheta);
    ClassDB::bind_method(D_METHOD("get_last_ca50"), &Cylinder::get_last_ca50);
    ClassDB::bind_method(D_METHOD("get_last_burn_10_90"), &Cylinder::get_last_burn_10_90);
    ClassDB::bind_method(D_METHOD("get_last_ivc_temp"), &Cylinder::get_last_ivc_temp);
    ClassDB::bind_method(D_METHOD("get_last_residual_fraction"), &Cylinder::get_last_residual_fraction);
    ClassDB::bind_method(D_METHOD("get_last_imep"), &Cylinder::get_last_imep);
}

float Cylinder::volume(float phi_deg) const {
    float angle = Math::deg_to_rad(phi_deg);
    float crank_radius = stroke * 0.5f;
    float rod_length = rod_ratio * crank_radius;
    float crank_offset = crank_radius * std::sin(angle);
    float displacement = crank_radius * (1.0f - std::cos(angle)) + rod_length - std::sqrt(rod_length * rod_length - crank_offset * crank_offset);
    return clearance + piston_area * displacement;
}

float Cylinder::lift(float phi_deg, float open_deg, float close_deg, float peak) {
    float p = Math::fposmod(phi_deg, 720.0f);
    if (p < open_deg || p > close_deg) return 0.0f;
    return peak * std::sin(Math::PI * (p - open_deg) / (close_deg - open_deg));
}

float Cylinder::mass_flow(float area, float p1, float t1, float p2, float t2) {
    if (area <= 0.0f) return 0.0f;
    if (p1 >= p2) return _subsonic(area, p1, t1, p2);
    return -_subsonic(area, p2, t2, p1);
}

float Cylinder::_subsonic(float area, float p_up, float t_up, float p_down) {
    float pr = p_down / p_up;
    float k = CD_VALVE * area * p_up / std::sqrt(R * t_up);
    float crit = std::pow(2.0f / (G + 1.0f), G / (G - 1.0f));
    if (pr <= crit) {
        return k * std::sqrt(G * std::pow(2.0f / (G + 1.0f), (G + 1.0f) / (G - 1.0f)));
    }
    return k * std::sqrt(2.0f * G / (G - 1.0f) * (std::pow(pr, 2.0f / G) - std::pow(pr, (G + 1.0f) / G)));
}

void Cylinder::setup(float bore_mm, float stroke_mm, float compression_ratio, float recip_kg, float rod_lambda) {
    bore = bore_mm * 0.001f;
    piston_area = Math::PI * bore * bore / 4.0f;
    stroke = stroke_mm * 0.001f;
    swept = piston_area * stroke;
    recip_kg = recip_kg;
    rod_ratio = rod_lambda;
    clearance = swept / (compression_ratio - 1.0f);
    pressure = P0;
    temp = T0;
    mass = pressure * (clearance + swept) / (R * temp);
    _u = mass * CV * temp;
    phi = 0.0f;
    port_p = P0;
    runner_q = 0.0f;
    _exhaust_flow_cycle.resize(EXHAUST_FLOW_BINS);
    _exhaust_flow_cycle.fill(0.0f);
}

void Cylinder::set_cams(const EngineSpec *spec) {
    intake_open = spec->intake_open_deg();
    intake_close = spec->intake_close_deg();
    exhaust_open = spec->exhaust_open_deg();
    exhaust_close = spec->exhaust_close_deg();
    intake_lift = spec->intake_lift_mm * 0.001f;
    exhaust_lift = spec->exhaust_lift_mm * 0.001f;
    intake_valve_d = spec->intake_valve_mm * 0.001f;
    exhaust_valve_d = spec->exhaust_valve_mm * 0.001f;
    runner_length = spec->runner_length_m;
    wall_heat_scale = spec->wall_heat_scale;

    _intake_profile = spec->intake_lobe_profile >= 0 ? spec->intake_lobe_profile : spec->cam_lobe_profile;
    _exhaust_profile = spec->exhaust_lobe_profile >= 0 ? spec->exhaust_lobe_profile : spec->cam_lobe_profile;
    _intake_lift_curve = spec->intake_lift_curve;
    _exhaust_lift_curve = spec->exhaust_lift_curve;
    _intake_flat_frac = spec->intake_flat_fraction;
    _exhaust_flat_frac = spec->exhaust_flat_fraction;
    _intake_open_ramp = spec->intake_open_ramp_deg;
    _intake_close_ramp = spec->intake_close_ramp_deg;
    _exhaust_open_ramp = spec->exhaust_open_ramp_deg;
    _exhaust_close_ramp = spec->exhaust_close_ramp_deg;
    _intake_duration_050 = spec->intake_duration_050_deg;
    _exhaust_duration_050 = spec->exhaust_duration_050_deg;
    valve_cd = spec->valve_cd;
}

void Cylinder::start_at(float phase_deg) {
    phi = Math::fposmod(phase_deg, 720.0f);
    mass = pressure * volume(phi) / (R * temp);
    _u = mass * CV * temp;
}

float Cylinder::_lift(float phi_deg, float open_deg, float close_deg, float peak,
                      int profile, const Array &lift_curve, float flat_frac,
                      float open_ramp_deg, float close_ramp_deg, float duration_050) const {
    return lobe_lift(phi_deg, open_deg, close_deg, peak, profile, lift_curve, open_ramp_deg, close_ramp_deg, duration_050);
}

float Cylinder::exhaust_valve_area(float phase_deg) const {
    float lift_m = _lift(phase_deg, exhaust_open, exhaust_close, exhaust_lift,
                         _exhaust_profile, _exhaust_lift_curve, _exhaust_flat_frac,
                         _exhaust_open_ramp, _exhaust_close_ramp, _exhaust_duration_050);
    return std::min(2.0f * Math::PI * exhaust_valve_d * lift_m, EXHAUST_PORT_AREA);
}

float Cylinder::_intake_area(float phase_deg) const {
    float lift_m = _lift(phase_deg, intake_open, intake_close, intake_lift,
                         _intake_profile, _intake_lift_curve, _intake_flat_frac,
                         _intake_open_ramp, _intake_close_ramp, _intake_duration_050);
    return std::min(2.0f * Math::PI * intake_valve_d * lift_m, INTAKE_PORT_AREA);
}

int Cylinder::_flow_steps(float dphi, float dt, float pm, float tm, float p_ex, float t_ex) const {
    int steps = std::max(1, std::max(int(std::ceil(std::abs(dphi) / STEP_DEG)), int(std::ceil(dt / MAX_FLOW_DT))));
    if (dt <= 0.0f || mass < 1e-7f) return steps;

    float mid = phi + dphi * 0.5f;
    float end = phi + dphi;
    float cd = valve_cd / CD_VALVE;
    float ex_area = std::max(exhaust_valve_area(phi), std::max(exhaust_valve_area(phi + dphi * 0.5f), exhaust_valve_area(phi + dphi)));
    float in_area = std::max(_intake_area(phi), std::max(_intake_area(phi + dphi * 0.5f), _intake_area(phi + dphi)));
    ex_area *= cd;
    in_area *= cd;

    int finer = steps;
    float mdot = std::abs(mass_flow(ex_area, std::max(pressure, p_ex), std::max(temp, 250.0f), std::min(pressure, p_ex), t_ex));
    mdot = std::max(mdot, std::abs(mass_flow(in_area, std::max(port_p, pm), std::max(tm, 250.0f), std::min(pressure, pm), temp)));
    float cap = 0.1f * mass;
    if (mdot * dt > cap * float(finer)) {
        finer = std::max(finer, int(std::ceil(mdot * dt / cap)));
    }

    float opening = std::max(ex_area, in_area);
    if (opening > 0.0f) {
        float volume = mass * R * std::max(temp, 250.0f) / std::max(pressure, 1000.0f);
        float wave = std::sqrt(G * R * std::max(temp, 250.0f));
        float dt_ok = 0.2f * volume / (opening * wave);
        if (dt_ok > 0.0f) {
            finer = std::max(finer, int(std::ceil(dt / dt_ok)));
        }
    }
    return std::min(finer, std::max(steps, 24));
}

float Cylinder::_intake_area(float phase_deg) const {
    float lift_m = _lift(phase_deg, intake_open, intake_close, intake_lift,
                         _intake_profile, _intake_lift_curve, _intake_flat_frac,
                         _intake_open_ramp, _intake_close_ramp, _intake_duration_050);
    return std::min(2.0f * Math::PI * intake_valve_d * lift_m, INTAKE_PORT_AREA);
}

void Cylinder::_fuel_charge(FuelTank *tank, float lambda, bool spark, bool limiter_cut, float pm) {
    burn_energy = 0.0f;
    burn_energy_left = 0.0f;
    last_lambda = 1.0f;

    if (limiter_cut) return;
    if (lambda >= MISFIRE_LAMBDA) return;

    float fresh = std::max(mass - _residual_kg, 0.0f);
    float wanted = fresh / (tank->afr * lambda);
    float supplied = std::min(wanted, tank->mass_kg);
    tank->mass_kg -= supplied;
    mass += supplied;
    _u += supplied * CV * temp;

    if (!spark) {
        fuel_unburnt_kg = supplied;
        return;
    }

    fuel_unburnt_kg = 0.0f;
    if (supplied > 0.0f) {
        last_lambda = fresh / (tank->afr * supplied);
    }

    float burnable = std::min(supplied, fresh / tank->afr);
    burn_energy = burnable * tank->lhv * COMBUSTION_EFFICIENCY;
    burn_energy_left = burn_energy;
    _fired = supplied > 0.0f;
}

float Cylinder::_wiebe(float rel, float burn_deg) const {
    return 1.0f - std::exp(-WIEBE_A * std::pow(std::clamp(rel / burn_deg, 0.0f, 1.0f), WIEBE_M + 1.0f));
}

bool Cylinder::_crossed(float a, float b, float at) {
    return std::floor((b - at) / 720.0f) > std::floor((a - at) / 720.0f);
}

bool Cylinder::_in_window(float p, float start, float length) {
    float rel = Math::fposmod(p - start + 720.0f, 720.0f);
    return rel < length;
}

Vector2 Cylinder::advance(float dphi, float dt, float pm, float tm, float ign_phi, bool firing,
                          FuelTank *tank, float lambda, bool spark, bool limiter_cut,
                          float p_ex, float t_ex) {
    int steps = _flow_steps(dphi, dt, pm, tm, p_ex, t_ex);
    float sd = dphi / steps;
    float sdt = dt / steps;
    float work = 0.0f;
    float theta = 0.0f;
    float drawn = 0.0f;
    float w = dt > 0.0f ? Math::deg_to_rad(dphi) / dt : 0.0f;
    float crank_r = stroke * 0.5f;
    float burn_deg = burn_duration_deg(w * 60.0f / Math::TAU);

    _exhaust_flow_cycle.fill(0.0f);

    for (int i = 0; i < steps; i++) {
        float p0 = phi;
        float p1 = phi + sd;
        float dv = volume(p1) - volume(p0);

        if (_crossed(p0, p1, intake_open)) {
            _close_cycle();
            last_peak_temp = peak_temp;
            peak_temp = temp;
            _burnt = 0.0f;
        }

        float v_run = runner_q / (RUNNER_AREA * 1.2f);
        runner_q += RUNNER_AREA / runner_length * (pm - port_p - 0.5f * RUNNER_LOSS * 1.2f * v_run * std::abs(v_run)) * sdt;

        float in_lift = _lift(p0, intake_open, intake_close, intake_lift,
                              _intake_profile, _intake_lift_curve, _intake_flat_frac,
                              _intake_open_ramp, _intake_close_ramp, _intake_duration_050);
        float in_area_val = std::min(2.0f * Math::PI * intake_valve_d * in_lift, INTAKE_PORT_AREA) * valve_cd / CD_VALVE;
        float m_in = mass_flow(in_area_val, port_p, tm, pressure, temp) * sdt;

        port_p = std::clamp(port_p + R * tm / PORT_VOLUME * (runner_q * sdt - m_in), 1000.0f, 3.0f * P0);

        float ex_lift = _lift(p0, exhaust_open, exhaust_close, exhaust_lift,
                              _exhaust_profile, _exhaust_lift_curve, _exhaust_flat_frac,
                              _exhaust_open_ramp, _exhaust_close_ramp, _exhaust_duration_050);
        float ex_area_val = std::min(2.0f * Math::PI * exhaust_valve_d * ex_lift, EXHAUST_PORT_AREA) * valve_cd / CD_VALVE;
        float m_out = mass_flow(ex_area_val, pressure, temp, p_ex, t_ex) * sdt;

        if (m_in < 0.0f && _lift(p0, exhaust_open, exhaust_close, exhaust_lift,
                                  _exhaust_profile, _exhaust_lift_curve, _exhaust_flat_frac,
                                  _exhaust_open_ramp, _exhaust_close_ramp, _exhaust_duration_050) > 0.0f) {
            _overlap_out -= m_in;
        }

        port_p = std::clamp(port_p + R * tm / PORT_VOLUME * (runner_q * sdt - m_in), 1000.0f, 3.0f * P0);

        if (_crossed(p0, p1, exhaust_open)) {
            if (fuel_unburnt_kg > 0.0f) {
                if (_port_heat > AUTO_IGNITE_K) {
                    backfire_j += fuel_unburnt_kg * tank->lhv * BACKFIRE_BURN;
                }
                _port_heat = T0;
                fuel_unburnt_kg = 0.0f;
            }
            if (_fired) {
                exhaust_temp = temp;
                _port_heat = temp;
            }
        }
        if (_crossed(p0, p1, exhaust_close)) {
            _residual_kg = mass;
        }

        if (_crossed(p0, p1, intake_close)) {
            _fired = false;
            if (firing) {
                _fuel_charge(tank, lambda, spark, limiter_cut, pm);
            }
        }

        float dq = 0.0f;
        if (spark && burn_energy_left > 0.0f && _in_window(p0, ign_phi, burn_deg)) {
            float rel = Math::fposmod(p0 - ign_phi + 720.0f, 720.0f);
            dq = std::min(burn_energy_left, burn_energy * (_wiebe(rel + sd, burn_deg) - _wiebe(rel, burn_deg)));
            burn_energy_left -= dq;
            _burnt = 1.0f - burn_energy_left / burn_energy;
        }

        float liner = (volume(p1) - clearance) / piston_area;
        float wall_area = 2.0f * piston_area + Math::PI * bore * std::max(liner, 0.0f);
        float h_wall = WALL_HEAT * wall_heat_scale * std::pow(std::max(w, 1.0f) / WALL_REF_W, 0.8f);
        float q_loss = h_wall * wall_area * (temp - WALL_TEMP) * sdt;
        wall_loss_j += q_loss;

        float cv = CV + _burnt * (CV_BURNT - CV);
        float cp = cv + R;
        float h_in = cp * (m_in >= 0.0f ? tm : temp) * m_in;
        enthalpy_in_j += h_in;
        float h_ex = cp * (m_out >= 0.0f ? temp : t_ex) * m_out;
        enthalpy_out_j += h_ex;

        float u = _u - pressure * dv + dq + h_in - h_ex - q_loss;
        mass = std::max(mass + m_in - m_out, 1e-12f);
        temp = std::clamp(u / (mass * cv), 200.0f, 4000.0f);
        _u = mass * cv * temp;
        peak_temp = std::max(peak_temp, temp);
        pressure = std::clamp(mass * R * temp / volume(p1), 1000.0f, 1.0e7f);

        if (sd > 0.0f && _cycle_deg > 0.0f) {
            _cycle_max_dp = std::max(_cycle_max_dp, (pressure - _cycle_p) / sd);
        }
        _cycle_p = pressure;
        _cycle_peak_p = std::max(_cycle_peak_p, pressure);
        _cycle_work += pressure * dv;
        _cycle_deg += sd;

        if (sdt > 0.0f) {
            int first_bin = int(std::floor(p0 * EXHAUST_FLOW_BINS / 720.0f));
            int last_bin = int(std::floor(p1 * EXHAUST_FLOW_BINS / 720.0f));
            for (int bin_index = first_bin; bin_index <= last_bin; bin_index++) {
                _exhaust_flow_cycle[Math::posmod(bin_index, EXHAUST_FLOW_BINS)] = m_out / sdt;
            }
        }

        float dtheta = sd * Math::PI / 180.0f;
        work += (pressure - P0) * dv;

        float phi_r = Math::deg_to_rad(p0);
        float accel_term = std::cos(phi_r) + std::cos(2.0f * phi_r) / rod_ratio;
        work -= recip_kg * crank_r * crank_r * w * w * accel_term * std::sin(phi_r) * dtheta;

        theta += dtheta;
        drawn += runner_q * sdt;
        phi = p1;
    }
    return Vector2(theta > 0.0f ? work / theta : 0.0f, drawn);
}

float Cylinder::burn_duration_deg(float rpm) {
    return BURN_DEG_BASE + BURN_DEG_PER_RPM * rpm;
}

float Cylinder::_lift(float phi_deg, float open_deg, float close_deg, float peak,
                      int profile, const Array &lift_curve, float flat_frac,
                      float open_ramp_deg, float close_ramp_deg, float duration_050) const {
    return lobe_lift(phi_deg, open_deg, close_deg, peak, profile, lift_curve, open_ramp_deg, close_ramp_deg, duration_050);
}

float Cylinder::lobe_lift(float phi_deg, float open_deg, float close_deg, float peak,
                          int profile, const Array &lift_curve, float open_ramp_deg, float close_ramp_deg, float duration_050) {
    float p = Math::fposmod(phi_deg, 720.0f);
    if (profile == EngineSpec::CamLobeProfile::CUSTOM) {
        return _curve_lift(lift_curve, p);
    }
    if (p < open_deg || p > close_deg || close_deg <= open_deg || peak <= 0.0f) return 0.0f;
    float seat = close_deg - open_deg;
    if (profile == EngineSpec::CamLobeProfile::HALF_SINE) {
        return peak * std::sin(Math::PI * (p - open_deg) / seat);
    }
    Vector2 ramps = seat_ramps(seat, duration_050, open_ramp_deg, close_ramp_deg);
    float check_open = open_deg + ramps.x;
    float check_close = close_deg - ramps.y;
    float check_m = std::min(CHECK_LIFT_M, peak * 0.5f);
    if (ramps.x > 0.05f && p < check_open) {
        return check_m * (p - open_deg) / ramps.x;
    }
    if (ramps.y > 0.05f && p > check_close) {
        return check_m * (close_deg - p) / ramps.y;
    }
    float half = std::max((check_close - check_open) * 0.5f, 0.5f);
    float centre = (check_open + check_close) * 0.5f;
    float cos_arg = std::clamp(2.0f * check_m / peak - 1.0f, -1.0f, 1.0f);
    float omega = std::acos(cos_arg) / half;
    return peak * 0.5f * (std::cos(omega * (p - centre)) + 1.0f);
}

Vector2 Cylinder::seat_ramps(float seat_deg, float duration_050, float open_ramp, float close_ramp) {
    if (open_ramp > 0.0f || close_ramp > 0.0f) {
        float opening = open_ramp > 0.0f ? open_ramp : close_ramp;
        float closing = close_ramp > 0.0f ? close_ramp : open_ramp;
        float cap = seat_deg * 0.45f;
        return Vector2(std::min(opening, cap), std::min(closing, cap));
    }
    float at_050 = duration_050 > 0.0f ? duration_050 : seat_deg / SEAT_OVER_050;
    at_050 = std::clamp(at_050, seat_deg * 0.5f, seat_deg);
    float ramp = (seat_deg - at_050) * 0.5f;
    return Vector2(ramp, ramp);
}

float Cylinder::_curve_lift(const Array &curve, float deg) const {
    if (curve.size() < 2) return 0.0f;
    for (int i = 0; i < curve.size() - 1; i++) {
        float d1 = float(curve[i][0]);
        float d2 = float(curve[i + 1][0]);
        if (deg >= d1 && deg <= d2) {
            float span = d2 - d1;
            if (span <= 0.0f) return float(curve[i][1]) * 0.001f;
            float t = (deg - d1) / span;
            return Math::lerpf(float(curve[i][1]), float(curve[i + 1][1]), t) * 0.001f;
        }
    }
    return 0.0f;
}

void Cylinder::_close_cycle() {
    last_peak_temp = peak_temp;
    peak_temp = temp;
    _burnt = 0.0f;
    _cycle_max_dp = 0.0f;
    _cycle_p = pressure;
    _cycle_peak_p = 0.0f;
    _cycle_work = 0.0f;
    _cycle_deg = 0.0f;
}

} // namespace engine_sim