extends Node3D

# Coordinator: builds the scene, runs the physics each frame, and routes input and changes
# between the parts. Physics lives in EngineSim; the drawing in EngineModel and friends;
# the screen in scripts/ui; the floor in scripts/world.

const THROTTLE_SPEED := 1.5 # full travel per second while held open
const CAR_MODEL := preload("res://scripts/drivetrain/car_model.gd")
const DYNO_TEST_SCRIPT := preload("res://scripts/dyno/dyno_test.gd")
const DYNO_VIEW_SCRIPT := preload("res://scripts/dyno/dyno_view.gd")
const DYNO_CELL_SCRIPT := preload("res://scripts/dyno/dyno_cell.gd")
const AUDIO_RENDERER_SCRIPT := preload("res://scripts/render/audio_renderer.gd")
const ENGINE_STATS_SCRIPT := preload("res://scripts/ui/engine_stats.gd")
const SHIFT_SENSOR := preload("res://scripts/ignition/shift_sensor.gd")
const THROTTLE_RETURN_SPEED := 3.0 # full travel per second when released, like a return spring
const SHIFT_PRELOAD_TIME := 0.8
const SHIFT_MATCH_RPM := 300.0

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
var _background_since := -1
var _clutch_held := false # Shift is held: clutch pulled in
var _brake_held := false # B is held
var _sound_on := true # the Sound option in the pause menu
var _touch: TouchControls
var _touch_throttle := 0.0 # the on-screen throttle lever, 0 = closed, 1 = wide open
var _touch_clutch := 0.0 # the on-screen clutch lever, 0 = engaged, 1 = pulled in
var _touch_brake := false
var _touch_starter := false
var _panel_starter := false
var _keyboard_starting := false
var _shift_sensor: ShiftSensor
var _sound_gate := 0.0 # 0 = exhaust silent, 1 = exhaust full, fades between
var _idle_audio_cleared := false
const SOUND_FADE_TIME := 0.05 # s, fade in and out of the exhaust note
var _backfires_heard := 0 # the sim's backfire count the sound has already played
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
var _pending_shift := 0
var _shift_time := 0.0
var _shift_target := -1


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
	_sound = EngineSound.new()
	add_child(_sound)

	_panel = ControlPanel.new()
	add_child(_panel)
	_panel.changed.connect(_on_panel_changed)
	_panel.refuel_pressed.connect(func() -> void:
		_sim.fuel.refill()
		_hud.flash("TANK FILLED"))
	_panel.kill_switch_changed.connect(func(killed: bool) -> void: _ignition = not killed)
	_panel.starter_changed.connect(func(held: bool) -> void: _panel_starter = held)
	_panel.camera_requested.connect(_on_camera_requested)
	_panel.dyno_pressed.connect(_on_dyno_pressed)
	_panel.render_pressed.connect(_on_render_pressed)
	_stats = ENGINE_STATS_SCRIPT.new()
	add_child(_stats)

	_audio_renderer = AUDIO_RENDERER_SCRIPT.new()
	add_child(_audio_renderer)
	_audio_renderer.render_completed.connect(func(path: String) -> void:
		_hud.flash("RENDER SAVED: %s" % [path.get_file()]))
	_audio_renderer.render_failed.connect(func(msg: String) -> void:
		_hud.flash("RENDER FAILED: %s" % [msg]))
	_audio_renderer.render_progress.connect(func(p: float) -> void:
		_hud.flash("RENDERING: %d%%" % [roundi(p * 100)]))

	_hud = Hud.new()
	add_child(_hud)
	_dyno_view = DYNO_VIEW_SCRIPT.new()
	add_child(_dyno_view)
	_dyno_view.stop_requested.connect(func() -> void: _dyno.cancel())
	_build_cell_panel()

	_pause = preload("res://scenes/pause_menu.tscn").instantiate()
	add_child(_pause)
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
	_trace("ready done")


func _unhandled_input(event: InputEvent) -> void:
	# a click on the 3D view takes focus away from any box in the panel, so W and S drive the throttle again
	if event is InputEventMouseButton and event.pressed:
		get_viewport().gui_release_focus()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ESCAPE:
			_set_paused(not _paused)
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


func _update_keyboard_starter(open_keys: bool) -> void:
	if not open_keys:
		_keyboard_starting = false
	elif not _sim.running:
		_keyboard_starting = true
	elif _keyboard_starting and _sim.rpm >= spec.idle_target_rpm:
		_keyboard_starting = false


