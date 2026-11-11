#include "exhaust_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

using namespace godot;

void ExhaustNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build", "layout"), &ExhaustNative::build);
	ClassDB::bind_method(D_METHOD("port_pressure", "cylinder_index"), &ExhaustNative::port_pressure);
	ClassDB::bind_method(D_METHOD("port_temperature", "cylinder_index"), &ExhaustNative::port_temperature);
	ClassDB::bind_method(D_METHOD("apply_valve", "cylinder_index", "mdot", "power"), &ExhaustNative::apply_valve);
	ClassDB::bind_method(D_METHOD("add_energy", "cylinder_index", "joules"), &ExhaustNative::add_energy);
	ClassDB::bind_method(D_METHOD("station_pressure", "pipe_index"), &ExhaustNative::station_pressure);
	ClassDB::bind_method(D_METHOD("tail_volume_flow"), &ExhaustNative::tail_volume_flow);
	ClassDB::bind_method(D_METHOD("take_flow"), &ExhaustNative::take_flow);
	ClassDB::bind_method(D_METHOD("advance", "dt"), &ExhaustNative::advance);
	ClassDB::bind_method(D_METHOD("set_record_audio", "record"), &ExhaustNative::set_record_audio);
}

void ExhaustNative::build(const Dictionary &layout) {
	engine_sim::ExhaustLayoutData data;
	data.scene_per_m = static_cast<double>(layout.get("scene_per_m", 10.0));
	Array pipes = layout.get("pipes", Array());
	for (int i = 0; i < pipes.size(); i++) {
		Dictionary d = pipes[i];
		engine_sim::ExhaustPipe pipe;
		PackedVector3Array pts = d.get("pts", PackedVector3Array());
		PackedFloat64Array radii = d.get("radii", PackedFloat64Array());
		// ExhaustPipe needs one radius per point
		ERR_FAIL_COND_MSG(radii.size() != pts.size(), "ExhaustNative.build: radii and pts must be the same length.");
		for (int k = 0; k < pts.size(); k++) {
			pipe.pts.push_back({ pts[k].x, pts[k].y, pts[k].z });
			pipe.radii.push_back(static_cast<float>(radii[k]));
		}
		pipe.cyl = static_cast<int>(d.get("cyl", -1));
		PackedInt32Array feeders = d.get("feeders", PackedInt32Array());
		for (int k = 0; k < feeders.size(); k++) {
			pipe.feeders.push_back(feeders[k]);
		}
		pipe.loss = static_cast<float>(static_cast<double>(d.get("loss", 0.25)));
		data.pipes.push_back(std::move(pipe));
	}
	gas.build(data);
}

double ExhaustNative::port_pressure(int cylinder_index) const { return gas.port_pressure(cylinder_index); }
double ExhaustNative::port_temperature(int cylinder_index) const { return gas.port_temperature(cylinder_index); }
void ExhaustNative::apply_valve(int cylinder_index, double mdot, double power) { gas.apply_valve(cylinder_index, mdot, power); }
void ExhaustNative::add_energy(int cylinder_index, double joules) { gas.add_energy(cylinder_index, joules); }
double ExhaustNative::station_pressure(int pipe_index) const { return gas.station_pressure(pipe_index); }
double ExhaustNative::tail_volume_flow() const { return gas.tail_volume_flow(); }

PackedFloat32Array ExhaustNative::take_flow() {
	std::vector<float> flow = gas.take_flow();
	PackedFloat32Array out;
	out.resize(static_cast<int64_t>(flow.size()));
	for (size_t i = 0; i < flow.size(); i++) {
		out[static_cast<int64_t>(i)] = flow[i];
	}
	return out;
}

void ExhaustNative::advance(double dt) { gas.advance(dt); }
void ExhaustNative::set_record_audio(bool record) { gas.record_audio = record; }
