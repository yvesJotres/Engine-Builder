class_name SpatialFalloff
extends RefCounted

# The distance law every positional sound in the game follows. The players get their gain from Godot; this class is
# the same law written down, so the tuning can be checked numerically instead of by ear (tests/unit/controls/
# spatial_audio_test.gd measures a real AudioStreamPlayer3D against it).
#
# WHICH MODEL, AND WHY IT IS NOT THE "INVERSE SQUARE" ONE
#   A point source radiating into a free field spreads its power over a sphere of area 4*pi*r^2, so the INTENSITY
#   falls as 1/r^2. Intensity is proportional to the square of the sound PRESSURE, so the pressure - which is what the
#   mixer carries as gain - falls as 1/r. In decibels that is 20*log10(r), i.e. 6.02 dB per doubling of distance.
#   Godot's ATTENUATION_INVERSE_SQUARE_DISTANCE divides the gain by r^2 as well, i.e. 12.04 dB per doubling, which is
#   the intensity law applied to an amplitude: it double-counts the square that the pressure/intensity relation already
#   contains and would make the exhaust drop off twice as fast as a real one. Both players here therefore use
#   ATTENUATION_INVERSE_DISTANCE, which is exactly 1/r.
#
# THE LAW GODOT ACTUALLY APPLIES (scene/3d/audio_stream_player_3d.cpp in 4.7.2)
#   attenuation_db = min(max_db, -20*log10(distance / unit_size))
#   gain           = db_to_linear(attenuation_db) * max(0, 1 - distance / max_distance)      # silence beyond it
#   unit_size is the reference distance where the 1/r term reads 0 dB, so it is the distance the sound is calibrated
#   at. max_db is a ceiling on the near field: inside the distance where 1/r would exceed it the level is flat, which
#   is both the right thing to do for a source that is not a point in the first place (1/r runs to infinity at r = 0)
#   and what keeps a zoomed-in camera from being blasted. max_distance is a linear fade to silence: no acoustic law
#   does that, it is the mixer's cull. It is kept 100x the reference distance (CULL_FACTOR), which puts the cull 40 dB
#   below the reference, so the fade costs well under half a decibel anywhere the sound is still audible.
#
# MEASURED, NOT ASSUMED: a mono 3D source is mixed through an equal-power pan law, 1/sqrt(2) per channel (measured at
# -3.01 dB against a non-positional AudioStreamPlayer carrying the same mono stream). That is a pan gain, not part of
# the distance law, so it is not in these functions: a caller comparing a 3D level against a 2D one has to allow for
# it (see PAN_LAW_DB).

const MIN_DISTANCE := 1e-4 # distance never divides by zero
const CULL_FACTOR := 100.0 # max_distance / reference distance: the cull sits -40 dB below the reference
const PAN_LAW_DB := -3.0103 # mono 3D source against the same stream on a 2D player: 20*log10(1/sqrt(2))


# Free-field pressure law: 0 dB at unit_size, -6.02 dB per doubling.
static func free_field_db(distance: float, unit_size: float) -> float:
	return -20.0 * log(maxf(distance, MIN_DISTANCE) / maxf(unit_size, MIN_DISTANCE)) / log(10.0)


# 1/r with the near-field ceiling applied.
static func attenuation_db(distance: float, unit_size: float, max_db: float) -> float:
	return minf(free_field_db(distance, unit_size), max_db)


# The mixer's linear fade to the cull radius: 1.0 well inside it, 0.0 at and beyond it.
static func cull_gain(distance: float, max_distance: float) -> float:
	if max_distance <= 0.0:
		return 1.0
	return clampf(1.0 - distance / max_distance, 0.0, 1.0)


# Total gain in dB a listener at this distance hears, relative to the player's own volume_db.
static func gain_db(distance: float, unit_size: float, max_distance: float, max_db: float) -> float:
	var cull := cull_gain(distance, max_distance)
	if cull <= 0.0:
		return -INF
	return attenuation_db(distance, unit_size, max_db) + linear_to_db(cull)


# Where a cull radius should sit for a sound calibrated at unit_size that is to disappear at floor_db below it.
static func cull_distance(unit_size: float, floor_db: float) -> float:
	return unit_size * db_to_linear(-floor_db / 20.0)
