# R1M source repair — 9 November 2026

The restrictive intake and undersized clutch have been corrected. The source game now records **300.08 km/h**, **191.19 mechanical hp (142.57 kW)** at 14,071 rpm, and **101.78 Nm** at 12,878 rpm in its automatic road sweep. These are simulation results, not a real-world accuracy signoff. The installed game was not used.

## What changed and why

- The R1M inherited 6/5 mm valve lift and 240/230-degree durations from the generic small single. It now uses a documented same-generation valve-data proxy: 9.7/8.8 mm and 284/280 degrees. Yamaha's standard cam centres, 108 degrees intake ATDC and 110 degrees exhaust BTDC, become simulation phases 468/250.
- Every cylinder previously used a fixed 6.6 cm² runner, equivalent to approximately 29 mm diameter, regardless of its throttle size. Runner equivalent bore now reaches both the GDScript and C++ cylinder solvers, saved builds, preset selection and the cylinder configuration cache. The R1M uses an explicitly estimated 45 mm equivalent bore, based on its throttle bore. Legacy engines keep their previous runner area.
- Large runners exposed numerical damping at the old 10–20-degree integration limit. They now use at most one crank degree per cylinder integration step. Both implementations use the same limit.
- The generic clutch fallback gave the 998 cc R1M only 99.8 Nm of crank-side holding capacity, below its published 112.4 Nm engine torque. Its explicit **200 Nm holding-capacity estimate** eliminates sustained high-speed clutch slip. This value is not a measured clutch specification and does not multiply engine torque or power.
- The 0.40 m² generic naked-bike drag estimate became **0.35 m² for a tucked rider**, using an older-R1 CFD example as a proxy. This is not a verified 2015 R1M aerodynamic measurement.
- The preset's market label now matches the unrestricted Europe reference. A preset revision prevents old server/cache copies from restoring the previous cam settings. Saved custom builds retain their explicitly saved cam settings.
- Old native libraries fall back to GDScript for the new runner geometry. The rebuilt native library also accepts the previous 26-value configuration format.

Confirmed bore, stroke, compression, valve diameters, mass, tyre sizes, gearing and manufacturer output references were not adjusted to force a pass. No power or top-speed multiplier/cap was added.

## Measured before/after

All power figures below are uncorrected estimated crank output. Do not compare these directly with rear-wheel dyno figures.

| Check | Before | After |
|---|---:|---:|
| Fixed-speed power at 13,500 rpm, 7,200 Hz | 94.01 kW | 142.41 kW |
| Fixed-speed torque at 11,500 rpm, 7,200 Hz | 78.43 Nm | 100.46 Nm |
| Automatic road sweep peak power | 124.60 hp | 191.19 hp |
| Highest speed during six-gear road sweep | approximately 248 km/h | 300.08 km/h, fifth gear |
| Sixth-gear speed | approximately 248 km/h | 293.18 km/h |
| Final clutch slip, corrected source run | not captured | −3.4 rpm instantaneous |

The road sweep includes the intake, cam, numerical-step, clutch and drag-estimate changes together. Its speed improvement cannot be attributed solely to a corrected physics calculation. The sixth-gear result remains lower than fifth: the current torque curve and drag model do not sustain the higher gear at the same speed. No road accuracy pass is claimed.

## Numerical checks and remaining accuracy failures

The fixed-speed audit holds the crank speed independently, warms for one simulated second and integrates 32 complete engine cycles. Fuel is RON95; nominal inlet conditions are 101,325 Pa and 300 K with modelled charge cooling; initial oil/coolant are 100/90 °C. The road model adds a 75 kg rider to the 200 kg curb mass, uses nominal 200/55-17 rear radius, and has no wind or gradient. The game records fuel consumption during the sweep.

| Outer simulation rate | Power at 13,500 rpm | Torque at 11,500 rpm |
|---|---:|---:|
| 2,400 Hz, automatic-sweep rate | 140.20 kW | 99.09 Nm |
| 7,200 Hz | 142.41 kW | 100.46 Nm |
| 14,400 Hz | 143.93 kW | 101.91 Nm |
| 28,800 Hz | 144.26 kW | 102.02 Nm |

14,400 to 28,800 Hz changes rated-point power by **0.22%** and torque by **0.11%**. The normal 2,400 Hz rate still underestimates those fine-rate results by approximately **2.8%**. A controlled, prescribed-crank R1 cylinder test compares every torque step over 20 cycles at both rated speeds; native and script agree within 1e-6 relative tolerance, including final gas/runner states.

