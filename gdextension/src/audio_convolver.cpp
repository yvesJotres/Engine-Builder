#include "audio_convolver.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>

namespace godot {

void AudioConvolver::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_ir", "ir"), &AudioConvolver::set_ir);
	ClassDB::bind_method(D_METHOD("get_ir"), &AudioConvolver::get_ir);
	ClassDB::bind_method(D_METHOD("get_taps"), &AudioConvolver::get_taps);
	ClassDB::bind_method(D_METHOD("get_ir_sum"), &AudioConvolver::get_ir_sum);
	ClassDB::bind_method(D_METHOD("reset"), &AudioConvolver::reset);
	ClassDB::bind_method(D_METHOD("process", "body"), &AudioConvolver::process);
}

void AudioConvolver::set_ir(const PackedFloat32Array &ir) {
	taps_ = ir.size();
	ir_.resize(static_cast<size_t>(taps_));
	sum_ = 0.0;
	for (int i = 0; i < taps_; ++i) {
		// reversed: ir_[0] is the oldest tap, so the history window reads forwards
		ir_[static_cast<size_t>(i)] = ir[taps_ - 1 - i];
		sum_ += static_cast<double>(ir[i]);
	}
	history_.assign(static_cast<size_t>(taps_) * 2, 0.0f);
	pos_ = 0;
}

PackedFloat32Array AudioConvolver::get_ir() const {
	PackedFloat32Array out;
	out.resize(taps_);
	for (int i = 0; i < taps_; ++i) {
		out[i] = ir_[static_cast<size_t>(taps_ - 1 - i)];
	}
	return out;
}

int AudioConvolver::get_taps() const {
	return taps_;
}

double AudioConvolver::get_ir_sum() const {
	return sum_;
}

void AudioConvolver::reset() {
	std::fill(history_.begin(), history_.end(), 0.0f);
	pos_ = 0;
}

PackedFloat32Array AudioConvolver::process(const PackedFloat32Array &body) {
	PackedFloat32Array wet;
	const int n = body.size();
	wet.resize(n);
	if (taps_ <= 0) {
		// no impulse response loaded: pass the body through unchanged rather than going silent
		for (int i = 0; i < n; ++i) {
			wet[i] = body[i];
		}
		return wet;
	}
	const int taps = taps_;
	const float *ir = ir_.data();
	float *hist = history_.data();
	int pos = pos_;
	for (int i = 0; i < n; ++i) {
		const float x = body[i];
		hist[pos] = x;
		hist[pos + taps] = x;
		const float *window = hist + pos + 1;
		// four partial sums: one long dependency chain would stall the pipeline, and this way
		// the compiler can vectorise the inner loop too
		float a0 = 0.0f;
		float a1 = 0.0f;
		float a2 = 0.0f;
		float a3 = 0.0f;
		int k = 0;
		for (; k + 4 <= taps; k += 4) {
			a0 += ir[k] * window[k];
			a1 += ir[k + 1] * window[k + 1];
			a2 += ir[k + 2] * window[k + 2];
			a3 += ir[k + 3] * window[k + 3];
		}
		for (; k < taps; ++k) {
			a0 += ir[k] * window[k];
		}
		wet[i] = (a0 + a1) + (a2 + a3);
		if (++pos >= taps) {
			pos = 0;
		}
	}
	pos_ = pos;
	return wet;
}

} // namespace godot
