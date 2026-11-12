class_name OrbitCamera
extends Node3D

# Mouse-controlled camera: left drag orbits, right drag pans, wheel zooms.
# Starts in side view so the chain and wheel show.

var target := Vector3(0.0, 1.0, -2.0) # the point the camera looks at
var yaw := -PI / 2.0
var pitch := 0.133
var distance := 11.0
var camera: Camera3D
var _orbiting := false
var _panning := false


func _ready() -> void:
	camera = Camera3D.new()
	add_child(camera)
	_update()


func _process(_delta: float) -> void:
	_update()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_orbiting = event.pressed
			MOUSE_BUTTON_RIGHT:
				_panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				distance = maxf(distance * 0.9, 2.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				distance = minf(distance / 0.9, 40.0)
	elif event is InputEventMouseMotion:
		if _orbiting:
			yaw -= event.relative.x * 0.01
			pitch = clampf(pitch + event.relative.y * 0.01, -1.4, 1.4)
		elif _panning:
			var cam_basis := camera.global_transform.basis
			target += (-event.relative.x * cam_basis.x + event.relative.y * cam_basis.y) * distance * 0.0015


func _update() -> void:
	var offset := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	camera.position = target + offset * distance
	camera.look_at(target)
