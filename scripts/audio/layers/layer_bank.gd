class_name LayerBank
extends RefCounted

# The sound layers, mixed into one mono block. Each layer has its own gain, so a layer can be turned down or off without touching
# its code. Layers add to the engine sound before the leveler, so the leveler keeps the total at a sensible level.

const GAIN_VALVETRAIN := 0.05 # gains tuned on the R1M idle: the layers are a texture under the exhaust, not a second engine
const GAIN_MECHANICAL := 0.5
const GAIN_DRIVELINE := 0.08
const GAIN_TURBO := 0.4
const GAIN_KNOCK := 0.4

var enabled := true # false switches every layer off, for comparing against the plain engine sound
var _layers: Array[SoundLayer] = []
var _gains: Array[float] = []
var _mix := PackedFloat32Array()


# The standard set. The driveline and turbo layers cost the most CPU, so phones skip them.
static func standard(mobile: bool) -> LayerBank:
	var bank := LayerBank.new()
	bank.add(ValvetrainLayer.new(), GAIN_VALVETRAIN)
	bank.add(MechanicalLayer.new(), GAIN_MECHANICAL)
	if not mobile:
		bank.add(DrivelineLayer.new(), GAIN_DRIVELINE)
		bank.add(TurboLayer.new(), GAIN_TURBO)
	bank.add(KnockLayer.new(), GAIN_KNOCK)
	return bank


func add(layer: SoundLayer, gain: float) -> void:
	_layers.append(layer)
	_gains.append(gain)


func configure(spec: EngineSpec) -> void:
	for layer in _layers:
		layer.configure(spec)


func reset() -> void:
	for layer in _layers:
		layer.reset()


# Sets one layer's gain by its index in the order they were added. A gain of 0 turns it off.
func set_gain(index: int, gain: float) -> void:
	if index >= 0 and index < _gains.size():
		_gains[index] = gain


func layer_count() -> int:
	return _layers.size()


# Renders frames mono samples: every layer, scaled by its gain, summed.
func render(frames: int, c: SoundContext) -> PackedFloat32Array:
	if _mix.size() != frames:
		_mix.resize(frames)
	_mix.fill(0.0)
	if not enabled or frames <= 0:
		return _mix
	for index in _layers.size():
		var gain := _gains[index]
		if gain <= 0.0:
			continue
		var block := _layers[index].render(frames, c)
		for i in frames:
			_mix[i] += block[i] * gain
	return _mix
