#include "exhaust_gas.h"
#include "exhaust_layout.h"
#include <godot_cpp/variant/utility_functions.hpp>
#include <cmath>
#include <algorithm>

namespace engine_sim {

using namespace godot;

void ExhaustGas::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build", "layout"), &ExhaustGas::build);
    ClassDB::bind_method(D_METHOD("port_pressure", "cylinder_index"), &ExhaustGas::port_pressure);
    ClassDB::bind_method(D_METHOD("port_temperature", "cylinder_index"), &ExhaustGas::port_temperature);
    ClassDB::bind_method(D_METHOD("apply_valve", "cylinder_index", "mdot", "power"), &ExhaustGas::apply_valve);
    ClassDB::bind_method(D_METHOD("add_energy", "cylinder_index", "joules"), &ExhaustGas::add_energy);
    ClassDB::bind_method(D_METHOD("station_pressure", "pipe_index"), &ExhaustGas::station_pressure);
    ClassDB::bind_method(D_METHOD("tail_volume_flow"), &ExhaustGas::tail_volume_flow);
    ClassDB::bind_method(D_METHOD("take_flow"), &ExhaustGas::take_flow);
    ClassDB::bind_method(D_METHOD("advance", "dt"), &ExhaustGas::advance);

    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "record_audio"), "", "record_audio");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "exhaust_solver"), "", "exhaust_solver");
}

float ExhaustGas::_ambient_sound_speed() {
    return std::sqrt(GAMMA * R * T0);
}

void ExhaustGas::build(const ExhaustLayout *layout) {
    if (!layout) return;

    _npipes = layout->pipes.size();
    _pipe0.resize(_npipes);
    _pipe_n.resize(_npipes);
    _parent.resize(_npipes);
    _parent.fill(-1);
    _feeders.clear();
    _feeders.resize(_npipes);
    _cyl_pipe.resize(16);
    _cyl_pipe.fill(-1);

    std::vector<int> counts;
    std::vector<float> areas;
    std::vector<float> losses;
    std::vector<float> dxs;

    for (int i = 0; i < _npipes; i++) {
        const ExhaustLayout::Pipe *pipe = layout->pipes[i];
        float length = std::max(pipe->length_m(), CELL_M);
        int count = std::max(1, int(std::round(length / CELL_M)));
        float dx = length / float(count);
        counts.push_back(count);
        dxs.push_back(dx);
        losses.push_back(pipe->loss);
        _feeders[i] = pipe->feeders;
        for (int f : pipe->feeders) {
            _parent[f] = i;
        }
        if (pipe->cyl >= 0 && pipe->cyl < (int)_cyl_pipe.size()) {
            _cyl_pipe[pipe->cyl] = i;
        }
        for (int c = 0; c < count; c++) {
            areas.push_back(_area_at(pipe, (float(c) + 0.5f) * dx));
        }
    }

    int total = 0;
    for (int i = 0; i < _npipes; i++) {
        _pipe0[i] = total;
        _pipe_n[i] = counts[i];
        total += counts[i];
    }
    _n = total;

    _area.resize(total);
    _dx.resize(total);
    _loss.resize(total);

    int at = 0;
    for (int i = 0; i < _npipes; i++) {
        for (int c = 0; c < counts[i]; c++) {
            _area[at] = areas[at];
            _dx[at] = dxs[i];
            _loss[at] = losses[i];
            at++;
        }
    }

    _rho.resize(total);
    _ru.resize(total);
    _re.resize(total);

    float rho0 = P0 / (R * T0);
    float e0 = P0 / ((GAMMA - 1.0f) * rho0);

    for (int i = 0; i < total; i++) {
        _rho[i] = rho0;
        _ru[i] = 0.0f;
        _re[i] = rho0 * e0;
    }

    _mdot.resize(16);
    _power.resize(16);
    _mdot.fill(0.0f);
    _power.fill(0.0f);
    _flow = PackedFloat32Array();
    _d_rho.resize(total);
    _d_ru.resize(total);
    _d_re.resize(total);
    _min_dx = CELL_M;
    for (int i = 0; i < total; i++) {
        _min_dx = std::min(_min_dx, _dx[i]);
    }
    _cfl_dt = CFL * _min_dx / (_ambient_sound_speed() + 1.0f);
    _audio_left = 0.0f;

    _build_faces();
}

