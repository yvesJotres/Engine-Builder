# Multi-Agent Implementation Plan: Natural Feel v1

**Architecture:** 3 agents (Physics, Geometry, UIUX) + 1 orchestrator
**Branch strategy:** `feat/physics-*`, `feat/geometry-*`, `feat/uiux-*` → `feat/natural-feel-v1` (integration)
**Sync point:** Daily 15-min standup; shared `docs/AGENT_SYNC.md`

---

## Agent Ownership Matrix

| Feature | Physics Agent | Geometry Agent | UIUX Agent |
|---------|---------------|----------------|------------|
| **Pacejka MF 6.2** | ✅ Core model, coeff calibration | ❌ | ✅ Mode toggle UI, slip visualization |
| **Knock Proxy** | ✅ Livengold-Wu integral, calibration | ❌ | ✅ Knock indicator (HUD), retard feedback |
| **Metghalchi-Keck Flame Speed** | ✅ Su model, burn_deg integration | ❌ | ✅ Burn rate debug overlay |
| **Turbo Compressor Map** | ✅ Map lookup, wastegate logic | ✅ Compressor geometry → map scaling | ✅ Boost gauge, spool animation |
| **Woschni Validation** | ✅ Constants, hand-calc verification | ✅ Bore/stroke → heat transfer area | ✅ Coolant temp gauge calibration |
| **Exhaust End Correction** | ✅ Reflection coeff validation | ✅ Pipe radius → end correction | ❌ |
| **Dyno Regression** | ✅ Tolerance logic, CI integration | ❌ | ✅ Report visualization, pass/fail badges |
| **Mode Switch (Arcade/Sim)** | ✅ Physics flags | ❌ | ✅ Toggle, preset sync, onboarding |

---

## Agent Work Packages (Ready to Assign)

### 📦 Physics Agent (`feat/physics-natural-feel`)

```markdown
# PHYSICS AGENT WORK PACKAGE

## Scope
All crank-angle loop physics: cylinder, exhaust, intake, ECU, wheel dynamics.

## Deliverables (Phase 1)
- [ ] `scripts/sim/wheel.gd` — Pacejka MF 6.2 steady-state `mu(kappa, Fz)`
- [ ] `scripts/engine/cylinder.gd` — Knock integral (Livengood-Wu)
- [ ] `scripts/engine/cylinder.gd` — Metghalchi-Keck `Su(T, p, φ, f)` → `burn_deg`
- [ ] `scripts/engine/two_stroke_cylinder.gd` — Same knock + flame speed
- [ ] `scripts/ecu/ecu.gd` — Knock trim → spark retard

## Deliverables (Phase 2)
- [ ] `gdextension/src/intake_native.cpp` — Turbo compressor map bilinear interp
- [ ] `gdextension/include/intake_native.h` — API: `load_map()`, `step()`
- [ ] `scripts/engine/cylinder.gd` — Woschni constants tune (motored/fired)
- [ ] `gdextension/src/exhaust_gas.cpp` — Verify end correction 0.6133a

## Tests to Write (all in `tests/unit/`)
- [ ] `sim/pacejka_test.gd` — Peak Fx=1.05×Fz, locked=0.75×Fz
- [ ] `engine/knock_test.gd` — Retard >2° at 15:1 AFR, 30° adv, 10k RPM
- [ ] `engine/flame_speed_test.gd` — Su=0.4 m/s at φ=1.0, 300K, 1atm
- [ ] `intake/turbo_map_test.gd` — PR=2.0, eff=0.72 at design point
- [ ] `engine/woschni_validation_test.gd` — h_motored=1250±12%, h_fired=8500±12%
- [ ] `exhaust/open_end_reflection_test.gd` — |R| at ka=0.1, 0.6133a phase

## Handoff Contracts
- **To Geometry:** `EngineSpec` fields for Pacejka coeffs per bike, turbo map scaling
- **To UIUX:** Physics flags `pacejka_enabled`, `knock_enabled`, `flame_speed_enabled`, `turbo_enabled`
- **Exports:** `Wheel.get_slip()`, `Cylinder.get_knock_integral()`, `IntakeNative.get_boost()`

## Performance Budget
- Total physics/frame < 100 μs (current ~54 μs)
- Pacejka: < 5 μs, Knock: < 1 μs, Flame speed: < 1 μs, Turbo: < 3 μs
```

---

### 📦 Geometry Agent (`feat/geometry-natural-feel`)

