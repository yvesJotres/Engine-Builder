extends SceneTree

const SHIFT_SENSOR := preload("res://scripts/ignition/shift_sensor.gd")

func _init():
	var sensor = SHIFT_SENSOR.new()
	sensor.upshift_threshold = 0.7
	sensor.downshift_threshold = 0.7
	sensor.debounce_ms = 0  # disable debounce for testing
	
	# No shift at low force
	assert(sensor.update(0.5, 0.016) == 0)
	
	# Upshift detected
	assert(sensor.update(0.8, 0.016) == 1)
	
	# No double-detect without reset
	assert(sensor.update(0.8, 0.016) == 0)
	
	# Reset after force drops
	sensor.update(0.0, 0.016)
	assert(sensor.update(0.8, 0.016) == 1)
	
	# Downshift
	sensor.update(0.0, 0.016)
	assert(sensor.update(-0.8, 0.016) == -1)
	
	print("ShiftSensor tests passed")
	quit()