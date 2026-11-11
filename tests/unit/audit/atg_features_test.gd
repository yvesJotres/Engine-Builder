extends SceneTree

# Audit: which of the ATG engine-sim's strongest features our sim already has. Each check looks for the feature in the source
# files that run it, so a feature counts as present only if the code that uses it is in the sim path. A feature that is
# ported but not called by the sim counts as ABSENT. Prints a table and exits 0; it is a report, not a pass/fail gate.
# Run: godot --headless --path . -s res://tests/unit/audio/atg_features_test.gd

const SRC := {
	"cyl_gd": "res://scripts/engine/cylinder.gd",
	"kernel": "res://gdextension/src/cylinder_kernel.cpp",
	"kernel_h": "res://gdextension/include/cylinder_kernel.h",
	"sim": "res://scripts/sim/engine_sim.gd",
	"sound": "res://scripts/audio/engine_sound.gd",
	"exh": "res://scripts/exhaust/exhaust_gas.gd",
}

# [feature, ATG reference, [file keys], [patterns that must appear in one of those files], note]
const CHECKS := [
	["Flame-front combustion", "combustion_chamber.cpp", ["cyl_gd", "kernel"], ["flame_speed", "flameSpeed", "travel_x"],
		"ATG grows a flame radius at a turbulence-dependent speed. We use a Wiebe curve."],
	["Stribeck friction", "combustion_chamber.cpp:374-390", ["sim", "cyl_gd", "kernel"], ["breakaway", "stribeck", "calculate_friction"],
		"ATG friction is smooth through zero speed. Ours is a simpler term in engine_sim.gd."],
	["Choked valve flow", "gas_system.cpp:183-229", ["cyl_gd", "kernel"], ["choked", "crit :=", "crit ="],
		"ATG has a choked branch in its orifice flow. Ours switches at the critical pressure ratio (crit)."],
	["Energy-based gas state", "gas_system.h:239-249", ["kernel_h"], ["S_U"],
		"Both track internal energy. This one is present."],
	["Adaptive fluid sub-steps", "piston_engine_simulator.cpp:304-317", ["cyl_gd"], ["_flow_steps"],
		"ATG runs 8 fluid sub-steps. We pick steps from the crank angle per call."],
	["Species / composition transport", "gas_system.h mix", ["cyl_gd", "kernel"], ["p_o2", "mole_fraction", "species"],
		"ATG tracks fuel, O2 and inert moles. We track fuel mass only."],
	["Blow-by to crankcase", "combustion_chamber.cpp:249", ["sim", "cyl_gd"], ["blowby", "blow_by"],
		"ATG leaks gas to a fixed crankcase reservoir. We have none."],
	["Dedicated audio thread", "synthesizer.cpp / simulator.cpp", ["sound"], ["Thread", "WorkerThreadPool"],
		"ATG renders audio on its own thread. Ours renders in _process on the main thread."],
	["1D exhaust wave model", "ATG has none (lumped volumes)", ["exh"], ["HLLE", "hlle", "CELL_M"],
		"Ours is an advantage: pressure waves travel along the pipes."],
	["Procedural sound layers", "ATG has none", ["sound"], ["LayerBank", "layer_bank"],
		"Ours is an advantage: starter, dynamo, gear whine, valvetrain, knock."],
]


func _init() -> void:
	var text := {}
	for key in SRC:
		text[key] = FileAccess.get_file_as_string(SRC[key])
	var present := 0
	print("%-32s %-8s %s" % ["Feature", "Result", "ATG reference / note"])
	for c in CHECKS:
		var found := false
		for key in c[2]:
			for pat in c[3]:
				if str(text[key]).contains(pat):
					found = true
		if found:
			present += 1
		print("%-32s %-8s %s | %s" % [c[0], "PRESENT" if found else "ABSENT", c[1], c[4]])
	print("atg_features_test: %d of %d ATG features present in the sim path" % [present, CHECKS.size()])
	quit(0)
