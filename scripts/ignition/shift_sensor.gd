class_name ShiftSensor
extends Resource

@export var upshift_threshold: float = 0.7
@export var downshift_threshold: float = 0.7
@export var debounce_ms: int = 50
@export var flat_shift_throttle: float = 0.15

var _last_force: float = 0.0
var _last_shift_time: float = 0.0
var _shift_state: int = 0

func reset() -> void:
	_last_force = 0.0
	_last_shift_time = 0.0
	_shift_state = 0

func update(force: float, dt: float) -> int:
	var now = Time.get_ticks_msec() / 1000.0
	
	if now - _last_shift_time < debounce_ms / 1000.0:
		return 0
	
	var result = 0
	if force >= upshift_threshold and _shift_state <= 0:
		_shift_state = 1
		_last_shift_time = now
		result = 1
	elif force <= -downshift_threshold and _shift_state >= 0:
		_shift_state = -1
		_last_shift_time = now
		result = -1
	elif abs(force) < 0.1:
		_shift_state = 0
	
	return result

func get_flat_shift_throttle() -> float:
	return flat_shift_throttle