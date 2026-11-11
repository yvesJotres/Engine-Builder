#ifndef FUEL_MODEL_H
#define FUEL_MODEL_H

#include <array>
#include <string>

// Port of scripts/fuel/fuel.gd (class FuelTank). Plain C++, no Godot types.
// Fuel properties (SI) and a tank that the engine draws from.
// afr: stoichiometric air-fuel ratio by mass. lhv: lower heating value, J/kg. latent: heat of evaporation, J/kg.
// octane: research octane number (RON), which sets how far the ignition can be advanced before the engine knocks.
// The petrol grades (RON 90, 92, 95, 98) share gasoline's chemistry and differ only in octane.
// E85 is 80% ethanol by mass with 20% gasoline. Its values are the mass-weighted blend of the two components below, so
// fuel_chemistry_test checks them against the components:
//   ethanol:  afr 9.0, lhv 26.8 MJ/kg, latent 840 kJ/kg, density 789 kg/m3, octane 108
//   gasoline: afr 14.7, lhv 44 MJ/kg, latent 350 kJ/kg, density 745 kg/m3, octane 95

namespace engine_physics {

constexpr double FUEL_TANK_LITRES = 12.0;

struct FuelProperties {
    double afr;
    double lhv;
    double density;
    double latent;
    double octane;
};

// Looks up a fuel kind ("ron90", ..., "e85"). Throws std::out_of_range for an unknown kind.
const FuelProperties &fuel_properties(const std::string &kind);

// The fuel choices in the order the panel lists them, with the labels it shows.
extern const std::array<const char *, 6> FUEL_KINDS;
extern const std::array<const char *, 6> FUEL_LABELS;

class FuelTank {
public:
    std::string kind = "ron95";
    double afr = 0.0;
    double lhv = 0.0;
    double latent = 0.0;
    double octane = 0.0;
    double mass_kg = 0.0;
    double capacity_litres = FUEL_TANK_LITRES;

    FuelTank();

    // Switching fuel type fills the tank with the new fuel.
    void set_kind(const std::string &new_kind);
    void refill();
    double fraction() const;
    void set_capacity(double litres);

private:
    void apply_kind(const std::string &new_kind);
};

} // namespace engine_physics

#endif // FUEL_MODEL_H
