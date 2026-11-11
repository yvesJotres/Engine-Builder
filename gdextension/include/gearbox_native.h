#ifndef GEARBOX_NATIVE_H
#define GEARBOX_NATIVE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include "gearbox.h"

// Godot wrapper over engine_physics::Gearbox (mirror of scripts/drivetrain/gearbox.gd).
namespace godot {

class GearboxNative : public RefCounted {
	GDCLASS(GearboxNative, RefCounted)

	engine_physics::Gearbox box;

protected:
	static void _bind_methods();

public:
	static PackedFloat64Array ratios();

	int64_t get_gear() const;
	void set_gear(int64_t gear);
	PackedFloat64Array get_gear_ratios() const;
	void set_gear_ratios(const PackedFloat64Array &ratios);
	double ratio() const;
	void shift_up();
	void shift_down();
	String label() const;
};

} // namespace godot

#endif // GEARBOX_NATIVE_H
