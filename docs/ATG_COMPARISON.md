# Comparison: ATG engine-sim vs Engine Builder

Sources: ATG engine-sim at `D:\Projects\ATG Source\engine-sim` (C++), read by three read-only agents and spot-checked by the lead. Our project at `D:\Projects\Engine Builder`. Nothing was run for the ATG side, and no audio was compared by ear.

## 1. Architecture

|| | ATG engine-sim | Engine Builder |
|---|---|---|---|
| Language | C++ | GDScript, with a native C++ cylinder kernel (`cylinder_kernel.cpp`) |
| Physics step | 10 kHz default (scripts override to 15 to 20 kHz), with 8 fluid sub-steps | 1/1200 s (sim), with adaptive sub-steps inside the cylinder |
| Exhaust | Lumped gas volumes, no wave model | 1D Euler solver with HLLE fluxes, 0.24 m cells |
| Audio | Synthesis at 10 kHz, convolved with a recorded impulse response | Procedural layers plus a convolution, with exhaust pulse shaping (in `ExhaustSound`) |
| Audio rate | 44.1 kHz output, 1.9 kHz antialias before convolution | 44.1 kHz, convolution at the output rate over the whole recorded impulse response (219–266 ms), native (`AudioConvolver`). Before this change it was 16 kHz with 128 taps, i.e. the first 8 ms only |
| Platform | Windows-only build | Godot, runs on desktop and mobile |

## 2. Thermodynamics

**ATG engine-sim (`gas_system.cpp`, `combustion_chamber.cpp`)**
- Energy-based state: moles, kinetic energy, volume, momentum and composition. Pressure and temperature come from the energy.
- Flow between volumes uses isentropic orifice equations, with a flow-bench lookup for valve lift.
- Burn follows flame kinematics: a flame speed from a laminar burning-velocity fit and a turbulence lookup, a flame radius that grows to the bore, and an efficiency with random scatter.
- No wall heat-transfer code was found in the ATG `src`, `include` or `scripting` folders (checked again in the audit). An earlier note of a fixed 90 °C wall is not supported by that source.
- No Wiebe, CA50 or heat-release shaping anywhere in the repository (confirmed by search).
- Gas molar mass is constant (air), even though the products differ.

**Engine Builder (`cylinder.gd`, `cylinder_kernel.cpp`)**
- Mass, temperature, pressure and internal energy, with ideal gas and a variable heat capacity that moves from air toward burnt gas.
- Wiebe burn with a duration that depends on rpm, and a spark timing that sets CA50 near 10° ATDC.
- Woschni-form wall heat transfer from the cylinder state (pressure, temperature, gas velocity), with a fixed wall temperature of 420 K (estimate).
- Valve lift from cam profiles with check-lift ramps, orifice flow with Cd 0.7, and a lumped port and runner resonator.
- Overlap backflow, a fuel film on the port wall, misfire above λ 1.35, and backfire from unlit fuel in a hot port.

## 3. Where ours is stronger

1. **Calibratable combustion.** The Wiebe burn with CA10, CA50 and CA90 outputs can be tuned to a measured burn. ATG has no equivalent, so its burn can't be matched to data without new code.
2. **Explicit heat-release timing.** The burn is tied to crank angle, so ignition timing and knock have clear, testable effects.
3. **Wall heat transfer from gas state and gas motion.** Woschni form. ATG has no wall heat-transfer code, so there is nothing to compare.
4. **Energy accounting.** Our model keeps running energy totals for enthalpy in and out, wall loss and work, so the first law can be checked. We found no equivalent energy-balance check in ATG.
5. **Native kernel with a GDScript reference.** A test compares the two paths, which gives a way to catch porting errors.
6. **Sound layers.** Starter, dynamo, gear whine, valve train, driveline, knock, mechanical supercharger whine, and turbo, each with its own level control in the panel. ATG's audio is a single exhaust-driven path with noise and jitter.
7. **Exhaust drawing and sound share one pipe layout.** Changing the drawn pipe changes the sound.
8. **Offline and live consistency.** The lab and the game share the same audio code path.
9. **Cross-platform.** Godot runs on phones and desktop. ATG builds on Windows only.

## 4. Where ours is weaker

