# Contributing

## Running the tests

The project runs its tests headless with Godot 4.7.2. `run_test.bat` runs the main engine test:

```bash
godot --headless --path . -s res://tests/unit/test_engine.gd
```

Each test is a script in `tests/` that extends `SceneTree`. It exits 0 when it passes and 1 when it fails. A test that prints `SCRIPT ERROR` also counts as failing, even with exit 0.

The publish gate in `server/publish_update.py` runs a fixed list of these tests, plus the server's own unit tests, before any patch goes out. A patch is only published when the whole gate passes.

## Code style

- GDScript, indented with tabs.
- Explicit types on variables where Godot can't infer them. In particular, `var x := dict["key"]` fails to parse when the dictionary isn't typed; write `var x: bool = dict["key"]`.
- A `class_name` script can't be added by a patch. New scripts that patches must ship should use `preload` instead.
- Keep constants with their units in the name or a comment (`_m`, `_kg`, `_rpm`, `_deg`).

## Changing presets

See [docs/presets.md](docs/presets.md). Run `tests/unit/controls/panel_defaults_test.gd` after changing a preset or a control, since it checks that the panel matches each preset.

## Changing the ECU parser

See [docs/ecu_binaries.md](docs/ecu_binaries.md). Only the verified primary rev limiter affects the physics. Do not add other decoded tables to the simulation without a test against a published reference.

## Publishing

Patches are published with `server/publish_update.py`: `--draft` stores a patch that players can't see yet, and `--promote` makes it available. Do not publish while the change is still being tested.
