# Layout

| what it is | where it goes | test goes in |
|---|---|---|
| physics, one file per model | `scripts/sim/` | `tests/unit/sim/` |
| node-building geometry | `scripts/model/<feature>/` | `tests/unit/model/<feature>/` |
| pure mesh maths (no nodes) | `scripts/model/<feature>/parts/` | same folder |
| scene-wide behaviour | `scripts/app/` | `tests/integration/` |
| screen and `CanvasLayer` UI | `scripts/ui/` | `tests/unit/ui/` |
| any binary or data file | `assets/` | — |
| one-off inspection script | `tools/diagnostics/` | not run by the runner |

`tests/unit/structure/layout_test.gd` enforces the two rules that are mechanical: no `.gd` under `assets/`, and nothing
referencing the old `assets/3d/generated` path. Adding a part means: geometry in `scripts/model/<feature>/`, test in the
mirrored folder, then

```
TEST_FILTER=<feature>/ godot --headless --path . -s res://tests/test_runner.gd
```

## The bike's geometry, as it stands

```
scripts/model/
├── engine/   engine_model.gd · crankshaft.gd · intake_model.gd
├── bike/     drivetrain.gd (coordinator) · chassis.gd · brakes.gd · cockpit.gd · axles.gd
│   └── parts/  sprocket.gd · tire_tread.gd · meshes.gd · materials.gd
├── pipe/     exhaust.gd
└── props/    dyno_cell.gd · spl_meter_rig.gd · ground.gd · fuel_tank_model.gd · fuel_line.gd
```

`Drivetrain` owns the scene node and the bike's state (`_front_half`, `_rear_half`, `_head`, the pedal and lever nodes).
The modules are `RefCounted` with `static func`s; the ones that add nodes take the node they draw into as `host`, and the
ones that are pure maths (`parts/meshes.gd`) take numbers only. `Drivetrain` re-exports the constants the modules own
(`const ROTOR_THICKNESS := BikeMeshes.ROTOR_THICKNESS`) so tests and callers keep one stable name to import.
