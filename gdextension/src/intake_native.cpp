#include "intake_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

using namespace godot;

namespace {

std::string str(const String &s) {
	return std::string(s.utf8().get_data());
}

std::vector<engine_sim::FlowPr> flow_pr(const Array &a) {
	std::vector<engine_sim::FlowPr> out;
	for (int i = 0; i < a.size(); i++) {
		Array p = a[i];
		out.push_back({ double(p[0]), double(p[1]) });
	}
	return out;
}

} // namespace

// Copies the IntakeSpec fields from a dictionary. Fields not in the dictionary keep the IntakeSpec defaults.
void IntakeNative::set_spec(const Dictionary &d) {
	spec = engine_sim::IntakeSpec();
	spec.electric_compressor = d.get("electric_compressor", spec.electric_compressor);
	spec.compressor_map_id = str(d.get("compressor_map_id", String()));
	spec.max_boost_ratio = d.get("max_boost_ratio", spec.max_boost_ratio);
	spec.compressor_battery_wh = d.get("compressor_battery_wh", spec.compressor_battery_wh);
	spec.compressor_power_w = d.get("compressor_power_w", spec.compressor_power_w);
	spec.compressor_charge_w = d.get("compressor_charge_w", spec.compressor_charge_w);
	spec.boost_spool_time = d.get("boost_spool_time", spec.boost_spool_time);
	spec.compressor_inertia_kgm2 = d.get("compressor_inertia_kgm2", spec.compressor_inertia_kgm2);
	spec.wastegate_type = str(d.get("wastegate_type", String(spec.wastegate_type.c_str())));
	spec.wastegate_pressure_ratio = d.get("wastegate_pressure_ratio", spec.wastegate_pressure_ratio);
	spec.turbine_efficiency = d.get("turbine_efficiency", spec.turbine_efficiency);
	spec.intake_area_scale = d.get("intake_area_scale", spec.intake_area_scale);
	spec.throttle_bore_mm = d.get("throttle_bore_mm", spec.throttle_bore_mm);
	spec.throttle_count = d.get("throttle_count", spec.throttle_count);
	spec.manifold_volume_scale = d.get("manifold_volume_scale", spec.manifold_volume_scale);
}

// Full setup: spec plus the compressor map, and a fresh model. Called at the start of a run and when the map id changes.
void IntakeNative::setup(const Dictionary &d, const Dictionary &m) {
	set_spec(d);

	std::shared_ptr<engine_sim::CompressorMap> map;
	if (!m.is_empty()) {
		map = std::make_shared<engine_sim::CompressorMap>();
		map->ref_temp_k = m.get("ref_temp_k", map->ref_temp_k);
		map->ref_pressure_pa = m.get("ref_pressure_pa", map->ref_pressure_pa);
		Array lines = m.get("speed_lines", Array());
		for (int i = 0; i < lines.size(); i++) {
			Array line = lines[i];
			engine_sim::SpeedLine sl;
			sl.speed_rpm = line[0];
			Array pts = line[1];
			for (int j = 0; j < pts.size(); j++) {
				Array p = pts[j];
				sl.points.push_back({ double(p[0]), double(p[1]), double(p[2]) });
			}
			map->speed_lines.push_back(sl);
		}
		map->surge_line = flow_pr(m.get("surge_line", Array()));
		map->choke_line = flow_pr(m.get("choke_line", Array()));
		map->sort_points();
	}
	model = engine_sim::IntakeModel();
	model.setup(spec, map);
}

double IntakeNative::map_correct_flow(double m_dot, double T, double P) const {
	return model.compressor_map ? model.compressor_map->correct_flow(m_dot, T, P) : m_dot;
}

double IntakeNative::map_correct_speed(double speed_rpm, double T) const {
	return model.compressor_map ? model.compressor_map->correct_speed(speed_rpm, T) : speed_rpm;
}

void IntakeNative::manifold_update(double dt, double throttle, double drawn_kg_s, double rpm, bool running, double bike_speed_ms) {
	model.manifold_update(dt, throttle, drawn_kg_s, &spec, rpm, running, bike_speed_ms);
}

void IntakeNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "spec_dict", "map_dict"), &IntakeNative::setup);
	ClassDB::bind_method(D_METHOD("get_bypass_area"), &IntakeNative::get_bypass_area);
	ClassDB::bind_method(D_METHOD("set_bypass_area", "v"), &IntakeNative::set_bypass_area);
	ClassDB::bind_method(D_METHOD("get_limiter_cut"), &IntakeNative::get_limiter_cut);
	ClassDB::bind_method(D_METHOD("set_limiter_cut", "v"), &IntakeNative::set_limiter_cut);
	ClassDB::bind_method(D_METHOD("get_boost_ratio"), &IntakeNative::get_boost_ratio);
	ClassDB::bind_method(D_METHOD("set_boost_ratio", "v"), &IntakeNative::set_boost_ratio);
	ClassDB::bind_method(D_METHOD("get_compressor_load"), &IntakeNative::get_compressor_load);
	ClassDB::bind_method(D_METHOD("set_compressor_load", "v"), &IntakeNative::set_compressor_load);
	ClassDB::bind_method(D_METHOD("get_compressor_charge"), &IntakeNative::get_compressor_charge);
	ClassDB::bind_method(D_METHOD("set_compressor_charge", "v"), &IntakeNative::set_compressor_charge);
	ClassDB::bind_method(D_METHOD("has_map"), &IntakeNative::has_map);
	ClassDB::bind_method(D_METHOD("map_correct_flow", "m_dot", "T", "P"), &IntakeNative::map_correct_flow);
	ClassDB::bind_method(D_METHOD("map_correct_speed", "speed_rpm", "T"), &IntakeNative::map_correct_speed);
	ClassDB::bind_method(D_METHOD("get_pressure"), &IntakeNative::get_pressure);
	// read-only values the simulator reads as plain variables (the getters are the methods bound above)
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "pressure"), "", "get_pressure");
	ClassDB::bind_method(D_METHOD("get_compressor_pr"), &IntakeNative::get_compressor_pr);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "compressor_pr"), "", "get_compressor_pr");
	ClassDB::bind_method(D_METHOD("get_compressor_speed_rpm"), &IntakeNative::get_compressor_speed_rpm);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "compressor_speed_rpm"), "", "get_compressor_speed_rpm");
	ClassDB::bind_method(D_METHOD("get_ram_air_boost"), &IntakeNative::get_ram_air_boost);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "ram_air_boost"), "", "get_ram_air_boost");
	ClassDB::bind_method(D_METHOD("get_surge_count"), &IntakeNative::get_surge_count);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "surge_count"), "", "get_surge_count");
	ClassDB::bind_method(D_METHOD("get_choke_count"), &IntakeNative::get_choke_count);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "choke_count"), "", "get_choke_count");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "bypass_area"), "set_bypass_area", "get_bypass_area");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "limiter_cut"), "set_limiter_cut", "get_limiter_cut");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "boost_ratio"), "set_boost_ratio", "get_boost_ratio");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "compressor_load"), "set_compressor_load", "get_compressor_load");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "compressor_charge"), "set_compressor_charge", "get_compressor_charge");
	ClassDB::bind_method(D_METHOD("set_spec", "spec_dict"), &IntakeNative::set_spec);
	ClassDB::bind_method(D_METHOD("manifold_update", "dt", "throttle", "drawn_kg_s", "rpm", "running", "bike_speed_ms"), &IntakeNative::manifold_update);
}
