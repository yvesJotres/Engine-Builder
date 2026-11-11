#include "fuel_native.h"

#include <stdexcept>

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void FuelNative::_bind_methods() {
	ClassDB::bind_static_method("FuelNative", D_METHOD("properties", "kind"), &FuelNative::properties);
	ClassDB::bind_static_method("FuelNative", D_METHOD("kinds"), &FuelNative::kinds);
	ClassDB::bind_static_method("FuelNative", D_METHOD("labels"), &FuelNative::labels);
	ClassDB::bind_method(D_METHOD("set_kind", "kind"), &FuelNative::set_kind);
	ClassDB::bind_method(D_METHOD("refill"), &FuelNative::refill);
	ClassDB::bind_method(D_METHOD("fraction"), &FuelNative::fraction);
	ClassDB::bind_method(D_METHOD("set_capacity", "litres"), &FuelNative::set_capacity);
	ClassDB::bind_method(D_METHOD("get_kind"), &FuelNative::get_kind);
	ClassDB::bind_method(D_METHOD("get_afr"), &FuelNative::get_afr);
	ClassDB::bind_method(D_METHOD("get_lhv"), &FuelNative::get_lhv);
	ClassDB::bind_method(D_METHOD("get_latent"), &FuelNative::get_latent);
	ClassDB::bind_method(D_METHOD("get_octane"), &FuelNative::get_octane);
	ClassDB::bind_method(D_METHOD("get_mass_kg"), &FuelNative::get_mass_kg);
	ClassDB::bind_method(D_METHOD("set_mass_kg", "kg"), &FuelNative::set_mass_kg);
	ClassDB::bind_method(D_METHOD("get_capacity_litres"), &FuelNative::get_capacity_litres);
}

Dictionary FuelNative::properties(const String &kind) {
	Dictionary d;
	try {
		const engine_physics::FuelProperties &p = engine_physics::fuel_properties(kind.utf8().get_data());
		d["afr"] = p.afr;
		d["lhv"] = p.lhv;
		d["density"] = p.density;
		d["latent"] = p.latent;
		d["octane"] = p.octane;
	} catch (const std::out_of_range &) {
	}
	return d;
}

PackedStringArray FuelNative::kinds() {
	PackedStringArray out;
	for (const char *k : engine_physics::FUEL_KINDS) {
		out.push_back(String(k));
	}
	return out;
}

PackedStringArray FuelNative::labels() {
	PackedStringArray out;
	for (const char *k : engine_physics::FUEL_LABELS) {
		out.push_back(String(k));
	}
	return out;
}

void FuelNative::set_kind(const String &kind) {
	try {
		tank.set_kind(kind.utf8().get_data());
	} catch (const std::out_of_range &) {
	}
}

void FuelNative::refill() { tank.refill(); }
double FuelNative::fraction() const { return tank.fraction(); }
void FuelNative::set_capacity(double litres) { tank.set_capacity(litres); }
String FuelNative::get_kind() const { return String(tank.kind.c_str()); }
double FuelNative::get_afr() const { return tank.afr; }
double FuelNative::get_lhv() const { return tank.lhv; }
double FuelNative::get_latent() const { return tank.latent; }
double FuelNative::get_octane() const { return tank.octane; }
double FuelNative::get_mass_kg() const { return tank.mass_kg; }
void FuelNative::set_mass_kg(double kg) { tank.mass_kg = kg; }
double FuelNative::get_capacity_litres() const { return tank.capacity_litres; }