func _process(delta: float) -> void:
	_frame += 1
	if _frame <= 120 or _frame % 120 == 0:
		_trace("frame %d" % _frame)
	# while paused no gameplay key counts
	var open_keys := not _paused and (Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	var close_keys := not _paused and (Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
	_update_keyboard_starter(open_keys)
	# spring-return throttle: holding W/Up opens it, letting go springs it back to closed
	if open_keys and not _keyboard_starting:
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
	if spec.transmission_type == "dual_clutch" and _sim.gear.gear > 0 and not _dyno.active():
		var engagement := clampf((_sim.rpm - spec.idle_target_rpm * 0.9) / maxf(spec.idle_target_rpm * 0.8, 1.0), 0.0, 1.0)
		_sim.clutch_pull = 0.9 - 0.4 * engagement if _sim.speed < 5.0 else 0.0
	_clutch_held = Input.is_physical_key_pressed(KEY_SHIFT) or _touch_clutch > 0.5
	_brake_held = Input.is_physical_key_pressed(KEY_B) or _touch_brake

	_sim.audio_enabled = _sound_on
	_sound.audio_enabled = _sound_on
	
	# Shift sensor: compute shift force from input
	var shift_force := 0.0
	if not _paused:
		if Input.is_physical_key_pressed(KEY_E):
			shift_force = 1.0
		elif Input.is_physical_key_pressed(KEY_Q):
			shift_force = -1.0
		# Touch controls would feed here too
	
	var shift_result = _shift_sensor.update(shift_force, delta)
	
	if shift_result == 1:
		_shift(true)
	elif shift_result == -1:
		_shift(false)
		# Trigger downshift blip
		_sim.ecu.trigger_quickshifter_downshift(spec)

	if _dyno.active() and not _paused:
		# the dyno test drives the throttle, clutch and gearbox itself, and steps the same engine physics
		_dyno.advance(delta, _sim, spec, _panel.lambda(), _ignition)
		_throttle = _dyno.throttle
		_clutch_held = _dyno.clutch_held
		_crank = fmod(_crank + _sim.rpm * 6.0 * delta, 720.0)
		_update_vehicle_wheels(delta)
	elif not _paused:
		# W cranks the engine while it is stopped, same as the starter button
		# the starter only turns the engine in neutral or with the clutch pulled in, as the interlock on a modern bike
		var wants_start := _touch_starter or _panel_starter or _keyboard_starting
		var in_neutral_or_pulled := _sim.gear.gear == 0 or _clutch_held
		if wants_start and not in_neutral_or_pulled:
			_hud.flash("PULL CLUTCH OR SHIFT TO NEUTRAL TO START")
		if wants_start and not _ignition:
			_hud.flash("KILL SWITCH IS ON: SET IT TO RUN TO START")
		# only the Shift key pulls the clutch fully apart; the lever's own pull sets the friction zone through clutch_pull
		# Get throttle override from ECU (quickshifter cut/blip)
		var ecu_throttle_override = _sim.ecu.update(delta, _sim.rpm, _throttle, _sim.running, spec, _sim.speed, _sim.clutch_pull, _sim.gear.gear)
		if ecu_throttle_override >= 0.0:
			_throttle = ecu_throttle_override
		
		_sim.step(delta, spec, _throttle, _ignition, wants_start and in_neutral_or_pulled, Input.is_physical_key_pressed(KEY_SHIFT), _brake_held, _panel.lambda())
		_update_shift_request(delta)
		if _frame <= 3: _trace("sim stepped")
		_crank = fmod(_crank + _sim.rpm * 6.0 * delta, 720.0)
		_update_vehicle_wheels(delta)
		if _frame <= 3: _trace("drivetrain updated")
	_model.set_throttle(_throttle)
	_model.update_crank(_crank)
	if _frame <= 3: _trace("engine model updated")
	_clutch.update(-_crank / spec.primary_ratio, _sim.clutch_engage) # basket turns at primary-reduced speed, with the crank
	_tank.update(_sim.fuel.fraction(), Color(0.2, 0.55, 0.3) if _sim.fuel.kind == "e85" else Color(0.2, 0.4, 0.9))
	if _frame <= 3: _trace("clutch and tank updated")
	_sound.rpm = _sim.rpm
	_sound.compressor_load = _sim.intake.compressor_load if spec.electric_compressor else 0.0
	_sound.position = _tail_tip
	if _sound_on:
		_sound.set_conditions(_sim.o2_lambda(), _sim.exhaust_temp_c(), _sim.backpressure_pa())
		if _sim.exhaust_solver and _sim.exhaust != null:
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
		if not _sim.exhaust_solver:
			_sound.backfire(_sim.last_backfire_j)

	var clutch_state := "open" if _sim.clutch_engage < 0.01 else ("engaged" if _sim.clutch_engage > 0.99 else "slipping")
	var state := "RUNNING" if _sim.running else ("CRANKING" if _sim.rpm > 0.0 else "STOPPED")
	var stopped := _sim.rpm < 1.0
	var torque := 0.0 if stopped else _sim.torque
	var power_hp := 0.0 if stopped else Units.w_to_hp(Units.power_w(_sim.torque, _sim.rpm))
	var bmep_bar := 0.0 if stopped else _sim.bmep_pa() / 1.0e5
	var imep_bar := 0.0 if stopped else _sim.imep_pa() / 1.0e5
	var ca50 := _sim.ca50_deg()
	var ca50_text := "—" if ca50 < 0.0 else "%.0f°" % ca50
	_stats.set_engine_data("%s  |  %d RPM\nInstant crank torque %.1f N·m\nInstant power %.1f hp\nBMEP %.1f bar   IMEP %.1f bar   ηm %.0f%%\nVE %.0f%%   BSFC %.0f g/kWh   ηb %.0f%%\nPmax %.0f bar   CA50 %s   10–90 %.0f°\nIntake %.1f psi   Air %.0f °C\nThrottle %d%%   Clutch %s (%d%%)\nFuel %.1f kg (%d%%)   %.2f g/s\nMixture target λ %.2f   Timing %+.1f°\nKnocks %d   Audio %s (%s)" % [
		state, roundi(_sim.rpm), torque, power_hp,
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
	if _panel._controls.has("compressor_map_view") and _sim.intake.compressor_map != null:
		var map_view = _panel._controls["compressor_map_view"]
		var corr_flow = _sim.intake.compressor_map.correct_flow(_sim.intake.pressure * _sim.intake.manifold_volume_scale / (EngineAir.R_AIR * EngineAir.T0), EngineAir.T0, EngineAir.P0)
		# Use engine mass flow as approximation
		var m_dot = 0.0
		for c in _sim.cylinders:
			m_dot += c.runner_q * (EngineAir.P0 / (EngineAir.R_AIR * EngineAir.T0))
		corr_flow = _sim.intake.compressor_map.correct_flow(m_dot, EngineAir.T0, EngineAir.P0)
		var corr_speed = _sim.intake.compressor_map.correct_speed(_sim.intake.compressor_speed_rpm, EngineAir.T0)
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
	_hud.update(_sim, spec, _clutch_held, _throttle)
	if _frame <= 3: _trace("hud updated")
	if _dyno_view.is_open():
		_dyno_view.refresh(_dyno)


func _shift(up: bool) -> void:
	if _dyno.active():
		_hud.flash("DYNO TEST IS RUNNING")
		return
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
		_drivetrain.update(_crank, wheel_rpm, delta)
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
	if target == 0:
		_hud.flash("NEUTRAL")
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
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -320.0
	panel.offset_right = -16.0
	panel.offset_top = 132.0
	layer.add_child(panel)
	var box := VBoxContainer.new()
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
	slider.custom_minimum_size.x = 260.0
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
	_cell.build(Ground.Y, rear_z, rear_z + Drivetrain.WHEELBASE)
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
	# Rebuild the current layout so the render uses the same pipes as the live engine
	var layout := ExhaustLayout.build(spec, _model.exhaust_ports(), _model.crank_position(), Ground.Y, _car.rear_axle if spec.vehicle_type == "car" else _drivetrain.rear_axle)
	_audio_renderer.render(spec, layout) # defaults: 10s, 44.1kHz, 16-bit, WOT


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
		_keyboard_starting = false


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
	_panel.set_build_summary(spec)
	_sim.fuel.set_capacity(spec.fuel_capacity_l)
	_sim.fuel.set_kind(spec.fuel)
	_sim.gear.gear_ratios = spec.gear_ratios
	_sim.gear.gear = mini(_sim.gear.gear, spec.gear_ratios.size())
	_model.build(spec)
	var is_car := spec.vehicle_type == "car"
	_drivetrain.visible = not is_car
	_clutch.visible = not is_car
	_gearbox.visible = not is_car
	_tank.visible = not is_car
	_fuel_line.visible = not is_car
	_car.visible = is_car
	if is_car:
		_car.build(spec, Ground.Y)
	else:
		_tank.place(_model.highest_y() + 0.4, (_model.crank_position().z + _model.throttle_position().z) * 0.5)
		var frame_half_width := maxf(0.85, _model._span * 0.5 + spec.bore_mm * Units.MM_TO_SCENE * 0.65 + 0.12)
		_drivetrain.build(Ground.Y, GearboxModel.countershaft_position(_model.crank_position(), spec), _tank.outlet_position(), frame_half_width)
		_build_cell_equipment()
		if spec.v3r_style:
			_drivetrain.add_v3r_bodywork(_tank.outlet_position())
		_clutch.build(_model.crank_position(), spec, _model.primary_gear_x())
		_gearbox.build(_model.crank_position(), spec, _model.primary_gear_x())
		_fuel_line.build(_tank.outlet_position(), _model.injector_position())
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
	_exhaust.build(layout)
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
	_panel.set_warning(spec.validation_warning())


var _audio_key := ""
var _tail_tip := Vector3.ZERO


func _tailpipe_tip(layout: ExhaustLayout) -> Vector3:
	for i in range(layout.pipes.size() - 1, -1, -1):
		var pipe = layout.pipes[i]
		if pipe.kind == "tail" and not pipe.pts.is_empty():
			return pipe.pts[pipe.pts.size() - 1]
	return Vector3.ZERO


# Debug trace: prints the step and time, so a freeze shows the last step reached in the Output panel.
func _trace(step: String) -> void:
	print("[trace %8.3fs] %s" % [Time.get_ticks_msec() / 1000.0, step])
