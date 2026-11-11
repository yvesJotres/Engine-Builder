#include "compressor_map.h"

#include <algorithm>
#include <cmath>

namespace engine_sim {

namespace {
double lerp(double a, double b, double t) { return a + (b - a) * t; }
} // namespace

void CompressorMap::sort_points() {
    for (SpeedLine &line : speed_lines) {
        std::sort(line.points.begin(), line.points.end(),
                  [](const MapPoint &a, const MapPoint &b) { return a.flow < b.flow; });
    }
}

// Corrected mass flow: m_dot * sqrt(T/T_ref) / (P/P_ref)  [kg/s]
double CompressorMap::correct_flow(double raw_flow, double temp_k, double pressure_pa) const {
    return raw_flow * std::sqrt(temp_k / ref_temp_k) / (pressure_pa / ref_pressure_pa);
}

// Corrected speed: N / sqrt(T/T_ref)  [rpm]
double CompressorMap::correct_speed(double raw_speed, double temp_k) const {
    return raw_speed / std::sqrt(temp_k / ref_temp_k);
}

// Linear interpolation on one speed line at corrected_flow, returns (pr, eff).
// The GDScript lookup_speed_line returns a Vector2, which stores float32, so it rounds pr and eff to float32. This shim
// rounds the same way so the native and GDScript paths agree exactly while both exist. Remove it (and the f32 calls)
// when scripts/intake/compressor_map.gd is retired: the double values are the more accurate ones.
static inline double f32(double x) { return static_cast<double>(static_cast<float>(x)); }

PrEff CompressorMap::lookup_speed_line(int line_idx, double corrected_flow) const {
    const std::vector<MapPoint> &points = speed_lines[line_idx].points;
    if (points.empty()) {
        return {1.0, 0.7}; // shortcut: empty line, same fallback as lookup(); the GDScript would error
    }
    for (size_t i = 0; i + 1 < points.size(); ++i) {
        double f0 = points[i].flow;
        double f1 = points[i + 1].flow;
        if (corrected_flow >= f0 && corrected_flow <= f1) {
            double t = (corrected_flow - f0) / (f1 - f0);
            return {f32(lerp(points[i].pr, points[i + 1].pr, t)), f32(lerp(points[i].eff, points[i + 1].eff, t))};
        }
    }
    // extrapolate nearest
    if (corrected_flow < points.front().flow) {
        return {f32(points.front().pr), f32(points.front().eff)};
    }
    return {f32(points.back().pr), f32(points.back().eff)};
}

// Interpolates between speed lines at corrected_speed and corrected_flow.
MapLookup CompressorMap::lookup(double corrected_speed, double corrected_flow) const {
    if (speed_lines.empty()) {
        return {1.0, 0.7, 0};
    }
    const int last = static_cast<int>(speed_lines.size()) - 1;
    if (corrected_speed <= speed_lines[0].speed_rpm) {
        PrEff res = lookup_speed_line(0, corrected_flow);
        return {res.pr, res.eff, 0};
    }
    if (corrected_speed >= speed_lines[last].speed_rpm) {
        PrEff res = lookup_speed_line(last, corrected_flow);
        return {res.pr, res.eff, last};
    }
    for (int i = 0; i < last; ++i) {
        double s0 = speed_lines[i].speed_rpm;
        double s1 = speed_lines[i + 1].speed_rpm;
        if (corrected_speed >= s0 && corrected_speed <= s1) {
            double t = (corrected_speed - s0) / (s1 - s0);
            PrEff res0 = lookup_speed_line(i, corrected_flow);
            PrEff res1 = lookup_speed_line(i + 1, corrected_flow);
            return {lerp(res0.pr, res1.pr, t), lerp(res0.eff, res1.eff, t), i};
        }
    }
    return {1.0, 0.7, 0};
}

// In surge when the operating PR is above the surge line at this flow.
bool CompressorMap::is_surge(double corrected_flow, double pr) const {
    for (size_t i = 0; i + 1 < surge_line.size(); ++i) {
        double f0 = surge_line[i].flow;
        double f1 = surge_line[i + 1].flow;
        if (corrected_flow >= f0 && corrected_flow <= f1) {
            double surge_pr = lerp(surge_line[i].pr, surge_line[i + 1].pr, (corrected_flow - f0) / (f1 - f0));
            return pr > surge_pr;
        }
    }
    return false;
}

// In choke when the operating PR is below the choke line at this flow.
bool CompressorMap::is_choke(double corrected_flow, double pr) const {
    for (size_t i = 0; i + 1 < choke_line.size(); ++i) {
        double f0 = choke_line[i].flow;
        double f1 = choke_line[i + 1].flow;
        if (corrected_flow >= f0 && corrected_flow <= f1) {
            double choke_pr = lerp(choke_line[i].pr, choke_line[i + 1].pr, (corrected_flow - f0) / (f1 - f0));
            return pr < choke_pr;
        }
    }
    return false;
}

} // namespace engine_sim
