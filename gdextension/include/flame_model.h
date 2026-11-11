#ifndef FLAME_MODEL_H
#define FLAME_MODEL_H

#include <utility>
#include <vector>

// Port of the ATG engine-sim flame-front combustion model:
//   combustion_chamber.cpp  ignite() lines 169-224, flow() flame section lines 315-354
//   fuel.cpp                flameSpeed() lines 37-49, laminarBurningVelocity() lines 51-65
// Plain C++17, std only, no Godot types, nothing registered.
// Units are SI: m, s, Pa, K, J, kg, mol.
// Every constant below names the ATG file and line it came from. Gasoline defaults are from fuel.h.

namespace engine_physics {

// ATG GasSystem::Mix fields used by the flame (p_fuel, p_o2, p_inert).
struct FlameMix {
    double p_fuel = 0.0;
    double p_o2 = 0.0;
    double p_inert = 0.0;
};

// Lookup table of (x, y) points sorted by ascending x. Lookups are piecewise linear with clamped ends.
using FlameTable = std::vector<std::pair<double, double>>;

// Fuel constants, gasoline defaults from ATG fuel.h.
struct FlameFuel {
    double molecularMass = 0.100;              // kg/mol. fuel.h:15, units::mass(100.0, g)
    double energyDensity = 4.81e7;             // J/kg. fuel.h:16-17, 48.1 kJ / 1 g
    double molecularAfr = 12.5;                // fuel.h:20, 25 / 2.0
    double burningEfficiencyRandomness = 0.5;  // fuel.h:21
    double lowEfficiencyAttenuation = 0.6;     // fuel.h:22
    double maxBurningEfficiency = 0.8;         // fuel.h:23
    double maxTurbulenceEffect = 2.0;          // fuel.h:24
    double maxDilutionEffect = 50.0;           // fuel.h:25
};

// Flame state, matching ATG CombustionChamber::FlameEvent (combustion_chamber.h:26-37).
struct FlameState {
    bool lit = false;
    double lastVolume = 0.0;   // m^3
    double travel_x = 0.0;     // flame radius, m
    double travel_y = 0.0;     // flame height, m
    double efficiency = 1.0;
    double flameSpeed = 0.0;   // m/s, turbulent flame speed
    double lit_n = 0.0;        // mol burnt by the flame so far (mol of gas, ATG lit_n)
    double total_n = 0.0;      // mol in the chamber at ignition
    double percentageLit = 0.0;
    FlameMix globalMix;        // mix at ignition
};

// Result of one advance() call.
struct FlameStep {
    double moles_burnt = 0.0;      // mol of fuel requested to react (ATG n * efficiency, before react() limits)
    double mass_burnt_kg = 0.0;    // kg, moles_burnt * molecularMass
    double energy_per_kg_J = 0.0;  // J/kg, fuel.energyDensity
    double energy_J = 0.0;         // J, mass_burnt_kg * energy_per_kg_J
};

class FlameModel {
public:
    FlameFuel fuel;
    FlameState state;

    // Caller-supplied turbulence tables (see the shortcut comment in flame_model.cpp).
    // Empty table = linear stand-in.
    // pistonSpeedToTurbulence: x = mean |piston speed| (m/s), y = turbulence (m/s).
    //   ATG: CombustionChamber::m_meanPistonSpeedToTurbulence, sampleTriangle(), combustion_chamber.cpp:202-204.
    // turbulenceToFlameSpeedRatio: x = turbulence / S_L, y = S_T / S_L.
    //   ATG: Fuel::m_turbulenceToFlameSpeedRatio, fuel.cpp:48.
    FlameTable pistonSpeedToTurbulence;
    FlameTable turbulenceToFlameSpeedRatio;

    // Starts the flame if the mix is ignitable. Returns true if the flame was lit by this call.
    // mix:             p_fuel, p_o2, p_inert (ATG m_system.mix()).
    // volume:          chamber volume, m^3 (ATG getVolume()).
    // totalMoles:      mol in the chamber (ATG m_system.n()).
    // meanPistonSpeed: mean |piston speed|, m/s (ATG calculateMeanPistonSpeed()).
    // temperature:     K. pressure: Pa.
    // randomUnit:      uniform random number in [0, 1], replaces ATG rand() / RAND_MAX (combustion_chamber.cpp:211).
    bool ignite(const FlameMix &mix,
                double volume,
                double totalMoles,
                double meanPistonSpeed,
                double temperature,
                double pressure,
                double randomUnit);

    // One flow step of the flame front. Call once per timestep after the gas flow.
    // dt:         s.
    // volume:     current chamber volume, m^3.
    // bore:       cylinder bore, m (ATG m_head->getCylinderBank()->getBore()).
    // totalMoles: current mol in the chamber (ATG m_system.n()).
    // intakeFlow: gas flow in through the intake this step, mol. A flow above 1e-9 extinguishes the flame
    //             (combustion_chamber.cpp:307-309).
    FlameStep advance(double dt, double volume, double bore, double totalMoles, double intakeFlow);

    bool isLit() const { return state.lit; }

    // ATG Fuel::laminarBurningVelocity (fuel.cpp:51-65). afr is the mix air-fuel ratio, T in K, P in Pa.
    double laminarBurningVelocity(double afr, double temperature, double pressure) const;

    // ATG Fuel::flameSpeed (fuel.cpp:37-49): S_T = ratio(turbulence / S_L) * S_L.
    double flameSpeed(double turbulence, double afr, double temperature, double pressure) const;

private:
    double turbulenceAt(double meanPistonSpeed) const;
    double flameSpeedRatio(double x) const;
};

} // namespace engine_physics

#endif // FLAME_MODEL_H
