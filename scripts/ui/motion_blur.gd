class_name MotionBlur
extends Node

# Frame blend motion blur, for both the Compatibility renderer on phones and Forward+ on PC (Godot's built-in motion
# blur needs Forward+ and motion vectors, so it is not used here). The 3D scene is drawn once into a buffer; a 2D
# history buffer mixes each new frame with what it already holds, so moving parts leave a short trail. The HUD and
# controls are drawn over the result, so they stay sharp. Only the 3D view is drawn by the main viewport when this is on.

const BLEND := 0.35 # weight of the newest frame each time; lower = longer trails

var _main: Viewport
var _source: Camera3D # the main camera, copied each frame into the buffer's camera
var _scene: SubViewport # the 3D render
var _camera: Camera3D
var _history: SubViewport # 2D: keeps a fading mix of past frames
var _layer: CanvasLayer # draws the history behind the HUD
var _shown: TextureRect
var enabled := false


func setup(main: Viewport, source: Camera3D) -> void:
	_main = main
	_source = source
	_scene = SubViewport.new()
	_scene.world_3d = main.world_3d # the same scene, drawn from a copy of the main camera
	add_child(_scene)
	_camera = Camera3D.new()
	_scene.add_child(_camera)

	_history = SubViewport.new()
	_history.disable_3d = true
	_history.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER # keep last frames, so the mix accumulates
	add_child(_history)
	var mix := TextureRect.new()
	mix.texture = _scene.get_texture()
	mix.modulate = Color(1, 1, 1, BLEND)
	mix.set_anchors_preset(Control.PRESET_FULL_RECT)
	_history.add_child(mix)

	_layer = CanvasLayer.new()
	_layer.layer = -1 # behind the HUD, panel and touch pads
	add_child(_layer)
	_shown = TextureRect.new()
	_shown.texture = _history.get_texture()
	_shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shown.stretch_mode = TextureRect.STRETCH_SCALE
	_shown.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_shown)
	set_enabled(false)


func set_enabled(on: bool) -> void:
	enabled = on
	_main.disable_3d = on # the buffer draws the 3D view instead
	_layer.visible = on
	var mode := SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	_scene.render_target_update_mode = mode
	_history.render_target_update_mode = mode
	set_process(on)


func _process(_delta: float) -> void:
	# copy the camera each frame, and keep the buffers the size of the window and the same anti-aliasing
	_camera.global_transform = _source.global_transform
	_camera.projection = _source.projection
	_camera.fov = _source.fov
	_camera.size = _source.size
	_camera.near = _source.near
	_camera.far = _source.far
	_camera.keep_aspect = _source.keep_aspect
	_camera.current = true
	_scene.msaa_3d = _main.msaa_3d
	if _scene.size != _main.size:
		_scene.size = _main.size
		_history.size = _main.size
