# Sound layers: physical basis and status

The procedural sound is a set of layers added under the exhaust. Each layer is now driven by the engine's
geometry, running state or a per-preset hardware field instead of a single hardcoded number. Defaults are
documented estimates; a preset can override any field.

## Layers

| Layer | Physical source | Formula / behaviour | Status |
|---|---|---|---|
| Valvetrain | Poppet valve seat impact and cam-chain rattle | Clicks at the actual intake/exhaust open and close angles, per cylinder, from `SoundContext.cylinder_phase_deg`; closing louder than opening. Chain rattle remains a separate texture. | Formula implemented; per-bike chain tension is not measured |
| Mechanical | Primary gear mesh, bearing/structure rumble, 2nd-order torsional harmonic | Mesh `rpm/60 * primary_crank_teeth`; fixed 400 Hz structure mode excited by rpm-scaled noise; primary whine has a load floor. | ZX25R uses 30T (87/30); other tooth counts are defaults |
| Driveline | Gearbox mesh, chain link impacts, gear-change clunk, dry-clutch rattle | Gear mesh `(rpm/primary_ratio)/60 * gearbox_input_teeth`; chain `wheel_rps * rear_sprocket_teeth`; rattle only when `dry_clutch`. | Tooth counts and clutch type are defaults unless the preset sets them |
| Turbo | Compressor blade-pass tone, wastegate flutter, diverter blow-off | `compressor_speed_rpm/60 * turbo_blade_count`; boost sets the level. Only for a turbo, not a blower. | Uses the simulated shaft speed; map-less engines use a documented fallback |
| Supercharger | Roots lobe mesh or centrifugal impeller blade pass, plus drive-gear mesh | Roots `rpm/60 * drive_ratio * lobes`; centrifugal `rpm/60 * drive_ratio * blades`; optional two-speed shift and gear tone. | H2R is centrifugal, two-speed (drive ratios estimated); no wastegate/blow-off |
| Starter | Commutator segment brush ring, pinion rattle, compression modulation, relay click | Segment rate `rpm/60 * starter_reduction * starter_segments`; one pinion burst per crank turn; compression cycles per cylinder. | Reduction and segment count are per-spec; defaults remain estimates |
| Dynamo | Alternator rotor pole/slot passing | `rpm/60 * alternator_drive_ratio * alternator_poles` | Default is crank-mounted 1:1, 12 poles; per-bike poles are estimates |
| Knock | Bore-direction combustion resonance | `f1 = 900000 / (PI * 0.5 * bore_mm)` Hz; `f2 = 1.58 * f1`; per-engine override. | 50 mm ZX25R ~11.46 kHz; 81 mm Panigale ~7.07 kHz |
| Electric compressor | Electric compressor blade pass | `compressor_speed_rpm/60 * compressor_blade_count` in `EngineSound`; load-based pitch is only a fallback. | Uses the simulated shaft speed |

## Per-engine fields

`EngineSpec` adds `primary_crank_teeth`, `gearbox_input_teeth`, `rear_sprocket_teeth`,
`alternator_drive_ratio`, `alternator_poles`, `starter_reduction`, `starter_segments`,
`turbo_blade_count`, `compressor_blade_count`, `supercharger_type`, `supercharger_drive_ratio`,
`supercharger_high_drive_ratio`, `supercharger_shift_rpm`, `supercharger_lobes`,
`supercharger_blades`, `supercharger_gear_teeth`, `dry_clutch` and
`knock_frequency_hz`. They are optional; defaults preserve the old sound except where a formula was
clearly wrong.

## Sources

- Gear-mesh frequency is tooth count times shaft speed: [OSTI, planetary gear vibration](https://www.osti.gov/biblio/7368821).
- Knock frequency baseline `900/(pi * 0.5 * bore_mm)` kHz: [HP Academy](https://www.hpacademy.com/forum/webinar-questions/show/083-understanding-knock-1), [JP2006022648A](https://patents.google.com/patent/JP2006022648A/en).
- Turbo blade-pass order: [US8696316](https://patentimages.storage.googleapis.com/b2/50/9f/1e2e8c8dae27a2/US8696316.pdf).
- Alternator pole/slot order: [US6424073](https://patentimages.storage.googleapis.com/45/ae/02/c8ef223f17a21a/US6424073.pdf).
- Valve event timing comes from the EngineSpec cam fields, the same ones the cylinder model uses.


## Exhaust body

The convolution impulse response is no longer shared between stock bikes. `EngineSound._load_ir()` takes the
recorded base (`mild_exhaust.wav` with a muffler, `sharp_01.wav` without) and runs it through
`ExhaustIr.modify()`, which adds early reflections, quarter-wave pipe resonances and a displacement-dependent
diffuse tail from the actual `ExhaustLayout` and engine spec. The result is cached by base path plus a full
pipe-geometry/spec fingerprint.

This is a geometry-derived body, not a measured impulse response. A measured per-bike IR still wins through
`EngineSpec.exhaust_ir_path`. Per-engine exhaust bodies are verified by
`tests/unit/audio/exhaust_ir_test.gd` and the CBR150R/ZX25R/R1M exhaust-only renders in
`tools/diagnostics/out/audio/`.

## Known estimates

The following are not measured for each bike and should be replaced when service data is available:
primary and gearbox tooth counts, rear sprocket teeth, alternator poles, starter reduction and segment
count, turbo blade count, H2R supercharger drive ratios, and the layer mix gains. The mix is still tuned on
the R1M; per-layer reference recordings are needed before changing the gains further.
