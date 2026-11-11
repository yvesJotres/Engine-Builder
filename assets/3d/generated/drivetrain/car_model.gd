class_name CarModel
extends Node3D

var rear_axle := Vector3.ZERO
var front_axle := Vector3.ZERO
var _wheels: Array[Node3D] = []
var _wheel_radii: Array[float] = []
var _rear_radius := 0.0

func build(spec: EngineSpec, ground_y: float) -> void:
	for child in get_children():
		child.queue_free()
	_wheels.clear()
	_wheel_radii.clear()
	var rear_radius := spec.wheel_radius_m * Units.M_TO_SCENE
	_rear_radius = rear_radius
	var front_radius := spec.front_wheel_radius_m * Units.M_TO_SCENE
	rear_axle = Vector3(0.0, ground_y + rear_radius, -3.0)
	front_axle = Vector3(0.0, ground_y + front_radius, rear_axle.z + spec.wheelbase_mm * Units.MM_TO_SCENE)
	var tire_material := _material(Color(0.055, 0.06, 0.065), 0.85, 0.0)
	var rim_material := _material(Color(0.48, 0.5, 0.53), 0.32, 0.65)
	for side in [-1, 1]:
		_add_wheel(rear_axle + Vector3(side * spec.rear_track_mm * Units.MM_TO_SCENE * 0.5, 0.0, 0.0), rear_radius, 21.0 * 25.4 * 0.5 * Units.MM_TO_SCENE, spec.rear_tire_width_mm * Units.MM_TO_SCENE, tire_material, rim_material)
		_add_wheel(front_axle + Vector3(side * spec.front_track_mm * Units.MM_TO_SCENE * 0.5, 0.0, 0.0), front_radius, 20.0 * 25.4 * 0.5 * Units.MM_TO_SCENE, spec.front_tire_width_mm * Units.MM_TO_SCENE, tire_material, rim_material)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _body_mesh(spec, ground_y)
	var paint := _material(Color(0.8, 0.82, 0.85, 0.7), 0.35, 0.15)
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	body.material_override = paint
	add_child(body)
	var canopy := MeshInstance3D.new()
	canopy.name = "Canopy"
	canopy.mesh = _canopy_mesh(spec, ground_y)
	var glass := _material(Color(0.09, 0.14, 0.19, 0.85), 0.22, 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	canopy.material_override = glass
	add_child(canopy)
	var light_material := _material(Color(0.9, 0.95, 1.0), 0.2, 0.0)
	light_material.emission_enabled = true
	light_material.emission = Color(0.55, 0.7, 0.8)
	for side in [-1, 1]:
		var light := MeshInstance3D.new()
		var light_mesh := BoxMesh.new()
		light_mesh.size = Vector3(2.4, 0.16, 0.15)
		light.mesh = light_mesh
		light.material_override = light_material
		light.position = Vector3(side * 4.8, ground_y + 4.2, (rear_axle.z + front_axle.z) * 0.5 + spec.vehicle_length_mm * Units.MM_TO_SCENE * 0.42)
		add_child(light)


func update(wheel_rpm: float, delta: float) -> void:
	for index in _wheels.size():
		var turn := deg_to_rad(wheel_rpm * 6.0 * delta * _rear_radius / _wheel_radii[index])
		_wheels[index].rotation.x = fposmod(_wheels[index].rotation.x + turn, TAU)


func _add_wheel(at: Vector3, radius: float, rim_radius: float, width: float, tire_material: Material, rim_material: Material) -> void:
	var wheel := Node3D.new()
	wheel.position = at
	add_child(wheel)
	_wheels.append(wheel)
	_wheel_radii.append(radius)
	var tire := MeshInstance3D.new()
	var tire_mesh := TorusMesh.new()
	tire_mesh.outer_radius = radius
	tire_mesh.inner_radius = rim_radius
	tire.mesh = tire_mesh
	tire.material_override = tire_material
	tire.rotation.z = PI / 2.0
	tire.scale.y = width / (radius - rim_radius)
	wheel.add_child(tire)
	preload("res://assets/3d/generated/drivetrain/tire_tread.gd").add_to(wheel, radius, rim_radius, width, 64)
	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = rim_radius - 0.1
	rim_mesh.outer_radius = rim_radius + 0.1
	rim.mesh = rim_mesh
	rim.material_override = rim_material
	rim.rotation.z = PI / 2.0
	wheel.add_child(rim)
	for spoke_index in 10:
		var spoke := MeshInstance3D.new()
		var spoke_mesh := BoxMesh.new()
		spoke_mesh.size = Vector3(0.2, rim_radius, 0.18)
		spoke.mesh = spoke_mesh
		spoke.material_override = rim_material
		var angle := TAU * spoke_index / 10.0
		spoke.rotation.x = angle
		spoke.position = Vector3(0.0, cos(angle), sin(angle)) * rim_radius * 0.5
		wheel.add_child(spoke)


func _body_mesh(spec: EngineSpec, ground_y: float) -> ArrayMesh:
	var length := spec.vehicle_length_mm * Units.MM_TO_SCENE
	var half_width := spec.vehicle_width_mm * Units.MM_TO_SCENE * 0.5
	var centre := (rear_axle.z + front_axle.z) * 0.5
	var sections := [Vector2(-0.5, 0.18), Vector2(-0.42, 0.8), Vector2(-0.25, 0.98), Vector2(0.0, 1.0), Vector2(0.25, 0.98), Vector2(0.43, 0.8), Vector2(0.5, 0.15)]
	var rings: Array[PackedVector3Array] = []
	for section in sections:
		var ring := PackedVector3Array()
		for vertex in 12:
			var angle := TAU * vertex / 12.0
			ring.append(Vector3(cos(angle) * half_width * section.y, ground_y + 3.8 + sin(angle) * 1.9 * section.y, centre + section.x * length))
		rings.append(ring)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for section_index in rings.size() - 1:
		for vertex in 12:
			var next := (vertex + 1) % 12
			for point in [rings[section_index][vertex], rings[section_index][next], rings[section_index + 1][vertex], rings[section_index][next], rings[section_index + 1][next], rings[section_index + 1][vertex]]:
				surface.add_vertex(point)
	surface.generate_normals()
	return surface.commit()


func _canopy_mesh(spec: EngineSpec, ground_y: float) -> ArrayMesh:
	var half_width := spec.vehicle_width_mm * Units.MM_TO_SCENE * 0.31
	var centre := (rear_axle.z + front_axle.z) * 0.5 + 2.0
	var half_length := spec.vehicle_length_mm * Units.MM_TO_SCENE * 0.16
	var bottom := ground_y + 5.2
	var top := ground_y + spec.vehicle_height_mm * Units.MM_TO_SCENE
	var rear_left := Vector3(-half_width, bottom, centre - half_length)
	var rear_right := Vector3(half_width, bottom, centre - half_length)
	var front_left := Vector3(-half_width, bottom, centre + half_length)
	var front_right := Vector3(half_width, bottom, centre + half_length)
	var roof_rear_left := Vector3(-half_width * 0.75, top, centre - half_length * 0.42)
	var roof_rear_right := Vector3(half_width * 0.75, top, centre - half_length * 0.42)
	var roof_front_left := Vector3(-half_width * 0.75, top, centre + half_length * 0.35)
	var roof_front_right := Vector3(half_width * 0.75, top, centre + half_length * 0.35)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [rear_left, rear_right, roof_rear_left, rear_right, roof_rear_right, roof_rear_left,
		front_right, front_left, roof_front_right, front_left, roof_front_left, roof_front_right,
		rear_left, roof_rear_left, front_left, front_left, roof_rear_left, roof_front_left,
		rear_right, front_right, roof_rear_right, front_right, roof_front_right, roof_rear_right,
		roof_rear_left, roof_rear_right, roof_front_left, roof_rear_right, roof_front_right, roof_front_left]:
		surface.add_vertex(point)
	surface.generate_normals()
	return surface.commit()


static func _material(colour: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	material.metallic = metallic
	return material