```markdown
# GEOMETRY AGENT WORK PACKAGE

## Scope
All geometric parameters that feed physics: bike specs, engine geometry, tire data, pipe dimensions.

## Deliverables (Phase 1)
- [ ] `assets/engines/*.json` — Add Pacejka coefficients per bike (front/rear)
- [ ] `assets/engines/*.json` — Add turbo compressor map reference (H2R: GTX3076R)
- [ ] `scripts/model/bike/parts/tyre.gd` (new) — Tire geometry → Pacejka scaling rules
- [ ] `scripts/model/bike/parts/brake_disc.gd` — Brake torque → clamp force geometry

## Deliverables (Phase 2)
- [ ] `scripts/model/pipe/exhaust.gd` — Pipe radius → end correction (0.6133×radius)
- [ ] `scripts/model/engine/engine_model.gd` — Bore/stroke → heat transfer area (Woschni)
- [ ] `scripts/model/bike/chassis.gd` — CG height, wheelbase → load transfer (already in engine_sim)

## Data Contracts (Physics consumes)
```json
// assets/engines/kawasaki_h2r.json additions
{
  "pacejka_front": { "PCX1": 1.6, "PDX1": 1.0, "PKX1": 21.0, ... },
  "pacejka_rear":  { "PCX1": 1.5, "PDX1": 1.1, "PKX1": 22.0, ... },
  "turbo_map": "garrett_gtx3076r",
  "turbo_wastegate_pring": 1.8
}
```

```json
// assets/engines/honda_cbr1000rrr_sp.json additions
{
  "pacejka_front": { ... },
  "pacejka_rear":  { ... },
  "turbo_map": null
}
```

## Tests to Write
- [ ] `tests/unit/geometry/tyre_scaling_test.gd` — 120/70ZR17 → coeffs match Moto-Braking
- [ ] `tests/unit/geometry/pipe_end_correction_test.gd` — radius=0.03 → 0.6133×0.03

## Handoff Contracts
- **To Physics:** Validated JSON specs; `TyreGeometry.get_pacejka_coeffs()`
- **To UIUX:** Spec fields for UI (tire size display, turbo badge)
- **Exports:** `EngineSpec.pacejka_front`, `EngineSpec.turbo_map_path`
```

---

### 📦 UIUX Agent (`feat/uiux-natural-feel`)

```markdown
# UIUX AGENT WORK PACKAGE

## Scope
User-facing controls, feedback, visualization, onboarding for new physics.

## Deliverables (Phase 1)
- [ ] `scripts/ui/panel/control_panel.gd` — Physics mode toggle (Arcade/Simulation)
- [ ] `scripts/ui/hud.gd` — Knock indicator (amber/red), slip bars (F/R), boost gauge
- [ ] `scripts/ui/panel/panel_presets.gd` — Preset sync: "Track" → Sim mode, "Cruise" → Arcade

## Deliverables (Phase 2)
- [ ] `scripts/ui/panel/control_panel.gd` — Per-physics toggles (Pacejka, Knock, Flame, Turbo)
- [ ] `scripts/ui/hud.gd` — Burn rate overlay (debug), coolant temp trend
- [ ] `scripts/dyno/dyno_report.gd` — SAE J1349 corrected badge, regression pass/fail

## Deliverables (Phase 3)
- [ ] `scripts/app/main.gd` — Feature flags persistence (ProjectSettings)
- [ ] `scripts/ui/panel/control_panel.gd` — Onboarding tooltip: "Simulation mode enables tire slip, knock, realistic burn"
- [ ] `scripts/ui/panel/panel_builds.gd` — Build validation: red badge if physics tests fail

## UI Contracts (Physics provides)
```gdscript
# Real-time signals (emitted at 60 Hz from EngineSim)
signal slip_changed(front: float, rear: float)
signal knock_level(integral: float, retard_deg: float)
signal boost_pressure(bar: float)
signal burn_rate(deg_per_ms: float)
signal coolant_temp(c: float)
```

## Tests to Write
- [ ] `tests/visual/ui/physics_mode_toggle_test.gd` — Arcade disables Pacejka, knock, flame
- [ ] `tests/visual/ui/knock_indicator_test.gd` — Amber at integral>0.5, red at >1.0
- [ ] `tests/visual/ui/dyno_report_test.gd` — J1349 badge shows corrected power

## Handoff Contracts
- **From Physics:** Signal names, update rates, value ranges
- **From Geometry:** Spec field names for UI display (tire size, turbo model)
- **To Physics:** Feature flag keys (`physics/pacejka_enabled`, etc.)
```

---

## Orchestrator Checklist (You)

```markdown
# ORCHESTRATOR DAILY CHECKLIST

## Morning (15 min)
- [ ] Check `docs/AGENT_SYNC.md` for blockers
- [ ] Verify no merge conflicts between agent branches
- [ ] Run `./run_test.bat --physics` on integration branch

## Evening
- [ ] Merge agent PRs to `feat/natural-feel-v1`
- [ ] Update `docs/AGENT_SYNC.md` with next-day priorities
- [ ] Tag integration build: `git tag -a physics-v1.0 -m "Physics complete"`

## Integration Gates
| Gate | Branch | Tests Required | Owner |
|------|--------|----------------|-------|
| Physics Core | `feat/physics-*` | 6 unit tests pass | Physics |
| Geometry Specs | `feat/geometry-*` | 2 unit tests + JSON validate | Geometry |
| UI Integration | `feat/uiux-*` | 3 visual tests | UIUX |
| **Full Integration** | `feat/natural-feel-v1` | All + dyno regression | You |

## Conflict Resolution Rules
1. **Physics wins** on crank-angle loop APIs
2. **Geometry wins** on JSON spec schema
3. **UIUX wins** on signal names / update rates
4. **You decide** on performance budget disputes
```

---

## Adding More Agent Categories

### Framework: "Capability → Agent" Registry

```yaml
# docs/AGENT_REGISTRY.yaml (create this)
agents:
  physics:
    owns: [thermodynamics, combustion, gas_dynamics, ecu, wheel_dynamics]
    contracts: [crank_angle_api, signal_emission, feature_flags]
    test_pattern: "tests/unit/**/*_test.gd"
  
  geometry:
    owns: [bike_specs, engine_geometry, tire_models, pipe_geometry, chassis]
    contracts: [json_schema, scaling_rules, validation_api]
    test_pattern: "tests/unit/geometry/**/*_test.gd"
  
  uiux:
    owns: [hud, panels, onboarding, visualization, persistence]
    contracts: [signal_subscription, feature_toggles, user_settings]
    test_pattern: "tests/visual/ui/**/*_test.gd"

  # ADD NEW AGENTS HERE:
  audio:
    owns: [exhaust_note, intake_sound, mechanical_noise, knock_audio]
    contracts: [physics_audio_signals, sample_bank, realtime_mixer]
    test_pattern: "tests/unit/audio/**/*_test.gd"
  
  networking:
    owns: [multiplayer_sync, ghost_laps, leaderboards, telemetry]
    contracts: [state_serialization, lag_compensation, auth]
    test_pattern: "tests/integration/network/**/*_test.gd"
  
  ai:
    owns: [racing_line, setup_optimizer, driver_coach, parameter_tuning]
    contracts: [sim_fast_forward, result_evaluation, safety_bounds]
    test_pattern: "tests/unit/ai/**/*_test.gd"
