extends Node3D

# The dyno cell's equipment: a roller under each wheel, a cooling fan in front of the bike, and a readout panel for the
# sensors. Physics (the drum's inertia and the eddy-current brake) lives in EngineSim.cell_mass_kg and cell_load_n;
# this script only draws the equipment and shows the readings.

const ROLLER_RADIUS := 0.25 # m, drum radius, estimate
const ROLLER_WIDTH := 0.5 # m
const FAN_OFFSET_Z := 1.6 # m in front of the front wheel
const FAN_SIZE := Vector3(0.9, 0.9, 0.12) # m

var _rollers: Array[Node3D] = []
var _fan: Node3D
var _fan_blades: Node3D
var _fan_on := true
var _readout: Label
var _ground_y := 0.0


# Builds the rollers under the two wheel axles and the fan in front of the front wheel.
func build(ground_y: float, rear_z: float, front_z: float, show_readout: bool = true) -> void:
	_ground_y = ground_y
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.55, 0.57, 0.6)
	steel.metallic = 0.6
	steel.roughness = 0.4
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.14)
	for z in [rear_z, front_z]:
		var drum := Node3D.new()
		drum.position = Vector3(0.0, ground_y - ROLLER_RADIUS, z)
		add_child(drum)
		var cylinder := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = ROLLER_RADIUS
		mesh.bottom_radius = ROLLER_RADIUS
		mesh.height = ROLLER_WIDTH
		cylinder.mesh = mesh
		cylinder.material_override = steel
		cylinder.rotation.z = PI / 2.0 # the drum's axis runs across the bike
		drum.add_child(cylinder)
		_rollers.append(drum)
	# Fan: a housing and a blade cross that spins with the fan switch
	_fan = Node3D.new()
	_fan.position = Vector3(0.0, ground_y + FAN_SIZE.y * 0.5, front_z + FAN_OFFSET_Z)
	add_child(_fan)
	var housing := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = FAN_SIZE
	housing.mesh = box
	housing.material_override = dark
	_fan.add_child(housing)
	_fan_blades = Node3D.new()
	_fan_blades.position = Vector3(0.0, 0.0, FAN_SIZE.z * 0.5 + 0.01)
	_fan.add_child(_fan_blades)
	for angle in [0.0, 90.0]:
		var blade := MeshInstance3D.new()
		var blade_mesh := BoxMesh.new()
		blade_mesh.size = Vector3(FAN_SIZE.x * 0.9, 0.08, 0.02)
		blade.mesh = blade_mesh
		blade.material_override = steel
		blade.rotation.z = deg_to_rad(angle)
		_fan_blades.add_child(blade)
	if show_readout:
		_build_readout()


# Shows the readout panel and the equipment; the cell's own panel (drum on/off, brake load) is built by main.gd
func _build_readout() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -320.0
	panel.offset_right = -16.0
	panel.offset_top = 300.0
	layer.add_child(panel)
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 16)
	panel.add_child(_readout)


func set_drum(on: bool) -> void:
	visible = on
	_fan_on = on


# Turns the rollers with the drum speed and spins the fan while the cell is on.
func update(delta: float, wheel_rpm: float) -> void:
	if not visible:
		return
	var spin := wheel_rpm * TAU / 60.0 * delta
	for drum in _rollers:
		drum.rotate_object_local(Vector3.RIGHT, spin)
	if _fan_on:
		_fan_blades.rotate_object_local(Vector3.FORWARD, 12.0 * delta)


# Sensor readings: the same quantities the engine stats panel uses, shown together
func show_readings(sim: EngineSim, _spec: EngineSpec, load_percent: float) -> void:
	if _readout == null or not visible:
		return
	var stopped := sim.rpm < 1.0
	var torque := 0.0 if stopped else sim.torque
	var power_hp := 0.0 if stopped else Units.w_to_hp(Units.power_w(sim.torque, sim.rpm))
	_readout.text = "DYNO CELL   load %d%%\nSpeed  %.0f km/h\nRPM    %.0f\nTorque %.1f N·m\nPower  %.1f hp\nAFR    %.1f (λ %.2f)\nEGT    %.0f °C\nFuel   %.2f g/s\nIntake %.2f psi\nCoolant %.0f °C   Oil %.0f °C" % [
		load_percent, sim.speed * 3.6, sim.rpm, torque, power_hp,
		14.7 * sim.o2_lambda(), sim.o2_lambda(), sim.exhaust_temp_c(), sim.fuel_flow,
		Units.pa_to_psi(sim.intake.pressure), sim.coolant_c, sim.oil_c]
