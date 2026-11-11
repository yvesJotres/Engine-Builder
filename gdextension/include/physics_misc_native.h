#ifndef PHYSICS_MISC_NATIVE_H
#define PHYSICS_MISC_NATIVE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

// Godot wrapper over friction_model.h (Stribeck piston-ring friction) and isentropic_flow.h (nozzle flow rate).
namespace godot {

class PhysicsMiscNative : public RefCounted {
	GDCLASS(PhysicsMiscNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// params keys (optional, ATG defaults): friction_coeff 0.06, breakaway_friction 50, breakaway_friction_velocity 0.1,
	// viscous_friction_coefficient 20.
	static double calculate_friction(double v_s, double wall_normal_force, const Dictionary &params);
	static double flow_rate(double p_up, double t_up, double p_down, double k_flow, double gamma, double r);
};

} // namespace godot

#endif // PHYSICS_MISC_NATIVE_H
