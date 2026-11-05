class_name FiringOrders
extends RefCounted

# Firing order (1-based cylinder numbers). Other counts fall back to 1..n.
const ORDERS := {
	3: [1, 2, 3],
	4: [1, 3, 4, 2],
	6: [1, 5, 3, 6, 2, 4],
	8: [1, 8, 4, 3, 6, 5, 7, 2],
}


static func order_for(cylinders: int) -> Array:
	if ORDERS.has(cylinders):
		return ORDERS[cylinders]
	var seq := []
	for i in range(1, cylinders + 1):
		seq.append(i)
	return seq


# True when the crank passed angle `at` while moving from prev to cur (unwrapped degrees).
static func fired_between(prev: float, cur: float, at: float) -> bool:
	return floor((cur - at) / 720.0) > floor((prev - at) / 720.0)


# Crank angle (deg, 0..720) at which each cylinder fires. Index = cylinder number - 1.
# A twin fires its second cylinder at its crank-pin angle: 360 is even firing, 270 and 180 are uneven.
static func fire_angles(cylinders: int, twin_pin_deg: float = 360.0, crossplane: bool = false, split_v4: bool = false) -> Array[float]:
	if cylinders == 2:
		var twin: Array[float] = [0.0, twin_pin_deg]
		return twin
	# 90 degree V4 with a 70 degree split crank pin (Ducati Panigale V4). Ignition wiring from engine-sim's panigale_v4.mr:
	# bank A front pin 0, bank B front pin -90, bank A rear pin -240, bank B rear pin -330, on a 720 degree cycle.
	# Cylinders 1 to 4 fire at 0, 630, 480, 390: uneven intervals of 390, 90, 150 and 90 degrees.
	if cylinders == 4 and split_v4:
		var split: Array[float] = [0.0, 630.0, 480.0, 390.0]
		return split
	# crossplane four: pins 90° apart, so firing comes 270/180/90/180 apart. Cylinders 1 to 4 fire at 0, 450, 270, 540.
	if cylinders == 4 and crossplane:
		var cross: Array[float] = [0.0, 450.0, 270.0, 540.0]
		return cross
	var order := order_for(cylinders)
	var interval := 720.0 / cylinders
	var angles: Array[float] = []
	angles.resize(cylinders)
	for i in order.size():
		angles[order[i] - 1] = i * interval
	return angles
