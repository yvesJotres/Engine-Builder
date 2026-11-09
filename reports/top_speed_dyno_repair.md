# Top-speed and dyno repair

Verified against the Godot source project. This repair corrects drivetrain/load and measurement errors; it does not certify every engine's torque/power model against a real vehicle.

## Changes

- Both four-stroke and two-stroke drivetrains now solve clutch transfer against engine inertia and wheel/vehicle inertia together, retaining finite clutch compliance, torque capacity and directional driveline efficiency. Explicit clutch-capacity settings are now honoured.
- Roller mode no longer receives road aerodynamic/rolling resistance or road-speed ram-air pressure. The configured roller brake load still opposes motion.
- Complete-cycle accumulation retains the remainder across boundaries. Four-strokes use 720 degrees and two-strokes use 360 degrees; cycle mean RPM accompanies each new cycle.
- Dyno bins accept each completed cycle once, rather than repeatedly sampling a stale cycle result at newer instantaneous RPM. Sample counts now represent independent cycles.
- Starting the test from first gear no longer hangs while trying to downshift to neutral.
- Top gear can continue to the actual limiter or speed plateau instead of ending at the lower-gear shift fraction. It has a bounded 120-second simulated-time limit; a timeout is not labelled a verified top speed.
- Results/export distinguish road and roller speed. The UI calls a stopped/incomplete measurement the highest recorded speed, rather than asserting a settled road top speed.
- Saved comparison curves are associated with the library vehicle ID. An unrelated or unidentified legacy curve is not silently overlaid on another bike.
- Added independent measurement, coupling-energy, start-from-first, reference isolation and roller-load regressions; dyno integration/UI/load checks are now part of the publication gate.

## Source measurements

The completed source-UI CBR250RR run reached **168.37 km/h in sixth**, ending on a speed plateau, with 44 populated curve bins. Its reported simulated crank peak is still about **47.35 hp**, which exceeds the manufacturer's reference; this repair does not resolve that engine calibration/model discrepancy.

Other bounded headless road sweeps completed for CBR150R, MT-07, ZX-25R and R1M. Their achievable simulated speed continues to depend on the engine power curve, drag, gearing and mass. No hard-coded speed cap or power multiplier was introduced to force a published road-test result.

## Verification and remaining failure

- CBR150R six-gear integration, CBR250RR/MT-07/ZX-25R/R1M road sweeps completed.
- Clutch energy/stability, roller brake-load response, cycle/neutral-start regression, source dyno UI and CSV/reference tests passed.
- Native/GDScript comparison passed all 600 frames for CBR150R, ZX-25R and Panigale V4 without reducing test thresholds.
- The RD350 automatic sweep still fails because its engine stalls during startup before recording any curve. Its two-stroke cycle reporting is corrected, but a full RD350 sweep remains unverified.
- Full real-world power and acceleration acceptance remains tracked in the separate engine accuracy investigation.

Source result: `build/dyno_cbr_repaired.json`. Source UI capture: `tools/diagnostics/out/dyno_repaired.png`. The capture runs many simulated frames per rendered frame and is not an FPS benchmark.
