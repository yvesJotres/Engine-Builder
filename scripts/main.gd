extends Node3D

# Coordinator: builds the scene, runs the physics each frame, and routes input and changes
# between the parts. Physics lives in EngineSim; the drawing in EngineModel and friends;
# the screen in scripts/ui; the floor in scripts/world.

const THROTTLE_SPEED := 1.5 # full travel per second while held open
const THROTTLE_RETURN_SPEED := 3.0 # full travel per second when released, like a return spring

var spec := EngineSpec.new()
var _sim := EngineSim.new()
var _blur: MotionBlur
var _sound: EngineSound
var _light: DirectionalLight3D
var _orbit: OrbitCamera
var _model: EngineModel
var _drivetrain: Drivetrain
var _clutch: Clutch
var _gearbox: GearboxModel
var _tank: FuelTankModel
var _fuel_line: FuelLine
var _exhaust: Exhaust
var _panel: ControlPanel
var _hud: Hud
var _pause: PauseMenu
var _paused := false
var _frame := 0 # debug trace: frames since start
var _crank := 0.0 # crank angle for the drawing, 0..720
var _throttle := 0.0
var _ignition := true # the engine kill switch is on RUN; the panel flips it
var _clutch_held := false # Shift is held: clutch pulled in
var _brake_held := false # B is held
var _sound_on := true # the Sound option in the pause menu
var _touch: TouchControls
var _touch_throttle := 0.0 # the on-screen throttle lever, 0 = closed, 1 = wide open
var _touch_clutch := 0.0 # the on-screen clutch lever, 0 = engaged, 1 = pulled in
var _touch_brake := false
var _touch_starter := false
var _sound_gate := 0.0 # 0 = exhaust silent, 1 = exhaust full, fades between
const SOUND_FADE_TIME := 0.05 # s, fade in and out of the exhaust note
var _backfires_heard := 0 # the sim's backfire count the sound has already played


func _ready() -> void:
	_trace("ready start")
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

	_orbit = OrbitCamera.new()
	add_child(_orbit)
	add_child(Ground.new())

	_model = EngineModel.new()
	add_child(_model)
	_drivetrain = Drivetrain.new()
	add_child(_drivetrain)
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
	_sound = EngineSound.new()
	add_child(_sound)

	_panel = ControlPanel.new()
	add_child(_panel)
	_panel.changed.connect(_on_panel_changed)
	_panel.refuel_pressed.connect(func() -> void:
		_sim.fuel.refill()
		_hud.flash("TANK FILLED"))
	_panel.kill_switch_changed.connect(func(killed: bool) -> void: _ignition = not killed)

	_hud = Hud.new()
	add_child(_hud)

	_pause = preload("res://scenes/pause_menu.tscn").instantiate()
	add_child(_pause)
	_pause.resume_requested.connect(func() -> void: _set_paused(false))
	_pause.quality_changed.connect(_on_quality_changed)
	_on_quality_changed(0 if OS.has_feature("mobile") else 1) # High on a PC, Low on a phone
	_pause.accuracy_changed.connect(_on_accuracy_changed)
	_blur = MotionBlur.new()
	add_child(_blur)
	_blur.setup(get_viewport(), _orbit.camera)
	_pause.blur_toggled.connect(_blur.set_enabled) # off by default
	_pause.sound_toggled.connect(_on_sound_toggled) # the sound switch lives in Options only
	_on_accuracy_changed(2) # 3,600 steps a second, the default on every device
	_touch = TouchControls.new()
	add_child(_touch)
	_touch.throttle_changed.connect(func(amount: float) -> void: _touch_throttle = amount)
	_touch.clutch_changed.connect(func(amount: float) -> void: _touch_clutch = amount)
	_touch.brake_changed.connect(func(on: bool) -> void: _touch_brake = on)
	_touch.starter_changed.connect(func(on: bool) -> void: _touch_starter = on)
	_touch.shift_pressed.connect(_shift)
	_touch.pause_pressed.connect(func() -> void: _set_paused(not _paused))
	_trace("scene built")

	_on_panel_changed()
	_trace("ready done")


