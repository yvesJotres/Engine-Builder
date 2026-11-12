# Agent Sync — Engine Builder

The shared board for the parallel agents. One file, newest entry at the top of each section. If two agents disagree
about an interface, the contract table at the bottom decides; if it is not there, the orchestrator decides and it gets
written down here in the same commit.

Architecture and work packages: [MULTI_AGENT_PLAN.md](MULTI_AGENT_PLAN.md). This file is only state and protocol.

---

## Trunk state (last updated 2026-11-12)

- `main` head: `9b12be8` — "gate: run_test.bat takes group flags, and the agent contract docs exist"
- Active branch: `feat/physics-natural-feel` — Woschni (gap 3) and orifice flow (gap 5) landed, both green.
- Gate: `run_test.bat` (see below). **Not green yet**, on purpose: the two reds are known work, not noise.
- Native extension: `gdextension/bin/libengine_sim.windows.template_{debug,release}.x86_64.dll` — rebuilt 2026-11-12.

**Parallelism note.** This machine has no subagent runner wired into the session, so the three work packages run
serially on their branches, one package per commit, orchestrator playing both roles. When a real parallel runner is
available, the branches and the ownership table below are already the right cut — nothing else needs to change.

### Known red, with the reason it is red

| Test | Why it is red | Owner / next step |
|---|---|---|
| `unit/drivetrain/shift_behavior_test.gd` | `gearbox_load` swings ±90 N m between firing pulses at 4,270 rpm (61.6 → −86.5 → −5.0, capacity 200 N m, unloaded threshold 16 N m), so the shift state machine sees "unloaded" at wide open and drops to neutral. | Orchestrator: cycle-mean `gearbox_load` in `_advance_driveline`. Do not encode the jump as the expected behaviour. |
| `integration/dyno/dyno_cbr250rr.gd` | 29.48 kW at 12,500 rpm against Honda's 28 kW factbook figure (+5.3%, gate is ±3%). **Not** the uncommitted header change: re-running with `header_primary_mm` back at the committed 42 mm gives the same 29.48 kW. A code bisect is impossible — the pre-checkpoint tree (`39df036`) does not run (see below) — so the sensitivity was measured instead: ±100% wall heat moves power by ~9% (25.20 N·m at 0, 23.07 at 1, 21.01 at 2) and the 1D pipe solver moves it 12% (26.55 kW on vs 30.20 off). The gap is model uncertainty around heat transfer and exhaust tuning, not one wrong constant. | Physics: needs a measured WOT cylinder-pressure trace (gap 6/7) or a sourced Woschni constant set. Any fix by scaling `wall_heat_scale` per bike is the fudge factor `GEMINI.md` 5 forbids. Gate stays at 28 kW. |

| `integration/dyno/dyno_regression_test.gd` | New gate (gap 14). Rear-wheel hp against the digitised curves, ±5 % mean / ±10 % worst. Corrected measurement (`sim.cycle_brake_torque`, cycle-averaged, not the last sub-step): CBR250RR SP **3.8 % (passes)**, Ninja 300 **12.4 %**, R1M **21.9 %**, CBR1000RR-R **23.5 %**. Shape: mid-range is within 4-8 % on every bike, the low end is too strong (+52…+69 % at 4000 rpm) and the litre top end too weak (−36 % at 13,900). VE measured 0.895 at 4000 rpm falling to 0.807 at 13,500 — a real engine climbs with rpm. | Physics: intake ram/resonance is missing or too weak at speed. Do not tune per bike. |

**No runnable baseline.** `39df036` (the commit before the checkpoint) cannot be run from a worktree: its scripts preload
`assets/3d/generated/drivetrain/tire_tread.gd`, which did not exist there, and reference `EngineSpec.PIN_RADIUS`,
`SHAFT_RADIUS`, `PIN_LENGTH` and `WEB_THICKNESS`, which it did not have. That is why the checkpoint's 221 files had to go
in as one commit, and it means code-level bisecting starts from `1b64243`, not before it.

Tooling for the open question: `tools/diagnostics/probe_cbr_power_sensitivity.gd` prints the 12,500 rpm hold at four
settings (shipped, no wall heat, double wall heat, 1D solver on).

Context for anyone tempted to close it by tuning: the Woschni source in `docs/papers/` (Qasemian and Rezaei 2020, §3.1)
measures the original correlation against a pressure trace and finds "an average of 13 percent" error in expansion
before re-fitting its constants for that engine. A 5 % power gap is inside that band, so the honest options are a
measured trace for this engine or a sourced, engine-specific constant set — not a scale factor. `woschni_validation_test`
now fails if `WOSCHNI_C1`/`_C1_GAS`/`_C2`/`WOSCHNI_H` drift from the published values, so a silent re-tune shows up in
the gate rather than in a dyno curve nobody re-reads.

Flaky, not fixed: `unit/engine/engine_stats_test.gd` failed once inside the full sweep and passes 3 of 3 alone; it
touches no file, clock or RNG.

Resolved 2026-11-12: `unit/engine/two_stroke_native_test.gd` — the native kernel now carries all five GDScript two-stroke
fixes (commit `6e50e2d`), 540 field comparisons across reed and piston paths, 0 problems.
`integration/dyno/dyno_cell_test.gd` — the pull compared one frame, whose firing phase outweighed a 200 N load; it now
compares the mean of the last half second (`3bc98c3`).

---

## The gate

```
run_test.bat                  full sweep (one Godot process per test, ~10 min)
run_test.bat --physics        engine/ exhaust/ intake/ sim/ dyno/
run_test.bat --ui             controls/ structure/ visual/
run_test.bat --drivetrain     drivetrain/ model/
run_test.bat --ecu            ecu/
run_test.bat --audio          audio/
run_test.bat <filter>         any raw TEST_FILTER, e.g. engine/woschni
```