1. ~~**The impulse response plays back about four times too fast.**~~ **Fixed, and then the truncation was fixed too.** `engine_sound.gd` now convolves at the output rate over the whole recording (up to `MAX_TAPS` 16,384 = 372 ms): every sample of the 219 ms muffler IR is a tap, so neither the rate nor the tail is squeezed. The convolution moved to `gdextension/src/audio_convolver.cpp`, because a full-length FIR is not affordable in GDScript. Measured on the CBR250RR rev render: RMS −13.7 → −13.1 dBFS, 200–500 Hz share +0.6 points (fuller body), no other band moved by more than 0.02 points, and the 8 kHz ceiling is gone.
2. **The exhaust solver is too coarse.** 0.24 m cells smear the blowdown kick. Finer cells sharpen it but cost too much for four cylinders (1.72× real time at 0.05 m).
3. **Backpressure is off in the default live path.** Four-stroke engines use a delay-line approximation unless a preset enables the pipe solver, so the live sound has no backpressure.
4. **Pipe padding and tailpipe lengths disagree with the delay-line lengths** (from the sim agent's report). Needs checking.
5. **The leveler couples layers to exhaust loudness.** Layers are summed before the leveler, so a knock or a clunk pulls the exhaust level down for about 50 ms.
6. ~~**The dead biquad costs CPU for nothing.**~~ **Gone.** The identity resonance cut is no longer in the tree; the only biquad left is the driveline band-pass, which does real work.
7. ~~**16 kHz box decimation aliases above 8 kHz.**~~ **Gone.** The body is no longer decimated: the convolver runs at the 44.1 kHz output rate, so there is no box filter and nothing folds down. A long IR is affordable because the loop is native and optimised (`audio_convolver.cpp` is built with /O2 even in Debug, so the editor and the game sound the same).
8. **Duplicated code.** GDScript and C++ versions of the cylinder model and exhaust solver are both maintained, and only the C++ cylinder kernel is built. `exhaust_gas.cpp` is not built.
9. **Many constants are marked "estimate".** Cd, wall temperature, 0.95 efficiency and CV_BURNT are unverified.
10. **Stale comments.** `mechanical_layer.gd` still describes a 1.5× partial that was removed. `starter_layer.gd` is marked as placeholder.

## 5. What ATG does better

1. **Flame physics.** The flame speed depends on turbulence, mixture, temperature and pressure, and misfires come out of the model. Ours uses a fixed burn shape.
2. **Gas dynamics at the valve.** Real isentropic flow with a choke limit, and a flow-bench lookup. Ours uses an orifice model with a single Cd.
3. **Friction.** A Stribeck-type friction model that is smooth through zero velocity. Ours uses a simpler model.
4. **Fluid sub-steps.** ATG runs the fluid at 8× the physics rate. We run adaptive sub-steps inside the cylinder.
5. **Audio timbre from recordings.** Each exhaust can use its own impulse response, which gives timbre cheaply and can match a real bike when the IR is correct. Ours does the same now (full-length IR at the output rate, weakness 1), so this is no longer an ATG advantage.
6. **Loudness stability.** Its leveler has a 30000 target and a gain cap, so the output stays stable.
7. **Scripting.** Engines are defined in a `.mr` script format with about 90 engine files, which is easier to extend than our preset JSON for large rosters.

## 6. What's good in ours, and what's bad

**Good**
- Calibrated, testable combustion with CA50 control.
- The layered sound design, with per-layer levels.
- The starter, dynamo, gear-whine, mechanical supercharger whine, and turbo models, which ATG doesn't have.
- The shared drawing and sound pipe layout.
- Cross-platform support.

**Bad**
- The impulse-response time compression (weakness 1), which is a likely bug.
- A coarse exhaust solver that rounds off the kick.
- Backpressure missing from the default live path.
- Duplicated C++ and GDScript code, with unverified constants.

## 7. Recommended next steps

Done since this comparison was written: the impulse-response rate and length (native convolver, full recording), the dead biquad, and the 16 kHz decimation.

1. **Confirm by ear.** The IR fix is measured but not yet listened to. Compare `tools/diagnostics/out/audio/cbr250rr_rev_base.wav` with `cbr250rr_rev_full.wav` and their spectrograms.
2. **Make the pipe solver the live default** (weakness 3). The blocker is the idle pressure it settles to (~45 kPa in the pipes); fix that before promising real backpressure in the live sound.
3. **Check the pipe padding and tailpipe lengths** against the delay-line lengths (weakness 4).
4. **Consider a flame-front burn option** as a port from `combustion_chamber.cpp`, behind a flag, to compare against Wiebe.
5. **Measure the real-time cost** of the native kernel with the pipe solver on a phone-class CPU before making the pipe the default.

## 8. Caveats

- ATG statements come from reading source, not from running it.
- Our IR finding comes from reading `engine_sound.gd`. It has not been confirmed by a render.
- Some ATG constants and paths were not verified (for example the `ir_lib` name mismatch in `cbr250rr.mr`, and whether `rand()` is seeded).