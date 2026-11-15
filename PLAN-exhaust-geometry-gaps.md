# Close the gaps in the exhaust geometry

## Goal

Add the hardware a real motorcycle exhaust has at its joints and mounts — head flanges with their studs and nuts, slip-joint
springs, an O2 sensor boss, a muffler hanger and a catalyst heat shield — so the drawn system stops looking like one welded
tube run and starts looking like a serviceable assembly.

## Current context / assumptions

Read this before touching anything; every claim below was checked in the tree.

**What exists and is already good.** Do not redo it.

- `scripts/model/pipe/exhaust.gd` (`class_name Exhaust`, 226 lines) draws an `ExhaustLayout`: `_tube()` sweeps a circle along
  a path and gives **open ends a real wall and rim** (`WALL := 0.012`, 1.2 mm), `_clamp()` puts band clamps at the joints
  (`catalyst`, `mid`, `muffler` upstream ends) and two straps round the canister, each part gets its own duplicated
  `StandardMaterial3D` so it can glow independently, and `update_heat(gas_c, delta)` drives `ExhaustHeat` per part with
  `HEAT_ALONG` cooling factors.
- `scripts/exhaust/exhaust_layout.gd` (243 lines) computes the routing and exposes `layout.pipes: Array[Pipe]`, where each
  `Pipe` has `name`, `kind` (`primary | secondary | collector | catalyst | mid | muffler | tail`), `pts`, `radii`, `cyl`
  (primary only), `feeders`, `loss`.
- `scripts/exhaust/expansion_chamber.gd` already draws the two-stroke chamber (`add_to(layout, port, cyl, length_m)`).
- `scripts/exhaust/backfire_flame.gd` puts the flame at the tail tip.
- Tests that already cover this — five unit tests (`tests/unit/exhaust/backfire_flame_test.gd`, `collector_rest_test.gd`,
  `exhaust_chamber_test.gd`, `exhaust_heat_test.gd`, `exhaust_native_test.gd`) and two integration tests
  (`tests/integration/exhaust/live_exhaust_option_test.gd`, `live_exhaust_routing_test.gd`), which is why
  `TEST_FILTER=exhaust/` reports **7** tests, not 5.
- `scripts/app/main.gd:1190` builds the layout and calls `_exhaust.build(layout, muffler_scene)`.

**What is missing** (this is the whole task list):

| missing part | why it matters | where it belongs |
|---|---|---|
| head flange + 2 studs + 2 nuts per primary | every header bolts to the head; the pipe currently starts in mid-air at the port | `Exhaust.build()` |
| crush gasket ring at each port | the flange needs something to crush against | same |
| slip-joint springs (2 per joint, header→collector and mid→muffler) | the most visible fastener on a naked bike's exhaust | same |
| O2 / lambda sensor boss on the collector | the sim models lambda; the bung and sensor are invisible | same |
| muffler hanger + rubber bobbin | the canister currently floats — nothing joins it to the bike | `Exhaust.build()` + `main.gd` passes an anchor |
| catalyst heat shield | real cats are shrouded; ours is a bare tube | `Exhaust.build()` |

**Conventions you must keep.**

- 1 scene unit = 100 mm (`Units.M_TO_SCENE`), so a 60 mm flange is `0.30` units.
- Geometry is generated in code: primitives or `SurfaceTool`, inline `StandardMaterial3D`, no imported files.
- A new part gets a **stable node name** — the tests address parts by path. Prefix by kind: `Flange%03d`, `HeaderSpring%d`,
  `MufflerHanger`, `LambdaBoss`, `CatalystShield`.
- Estimated proportions must be labelled `ESTIMATE` in a comment.
- Per `docs/LAYOUT.md`, tests for geometry go in `tests/unit/model/pipe/`, geometry stays in `scripts/model/pipe/`.
- Run tests with `$GODOT`; nothing here needs a window (no screenshots), so headless is enough.

Set up the shell once:

```bash
cd "/d/Projects/Engine Builder"
export GODOT="D:/Program Files (x86)/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
```

---

### Task 0 — Baseline

```bash
"$GODOT" --headless --path . --import 2>&1 | grep -icE 'SCRIPT ERROR|Parse Error'
TEST_FILTER=exhaust/ "$GODOT" --headless --path . -s res://tests/test_runner.gd 2>&1 | grep -E '^(FAIL|RESULT)' | tail -3
```