Yamaha's unrestricted 2015 Europe reference is **147.1 kW at 13,500 rpm and 112.4 Nm at 11,500 rpm**. At 28,800 Hz the corresponding errors are −1.9% power and −9.2% torque. At the normal sweep rate they are −4.7% power and −11.8% torque. **The user's 3% power / 5% torque contract is not yet met.** The 7,200 Hz steady sweep still rises to its highest measured power at 14,500 rpm, outside the 600-rpm peak-location tolerance. The accelerating road sweep peaks earlier; it is not a substitute for the steady curve.

Unresolved physical inputs include the exact 2015 cam lift trace and checking-height ramps, measured runner taper/length/port volume, YCC-I switching, and verified 2015 drag data. The 2017 APE valve data is a same-generation proxy, not a verified 2015 cam card. The model approximates those durations as seat events with generic ramps; no race cam was substituted. The fixed 0.25 m runner and 50 cc effective port volume remain estimates. Further torque calibration needs evidence and model work, rather than another output scalar.

An exploratory R1 whole-engine native/script startup comparison drifted beyond 1e-6 relative tolerance after about 85 rendered frames with the intermediate two-degree solver. Mean high-rev RPM remained within the existing tolerance. The pre-existing three-bike transient regression thresholds were not reduced; they still pass all 600 frames. The new R1 test prescribes the crank trajectory to isolate cylinder mathematics from crank/idle-controller feedback. Identical unrestricted transient R1 trajectories are not claimed.

## Verification

- Source main scene: complete six-gear road sweep, 49 RPM bins from 4,090 independent cycles; result JSON and CSV written under `build/dyno_yamaha_yzf_r1m_repaired.*`. Screenshot: `tools/diagnostics/out/dyno_yamaha_yzf_r1m_repaired.png`.
- Bounded real-time source main-scene run at a 60 FPS cap: idle 60.01 FPS, high rev 60.00 FPS at approximately 14,488 rpm. High-rev 95th-percentile frame time 17.00 ms; game-update time 4.74 ms. One audio buffer-starvation flag occurred during idle sampling; none during the three-second high-rev sample. These short windows are not an Android or long-duration audio signoff.
- New R1 tests pass for native/script prescribed-cycle agreement, legacy area and 26-value native configuration fallback, runner cache invalidation and clutch transmission of published torque into a high-inertia roller. Closed-cylinder adiabatic energy checks pass on both implementations with zero measured residual.
- Panel defaults, build save/load and preset cache revision tests pass. Existing CBR150R, ZX-25R and Panigale native/script transient tests pass 600 frames each. Full 28-test publication gate and server tests pass; the gate was executed without publishing.
- Windows debug/release DLLs and Android arm64 release library rebuilt successfully. Android device runtime, acceleration accuracy and long-duration manual driving remain unverified.
- No commit, release installation or publication was performed.

## Sources

- [Yamaha 2015 Europe R1/R1M launch specifications](https://global.yamaha-motor.com/news/2014/1104/yzf-r1.html): reference power/torque, geometry, R1M mass and tyres.
- [Yamaha technical paper on the 2015 R1](https://global.yamaha-motor.com/jp/design_technology/technical/product/pdf/browse/50ss02.pdf): finger-rocker valvetrain, intake/valve design and development intent.
- [Yamaha 2016 kit manual, standard engine specifications](https://www.manualslib.com/manual/1176112/Yamaha-Yzf-R1.html?page=4): standard 108/110-degree cam centres, distinguished from race-kit settings.
- [APE same-generation 2017 R1 valve data](https://www.aperaceparts.com/tech/2017yzfr1_1.html): valve lift, duration, measuring heights and throttle size. Its exhaust opening/closing headings are evidently reversed; the 70/30-degree events and 280-degree duration are consistent with the Yamaha 110-degree centre. No additional event values were taken from those headings.
- [Limebeer and Sharma, Design of a Novel Aerodynamically Efficient Motorcycle, BMD2010 abstract p48](https://www.bicycle.tudelft.nl/ProceedingsBMD2010/BookAbstractsBMD2010.pdf): older R1/rider CFD example, CdA 0.35 m² with rider prone. Used as an aerodynamic proxy only.
