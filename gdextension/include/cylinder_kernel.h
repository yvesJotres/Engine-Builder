#ifndef CYLINDER_KERNEL_H
#define CYLINDER_KERNEL_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

// Native copy of the hot loop in scripts/engine/cylinder.gd (Cylinder.advance and what it calls). It is a pure function:
// the caller passes the cylinder's mutable state as one PackedFloat64Array and gets the updated array back. The index
// tables below are mirrored by Cylinder.S_* / Cylinder.C_* in cylinder.gd; tests/unit/engine/cylinder_native_test.gd checks they agree.
namespace godot {

class CylinderKernel : public RefCounted {
	GDCLASS(CylinderKernel, RefCounted)

protected:
	static void _bind_methods();

public:
	// State array layout (doubles).
	enum StateIndex {
		S_PHI = 0, S_MASS, S_TEMP, S_PRESSURE, S_BURN_ENERGY_LEFT, S_BURN_ENERGY, S_PORT_P, S_RUNNER_Q, S_EXHAUST_TEMP,
		S_PEAK_TEMP, S_LAST_PEAK_TEMP, S_LAST_LAMBDA, S_FIRED, S_FUEL_UNBURNT_KG, S_PORT_HEAT, S_BACKFIRE_J, S_RESIDUAL_KG,
		S_OVERLAP_OUT, S_BURNT, S_WALL_LOSS_J, S_U, S_ENTHALPY_IN_J, S_ENTHALPY_OUT_J, S_EXHAUST_MDOT, S_EXHAUST_POWER,
		S_CYCLE_WORK, S_CYCLE_DEG, S_CYCLE_PEAK_P, S_CYCLE_MAX_DP, S_CYCLE_P, S_CA10, S_CA50, S_CA90, S_LAST_IMEP,
		S_LAST_PEAK_PRESSURE, S_LAST_DP_DTHETA, S_LAST_CA10, S_LAST_CA50, S_LAST_CA90, S_LAST_BURN_10_90, S_LAST_FRESH_KG,
		S_LAST_IVC_TEMP, S_LAST_RESIDUAL_FRACTION,
		S_TANK_MASS, // in and out: kg of fuel left in the tank
		S_OUT_TORQUE, // out: average gas torque over dphi, N*m
		S_OUT_DRAWN, // out: mass drawn from the manifold, kg
		S_FILM_KG, // fuel on the port wall, kg (in and out)
		S_BINS = 48, // 90 exhaust flow bins start here
		S_SIZE = 48 + 90
	};

	// Config array layout (doubles), fixed for the life of a cylinder.
	enum ConfigIndex {
		C_BORE = 0, C_PISTON_AREA, C_STROKE, C_SWEPT, C_CLEARANCE, C_RECIP_KG, C_ROD_RATIO, C_INTAKE_OPEN, C_INTAKE_CLOSE,
		C_EXHAUST_OPEN, C_EXHAUST_CLOSE, C_INTAKE_LIFT, C_EXHAUST_LIFT, C_INTAKE_VALVE_D, C_EXHAUST_VALVE_D, C_RUNNER_LENGTH,
		C_WALL_HEAT_SCALE, C_VALVE_CD, C_INTAKE_PROFILE, C_EXHAUST_PROFILE, C_INTAKE_OPEN_RAMP, C_INTAKE_CLOSE_RAMP,
		C_EXHAUST_OPEN_RAMP, C_EXHAUST_CLOSE_RAMP, C_INTAKE_DURATION_050, C_EXHAUST_DURATION_050, C_RUNNER_AREA,
		C_SIZE
	};

	static int64_t state_size() { return S_SIZE; }
	static int64_t config_size() { return C_SIZE; }

	// Same arguments as Cylinder.advance, with the tank's afr and lhv passed in and its mass carried in state[S_TANK_MASS].
	// icurve and ecurve are the custom lift curves flattened to [deg, mm, deg, mm, ...] (empty unless the lobe is CUSTOM).
	static PackedFloat64Array advance(PackedFloat64Array state, const PackedFloat64Array &cfg, const PackedFloat64Array &icurve,
			const PackedFloat64Array &ecurve, double dphi, double dt, double pm, double tm, double ign_phi, bool firing,
			double tank_afr, double tank_lhv, double lambda, bool spark, bool limiter_cut, double p_ex, double t_ex,
			double flow_step_deg);
};

} // namespace godot

#endif // CYLINDER_KERNEL_H
