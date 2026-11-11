#include "engine_sim_clock.h"

#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>

void EngineSimClock::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "physics_dt", "max_frame_time"), &EngineSimClock::configure);
	ClassDB::bind_method(D_METHOD("consume", "delta"), &EngineSimClock::consume);
	ClassDB::bind_method(D_METHOD("reset"), &EngineSimClock::reset);
	ClassDB::bind_method(D_METHOD("last_steps"), &EngineSimClock::last_steps);
	ClassDB::bind_method(D_METHOD("accumulator"), &EngineSimClock::accumulator);
	ClassDB::bind_method(D_METHOD("physics_dt"), &EngineSimClock::physics_dt);
}

void EngineSimClock::configure(double physics_dt, double max_frame_time) {
	_physics_dt = std::max(physics_dt, 1.0e-9);
	_max_frame_time = std::max(max_frame_time, 0.0);
}

int EngineSimClock::consume(double delta) {
	if (!(delta > 0.0) || _physics_dt <= 0.0) {
		_last_steps = 0;
		return 0;
	}
	_accumulator = std::min(_accumulator + delta, _max_frame_time);
	const int steps = static_cast<int>(std::floor(_accumulator / _physics_dt));
	_accumulator -= static_cast<double>(steps) * _physics_dt;
	if (_accumulator < 0.0) {
		_accumulator = 0.0;
	}
	_last_steps = steps;
	return steps;
}

void EngineSimClock::reset() {
	_accumulator = 0.0;
	_last_steps = 0;
}

