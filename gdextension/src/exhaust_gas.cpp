#include "exhaust_gas.h"

#include <algorithm>
#include <cmath>

namespace engine_sim {

namespace {

constexpr double PI_D = 3.14159265358979323846;
constexpr int CYLINDERS = 16;
constexpr int FLOW_BUFFER_SAMPLES = 88200; // 2 s at 44.1 kHz

inline double maxd(double a, double b) { return a > b ? a : b; }
inline double mind(double a, double b) { return a < b ? a : b; }
inline double clampd(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline double lerpd(double a, double b, double t) { return a + (b - a) * t; }

inline double segment_length(const ExhaustPoint &a, const ExhaustPoint &b) {
    double dx = double(a.x) - double(b.x);
    double dy = double(a.y) - double(b.y);
    double dz = double(a.z) - double(b.z);
    return std::sqrt(dx * dx + dy * dy + dz * dz);
}

} // namespace

double ExhaustPipe::length_m(double scene_per_m) const {
    double total = 0.0;
    for (size_t i = 0; i + 1 < pts.size(); i++) {
        total += segment_length(pts[i], pts[i + 1]);
    }
    return total / scene_per_m;
}

// Mean cross-section, weighted by length (a cone averages r1^2 + r1*r2 + r2^2).
double ExhaustPipe::area_m2(double scene_per_m) const {
    double sum = 0.0;
    double len_sum = 0.0;
    for (size_t i = 0; i + 1 < pts.size(); i++) {
        double seg = segment_length(pts[i], pts[i + 1]);
        double r1 = double(radii[i]) / scene_per_m;
        double r2 = double(radii[i + 1]) / scene_per_m;
        sum += seg * (r1 * r1 + r1 * r2 + r2 * r2) / 3.0;
        len_sum += seg;
    }
    return PI_D * sum / maxd(len_sum, 1e-9);
}

double ExhaustGas::ambient_sound_speed() {
    return std::sqrt(GAMMA * R * T0);
}

void ExhaustGas::build(const ExhaustLayoutData &layout) {
    _flow.clear(); // GDScript resizes then clears this in build; the buffer is allocated on the first advance
    _scene_per_m = layout.scene_per_m;
    _npipes = int(layout.pipes.size());
    _pipe0.assign(_npipes, 0);
    _pipe_n.assign(_npipes, 0);
    _parent.assign(_npipes, -1);
    _feeders.assign(_npipes, std::vector<int>());
    _cyl_pipe.assign(CYLINDERS, -1);

    std::vector<int> counts;
    std::vector<double> areas;
    std::vector<double> losses;
    std::vector<double> dxs;
    for (int i = 0; i < _npipes; i++) {
        const ExhaustPipe &pipe = layout.pipes[i];
        double length = maxd(pipe.length_m(_scene_per_m), CELL_M);
        int count = std::max(1, int(std::round(length / CELL_M)));
        double dx = length / double(count);
        counts.push_back(count);
        dxs.push_back(dx);
        losses.push_back(pipe.loss);
        _feeders[i] = pipe.feeders;
        for (int f : pipe.feeders) {
            if (f >= 0 && f < _npipes) _parent[f] = i;
        }
        if (pipe.cyl >= 0 && pipe.cyl < CYLINDERS) {
            _cyl_pipe[pipe.cyl] = i;
        }
        for (int c = 0; c < count; c++) {
            areas.push_back(_area_at(pipe, (double(c) + 0.5) * dx));
        }
    }

    int total = 0;
    for (int i = 0; i < _npipes; i++) {
        _pipe0[i] = total;
        _pipe_n[i] = counts[i];
        total += counts[i];
    }
    _n = total;

    _area.assign(total, 0.0f);
    _dx.assign(total, 0.0f);
    _loss.assign(total, 0.0f);
    int at = 0;
    for (int i = 0; i < _npipes; i++) {
        for (int c = 0; c < counts[i]; c++) {
            _area[at] = float(areas[at]);
            _dx[at] = float(dxs[i]);
            _loss[at] = float(losses[i]);
            at++;
        }
    }

    _rho.assign(total, 0.0f);
    _ru.assign(total, 0.0f);
    _re.assign(total, 0.0f);
    double rho0 = P0 / (R * T0);
    double e0 = P0 / ((GAMMA - 1.0) * rho0);
    for (int i = 0; i < total; i++) {
        _rho[i] = float(rho0);
        _ru[i] = 0.0f;
        _re[i] = float(rho0 * e0);
    }

    _mdot.assign(CYLINDERS, 0.0f);
    _power.assign(CYLINDERS, 0.0f);
    _d_rho.assign(total, 0.0f);
    _d_ru.assign(total, 0.0f);
    _d_re.assign(total, 0.0f);

    _min_dx = CELL_M;
    for (int i = 0; i < total; i++) {
        _min_dx = mind(_min_dx, double(_dx[i]));
    }
    _cfl_dt = CFL * _min_dx / (ambient_sound_speed() + 1.0);
    _audio_left = 0.0;
    _q_prev = 0.0;
    _build_faces();
}

int ExhaustGas::_port_cell(int cylinder_index) const {
    if (cylinder_index < 0 || cylinder_index >= int(_cyl_pipe.size())) return -1;
    int pipe = _cyl_pipe[cylinder_index];
    if (pipe < 0) return -1;
    return _pipe0[pipe];
}

double ExhaustGas::port_pressure(int cylinder_index) const {
    int cell = _port_cell(cylinder_index);
    if (cell < 0) return P0;
    return _pressure(cell);
}

double ExhaustGas::port_temperature(int cylinder_index) const {
    int cell = _port_cell(cylinder_index);
    if (cell < 0) return T0;
    return _pressure(cell) / (maxd(double(_rho[cell]), 1e-6) * R);
}

void ExhaustGas::apply_valve(int cylinder_index, double mdot, double power) {
    if (cylinder_index < 0 || cylinder_index >= int(_mdot.size())) return;
    _mdot[cylinder_index] = float(mdot);
    _power[cylinder_index] = float(power);
}

void ExhaustGas::add_energy(int cylinder_index, double joules) {
    int cell = _port_cell(cylinder_index);
    if (cell < 0 || joules == 0.0) return;
    double volume = double(_area[cell]) * double(_dx[cell]);
    _re[cell] += float(joules / maxd(volume, 1e-8));
    _clamp_cell(cell);
}

double ExhaustGas::station_pressure(int pipe_index) const {
    if (pipe_index < 0 || pipe_index >= _npipes) return P0;
    return _pressure(_pipe0[pipe_index]);
}

double ExhaustGas::tail_volume_flow() const {
    if (_n <= 0) return 0.0;
    int last = _n - 1;
    return _velocity(last) * double(_area[last]);
}

// Returns every sample written since the last call. The buffer is a growing vector, not a ring, so a wrap cannot drop samples.
std::vector<float> ExhaustGas::take_flow() {
    std::vector<float> out;
    out.swap(_flow);
    return out;
}

void ExhaustGas::advance(double dt) {
    if (_n <= 0 || dt <= 0.0) return;
    double remain = dt;
    int guard = 0;
    while (remain > 1.0e-8 && guard < 8000) {
        guard++;
        double h = mind(_cfl_dt, remain);
        _step(h);
        double q1 = tail_volume_flow();
        if (record_audio) {
            // samples fall at 44.1 kHz; each one is the tail flow interpolated across this step
            double sample = 1.0 / AUDIO_RATE;
            double t = _audio_left;
            while (t < h) {
                _flow.push_back(float(lerpd(_q_prev, q1, t / h)));
                t += sample;
            }
            _audio_left = t - h;
        }
        _q_prev = q1;
        remain -= h;
    }
}

double ExhaustGas::_area_at(const ExhaustPipe &pipe, double dist_m) const {
    double dist = dist_m * _scene_per_m;
    double walked = 0.0;
    size_t n = pipe.pts.size();
    if (n < 2) return maxd(pipe.area_m2(_scene_per_m), 1.0e-6);
    for (size_t i = 0; i + 1 < n; i++) {
        double seg = segment_length(pipe.pts[i], pipe.pts[i + 1]);
        if (walked + seg >= dist || i == n - 2) {
            double t = clampd((dist - walked) / maxd(seg, 1e-6), 0.0, 1.0);
            double radius = lerpd(double(pipe.radii[i]), double(pipe.radii[i + 1]), t) / _scene_per_m;
            return maxd(PI_D * radius * radius, 1.0e-6);
        }
        walked += seg;
    }
    return maxd(pipe.area_m2(_scene_per_m), 1.0e-6);
}

void ExhaustGas::_build_faces() {
    std::vector<int> lefts, rights;
    std::vector<float> scale_l, scale_r;
    std::vector<std::uint8_t> kinds;

    for (int pipe = 0; pipe < _npipes; pipe++) {
        int a0 = _pipe0[pipe];
        int count = _pipe_n[pipe];
        for (int i = 0; i < count - 1; i++) {
            int left = a0 + i;
            int right = a0 + i + 1;
            double face_area = mind(_area[left], _area[right]);
            lefts.push_back(left);
            rights.push_back(right);
            scale_l.push_back(float(-face_area / (double(_area[left]) * _dx[left])));
            scale_r.push_back(float(face_area / (double(_area[right]) * _dx[right])));
            kinds.push_back(0);
        }
        if (_parent[pipe] < 0) {
            int last = a0 + count - 1;
            lefts.push_back(last);
            rights.push_back(last);
            scale_l.push_back(float(-1.0 / _dx[last]));
            scale_r.push_back(0.0f);
            kinds.push_back(2);
        }
        if (_feeders[pipe].empty()) {
            lefts.push_back(a0);
            rights.push_back(a0);
            scale_l.push_back(float(1.0 / _dx[a0]));
            scale_r.push_back(0.0f);
            kinds.push_back(1);
        }
    }
    for (int pipe = 0; pipe < _npipes; pipe++) {
        if (_feeders[pipe].empty()) continue;
        int into = _pipe0[pipe];
        for (int f : _feeders[pipe]) {
            int last = _pipe0[f] + _pipe_n[f] - 1;
            double face_area = mind(_area[last], _area[into]);
            lefts.push_back(last);
            rights.push_back(into);
            scale_l.push_back(float(-face_area / (double(_area[last]) * _dx[last])));
            scale_r.push_back(float(face_area / (double(_area[into]) * _dx[into])));
            kinds.push_back(0);
        }
    }

    _nf = int(lefts.size());
    _fl = lefts;
    _fr = rights;
    _sl = scale_l;
    _sr = scale_r;
    _fk = kinds;
}

void ExhaustGas::_step(double dt) {
    std::fill(_d_rho.begin(), _d_rho.end(), 0.0f);
    std::fill(_d_ru.begin(), _d_ru.end(), 0.0f);
    std::fill(_d_re.begin(), _d_re.end(), 0.0f);
    const double gm1 = GAMMA - 1.0;

    for (int f = 0; f < _nf; f++) {
        int l = _fl[f];
        double rho_l = maxd(double(_rho[l]), 1.0e-6);
        double u_l = double(_ru[l]) / rho_l;
        double p_l = maxd(gm1 * (double(_re[l]) - 0.5 * rho_l * u_l * u_l), 200.0);
        int kind = _fk[f];
        double fm;
        double fu;
        double fe;
        if (kind == 1) {
            double c_l = std::sqrt(GAMMA * p_l / rho_l);
            fm = 0.0;
            fu = maxd(p_l - rho_l * c_l * u_l, 200.0);
            fe = 0.0;
        } else if (kind == 2) {
            double rho_face = u_l >= 0.0 ? rho_l : P0 / (R * T0);
            double e_face = P0 / gm1 + 0.5 * rho_face * u_l * u_l;
            double h_face = (e_face + P0) / rho_face;
            fm = rho_face * u_l;
            fu = fm * u_l + P0;
            fe = fm * h_face;
        } else {
            int r = _fr[f];
            double rho_r = maxd(double(_rho[r]), 1.0e-6);
            double u_r = double(_ru[r]) / rho_r;
            double p_r = maxd(gm1 * (double(_re[r]) - 0.5 * rho_r * u_r * u_r), 200.0);
            double e_l = p_l / gm1 + 0.5 * rho_l * u_l * u_l;
            double e_r = p_r / gm1 + 0.5 * rho_r * u_r * u_r;
            double h_l = (e_l + p_l) / rho_l;
            double h_r = (e_r + p_r) / rho_r;
            double fx_l = rho_l * u_l;
            double fy_l = fx_l * u_l + p_l;
            double fz_l = fx_l * h_l;
            double fx_r = rho_r * u_r;
            double fy_r = fx_r * u_r + p_r;
            double fz_r = fx_r * h_r;
            double s = maxd(std::fabs(u_l) + std::sqrt(GAMMA * p_l / rho_l),
                            std::fabs(u_r) + std::sqrt(GAMMA * p_r / rho_r));
            fm = 0.5 * (fx_l + fx_r) - 0.5 * s * (rho_r - rho_l);
            fu = 0.5 * (fy_l + fy_r) - 0.5 * s * (rho_r * u_r - rho_l * u_l);
            fe = 0.5 * (fz_l + fz_r) - 0.5 * s * (e_r - e_l);
            double sr = double(_sr[f]) * dt;
            _d_rho[r] += float(fm * sr);
            _d_ru[r] += float(fu * sr);
            _d_re[r] += float(fe * sr);
            // The flux crosses the narrower pipe. The step wall holds the rest of the wider pipe,
            // so a pipe at rest stays at rest instead of pumping itself up to the pressure clamp.
            double wide_l = _area[l];
            double wide_r = _area[r];
            double throat = mind(wide_l, wide_r);
            if (wide_l > throat) {
                _d_ru[l] -= float(p_l * (wide_l - throat) / (wide_l * _dx[l]) * dt);
            }
            if (wide_r > throat) {
                _d_ru[r] += float(p_r * (wide_r - throat) / (wide_r * _dx[r]) * dt);
            }
        }
        double sl = double(_sl[f]) * dt;
        _d_rho[l] += float(fm * sl);
        _d_ru[l] += float(fu * sl);
        _d_re[l] += float(fe * sl);
    }

    // A collector has one upstream pressure face, not one full-area face for each header.
    for (int pipe = 0; pipe < _npipes; pipe++) {
        int feeder_count = int(_feeders[pipe].size());
        if (feeder_count > 1) {
            int cell = _pipe0[pipe];
            _d_ru[cell] -= float((feeder_count - 1) * _pressure(cell) / _dx[cell] * dt);
        }
    }

    for (int i = 0; i < _n; i++) {
        _rho[i] += _d_rho[i];
        _ru[i] += _d_ru[i];
        _re[i] += _d_re[i];
    }

    for (int cyl = 0; cyl < int(_mdot.size()); cyl++) {
        int cell = _port_cell(cyl);
        if (cell < 0) continue;
        double volume = double(_area[cell]) * double(_dx[cell]);
        // Backflow carries the pipe's own gas out: its enthalpy, not the cylinder's.
        double rho_c = _rho[cell];
        double u_c = double(_ru[cell]) / maxd(rho_c, 1.0e-8);
        double p_c = (GAMMA - 1.0) * (double(_re[cell]) - 0.5 * rho_c * u_c * u_c);
        double h_c = (double(_re[cell]) + p_c) / maxd(rho_c, 1.0e-8);
        double mdot = _mdot[cyl];
        double energy_in = mdot < 0.0 ? mdot * h_c : double(_power[cyl]);
        _rho[cell] += float(mdot * dt / volume);
        _re[cell] += float(energy_in * dt / volume);
        double inflow = mdot / maxd(double(_rho[cell]) * double(_area[cell]), 1.0e-8);
        _ru[cell] += float(mdot * inflow * dt / volume);
    }

    double fastest = ambient_sound_speed();
    const double cv_min = R / gm1 * 200.0;
    const double cv_max = R / gm1 * 3500.0;
    for (int i = 0; i < _n; i++) {
        double rho = clampd(double(_rho[i]), 0.02, 40.0);
        double u = clampd(double(_ru[i]) / rho, -800.0, 800.0);
        double c_snd = std::sqrt(GAMMA * gm1 * maxd(double(_re[i]) / rho - 0.5 * u * u, cv_min));
        double cut = clampd(double(_loss[i]) * c_snd * dt, 0.0, 0.5); // loss per metre times the distance the wave covers
        u *= 1.0 - cut;
        double ke = 0.5 * u * u;
        double internal = clampd(double(_re[i]) / rho - ke, cv_min, cv_max);
        _rho[i] = float(rho);
        _ru[i] = float(rho * u);
        _re[i] = float(rho * (internal + ke));
        fastest = maxd(fastest, std::fabs(u) + std::sqrt(GAMMA * gm1 * internal));
    }
    _cfl_dt = maxd(CFL * _min_dx / fastest, 1.0e-6);
}

void ExhaustGas::_clamp_cell(int cell) {
    const double gm1 = GAMMA - 1.0;
    double rho = clampd(double(_rho[cell]), 0.02, 40.0);
    double u = clampd(double(_ru[cell]) / rho, -800.0, 800.0);
    double ke = 0.5 * u * u;
    double internal = clampd(double(_re[cell]) / rho - ke, R / gm1 * 200.0, R / gm1 * 3500.0);
    _rho[cell] = float(rho);
    _ru[cell] = float(rho * u);
    _re[cell] = float(rho * (internal + ke));
}

double ExhaustGas::_pressure(int cell) const {
    double u = _velocity(cell);
    double internal = double(_re[cell]) / maxd(double(_rho[cell]), 1e-6) - 0.5 * u * u;
    return maxd((GAMMA - 1.0) * double(_rho[cell]) * internal, 200.0);
}

double ExhaustGas::_velocity(int cell) const {
    return double(_ru[cell]) / maxd(double(_rho[cell]), 1e-6);
}

} // namespace engine_sim
