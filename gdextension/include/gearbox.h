#ifndef GEARBOX_H
#define GEARBOX_H

#include <array>
#include <string>
#include <vector>

// Port of scripts/drivetrain/gearbox.gd (class Gearbox). Plain C++, no Godot types.
// Six-speed gearbox, tooth counts from the Honda K45R parts catalogue (E-17 transmission).
// Gear ratio = countershaft teeth / mainshaft teeth, so 1st = 37 / 12 and 6th = 24 / 26.

namespace engine_physics {

constexpr std::array<int, 6> GEARBOX_MAIN_TEETH = {12, 17, 20, 22, 24, 26}; // mainshaft gears, 1st to 6th
constexpr std::array<int, 6> GEARBOX_COUNTER_TEETH = {37, 33, 30, 27, 25, 24}; // countershaft gears, 1st to 6th
constexpr int GEARBOX_TOP_GEAR = 6;

class Gearbox {
public:
    int gear = 0; // 0 = neutral
    std::vector<double> gear_ratios; // set per engine by EngineSim, default K45R

    Gearbox();

    // Gearbox ratio for each gear, 1st to 6th, from the K45R tooth counts.
    static std::vector<double> ratios();

    // Gearbox ratio for the selected gear, 0 in neutral.
    double ratio() const;

    // Like a real motorcycle drum: 1st, neutral, 2nd, 3rd, ... so neutral is the half click between 1st and 2nd, and there is
    // nothing below 1st. Starting in neutral, down gives 1st and up gives 2nd.
    void shift_up();
    void shift_down();

    std::string label() const;
};

} // namespace engine_physics

#endif // GEARBOX_H
