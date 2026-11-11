#include "ecu_model.h"

#include <algorithm>
#include <cmath>

namespace engine_physics {

static double move_toward_d(double from, double to, double delta) {
	if (std::fabs(to - from) <= delta) {
		return to;
	}
	return from + (to > from ? 1.0 : (to < from ? -1.0 : 0.0)) * delta;
}

static double clampd(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

void EcuModel::set_power_mode(const std::string &mode) {
	// POWER_MODE_LAMBDA: M/L run slightly leaner for economy. POWER_MODE_TIMING: M/L retard timing for softer delivery.
	power_mode_lambda_mult_ = 1.0;
	power_mode_timing_offset_ = 0.0;
	if (mode == "M") {
		power_mode_lambda_mult_ = 1.02;
		power_mode_timing_offset_ = -3.0;
	} else if (mode == "L") {
		power_mode_lambda_mult_ = 1.05;
		power_mode_timing_offset_ = -6.0;
	}
}

// Quickshifter cut time for the current rpm and gear (ms -> s)
double EcuModel::get_qs_cut_time(const EcuSpec &spec, int gear) const {
	const auto &prof = spec.quickshifter_cut_profile;
	if (prof.empty() || gear <= 0 || gear > (int)prof.size()) {
		return spec.quickshifter_cut_time;
	}
	const auto &profile = prof[gear - 1];
	if (profile.empty()) {
		return spec.quickshifter_cut_time;
	}
	for (size_t i = 0; i + 1 < profile.size(); i++) {
		if (current_rpm_ >= profile[i][0] && current_rpm_ <= profile[i + 1][0]) {
			double t = (current_rpm_ - profile[i][0]) / (profile[i + 1][0] - profile[i][0]);
			return (profile[i][1] + (profile[i + 1][1] - profile[i][1]) * t) / 1000.0;
		}
	}
	return profile.back()[1] / 1000.0;
}

double EcuModel::air_factor() const {
	return manual_air > 0.0 ? manual_air : std::exp(air_log_);
}

double EcuModel::update(double dt, double rpm, double throttle, bool running, const EcuSpec *spec, double speed_ms, double clutch_pull, int gear) {
	current_rpm_ = rpm;
	current_gear_ = gear;
	// Disabling an aid must cancel any in-flight intervention on this step.
	if (spec == nullptr || !spec->quickshifter || !running) {
		qs_active_ = false;
		qs_timer_ = 0.0;
		blip_active_ = false;
		blip_timer_ = 0.0;
	}
	if (spec == nullptr || !spec->launch_control || !running) {
		launch_active_ = false;
		launch_target_rpm_ = 0.0;
	}

	// Quickshifter upshift cut
	if (qs_active_) {
		qs_timer_ -= dt;
		if (qs_timer_ <= 0.0) {
			qs_active_ = false;
		}
		// the ignition and fuel are cut in the sim; the throttle closes, unless flat shift keeps it cracked
		return (spec != nullptr && spec->quickshifter_flat_shift) ? spec->flat_shift_throttle : 0.0;
	}

	// Quickshifter downshift blip
	if (blip_active_) {
		blip_timer_ -= dt;
		if (blip_timer_ <= 0.0) {
			blip_active_ = false;
		}
		return spec->quickshifter_blip_throttle;
	}

	// Speed limiter: closes the throttle at the limit and lets go 2 km/h under it, so the bike holds the limit without chattering
	if (spec != nullptr && spec->speed_limit_enabled && running) {
		double kmh = speed_ms * 3.6;
		if (kmh >= spec->speed_limit_kmh) {
			speed_limited_ = true;
		} else if (kmh < spec->speed_limit_kmh - 2.0) {
			speed_limited_ = false;
		}
		if (speed_limited_) {
			return 0.0;
		}
	} else {
		speed_limited_ = false;
	}

	// Launch control: check if conditions are met to arm/disarm
	if (spec != nullptr && spec->launch_control && running) {
		double speed_kmh = speed_ms * 3.6;
		bool launch_armed = throttle >= spec->launch_throttle && clutch_pull > 0.5 && speed_kmh < spec->launch_speed_kmh && rpm < spec->launch_rpm * 1.1;
		if (launch_armed && !launch_active_) {
			launch_active_ = true;
			launch_target_rpm_ = spec->launch_rpm;
			launch_throttle_ = 1.0;
		} else if (launch_active_ && (speed_kmh >= spec->launch_speed_kmh || throttle < spec->launch_throttle * 0.5)) {
			// letting the lever go is the launch itself: the clutch then slips at the target, so it does not end the launch
			launch_active_ = false;
		}
		if (launch_active_) {
			// Ramp up target RPM with speed
			launch_target_rpm_ += LAUNCH_RAMP_RATE * dt * clampd(speed_kmh / spec->launch_speed_kmh, 0.0, 1.0);
			launch_target_rpm_ = std::min(launch_target_rpm_, spec->redline_rpm * 0.95);
			// launch holds the target with the throttle: it opens while the engine is under the target and closes above it
			launch_throttle_ = clampd(1.0 - LAUNCH_HOLD_GAIN * (rpm - launch_target_rpm_) / std::max(launch_target_rpm_, 1.0), 0.0, 1.0);
			return launch_throttle_;
		}
	}

	// the ECU stays out of the way while the engine is starting and climbing, and only holds the idle once it is running
	if (!running || throttle > IDLE_THROTTLE || rpm < ACTIVE_RPM) {
		overrun_ = false;
		if (throttle > IDLE_THROTTLE) {
			integral_ = 0.0; // the idle trim only belongs at a closed throttle: with it left on, a big engine stalls as the throttle opens
		} else {
			integral_ = move_toward_d(integral_, 0.0, RELEASE_RATE * dt);
		}
		// A stalled engine or an open throttle releases the idle valve to neutral, because the engine is no longer being
		// idled. An engine that is still turning below the active rpm (cranking up to catch) keeps the air the idle loop
		// learned: releasing it there starves the last bit of a start and the engine dies instead of catching.
		if (!running || throttle > IDLE_THROTTLE) {
			air_integral_ = move_toward_d(air_integral_, 0.0, AIR_RELEASE_RATE * dt);
		}
		air_log_ = air_integral_;
		trim = integral_;
		return -1.0;
	}

	// A shut throttle still burns enough to hold a larger engine several thousand rpm up. Cut the fuel until it
	// is near idle. The rpm error while cutting is huge, so the valve and the spark stay at a normal idle
	// instead of slamming shut, and the engine can catch when the fuel returns.
	// decel_cut is a per-bike setting; a bike whose ECU does not cut on decel keeps injecting and firing on overrun.
	bool cut_on_overrun = spec == nullptr || spec->decel_cut;
	if (cut_on_overrun && rpm > target_rpm * OVERRUN_CUT) {
		overrun_ = true;
	} else if (rpm < target_rpm * OVERRUN_RESUME || !cut_on_overrun) {
		overrun_ = false;
	}
	if (overrun_) {
		// The fuel is cut, so the idle loops hold what they have learned. The proportional term would slam the valve shut
		// against the huge overrun error; keep the valve where the idle loop left it so the engine can catch when the fuel
		// returns instead of hunting between the cut and the catch.
		air_log_ = air_integral_;
		trim = integral_;
		return -1.0;
	}

	// Launch control overrides idle target when active
	double effective_target = target_rpm;
	if (launch_active_) {
		effective_target = launch_target_rpm_;
	}

	double error = effective_target - rpm;
	// the idle-air valve: below the target it opens, above it closes. The error is relative to the target, so the loop gains
	// the same response at a 700 rpm V6 idle and a 1500 rpm four.
	double error_frac = error / std::max(effective_target, 1.0);
	air_integral_ = clampd(air_integral_ + KI_AIR * error_frac * dt, -AIR_LIMIT, AIR_LIMIT);
	air_log_ = clampd(KP_AIR * error_frac + air_integral_, -AIR_LIMIT, AIR_LIMIT);
	// start boost: a just-fired engine is well below the idle speed, so the valve opens wide at once, as an ECU's start air does.
	// It is held to a crank speed the engine cannot sustain on its own: above that the idle loop must do the work, or the boost
	// and the idle loop fight and the speed hunts between them.
	if (rpm < START_BOOST_RPM) {
		air_log_ = std::max(air_log_, START_BOOST_LOG);
	}
	// catch: an engine that has fallen well under the target is about to stop firing altogether, and in that state the idle
	// loop is measuring a speed it can no longer control. Open the valve all the way until the charge lights again.
	if (rpm < effective_target * CATCH_RPM_FRAC) {
		air_log_ = AIR_LIMIT;
	}
	integral_ = clampd(integral_ + KI * error * dt, TRIM_MIN, TRIM_MAX); // clamped so it cannot wind up
	trim = clampd(KP * error + integral_, TRIM_MIN, TRIM_MAX);
	// Add power mode timing offset
	trim += power_mode_timing_offset_;
	return -1.0;
}

bool EcuModel::trigger_quickshifter(const EcuSpec &spec) {
	if (!spec.quickshifter) {
		return false;
	}
	qs_active_ = true;
	qs_timer_ = get_qs_cut_time(spec, current_gear_);
	return true;
}

bool EcuModel::trigger_quickshifter_downshift(const EcuSpec &spec) {
	if (!spec.quickshifter) {
		return false;
	}
	blip_active_ = true;
	blip_timer_ = spec.quickshifter_blip_time;
	return true;
}

} // namespace engine_physics
