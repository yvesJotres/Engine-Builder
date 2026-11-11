#include "firing_native.h"

#include <godot_cpp/core/class_db.hpp>

#include "firing_orders.h"

using namespace godot;

namespace {
PackedFloat64Array to_packed(const std::vector<double> &v) {
	PackedFloat64Array out;
	for (double x : v) {
		out.push_back(x);
	}
	return out;
}
} // namespace

void FiringNative::_bind_methods() {
	ClassDB::bind_static_method("FiringNative", D_METHOD("order_for", "cylinders"), &FiringNative::order_for);
	ClassDB::bind_static_method("FiringNative", D_METHOD("fired_between", "prev", "cur", "at"), &FiringNative::fired_between);
	ClassDB::bind_static_method("FiringNative", D_METHOD("fire_angles", "cylinders", "twin_pin_deg", "crossplane", "split_v4"),
			&FiringNative::fire_angles, DEFVAL(360.0), DEFVAL(false), DEFVAL(false));
	ClassDB::bind_static_method("FiringNative", D_METHOD("for_spec", "spec"), &FiringNative::for_spec);
}

PackedInt32Array FiringNative::order_for(int64_t cylinders) {
	PackedInt32Array out;
	for (int c : engine_physics::order_for((int)cylinders)) {
		out.push_back(c);
	}
	return out;
}

bool FiringNative::fired_between(double prev, double cur, double at) {
	return engine_physics::fired_between(prev, cur, at);
}

PackedFloat64Array FiringNative::fire_angles(int64_t cylinders, double twin_pin_deg, bool crossplane, bool split_v4) {
	return to_packed(engine_physics::fire_angles((int)cylinders, twin_pin_deg, crossplane, split_v4));
}

PackedFloat64Array FiringNative::for_spec(const Dictionary &spec) {
	engine_physics::FiringSpec s;
	s.cylinders = (int)(int64_t)spec.get("cylinders", 1);
	Array fd = spec.get("fire_deg", Array());
	for (int i = 0; i < fd.size(); i++) {
		s.fire_deg.push_back((double)fd[i]);
	}
	s.twin_pin_deg = spec.get("twin_pin_deg", 360.0);
	s.split_pin_v4 = spec.get("split_pin_v4", false);
	s.shared_v_crankpins = spec.get("shared_v_crankpins", false);
	s.crossplane = spec.get("crossplane", false);
	s.layout = String(spec.get("layout", "inline")).utf8().get_data();
	s.bank_angle = spec.get("bank_angle", 90.0);
	s.v3r_style = spec.get("v3r_style", false);
	return to_packed(engine_physics::for_spec(s));
}
