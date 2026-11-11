#ifndef ECU_MODEL_H
#define ECU_MODEL_H

#include <array>
#include <string>
#include <vector>

// Native copy of scripts/ecu/ecu.gd (the idle PI loops, overrun fuel cut, launch control, quickshifter cut and blip,
// power mode and speed limiter). Plain C++, no Godot types; EcuNative wraps it. Same constants and state as ecu.gd.
namespace engine_physics {

// The EngineSpec fields ecu.gd reads.
struct EcuSpec {
	bool quickshifter = false;
	double quickshifter_cut_time = 0.05;
	std::vector<std::vector<std::array<double, 2>>> quickshifter_cut_profile; // per gear: [rpm, cut_ms] points
	double quickshifter_blip_time = 0.08;
	double quickshifter_blip_throttle = 0.3;
	bool quickshifter_flat_shift = false;
	double flat_shift_throttle = 0.15;
	bool launch_control = false;
	double launch_rpm = 8000.0;
	double launch_throttle = 0.95;
	double launch_speed_kmh = 30.0;
	double redline_rpm = 10600.0;
	bool speed_limit_enabled = false;
	double speed_limit_kmh = 0.0;
	bool decel_cut = true; // ECU cuts fuel and spark on overrun (closed throttle, high rpm); off keeps burning
};

class EcuModel {
public:
	static constexpr double KP = 0.02;
	static constexpr double KI = 0.02;
	static constexpr double TRIM_MIN = -16.0;
	static constexpr double TRIM_MAX = 15.0;
	static constexpr double IDLE_THROTTLE = 0.02;
	static constexpr double ACTIVE_RPM = 300.0;
	static constexpr double RELEASE_RATE = 20.0;
	static constexpr double KP_AIR = 0.8; // log units of air per unit of relative speed error, as ecu.gd
	static constexpr double KI_AIR = 1.2; // log units of air per unit of relative error per second
	static constexpr double AIR_RELEASE_RATE = 2.0;
	static constexpr double START_BOOST_RPM = 600.0; // below this crank speed the start air opens
	static constexpr double START_BOOST_LOG = 1.5;
	static constexpr double AIR_BAND = 0.4; // relative error band the idle loop integrates inside
	static constexpr double AIR_LIMIT = 5.0;
	static constexpr double OVERRUN_CUT = 2.2;
	static constexpr double OVERRUN_RESUME = 1.25;
	static constexpr double CATCH_RPM_FRAC = 0.25; // below this fraction of the target the valve opens wide until the engine catches
	static constexpr double LAUNCH_RAMP_RATE = 500.0;
	static constexpr double LAUNCH_SLIP_RATE = 0.3;
	static constexpr double LAUNCH_HOLD_GAIN = 10.0; // estimate, as in ecu.gd

	double target_rpm = 1200.0;
	double trim = 0.0;
	double manual_air = -1.0;

	void set_power_mode(const std::string &mode);
	double get_power_mode_lambda_mult() const { return power_mode_lambda_mult_; }
	double get_power_mode_timing_offset() const { return power_mode_timing_offset_; }
	bool is_quickshifter_active() const { return qs_active_; }
	bool is_quickshifter_blip_active() const { return blip_active_; }
	bool is_launch_active() const { return launch_active_; }
	double get_launch_target_rpm() const { return launch_target_rpm_; }
	bool overrun() const { return overrun_; }
	double air_factor() const;

	// spec may be null (ecu.gd's default). Returns the throttle override: -1 none, 0 cut, >0 blip.
	double update(double dt, double rpm, double throttle, bool running, const EcuSpec *spec, double speed_ms, double clutch_pull, int gear);
	bool trigger_quickshifter(const EcuSpec &spec);
	bool trigger_quickshifter_downshift(const EcuSpec &spec);

private:
	double get_qs_cut_time(const EcuSpec &spec, int gear) const;

	double integral_ = 0.0;
	double air_log_ = 0.0;
	double air_integral_ = 0.0;
	bool overrun_ = false;
	bool qs_active_ = false;
	double qs_timer_ = 0.0;
	bool speed_limited_ = false;
	bool blip_active_ = false;
	double blip_timer_ = 0.0;
	bool launch_active_ = false;
	double launch_target_rpm_ = 0.0;
	double launch_throttle_ = 1.0;
	double power_mode_lambda_mult_ = 1.0;
	double power_mode_timing_offset_ = 0.0;
	double current_rpm_ = 0.0;
	int current_gear_ = 0;
};

} // namespace engine_physics

#endif // ECU_MODEL_H
