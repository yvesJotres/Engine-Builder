#ifndef AUDIO_CONVOLVER_H
#define AUDIO_CONVOLVER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include <vector>

// Direct-form FIR convolution for the exhaust body, so a full-length impulse response
// can run at the output rate. GDScript cannot afford thousands of taps per sample; the
// previous 16 kHz / 128-tap body used only the first 8 ms of a 219 ms recording, and
// the muffled impulse response carries 99% of its energy in the first 25 ms.
//
// The history is kept twice over: sample i is written at pos and pos + taps, so the
// newest-to-oldest window is a contiguous run and the inner loop has no wrap branch.
// The impulse response is stored reversed, which lets that run be read forwards.
namespace godot {

class AudioConvolver : public RefCounted {
	GDCLASS(AudioConvolver, RefCounted)

	std::vector<float> ir_; // reversed impulse response, one entry per tap
	std::vector<float> history_; // 2 * taps, each sample written twice
	double sum_ = 0.0; // running sum of the impulse response, for the DC report
	int taps_ = 0;
	int pos_ = 0;

protected:
	static void _bind_methods();

public:
	void set_ir(const PackedFloat32Array &ir);
	PackedFloat32Array get_ir() const;
	int get_taps() const;
	double get_ir_sum() const;
	void reset();
	PackedFloat32Array process(const PackedFloat32Array &body);
};

} // namespace godot

#endif // AUDIO_CONVOLVER_H
