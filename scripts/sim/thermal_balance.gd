extends RefCounted

# Two uniform thermal masses; conductances and capacities must describe the engine being modelled.
var wall_k: float
var coolant_k: float
var wall_capacity_j_k: float
var coolant_capacity_j_k: float
var rejected_j := 0.0


func _init(wall_capacity: float, coolant_capacity: float, wall_temp: float, coolant_temp: float) -> void:
	assert(wall_capacity > 0.0 and coolant_capacity > 0.0)
	wall_capacity_j_k = wall_capacity
	coolant_capacity_j_k = coolant_capacity
	wall_k = wall_temp
	coolant_k = coolant_temp


# Gas-to-wall energy is signed and averaged over the step. Conductances are W/K, temperatures K, time seconds.
func advance(dt: float, gas_heat_j: float, wall_coolant_w_k: float, radiator_w_k: float, ambient_k: float) -> void:
	assert(dt >= 0.0 and wall_coolant_w_k >= 0.0 and radiator_w_k >= 0.0)
	if dt == 0.0:
		wall_k += gas_heat_j / wall_capacity_j_k
		return
	var wall := wall_k - ambient_k
	var coolant := coolant_k - ambient_k
	var initial_energy := wall * wall_capacity_j_k + coolant * coolant_capacity_j_k
	var a := wall_coolant_w_k / wall_capacity_j_k
	var b := wall_coolant_w_k / coolant_capacity_j_k
	var c := radiator_w_k / coolant_capacity_j_k
	var half := (a + b + c) * 0.5
	if half == 0.0:
		wall_k += gas_heat_j / wall_capacity_j_k
		return
	var root := sqrt(maxf(half * half - a * c, 0.0))
	var low := -half - root
	var high := -a * c / (half + root)
	var gap := high - low
	var slow_wall := (-(a + low) * wall + a * coolant) / gap
	var slow_coolant := (b * wall - (b + c + low) * coolant) / gap
	var source := gas_heat_j / (dt * wall_capacity_j_k)
	var source_slow_wall := -(a + low) * source / gap
	var source_slow_coolant := b * source / gap
	var exp_low := exp(low * dt)
	var exp_delta := exp(high * dt) - exp_low
	var integral_low := _exp_integral(low, dt)
	var integral_delta := _exp_integral(high, dt) - integral_low
	wall_k = ambient_k + exp_low * wall + exp_delta * slow_wall + integral_low * source + integral_delta * source_slow_wall
	coolant_k = ambient_k + exp_low * coolant + exp_delta * slow_coolant + integral_delta * source_slow_coolant
	rejected_j += initial_energy + gas_heat_j - (wall_k - ambient_k) * wall_capacity_j_k - (coolant_k - ambient_k) * coolant_capacity_j_k


static func _exp_integral(rate: float, dt: float) -> float:
	var x := rate * dt
	if absf(x) < 0.0001:
		return dt * (1.0 + x * 0.5 + x * x / 6.0 + x * x * x / 24.0)
	return (exp(x) - 1.0) / rate
