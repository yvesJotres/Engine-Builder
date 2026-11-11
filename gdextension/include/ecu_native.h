#ifndef ECU_NATIVE_H
#define ECU_NATIVE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include "ecu_model.h"

// Godot wrapper over engine_physics::EcuModel, a native copy of scripts/ecu/ecu.gd. The spec argument is a Dictionary
// carrying only the EngineSpec fields the ECU reads (quickshifter, quickshifter_cut_time, quickshifter_cut_profile,
// quickshifter_blip_time, quickshifter_blip_throttle, quickshifter_flat_shift, flat_shift_throttle, launch_control,
// launch_rpm, launch_throttle, launch_speed_kmh, redline_rpm, speed_limit_enabled, speed_limit_kmh). An empty
// Dictionary stands for ecu.gd's null spec. tests/unit/ecu/ecu_native_test.gd checks it against ecu.gd.
namespace godot {

class EcuNative : public RefCounted {
	GDCLASS(EcuNative, RefCounted)

protected:
	static void _bind_methods();

public:
	void set_power_mode(const String &p_mode);
	double get_power_mode_lambda_mult() const;
	double get_power_mode_timing_offset() const;
	bool is_quickshifter_active() const;
	bool is_quickshifter_blip_active() const;
	bool is_launch_active() const;
	double get_launch_target_rpm() const;

	double update(double dt, double rpm, double throttle, bool running, const Dictionary &spec, double speed_ms, double clutch_pull, int64_t gear);
	double air_factor() const;
	bool overrun() const;
	bool trigger_quickshifter(const Dictionary &spec);
	bool trigger_quickshifter_downshift(const Dictionary &spec);
	bool quickshifter_cut_active() const;
	bool quickshifter_blip_active() const;

	void set_target_rpm(double v);
	double get_target_rpm() const;
	void set_trim(double v);
	double get_trim() const;
	void set_manual_air(double v);
	double get_manual_air() const;

private:
	engine_physics::EcuModel model_;
};

} // namespace godot

#endif // ECU_NATIVE_H