Expected: `0`, then `RESULT: 0 of 7 failed (exhaust/)`. If the exhaust tests are not green before you start, stop and report —
they are green on this tree.

---

### Task 1 — Head flanges, studs, nuts and gaskets

**Write the failing test** `tests/unit/model/pipe/exhaust_hardware_test.gd`:

```gdscript
extends SceneTree

# The exhaust hardware a real system bolts on with: a flange at every port with its two studs and nuts, a crush gasket
# behind each flange, springs at the slip joints, a lambda boss on the collector, a hanger on the canister and a shield
# over the catalyst. Geometry only - the gas model is covered in tests/unit/exhaust/.
# Run: godot --headless --path . -s tests/unit/model/pipe/exhaust_hardware_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func spec_of(id: String) -> EngineSpec:
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS[id]
	for key in preset.keys():
		spec.set(key, preset[key])
	return spec


func build(spec: EngineSpec) -> Array:
	var layout := ExhaustLayout.build(spec, [], Vector3(0.0, 2.0, 0.0), Ground.Y, Vector3(0.0, 3.0, -5.95))
	var exhaust := Exhaust.new()
	root.add_child(exhaust)
	exhaust.build(layout, null)
	return [exhaust, layout]


func primaries(layout: ExhaustLayout) -> Array:
	var found := []
	for pipe in layout.pipes:
		if pipe.kind == "primary":
			found.append(pipe)
	return found


func _init() -> void:
	await process_frame
	var spec := spec_of("honda_cbr1000rrr_sp")
	var built := build(spec)
	var exhaust := built[0] as Exhaust
	var layout := built[1] as ExhaustLayout
	var prim := primaries(layout)
	check(prim.size() == 4, "the inline-four has four primaries (%d found)" % prim.size())

	# one flange per port, sitting ON the port, no gap
	var flanges := 0
	for pipe in prim:
		var flange := exhaust.get_node_or_null("Flange_%s" % pipe.name.trim_prefix("primary ")) as Node3D
		check(flange != null, "a flange on %s" % pipe.name)
		if flange == null:
			continue
		flanges += 1
		var port: Vector3 = pipe.pts[0]
		check(flange.global_position.distance_to(exhaust.to_global(port)) < 1.0e-4,
			"%s: the flange is on the port (%.3f away)" % [pipe.name, flange.global_position.distance_to(exhaust.to_global(port))])
		check(flange.get_node_or_null("Gasket") != null, "%s: the flange has a gasket behind it" % pipe.name)
		check(flange.get_node_or_null("Stud0") != null and flange.get_node_or_null("Stud1") != null,
			"%s: the flange has two studs" % pipe.name)
		check(flange.get_node_or_null("Stud0/Nut") != null and flange.get_node_or_null("Stud1/Nut") != null,
			"%s: both studs carry a nut" % pipe.name)
	check(flanges == prim.size(), "every primary got its flange (%d of %d)" % [flanges, prim.size()])

	print("flanges: %d on %d primaries" % [flanges, prim.size()])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
```

Run it — expect four `FAIL a flange on primary N` lines and `RESULT: FAIL`:

```bash
timeout 120 "$GODOT" --headless --path . -s tests/unit/model/pipe/exhaust_hardware_test.gd 2>&1 | grep -E '^FAIL|RESULT'
```

**Implement** in `scripts/model/pipe/exhaust.gd`. Add two helpers above `_tube()` (they only need `MeshInstance3D`, so put
them next to `_clamp()`), then call them from `build()`.

