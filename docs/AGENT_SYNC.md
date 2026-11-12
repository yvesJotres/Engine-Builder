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
| `integration/dyno/dyno_cbr250rr.gd` | 29.48 kW at 12,500 rpm against Honda's 28 kW factbook figure (+5.3%, gate is ±3%). **Not** the uncommitted header change: re-running with `header_primary_mm` back at the committed 42 mm gives the same 29.48 kW. A code bisect is impossible — the pre-checkpoint tree (`39df036`) does not run (see below) — so the sensitivity was measured instead: ±100% wall heat moves power by ~9% (25.20 N·m at 0, 23.07 at 1, 21.01 at 2) and the 1D pipe solver moves it 12% (26.55 kW on vs 30.20 off). The gap is model uncertainty around heat transfer and exhaust tuning, not one wrong constant. | Physics: needs a measured WOT cylinder-pressure trace (gap 6/7) or a sourced Woschni constant set. Any fix by scaling `wall_heat_scale` per bike is the fudge factor `GEMINI.md` 5 forbids. Gate stays at 28 kW. |

| `integration/dyno/dyno_regression_test.gd` | New gate (gap 14). Rear-wheel hp against the digitised curves, ±5 % mean / ±10 % worst. Corrected measurement (`sim.cycle_brake_torque`, cycle-averaged, not the last sub-step): CBR250RR SP **3.8 % (passes)**, Ninja 300 **12.4 %**, R1M **21.9 %**, CBR1000RR-R **23.5 %**. Shape: mid-range is within 4-8 % on every bike, the low end is too strong (+52…+69 % at 4000 rpm) and the litre top end too weak (−36 % at 13,900). VE measured 0.895 at 4000 rpm falling to 0.807 at 13,500 — a real engine climbs with rpm. | Physics: measured the obvious lever and rejected it. Every preset leaves `runner_bore_mm` unset, so all engines fall back to one 29 mm runner (`RUNNER_AREA = 6.6e-4 m²`); sweeping it to 46 mm recovers only ~12 of the litre bikes' ~36 points (CBR1000RR-R −51.3 % → −39.0 %, R1M −46.3 % → −35.6 %) and moves the passing 250 off its 3.8 %. Cam timing and lift in the presets are plausible (256–284°, 9.7–10 mm), so it is not a bad preset. Remaining suspect: plenum/multi-cylinder interference and the valve Cd shortcut at high lift — both need a measured pressure trace to settle. Instrument: `tools/diagnostics/probe_runner_area.gd`. |

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

Resolved 2026-11-12: `unit/drivetrain/shift_behavior_test.gd` — `gearbox_load` was the last sub-step's clutch transfer,
which swings sign every firing event; it is now the mean over one engine cycle (720°, 360° two-stroke), accumulated
the same way `_accumulate_cycle` averages the crank torque. Measured after the change: WOT 76.7–79.6 N m (threshold
16 N m), closed throttle −13.4 N m. The raw sub-step value stayed as `_gearbox_transfer`. Instrument:
`tools/diagnostics/probe_gearbox_load_mean.gd`. Group `drivetrain/` is 16 of 16 green.
Also resolved 2026-11-12: `unit/engine/two_stroke_native_test.gd` — the native kernel now carries all five GDScript two-stroke
fixes (commit `6e50e2d`), 540 field comparisons across reed and piston paths, 0 problems.
`integration/dyno/dyno_cell_test.gd` — the pull compared one frame, whose firing phase outweighed a 200 N load; it now
compares the mean of the last half second (`3bc98c3`).

---

## The gate

```
run_test.bat                  full sweep (3 tests at a time, ~6 min)
run_test.bat --physics        engine/ exhaust/ intake/ sim/ dyno/ (~5 min)
run_test.bat --ui             controls/ structure/ visual/
run_test.bat --drivetrain     drivetrain/ model/
run_test.bat --ecu            ecu/
run_test.bat --audio          audio/
run_test.bat <filter>         any raw TEST_FILTER, e.g. engine/woschni
TEST_JOBS=1 run_test.bat      serial, for a machine that cannot take three at once
TEST_TIMEOUT_S=900 run_test.bat   longer deadline per test
```

Exit code 1 if any selected test fails. No `pause` when called with an argument, so a CI step or an agent can call it.
A merge to the integration branch requires the group you touched to be green, and **no new red anywhere**.

