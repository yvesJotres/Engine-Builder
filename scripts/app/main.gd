extends Node3D

# Coordinator: builds the scene, runs the physics each frame, and routes input and changes
# between the parts. Physics lives in EngineSim; the drawing in EngineModel and friends;
# the screen in scripts/ui; the floor in scripts/world.

const THROTTLE_SPEED := 1.0 / 0.3 # full travel per second while held open: 0.3 s closed to wide open, a wrist roll. The
# plate is mechanically 1:1 with the twist (cable, no servo), so this number models the hand and nothing else. Written as
# 1/0.3 rather than 3.333 so the 0.3 s is exact. It also sets how fast S closes the throttle (0.3 s), still under the
# clank's CLANK_MIN_RATE (6.0), so an eased close stays silent.
const CAR_MODEL := preload("res://scripts/model/bike/car_model.gd")
const DYNO_TEST_SCRIPT := preload("res://scripts/dyno/dyno_test.gd")
const DYNO_VIEW_SCRIPT := preload("res://scripts/dyno/dyno_view.gd")
const DYNO_CELL_SCRIPT := preload("res://scripts/model/props/dyno_cell.gd")
const SPL_RIG_SCRIPT := preload("res://scripts/model/props/spl_meter_rig.gd")
const AUDIO_RENDERER_SCRIPT := preload("res://scripts/audio/audio_renderer.gd")
const ENGINE_STATS_SCRIPT := preload("res://scripts/ui/engine_stats.gd")
const SHIFT_SENSOR := preload("res://scripts/ecu/shift_sensor.gd")
const THROTTLE_RETURN_SPEED := 13.3 # full travel per second when released. Measured on a real grip: 0.075 s from
# letting go to the clank of the throttle hitting its shut stop (frame 10 at 0.902 s -> impact at 0.978 s in a 10 fps
# clip, impact timed from the audio track). Full travel at 13.3/s is 0.075 s. Method: tools/diagnostics/
# throttle_return_probe.py CLIP --clank --release-frame N. A real tube snaps shut about 4x faster than the old 3.0
# guess (0.333 s), which read as a lazy return; if playtesting wants it softer, this is the one number to change.
const SHIFT_PRELOAD_TIME := 0.8
const SHIFT_MATCH_RPM := 300.0
# The throttle clank, recorded from a real grip: the tube hitting its shut stop. Fired when the spring returns the
# throttle to zero, not when the player eases it shut, and scaled by how far it had been opened (see _play_clank).
const CLANK_STREAM := preload("res://assets/sfx/throttle_closed_clank.wav")
const CLANK_GAIN_DB := -8.0 # sits under the engine; the sample itself peaks at -1 dBFS
const CLANK_MIN_OPEN := 0.12 # a blip this small does not slam the stop
const CLANK_MIN_RATE := 6.0 # full travel per second: the spring returns at 13.3, an eased close with S at 1.5
const CLANK_PITCH_JITTER := 0.08 # +-8% so repeats are not identical takes
const CLANK_GAIN_JITTER_DB := 1.5
# The clank is spatial: it plays at the throttle housing, so orbiting the camera away from the bars pulls it down like
# everything else. CLANK_UNIT_SIZE is the 1/r reference, i.e. the distance the tick is calibrated at, and that is the
# default camera seat measured to the bar: 15 scene units, not the 18 the exhaust uses - the camera orbits 11 units
# from the bike's centre and the right bar end is 9.6 units forward of that, so the bars are further from the lens than
# the tailpipe is. It is the same tick at the same level there as the 2D player it replaced, and 1/r from there out
# (SpatialFalloff states the model). CLANK_MAX_DB 0 stops it getting louder as the camera zooms in; the cull at 100x
# the reference puts it 40 dB down - inaudible - at 150 scene units.
const CLANK_UNIT_SIZE := 15.0 # 1/r reference: the default camera's distance to the right bar end, where it is calibrated
const CLANK_MAX_DB := 0.0 # flattened near field: a tick does not get louder in your ear
const CLANK_MAX_DISTANCE := SpatialFalloff.CULL_FACTOR * CLANK_UNIT_SIZE
# A positional mono source is panned with an equal-power law, 1/sqrt(2) per channel, which a non-positional player
# never was: the old 2D clank played at full level on both channels. The 3.01 dB comes back here so the tick at the
# default seat is exactly as loud as it was.
const CLANK_PAN_DB := -SpatialFalloff.PAN_LAW_DB

var spec := EngineSpec.new()
var _sim := EngineSim.new()
var _blur: MotionBlur
var _sound: EngineSound
var _light: DirectionalLight3D
var _orbit: OrbitCamera
var _model: EngineModel
var _drivetrain: Drivetrain
var _car = CAR_MODEL.new()
var _car_mode := false
var _bike_camera_target := Vector3.ZERO
var _bike_camera_distance := 11.0
var _clutch: Clutch
var _gearbox: GearboxModel
var _tank: FuelTankModel
var _fuel_line: FuelLine
var _exhaust: Exhaust
var _panel: ControlPanel
var _stats
var _hud: Hud
var _pause: PauseMenu
var _paused := false
var _frame := 0 # debug trace: frames since start
var _crank := 0.0 # crank angle for the drawing, 0..720
var _throttle := 0.0
var _ignition := true # the engine kill switch is on RUN; the panel flips it
# Phones: the app closes when it has been in the background for this long
const BACKGROUND_LIMIT_MS := 30000
const SLOW_MOTION_SCALE := 0.1 # Tab: a tenth of real time, slow enough to watch a valve open and close
var _background_since := -1
var _clutch_held := false # Shift is held: clutch pulled in
var _digital_clutch := false # the keyboard or the lever pulled all the way: the only sources that can force the plates apart
var _pad_debug := false # F9: show what the pad reports, axis by axis
var _pad_debug_next := 0
var _camera_view := 0 # which of the panel's camera views is showing, for the 1/2 keys and the D-pad
# A panel change rebuilds the whole 3D bike, which is far too heavy to run on every tick of a dragged slider. The cheap
# half of a change (engine spec, gear ratios, sound levels) still applies at once; the geometry waits REBUILD_DELAY and
# a burst of changes produces one rebuild.
const REBUILD_DELAY := 0.12
var _rebuild_timer: Timer
var _rebuild_dirty := false
var rebuilds_done := 0 # counted so a test can prove the burst collapses
var _brake_held := false # B is held
var _sound_on := true # the Sound option in the pause menu
var _clank: AudioStreamPlayer3D
# The SPL meter stands where a real exhaust test puts its microphone: 0.5 m from the outlet, 45 degrees off the flow,
# at the outlet's height and outboard of the bike (SplMeter has the standard and the calibration). It reads the engine's
# own output through the free-field law, so it follows the tune, not the volume slider.
const SPL_ATTACK := 0.05 # s, rise time: follows the firing pulses without flickering
const SPL_RELEASE := 0.6 # s, fall time: peak hold, so a blip stays readable
var _spl_mic := Vector3.ZERO # where the microphone stands: the 0.5 m / 45 degree test position
var _spl_db := -100.0
var _spl_rig: Node3D # the stand the microphone sits on, drawn where the reading is taken
var _clank_open := 0.0 # opening at the moment of a sudden release; >0 means a clank is owed at the stop
var _clank_plays := 0 # how many times the clank has fired, for the headless test
var _throttle_last := 0.0
var _throttle_springing := false # this frame's throttle move came from the return spring, not the player
var _touch: TouchControls
var _touch_throttle := 0.0 # the on-screen throttle lever, 0 = closed, 1 = wide open
var _touch_clutch := 0.0 # the on-screen clutch lever, 0 = engaged, 1 = pulled in
var _touch_brake := false
var _touch_starter := false
var _panel_starter := false
var _shift_sensor: ShiftSensor
var _sound_gate := 0.0 # 0 = exhaust silent, 1 = exhaust full, fades between
var _idle_audio_cleared := false
const SOUND_FADE_TIME := 0.05 # s, fade in and out of the exhaust note
var _backfires_heard := 0 # the sim's backfire count the sound has already played
var _backfire_flame: BackfireFlame # the flash at the pipe mouth
var _exhaust_fume: ExhaustFume # the vapour and soot leaving the pipe
var _dyno = DYNO_TEST_SCRIPT.new()
# Dyno cell: the bike runs against a roller drum with an eddy-current brake
const DRUM_MASS_KG := 80.0 # drum inertia as the equivalent mass at the tyre (about 5 kg·m² on a 0.25 m drum), estimate
const CELL_LOAD_RPM := 2500.0 # rpm above which the cell's brake loads the engine
const CELL_MAX_LOAD_N := 1000.0 # eddy-current brake force at the tyre at 100% load, estimate
var _cell_on := false
var _cell: Node3D
var _cell_status: Label
var _cell_load := 0.5
var _dyno_view
var _audio_renderer
var _render_dialog: FileDialog = null # the Save As window for the render, built on first use
var _render_folder := "" # the folder the last render was saved to, so the next dialog opens there
var _pending_render_layout: ExhaustLayout = null # the layout captured when Render was pressed
var _render_settings: ConfirmationDialog = null # length, throttle and bit depth, asked before the file
var _render_duration_box: SpinBox = null
var _render_throttle_box: OptionButton = null
var _render_bits_box: OptionButton = null
var _render_progress_popup: PopupPanel = null # shown while a render runs
var _render_progress_bar: ProgressBar = null
var _render_progress_label: Label = null
var _pending_shift := 0
var _shift_time := 0.0
var _shift_target := -1


