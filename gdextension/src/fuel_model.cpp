#include "fuel_model.h"

#include <algorithm>
#include <map>
#include <stdexcept>

namespace engine_physics {

// Values from scripts/fuel/fuel.gd PROPERTIES. Keys match the GDScript keys.
static const std::map<std::string, FuelProperties> &properties_table() {
    static const std::map<std::string, FuelProperties> table = {
        {"ron90", {14.7, 44e6, 745.0, 350e3, 90.0}},
        {"ron92", {14.7, 44e6, 745.0, 350e3, 92.0}},
        {"ron95", {14.7, 44e6, 745.0, 350e3, 95.0}},
        {"ron98", {14.7, 44e6, 745.0, 350e3, 98.0}},
        {"ron100", {14.7, 44e6, 745.0, 350e3, 100.0}},
        {"e85", {9.76, 30.2e6, 780.0, 742e3, 105.0}},
    };
    return table;
}

const FuelProperties &fuel_properties(const std::string &kind) {
    auto it = properties_table().find(kind);
    if (it == properties_table().end()) {
        throw std::out_of_range("unknown fuel kind: " + kind);
    }
    return it->second;
}

// The fuel choices in the order the panel lists them, with the labels it shows.
const std::array<const char *, 6> FUEL_KINDS = {"ron90", "ron92", "ron95", "ron98", "ron100", "e85"};
const std::array<const char *, 6> FUEL_LABELS = {"RON 90", "RON 92", "RON 95", "RON 98", "RON 100", "E85"};

FuelTank::FuelTank() {
    apply_kind(kind);
    refill();
}

// Switching fuel type fills the tank with the new fuel.
void FuelTank::set_kind(const std::string &new_kind) {
    if (new_kind != kind) {
        apply_kind(new_kind);
        refill();
    }
}

void FuelTank::refill() {
    mass_kg = capacity_litres * fuel_properties(kind).density / 1000.0;
}

double FuelTank::fraction() const {
    return mass_kg / (capacity_litres * fuel_properties(kind).density / 1000.0);
}

void FuelTank::set_capacity(double litres) {
    double level = std::clamp(fraction(), 0.0, 1.0);
    capacity_litres = std::max(litres, 0.1);
    mass_kg = level * capacity_litres * fuel_properties(kind).density / 1000.0;
}

void FuelTank::apply_kind(const std::string &new_kind) {
    kind = new_kind;
    const FuelProperties &p = fuel_properties(kind);
    afr = p.afr;
    lhv = p.lhv;
    latent = p.latent;
    octane = p.octane;
}

} // namespace engine_physics
