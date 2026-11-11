# ECU binaries

A preset can point at an ECU calibration dump with `ecu.binary_path`. The path is a `res://` path, usually under `ecu_bins/`. `scripts/sim/engine_sim.gd` (`_sync_ecu_calibration`) loads the file when the preset is applied. The simulation uses only the **verified primary rev limiter** from it, as a cap on the preset's redline. The other decoded maps are diagnostic only and do not affect the physics.

## What is parsed

`scripts/ecu/ecu_binary_parser.gd` (`ECUBinaryParser`) reads one layout: the Keihin N04 layout used by the Honda CBR250RR ECU (`38770-K64-N04`). The addresses are verified only for the Indonesia N04 flash. Other K64 flashes are rejected with an unsupported-layout warning rather than decoded, because applying the N04 addresses to them gave invalid values. It identifies the layout from the file, then decodes tables with `parse_all()`. The limiter it returns as `limiter_1` is the one the sim uses. The fuel and ignition map accessors (`get_fuel_map`, `get_ignition_map`) are for diagnostics.

Usage:

```gdscript
var parser := ECUBinaryParser.new()
if not parser.load_binary("res://ecu_bins/CBR250RR-38770-K64-N04_BIN.bin"):
	print(parser.get_error())
```

`load_binary` returns `false` and sets `get_error()` when the file can't be opened or doesn't match a known layout.

## What happens with other ECUs

Only the N04 layout is implemented. A file in any other format fails `load_binary`, and the test `tests/unit/test_engine.gd` fails on it. For that reason, presets for engines without a readable dump leave `binary_path` empty (for example the AMG M276 and the Yamaha presets).

## Adding a new layout

1. Find the byte offsets and scaling of the maps in the new dump. Write them down with the source.
2. Add a branch to `_identify_layout()` that recognises the file, and read the maps for it.
3. Add a test that loads a known file and checks a few values against a published reference.
4. Point the preset's `binary_path` at the file.

Calibration files belong to their manufacturers. Only add dumps you have the right to use.
