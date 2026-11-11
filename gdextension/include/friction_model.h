#ifndef FRICTION_MODEL_H
#define FRICTION_MODEL_H

// C++ port of the Stribeck piston-ring friction in ATG engine-sim
// (src/combustion_chamber.cpp calculateFrictionForce, lines 374-390).
// Plain C++17, no godot-cpp dependency. SI units throughout.

namespace engine_sim {

// Mirrors ATG's CombustionChamber::FrictionModelParams (combustion_chamber.h lines 39-44).
// Values are in SI: N, m/s and N/(m/s). See the note in friction_model.cpp.
struct FrictionParams {
    double frictionCoeff = 0.06;                  // combustion_chamber.h line 40
    double breakawayFriction = 50.0;              // N, combustion_chamber.h line 41
    double breakawayFrictionVelocity = 0.1;       // m/s, combustion_chamber.h line 42
    double viscousFrictionCoefficient = 20.0;     // N per (m/s), combustion_chamber.h line 43
};

// Returns the friction force magnitude for sliding speed v_s (m/s) and cylinder
// wall normal force (N). The result is non-negative for v_s and a non-negative
// wall_normal_force; the sign opposing motion is applied by the caller
// (ATG apply(), combustion_chamber.cpp lines 425-427).
// Caller must keep breakawayFrictionVelocity > 0 (ATG has no guard; a zero value
// divides by zero).
double calculateFriction(double v_s, double wall_normal_force, const FrictionParams &params);

} // namespace engine_sim

#endif // FRICTION_MODEL_H