int ExhaustGas::_port_cell(int cylinder_index) const {
    if (cylinder_index < 0 || cylinder_index >= (int)_cyl_pipe.size()) return -1;
    int pipe = _cyl_pipe[cylinder_index];
    if (pipe < 0) return -1;
    return _pipe0[pipe];
}

float ExhaustGas::_area_at(const ExhaustLayout::Pipe *pipe, float dist_m) const {
    float dist = dist_m * ExhaustLayout::M;
    float walked = 0.0f;
    int n = pipe->pts.size();
    if (n < 2) return std::max(pipe->area_m2(), 1.0e-6f);
    for (int i = 0; i < n - 1; i++) {
        float seg = pipe->pts[i].distance_to(pipe->pts[i + 1]);
        if (walked + seg >= dist || i == n - 2) {
            float t = std::clamp((dist - walked) / std::max(seg, 1.0e-6f), 0.0f, 1.0f);
            float radius = std::lerp(pipe->radii[i], pipe->radii[i + 1], t) / ExhaustLayout::M;
            return std::max(Math::PI * radius * radius, 1.0e-6f);
        }
        walked += seg;
    }
    return std::max(pipe->area_m2(), 1.0e-6f);
}

float ExhaustGas::_pressure(int cell) const {
    float u = _velocity(cell);
    float internal = _re[cell] / std::max(_rho[cell], 1.0e-6f) - 0.5f * u * u;
    return std::max((GAMMA - 1.0f) * _rho[cell] * internal, 200.0f);
}

float ExhaustGas::_velocity(int cell) const {
    return _ru[cell] / std::max(_rho[cell], 1.0e-6f);
}

float ExhaustGas::_sound(int cell) const {
    return _sound_of(_rho[cell], _pressure(cell));
}

float ExhaustGas::_sound_of(float rho, float p) const {
    return std::sqrt(GAMMA * p / std::max(rho, 1.0e-6f));
}

void ExhaustGas::_clamp_cell(int cell) {
    _rho[cell] = std::clamp(_rho[cell], 0.02f, 40.0f);
    float u = std::clamp(_velocity(cell), -800.0f, 800.0f);
    float ke = 0.5f * u * u;
    float internal = _re[cell] / std::max(_rho[cell], 1.0e-6f) - ke;
    internal = std::clamp(internal, R / (GAMMA - 1.0f) * 200.0f, R / (GAMMA - 1.0f) * 3500.0f);
    _ru[cell] = _rho[cell] * u;
    _re[cell] = _rho[cell] * (internal + ke);
}

void ExhaustGas::_build_faces() {
    std::vector<int> lefts, rights;
    std::vector<float> scale_l, scale_r;
    std::vector<int> kinds;

    for (int pipe = 0; pipe < _npipes; pipe++) {
        int a0 = _pipe0[pipe];
        int count = _pipe_n[pipe];
        for (int i = 0; i < count - 1; i++) {
            int left = a0 + i;
            int right = a0 + i + 1;
            float face_area = std::min(_area[left], _area[right]);
            lefts.push_back(left);
            rights.push_back(right);
            scale_l.push_back(-face_area / (_area[left] * _dx[left]));
            scale_r.push_back(face_area / (_area[right] * _dx[right]));
            kinds.push_back(0);
        }
        if (_parent[pipe] < 0) {
            int last = a0 + count - 1;
            lefts.push_back(last);
            rights.push_back(last);
            scale_l.push_back(-1.0f / _dx[last]);
            scale_r.push_back(0.0f);
            kinds.push_back(2); // open tail
        }
        if (_feeders[pipe].size() == 0) {
            lefts.push_back(a0);
            rights.push_back(a0);
            scale_l.push_back(1.0f / _dx[a0]);
            scale_r.push_back(0.0f);
            kinds.push_back(1); // closed valve
        }
    }

    _fl = PackedInt32Array(lefts);
    _fr = PackedInt32Array(rights);
    _sl = PackedFloat32Array(scale_l);
    _sr = PackedFloat32Array(scale_r);
    _fk = PackedByteArray(kinds);
    _nf = lefts.size();
}

