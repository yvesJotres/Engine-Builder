# Adding an engine preset

Each engine is one JSON file in `assets/engines/`. `scripts/presets/presets.gd` loads every `.json` in that folder at startup, so a new file is enough to register a new engine. The file name without `.json` becomes the preset's ID.

## Required sections

Every file needs these six top-level keys. `presets.gd` rejects the file without them.

| Section | Holds |
|---|---|
| `display_name` | Name shown in the launcher and panel |
| `geometry` | Cylinders, bore, stroke, rod ratio, layout, firing angles, masses |
| `valvetrain` | Cam timing, lift, duration, valve sizes |
| `drivetrain` | Redline, gears, final drive, idle target, fuel and header |
| `ecu` | `binary_path` (see [ECU binaries](ecu_binaries.md)) |
| `metadata` | `source`, `year`, `region`, `notes` |

Sections are flattened into one dictionary, so keys must be unique across sections.

## Checks the loader makes

- `geometry` must have `cylinders` and `displacement_cc`.
- `geometry.fire_deg` must have one entry per cylinder.
- `drivetrain.gear_ratios` must be an array.
- `ecu.binary_path` must be present. It can be an empty string.

## Optional features

Fitted hardware is set in `drivetrain`:

- Quickshifter: `has_quickshifter`, `quickshifter`, `quickshifter_cut_time`, `quickshifter_min_rpm`.
- Launch control: `has_launch_control`, `launch_control`, `launch_rpm`, `launch_throttle`, `launch_speed_kmh`.
- ABS and traction control: `has_abs`, `has_traction_control`.

`has_*` says the bike is fitted with the hardware. The rider switch (`quickshifter`, etc.) only works when `has_*` is true. The control panel shows a switch only for fitted hardware.

ABS/traction-control availability is recorded even while their switches are hidden: independent wheel-slip intervention is not implemented yet. `ControlPanel.WHEEL_AIDS_AVAILABLE` keeps those inert switches unavailable.

## Online dyno references

`assets/dyno/<preset_id>.json` can supply an independently measured rear-wheel benchmark for the dyno screen. The 2020 European CBR1000RR-R SP uses BSD/BikeSocial's UK stock base RR-R powertrain measurement; the tester states that the SP has the same engine.

The view can switch between original crank results and an explicitly estimated rear-wheel comparison using the simulator's existing drivetrain efficiency. References never feed the engine solver. The benchmark stores its measurement basis, correction convention, source URL, exact reported peaks and approximate chart samples. Both peak and curve errors remain visible; a close power peak alone does not count as a match. Export presets explicitly include these JSON files.

The DIN overlay normalizes the model's actual fixed dry-air conditions (300 K, 101325 Pa) to 20 C / 1013 mbar. It does not use editable weather labels as though they changed the cylinder physics. This display correction leaves crank measurements unchanged. The automatic multi-gear road sweep is not a reproduction of the reference's fourth-gear roller protocol.

## Example

Start from an existing file with the same layout, such as `assets/engines/honda_cbr250rr.json`, and change the values. For a variant of an existing bike, copy its file and change only what differs. `honda_cbr250rr_sp_qs.json` is an example: it changes the compression ratio and turns the quickshifter on.

## Checking a new preset

1. Boot the game headless: `godot --headless --path . --quit-after 120`. Any `Preset validation failed` line means the file was rejected.
2. Run `tests/unit/controls/panel_defaults_test.gd`. It checks that the control panel's values match each preset and that every preset validates.
3. Run `tests/unit/test_engine.gd` (see [CONTRIBUTING.md](../CONTRIBUTING.md)).
