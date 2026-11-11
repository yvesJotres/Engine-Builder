#include "friction_model.h"

#include <cmath>

namespace engine_sim {

namespace {
// Same values as src/constants.h (root_2 and e). Local copies keep this file std-only.
constexpr double kRoot2 = 1.41421356237309504880168872420969807856967187537694807317667973799;
constexpr double kE = 2.71828182845904523536028747135266249775724709369995;
} // namespace

// Unit note: ATG declares breakawayFrictionVelocity with units::distance(0.1, units::m).
// The value is used as a speed (compared against piston speed in m/s), so it is
// kept as 0.1 m/s here. Same for viscousFrictionCoefficient, which is multiplied by
// speed: 20 N per (m/s).
double calculateFriction(double v_s, double wall_normal_force, const FrictionParams &params) {
    // shortcut: with no breakaway velocity the Stribeck terms divide by zero (ATG has the same division). Fall back to
    // Coulomb plus viscous friction. Upgrade: set a positive breakawayFrictionVelocity in the spec.
    if (params.breakawayFrictionVelocity <= 0.0) {
        return params.frictionCoeff * wall_normal_force + params.viscousFrictionCoefficient * std::abs(v_s);
    }
    const double F_coul = params.frictionCoeff * wall_normal_force;   // combustion_chamber.cpp line 377
    const double v_st = params.breakawayFrictionVelocity * kRoot2;     // line 378
    const double v_coul = params.breakawayFrictionVelocity / 10;       // line 379
    const double F_brk = params.breakawayFriction;                     // line 380
    const double v = std::abs(v_s);                                    // line 381

    const double F_0 = kRoot2 * kE * (F_brk - F_coul);                 // line 383
    const double F_1 = v / v_st;                                       // line 384
    const double F_2 = std::exp(-F_1 * F_1) * F_1;                     // line 385
    const double F_3 = F_coul * std::tanh(v / v_coul);                 // line 386
    const double F_4 = params.viscousFrictionCoefficient * v;          // line 387

    return F_0 * F_2 + F_3 + F_4;                                      // line 389
}

} // namespace engine_sim