void ExhaustGas::_step(float h) {
    // Clear derivatives
    _d_rho.fill(0.0f);
    _d_ru.fill(0.0f);
    _d_re.fill(0.0f);

    // Internal faces (internal to pipes)
    for (int pipe = 0; pipe < _npipes; pipe++) {
        int a0 = _pipe0[pipe];
        int count = _pipe_n[pipe];
        for (int i = 0; i < count - 1; i++) {
            Vector3 flux = _face(a0 + i, a0 + i + 1);
            _add_cell(a0 + i, flux, h, -1.0f);
            _add_cell(a0 + i + 1, flux, h, 1.0f);
        }
    }

    // Tail and valve faces
    for (int pipe = 0; pipe < _npipes; pipe++) {
        int a0 = _pipe0[pipe];
        int count = _pipe_n[pipe];

        if (_parent[pipe] < 0) {
            // Open tail
            int last = a0 + count - 1;
            Vector3 flux_tail = _open_face(last);
            _add_cell(last, flux_tail, h, -1.0f);
        }
        if (_feeders[pipe].size() == 0) {
            // Closed valve
            Vector3 flux_wall = _wall_face(a0);
            _add_cell(a0, flux_wall, h, 1.0f);
        }
    }

    // Junctions: feeders -> pipe
    for (int pipe = 0; pipe < _npipes; pipe++) {
        const PackedInt32Array &feeders = _feeders[pipe];
        if (feeders.size() == 0) continue;
        int into = _pipe0[pipe];
        for (int f : feeders) {
            int last = _pipe0[f] + _pipe_n[f] - 1;
            Vector3 flux = _face(last, into);
            float scale = _area[last] / std::max(_area[into], 1.0e-8f);
            _add_cell(last, flux, h, -1.0f);
            _add_cell_scaled(into, flux, h, scale);
        }
    }

    // Valve sources
    for (int cyl = 0; cyl < (int)_mdot.size(); cyl++) {
        int cell = _port_cell(cyl);
        if (cell < 0) continue;
        float volume = _area[cell] * _dx[cell];
        _d_rho[cell] += _mdot[cyl] * h / volume;
        _d_re[cell] += _power[cyl] * h / volume;
        float inflow = _mdot[cyl] / std::max(_rho[cell] * _area[cell], 1.0e-8f);
        _d_ru[cell] += _mdot[cyl] * inflow * h / volume;
    }

    // Friction and clamping
    for (int i = 0; i < _n; i++) {
        _friction(i, h);
        _clamp_cell(i);
    }

    // Apply
    for (int i = 0; i < _n; i++) {
        _rho[i] += _d_rho[i];
        _ru[i] += _d_ru[i];
        _re[i] += _d_re[i];
    }
}

void ExhaustGas::_add_cell(int cell, const Vector3 &flux, float h, float sign) {
    float scale = sign * h / _dx[cell];
    _d_rho[cell] += scale * flux.x;
    _d_ru[cell] += scale * flux.y;
    _d_re[cell] += scale * flux.z;
}

void ExhaustGas::_add_cell_scaled(int cell, const Vector3 &flux, float h, float area_ratio) {
    float scale = area_ratio * h / _dx[cell];
    _d_rho[cell] += scale * flux.x;
    _d_ru[cell] += scale * flux.y;
    _d_re[cell] += scale * flux.z;
}

Vector3 ExhaustGas::_flux(float rho, float u, float p) const {
    float e = p / (GAMMA - 1.0f) + 0.5f * rho * u * u;
    float h = (e + p) / std::max(rho, 1.0e-8f);
    return Vector3(rho * u, rho * u * u + p, rho * u * h);
}

Vector3 ExhaustGas::_rusanov(float r_l, float u_l, float p_l, float r_r, float u_r, float p_r) const {
    Vector3 f_l = _flux(r_l, u_l, p_l);
    Vector3 f_r = _flux(r_r, u_r, p_r);
    float s = std::max(std::abs(u_l) + _sound_of(r_l, p_l), std::abs(u_r) + _sound_of(r_r, p_r));
    float e_l = p_l / (GAMMA - 1.0f) + 0.5f * r_l * u_l * u_l;
    float e_r = p_r / (GAMMA - 1.0f) + 0.5f * r_r * u_r * u_r;
    return Vector3(
        0.5f * (f_l.x + f_r.x) - 0.5f * s * (r_r - r_l),
        0.5f * (f_l.y + f_r.y) - 0.5f * s * (r_r * u_r - r_l * u_l),
        0.5f * (f_l.z + f_r.z) - 0.5f * s * (e_r - e_l)
    );
}

Vector3 ExhaustGas::_face(int left, int right) const {
    return _rusanov(_rho[left], _velocity(left), _pressure(left),
                    _rho[right], _velocity(right), _pressure(right));
}

