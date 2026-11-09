class_name ExhaustGas
extends RefCounted

# One-dimensional unsteady exhaust gas. Each drawn pipe is a row of cells. Pressure, velocity and
# temperature move with the gas, reflect at area changes, and leave at the open tail. The cylinder
# blows into the primary through the valve; the sound is the tail flow of this same gas.

const GAMMA := 1.3
const R := 287.0
const P0 := 101325.0
const T0 := 300.0
const CELL_M := 0.24
const AUDIO_RATE := 44100.0
const CFL := 0.85

var _n := 0
var _rho := PackedFloat32Array()
var _ru := PackedFloat32Array()
var _re := PackedFloat32Array()
var _area := PackedFloat32Array()
var _dx := PackedFloat32Array()
var _loss := PackedFloat32Array()
var _pipe0 := PackedInt32Array()
var _pipe_n := PackedInt32Array()
var _parent := PackedInt32Array() # pipe this one feeds, or -1 at the tail
var _cyl_pipe := PackedInt32Array()
var _feeders: Array = []
var _mdot := PackedFloat32Array()
var _power := PackedFloat32Array()
var _flow := PackedFloat32Array()
var record_audio := true # tail samples for the sound. The gas step itself always runs; the valves breathe that pressure.
var _d_rho := PackedFloat32Array()
var _d_ru := PackedFloat32Array()
var _d_re := PackedFloat32Array()
var _fl := PackedInt32Array()
var _fr := PackedInt32Array()
var _sl := PackedFloat32Array()
var _sr := PackedFloat32Array()
var _fk := PackedByteArray()
var _nf := 0
var _cfl_dt := 1.0e-4
var _min_dx := CELL_M
var _audio_left := 0.0 # time from the end of the last step to the next sample
var _q_prev := 0.0 # tail volume flow at the end of the last step
var _npipes := 0
var _flow_write_pos := 0


func build(layout: ExhaustLayout) -> void:
	_flow.resize(88200)
	_flow_write_pos = 0
	_npipes = layout.pipes.size()
	_pipe0.resize(_npipes)
	_pipe_n.resize(_npipes)
	_parent.resize(_npipes)
	_parent.fill(-1)
	_feeders.clear()
	_cyl_pipe = PackedInt32Array()
	_cyl_pipe.resize(16)
	_cyl_pipe.fill(-1)
	var counts: Array[int] = []
	var areas: Array[float] = []
	var losses: Array[float] = []
	var dxs: Array[float] = []
	for i in _npipes:
		var pipe: ExhaustLayout.Pipe = layout.pipes[i]
		var length := maxf(pipe.length_m(), CELL_M)
		var count := maxi(1, roundi(length / CELL_M))
		var dx := length / float(count)
		counts.append(count)
		dxs.append(dx)
		losses.append(pipe.loss)
		_feeders.append(PackedInt32Array(pipe.feeders))
		for f in pipe.feeders:
			_parent[f] = i
		if pipe.cyl >= 0 and pipe.cyl < _cyl_pipe.size():
			_cyl_pipe[pipe.cyl] = i
		for c in count:
			areas.append(_area_at(pipe, (float(c) + 0.5) * dx))
	var total := 0
	for i in _npipes:
		_pipe0[i] = total
		_pipe_n[i] = counts[i]
		total += counts[i]
	_n = total
	_area.resize(total)
	_dx.resize(total)
	_loss.resize(total)
	var at := 0
	for i in _npipes:
		for _c in counts[i]:
			_area[at] = areas[at]
			_dx[at] = dxs[i]
			_loss[at] = losses[i]
			at += 1
	_rho.resize(total)
	_ru.resize(total)
	_re.resize(total)
	var rho0 := P0 / (R * T0)
	var e0 := P0 / ((GAMMA - 1.0) * rho0)
	for i in total:
		_rho[i] = rho0
		_ru[i] = 0.0
		_re[i] = rho0 * e0
	_mdot.resize(16)
	_power.resize(16)
	_mdot.fill(0.0)
	_power.fill(0.0)
	_flow = PackedFloat32Array()
	_d_rho.resize(total)
	_d_ru.resize(total)
	_d_re.resize(total)
	_min_dx = CELL_M
	for i in total:
		_min_dx = minf(_min_dx, _dx[i])
	_cfl_dt = CFL * _min_dx / (ambient_sound_speed() + 1.0)
	_audio_left = 0.0
	_q_prev = 0.0
	_build_faces()