```gdscript
# The flange a header bolts to the head with, with its crush gasket and two studs. A real one is a 8-10 mm steel plate
# the tube is welded through, and the pipe's own radius sets its size: ESTIMATE the plate at 1.9x tube radius.
#   port  the exhaust port, i.e. pipe.pts[0]
#   dir   the direction the pipe leaves the port in
func _flange(parent: Node3D, port: Vector3, dir: Vector3, radius: float, name: String, steel: Material, dark: Material) -> void:
	var node := Node3D.new()
	node.name = name
	node.position = port
	parent.add_child(node)
	var plate := CylinderMesh.new()
	plate.top_radius = radius * 1.9
	plate.bottom_radius = radius * 1.9
	plate.height = 0.10 # 10 mm plate
	plate.radial_segments = SEGMENTS
	var body := MeshInstance3D.new()
	body.name = "Plate"
	body.mesh = plate
	body.material_override = steel
	body.quaternion = Quaternion(Vector3.UP, dir)
	node.add_child(body)
	# the crush gasket, a ring of copper behind the plate
	var gasket := MeshInstance3D.new()
	gasket.name = "Gasket"
	var ring := TorusMesh.new()
	ring.inner_radius = radius * 1.05
	ring.outer_radius = radius * 1.7
	ring.rings = SEGMENTS
	ring.ring_segments = 8
	gasket.mesh = ring
	gasket.material_override = _metal(Color(0.72, 0.45, 0.25), 0.5, 0.6)
	gasket.quaternion = Quaternion(Vector3.UP, dir)
	gasket.position = -dir * 0.06
	node.add_child(gasket)
	# two studs either side of the tube, each with its nut
	var tangent := dir.cross(Vector3.UP).normalized()
	if tangent.length() < 0.1:
		tangent = dir.cross(Vector3.RIGHT).normalized()
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var stud := MeshInstance3D.new()
		stud.name = "Stud%d" % i
		var rod := CylinderMesh.new()
		rod.top_radius = 0.035
		rod.bottom_radius = 0.035
		rod.height = 0.26
		rod.radial_segments = 8
		stud.mesh = rod
		stud.material_override = steel
		stud.position = tangent * side * radius * 1.55 + dir * 0.10
		stud.quaternion = Quaternion(Vector3.UP, dir)
		node.add_child(stud)
		var nut := MeshInstance3D.new()
		nut.name = "Nut"
		var hex := CylinderMesh.new()
		hex.top_radius = 0.055
		hex.bottom_radius = 0.055
		hex.height = 0.07
		hex.radial_segments = 6 # a hex nut, not a round one
		nut.mesh = hex
		nut.material_override = dark
		nut.position = dir * 0.14
		stud.add_child(nut)
```

Then, inside `build()`, immediately after the `if not used_asset: _add_mesh(...)` line, add:

```gdscript
		if pipe.kind == "primary" and pipe.pts.size() >= 2:
			var dir := (pipe.pts[1] - pipe.pts[0]).normalized()
			_flange(self, pipe.pts[0], dir, pipe.radii[0], "Flange_%s" % pipe.name.trim_prefix("primary "), header, clamp_mat)
```

Run the test again → `RESULT: PASS`, then the existing exhaust tests:

```bash
TEST_FILTER=exhaust/ "$GODOT" --headless --path . -s res://tests/test_runner.gd 2>&1 | grep -E '^RESULT'
```

Expected: `RESULT: 0 of 7 failed (exhaust/)`.

```bash
git add scripts/model/pipe/exhaust.gd tests/unit/model/pipe/exhaust_hardware_test.gd
git commit -m "Exhaust: flange, gasket, studs and nuts at every port"
```

---

### Task 2 — Slip-joint springs

**Extend the test** (add before the `RESULT` print):

```gdscript
	# a spring either side of every slip joint: header into the collector, and the mid pipe into the canister
	var joints := 0
	for pipe in layout.pipes:
		if pipe.kind in ["collector", "muffler"] and pipe.pts.size() >= 2:
			for i in 2:
				joints += 1
				check(exhaust.get_node_or_null("%sSpring%d" % [pipe.kind.capitalize(), i]) != null,
					"a spring on the %s joint (%d)" % [pipe.kind, i])
	check(joints > 0, "the layout produced joints to spring")
```

Run: two `FAIL` per joint. Then add to `scripts/model/pipe/exhaust.gd`:

```gdscript
# A tension spring across a slip joint, hooked to a lug on each pipe. The helix is swept with _tube so the coils read as
# round wire from any angle.
func _spring(parent: Node3D, at: Vector3, axis: Vector3, radius: float, name: String, steel: Material, coils := 6) -> void:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var flat := axis.cross(Vector3.UP).normalized()
	if flat.length() < 0.1:
		flat = axis.cross(Vector3.RIGHT).normalized()
	var up := axis.cross(flat).normalized()
	var turns := coils * TAU
	for i in coils * 12:
		var t := float(i) / float(coils * 12 - 1)
		var a := turns * t
		pts.append(at + axis * (t * 0.22) + flat * cos(a) * radius + up * sin(a) * radius)
		radii.append(0.012) # 12 mm of wire
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = _tube(pts, radii, false)
	node.material_override = steel
	parent.add_child(node)
```

and in `build()`, after the flange block:

```gdscript
		if pipe.kind in ["collector", "muffler"] and pipe.pts.size() >= 2:
			var axis := (pipe.pts[1] - pipe.pts[0]).normalized()
			var tangent := axis.cross(Vector3.UP).normalized()
			for i in 2:
				var side := 1.0 if i == 0 else -1.0
				_spring(self, pipe.pts[0] + tangent * side * pipe.radii[0] * 1.3, axis,
					pipe.radii[0] * 0.22, "%sSpring%d" % [pipe.kind.capitalize(), i], clamp_mat)
```

Verify with the same three commands as task 1, then:

```bash
git add -A scripts/model/pipe/exhaust.gd tests/unit/model/pipe/exhaust_hardware_test.gd
git commit -m "Exhaust: slip-joint springs at the collector and canister"
```

---

### Task 3 — Lambda sensor boss on the collector

**Extend the test:**

```gdscript
	# the O2 sensor: a boss on the collector with a sensor screwed into it, facing away from the pipe
	var boss := exhaust.get_node_or_null("LambdaBoss") as Node3D
	check(boss != null, "the collector carries a lambda boss")
	if boss != null:
		check(boss.get_node_or_null("Sensor") != null, "a sensor is screwed into the boss")
		var collector := layout.pipes.filter(func(p): return p.kind == "collector")[0]
		var on_pipe := collector.pts[1]
		check(boss.global_position.distance_to(exhaust.to_global(on_pipe)) < 0.05,
			"the boss sits on the collector (%.3f from its second point)" % boss.global_position.distance_to(exhaust.to_global(on_pipe)))
```

Implement in `build()` after the pipe loop (the collector is known by then):

```gdscript
	# the lambda sensor: a boss welded into the collector with the sensor threaded into it, and a wire that leaves along
	# the pipe. The physics already reads lambda; this is the part that measures it.
	for pipe in layout.pipes:
		if pipe.kind == "collector" and pipe.pts.size() >= 2:
			var axis := (pipe.pts[1] - pipe.pts[0]).normalized()
			var normal := axis.cross(Vector3.RIGHT).normalized()
			var boss := Node3D.new()
			boss.name = "LambdaBoss"
			boss.position = pipe.pts[1] + normal * pipe.radii[1] * 0.9
			boss.quaternion = Quaternion(Vector3.UP, normal)
			add_child(boss)
			var collar := MeshInstance3D.new()
			collar.name = "Collar"
			var shape := CylinderMesh.new()
			shape.top_radius = 0.07
			shape.bottom_radius = 0.07
			shape.height = 0.12
			shape.radial_segments = 6
			collar.mesh = shape
			collar.material_override = clamp_mat
			boss.add_child(collar)
			var sensor := MeshInstance3D.new()
			sensor.name = "Sensor"
			var body := CylinderMesh.new()
			body.top_radius = 0.045
			body.bottom_radius = 0.045
			body.height = 0.30
			body.radial_segments = 10
			sensor.mesh = body
			sensor.material_override = cat
			sensor.position = Vector3(0.0, 0.16, 0.0)
			boss.add_child(sensor)
			var wire := MeshInstance3D.new()
			wire.name = "Wire"
			wire.mesh = _tube(PackedVector3Array([pipe.pts[1] + normal * 0.28, pipe.pts[1] + normal * 0.34 + axis * 0.25,
				pipe.pts[1] + normal * 0.20 + axis * 0.55]), PackedFloat32Array([0.014, 0.014, 0.014]), false)
			wire.material_override = clamp_mat
			wire.position = Vector3.ZERO
			add_child(wire)
			break
```

Verify as before, then commit with `-m "Exhaust: lambda boss and sensor on the collector"`.

---

### Task 4 — Muffler hanger and bobbin

**Extend the test:**

```gdscript
	var hanger := exhaust.get_node_or_null("MufflerHanger") as Node3D
	check(hanger != null, "the canister is hung off the bike, not floating")
	if hanger != null:
		check(hanger.get_node_or_null("Bobbin") != null, "the hanger has a rubber bobbin")
		var canister := layout.pipes.filter(func(p): return p.kind == "muffler")[0]
		var middle := canister.pts[0].lerp(canister.pts[-1], 0.55)
		check(hanger.global_position.distance_to(exhaust.to_global(middle)) < 0.5,
			"the hanger picks the canister up near its middle")
```

Implementation in `build()` after the strap loop:

```gdscript
		# the hanger: a stay from the canister up to a bracket on the frame, with a rubber bobbin so the exhaust can move
		# without cracking. The anchor is ESTIMATE - inboard and above the canister, where a subframe rail runs.
		if pipe.kind == "muffler":
			var middle := pipe.pts[0].lerp(pipe.pts[-1], 0.55)
			var upward := Vector3(0.0, 0.42, 0.0)
			var hanger := Node3D.new()
			hanger.name = "MufflerHanger"
			hanger.position = middle
			add_child(hanger)
			var stay := MeshInstance3D.new()
			stay.name = "Stay"
			var rod := CylinderMesh.new()
			rod.top_radius = 0.035
			rod.bottom_radius = 0.035
			rod.height = upward.length()
			rod.radial_segments = 8
			stay.mesh = rod
			stay.material_override = clamp_mat
			stay.position = upward * 0.5
			stay.quaternion = Quaternion(Vector3.UP, upward.normalized())
			hanger.add_child(stay)
			var bobbin := MeshInstance3D.new()
			bobbin.name = "Bobbin"
			var rubber := CylinderMesh.new()
			rubber.top_radius = 0.075
			rubber.bottom_radius = 0.075
			rubber.height = 0.10
			rubber.radial_segments = 12
			bobbin.mesh = rubber
			bobbin.material_override = _metal(Color(0.12, 0.12, 0.13), 0.9, 0.0)
			bobbin.position = upward
			bobbin.quaternion = Quaternion(Vector3.UP, upward.normalized())
			hanger.add_child(bobbin)
```

Verify as before, then commit with `-m "Exhaust: muffler hanger with a rubber bobbin"`.

---

### Task 5 — Catalyst heat shield

**Extend the test:**

```gdscript
	var shield := exhaust.get_node_or_null("CatalystShield") as MeshInstance3D
	check(shield != null, "the catalyst is shrouded, as a real one is")
	if shield != null:
		var cat_pipe := layout.pipes.filter(func(p): return p.kind == "catalyst")[0]
		check(shield.get_aabb().size.y > cat_pipe.radii[0] * 2.0,
			"the shield stands off the catalyst shell (%.3f)" % shield.get_aabb().size.y)
```

Implementation — a half-shell swept over the catalyst, standing off the tube so it reads as a shield:

```gdscript
# A half-cylindrical heat shield over a pipe: an arc of `span_deg` swept along the pipe's first two points, standing
# `stand_off` clear of the tube so air can pass behind it.
func _shield(pts: PackedVector3Array, radius: float, stand_off: float, steel: Material, name: String) -> void:
	var node := MeshInstance3D.new()
	node.name = name
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var axis := (pts[1] - pts[0]).normalized()
	var up := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var side := axis.cross(up).normalized()
	var out := side.cross(axis).normalized()
	var r := radius + stand_off
	var steps := 12
	for i in steps:
		var a0 := lerpf(-PI * 0.45, PI * 0.45, float(i) / float(steps))
		var a1 := lerpf(-PI * 0.45, PI * 0.45, float(i + 1) / float(steps))
		var n0 := (out * cos(a0) + side * sin(a0)).normalized()
		var n1 := (out * cos(a1) + side * sin(a1)).normalized()
		var p := pts[0] + n0 * r
		var q := pts[1] + n0 * r
		var s := pts[0] + n1 * r
		var t := pts[1] + n1 * r
		for item in [[p, n0], [q, n0], [s, n1], [s, n1], [q, n0], [t, n1]]:
			surface.set_normal(item[1])
			surface.add_vertex(item[0])
	node.mesh = surface.commit()
	node.material_override = steel
	add_child(node)
```

Call it after the pipe loop:

```gdscript
	for pipe in layout.pipes:
		if pipe.kind == "catalyst" and pipe.pts.size() >= 2:
			_shield(pipe.pts, pipe.radii[0], 0.06, muffler, "CatalystShield")
			break
```

Verify, then:

```bash
git add -A scripts/model/pipe/exhaust.gd tests/unit/model/pipe/exhaust_hardware_test.gd
git commit -m "Exhaust: heat shield over the catalyst"
```

---

### Task 6 — Full gate

```bash
"$GODOT" --headless --path . --import 2>&1 | grep -icE 'SCRIPT ERROR|Parse Error'
timeout 120 "$GODOT" --headless --path . -s tests/unit/model/pipe/exhaust_hardware_test.gd 2>&1 | grep -E '^FAIL|RESULT'
TEST_FILTER=exhaust/ "$GODOT" --headless --path . -s res://tests/test_runner.gd 2>&1 | grep -E '^(FAIL|RESULT)'
TEST_FILTER=model/ "$GODOT" --headless --path . -s res://tests/test_runner.gd 2>&1 | grep -E '^(FAIL|RESULT)'
"$GODOT" --headless --path . --quit-after 150 2>&1 | grep -cE 'SCRIPT ERROR|Parse Error'
```

