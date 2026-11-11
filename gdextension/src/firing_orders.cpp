#include "firing_orders.h"

#include <cmath>
#include <map>

namespace engine_physics {

namespace {

// GDScript fposmod: the remainder keeps the sign of the divisor.
double fposmod(double x, double y) {
    double rem = std::fmod(x, y);
    if ((rem < 0.0 && y > 0.0) || (rem > 0.0 && y < 0.0)) {
        rem += y;
    }
    return rem;
}

} // namespace

// Values from scripts/engine/firing_orders.gd ORDERS.
std::vector<int> order_for(int cylinders) {
    static const std::map<int, std::vector<int>> orders = {
        {3, {1, 2, 3}},
        {4, {1, 3, 4, 2}},
        {6, {1, 5, 3, 6, 2, 4}},
        {8, {1, 8, 4, 3, 6, 5, 7, 2}},
    };
    auto it = orders.find(cylinders);
    if (it != orders.end()) {
        return it->second;
    }
    std::vector<int> seq;
    for (int i = 1; i <= cylinders; ++i) {
        seq.push_back(i);
    }
    return seq;
}

// True when the crank passed angle `at` while moving from prev to cur (unwrapped degrees).
bool fired_between(double prev, double cur, double at) {
    return std::floor((cur - at) / 720.0) > std::floor((prev - at) / 720.0);
}

// The firing angles for this spec: the engine's own ignition wiring when its preset gives one for this cylinder count,
// otherwise the generic order below.
std::vector<double> for_spec(const FiringSpec &spec) {
    std::vector<double> out;
    if (spec.cylinders > 0 && static_cast<int>(spec.fire_deg.size()) == spec.cylinders) {
        out = spec.fire_deg;
    } else {
        out = fire_angles(spec.cylinders, spec.twin_pin_deg, spec.crossplane, spec.split_pin_v4);
    }
    if (spec.layout == "V" && spec.shared_v_crankpins) {
        for (size_t i = 0; i + 1 < out.size(); i += 2) {
            // Opposite banks share a crankpin when bank_angle + second firing angle
            // equals the first firing angle modulo one crank revolution.
            double bank_offset = (spec.v3r_style && spec.cylinders == 3) ? -spec.bank_angle : spec.bank_angle;
            double first = fposmod(out[i] - bank_offset, 360.0);
            double second = first + 360.0;
            double old = fposmod(out[i + 1], 720.0);
            double d1 = std::fabs(fposmod(first - old + 360.0, 720.0) - 360.0);
            double d2 = std::fabs(fposmod(second - old + 360.0, 720.0) - 360.0);
            out[i + 1] = d1 <= d2 ? first : second;
        }
    }
    return out;
}

// Crank angle (deg, 0..720) at which each cylinder fires. Index = cylinder number - 1.
// A twin fires its second cylinder at its crank-pin angle: 360 is even firing, 270 and 180 are uneven.
std::vector<double> fire_angles(int cylinders, double twin_pin_deg, bool crossplane, bool split_v4) {
    if (cylinders == 2) {
        return {0.0, twin_pin_deg};
    }
    // 90 degree V4 with a 70 degree split crank pin (Ducati Panigale V4). Ignition wiring from engine-sim's panigale_v4.mr:
    // bank A front pin 0, bank B front pin -90, bank A rear pin -240, bank B rear pin -330, on a 720 degree cycle.
    // Cylinders 1 to 4 fire at 0, 630, 480, 390: uneven intervals of 390, 90, 150 and 90 degrees.
    if (cylinders == 4 && split_v4) {
        return {0.0, 630.0, 480.0, 390.0};
    }
    // crossplane four: pins 90° apart, so firing comes 270/180/90/180 apart. Cylinders 1 to 4 fire at 0, 450, 270, 540.
    if (cylinders == 4 && crossplane) {
        return {0.0, 450.0, 270.0, 540.0};
    }
    if (cylinders <= 0) {
        return {};
    }
    std::vector<int> order = order_for(cylinders);
    double interval = 720.0 / cylinders;
    std::vector<double> angles(cylinders, 0.0);
    for (size_t i = 0; i < order.size(); ++i) {
        angles[order[i] - 1] = static_cast<double>(i) * interval;
    }
    return angles;
}

} // namespace engine_physics