Vector3 ExhaustGas::_wall_face(int cell) const {
    float u = _velocity(cell);
    return _rusanov(_rho[cell], -u, _pressure(cell),
                    _rho[cell], u, _pressure(cell));
}

Vector3 ExhaustGas::_open_face(int cell) const {
    float u = _velocity(cell);
    float rho = _rho[cell];
    float p = _pressure(cell);
    if (u >= 0.0f) {
        // Outflow: subsonic to ambient
        return _rusanov(rho, u, p, rho, u, P0);
    }
    // Inflow from ambient
    float rho_in = P0 / (R * T0);
    return _rusanov(rho, u, p, rho_in, u, P0);
}

void ExhaustGas::_friction(int cell, float dt) {
    float u = _velocity(cell);
    float cut = std::clamp(_loss[cell] * std::abs(u) * dt, 0.0f, 0.5f);
    _ru[cell] = _rho[cell] * u * (1.0f - cut);
}

void ExhaustGas::_clamp_cell(int cell) {
    _rho[cell] = std::clamp(_rho[cell], 0.02f, 40.0f);
    float u = std::clamp(_velocity(cell), -800.0f, 800.0f);
    float ke = 0.5f * u * u;
    float internal = _re[cell] / std::max(_rho[cell], 1.0e-6f) - ke;
    internal = std::clamp(internal, R / (GAMMA - 1.0f) * 200.0f, R / (GAMMA - 1.0f) * 3500.0f);
    _ru[cell] = _rho[cell] * u;
    _re[cell] = _rho[cell] * (internal + ke);
}

// Public interface
void ExhaustGas::build(const ExhaustLayout *layout) {
    build(layout);
}

float ExhaustGas::port_pressure(int cylinder_index) const {
    int cell = _port_cell(cylinder_index);
    if (cell < 0) return P0;
    return _pressure(cell);
}

float ExhaustGas::port_temperature(int cylinder_index) const {
    int cell = _port_cell(cylinder_index);
    if (cell < 0) return T0;
    return _pressure(cell) / (std::max(_rho[cell], 1.0e-6f) * R);
}

void ExhaustGas::apply_valve(int cylinder_index, float mdot, float power) {
    if (cylinder_index < 0 || cylinder_index >= (int)_mdot.size()) return;
    _mdot[cylinder_index] = mdot;
    _power[cylinder_index] = power;
}

void ExhaustGas::add_energy(int cylinder_index, float joules) {
    int cell = _port_cell(cylinder_index);
    if (cell < 0 || joules == 0.0f) return;
    float volume = _area[cell] * _dx[cell];
    _re[cell] += joules / std::max(volume, 1.0e-8f);
    _clamp_cell(cell);
}

float ExhaustGas::station_pressure(int pipe_index) const {
    if (pipe_index < 0 || pipe_index >= _npipes) return P0;
    return _pressure(_pipe0[pipe_index]);
}

float ExhaustGas::tail_volume_flow() const {
    if (_n <= 0) return 0.0f;
    int last = _n - 1;
    return _velocity(last) * _area[last];
}

PackedFloat32Array ExhaustGas::take_flow() {
    PackedFloat32Array out = _flow;
    _flow = PackedFloat32Array();
    return out;
}

void ExhaustGas::advance(float dt) {
    if (_n <= 0 || dt <= 0.0f) return;
    float remain = dt;
    int guard = 0;
    while (remain > 1.0e-8f && guard < 8000) {
        guard++;
        float h = std::min(_cfl_dt, remain);
        _step(h);
        if (record_audio) {
            _audio_left += h;
            float q = tail_volume_flow();
            float sample = 1.0f / AUDIO_RATE;
            int extra = int(_audio_left / sample);
            if (extra > 0) {
                int base = _flow.size();
                _flow.resize(base + extra);
                for (int i = 0; i < extra; i++) {
                    _flow[base + i] = q;
                }
                _audio_left -= float(extra) * sample;
                if (_flow.size() > 88200) {
                    _flow = PackedFloat32Array();
                }
            }
        }
        remain -= h;
    }
}

// PackedFloat32Array interface
int ExhaustGas::_port_cell(int cylinder_index) const {
    if (cylinder_index < 0 || cylinder_index >= (int)_cyl_pipe.size()) return -1;
    int pipe = _cyl_pipe[cylinder_index];
    if (pipe < 0) return -1;
    return _pipe0[pipe];
}

} // namespace engine_sim