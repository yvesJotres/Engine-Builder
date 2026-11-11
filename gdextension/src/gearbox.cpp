#include "gearbox.h"

#include <algorithm>

namespace engine_physics {

Gearbox::Gearbox() : gear_ratios(ratios()) {}

// Gearbox ratio for each gear, 1st to 6th, from the K45R tooth counts.
std::vector<double> Gearbox::ratios() {
    std::vector<double> out;
    for (size_t i = 0; i < GEARBOX_MAIN_TEETH.size(); ++i) {
        out.push_back(static_cast<double>(GEARBOX_COUNTER_TEETH[i]) / GEARBOX_MAIN_TEETH[i]);
    }
    return out;
}

// Gearbox ratio for the selected gear, 0 in neutral.
double Gearbox::ratio() const {
    return gear > 0 ? gear_ratios[gear - 1] : 0.0;
}

void Gearbox::shift_up() {
    const int n = static_cast<int>(gear_ratios.size());
    if (gear == 0) {
        gear = std::min(2, n);
    } else if (gear == 1) {
        gear = 0;
    } else {
        gear = std::min(gear + 1, n);
    }
}

void Gearbox::shift_down() {
    if (gear == 0) {
        gear = 1;
    } else if (gear == 2) {
        gear = 0;
    } else {
        gear = std::max(gear - 1, 1);
    }
}

std::string Gearbox::label() const {
    return gear == 0 ? "N" : std::to_string(gear);
}

} // namespace engine_physics