func port_pressure(cylinder_index: int) -> float:
	var cell := _port_cell(cylinder_index)
	if cell < 0:
		return P0
	return _pressure(cell)


func port_temperature(cylinder_index: int) -> float:
	var cell := _port_cell(cylinder_index)
	if cell < 0:
		return T0
	return _pressure(cell) / (maxf(_rho[cell], 1e-6) * R)


# mdot > 0 is gas leaving the cylinder into the pipe. power is the enthalpy flux, watts, same sign.
func apply_valve(cylinder_index: int, mdot: float, power: float) -> void:
	if cylinder_index < 0 or cylinder_index >= _mdot.size():
		return
	_mdot[cylinder_index] = mdot
	_power[cylinder_index] = power


func add_energy(cylinder_index: int, joules: float) -> void:
	var cell := _port_cell(cylinder_index)
	if cell < 0 or joules == 0.0:
		return
	var volume := _area[cell] * _dx[cell]
	_re[cell] += joules / maxf(volume, 1e-8)
	_clamp_cell(cell)


func station_pressure(pipe_index: int) -> float:
	if pipe_index < 0 or pipe_index >= _npipes:
		return P0
	return _pressure(_pipe0[pipe_index])


func tail_volume_flow() -> float:
	if _n <= 0:
		return 0.0
	var last := _n - 1
	return _velocity(last) * _area[last]


func take_flow() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if _flow_write_pos > 0:
		out.resize(_flow_write_pos)
		for i in _flow_write_pos:
			out[i] = _flow[i]
	_flow_write_pos = 0
	return out


func advance(dt: float) -> void:
	if _n <= 0 or dt <= 0.0:
		return
	if _flow.size() == 0:
		_flow.resize(88200)
		_flow_write_pos = 0
	var remain := dt
	var guard := 0
	while remain > 1.0e-8 and guard < 8000:
		guard += 1
		var h := minf(_cfl_dt, remain)
		_step(h)
		var q1 := tail_volume_flow()
		if record_audio:
			# samples fall at 44.1 kHz; each one is the tail flow interpolated across this step, not held from its end
			var sample := 1.0 / AUDIO_RATE
			var t := _audio_left
			while t < h:
				_flow[_flow_write_pos] = lerpf(_q_prev, q1, t / h)
				_flow_write_pos = (_flow_write_pos + 1) % _flow.size()
				t += sample
			_audio_left = t - h
		_q_prev = q1
		remain -= h


func _port_cell(cylinder_index: int) -> int:
	if cylinder_index < 0 or cylinder_index >= _cyl_pipe.size():
		return -1
	var pipe := _cyl_pipe[cylinder_index]
	if pipe < 0:
		return -1
	return _pipe0[pipe]


func _area_at(pipe: ExhaustLayout.Pipe, dist_m: float) -> float:
	var dist := dist_m * ExhaustLayout.M
	var walked := 0.0
	var n := pipe.pts.size()
	if n < 2:
		return maxf(pipe.area_m2(), 1.0e-6)
	for i in n - 1:
		var seg := pipe.pts[i].distance_to(pipe.pts[i + 1])
		if walked + seg >= dist or i == n - 2:
			var t := clampf((dist - walked) / maxf(seg, 1e-6), 0.0, 1.0)
			var radius := lerpf(pipe.radii[i], pipe.radii[i + 1], t) / ExhaustLayout.M
			return maxf(PI * radius * radius, 1.0e-6)
		walked += seg
	return maxf(pipe.area_m2(), 1.0e-6)


