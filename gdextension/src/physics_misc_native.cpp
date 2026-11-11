#include "physics_misc_native.h"

#include <godot_cpp/core/class_db.hpp>

#include "friction_model.h"
#include "isentropic_flow.h"

using namespace godot;

void PhysicsMiscNative::_bind_methods() {
	ClassDB::bind_static_method("PhysicsMiscNative", D_METHOD("calculate_friction", "v_s", "wall_normal_force", "params"),
			&PhysicsMiscNative::calculate_friction, DEFVAL(Dictionary()));
	ClassDB::bind_static_method("PhysicsMiscNative", D_METHOD("flow_rate", "p_up", "t_up", "p_down", "k_flow", "gamma", "r"),
			&PhysicsMiscNative::flow_rate);
}

double PhysicsMiscNative::calculate_friction(double v_s, double wall_normal_force, const Dictionary &params) {
	engine_sim::FrictionParams p;
	p.frictionCoeff = params.get("friction_coeff", p.frictionCoeff);
	p.breakawayFriction = params.get("breakaway_friction", p.breakawayFriction);
	p.breakawayFrictionVelocity = params.get("breakaway_friction_velocity", p.breakawayFrictionVelocity);
	p.viscousFrictionCoefficient = params.get("viscous_friction_coefficient", p.viscousFrictionCoefficient);
	return engine_sim::calculateFriction(v_s, wall_normal_force, p);
}

double PhysicsMiscNative::flow_rate(double p_up, double t_up, double p_down, double k_flow, double gamma, double r) {
	return engine_sim::isentropic::flowRate(p_up, t_up, p_down, k_flow, gamma, r);
}
