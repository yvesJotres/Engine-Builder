# Engine Builder

**Real-time engine simulation and dyno in Godot 4.7**

A physically grounded engine simulator with live 3D visualization, automatic dyno testing, and offline audio rendering. Built for motorcycles but extensible to cars.

---

## What It Does

- **Crank-angle gas simulation** — each cylinder runs its own 4-stroke cycle at its firing angle, with intake/exhaust flow, heat transfer, combustion, and knock.
- **Live 3D engine** — crankshaft, pistons, rods, valves, camshafts, throttle bodies, exhaust ports drawn from the same geometry the physics uses.
- **Drivetrain** — clutch (with slipper), gearbox, final drive, wheel inertia, aero drag, rolling resistance.
- **Automatic dyno test** — starts the engine, takes up the clutch in 1st, runs every gear to redline, shifts up, outputs torque/power curves with SAE J1349 correction, per-gear peaks, BSFC, λ, EGT.
- **Audio synthesis** — blowdown + intake flow → 1D pipe propagation → convolution with real exhaust impulse responses (from [engine-sim](https://github.com/AngeTheGreat/engine-sim)). Offline render at 1/3600 s physics step ignores real-time caps.
- **Engine presets** — 11 bundled bikes (CBR150R, ZX-25R/SE, Panigale V4, MT-07, YZF-R1M, Bugatti Centodieci, Honda V3R, CBR250RR, TRX520, AMG M276 variants) loaded from JSON.
- **Full control panel** — every parameter editable live: bore, stroke, cams, boost, fuel, compression, gearbox, ECU maps, quickshifter, launch control, slipper clutch.
- **Build save/load** — custom builds stored locally (`user://engine_builds.cfg`).
- **Patch/OTA system** — `Patcher` autoload downloads signed patches from a server; `bootstrap.tscn` loads the launcher first to mount patches before the game scene.

---

## Quick Start

### Requirements
- Godot 4.7 (Forward+ renderer)
- Desktop (Windows/Linux/macOS) or Android

### Run from Editor
```bash
# Open project in Godot 4.7 and press F5
# Or from terminal:
godot --path D:/Projects/Engine\ Builder
```

### Controls
| Input | Action |
|-------|--------|
| `W` / `↑` | Throttle / starter crank |
| `S` / `↓` | Close throttle |
| `Shift` | Pull clutch fully |
| `Q` / `E` | Downshift / upshift |
| `B` | Brake |
| `K` | Toggle kill switch |
| `Space` / `Esc` | Pause |
| Touch | On-screen throttle/clutch/brake/shift/starter |

---

## Project Structure

```
scripts/
├── app/                    # Single-instance lock, bootstrap
├── bootstrap.gd            # Mounts patch, launches launcher.tscn
├── main.gd                 # Coordinator: scene, physics loop, input, UI wiring
├── controls/
│   ├── control_panel.gd    # Left panel: kill switch, presets, 5 sections, dyno/render buttons, build save/load
│   └── touch_controls.gd   # Mobile on-screen controls
├── drivetrain/             # Clutch, gearbox, sprocket, car_model, drivetrain
├── dyno/
│   ├── dyno_test.gd        # Automatic dyno state machine (IDLE→START→WARM→CLUTCH→TAKEUP→PULL→UPSHIFT→DONE)
│   ├── dyno_view.gd        # Live curve overlay while test runs
│   └── dyno_graph.gd       # Graph drawing
├── ecu/                    # ECU binary parser, ignition/fuel maps, quickshifter, launch control
├── engine/
│   ├── cylinder.gd         # Crank-angle gas model: intake, compression, combustion, exhaust, heat, knock
│   ├── engine_sim.gd       # Whole-bike physics: N cylinders + intake + exhaust + clutch + drivetrain
│   ├── engine_model.gd     # 3D visualization built from spec (crank, pistons, rods, valves, cams, runners, throttle)
│   ├── engine_spec.gd      # Resource: all tunable parameters + validation + derived quantities
│   ├── engine_sound.gd     # Audio: convolution with IR, intake/exhaust flow, backfires
│   ├── engine_library.gd   # Fetches preset JSON from server
│   ├── presets.gd          # Loads assets/engines/*.json at startup
│   ├── firing_orders.gd    # Crank pin angles per layout (inline, V, W, crossplane, T-plane, custom)
│   └── presets/            # Per-bike preset scripts (apply preset data to spec)
├── exhaust/
│   ├── exhaust.gd          # Visual exhaust pipes from layout
│   ├── exhaust_gas.gd      # 1D pipe solver (method of characteristics) for offline audio
│   └── exhaust_layout.gd   # Builds pipe network from spec + engine model ports
├── fuel_system/            # Fuel tank, line, pump
├── ignition/               # ECU spark logic
├── instruments/            # HUD readouts
├── intake/                 # EngineAir: manifold, throttle, compressor, boost
├── render/
│   ├── audio_renderer.gd   # Offline WAV export at highest physics rate
│   ├── motion_blur.gd      # Camera motion blur
│   └── wav_writer.gd       # WAV file writer
├── ui/                     # FPS overlay, frame stats, engine stats panel
├── world/                  # Ground plane
└── updates/
    └── patcher.gd          # OTA patch download, verify, mount

scenes/
├── bootstrap.tscn          # Entry point, changes to launcher/main after patch
├── launcher.tscn           # Update check, PLAY button
├── main.tscn               # Game scene (root = main.gd)
└── pause_menu.tscn         # Quality/accuracy/audio/HUD toggles

assets/
├── engines/                # 11 preset JSON files
└── ir/                     # Exhaust impulse responses (MIT, from engine-sim)
    ├── mild_exhaust.wav
    ├── sharp_01.wav
    └── minimal_muffling_03.wav
```

---

## Engine Simulation Details

### Cylinder Model (`cylinder.gd`)
- **Intake flow** — orifice equation through valve curtain area, runner inertia, manifold pressure
- **Compression** — polytropic with heat transfer to walls (Woschni correlation)
- **Combustion** — Wiebe function (two-zone: burned/unburned), calibrated to burn 10–90% in ~30–40°
- **Exhaust blowdown** — choked/unchoked flow through valve curtain into exhaust port
- **Knock** — advance past fuel/compression limit loses torque and increments knock counter
- **E85** — higher octane + charge cooling (latent heat) modeled explicitly
- **Valve lift** — half-sine, cam-card (flat-taper), or custom table; ramps at 0.050″ seat

### Whole-Bike Physics (`engine_sim.gd`)
- **Crank dynamics** — implicit clutch spring (stable at any step size), friction (rings, bearings, oil temp)
- **Clutch** — wet multi-plate, lever position → grip (friction zone), slipper clutch on overrun
- **Gearbox** — 6-speed, primary + final drive, 93% efficiency
- **Vehicle** — aero drag (CdA), rolling resistance, brake force, wheel rotational inertia
- **Starter** — torque fades to zero at ~900 RPM
- **Fluids** — oil/coolant warm-up from combustion heat
- **ECU** — idle spark trim, power modes (F/M/L), quickshifter cut, launch control

### Dyno Test (`dyno_test.gd`)
State machine phases:
1. **START** — starter on, wait for engine to hold >1000 RPM
2. **WARM** — 1.5 s at idle
3. **CLUTCH** — pull clutch, select 1st
4. **TAKEUP** — feed clutch out at closed throttle, keep RPM near idle
5. **PULL** — WOT, record cycle-mean torque every 250 RPM bin
6. **UPSHIFT** — throttle shut, clutch open, shift, clutch home, repeat
7. **DONE** — all gears done or top gear plateau

Output: torque/power curves (raw + SAE J1349 corrected), peak torque/power per gear, BSFC, λ, EGT, intake pressure, torque std dev.

---

## Audio System

**Live** — valve flow samples → delay lines per primary pipe → simple attenuation → convolution with selected IR.

**Offline Render** (`audio_renderer.gd`) — runs the 1D pipe solver (`exhaust_gas.gd`) at 1/3600 s physics step, exports 44.1 kHz 16-bit WAV (default 10 s @ WOT).

IR sources (MIT license): `mild_exhaust.wav`, `sharp_01.wav`, `minimal_muffling_03.wav` from [engine-sim](https://github.com/AngeTheGreat/engine-sim/tree/main/sound-library).

---

## Presets (JSON in `assets/engines/`)

Each preset defines:
- **geometry** — cylinders, bore, stroke, layout, bank angle, crank pins, compression, rod ratio
- **valvetrain** — durations, centres, lifts, valve sizes, runner length, cam profiles
- **drivetrain** — gear ratios, primary/final, vehicle mass, wheel specs
- **ecu** — redline, idle, flywheel, power modes, quickshifter, launch, slipper, binary path
- **metadata** — display name, source notes

Built-in:
| ID | Display Name | Layout | Cylinders | Displacement |
|----|--------------|--------|-----------|--------------|
| `honda_cbr150r` | Honda CBR150R (K45R) | inline | 1 | 149 cc |
| `kawasaki_zx25r` | Kawasaki Ninja ZX-25R | inline | 4 | 249 cc |
| `kawasaki_zx25r_se` | Kawasaki Ninja ZX-25R SE | inline | 4 | 249 cc |
| `ducati_panigale_v4` | Ducati Panigale V4 | V | 4 | 1103 cc |
| `yamaha_mt07` | Yamaha MT-07 | inline | 2 | 689 cc |
| `yamaha_yzf_r1m` | Yamaha YZF-R1M | inline | 4 | 998 cc |
| `bugatti_centodieci` | Bugatti Centodieci | W | 16 | 7993 cc |
| `honda_cbr250rr` | Honda CBR250RR | inline | 2 | 249 cc |
| `honda_trx520` | Honda TRX520 | inline | 1 | 518 cc |
| `honda_v3r900` | Honda V3R 900 (est.) | V | 3 | 900 cc |
| `amg_m276_v6` | AMG M276 DE30 LA | V | 6 | 2996 cc |
| `amg_v6_w17` | AMG V6 W17 (est.) | V | 6 | ~3000 cc |
| `m276_de30la` | M276 DE30 LA | V | 6 | 2996 cc |

Add your own: drop a `.json` in `assets/engines/` matching `schema.json`.

---

## Building & Export

### Desktop
```bash
# In Godot: Project → Export → add "Windows Desktop" / "Linux/X11" / "macOS" preset → Export Project
# Or CLI:
godot --headless --path D:/Projects/Engine\ Builder --export-release "Windows Desktop" build/EngineBuilder.exe
```

### Android
- Set `export_presets.cfg` Android keystore
- `APK_VERSION_CODE` in `bootstrap.gd` must match `version/code` in `export_presets.cfg`
- Export "Android" preset

### Patch Server
- `server/` contains a Go patch server (signs with Ed25519)
- `config/server.local.cfg` (gitignored) holds the private key
- `Patcher` autoload polls `config/server.cfg` for `patch_url` and `patch_pubkey`

---

## Third-Party Licenses

| Asset | Source | License |
|-------|--------|---------|
| Exhaust IRs (`mild_exhaust.wav`, `sharp_01.wav`, `minimal_muffling_03.wav`) | [engine-sim](https://github.com/AngeTheGreat/engine-sim) | MIT |
| Godot Engine | [godotengine/godot](https://github.com/godotengine/godot) | MIT |
| godot-cpp (GDExtension) | [godotengine/godot-cpp](https://github.com/godotengine/godot-cpp) | MIT |

See [THIRD_PARTY.md](THIRD_PARTY.md) for details.

---

## Development

### Code Style
- GDScript, Godot 4.7, Forward+
- Class names via `class_name` (no `extends Resource` boilerplate in every file)
- Physics at fixed rates (1/1200 to 1/7200 s) set from pause menu
- No external deps beyond Godot stdlib

### Key Files to Understand
| File | Role |
|------|------|
| `scripts/main.gd` | Frame loop, input, coord all systems |
| `scripts/engine/engine_sim.gd` | Physics step, cylinder array, clutch, drivetrain |
| `scripts/engine/cylinder.gd` | Per-cylinder gas dynamics |
| `scripts/engine/engine_model.gd` | 3D engine built from spec |
| `scripts/controls/control_panel.gd` | Full parameter UI |
| `scripts/dyno/dyno_test.gd` | Automatic dyno state machine |
| `scripts/render/audio_renderer.gd` | Offline WAV export |
| `scripts/updates/patcher.gd` | OTA patch client |

### Adding a Preset
1. Create `assets/engines/my_bike.json` (see existing files for schema)
2. Restart editor — `Presets._build_presets()` loads it automatically
3. Appears in control panel dropdown

### Running Tests
```bash
# From project root
godot --headless --path . --script tests/run_tests.gd
```

---

## Roadmap / Known Limits

- [ ] Car mode drivetrain visualization (currently only bike chain/drivetrain drawn)
- [ ] Turbo lag model (compressor spool is first-order)
- [ ] Turbo compressor map (currently fixed pressure ratio)
- [ ] Water/methanol injection
- [ ] Nitrous oxide
- [ ] More ECU binary formats (currently parses simple K45R-like bins)
- [ ] Multiplayer / shared dyno sessions

---

## Credits

- **Engine simulation architecture** — heavily inspired by [engine-sim](https://github.com/AngeTheGreat/engine-sim) (Ange Yaghi)
- **Exhaust impulse responses** — engine-sim sound library (MIT)
- **Godot** — Godot Engine contributors (MIT)
- **Firing order math** — adapted from engine-sim's wiring tables

---

## License

MIT License — see [LICENSE](LICENSE) (add one if you want; currently no LICENSE file in repo).

---

*Built with Godot 4.7. If you use this in a project, a mention is appreciated but not required.*