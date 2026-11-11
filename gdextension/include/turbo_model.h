#ifndef TURBO_MODEL_H
#define TURBO_MODEL_H

// Port of scripts/intake/turbo.gd (Turbo.update_map). Works on the IntakeModel state, like the GDScript did.

#include "intake_model.h"

namespace engine_sim {

namespace turbo {
constexpr double FLOW_AVG_TIME = 0.03;  // s
constexpr double EXH_RATIO = 1.15;      // exhaust pressure over manifold pressure
constexpr double START_OMEGA = 100.0;   // rad/s
constexpr double CP_AIR = 1005.0;       // J/(kg K)
constexpr double BASE_SPEED_RPM = 50000.0;

// Advances the compressor map model in air by dt seconds, given the engine's air draw m_dot_engine (kg/s).
void update_map(IntakeModel &air, double dt, const IntakeSpec &spec, double m_dot_engine, double throttle,
                bool engine_running);
} // namespace turbo

} // namespace engine_sim

#endif // TURBO_MODEL_H