Exit code 1 if any selected test fails. No `pause` when called with an argument, so a CI step or an agent can call it.
A merge to the integration branch requires the group you touched to be green, and **no new red anywhere**.

---

## Branches

| Branch | Agent | May touch |
|---|---|---|
| `feat/physics-natural-feel` | Physics | `scripts/engine/`, `scripts/ecu/`, `scripts/sim/`, `gdextension/src/*kernel*`, `gdextension/src/exhaust_gas.cpp`, `gdextension/src/intake_native.cpp` |
| `feat/geometry-natural-feel` | Geometry | `assets/engines/*.json`, `scripts/model/bike/`, `scripts/model/pipe/`, `assets/compressor_maps/` |
| `feat/uiux-natural-feel` | UIUX | `scripts/ui/`, `scenes/`, `tests/visual/` |
| `feat/natural-feel-v1` | Orchestrator | integration only |

Rules that exist because three agents broke them the last time this was attempted:

1. **One owner per native file.** `gdextension/src/` is Physics only. A second agent touching the C++ tree means the
   DLL has two possible parents and nothing can be bisected. Geometry work that needs a native change files it as a
   blocker instead.
2. **Rebuild before you test.** `--import` after adding a `class_name`, `gdextension/build/build_win.bat` after a `.cpp`
   change, then the gate. A stale DLL looks exactly like a logic bug.
3. **Tests cite a value from outside the code** (`[hand]`, `[table]`, `[closed]`, `[fig]`, `[meas]`, `[ind]`), per
   `docs/physics-validation.md`. A test that only proves the code equals itself does not count as a gate.
4. **No fudge factors** (`GEMINI.md` §5): no torque or power multipliers, no reference-curve lookups, no per-bike
   adjustment. If a preset cannot reach its dyno curve, the physics changes in a general way and gets a test.

---

## Interfaces (contracts)

Fill a row in the same commit that changes the signature. Format: `name — signature — owner — since`.

| Contract | Signature | Owner | Since |
|---|---|---|---|
| knock integral | `Cylinder.get_knock_integral() -> float` | Physics | planned |
| slip | `Wheel.get_slip() -> float`, `EngineSim.front_slip() / rear_slip()` | Physics | `d2cd57a` |
| boost | `IntakeNative.get_boost() -> float` | Physics | planned |
| burn rate | `signal burn_rate(deg_per_ms: float)` | UIUX | planned |
| exhaust flow to audio | `EngineSim.exhaust_mass_flow() -> float` (kg/s, all cylinders) | Physics | 2026-11-12 |
| layout key | `ExhaustLayout.build(spec, ports, crank, ground_y, axle)` | Geometry | current |

---

## Blockers

Newest first. Format: `date — agent — what — what it needs — who`.

- 2026-11-12 — orchestrator — **the two-stroke C++ port is written and compiles, but cannot be linked**: 5 Godot
  processes (the full sweep on PID 9640 plus its children, and two editor instances) hold
  `gdextension/bin/libengine_sim.windows.template_debug.x86_64.dll` open, so the linker fails with LNK1104. Needs the
  editor and any running sweep closed, then `gdextension\build_win.bat template_debug`, then
  `run_test.bat two_stroke_native`. The port is deliberately **not committed** until that test passes.
- 2026-11-12 — orchestrator — the gate now detects this class of blocker itself: `run_test.bat --check-dll` exits 1 when
  any `gdextension/src|include` file is newer than the debug DLL, and every normal run prints the warning.

- 2026-11-12 — orchestrator — `two_stroke_native_test` red because the native kernel is unported — needs the five
  GDScript fixes in `two_stroke_kernel.cpp` and a DLL rebuild — Physics.
- 2026-11-12 — orchestrator — `shift_behavior_test` red because `gearbox_load` alternates sign per firing pulse —
  needs a cycle-mean in `_advance_driveline`, not a test edit — orchestrator.

## Decisions

- 2026-11-12 — **gap 5 (orifice flow) closed.** `tests/unit/engine/orifice_flow_test.gd` checks `Cylinder.mass_flow()`
  against the App C closed form: choked 0.028293 kg/s, subsonic at pr 0.70, the two branches meeting at pr 0.5283 to
  1e-8, sign symmetry, linearity in area and upstream pressure. Tags `[closed]`.
- 2026-11-12 — **gap 3 (Woschni) closed.** `tests/unit/engine/woschni_validation_test.gd` hand-evaluates the published
  correlation at three points (motored 270.6, fired 3603.2, gas exchange 110.2 W/(m²·K) at 3000 rpm) and pins the
  C2 term to combustion/expansion only. Tagged `[hand]`: it checks the port, not that Woschni is the right model — the
  original SAE 670931 text is still unreachable, the constants come from Qasemian & Rezaei 2020.
- 2026-11-12 — `docs/physics-validation.md` was four rows out of date (gas properties, C++/GDScript parity, ABS
  hysteresis, Chen–Flynn all had tests). Corrected; treat the file as the backlog, not as memory.
- 2026-11-12 — the golden trace fixture is a self-consistency gate, not a physics check. It was regenerated after the
  physics changed. The `kawasaki_zx25r` torque column flips sign and magnitude between fixtures (+190 vs −188 N m at
  16k rpm) and looks like an inertia artifact; it is recorded, not endorsed.
- 2026-11-12 — geometry rebuilds are debounced (`main.REBUILD_DELAY = 0.12 s`). A test that wants the new geometry now
  calls `main.flush_rebuild()` instead of waiting a fixed number of frames.
