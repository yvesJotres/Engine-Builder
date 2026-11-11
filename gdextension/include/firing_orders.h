#ifndef FIRING_ORDERS_H
#define FIRING_ORDERS_H

#include <string>
#include <vector>

// Port of scripts/engine/firing_orders.gd. Plain C++, no Godot types.

namespace engine_physics {

// The EngineSpec fields the firing-angle logic reads. Defaults match scripts/sim/engine_spec.gd.
struct FiringSpec {
    int cylinders = 1;
    std::vector<double> fire_deg; // wire angle per cylinder; empty = generic order
    double twin_pin_deg = 360.0;
    bool split_pin_v4 = false;
    bool shared_v_crankpins = false;
    bool crossplane = false;
    std::string layout = "inline"; // inline | V
    double bank_angle = 90.0;
    bool v3r_style = false;
};

// Firing order (1-based cylinder numbers). Other counts fall back to 1..n.
std::vector<int> order_for(int cylinders);

// True when the crank passed angle `at` while moving from prev to cur (unwrapped degrees).
bool fired_between(double prev, double cur, double at);

// The firing angles for this spec: the engine's own ignition wiring when its preset gives one for this cylinder count,
// otherwise the generic order below.
std::vector<double> for_spec(const FiringSpec &spec);

// Crank angle (deg, 0..720) at which each cylinder fires. Index = cylinder number - 1.
// A twin fires its second cylinder at its crank-pin angle: 360 is even firing, 270 and 180 are uneven.
std::vector<double> fire_angles(int cylinders, double twin_pin_deg = 360.0, bool crossplane = false, bool split_v4 = false);

} // namespace engine_physics

#endif // FIRING_ORDERS_H
