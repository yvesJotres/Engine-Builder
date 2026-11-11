#ifndef INTAKE_NATIVE_H
#define INTAKE_NATIVE_H

#include "intake_model.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

// Godot wrapper around engine_sim::IntakeModel (port of scripts/intake/engine_air.gd).
// tests/unit/intake/intake_native_test.gd compares it against the GDScript EngineAir.
namespace godot {

class IntakeNative : public RefCounted {
	GDCLASS(IntakeNative, RefCounted)

	engine_sim::IntakeModel model;
	engine_sim::IntakeSpec spec;

protected:
	static void _bind_methods();

public:
	// spec_dict: IntakeSpec field names. map_dict: speed_lines, surge_line, choke_line (+ optional ref_temp_k, ref_pressure_pa)
	// in the JSON layout of assets/compressor_maps/. An empty map_dict means no map.
	void setup(const Dictionary &spec_dict, const Dictionary &map_dict);
	// Refreshes the spec only (no map reload, no model reset): cheap enough to call every frame.
	void set_spec(const Dictionary &spec_dict);
	// getters for the read-only properties (a property sharing a bound method's name resolves to the method in GDScript)
	double get_pressure() const { return model.pressure; }
	double get_compressor_pr() const { return model.compressor_pr; }
	double get_compressor_speed_rpm() const { return model.compressor_speed_rpm; }
	double get_ram_air_boost() const { return model.ram_air_boost; }
	int get_surge_count() const { return model.surge_count; }
	int get_choke_count() const { return model.choke_count; }
	void manifold_update(double dt, double throttle, double drawn_kg_s, double rpm, bool running, double bike_speed_ms);

	double pressure() const { return model.pressure; }
	double boost_ratio() const { return model.boost_ratio; }
	double compressor_pr() const { return model.compressor_pr; }
	double compressor_speed_rpm() const { return model.compressor_speed_rpm; }
	double ram_air_boost() const { return model.ram_air_boost; }
	int surge_count() const { return model.surge_count; }
	int choke_count() const { return model.choke_count; }

	// The fields the simulator writes each step (EngineAir keeps these as plain variables).
	double get_bypass_area() const { return model.bypass_area; }
	void set_bypass_area(double v) { model.bypass_area = v; }
	bool get_limiter_cut() const { return model.limiter_cut; }
	void set_limiter_cut(bool v) { model.limiter_cut = v; }
	double get_boost_ratio() const { return model.boost_ratio; }
	void set_boost_ratio(double v) { model.boost_ratio = v; }
	double get_compressor_load() const { return model.compressor_load; }
	void set_compressor_load(double v) { model.compressor_load = v; }
	double get_compressor_charge() const { return model.compressor_charge; }
	void set_compressor_charge(double v) { model.compressor_charge = v; }

	// The compressor map queries the control panel uses (GDScript compressor_map.gd: correct_flow and correct_speed).
	// Both return the input unchanged when there is no map, so the panel can call them without a null check.
	bool has_map() const { return model.compressor_map != nullptr; }
	double map_correct_flow(double m_dot, double T, double P) const;
	double map_correct_speed(double speed_rpm, double T) const;
};

} // namespace godot

#endif // INTAKE_NATIVE_H
