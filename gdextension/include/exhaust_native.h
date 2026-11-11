#ifndef EXHAUST_NATIVE_H
#define EXHAUST_NATIVE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include "exhaust_gas.h"

// Godot wrapper for engine_sim::ExhaustGas. Mirrors scripts/exhaust/exhaust_gas.gd; tests/unit/exhaust/exhaust_native_test.gd compares them.
// build() takes {"scene_per_m": float, "pipes": [{pts: PackedVector3Array, radii: PackedFloat64Array, cyl: int,
// feeders: PackedInt32Array, loss: float}]}, pipes upstream first, the last one the tailpipe.
namespace godot {

class ExhaustNative : public RefCounted {
	GDCLASS(ExhaustNative, RefCounted)

	engine_sim::ExhaustGas gas;

protected:
	static void _bind_methods();

public:
	void build(const Dictionary &layout);
	double port_pressure(int cylinder_index) const;
	double port_temperature(int cylinder_index) const;
	void apply_valve(int cylinder_index, double mdot, double power);
	void add_energy(int cylinder_index, double joules);
	double station_pressure(int pipe_index) const;
	double tail_volume_flow() const;
	PackedFloat32Array take_flow();
	void advance(double dt);
	void set_record_audio(bool record);
};

} // namespace godot

#endif // EXHAUST_NATIVE_H