func _unhandled_input(event: InputEvent) -> void:
	# a click on the 3D view takes focus away from any box in the panel, so W and S drive the throttle again
	if event is InputEventMouseButton and event.pressed:
		get_viewport().gui_release_focus()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ESCAPE:
			_set_paused(not _paused)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_K:
			_panel.toggle_kill()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E or event.keycode == KEY_Q:
			_shift(event.keycode == KEY_E)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F11:
			var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
			_pause.set_fullscreen_checked(not fullscreen)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_frame += 1
	if _frame <= 120 or _frame % 120 == 0:
		_trace("frame %d" % _frame)
	var open_keys := Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
	var close_keys := Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
	# spring-return throttle: holding W/Up opens it, letting go springs it back to closed
	if open_keys:
		_throttle = minf(_throttle + THROTTLE_SPEED * delta, 1.0)
	elif close_keys:
		_throttle = maxf(_throttle - THROTTLE_SPEED * delta, 0.0)
	else:
		_throttle = move_toward(_throttle, 0.0, THROTTLE_RETURN_SPEED * delta)

	# the throttle lever sets the opening directly, and springs back to closed through the return above when let go
	if _touch_throttle > 0.0:
		_throttle = _touch_throttle
	# a pulled clutch lever slips the clutch by its amount; past half way it counts as pulled in for the interlocks
	_sim.clutch_pull = _touch_clutch
	_clutch_held = Input.is_physical_key_pressed(KEY_SHIFT) or _touch_clutch > 0.5
	_brake_held = Input.is_physical_key_pressed(KEY_B) or _touch_brake

	if not _paused:
		# W cranks the engine while it is stopped, same as the starter button
		# the starter only turns the engine in neutral or with the clutch pulled in, as the interlock on a modern bike
		var wants_start := _touch_starter or (open_keys and not _sim.running)
		var in_neutral_or_pulled := _sim.gear.gear == 0 or _clutch_held
		if wants_start and not in_neutral_or_pulled:
			_hud.flash("PULL CLUTCH OR SHIFT TO NEUTRAL TO START")
		if wants_start and not _ignition:
			_hud.flash("KILL SWITCH IS ON: SET IT TO RUN TO START")
		# only the Shift key pulls the clutch fully apart; the lever's own pull sets the friction zone through clutch_pull
		_sim.step(delta, spec, _throttle, _ignition, wants_start and in_neutral_or_pulled, Input.is_physical_key_pressed(KEY_SHIFT), _brake_held, _panel.lambda())
		if _frame <= 3: _trace("sim stepped")
		_crank = fmod(_crank + _sim.rpm * 6.0 * delta, 720.0)
		_drivetrain.update(_crank, _sim.speed / EngineSim.tire_radius_m() * 60.0 / TAU, delta)
		if _frame <= 3: _trace("drivetrain updated")
	_model.set_throttle(_throttle)
	_model.update_crank(_crank)
	if _frame <= 3: _trace("engine model updated")
	_clutch.update(-_crank / spec.primary_ratio, _sim.clutch_engage) # basket turns at primary-reduced speed, with the crank
	_tank.update(_sim.fuel.fraction(), Color(0.2, 0.55, 0.3) if _sim.fuel.kind == "e85" else Color(0.2, 0.4, 0.9))
	if _frame <= 3: _trace("clutch and tank updated")
	# the exhaust only pops once the engine is firing on its own
	# the exhaust fades out while the limiter cuts the spark and back in afterwards, instead of cutting hard
	_sound.rpm = _sim.rpm
	var gate_target := 1.0 if _sim.running else 0.0
	_sound_gate = move_toward(_sound_gate, gate_target, delta / SOUND_FADE_TIME)
	_sound.firing = _sim.running and not _sim.limiter_active
	# exhaust energy follows the fuel burned: fuel flow as a share of the most the engine could burn
	# at its redline (full air charge, stoichiometric mixture, atmospheric density)
	var max_air_kg_s := Units.AIR_DENSITY * spec.displacement_cc * 1e-6 * (spec.redline_rpm / 120.0)
	var afr: float = FuelTank.PROPERTIES[_sim.fuel.kind].afr
	var max_fuel_g_s: float = max_air_kg_s / afr * 1000.0
	# sound pressure grows with the square root of acoustic power, and power follows the fuel burned
	# floor at 0.02 ratio (~14% energy) so idle isn't disproportionately quiet
	_sound.energy = sqrt(maxf(_sim.fuel_flow / max_fuel_g_s, 0.02))
	_sound.knock = clampf(_sim.knock_excess / 5.0, 0.0, 1.0) # the detonation ping grows with how far past the knock limit the advance is
	_sound.volume_db = (0.0 if _sound_on else -80.0) + linear_to_db(maxf(_sound_gate, 0.0001))
	# each backfire pops the exhaust once, and flashes on the dashboard
	if _sim.backfire_count != _backfires_heard:
		_backfires_heard = _sim.backfire_count
		_sound.backfire(_sim.last_backfire_j)
		_hud.flash("BACKFIRE")

	var clutch_state := "open" if _sim.clutch_engage < 0.01 else ("engaged" if _sim.clutch_engage > 0.99 else "slipping")
	var state := "RUNNING" if _sim.running else ("CRANKING" if _sim.rpm > 0.0 else "STOPPED")
	var power_hp := Units.w_to_hp(Units.power_w(_sim.torque, _sim.rpm))
	_panel.set_throttle_text("Engine: %s  RPM: %d\nTorque %.1f N·m   Power %.1f hp\nIntake %.1f psi   Air %.0f °C\nThrottle: %d%%  (hold W/Up, springs back)   Clutch: %s (%d%% grip)\nFuel: %.1f kg (%d%%)  flow %.2f g/s  λ %.2f\nSound: %s (%s)\nTiming %+.1f°   Intake %d° at %.1f mm   Exhaust %d° at %.1f mm   Knocks %d" % [
		state, roundi(_sim.rpm), _sim.torque, power_hp,
		Units.pa_to_psi(_sim.intake.pressure), Units.k_to_c(EngineAir.T0),
		roundi(_throttle * 100), clutch_state, roundi(_sim.clutch_engage * 100.0), _sim.fuel.mass_kg, roundi(_sim.fuel.fraction() * 100), _sim.fuel_flow, _panel.lambda(),
		"on" if _sound_on else "muted", "starved" if _sound.starved else ("playing" if _sound.playing else "no output"),
		spec.ignition_offset_deg, roundi(spec.intake_duration_deg), spec.intake_lift_mm, roundi(spec.exhaust_duration_deg), spec.exhaust_lift_mm, _sim.knock_count])
	# the sensors: chamber temperature (hottest gas each cylinder reached last cycle), exhaust port temperature per header runner, O2
	var hottest := 0.0
	for c in _sim.cylinders:
		hottest = maxf(hottest, c.last_peak_temp - 273.15)
	var headers := ""
	for t in _sim.port_temps_c():
		headers += "%.0f  " % t
	_panel.set_sensor_text("Chamber: avg %.0f °C, hottest %.0f °C\nExhaust port (header), °C: %sO2 sensor λ %.2f  (exhaust %.0f °C)" % [_sim.chamber_peak_c(), hottest, headers, _sim.o2_lambda(), _sim.exhaust_temp_c()])
	if _frame <= 3: _trace("sound settings done")
	_hud.update(_sim, spec, _clutch_held)
	if _frame <= 3: _trace("hud updated")


