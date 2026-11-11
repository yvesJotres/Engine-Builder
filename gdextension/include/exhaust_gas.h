#ifndef EXHAUST_GAS_H
#define EXHAUST_GAS_H

// C++ port of scripts/exhaust/exhaust_gas.gd (1D unsteady exhaust gas, HLLE Euler solver).
// Plain C++ with no godot-cpp dependency; the lead registers the class and provides the layout.

#include <cstdint>
#include <vector>

namespace engine_sim {

// Mirrors ExhaustLayout's Vector3 points. Scene units: layout.scene_per_m scene units per metre.
struct ExhaustPoint {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
};

// Mirrors ExhaustLayout.Pipe. Requires radii.size() == pts.size().
struct ExhaustPipe {
    std::vector<ExhaustPoint> pts;
    std::vector<float> radii;        // scene units, one per point
    int cyl = -1;                    // primary pipes only: the cylinder feeding it
    std::vector<int> feeders;        // pipes that join at this pipe's upstream end
    float loss = 0.25f;              // 1/m amplitude loss along the pipe

    double length_m(double scene_per_m) const;
    double area_m2(double scene_per_m) const;
};

// Mirrors ExhaustLayout: pipes listed upstream first, the last one is the tailpipe.
struct ExhaustLayoutData {
    double scene_per_m = 10.0;       // ExhaustLayout.M (Units.M_TO_SCENE)
    std::vector<ExhaustPipe> pipes;
};

class ExhaustGas {
public:
    static constexpr double GAMMA = 1.3;
    static constexpr double R = 287.0;
    static constexpr double P0 = 101325.0;
    static constexpr double T0 = 300.0;
    static constexpr double CELL_M = 0.24;
    static constexpr double AUDIO_RATE = 44100.0;
    static constexpr double CFL = 0.85;

    // Tail samples for the sound. The gas step always runs; the valves breathe that pressure.
    bool record_audio = true;

    void build(const ExhaustLayoutData &layout);
    double port_pressure(int cylinder_index) const;
    double port_temperature(int cylinder_index) const;
    // mdot > 0 is gas leaving the cylinder into the pipe. power is the enthalpy flux, watts, same sign.
    void apply_valve(int cylinder_index, double mdot, double power);
    void add_energy(int cylinder_index, double joules);
    double station_pressure(int pipe_index) const;
    double tail_volume_flow() const;
    std::vector<float> take_flow();
    void advance(double dt);

    static double ambient_sound_speed();

private:
    int _n = 0;
    int _npipes = 0;
    double _scene_per_m = 10.0;
    std::vector<float> _rho, _ru, _re;
    std::vector<float> _area, _dx, _loss;
    std::vector<int> _pipe0, _pipe_n, _parent, _cyl_pipe;
    std::vector<std::vector<int>> _feeders;
    std::vector<float> _mdot, _power;
    std::vector<float> _flow;

    std::vector<float> _d_rho, _d_ru, _d_re;
    std::vector<int> _fl, _fr;
    std::vector<float> _sl, _sr;
    std::vector<std::uint8_t> _fk;
    int _nf = 0;
    double _cfl_dt = 1.0e-4;
    double _min_dx = CELL_M;
    double _audio_left = 0.0;   // time from the end of the last step to the next sample
    double _q_prev = 0.0;       // tail volume flow at the end of the last step

    int _port_cell(int cylinder_index) const;
    double _area_at(const ExhaustPipe &pipe, double dist_m) const;
    void _build_faces();
    void _step(double dt);
    void _clamp_cell(int cell);
    double _pressure(int cell) const;
    double _velocity(int cell) const;
};

} // namespace engine_sim

#endif // EXHAUST_GAS_H