func _build_faces() -> void:
	var lefts: Array[int] = []
	var rights: Array[int] = []
	var scale_l: Array[float] = []
	var scale_r: Array[float] = []
	var kinds: Array[int] = []
	for pipe in _npipes:
		var a0 := _pipe0[pipe]
		var count := _pipe_n[pipe]
		for i in count - 1:
			var left := a0 + i
			var right := a0 + i + 1
			var face_area := minf(_area[left], _area[right])
			lefts.append(left)
			rights.append(right)
			scale_l.append(-face_area / (_area[left] * _dx[left]))
			scale_r.append(face_area / (_area[right] * _dx[right]))
			kinds.append(0)
		if _parent[pipe] < 0:
			var last := a0 + count - 1
			lefts.append(last)
			rights.append(last)
			scale_l.append(-1.0 / _dx[last])
			scale_r.append(0.0)
			kinds.append(2)
		if (_feeders[pipe] as PackedInt32Array).is_empty():
			lefts.append(a0)
			rights.append(a0)
			scale_l.append(1.0 / _dx[a0])
			scale_r.append(0.0)
			kinds.append(1)
	for pipe in _npipes:
		var feeders: PackedInt32Array = _feeders[pipe]
		if feeders.is_empty():
			continue
		var into := _pipe0[pipe]
		for f in feeders:
			var last := _pipe0[f] + _pipe_n[f] - 1
			var face_area := minf(_area[last], _area[into])
			lefts.append(last)
			rights.append(into)
			scale_l.append(-face_area / (_area[last] * _dx[last]))
			scale_r.append(face_area / (_area[into] * _dx[into]))
			kinds.append(0)
	_nf = lefts.size()
	_fl = PackedInt32Array(lefts)
	_fr = PackedInt32Array(rights)
	_sl = PackedFloat32Array(scale_l)
	_sr = PackedFloat32Array(scale_r)
	_fk.resize(_nf)
	for i in _nf:
		_fk[i] = kinds[i]


