#include "gearbox_native.h"

#include <godot_cpp/core/class_db.hpp>

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

void GearboxNative::_bind_methods() {
	ClassDB::bind_static_method("GearboxNative", D_METHOD("ratios"), &GearboxNative::ratios);
	ClassDB::bind_method(D_METHOD("get_gear"), &GearboxNative::get_gear);
	ClassDB::bind_method(D_METHOD("set_gear", "gear"), &GearboxNative::set_gear);
	ClassDB::bind_method(D_METHOD("get_gear_ratios"), &GearboxNative::get_gear_ratios);
	ClassDB::bind_method(D_METHOD("set_gear_ratios", "ratios"), &GearboxNative::set_gear_ratios);
	ClassDB::bind_method(D_METHOD("ratio"), &GearboxNative::ratio);
	ClassDB::bind_method(D_METHOD("shift_up"), &GearboxNative::shift_up);
	ClassDB::bind_method(D_METHOD("shift_down"), &GearboxNative::shift_down);
	ClassDB::bind_method(D_METHOD("label"), &GearboxNative::label);
}

PackedFloat64Array GearboxNative::ratios() { return to_packed(engine_physics::Gearbox::ratios()); }
int64_t GearboxNative::get_gear() const { return box.gear; }
void GearboxNative::set_gear(int64_t gear) { box.gear = (int)gear; }
PackedFloat64Array GearboxNative::get_gear_ratios() const { return to_packed(box.gear_ratios); }

void GearboxNative::set_gear_ratios(const PackedFloat64Array &r) {
	box.gear_ratios.assign(r.ptr(), r.ptr() + r.size());
}

double GearboxNative::ratio() const { return box.ratio(); }
void GearboxNative::shift_up() { box.shift_up(); }
void GearboxNative::shift_down() { box.shift_down(); }
String GearboxNative::label() const { return String(box.label().c_str()); }
