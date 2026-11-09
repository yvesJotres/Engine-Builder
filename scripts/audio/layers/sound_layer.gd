class_name SoundLayer
extends RefCounted

# One procedural sound layer: valve tick, bearing rumble, turbo whistle and so on. A layer renders mono samples for a block, and
# the engine sound adds them to the mix before the leveler, the way the compressor whine is added.
#
# The rules every layer follows:
#  - cheap: one call per block, no allocation per sample, no calls into other nodes;
#  - continuous: oscillator phases and filter states carry over between blocks, so block edges do not click;
#  - repeatable: random numbers come from a RandomNumberGenerator with a fixed seed, so a render is the same every time;
#  - quiet by contract: the nominal peak is 0.2 at the loudest the layer ever gets. The engine sound applies the gain;
#  - silent when it should be: zeros when the engine is not running or the rpm is under 1.

const RATE := 44100.0

# Called once when the engine is set up. Read the spec here, not on every block.
func configure(_spec: EngineSpec) -> void:
	pass


# Clears every state, for an engine restart.
func reset() -> void:
	pass


# Renders frames mono samples.
func render(frames: int, _c: SoundContext) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	return out
