#include "ecu_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

using namespace godot;

static engine_physics::EcuSpec to_spec(const Dictionary &d) {
	engine_physics::EcuSpec s;
	s.quickshifter = d.get("quickshifter", s.quickshifter);
	s.quickshifter_cut_time = d.get("quickshifter_cut_time", s.quickshifter_cut_time);
	s.quickshifter_blip_time = d.get("quickshifter_blip_time", s.quickshifter_blip_time);
	s.quickshifter_blip_throttle = d.get("quickshifter_blip_throttle", s.quickshifter_blip_throttle);
	s.quickshifter_flat_shift = d.get("quickshifter_flat_shift", s.quickshifter_flat_shift);
	s.flat_shift_throttle = d.get("flat_shift_throttle", s.flat_shift_throttle);
	s.launch_control = d.get("launch_control", s.launch_control);
	s.launch_rpm = d.get("launch_rpm", s.launch_rpm);
	s.launch_throttle = d.get("launch_throttle", s.launch_throttle);
	s.launch_speed_kmh = d.get("launch_speed_kmh", s.launch_speed_kmh);
	s.redline_rpm = d.get("redline_rpm", s.redline_rpm);
	s.speed_limit_enabled = d.get("speed_limit_enabled", s.speed_limit_enabled);
	s.speed_limit_kmh = d.get("speed_limit_kmh", s.speed_limit_kmh);
	s.decel_cut = d.get("decel_cut", s.decel_cut);
	Array gears = d.get("quickshifter_cut_profile", Array());
	for (int i = 0; i < gears.size(); i++) {
		Array pts = gears[i];
		std::vector<std::array<double, 2>> profile;
		for (int j = 0; j < pts.size(); j++) {
			Array pt = pts[j];
			profile.push_back({ (double)pt[0], (double)pt[1] });
		}
		s.quickshifter_cut_profile.push_back(profile);
	}
	return s;
}

void EcuNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_power_mode", "mode"), &EcuNative::set_power_mode);
	ClassDB::bind_method(D_METHOD("get_power_mode_lambda_mult"), &EcuNative::get_power_mode_lambda_mult);
	ClassDB::bind_method(D_METHOD("get_power_mode_timing_offset"), &EcuNative::get_power_mode_timing_offset);
	ClassDB::bind_method(D_METHOD("is_quickshifter_active"), &EcuNative::is_quickshifter_active);
	ClassDB::bind_method(D_METHOD("is_quickshifter_blip_active"), &EcuNative::is_quickshifter_blip_active);
	ClassDB::bind_method(D_METHOD("is_launch_active"), &EcuNative::is_launch_active);
	ClassDB::bind_method(D_METHOD("get_launch_target_rpm"), &EcuNative::get_launch_target_rpm);
	ClassDB::bind_method(D_METHOD("update", "dt", "rpm", "throttle", "running", "spec", "speed_ms", "clutch_pull", "gear"), &EcuNative::update, DEFVAL(Dictionary()), DEFVAL(0.0), DEFVAL(0.0), DEFVAL(0));
	ClassDB::bind_method(D_METHOD("air_factor"), &EcuNative::air_factor);
	ClassDB::bind_method(D_METHOD("overrun"), &EcuNative::overrun);
	ClassDB::bind_method(D_METHOD("trigger_quickshifter", "spec"), &EcuNative::trigger_quickshifter);
	ClassDB::bind_method(D_METHOD("trigger_quickshifter_downshift", "spec"), &EcuNative::trigger_quickshifter_downshift);
	ClassDB::bind_method(D_METHOD("quickshifter_cut_active"), &EcuNative::quickshifter_cut_active);
	ClassDB::bind_method(D_METHOD("quickshifter_blip_active"), &EcuNative::quickshifter_blip_active);
	ClassDB::bind_method(D_METHOD("set_target_rpm", "v"), &EcuNative::set_target_rpm);
	ClassDB::bind_method(D_METHOD("get_target_rpm"), &EcuNative::get_target_rpm);
	ClassDB::bind_method(D_METHOD("set_trim", "v"), &EcuNative::set_trim);
	ClassDB::bind_method(D_METHOD("get_trim"), &EcuNative::get_trim);
	ClassDB::bind_method(D_METHOD("set_manual_air", "v"), &EcuNative::set_manual_air);
	ClassDB::bind_method(D_METHOD("get_manual_air"), &EcuNative::get_manual_air);
	// the GDScript ECU exposes these as plain variables, so engine code writes ecu.target_rpm and reads ecu.trim
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "target_rpm"), "set_target_rpm", "get_target_rpm");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "trim"), "set_trim", "get_trim");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "manual_air"), "set_manual_air", "get_manual_air");
}

void EcuNative::set_power_mode(const String &p_mode) { model_.set_power_mode(p_mode.utf8().get_data()); }
double EcuNative::get_power_mode_lambda_mult() const { return model_.get_power_mode_lambda_mult(); }
double EcuNative::get_power_mode_timing_offset() const { return model_.get_power_mode_timing_offset(); }
bool EcuNative::is_quickshifter_active() const { return model_.is_quickshifter_active(); }
bool EcuNative::is_quickshifter_blip_active() const { return model_.is_quickshifter_blip_active(); }
bool EcuNative::is_launch_active() const { return model_.is_launch_active(); }
double EcuNative::get_launch_target_rpm() const { return model_.get_launch_target_rpm(); }

double EcuNative::update(double dt, double rpm, double throttle, bool running, const Dictionary &spec, double speed_ms, double clutch_pull, int64_t gear) {
	if (spec.is_empty()) {
		return model_.update(dt, rpm, throttle, running, nullptr, speed_ms, clutch_pull, (int)gear);
	}
	engine_physics::EcuSpec s = to_spec(spec);
	return model_.update(dt, rpm, throttle, running, &s, speed_ms, clutch_pull, (int)gear);
}

double EcuNative::air_factor() const { return model_.air_factor(); }
bool EcuNative::overrun() const { return model_.overrun(); }
bool EcuNative::trigger_quickshifter(const Dictionary &spec) { return model_.trigger_quickshifter(to_spec(spec)); }
bool EcuNative::trigger_quickshifter_downshift(const Dictionary &spec) { return model_.trigger_quickshifter_downshift(to_spec(spec)); }
bool EcuNative::quickshifter_cut_active() const { return model_.is_quickshifter_active(); }
bool EcuNative::quickshifter_blip_active() const { return model_.is_quickshifter_blip_active(); }

void EcuNative::set_target_rpm(double v) { model_.target_rpm = v; }
double EcuNative::get_target_rpm() const { return model_.target_rpm; }
void EcuNative::set_trim(double v) { model_.trim = v; }
double EcuNative::get_trim() const { return model_.trim; }
void EcuNative::set_manual_air(double v) { model_.manual_air = v; }
double EcuNative::get_manual_air() const { return model_.manual_air; }
