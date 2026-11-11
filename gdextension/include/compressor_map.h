#ifndef COMPRESSOR_MAP_H
#define COMPRESSOR_MAP_H

// Port of scripts/intake/compressor_map.gd. Plain C++, no Godot types, nothing registered.
// The tables are filled by the caller (the JSON in assets/compressor_maps/ is not parsed here).
// Call sort_points() once after filling speed_lines, since lookup_speed_line assumes flow-sorted points.

#include <string>
#include <vector>

namespace engine_sim {

struct MapPoint {
    double pr;   // pressure ratio
    double flow; // corrected mass flow, kg/s
    double eff;  // isentropic efficiency
};

struct SpeedLine {
    double speed_rpm; // corrected speed of this line
    std::vector<MapPoint> points;
};

struct FlowPr {
    double flow;
    double pr;
};

struct PrEff {
    double pr;
    double eff;
};

struct MapLookup {
    double pr;
    double eff;
    int speed_line; // index of the line used (lower one when interpolating)
};

class CompressorMap {
public:
    std::string map_id;
    std::string name;
    std::vector<SpeedLine> speed_lines; // ascending corrected speed
    std::vector<FlowPr> surge_line;     // left boundary, sorted by flow
    std::vector<FlowPr> choke_line;     // right boundary, sorted by flow
    double ref_temp_k = 288.15;
    double ref_pressure_pa = 101325.0;

    void sort_points(); // sorts each speed line's points by flow

    double correct_flow(double raw_flow, double temp_k, double pressure_pa) const;
    double correct_speed(double raw_speed, double temp_k) const;
    PrEff lookup_speed_line(int line_idx, double corrected_flow) const;
    MapLookup lookup(double corrected_speed, double corrected_flow) const;
    bool is_surge(double corrected_flow, double pr) const;
    bool is_choke(double corrected_flow, double pr) const;
};

} // namespace engine_sim

#endif // COMPRESSOR_MAP_H
