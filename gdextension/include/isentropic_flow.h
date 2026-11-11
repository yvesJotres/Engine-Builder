#ifndef ISENTROPIC_FLOW_H
#define ISENTROPIC_FLOW_H

// C++ port of the isentropic nozzle flow function in ATG engine-sim
// (src/gas_system.cpp GasSystem::flowRate, lines 183-229).
// Plain C++17, no godot-cpp dependency. SI units assumed (see isentropic_flow.cpp).

namespace engine_sim {
namespace isentropic {

// Returns the flow rate through a nozzle for upstream pressure p_up (Pa) and
// temperature t_up (K), downstream pressure p_down (Pa), flow scale k_flow,
// heat capacity ratio gamma and specific gas constant R (J/(mol*K) in ATG).
//
// Requires p_up >= p_down. The function does not swap the two pressures or
// apply a direction; if p_down > p_up it returns 0 (the subsonic branch clamps
// negative terms). The caller applies the direction as gas_system.cpp does
// (lines 198-209 and 226).
//
// Subsonic branch when p_down / p_up > (2/(gamma+1))^(gamma/(gamma-1)),
// choked branch otherwise. Returns k_flow * p_up / sqrt(R * t_up) * f(ratio).
// Returns 0 when k_flow == 0.
double flowRate(double p_up, double t_up, double p_down, double k_flow, double gamma, double R);

} // namespace isentropic
} // namespace engine_sim

#endif // ISENTROPIC_FLOW_H
