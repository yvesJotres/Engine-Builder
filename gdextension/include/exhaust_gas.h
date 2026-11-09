#ifndef EXHAUST_GAS_H
#define EXHAUST_GAS_H

#include "engine_sim.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <vector>
#include <cmath>
#include <algorithm>

namespace engine_sim {

using namespace godot;

class ExhaustLayout;

class ExhaustGas : public RefCounted {
    GDCLASS(ExhaustGas, RefCounted);

public:
    static constexpr float GAMMA = 1.3f;
    static constexpr float R = 287.0f;
    static constexpr float P0 = 101325.0f;
    static constexpr float T0 = 300.0f;
    static constexpr float CELL_M = 0.12f;
    static constexpr float AUDIO_RATE = 44100.0f;
    static constexpr float CFL = 0.85f;

    // Public properties
    bool record_audio = true;
    bool exhaust_solver = false;

    // Main interface
    void build(const ExhaustLayout *layout);
    float port_pressure(int cylinder_index) const;
    float port_temperature(int cylinder_index) const;
    void apply_valve(int cylinder_index, float mdot, float power);
    void add_energy(int cylinder_index, float joules);
    float station_pressure(int pipe_index) const;
    float tail_volume_flow() const;
    PackedFloat32Array take_flow();
    void advance(float dt);

protected:
    static void _bind_methods();

private:
    // Core state
    int _n = 0;
    int _npipes = 0;
    PackedFloat32Array _rho;
    PackedFloat32Array _ru;
    PackedFloat32Array _re;
    PackedFloat32Array _area;
    PackedFloat32Array _dx;
    PackedFloat32Array _loss;
    PackedInt32Array _pipe0;
    PackedInt32Array _pipe_n;
    PackedInt32Array _parent;
    PackedInt32Array _cyl_pipe;
    std::vector<PackedInt32Array> _feeders;
    PackedFloat32Array _mdot;
    PackedFloat32Array _power;
    PackedFloat32Array _flow;

    // Scratch arrays for stepping
    PackedFloat32Array _d_rho;
    PackedFloat32Array _d_ru;
    PackedFloat32Array _d_re;
    PackedInt32Array _fl;
    PackedInt32Array _fr;
    PackedFloat32Array _sl;
    PackedFloat32Array _sr;
    PackedByteArray _fk;
    int _nf = 0;
    float _cfl_dt = 1.0e-4f;
    float _min_dx = CELL_M;
    float _audio_left = 0.0f;

    // Helpers
    int _port_cell(int cylinder_index) const;
    float _area_at(const ExhaustLayout::Pipe *pipe, float dist_m) const;
    void _build_faces();
    float _cfl_dt_calc() const;
    float _pressure(int cell) const;
    float _velocity(int cell) const;
    float _sound(int cell) const;
    float _sound_of(float rho, float p) const;
    static float _ambient_sound_speed();
    void _clamp_cell(int cell);
    void _step(float h);
    Vector3 _rusanov(float r_l, float u_l, float p_l, float r_r, float u_r, float p_r) const;
    Vector3 _flux(float rho, float u, float p) const;
    Vector3 _face(int left, int right) const;
    Vector3 _wall_face(int cell) const;
    Vector3 _open_face(int cell) const;
    void _friction(int cell, float dt);
    void _clamp_cell(int cell);
};

} // namespace engine_sim

#endif // EXHAUST_GAS_H