```

### Adding a New Agent: 5-Minute Process

```bash
# 1. Add to AGENT_REGISTRY.yaml
# 2. Create branch convention: feat/<agent>-<feature>
# 3. Create work package template (copy Physics/Geometry/UIUX)
# 4. Define 3 contracts: Inputs, Outputs, Tests
# 5. Add to orchestrator checklist
# 6. Create test directory: tests/unit/<agent>/
```

### Example: Adding Audio Agent for "Natural Feel v2"

```markdown
# AUDIO AGENT WORK PACKAGE (Future)

## Scope
Exhaust note synthesis, intake induction noise, knock audio, mechanical sounds.

## Physics Contracts (Input)
- `ExhaustNative.get_pressure_wave(ca)` → pressure vs crank angle
- `Cylinder.get_knock_event(ca)` → knock timing/intensity
- `IntakeNative.get_throttle_velocity()` → induction rush

## Deliverables
- [ ] `scripts/audio/exhaust_synth.gd` — Waveguide synthesis from pressure wave
- [ ] `scripts/audio/knock_audio.gd` — "Ping" sample triggered by knock_event
- [ ] `scripts/audio/intake_synth.gd` — Throttle velocity → induction tone

## Tests
- [ ] `tests/unit/audio/exhaust_synth_test.gd` — Frequency content matches recorded
- [ ] `tests/unit/audio/knock_latency_test.gd` — < 5 ms from knock_event to audio

## Handoff
- **From Physics:** Signal specs, update rate (crank-resolved vs frame)
- **To UIUX:** Volume sliders, mute toggles, spatial audio settings
```

---

## Branch & Merge Strategy

```
main
  │
  ├─ feat/physics-natural-feel     (Physics agent)
  │     ├─ pacejka
  │     ├─ knock
  │     └─ flame_speed
  │
  ├─ feat/geometry-natural-feel    (Geometry agent)
  │     ├─ pacejka_coeffs
  │     ├─ turbo_specs
  │     └─ pipe_geometry
  │
  ├─ feat/uiux-natural-feel        (UIUX agent)
  │     ├─ mode_toggle
  │     ├─ hud_indicators
  │     └─ dyno_badges
  │
  └─ feat/natural-feel-v1          (Integration — YOU)
        │
        ├─ MERGE physics → resolve crank-angle API
        ├─ MERGE geometry → validate JSON specs
        ├─ MERGE uiux → wire signals
        └─ RUN full dyno regression → tag release
```

---

## Communication Protocol

| Channel | Purpose | Frequency |
|---------|---------|-----------|
| `docs/AGENT_SYNC.md` | Blockers, decisions, API changes | Updated continuously |
| Daily standup (15 min) | Sync progress, resolve conflicts | Daily |
| PR reviews | Code quality, contract compliance | Per feature |
| Integration build | Full test suite on `feat/natural-feel-v1` | After each agent merge |

---

## Scaling Rules

| # Agents | Coordination Cost | Mitigation |
|----------|-------------------|------------|
| 3 | Low | Daily standup + shared sync doc |
| 5 | Medium | Add "Tech Lead" per domain (Physics Lead, Geometry Lead) |
| 8+ | High | Split into squads: Powertrain, Chassis, UI, Audio, Network, AI |

**Each new agent adds ~15 min/day coordination.** Cap at 5 agents per orchestrator.