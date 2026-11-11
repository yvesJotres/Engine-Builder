extends SceneTree

# Renders the mechanical layer alone at a fixed rpm and prints the dominant frequency: checks the gear-mesh formula.
func _init() -> void:
	var c := SoundContext.new()
	c.rpm = 10500.0
	c.running = true
	c.load = 1.0
	c.fire_time = 10.0
	c.primary_ratio = 3.26
	var layer := MechanicalLayer.new()
	var n := 44100
	var out := PackedFloat32Array()
	var done := 0
	while done < n:
		out.append_array(layer.render(441, c))
		done += 441
	var best_f := 0.0
	var best := 0.0
	var f := 2000.0
	while f < 20000.0:
		var re := 0.0
		var im := 0.0
		for i in range(20000, 40000):
			re += out[i] * cos(TAU * f * i / 44100.0)
			im += out[i] * sin(TAU * f * i / 44100.0)
		var p := re * re + im * im
		if p > best:
			best = p
			best_f = f
		f += 20.0
	print("dominant freq %.0f Hz (expected %.0f)" % [best_f, 75.0 * 10500.0 / 60.0])
	quit(0)
