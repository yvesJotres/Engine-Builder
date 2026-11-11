#ifndef FUEL_NATIVE_H
#define FUEL_NATIVE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include "fuel_model.h"

// Godot wrapper over engine_physics::FuelTank (mirror of scripts/fuel/fuel.gd FuelTank).
namespace godot {

class FuelNative : public RefCounted {
	GDCLASS(FuelNative, RefCounted)

	engine_physics::FuelTank tank;

protected:
	static void _bind_methods();

public:
	static Dictionary properties(const String &kind); // empty for an unknown kind
	static PackedStringArray kinds();
	static PackedStringArray labels();

	void set_kind(const String &kind); // unknown kinds are ignored
	void refill();
	double fraction() const;
	void set_capacity(double litres);

	String get_kind() const;
	double get_afr() const;
	double get_lhv() const;
	double get_latent() const;
	double get_octane() const;
	double get_mass_kg() const;
	void set_mass_kg(double kg);
	double get_capacity_litres() const;
};

} // namespace godot

#endif // FUEL_NATIVE_H
