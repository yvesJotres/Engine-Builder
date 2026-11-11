#ifndef FIRING_NATIVE_H
#define FIRING_NATIVE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

// Godot wrapper over firing_orders.h (mirror of scripts/engine/firing_orders.gd).
namespace godot {

class FiringNative : public RefCounted {
	GDCLASS(FiringNative, RefCounted)

protected:
	static void _bind_methods();

public:
	static PackedInt32Array order_for(int64_t cylinders);
	static bool fired_between(double prev, double cur, double at);
	static PackedFloat64Array fire_angles(int64_t cylinders, double twin_pin_deg = 360.0, bool crossplane = false, bool split_v4 = false);
	// spec keys (all optional, EngineSpec defaults): cylinders, fire_deg, twin_pin_deg, split_pin_v4, shared_v_crankpins,
	// crossplane, layout, bank_angle, v3r_style.
	static PackedFloat64Array for_spec(const Dictionary &spec);
};

} // namespace godot

#endif // FIRING_NATIVE_H