func _ready() -> void:
	_trace("ready start")
	Gamepad.load_config()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.08, 0.1)
	# ambient light so the dark parts (tyre, block) still show their shape
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.45, 0.5)
	env.ambient_light_energy = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	_light = DirectionalLight3D.new()
	_light.rotation_degrees = Vector3(-45, 30, 0)
	_light.light_energy = 1.6
	add_child(_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(35, -145, 0)
	fill_light.light_color = Color(0.8, 0.87, 1.0)
	fill_light.light_energy = 0.6
	add_child(fill_light)

	_orbit = OrbitCamera.new()
	add_child(_orbit)
	add_child(Ground.new())

	_model = EngineModel.new()
	add_child(_model)
	_drivetrain = Drivetrain.new()
	_dyno.shift_pedal_requested.connect(_drivetrain.animate_shift)
	add_child(_drivetrain)
	_car.visible = false
	add_child(_car)
	_clutch = Clutch.new()
	add_child(_clutch)
	_gearbox = GearboxModel.new()
	add_child(_gearbox)
	_tank = FuelTankModel.new()
	add_child(_tank)
	_fuel_line = FuelLine.new()
	add_child(_fuel_line)
	_exhaust = Exhaust.new()
	add_child(_exhaust)
	_spl_rig = SPL_RIG_SCRIPT.new()
	add_child(_spl_rig)
	_spl_rig.build()
	# a backfire is a flash at the pipe mouth as well as a bang: sized by the energy the cylinder released
	_backfire_flame = BackfireFlame.new()
	add_child(_backfire_flame)
	_backfire_flame.build()
	# and what comes out of the pipe between the bangs: vapour while the gas is cool, soot while it is rich
	_exhaust_fume = ExhaustFume.new()
	add_child(_exhaust_fume)
	_exhaust_fume.build()
	_sound = EngineSound.new()
	add_child(_sound)
	# the clank is a body-borne mechanical tick inside the right-hand bar, so it comes from there: a 3D player at the
	# throttle housing, positioned every frame in _process, with polyphony so a fast blip does not cut the previous tail
	_clank = AudioStreamPlayer3D.new()
	_clank.stream = CLANK_STREAM
	_clank.max_polyphony = 3
	_clank.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_clank.unit_size = CLANK_UNIT_SIZE
	_clank.max_db = CLANK_MAX_DB
	_clank.max_distance = CLANK_MAX_DISTANCE
	# No distance filter. The default is a -24 dB shelf above 5 kHz that closes with distance, which at 6 m is about
	# 5000x the real air absorption (0.05 dB there) and would eat the 14-19 kHz half of the sample. The band a phone
	# speaker keeps, 0.5-2 kHz, must not depend on the distance tuning at all; with no shelf it cannot.
	_clank.attenuation_filter_db = 0.0
	add_child(_clank)

	_panel = ControlPanel.new()
	add_child(_panel)
	_panel.changed.connect(_on_panel_changed)
	_rebuild_timer = Timer.new()
	_rebuild_timer.one_shot = true
	_rebuild_timer.wait_time = REBUILD_DELAY
	_rebuild_timer.timeout.connect(_rebuild_scene)
	add_child(_rebuild_timer)
	_panel.refuel_pressed.connect(func() -> void:
		_sim.fuel.refill()
		_hud.flash("TANK FILLED"))
	_panel.kill_switch_changed.connect(func(killed: bool) -> void: _ignition = not killed)
	_panel.starter_changed.connect(func(held: bool) -> void: _panel_starter = held)
	_panel.camera_requested.connect(_on_camera_requested)
	_panel.engine_cover_changed.connect(func(assembled: bool) -> void: _model.set_assembled_view(assembled))
	_panel.dyno_pressed.connect(_on_dyno_pressed)
	_panel.render_pressed.connect(_on_render_pressed)
	_stats = ENGINE_STATS_SCRIPT.new()
	add_child(_stats)

	_audio_renderer = AUDIO_RENDERER_SCRIPT.new()
	add_child(_audio_renderer)
	_audio_renderer.render_completed.connect(func(path: String) -> void:
		_show_render_progress(false)
		_hud.flash("RENDER SAVED: %s" % [path.get_file()]))
	_audio_renderer.render_failed.connect(func(msg: String) -> void:
		_show_render_progress(false)
		_hud.flash("RENDER FAILED: %s" % [msg]))
	_audio_renderer.render_progress.connect(_on_render_progress)
	_audio_renderer.render_progress.connect(func(p: float) -> void:
		_hud.flash("RENDERING: %d%%" % [roundi(p * 100)]))

	_hud = Hud.new()
	add_child(_hud)
	# A pad plugged in mid-session announces its mapping once, so the rider is not guessing which shoulder is the clutch.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_dyno_view = DYNO_VIEW_SCRIPT.new()
	add_child(_dyno_view)
	_dyno_view.stop_requested.connect(func() -> void: _dyno.cancel())
	_build_cell_panel()

	_pause = preload("res://scenes/pause_menu.tscn").instantiate()
	add_child(_pause)
	_pause.probe_requested.connect(_run_frame_probe)
	_pause.resume_requested.connect(func() -> void: _set_paused(false))
	_pause.quality_changed.connect(_on_quality_changed)
	_pause.accuracy_changed.connect(_on_accuracy_changed)
	_blur = MotionBlur.new()
	add_child(_blur)
	_blur.setup(get_viewport(), _orbit.camera)
	_pause.blur_toggled.connect(_blur.set_enabled) # off by default
	_pause.sound_toggled.connect(_on_sound_toggled) # the sound switch lives in Options only
	var fps := preload("res://scripts/ui/fps_overlay.gd").new()
	add_child(fps)
	_pause.fps_toggled.connect(func(on: bool) -> void: fps.shown = on)
	_pause.hud_changed.connect(_hud.set_mode)
	_pause.fps_cap_changed.connect(_apply_fps_cap)
	_pause.apply_settings()
	_touch = TouchControls.new()
	add_child(_touch)
	_touch.throttle_changed.connect(func(amount: float) -> void: _touch_throttle = amount)
	_touch.clutch_changed.connect(func(amount: float) -> void: _touch_clutch = amount)
	_touch.brake_changed.connect(func(on: bool) -> void: _touch_brake = on)
	_touch.starter_changed.connect(func(on: bool) -> void: _touch_starter = on)
	_touch.shift_pressed.connect(_shift)
	_touch.pause_pressed.connect(func() -> void: _set_paused(not _paused))
	_touch.setup_pressed.connect(func() -> void: _set_setup_open(not _panel.visible))
	
	# Shift sensor for realistic quickshifter
	_shift_sensor = SHIFT_SENSOR.new()
	_shift_sensor.upshift_threshold = 0.7
	_shift_sensor.downshift_threshold = 0.7
	_shift_sensor.debounce_ms = 50
	
	if OS.has_feature("mobile"):
		_set_setup_open(false)
	_trace("scene built")

	_on_panel_changed()
	flush_rebuild() # startup wants the bike now, not in 120 ms
	# A marker file in the app's data folder runs the frame cost probe at start-up, so a measurement
	# can be taken over USB without tapping through the menu. Nothing creates this file by itself.
	if FileAccess.file_exists("user://run_probe"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://run_probe"))
		_run_frame_probe()
	# Open with the engine from the previous session: the dropdown already shows that name, so the engine inside
	# has to be the same one. It waits for the library to load, which lands a frame or two after this.
	_panel.restore_last_engine()
	_trace("ready done")


func _unhandled_input(event: InputEvent) -> void:
	# a click on the 3D view takes focus away from any box in the panel, so W and S drive the throttle again
	if event is InputEventMouseButton and event.pressed:
		get_viewport().gui_release_focus()
	# slow motion is a hold: down for a tenth of real time, up for real time. Released keys matter, so this is read
	# before the "pressed" filter below.
	if event is InputEventKey and event.keycode == KEY_TAB and not event.echo:
		Engine.time_scale = SLOW_MOTION_SCALE if event.pressed else 1.0
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_set_paused(not _paused)
			get_viewport().set_input_as_handled()
		# stepping works while paused, which is the whole point of it, so it comes before the pause guard
		elif event.keycode == KEY_BRACKETLEFT or event.keycode == KEY_BRACKETRIGHT:
			_step_once()
			get_viewport().set_input_as_handled()
		elif _paused:
			pass # the game keys below do nothing while the pause menu is up
		elif event.keycode == KEY_K:
			_panel.toggle_kill()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F11:
			var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
			_pause.set_fullscreen_checked(not fullscreen)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F9:
			_pad_debug = not _pad_debug
			_hud.flash("PAD READOUT ON" if _pad_debug else "PAD READOUT OFF")
			get_viewport().set_input_as_handled()
		# rider aids, live: the panel switches they drive are the same ones, so the state cannot disagree
		elif event.keycode == KEY_T:
			_toggle_aid("traction_control_enabled")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Y:
			_toggle_aid("abs_enabled")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_U:
			_toggle_aid("quickshifter")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_L:
			_toggle_aid("launch_control")
			get_viewport().set_input_as_handled()
		# the view: panel off for a full 3D look, HUD off for a clean shot, mute for a quiet bench
		elif event.keycode == KEY_P:
			_panel.visible = not _panel.visible
			_hud.flash("PANEL %s" % ("SHOWN" if _panel.visible else "HIDDEN"))
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_H:
			_hud.visible = not _hud.visible
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_M:
			_sound_on = not _sound_on
			_hud.flash("SOUND %s" % ("ON" if _sound_on else "OFF"))
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R:
			_reset_bike()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_1 or event.keycode == KEY_2:
			_cycle_camera(1 if event.keycode == KEY_1 else 0)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F5:
			_on_dyno_pressed()
			get_viewport().set_input_as_handled()
	# the same two actions from the pad, so the game can be ridden with the controller alone: Start pauses, Back is the
	# kill switch. Both are edge events, so holding the button does not toggle twice.
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == Gamepad.PAUSE_BUTTON:
			_set_paused(not _paused)
			get_viewport().set_input_as_handled()
		elif event.button_index == Gamepad.KILL_BUTTON and not _paused:
			_panel.toggle_kill()
			get_viewport().set_input_as_handled()
		elif not _paused and event.button_index == JOY_BUTTON_DPAD_LEFT:
			_toggle_aid("traction_control_enabled")
			get_viewport().set_input_as_handled()
		elif not _paused and event.button_index == JOY_BUTTON_DPAD_RIGHT:
			_toggle_aid("abs_enabled")
			get_viewport().set_input_as_handled()
		elif not _paused and event.button_index == JOY_BUTTON_DPAD_UP:
			_cycle_camera(1)
			get_viewport().set_input_as_handled()
		elif not _paused and event.button_index == JOY_BUTTON_DPAD_DOWN:
			_cycle_camera(0)
			get_viewport().set_input_as_handled()


# Flips one of the panel's on/off switches from a key or the pad, so a rider aid can be changed without opening the page.
# The panel stays the single source of truth: the same switch moves, and its change signal updates the engine spec.
func _toggle_aid(key: String) -> void:
	var said := _panel.toggle_aid(key)
	if said == "":
		return
	_panel.apply_to(spec) # values only: no changed signal, so no engine rebuild for a switch
	_hud.flash(said)


# Steps one frame of game time while paused, for looking at a single moment of the valvetrain or the clutch.
func _step_once() -> void:
	if not _paused:
		return
	_paused = false
	_process(1.0 / 60.0)
	_paused = true


# Switches between the panel's camera views; step 1 goes forward, 0 back, so D-pad up/down reads naturally.
func _cycle_camera(step: int) -> void:
	var views: Array = _panel.camera_views()
	if views.is_empty():
		return
	_camera_view = posmod(_camera_view + (step if step != 0 else -1), views.size())
	_on_camera_requested(views[_camera_view])
	_hud.flash("CAMERA: %s" % String(views[_camera_view]).to_upper())


# Back to a stopped, neutral bike: the state a reset should leave behind, without rebuilding the engine.
func _reset_bike() -> void:
	_sim.speed = 0.0
	_sim.gear.gear = 0
	_sim.clutch_pull = 0.0
	_sim.clutch_engage = 1.0
	_throttle = 0.0
	_touch_throttle = 0.0
	_hud.flash("RESET: NEUTRAL, STOPPED")


# True while a text field owns the keyboard focus: the player is naming a build, not riding, so the riding keys are
# not read. A focused LineEdit or TextEdit (the build-name box) would otherwise take W as throttle and Q/E as shifts.
func _typing_in_field() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if connected and _hud != null:
		_hud.flash(Gamepad.mapping_hint())


# The clank is the grip arriving at its shut stop, so it plays when the throttle reaches zero, not when the hand leaves
# it. The delay is the spring doing its work: 1 / THROTTLE_RETURN_SPEED is 75 ms at full opening, the same 0.075 s that
# was measured on the real grip. Two gates decide whether a release has earned one:
#   - how far it was open: a 5% blip does not slam the stop;
#   - how fast it came back: the spring returns at 13.3 full travel/s and the eased S key at 1.5, so a slow close is
#     silent. That is the "pull back speed" test, measured rather than assumed.
func _update_throttle_clank(delta: float) -> void:
	var prev := _throttle_last
	_throttle_last = _throttle
	if _paused:
		_clank_open = 0.0 # pausing zeroes the throttle; that must not be heard as a slam
		return
	var rate := (prev - _throttle) / maxf(delta, 0.0001) # full travel per second, this frame
	if _clank_open <= 0.0 and prev >= CLANK_MIN_OPEN and _throttle < prev and rate >= CLANK_MIN_RATE:
		_clank_open = prev # a clank is owed, scaled by this opening
	if _clank_open <= 0.0:
		return
	if _throttle <= 0.0:
		_play_clank(_clank_open)
		_clank_open = 0.0
	elif not _throttle_springing:
		_clank_open = 0.0 # opened again mid-return, so nothing hits the stop


# Level follows the energy at the stop. A return spring delivers roughly constant torque, so the speed at the stop goes
# with the square root of the distance travelled, and the impact level with it: a 20% blip is about half as loud as a
# full twist, not a fifth. Pitch and level are jittered so a chain of blips does not sound like one take repeated.
func _play_clank(opening: float) -> void:
	if not _sound_on:
		return
	var energy := sqrt(clampf(opening, 0.0, 1.0))
	_clank.pitch_scale = 1.0 + randf_range(-CLANK_PITCH_JITTER, CLANK_PITCH_JITTER)
	_clank.volume_db = (CLANK_GAIN_DB + CLANK_PAN_DB + linear_to_db(maxf(energy, 0.02))
		+ randf_range(-CLANK_GAIN_JITTER_DB, CLANK_GAIN_JITTER_DB))
	_clank.play()
	_clank_plays += 1


# The meter stands a metre behind the bike, on its axis: back along the wheelbase from the tailpipe tip, at whatever
# height the tip is (a real meter is held off the pipe, not off the floor). Ballistics are a fast rise and a slow
# release, so the reading sits on the sound instead of on the frame it was sampled in.
func _update_spl_meter(delta: float) -> void:
	# 45 degrees off the direction the gas leaves the pipe, on the side the pipe sticks out from, level with the outlet.
	# The flow is taken horizontal: a muffler that rises still exits into a meter held at the outlet's height.
	var flow := Vector3(_tail_dir.x, 0.0, _tail_dir.z)
	flow = flow.normalized() if flow.length() > 0.001 else Vector3.FORWARD
	var side := flow.cross(Vector3.UP).normalized()
	if _tail_tip.x < 0.0:
		side = -side # outboard: the microphone stands on the side of the bike the pipe is on
	var off := deg_to_rad(SplMeter.MIC_ANGLE_DEG)
	_spl_mic = _tail_tip + (flow * cos(off) + side * sin(off)).normalized() * SplMeter.MIC_DISTANCE
	_spl_mic.y = maxf(_spl_mic.y, Ground.Y + SplMeter.MIC_MIN_HEIGHT)
	var rms := _sound.output_rms if _sound_on and not _paused else 0.0
	var level := SplMeter.level_db(rms)
	var tau := SPL_ATTACK if level > _spl_db else SPL_RELEASE
	_spl_db = lerpf(_spl_db, level, 1.0 - exp(-maxf(delta, 0.0) / tau))
	# the stand is drawn where the reading is taken: the capsule sits on the point, the display shows the number
	if _spl_rig != null:
		_spl_rig.place(_spl_mic, _tail_tip, Ground.Y)
		_spl_rig.set_reading(SplMeter.text(_spl_db))


func _process(delta: float) -> void:
	_frame += 1
	if _frame <= 120 or _frame % 120 == 0:
		_trace("frame %d" % _frame)
	# while paused no gameplay key counts, and neither does one typed into a text field: naming a build must not
	# open the throttle with W or shift with Q and E
	var typing := _typing_in_field()
	var open_keys := not _paused and KeyboardControls.throttle_open(typing)
	var close_keys := not _paused and KeyboardControls.throttle_close(typing)
	# spring-return throttle: holding W/Up opens it, letting go springs it back to closed
	if open_keys:
		_throttle = minf(_throttle + THROTTLE_SPEED * delta, 1.0)
		_throttle_springing = false
	elif close_keys:
		_throttle = maxf(_throttle - THROTTLE_SPEED * delta, 0.0)
		_throttle_springing = false # eased shut by the player, not slammed by the spring
	else:
		_throttle = move_toward(_throttle, 0.0, THROTTLE_RETURN_SPEED * delta)
		_throttle_springing = true

	# the throttle lever sets the opening directly, and springs back to closed through the return above when let go
	if _touch_throttle > 0.0:
		_throttle = _touch_throttle
		_throttle_springing = false
	# A gamepad trigger is a real analog throttle: the finger's position is the opening, no ramp needed. It is
	# authoritative whenever it is off its stop, following the finger on the way shut as well as the way open, so
	# backing off 80 % to 30 % lands exactly on 30 % instead of being swallowed by the return spring. Fully released,
	# the spring ramp above takes over - which is what shuts the butterfly in 75 ms and earns the clank.
	var pad := Gamepad.device()
	# a pad whose triggers are not on the axes we expect teaches us which axes they are on, the moment they are squeezed
	var learned := Gamepad.learn_axes(pad)
	if learned != "":
		_hud.flash("GAMEPAD: %s LEARNED ON AXIS %d" % [learned.to_upper(),
			Gamepad.throttle_axis if learned == "throttle" else Gamepad.clutch_axis])
	var pad_throttle := Gamepad.throttle(pad)
	if pad_throttle > 0.0:
		if Gamepad.throttle_is_digital():
			# the trigger is a switch: only 0 and 1 are ever reported, so its hold is ramped like the W key rather than
			# slamming the butterfly from shut to wide open in one frame. Releasing falls through to the spring above.
			_throttle = minf(_throttle + THROTTLE_SPEED * delta, 1.0)
		else:
			_throttle = pad_throttle
		_throttle_springing = false
	_record_pad_frame(pad, pad_throttle)
	# F9: what the pad is actually reporting, so a dead trigger shows its axis instead of just doing nothing
	if _pad_debug and Time.get_ticks_msec() >= _pad_debug_next:
		_pad_debug_next = Time.get_ticks_msec() + 600
		_hud.flash(Gamepad.describe(pad))
	_update_throttle_clank(delta)
	# a pulled clutch lever slips the clutch by its amount; past half way it counts as pulled in for the interlocks
	# the clutch trigger is analog, like the touch lever: it slips by how far it is pulled. Whichever is further in wins.
	# The key is a full pull and it writes the same lever value the touch lever and the pad trigger write: launch
	# control and the friction zone both read clutch_pull, so a keyboard rider must not be a different rider.
	var key_clutch := KeyboardControls.clutch(typing)
	_sim.clutch_pull = maxf(_touch_clutch, 1.0 if key_clutch else 0.0)
	_sim.clutch_pull = maxf(_sim.clutch_pull, Gamepad.clutch(pad))
	if spec.transmission_type == "dual_clutch" and _sim.gear.gear > 0 and not _dyno.active():
		var engagement := clampf((_sim.rpm - spec.idle_target_rpm * 0.9) / maxf(spec.idle_target_rpm * 0.8, 1.0), 0.0, 1.0)
		_sim.clutch_pull = 0.9 - 0.4 * engagement if _sim.speed < 5.0 else 0.0
	# _clutch_held is the DIGITAL all-the-way-in the sim forces the plates apart on, not the analog pull: only the
	# keyboard and the lever's own end can ask for that. The trigger writes clutch_pull and nothing else - handing its
	# threshold to the sim as clutch_held is what made the clutch stay fully open until the pull came back under it, so
	# the bite only arrived in the last 30 % of the release.
	_digital_clutch = key_clutch or _touch_clutch > 0.5
	_clutch_held = _digital_clutch or Gamepad.clutch_full(pad)
	_brake_held = KeyboardControls.brake(typing) or _touch_brake or Gamepad.braking(pad)

	_sim.audio_enabled = _sound_on
	_sound.audio_enabled = _sound_on
	
	# Shift sensor: compute shift force from input. Keys first, then the pad's shoulders, so a mixed setup behaves.
	var shift_force := 0.0
	if not _paused and not typing:
		shift_force = KeyboardControls.shift_force(typing)
		if shift_force == 0.0:
			shift_force = Gamepad.shift_force(pad)
	
	var shift_result = _shift_sensor.update(shift_force, delta)
	
	if shift_result == 1:
		_shift(true)
	elif shift_result == -1:
		# A downshift request is not a blip by itself. Asking for a lower gear from neutral, or with the
		# clutch pulled in, is not a clutch-less downshift, and blipping there raced the engine with the
		# clutch open. The blip is triggered where a lower gear actually engages with the clutch closed.
		_shift(false)

	if _dyno.active() and not _paused:
		# the dyno test drives the throttle, clutch and gearbox itself, and steps the same engine physics
		_dyno.advance(delta, _sim, spec, _panel.lambda(), _ignition)
		_throttle = _dyno.throttle
		_clutch_held = _dyno.clutch_held
		_crank = fmod(_crank + _sim.rpm * 6.0 * delta, 720.0)
		_update_vehicle_wheels(delta)
	elif not _paused:
		# the starter button and the touch pad crank the engine; the throttle keys do not, so opening the throttle
		# on a stopped engine winds it over instead of starting it. The starter only turns in neutral or with the
		# clutch pulled in, as the interlock on a modern bike.
		var wants_start := _touch_starter or _panel_starter or KeyboardControls.starter(typing) or Gamepad.starter(pad)
		var in_neutral_or_pulled := _sim.gear.gear == 0 or _clutch_held
		if wants_start and not in_neutral_or_pulled:
			_hud.flash("PULL CLUTCH OR SHIFT TO NEUTRAL TO START")
		if wants_start and not _ignition:
			_hud.flash("KILL SWITCH IS ON: SET IT TO RUN TO START")
		# only the Shift key pulls the clutch fully apart; the lever's own pull sets the friction zone through clutch_pull
		# Get throttle override from ECU (quickshifter cut/blip)
		# ECU timers advance only in the fixed physics loop.
		
		_sim.step(delta, spec, _throttle, _ignition, wants_start and in_neutral_or_pulled, _digital_clutch, _brake_held, _panel.lambda())
		_update_shift_request(delta)
		if _frame <= 3: _trace("sim stepped")
		_crank = fmod(_crank + _sim.rpm * 6.0 * delta, 720.0)
		_update_vehicle_wheels(delta)
		if _frame <= 3: _trace("drivetrain updated")
	_model.set_throttle(_throttle)
	_model.update_crank(_crank)
	# the flame and the spark come from the sim's own burn state, after the crank has placed the pistons
	_model.update_combustion(_sim.cylinders, delta)
	if _frame <= 3: _trace("engine model updated")
	_clutch.update(-_crank / spec.primary_ratio, _sim.clutch_engage) # basket turns at primary-reduced speed, with the crank
	_tank.update(_sim.fuel.fraction(), Color(0.2, 0.55, 0.3) if _sim.fuel.kind == "e85" else Color(0.2, 0.4, 0.9))
	if _frame <= 3: _trace("clutch and tank updated")
	_sound.rpm = _sim.rpm
	_sound.drive.update_from(_sim, spec, _throttle)
	_sound.compressor_load = _sim.intake.compressor_load if spec.electric_compressor else 0.0
	_sound.position = _tail_tip
	if _backfire_flame != null:
		_backfire_flame.place(_tail_tip, _tail_dir)
	if _exhaust_fume != null:
		_exhaust_fume.place(_tail_tip, _tail_dir)
	# the clank comes from the right bar end, which moves when the bike is rebuilt
	if _drivetrain != null:
		_clank.position = _drivetrain.throttle_housing_position()
	_update_spl_meter(delta)
	# the pipes glow when their walls are hot enough, which takes hot running: see ExhaustHeat for the thresholds
	_exhaust.update_heat(_sim.exhaust_temp_c(), delta)
	_backfire_flame.update(delta)
	# the plume is the engine's own gas: temperature decides the vapour, mixture decides the soot, mass flow scales both
	_exhaust_fume.update(_sim.exhaust_temp_c() + 273.15, _sim.exhaust_mass_flow(), _sim.o2_lambda(), delta)
	if _sound_on:
		_sound.set_conditions(_sim.o2_lambda(), _sim.exhaust_temp_c(), _sim.backpressure_pa())
		if _sim.uses_pipe_sound():
			_sound.push_flow(_sim.exhaust.take_flow())
		else:
			_sound.push_flow(_sim.take_blowdown())
		_sound.push_intake_flow(_sim.take_intake_flow())
	else:
		if _sim.exhaust != null:
			_sim.exhaust.take_flow()
		_sim.take_blowdown()
		_sim.take_intake_flow()
	var gate_target := 1.0 if _sim.rpm > 1.0 else 0.0
	_sound_gate = move_toward(_sound_gate, gate_target, delta / SOUND_FADE_TIME)
	if _sound_gate <= 0.0:
		if not _idle_audio_cleared:
			_sound.clear_pending()
			_idle_audio_cleared = true
	else:
		_idle_audio_cleared = false
		if _sound_on and not _sound.playing:
			_sound.play()
	_sound.stream_paused = _paused or not _sound_on or _sound_gate <= 0.0
	_sound.volume_db = (0.0 if _sound_on else -80.0) + linear_to_db(maxf(_sound_gate, 0.0001))
	# each backfire pops the exhaust once, and flashes on the dashboard
	if _sim.backfire_count != _backfires_heard:
		_backfires_heard = _sim.backfire_count
		_hud.flash("BACKFIRE")
		_backfire_flame.pop(_sim.last_backfire_j)
		if not _sim.exhaust_solver:
			_sound.backfire(_sim.last_backfire_j)

	var clutch_state := "open" if _sim.clutch_engage < 0.01 else ("engaged" if _sim.clutch_engage > 0.99 else "slipping")
	var stopped := _sim.rpm < 1.0
	var torque := 0.0 if stopped else _sim.torque
	var power_hp := 0.0 if stopped else Units.w_to_hp(Units.power_w(_sim.torque, _sim.rpm))
	var bmep_bar := 0.0 if stopped else _sim.bmep_pa() / 1.0e5
	var imep_bar := 0.0 if stopped else _sim.imep_pa() / 1.0e5
	var ca50 := _sim.ca50_deg()
	var ca50_text := "—" if ca50 < 0.0 else "%.0f°" % ca50
	_stats.set_engine_data("RPM %.0f   Instant crank torque %.1f N·m\nInstant power %.1f hp\nBMEP %.1f bar   IMEP %.1f bar   ηm %.0f%%\nVE %.0f%%   BSFC %.0f g/kWh   ηb %.0f%%\nPmax %.0f bar   CA50 %s   10–90 %.0f°\nIntake %.1f psi   Air %.0f °C\nThrottle %d%%   Clutch %s (%d%%)\nFuel %.1f kg (%d%%)   %.2f g/s\nMixture target λ %.2f   Timing %+.1f°\nKnocks %d   Audio %s (%s)" % [
		_sim.rpm, torque, power_hp,
		bmep_bar, imep_bar, _sim.mechanical_efficiency() * 100.0,
		_sim.volumetric_efficiency() * 100.0, _sim.bsfc_g_kwh(), _sim.brake_thermal_efficiency() * 100.0,
		_sim.peak_pressure_pa() / 1.0e5, ca50_text, _sim.burn_10_90_deg(),
		Units.pa_to_psi(_sim.intake.pressure), Units.k_to_c(EngineAir.T0),
		roundi(_throttle * 100), clutch_state, roundi(_sim.clutch_engage * 100.0), _sim.fuel.mass_kg, roundi(_sim.fuel.fraction() * 100), _sim.fuel_flow,
		_panel.lambda(), spec.ignition_offset_deg,
		_sim.knock_count, "on" if _sound_on else "muted", "starved" if _sound.starved else ("playing" if _sound.playing else "no output")])
	if spec.electric_compressor:
		_stats._engine_data.text += "\nE-compressor: %.2f×  Battery %.0f%% (estimated)" % [_sim.intake.boost_ratio, _sim.intake.compressor_charge * 100.0]
	# Update compressor map view if turbo section is available
	if _panel._controls.has("compressor_map_view") and _sim.intake.has_map():
		var map_view = _panel._controls["compressor_map_view"]
		var corr_flow = _sim.intake.map_correct_flow(_sim.intake.pressure * spec.manifold_volume_scale / (EngineAir.R_AIR * EngineAir.T0), EngineAir.T0, EngineAir.P0)
		# Use engine mass flow as approximation
		var m_dot = 0.0
		for c in _sim.cylinders:
			m_dot += c.runner_q * (EngineAir.P0 / (EngineAir.R_AIR * EngineAir.T0))
		corr_flow = _sim.intake.map_correct_flow(m_dot, EngineAir.T0, EngineAir.P0)
		var corr_speed = _sim.intake.map_correct_speed(_sim.intake.compressor_speed_rpm, EngineAir.T0)
		map_view.set_operating_point(corr_flow, _sim.intake.compressor_pr, corr_speed)
	# the sensors: chamber temperature (hottest gas each cylinder reached last cycle), exhaust port span, O2
	var hottest := 0.0
	for c in _sim.cylinders:
		hottest = maxf(hottest, c.last_peak_temp - 273.15)
	var ports: Array = _sim.port_temps_c()
	var header_line := "Header —"
	if ports.size() == 1:
		header_line = "Header %.0f °C" % ports[0]
	elif ports.size() > 1:
		var coolest: float = ports[0]
		var warmest: float = ports[0]
		for t in ports:
			coolest = minf(coolest, t)
			warmest = maxf(warmest, t)
		header_line = "Headers %.0f–%.0f °C (%d)" % [coolest, warmest, ports.size()]
	_stats.set_sensors("Last-cycle chamber peak: mean %.0f °C\nHottest cylinder %.0f °C\n%s\nExhaust %.0f °C   O2 λ %.2f" % [_sim.chamber_peak_c(), hottest, header_line, _sim.exhaust_temp_c(), _sim.o2_lambda()])
	if _frame <= 3: _trace("sound settings done")
	_hud.update(_sim, spec, _clutch_held, _throttle, _spl_db)
	if _frame <= 3: _trace("hud updated")
	if _dyno_view.is_open():
		_dyno_view.refresh(_dyno)


# On the phone the app runs uncapped by default: Godot's vsync is off (project.godot sets
# vsync_mode 0), so the renderer posts a frame every ~8 ms - 125 fps on this handset - while the
# panel shows 60. More than half the CPU time and the whole GPU heat budget go on frames nobody
# sees, and that heat is what turns into stutter after a few minutes of running. 60 fps is the
# panel's own rate, so the cap costs no visible smoothness. The pause menu's "Frame rate" option
# picks between the cap and no cap; this is the default and the ceiling.
const MOBILE_MAX_FPS := 60


func _apply_fps_cap(index: int) -> void:
	Engine.max_fps = preload("res://scripts/ui/pause_menu.gd").FPS_CAPS[clampi(index, 0, 1)]


# Times one frame of the running app on this device, phase by phase, into user://frame_phases.txt.
# Loaded by path, not preloaded: this file ships inside the APK, but a project that strips it must
# never stop the game from opening.
func _run_frame_probe() -> void:
	var script: Resource = load("res://scripts/diagnostics/frame_phases.gd")
	if script == null:
		_hud.flash("FRAME PROBE NOT IN THIS BUILD")
		return
	var probe: Node = (script as GDScript).new()
	probe.name = "FramePhasesProbe"
	add_child(probe)
	_hud.flash("FRAME PROBE RUNNING")


func _shift(up: bool) -> void:
	if _dyno.active():
		_hud.flash("DYNO TEST IS RUNNING")
		return
	if spec.vehicle_type != "car":
		_drivetrain.animate_shift(up)
	if spec.transmission_type == "dual_clutch":
		_shift_dual_clutch(up)
		return
	_pending_shift = 1 if up else -1
	_shift_time = SHIFT_PRELOAD_TIME
	_shift_target = -1
	_update_shift_request(0.0)
	if _pending_shift != 0 and _shift_target < 0:
		_hud.flash("SHIFT PRELOADED")


func _update_vehicle_wheels(delta: float) -> void:
	var wheel_rpm := _sim.speed / EngineSim.tire_radius_m(spec) * 60.0 / TAU
	if spec.vehicle_type == "car":
		_car.update(wheel_rpm, delta)
	else:
		# the bars move with the rider's inputs: lever in, twist grip round, clutch lever pulled
		_drivetrain.update(_crank, wheel_rpm, delta, _sim.brake, _throttle, 1.0 - _sim.clutch_engage)
	_update_cell(delta)


func _shift_dual_clutch(up: bool) -> void:
	var before := _sim.gear.gear
	var target := mini(before + 1, spec.gear_ratios.size()) if up else maxi(before - 1, 0)
	if target == 0 and _sim.speed >= 0.5:
		target = before
	if target > 0 and target < before:
		var target_ratio: float = spec.primary_ratio * float(spec.gear_ratios[target - 1]) * spec.final_drive
		var target_rpm := _sim.speed / EngineSim.tire_radius_m(spec) * target_ratio * 60.0 / TAU
		if target_rpm > spec.redline_rpm * 1.03:
			_hud.flash("DOWNSHIFT BLOCKED: OVERREV")
			return
	if before == 0 and target > 0 and _sim.speed < 0.5:
		_sim.clutch_engage = 0.0
		_sim.clutch_pull = 1.0
	_sim.gear.gear = target
	if target == before:
		_hud.flash("TOP GEAR" if up else "BOTTOM GEAR")
	elif target == 0:
		_hud.flash("NEUTRAL")
	elif before == 0:
		_hud.flash("FIRST GEAR")
	else:
		_hud.flash("UPSHIFT" if up else "DOWNSHIFT")


func _update_shift_request(delta: float) -> void:
	if _pending_shift == 0:
		return
	if _dyno.active():
		_pending_shift = 0
		return
	_shift_time -= delta
	if _shift_time <= 0.0:
		_pending_shift = 0
		_hud.flash("SHIFT BLOCKED: GEARBOX LOADED")
		return
	var up := _pending_shift > 0
	var before := _sim.gear.gear
	var target := _shift_target
	if target < 0:
		target = 2 if up and before == 0 else (1 if not up and before == 0 else before + _pending_shift)
		if before == 1 and up and _sim.speed < 0.5:
			target = 0
		elif before == 2 and not up and _sim.speed < 0.5:
			target = 0
	if target < 0 or target > _sim.gear.gear_ratios.size() or target == before:
		_pending_shift = 0
		_hud.flash("TOP GEAR" if up else "BOTTOM GEAR")
		return
	# Quickshifter: shift with the clutch engaged and under load. Upshifts cut the ignition; downshifts rely on the blip.
	if spec.quickshifter and before > 0 and target > 0:
		var qs_ratio: float = spec.primary_ratio * float(_sim.gear.gear_ratios[target - 1]) * spec.final_drive
		var qs_rpm := _sim.speed / EngineSim.tire_radius_m(spec) * qs_ratio * 60.0 / TAU
		var quick_up := up and _throttle > 0.5 and _sim.rpm >= spec.quickshifter_min_rpm
		# A quickshift is clutch-less by definition. With the clutch pulled in the rider is shifting by hand,
		# and the gear still drops through the ordinary path below, without a cut or a blip.
		var quick_down := not up and target < before and qs_rpm <= spec.redline_rpm * 1.03 and _sim.clutch_engage > 0.1
		if quick_up or quick_down:
			_sim.gear.gear = target
			_pending_shift = 0
			if quick_up:
				_sim.ecu.trigger_quickshifter(spec)
			else:
				_sim.ecu.trigger_quickshifter_downshift(spec)
			_hud.flash("QUICKSHIFT UP" if quick_up else "QUICKSHIFT DOWN")
			return
	var clutch_open := _sim.clutch_engage <= 0.1
	var unloaded := absf(_sim.gearbox_load) <= maxf(0.5, _sim.clutch_capacity(spec) * 0.08)
	var speed_matched := true
	if target > 0 and (before == 0 or target < before):
		var target_ratio: float = spec.primary_ratio * float(_sim.gear.gear_ratios[target - 1]) * spec.final_drive
		var target_rpm := _sim.speed / EngineSim.tire_radius_m(spec) * target_ratio * 60.0 / TAU
		speed_matched = absf(_sim.rpm - target_rpm) <= SHIFT_MATCH_RPM
	var throttle_unloaded := _throttle <= 0.12 or not up
	if not clutch_open and not up and before > 0 and target > 0 and unloaded and not speed_matched:
		_shift_target = target
		_sim.gear.gear = 0
		_hud.flash("MATCH RPM")
		return
	if not clutch_open and not (unloaded and speed_matched and throttle_unloaded):
		return
	_sim.gear.gear = target
	_pending_shift = 0
	# Quickshifter: trigger ignition/fuel cut for clutchless upshift
	if up and spec.quickshifter and _sim.rpm >= spec.quickshifter_min_rpm and _throttle > 0.5:
		_sim.ecu.trigger_quickshifter(spec)
	# A clutch-less drop into a lower gear blips the throttle, the way a quickshifter does. With the clutch
	# pulled in the rider owns the revs, so the engine is left alone, and neutral into first drops no gear.
	if not up and spec.quickshifter and before > 0 and target > 0 and target < before and not clutch_open:
		_sim.ecu.trigger_quickshifter_downshift(spec)
	if target == 0:
		_hud.flash("NEUTRAL")
	elif before == 0:
		_hud.flash("FIRST GEAR")
	else:
		_hud.flash("UPSHIFT" if up else "DOWNSHIFT")


# Phones only: after BACKGROUND_LIMIT_MS in the background the app closes. Android can freeze a backgrounded app, so the time
# is also checked when it comes back, and the app closes then if the limit has passed.
func _notification(what: int) -> void:
	if not OS.has_feature("mobile"):
		return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _background_since < 0:
			_background_since = Time.get_ticks_msec()
			get_tree().create_timer(BACKGROUND_LIMIT_MS / 1000.0).timeout.connect(_close_if_still_background)
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_close_if_still_background()
		_background_since = -1


func _close_if_still_background() -> void:
	if _background_since >= 0 and Time.get_ticks_msec() - _background_since >= BACKGROUND_LIMIT_MS:
		get_tree().quit()


# The dyno cell controls: the drum on or off, and how hard its brake loads the engine
func _build_cell_panel() -> void:
	var panel := PanelContainer.new()
	_stats.add_controls(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "DYNO CELL"
	box.add_child(title)
	var drum := CheckButton.new()
	drum.text = "Drum on"
	drum.toggled.connect(_set_cell)
	box.add_child(drum)
	var load_label := Label.new()
	box.add_child(load_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.value = _cell_load * 100.0
	slider.custom_minimum_size = Vector2(0, 40)
	box.add_child(slider)
	var show_load := func(percent: float) -> void:
		load_label.text = "Brake load %d%%" % int(percent)
	show_load.call(slider.value)
	slider.value_changed.connect(func(percent: float) -> void:
		_cell_load = percent / 100.0
		show_load.call(percent)
		_apply_cell())
	var run := Button.new()
	run.text = "Run dyno sweep"
	run.focus_mode = Control.FOCUS_NONE
	run.custom_minimum_size = Vector2(0, 44)
	run.pressed.connect(_on_dyno_pressed)
	box.add_child(run)
	_cell_status = Label.new()
	_cell_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_cell_status)


func _set_cell(on: bool) -> void:
	_cell_on = on
	_apply_cell()


# Builds the rollers and fan under the bike's wheels. Called each time a bike is built, since the wheels move with the frame.
func _build_cell_equipment() -> void:
	if _cell != null:
		_cell.queue_free()
	_cell = DYNO_CELL_SCRIPT.new()
	add_child(_cell)
	var rear_z := _drivetrain.rear_axle.z
	# The shared stats panel already displays the sensor values.
	_cell.build(Ground.Y, rear_z, _drivetrain.front_axle.z, false)
	_cell.set_drum(_cell_on)


# Per frame: rollers and fan follow the drum speed, and the readouts and run status update
func _update_cell(delta: float) -> void:
	if _cell == null or not _cell_on:
		return
	# the brake comes on once the engine is past launch speed, so the pull-away is unloaded like a real cell
	_sim.cell_load_n = CELL_MAX_LOAD_N * _cell_load if _sim.rpm > CELL_LOAD_RPM else 0.0
	_cell.update(delta, _sim.speed / EngineSim.tire_radius_m(spec) * 60.0 / TAU)
	_cell.show_readings(_sim, spec, _cell_load * 100.0)
	_cell_status.text = _dyno.status_text() if _dyno.active() else "Idle: press Run dyno sweep"


# Pushes the drum and brake settings into the sim; with the drum off the bike runs on the road as before
func _apply_cell() -> void:
	_sim.cell_mass_kg = DRUM_MASS_KG if _cell_on else 0.0
	_sim.cell_load_n = CELL_MAX_LOAD_N * _cell_load if _cell_on else 0.0
	if _cell != null:
		_cell.set_drum(_cell_on)


# The dyno test button: starts the automatic test, or stops it when it is already running.
func _on_dyno_pressed() -> void:
	if _dyno.active():
		_dyno.cancel()
		return
	if not _ignition:
		_hud.flash("KILL SWITCH IS ON: SET IT TO RUN FOR THE DYNO TEST")
		return
	_pending_shift = 0
	var selected_preset: int = _panel._preset_button.selected
	_dyno.reference_id = str(_panel._preset_ids[selected_preset]) if selected_preset >= 0 else ""
	_dyno.start(spec, _sim)
	_dyno_view.open()
	_dyno_view.refresh(_dyno)


# Renders the exhaust sound to a WAV file offline at the highest simulation refresh
# (physics_dt = 1/3600), ignoring real-time frame caps. The render uses the current
# engine spec and exhaust layout, so the exported sound matches the live engine.
func _on_render_pressed() -> void:
	if not _ignition:
		_hud.flash("KILL SWITCH IS ON: SET IT TO RUN FOR THE RENDER")
		return
	# Rebuild the current layout now, so the render uses the same pipes as the live engine when the file is chosen
	_pending_render_layout = ExhaustLayout.build(spec, _model.exhaust_ports(), _model.crank_position(), Ground.Y, _car.rear_axle if spec.vehicle_type == "car" else _drivetrain.rear_axle)
	_build_render_settings()
	_render_settings.popup_centered()


# The render settings: length, throttle and bit depth. The sample rate is fixed at 44.1 kHz (the renderer supports only that).
func _build_render_settings() -> void:
	if _render_settings != null:
		return
	_render_settings = ConfirmationDialog.new()
	_render_settings.title = "Render settings"
	_render_settings.ok_button_text = "Next: choose file"
	var box := VBoxContainer.new()
	_render_settings.add_child(box)
	_render_duration_box = SpinBox.new()
	_render_duration_box.min_value = 1
	_render_duration_box.max_value = 60
	_render_duration_box.step = 1
	_render_duration_box.value = 10
	_render_duration_box.suffix = " s"
	box.add_child(_render_row("Length", _render_duration_box))
	_render_throttle_box = OptionButton.new()
	_render_throttle_box.add_item("Idle (closed throttle)")
	_render_throttle_box.add_item("Half throttle")
	_render_throttle_box.add_item("Wide open")
	_render_throttle_box.select(2)
	box.add_child(_render_row("Throttle", _render_throttle_box))
	_render_bits_box = OptionButton.new()
	_render_bits_box.add_item("16-bit")
	_render_bits_box.add_item("24-bit")
	_render_bits_box.add_item("32-bit float")
	_render_bits_box.select(0)
	box.add_child(_render_row("Bit depth", _render_bits_box))
	_render_settings.confirmed.connect(_open_render_file_dialog)
	add_child(_render_settings)


func _render_row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


# The Save As window, opened after the settings are confirmed.
func _open_render_file_dialog() -> void:
	if _render_dialog == null:
		_render_dialog = FileDialog.new()
		_render_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_render_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_render_dialog.use_native_dialog = true # the operating system's own Save As window
		_render_dialog.title = "Save engine render"
		_render_dialog.add_filter("*.wav", "WAV audio")
		_render_dialog.file_selected.connect(_on_render_file_chosen)
		add_child(_render_dialog)
	_render_dialog.current_dir = _render_folder if _render_folder != "" else OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	_render_dialog.current_file = "engine_render.wav"
	_render_dialog.popup_centered_ratio(0.6)


# The file is chosen: start the render with the settings, and show its progress.
func _on_render_file_chosen(path: String) -> void:
	_render_folder = path.get_base_dir()
	if not path.to_lower().ends_with(".wav"):
		path += ".wav"
	var throttle: float = [0.0, 0.5, 1.0][_render_throttle_box.selected]
	var bit_depth: int = [16, 24, 32][_render_bits_box.selected]
	_show_render_progress(true)
	_audio_renderer.render(spec, _pending_render_layout, _render_duration_box.value, 44100, bit_depth, throttle, "", path)


# A small window with a progress bar, shown while the render runs and hidden when it finishes or fails.
func _show_render_progress(on: bool) -> void:
	if _render_progress_popup == null:
		_render_progress_popup = PopupPanel.new()
		var box := VBoxContainer.new()
		_render_progress_popup.add_child(box)
		_render_progress_label = Label.new()
		_render_progress_label.text = "Rendering engine sound..."
		box.add_child(_render_progress_label)
		_render_progress_bar = ProgressBar.new()
		_render_progress_bar.min_value = 0.0
		_render_progress_bar.max_value = 100.0
		_render_progress_bar.custom_minimum_size = Vector2(360, 24)
		box.add_child(_render_progress_bar)
		add_child(_render_progress_popup)
	if on:
		_render_progress_bar.value = 0.0
		_render_progress_popup.popup_centered()
	else:
		_render_progress_popup.hide()


func _on_render_progress(progress: float) -> void:
	if _render_progress_bar != null:
		_render_progress_bar.value = progress * 100.0
		_render_progress_label.text = "Rendering engine sound... %d%%" % [int(progress * 100.0)]


func _set_setup_open(open: bool) -> void:
	_panel.visible = open
	_touch.set_panel_open(open)


func _set_paused(on: bool) -> void:
	_paused = on
	_sound.stream_paused = on or not _sound_on
	_pause.visible = on
	if on: # a finger or key held when the game pauses must not keep driving the engine
		_touch_throttle = 0.0
		_touch_clutch = 0.0
		_touch_brake = false
		_touch_starter = false


# High: 4x anti-aliasing and shadows. Low: neither, for slower machines.
func _on_accuracy_changed(index: int) -> void:
	_sim.physics_dt = 1.0 / PauseMenu.PHYSICS_RATES[index]


func _on_quality_changed(index: int) -> void:
	get_viewport().msaa_3d = Viewport.MSAA_4X if index == 1 else Viewport.MSAA_DISABLED
	_light.shadow_enabled = index == 1


func _on_camera_requested(view: String) -> void:
	_orbit.yaw = -PI / 2.0
	_orbit.pitch = 0.133
	if view == "Engine":
		_orbit.target = _model.crank_position()
		_orbit.distance = maxf(3.5, _model._span * 2.0 + 2.0)
	elif _car_mode:
		_orbit.target = Vector3(0.0, 2.0, (_car.front_axle.z + _car.rear_axle.z) * 0.5)
		_orbit.distance = 36.0
	else:
		_orbit.target = Vector3(0.0, 1.0, -2.0)
		_orbit.distance = 11.0


func _on_sound_toggled(on: bool) -> void:
	_sound_on = on
	_sim.audio_enabled = on
	if on and _sim._audio_layout != null:
		_sim.set_audio_layout(_sim._audio_layout, spec.cylinders)
	_sound.audio_enabled = on
	_sound.stream_paused = _paused or not on


# Rebuilds the engine and its neighbours after any setting changes.
func _on_panel_changed() -> void:
	_panel.apply_to(spec)
	_sound.apply_levels(spec)
	_sim.exhaust_solver = spec.live_exhaust_physics
	_shift_sensor.upshift_threshold = spec.quickshifter_sensitivity
	_shift_sensor.downshift_threshold = spec.quickshifter_sensitivity
	_sim.fuel.set_capacity(spec.fuel_capacity_l)
	_sim.fuel.set_kind(spec.fuel)
	_sim.gear.gear_ratios = spec.gear_ratios
	_sim.gear.gear = mini(_sim.gear.gear, spec.gear_ratios.size())
	var problem := spec.validation_problem()
	_panel.set_warning(String(problem.get("text", "")), String(problem.get("key", "")))
	_rebuild_dirty = true
	_rebuild_timer.start() # restarting collapses a burst of changes into one rebuild


# Anything that must not wait for the timer: startup, and a test that wants the geometry now.
func flush_rebuild() -> void:
	if not _rebuild_dirty:
		return
	_rebuild_timer.stop()
	_rebuild_scene()


func _rebuild_scene() -> void:
	if not _rebuild_dirty:
		return
	_rebuild_dirty = false
	rebuilds_done += 1
	_model.build(spec)
	var selected_id := ""
	var selected_index := _panel._preset_button.selected
	if selected_index >= 0 and selected_index < _panel._preset_ids.size():
		selected_id = str(_panel._preset_ids[selected_index]).validate_filename()
	var is_car := spec.vehicle_type == "car"
	_drivetrain.visible = not is_car
	_clutch.visible = not is_car
	_spl_rig.visible = not is_car # the meter reads a tailpipe, and a car has none
	_gearbox.visible = not is_car
	_tank.visible = not is_car
	_fuel_line.visible = not is_car
	_car.visible = is_car
	if is_car:
		_car.build(spec, Ground.Y)
	else:
		var tank_scene: PackedScene = null
		if not selected_id.is_empty():
			var asset_path := "res://assets/models/%s/tank.glb" % selected_id
			if ResourceLoader.exists(asset_path, "PackedScene"):
				tank_scene = load(asset_path) as PackedScene
		_tank.set_shell_scene(tank_scene)
		_tank.set_capacity(spec.fuel_capacity_l)
		_tank.place(_model.highest_y() + 0.4, (_model.crank_position().z + _model.throttle_position().z) * 0.5)
		var engine_bounds := _model.chassis_envelope()
		var frame_half_width := maxf(0.85, maxf(absf(engine_bounds.position.x), absf(engine_bounds.end.x)) + 0.25)
		_drivetrain.build(Ground.Y, GearboxModel.countershaft_position(_model.crank_position(), spec), _tank.outlet_position(), frame_half_width, spec.abs_hardware(), engine_bounds, spec, selected_id)
		_build_cell_equipment()
		if spec.v3r_style:
			_drivetrain.add_v3r_bodywork(_tank.outlet_position())
		_clutch.build(_model.crank_position(), spec, _model.primary_gear_x())
		_gearbox.build(_model.crank_position(), spec, _model.primary_gear_x())
		_fuel_line.build(_tank.outlet_position(), _model.fuel_feed_positions(), spec.induction)
	if is_car != _car_mode:
		if is_car:
			_bike_camera_target = _orbit.target
			_bike_camera_distance = _orbit.distance
			_orbit.target = Vector3(0.0, 2.0, (_car.front_axle.z + _car.rear_axle.z) * 0.5)
			_orbit.distance = 36.0
		else:
			_orbit.target = _bike_camera_target
			_orbit.distance = _bike_camera_distance
		_car_mode = is_car
	# only sound inputs reset the stream, so bore/stroke tweaks don't cut the sound
	var layout := ExhaustLayout.build(spec, _model.exhaust_ports(), _model.crank_position(), Ground.Y, _car.rear_axle if is_car else _drivetrain.rear_axle)
	var muffler_scene: PackedScene = null
	if not selected_id.is_empty():
		var muffler_path := "res://assets/models/%s/muffler_%s.glb" % [selected_id, spec.muffler_style.validate_filename()]
		if ResourceLoader.exists(muffler_path, "PackedScene"):
			muffler_scene = load(muffler_path) as PackedScene
	_exhaust.build(layout, muffler_scene)
	_tail_tip = _tailpipe_tip(layout)
	# the pipes set the sound, so a layout change of more than a couple of centimetres rebuilds it
	var path_key := []
	for pipe in layout.pipes:
		path_key.append([pipe.kind, pipe.cyl, pipe.feeders, roundi(pipe.length_m() * 1000.0), pipe.loss])
	var audio_key := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [spec.cylinders, spec.displacement_cc, spec.header, spec.fuel, spec.twin_pin_deg, spec.crossplane, str(FiringOrders.for_spec(spec)), spec.intake_centre_deg, spec.exhaust_centre_deg, spec.exhaust_duration_deg, spec.ignition_offset_deg, str(path_key)]
	if audio_key != _audio_key:
		_audio_key = audio_key
		_sim.set_audio_layout(layout, spec.cylinders)
		_sound.setup(spec, layout) # stops the player, so start it again below
		_sound.play()
		_sound.stream_paused = _paused or not _sound_on


var _audio_key := ""
var _tail_tip := Vector3.ZERO
var _tail_dir := Vector3.FORWARD # direction the gas leaves the tailpipe: the axis the SPL meter stands 45 degrees off


func _tailpipe_tip(layout: ExhaustLayout) -> Vector3:
	for i in range(layout.pipes.size() - 1, -1, -1):
		var pipe = layout.pipes[i]
		if pipe.kind == "tail" and not pipe.pts.is_empty():
			var n: int = pipe.pts.size()
			if n >= 2:
				_tail_dir = (pipe.pts[n - 1] - pipe.pts[n - 2]).normalized()
			return pipe.pts[n - 1]
	return Vector3.ZERO


# Debug trace: prints the step and time, so a freeze shows the last step reached in the Output panel.
func _trace(step: String) -> void:
	print("[trace %8.3fs] %s" % [Time.get_ticks_msec() / 1000.0, step])


# --- trigger diagnostics -------------------------------------------------------------------------------------------
# A trigger that jumps from shut to wide open is one of three things: a digital (on/off) axis, an axis being read wrong,
# or the pad's own firmware. When the pad throttle moves more than JUMP_ALERT in a single frame, the last PAD_HISTORY
# frames are written to user://throttle_jump.txt, so the numbers behind the jump can be read instead of guessed at.
const PAD_HISTORY := 90
const JUMP_ALERT := 0.4
var _pad_hist: Array = []
var _jump_dumped := false


func _record_pad_frame(pad: int, pad_throttle: float) -> void:
	var axes := PackedFloat32Array()
	axes.resize(4)
	for i in 4:
		axes[i] = Gamepad.raw_axis(pad, 4 + i)
	_pad_hist.append({"t": Time.get_ticks_msec(), "axes": axes, "pt": pad_throttle, "th": _throttle})
	if _pad_hist.size() > PAD_HISTORY:
		_pad_hist.pop_front()
	if _jump_dumped or _pad_hist.size() < 3:
		return
	var before: float = _pad_hist[_pad_hist.size() - 2]["pt"]
	if absf(pad_throttle - before) < JUMP_ALERT:
		return
	_jump_dumped = true
	_dump_pad_history(before, pad_throttle)


func _dump_pad_history(before: float, now: float) -> void:
	var path := ProjectSettings.globalize_path("user://throttle_jump.txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("Engine Builder - pad throttle jump")
	f.store_line("axes are the four trigger-capable axes; pt = Gamepad.throttle, th = what the sim was given")
	f.store_line("jump %.3f -> %.3f   throttle axis %d   clutch axis %d" % [before, now, Gamepad.throttle_axis, Gamepad.clutch_axis])
	f.store_line("")
	for row in _pad_hist:
		var a: PackedFloat32Array = row["axes"]
		f.store_line("t=%6d  ax4=%.3f ax5=%.3f ax6=%.3f ax7=%.3f  pt=%.3f  th=%.3f" % [
			row["t"], a[0], a[1], a[2], a[3], row["pt"], row["th"]])
	f.close()
	_hud.flash("THROTTLE JUMP LOGGED (throttle_jump.txt)")
	print("throttle jump logged to ", path)