Expected: `0`; `RESULT: PASS`; `RESULT: 0 of 7 failed (exhaust/)`; `RESULT: 0 of 8 failed (model/)` (7 + the new file); `0`.

Known-red tests on this tree, unrelated and not to be chased: `unit/drivetrain/shift_behavior_test.gd`,
`unit/sim/golden_trace_test.gd`, `unit/fuel/fuel_flow_test.gd`, `unit/ecu/ir_check.gd`, `unit/ecu/cut_pop_test.gd`,
`unit/engine/two_stroke_native_test.gd`.

---

### Task 7 — Look at it (windowed, optional but recommended)

Write `tools/diagnostics/capture_exhaust.gd` — same shape as `tools/diagnostics/capture_brakes.gd` (build a Drivetrain for
`honda_cbr1000rrr_sp`, then `_exhaust.build(ExhaustLayout.build(...))`, two lights, `Camera3D`, save PNG):

```gdscript
const OUT_DIR := "res://tools/diagnostics/out"
const PRESET := "honda_cbr1000rrr_sp"
# ... build spec, dt, layout, exhaust; then
#   await _shoot(cam, header_point + Vector3(-4.0, 2.0, 3.0), header_point, "%s/exhaust_header.png" % OUT_DIR)
#   await _shoot(cam, canister_mid + Vector3(-5.0, 2.5, 1.5), canister_mid, "%s/exhaust_can.png" % OUT_DIR)
```

```bash
timeout 300 "$GODOT" --path . -s res://tools/diagnostics/capture_exhaust.gd 2>&1 | grep -E 'saved|SCRIPT ERROR'
```

Expected: two `saved` lines. Look at the pictures: every primary should start on a flange, both joints should have springs,
the collector should carry the sensor, and the canister should hang off a stay.

## Tests / validation summary

| command | proves |
|---|---|
| `exhaust_hardware_test.gd` | flanges on ports with gaskets, studs and nuts; springs at both joints; lambda boss on the collector; hanger on the canister; shield over the catalyst |
| `TEST_FILTER=exhaust/` | the gas model, heat glow and flame are untouched |
| `TEST_FILTER=model/` | the rest of the geometry still builds |
| `--import` and `--quit-after 150` | every path resolves and the scene loads |
| `capture_exhaust.gd` | it looks like the parts are where the numbers say |

## Risks, tradeoffs, and open questions

- **These are decorative parts with no physics.** `ExhaustLayout` decides routing and losses; nothing here changes `loss`,
  `area_m2()` or `length_m()`. Keep it that way — if a flange ever needs to affect flow, that is a separate change with a
  physics test.
- **The hanger anchor is fabricated.** The exhaust Node has no reference to the frame, so the stay rises 42 mm to a bobbin
  in mid-air where a subframe rail would be. The honest fix is an optional `anchor: Vector3` parameter that `main.gd` fills
  from `_drivetrain`; do that only if it looks wrong in the render (YAGNI until then).
- **Node names are the test contract.** `Flange_1`…`Flange_4`, `CollectorSpring0/1`, `MufflerSpring0/1`, `LambdaBoss`,
  `MufflerHanger`, `CatalystShield`. Renaming one breaks the test, which is the point.
- **Two-stroke path untouched.** `ExpansionChamber.add_to()` builds its own layout, so no flange appears on a two-stroke; if
  that matters, the same `_flange()` call goes into `expansion_chamber.gd` with a test on `kawasaki_h2r`-free presets like
  `yamaha_rd350`. Deliberately out of scope.
- **An authored muffler still gets the straps, springs and hanger, and that may not suit it.** Those blocks sit outside the
  `if not used_asset:` branch (they read `pipe.radii` and `pipe.pts`, not the mesh), so a preset with a `muffler.glb` would
  get bands drawn at the procedural canister's radius, over a model of unknown size. No preset ships one today; if one does,
  guard the strap/hanger blocks with `if not used_asset:` at that point.
- **Open question:** should the exhaust valve (EXUP) and its cable be drawn at the canister inlet? Several litre bikes have
  one, but it is invisible behind the fairing on some and absent on others; add it only if the reference photo for the
  chosen preset shows it.
