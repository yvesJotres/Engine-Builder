#ifndef TWO_STROKE_KERNEL_H
#define TWO_STROKE_KERNEL_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

// Native copy of TwoStrokeCylinder.advance in scripts/engine/two_stroke_cylinder.gd (and what it calls). It is a pure function:
// the caller passes the cylinder's mutable state as one PackedFloat64Array and gets the updated array back, the same pattern as
// CylinderKernel. tests/unit/engine/two_stroke_native_test.gd compares it with the GDScript.
namespace godot {

class TwoStrokeKernel : public RefCounted {
	GDCLASS(TwoStrokeKernel, RefCounted)

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
		S_CRANKCASE_MASS, S_CRANKCASE_TEMP, S_CRANKCASE_PRESSURE, S_OIL_IN_CRANKCASE_KG,
		S_TANK_MASS, // in and out: kg of fuel left in the tank
		S_OUT_WORK, // out: cycle work returned by advance (Vector2.x), J
		S_OUT_FUEL, // out: fuel consumed returned by advance (Vector2.y), kg (the GDScript never sets it, so always 0)
		S_SIZE
	};

	// Config array layout (doubles), fixed for the life of a cylinder.
	enum ConfigIndex {
		C_BORE = 0, C_PISTON_AREA, C_STROKE, C_SWEPT, C_CLEARANCE, C_RECIP_KG, C_ROD_RATIO, C_TRANSFER_OPEN, C_TRANSFER_CLOSE,
		C_EXHAUST_OPEN, C_EXHAUST_CLOSE, C_INTAKE_OPEN, C_INTAKE_CLOSE, C_TRANSFER_AREA, C_EXHAUST_AREA, C_INTAKE_AREA,
		C_CRANKCASE_VOLUME, C_OIL_RATIO,
		C_INTAKE_TYPE, // 1 = reed, 2 = rotary or piston port, 0 = anything else (no intake flow)
		C_CRANK_RADIUS, // the member crank_radius of the GDScript (0 until _get_crank_radius is called, which advance never does)
		C_SIZE
	};

	static int64_t state_size() { return S_SIZE; }
	static int64_t config_size() { return C_SIZE; }

	// Same arguments as TwoStrokeCylinder.advance, with the tank's afr and lhv passed in and its mass carried in state[S_TANK_MASS].
	static PackedFloat64Array advance(PackedFloat64Array state, const PackedFloat64Array &cfg, double dphi, double dt,
			double intake_p, double intake_temp, double ign_phi, bool running, double tank_afr, double tank_lhv, double lambda,
			bool spark, bool limiter_cut, double p_ex, double t_ex);
};

} // namespace godot

#endif // TWO_STROKE_KERNEL_H
