#ifndef ENGINE_SIM_CLOCK_H
#define ENGINE_SIM_CLOCK_H

#include <godot_cpp/classes/ref_counted.hpp>

using namespace godot;

// Phase 1 of the C++ physics migration: the fixed-step clock that used to live in GDScript. It owns the
// accumulator and exposes the number of whole physics steps a frame must run. EngineSimCore will take over
// the actual step work next; keeping the clock in one place makes the migration checks exact.
class EngineSimClock : public RefCounted {
	GDCLASS(EngineSimClock, RefCounted)

	double _physics_dt = 1.0 / 1200.0;
	double _max_frame_time = 0.1;
	double _accumulator = 0.0;
	int _last_steps = 0;

protected:
	static void _bind_methods();

public:
	void configure(double physics_dt, double max_frame_time);
	int consume(double delta);
	void reset();
	int last_steps() const { return _last_steps; }
	double accumulator() const { return _accumulator; }
	double physics_dt() const { return _physics_dt; }
};


#endif