# E shifts up, Q shifts down, both only with the clutch pulled. The dashboard says what happened.
func _shift(up: bool) -> void:
	# no gate: a rider can click through several gears on one pull, or shift without the clutch. Shifting under load with the
	# clutch in is smooth; without it the clutch slips (capped torque) while engine and wheel speeds catch up, as on a real bike.
	var before := _sim.gear.gear
	if up:
		_sim.gear.shift_up()
	else:
		_sim.gear.shift_down()
	if _sim.gear.gear == before:
		_hud.flash("TOP GEAR" if up else "BOTTOM GEAR")
	elif _sim.gear.gear == 0:
		_hud.flash("NEUTRAL")
	else:
		_hud.flash("UPSHIFT" if up else "DOWNSHIFT")


func _set_paused(on: bool) -> void:
	_paused = on
	_sound.stream_paused = on
	_pause.visible = on


# High: 4x anti-aliasing and shadows. Low: neither, for slower machines.
func _on_accuracy_changed(index: int) -> void:
	_sim.physics_dt = 1.0 / PauseMenu.PHYSICS_RATES[index]


func _on_quality_changed(index: int) -> void:
	get_viewport().msaa_3d = Viewport.MSAA_4X if index == 1 else Viewport.MSAA_DISABLED
	_light.shadow_enabled = index == 1


func _on_sound_toggled(on: bool) -> void:
	_sound_on = on


# Rebuilds the engine and its neighbours after any setting changes.
func _on_panel_changed() -> void:
	_panel.apply_to(spec)
	_sim.fuel.set_kind(spec.fuel)
	_model.build(spec)
	# the front sprocket sits on the gearbox countershaft, not the crank
	_drivetrain.build(Ground.Y, GearboxModel.countershaft_position(_model.crank_position(), spec))
	_clutch.build(_model.crank_position(), spec, _model.primary_gear_x())
	_gearbox.build(_model.crank_position(), spec, _model.primary_gear_x())
	# the tank sits over the engine and its throttle body, clear of the plugs
	_tank.place(_model.highest_y() + 0.4, (_model.crank_position().z + _model.throttle_position().z) * 0.5)
	_fuel_line.build(_tank.outlet_position(), _model.injector_position())
	# only sound inputs reset the stream, so bore/stroke tweaks don't cut the sound
	var layout := ExhaustLayout.build(spec, _model.exhaust_ports(), _model.crank_position(), Ground.Y, _drivetrain.rear_axle)
	_exhaust.build(layout)
	# the pipes set the sound, so a layout change of more than a couple of centimetres rebuilds it
	var audio_key := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%d" % [spec.cylinders, spec.displacement_cc, spec.header, spec.fuel, spec.twin_pin_deg, spec.crossplane, str(spec.fire_deg), spec.intake_centre_deg, spec.exhaust_centre_deg, spec.exhaust_duration_deg, spec.ignition_offset_deg, roundi(layout.total_length_m() * 50.0)]
	if audio_key != _audio_key:
		_audio_key = audio_key
		_sound.setup(spec, layout) # stops the player, so start it again below
		_sound.play()
		_sound.stream_paused = _paused
	_panel.set_warning(spec.validation_warning())


var _audio_key := ""


# Debug trace: prints the step and time, so a freeze shows the last step reached in the Output panel.
func _trace(step: String) -> void:
	print("[trace %8.3fs] %s" % [Time.get_ticks_msec() / 1000.0, step])