Every test runs in its own Godot process (a crash or leaked singleton cannot smear into the next). That used to mean
one process at a time and no bound on how long one could take, which is how an 18-minute hang read as "the suite is
slow". Three things bound it now, all in `tests/test_runner.gd`: tests run `TEST_JOBS` at a time (default 3), each has
a wall-clock deadline reported as `TIMEOUT` and killed with `taskkill /T` past it, children get `--quit-after 3000` so an
assert that fires before the test's own `quit()` cannot leave the tree spinning, and every test's output is kept in
`user://test_logs/<test>.log` — which is also how the verdict is read, since a detached process reports no exit code.
A failure always prints one of `FAIL_MARKERS` (checked: all 90 files that call `quit(1)` do).

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

- 2026-11-12 — **the gate runs tests in parallel and kills what hangs.** `tests/test_runner.gd` now keeps `TEST_JOBS`
  children (default 3) in flight through `OS.create_process`, polls them, and past `TEST_TIMEOUT_S` (default 600) kills
  the tree with `taskkill /T` and reports `TIMEOUT`. Each child gets `--log-file` into `user://test_logs`, because a
  detached process reports no exit code: the verdict is read from the log against `FAIL_MARKERS`, which is safe here —
  all 90 test files that call `quit(1)` also print FAIL, PASS or RESULT. No shell wrapper: `cmd.exe` mangles a quoted
  batch path followed by more arguments (`'C:\Users\Yves' is not recognized`, then `Access is denied`), so the child is
  the Godot binary itself. Measured: `--physics` went from a 18-minute hang to **5 min 2 s**, and the full sweep is
  **172 tests in 5 min 48 s with 2 red**, both of them the known physics gaps below — every other group green. The
  regression numbers are unchanged to the decimal (3.8 / 12.4 / 21.9 / 23.5 %), so the cycle-mean
  `gearbox_load` did not move the dyno curves. `batch_dyno_test` is the long pole at 237 s of that 348 s: it runs a
  full pull on all 20 presets in one process, so it needs splitting before anyone raises the worker count.
- 2026-11-12 — **the gate can no longer hang on an assert.** A test whose `assert` fires before its own `quit()` leaves
  the script function aborted but the scene tree running, so the child process never exited: `exhaust_options_test` sat
  there for 18 minutes and the whole sweep printed nothing, which reads exactly like "the suite is slow". Two changes in
  `tests/test_runner.gd`: each test name is printed before it runs (`run  <path>`), so a hang names itself in the log, and
  children are launched with `--quit-after 3000`, which bounds the aborted-tree case to ~20 s. A test that needs more
  scene-tree time than that has to raise the number. Verified with a deliberate failing assert: FAIL, exit 1, 21 s
  instead of forever.
- 2026-11-12 — **`exhaust_options_test`'s tailpipe check was stale, not the layout.** The uncommitted exhaust work
  recesses the outlet pipe 2.5 cm into the canister so the mouth has depth (`TAIL_RECESS`), which broke the old
  assertion that the tail starts flush with the can's end face. The test now asserts the recess equals the declared
  `TAIL_RECESS` and that the tailpipe is still wired onto the muffler it slides into — a real invariant of the new
  design, not a loosened tolerance.
- 2026-11-12 — **`ota_compatibility_test`'s car check was stale too.** It selected the Centodieci and read
  `_car._wheels` on the same frame, but geometry rebuilds are debounced (`main.REBUILD_DELAY = 0.12 s`), so it was
  reading the previous vehicle. It now calls `main.flush_rebuild()`, the documented way for a test to ask for the new
  body now. Both of the stale tests found today share the same cause: a change landed in the working tree and the test
  that encoded the old behaviour was never re-run, because the sweep was hanging before it got there.
- 2026-11-12 — **`gearbox_load` is a cycle mean.** The clutch transfer pulses with each firing event (measured +200,
  −13.9, +200, −86.3, +15.7 N m on five consecutive sub-steps at 4,270 rpm), so the shift state machine's "unloaded"
  test and the slipper clutch both read a signal that flipped sign between frames. `_advance_driveline` now accumulates
  transfer × crank degrees and publishes the mean once 720° (360° two-stroke) has gone by — the same window and the
  same bookkeeping `_accumulate_cycle` already uses for `cycle_brake_torque`. The sub-step value is `_gearbox_transfer`
  and is what the slipper could read instead if a measured clutch trace says the mean is too slow.
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
