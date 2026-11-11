#include "flame_model.h"

#include <algorithm>
#include <cmath>
#include <cstddef>

namespace engine_physics {

namespace {

// ATG constants::pi (constants.h, not read here).
constexpr double PI = 3.14159265358979323846;

// Clamp to [0, 1]. ATG clamp() from utilities.h (not read here); assumed to clamp to [0, 1].
double clamp01(double x) {
    if (x < 0.0) return 0.0;
    if (x > 1.0) return 1.0;
    return x;
}

// Piecewise-linear lookup with clamped ends. ATG Function::sampleTriangle (function.cpp, not read here)
// is assumed to behave like this. Table must be non-empty and sorted by x.
double sampleTable(const FlameTable &t, double x) {
    if (x <= t.front().first) return t.front().second;
    if (x >= t.back().first) return t.back().second;
    for (std::size_t i = 1; i < t.size(); ++i) {
        if (x <= t[i].first) {
            const double x0 = t[i - 1].first;
            const double x1 = t[i].first;
            const double y0 = t[i - 1].second;
            const double y1 = t[i].second;
            const double dx = x1 - x0;
            if (dx <= 0.0) return y1;
            return y0 + (x - x0) / dx * (y1 - y0);
        }
    }
    return t.back().second;
}

} // namespace

// shortcut: linear stand-in when no table is given. Turbulence = mean piston speed (identity), and the
//           flame-speed ratio is 1 + x (S_T = S_L + u'). Both are linear, not ATG's measured curves.
//           upgrade: when the ATG tables (combustion_chamber.cpp:202-204 and fuel.cpp:48) are exported
//           and passed in through pistonSpeedToTurbulence and turbulenceToFlameSpeedRatio.
double FlameModel::turbulenceAt(double meanPistonSpeed) const {
    if (pistonSpeedToTurbulence.empty()) return meanPistonSpeed;
    return sampleTable(pistonSpeedToTurbulence, meanPistonSpeed);
}

double FlameModel::flameSpeedRatio(double x) const {
    if (turbulenceToFlameSpeedRatio.empty()) return 1.0 + x;
    return sampleTable(turbulenceToFlameSpeedRatio, x);
}

double FlameModel::laminarBurningVelocity(double afr, double temperature, double pressure) const {
    // Gasoline fit (fuel.cpp:52).
    constexpr double er_m = 1.21;                // fuel.cpp:53
    constexpr double B_m = 0.305;                // fuel.cpp:54, units::distance(30.5, cm) / sec, m/s
    constexpr double B_er = -0.549;              // fuel.cpp:55, -units::distance(54.9, cm) / sec, m/s
    constexpr double T_ref = 298.0;              // fuel.cpp:61, units::kelvin(298), K
    constexpr double P_ref = 101325.0;           // fuel.cpp:62, units::pressure(1.0, atm), Pa

    const double er = afr / fuel.molecularAfr;                       // fuel.cpp:56
    const double alpha = 2.4 - 0.271 * std::pow(er, 3.51);           // fuel.cpp:57
    const double beta = -0.357 + 0.14 * std::pow(er, 2.77);          // fuel.cpp:58
    const double S_L_0 = B_m + B_er * (er - er_m) * (er - er_m);     // fuel.cpp:60
    const double T_ratio = temperature / T_ref;                      // fuel.cpp:61
    const double P_ratio = pressure / P_ref;                         // fuel.cpp:62

    return S_L_0 * std::pow(T_ratio, alpha) * std::pow(P_ratio, beta);  // fuel.cpp:64
}

// ATG passes the 160 psi motoring pressure (combustion_chamber.cpp:222) and firing pressure (:221) into
// flameSpeed. Neither is used by flameSpeed or laminarBurningVelocity, so they are not ported.
double FlameModel::flameSpeed(double turbulence, double afr, double temperature, double pressure) const {
    const double S_L = laminarBurningVelocity(afr, temperature, pressure);
    // ATG p_adjustment = 1.0 (fuel.cpp:46), so the lookup argument is turbulence / S_L.
    return flameSpeedRatio(turbulence / S_L) * S_L;  // fuel.cpp:48
}

bool FlameModel::ignite(const FlameMix &mix,
                        double volume,
                        double totalMoles,
                        double meanPistonSpeed,
                        double temperature,
                        double pressure,
                        double randomUnit) {
    if (state.lit) return false;                       // combustion_chamber.cpp:170
    if (mix.p_fuel == 0.0) return false;               // combustion_chamber.cpp:171

    const double afr = mix.p_o2 / mix.p_fuel;          // combustion_chamber.cpp:173
    const double equivalenceRatio = afr / fuel.molecularAfr;  // combustion_chamber.cpp:174
    if (equivalenceRatio < 0.5) return false;          // combustion_chamber.cpp:175
    if (equivalenceRatio > 1.9) return false;          // combustion_chamber.cpp:176

    const double idealInert = mix.p_o2 / 0.7;          // combustion_chamber.cpp:178
    const double dilution = (mix.p_inert / idealInert) - 1;  // combustion_chamber.cpp:179

    state.lastVolume = volume;                         // combustion_chamber.cpp:181
    state.travel_x = 0.0;                              // combustion_chamber.cpp:182
    state.travel_y = 0.0;                              // combustion_chamber.cpp:183
    state.lit_n = 0.0;                                 // combustion_chamber.cpp:184
    state.total_n = totalMoles;                        // combustion_chamber.cpp:185
    state.percentageLit = 0.0;                         // combustion_chamber.cpp:186
    state.globalMix = mix;                             // combustion_chamber.cpp:187
    state.lit = true;                                  // combustion_chamber.cpp:188

    const double turbulence = turbulenceAt(meanPistonSpeed);  // combustion_chamber.cpp:202-204

    const double mixingFactor =
        1.0 - (clamp01(turbulence / fuel.maxTurbulenceEffect)            // combustion_chamber.cpp:207
               * clamp01(1 - dilution / fuel.maxDilutionEffect));        // combustion_chamber.cpp:208

    // combustion_chamber.cpp:209-211. randomUnit replaces rand() / RAND_MAX.
    const double r = clamp01(randomUnit);
    const double rand_s =
        fuel.lowEfficiencyAttenuation
        * ((1 - fuel.burningEfficiencyRandomness) + fuel.burningEfficiencyRandomness * r);

    const double efficiencyAttenuation = (mixingFactor * rand_s + (1 - mixingFactor));  // combustion_chamber.cpp:212-213
    state.efficiency = efficiencyAttenuation * fuel.maxBurningEfficiency;               // combustion_chamber.cpp:214-215

    state.flameSpeed = flameSpeed(turbulence, afr, temperature, pressure);              // combustion_chamber.cpp:216-222
    return true;
}

FlameStep FlameModel::advance(double dt, double volume, double bore, double totalMoles, double intakeFlow) {
    FlameStep out;
    out.energy_per_kg_J = fuel.energyDensity;

    if (std::abs(intakeFlow) > 1E-9 && state.lit) {    // combustion_chamber.cpp:307-309
        state.lit = false;
    }
    if (!state.lit) return out;                        // combustion_chamber.cpp:315

    const double totalTravel_x = bore / 2;                         // combustion_chamber.cpp:317
    const double boreArea = PI * bore * bore / 4.0;                // bore area, as in combustion_chamber.cpp:406
    const double totalTravel_y = volume / boreArea;                // combustion_chamber.cpp:318

    // shortcut: guard against lastVolume <= 0 (ATG divides without a check). Expansion is 1 in that case.
    //           upgrade: never needed if ignite() always stores a positive volume.
    const double expansion = state.lastVolume > 0.0 ? volume / state.lastVolume : 1.0;  // combustion_chamber.cpp:319
    const double lastTravel_x = state.travel_x;                    // combustion_chamber.cpp:320
    const double lastTravel_y = state.travel_y * expansion;        // combustion_chamber.cpp:321
    const double flameSpeed = state.flameSpeed;                    // combustion_chamber.cpp:322

    state.travel_x = std::fmin(lastTravel_x + dt * flameSpeed, totalTravel_x);  // combustion_chamber.cpp:324-325
    state.travel_y = std::fmin(lastTravel_y + dt * flameSpeed, totalTravel_y);  // combustion_chamber.cpp:326-327

    if (lastTravel_x < state.travel_x || lastTravel_y < state.travel_y) {       // combustion_chamber.cpp:329
        const double burnedVolume =
            state.travel_x * state.travel_x * PI * state.travel_y;              // combustion_chamber.cpp:330-332
        const double prevBurnedVolume =
            lastTravel_x * lastTravel_x * PI * lastTravel_y;                    // combustion_chamber.cpp:333-334
        const double litVolume = burnedVolume - prevBurnedVolume;               // combustion_chamber.cpp:335
        const double n = (litVolume / volume) * totalMoles;                     // combustion_chamber.cpp:336

        // ATG calls m_system.react(n * efficiency, globalMix) at line 339. react() is not ported, so this
        // returns the requested moles. The caller must limit them to the reactants actually present.
        const double moles = n * state.efficiency;
        out.moles_burnt = moles;                                                // combustion_chamber.cpp:339
        out.mass_burnt_kg = moles * fuel.molecularMass;                         // combustion_chamber.cpp:340
        out.energy_J = out.mass_burnt_kg * fuel.energyDensity;                  // combustion_chamber.cpp:341-342

        state.lit_n += n;                                                       // combustion_chamber.cpp:344
        state.percentageLit += litVolume / volume;                              // combustion_chamber.cpp:345
    }
    else {
        state.lit = false;                                                      // combustion_chamber.cpp:349-351
    }

    state.lastVolume = volume;                                                  // combustion_chamber.cpp:353
    return out;
}

} // namespace engine_physics
