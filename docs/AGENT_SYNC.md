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
| `unit/engine/two_stroke_native_test.gd` | `scripts/engine/two_stroke_cylinder.gd` got five physics fixes (residual capture, burn duration vs RPM, crank radius inertia, port backfire heat, CA markers); `gdextension/src/two_stroke_kernel.cpp` has not been ported. Diverges from step 0: `last_residual_fraction` 1.0 vs 0.0, `u` 62.1 vs 100.1. | Physics, then rebuild the DLL. Do not rework the gate. |
| `unit/drivetrain/shift_behavior_test.gd` | `gearbox_load` swings ±90 N m between firing pulses at 4,270 rpm (61.6 → −86.5 → −5.0, capacity 200 N m, unloaded threshold 16 N m), so the shift state machine sees "unloaded" at wide open and drops to neutral. | Orchestrator: cycle-mean `gearbox_load` in `_advance_driveline`. Do not encode the jump as the expected behaviour. |

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
