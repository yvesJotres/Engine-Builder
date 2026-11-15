class_name SplMeter
extends RefCounted

# Sound pressure level where a real exhaust noise test puts the microphone: 0.5 m from the outlet, 45 degrees off the
# direction of the flow, at the height of the outlet, outboard of the bike so the bodywork does not shadow it, and never
# lower than 0.2 m above the ground. That is the geometry of the JIS D 1030 / SAE J1287 proximity test, i.e. the same
# point the ZX-25R's 90 dB(A) label is measured at, so the number on the dash can be held against a published one.
#
# The samples EngineSound renders ARE the pressure at its 1/r reference distance (18 scene units), so what the
# microphone hears is those samples through the free field law over the last 1.3 m:
#     SPL = 20*log10(rms) + REFERENCE_DB + free_field_db(MIC_DISTANCE)
# It deliberately does NOT use SpatialFalloff.gain_db: that carries max_db (the near-field cap that stops a zoomed-in
# camera being blasted) and the max_distance cull, and both are playback guards rather than properties of the source.
# With them, moving the microphone from 1 m to 0.5 m would change the reading by 0 dB; a real meter reads 6.02 dB more
# at half the distance, and a test position that does not do that is a lie.
#
# CALIBRATION, STATED SO IT CAN BE ARGUED WITH: 0 dBFS on the engine stream is taken as 94 dB SPL at the reference
# distance. 94 dB is the reference pressure 1 Pa against the 20 uPa hearing threshold, the usual way of tying a
# full-scale digital signal to a pressure. No microphone was involved, so this is a calibrated meter, not a measured
# one. It is also FLAT - no A-weighting - so it reads dB SPL, not dB(A); on a four-cylinder the flat reading sits a
# couple of dB below a dB(A) one because most of the energy is low, which is the main reason to treat a comparison with
# a published dB(A) figure as indicative.
const REFERENCE_DB := 94.0 # 0 dBFS = 94 dB SPL at EngineSound.UNIT_SIZE
const MIC_DISTANCE := 5.0 # 0.5 m from the outlet; 1 scene unit = 10 cm
const MIC_ANGLE_DEG := 45.0 # off the exhaust flow, the angle the test stands the microphone at
const MIC_MIN_HEIGHT := 2.0 # scene units above the ground: the standard's floor for the microphone
const FLOOR_DB := 30.0 # quieter than a quiet room: the meter shows nothing rather than a number nobody can use


# Level in dB SPL for the RMS of the engine's recent output (full scale = 1.0).
static func level_db(rms: float) -> float:
	var falloff := SpatialFalloff.free_field_db(MIC_DISTANCE, EngineSound.UNIT_SIZE)
	return linear_to_db(maxf(rms, 1e-9)) + REFERENCE_DB + falloff


# What the dashboard prints: the reading, or a dash when there is nothing to read.
static func text(db: float) -> String:
	return "%d dB" % roundi(db) if db >= FLOOR_DB else "-- dB"