func _step(dt: float) -> void:
	_d_rho.fill(0.0)
	_d_ru.fill(0.0)
	_d_re.fill(0.0)
	var gm1 := GAMMA - 1.0
	for f in _nf:
		var l := _fl[f]
		var rho_l := maxf(_rho[l], 1.0e-6)
		var u_l := _ru[l] / rho_l
		var p_l := maxf(gm1 * (_re[l] - 0.5 * rho_l * u_l * u_l), 200.0)
		var kind := _fk[f]
		var fm: float
		var fu: float
		var fe: float
		if kind == 1:
			var c_l := sqrt(GAMMA * p_l / rho_l)
			fm = 0.0
			fu = maxf(p_l - rho_l * c_l * u_l, 200.0)
			fe = 0.0
		elif kind == 2:
			var rho_face := rho_l if u_l >= 0.0 else P0 / (R * T0)
			var e_face := P0 / gm1 + 0.5 * rho_face * u_l * u_l
			var h_face := (e_face + P0) / rho_face
			fm = rho_face * u_l
			fu = fm * u_l + P0
			fe = fm * h_face
		else:
			var r := _fr[f]
			var rho_r := maxf(_rho[r], 1.0e-6)
			var u_r := _ru[r] / rho_r
			var p_r := maxf(gm1 * (_re[r] - 0.5 * rho_r * u_r * u_r), 200.0)
			var e_l := p_l / gm1 + 0.5 * rho_l * u_l * u_l
			var e_r := p_r / gm1 + 0.5 * rho_r * u_r * u_r
			var h_l := (e_l + p_l) / rho_l
			var h_r := (e_r + p_r) / rho_r
			var fx_l := rho_l * u_l
			var fy_l := fx_l * u_l + p_l
			var fz_l := fx_l * h_l
			var fx_r := rho_r * u_r
			var fy_r := fx_r * u_r + p_r
			var fz_r := fx_r * h_r
			var s := maxf(absf(u_l) + sqrt(GAMMA * p_l / rho_l), absf(u_r) + sqrt(GAMMA * p_r / rho_r))
			fm = 0.5 * (fx_l + fx_r) - 0.5 * s * (rho_r - rho_l)
			fu = 0.5 * (fy_l + fy_r) - 0.5 * s * (rho_r * u_r - rho_l * u_l)
			fe = 0.5 * (fz_l + fz_r) - 0.5 * s * (e_r - e_l)
			var sr := _sr[f] * dt
			_d_rho[r] += fm * sr
			_d_ru[r] += fu * sr
			_d_re[r] += fe * sr
			# The flux crosses the narrower pipe. The step wall holds the rest of the wider pipe,
			# so a pipe at rest stays at rest instead of pumping itself up to the pressure clamp.
			var wide_l := _area[l]
			var wide_r := _area[r]
			var throat := minf(wide_l, wide_r)
			if wide_l > throat:
				_d_ru[l] -= p_l * (wide_l - throat) / (wide_l * _dx[l]) * dt
			if wide_r > throat:
				_d_ru[r] += p_r * (wide_r - throat) / (wide_r * _dx[r]) * dt
		var sl := _sl[f] * dt
		_d_rho[l] += fm * sl
		_d_ru[l] += fu * sl
		_d_re[l] += fe * sl
	# A collector has one upstream pressure face, not one full-area face for
	# each header. Per-branch wall corrections above otherwise count the same
	# parent pressure multiple times and accelerate gas even at uniform rest.
	for pipe in _npipes:
		var feeder_count: int = (_feeders[pipe] as PackedInt32Array).size()
		if feeder_count > 1:
			var cell := _pipe0[pipe]
			_d_ru[cell] -= (feeder_count - 1) * _pressure(cell) / _dx[cell] * dt
	for i in _n:
		_rho[i] += _d_rho[i]
		_ru[i] += _d_ru[i]
		_re[i] += _d_re[i]
	for cyl in _mdot.size():
		var cell := _port_cell(cyl)
		if cell < 0:
			continue
		var volume := _area[cell] * _dx[cell]
		# Backflow (gas drawn from the pipe into the cylinder) carries the pipe's own gas out: its enthalpy, not the cylinder's.
		# The cylinder's enthalpy is only right for gas that flows in from the cylinder.
		var rho_c := _rho[cell]
		var u_c := _ru[cell] / maxf(rho_c, 1.0e-8)
		var p_c := (GAMMA - 1.0) * (_re[cell] - 0.5 * rho_c * u_c * u_c)
		var h_c := (_re[cell] + p_c) / maxf(rho_c, 1.0e-8)
		var energy_in := _mdot[cyl] * h_c if _mdot[cyl] < 0.0 else _power[cyl]
		_rho[cell] += _mdot[cyl] * dt / volume
		_re[cell] += energy_in * dt / volume
		var inflow := _mdot[cyl] / maxf(_rho[cell] * _area[cell], 1.0e-8)
		_ru[cell] += _mdot[cyl] * inflow * dt / volume
	var fastest := ambient_sound_speed()
	var cv_min := R / gm1 * 200.0
	var cv_max := R / gm1 * 3500.0
	for i in _n:
		var rho := clampf(_rho[i], 0.02, 40.0)
		var u := clampf(_ru[i] / rho, -800.0, 800.0)
		var c_snd := sqrt(GAMMA * gm1 * maxf(_re[i] / rho - 0.5 * u * u, cv_min))
		var cut := clampf(_loss[i] * c_snd * dt, 0.0, 0.5) # loss is per metre, and the wave covers c * dt in this step
		u *= 1.0 - cut
		var ke := 0.5 * u * u
		var internal := clampf(_re[i] / rho - ke, cv_min, cv_max)
		_rho[i] = rho
		_ru[i] = rho * u
		_re[i] = rho * (internal + ke)
		fastest = maxf(fastest, absf(u) + sqrt(GAMMA * gm1 * internal))
	_cfl_dt = maxf(CFL * _min_dx / fastest, 1.0e-6)


func _clamp_cell(cell: int) -> void:
	var rho := clampf(_rho[cell], 0.02, 40.0)
	var u := clampf(_ru[cell] / rho, -800.0, 800.0)
	var ke := 0.5 * u * u
	var internal := clampf(_re[cell] / rho - ke, R / (GAMMA - 1.0) * 200.0, R / (GAMMA - 1.0) * 3500.0)
	_rho[cell] = rho
	_ru[cell] = rho * u
	_re[cell] = rho * (internal + ke)


func _pressure(cell: int) -> float:
	var u := _velocity(cell)
	var internal := _re[cell] / maxf(_rho[cell], 1e-6) - 0.5 * u * u
	return maxf((GAMMA - 1.0) * _rho[cell] * internal, 200.0)


func _velocity(cell: int) -> float:
	return _ru[cell] / maxf(_rho[cell], 1e-6)


static func ambient_sound_speed() -> float:
	return sqrt(GAMMA * R * T0)
