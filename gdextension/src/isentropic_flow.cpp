#include "isentropic_flow.h"

#include <algorithm>
#include <cmath>

namespace engine_sim {
namespace isentropic {

// Unit assumption: pressures in Pa, temperature in K, R in J/(mol*K).
// Output is the ATG flowRate value (mol/s scale, times k_flow); ATG's flow()
// multiplies by dt, and this function does not.
double flowRate(double p_up, double t_up, double p_down, double k_flow, double gamma, double R) {
    if (k_flow == 0) return 0;

    const double hcr = gamma;
    const double p_ratio = p_down / p_up;

    // Choked limit and choked flow factor: gas_system.h lines 131-142.
    const double chokedFlowLimit = std::pow(2.0 / (hcr + 1), hcr / (hcr - 1));

    double flow = 0;
    if (p_ratio <= chokedFlowLimit) {
        // Choked flow (gas_system.cpp lines 213-217).
        // Cached factor from gas_system.h lines 136-142.
        flow = std::sqrt(hcr) * std::pow(2 / (hcr + 1), (hcr + 1) / (2 * (hcr - 1)));
        flow /= std::sqrt(R * t_up);
    }
    else {
        // Subsonic flow (gas_system.cpp lines 218-224).
        const double s = std::pow(p_ratio, 1 / hcr);

        flow = (2 * hcr) / (hcr - 1);
        flow *= s * (s - p_ratio);
        flow = std::sqrt(std::fmax(flow, 0.0) / (R * t_up));
    }

    flow *= p_up;  // direction is +1 because p_up is the upstream side

    return flow * k_flow;
}

} // namespace isentropic
} // namespace engine_sim
