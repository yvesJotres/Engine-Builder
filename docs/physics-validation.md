# Physics Validation Inventory

**Purpose.** When the simulation produces wrong numbers we must rule out whole components. That works only if each scientific formula is pinned by a test against a value from **outside the code**: a closed form, a textbook or paper table/figure, or a hand calculation, with the reference cited. This file is the inventory of what exists today and the gaps, ranked by how much they matter for dyno accuracy and realism.

**Scope.** Every physics module in:
- `gdextension/src/*.cpp` (C++ native: cylinder kernel, ECU, intake, exhaust)
- `scripts/engine/*.gd` (GDScript: cylinder, two-stroke, firing orders)
- `scripts/sim/*.gd` (GDScript: engine_sim, gas_properties, wheel, abs_controller)
- `scripts/ecu/*.gd` (GDScript: ECU with launch, quickshift, overrun)

Config/serde, UI, and unit-conversion helpers are skipped.

**Legend**

- ✅ **external** — a test asserts a value that does not come from running the code: closed form, published table, figure read from paper, or hand evaluation of the cited formula. Tags: `[hand]` hand evaluation of cited formula (checks implementation, not that formula is the right model), `[closed]` exact closed form or limit, `[table]` published table, `[fig]` value read from published figure (tolerance = reading error), `[meas]` published measurement, `[ind]` independent implementation (other language).
- 🟡 **self-consistent only** — tests exist but check conservation, symmetry, monotonicity, "stays finite", loose plausibility bands, or compare code with itself.
- ❌ **untested** — nothing found that exercises the model's numbers.

**Reading depth.** I read the bodies of the tests that carry the physics (all of `gas_properties`, `cylinder_kernel`, `ecu_model`, `engine_sim` headers). For scenario/integration tests (`tests/integration/*`, `tests/unit/*`) I judged from name and leading comment only; they are robustness tests and none counted as ✅ unless they assert an external value.

**Status note (2026-11-12).** This inventory was four rows out of date: gas properties, the C++/GDScript parity gate, ABS hysteresis and Chen–Flynn all have tests that assert values from outside the code, and all four pass. They are marked ✅ below with the file that carries them. Two tests are knowingly red and both are code problems, not stale gates: `two_stroke_native_test` (the native kernel has not been ported to the five GDScript two-stroke fixes) and `shift_behavior_test` (`gearbox_load` alternates sign per firing pulse). Tracked in [AGENT_SYNC.md](AGENT_SYNC.md).

**Run them:** `run_test.bat --physics` (or any `TEST_FILTER` prefix, e.g. `run_test.bat engine/woschni`).

---

## 1. Gas Properties (Temperature-Dependent cp, cv, u, h)

| Model | Source in Code | Test | Reference Value | Status |
|-------|----------------|------|-----------------|--------|
| cp_air(T) 29-point table 300–3000 K | `scripts/sim/gas_properties.gd:18` `gdextension/src/cylinder_kernel.cpp:25` | ✅ `tests/unit/engine/gas_properties_test.gd` | Keenan & Kaye / Cengel *Thermodynamics* Appendix tables | ✅ `[table]` |
| cp_burnt(T) 29-point table | `gas_properties.gd:21` `cylinder_kernel.cpp:28` | ✅ `gas_properties_test.gd` | Stoich hydrocarbon flame products (same sources) | ✅ `[table]` |
| u(burnt, T) = ∫cv dT (trapezoid) | `gas_properties.gd:74` `cylinder_kernel.cpp:108` | ✅ `gas_properties_test.gd` — u(1000 K) against the trapezoid of the table | Integral of cv; u(300K)=0 by construction | ✅ `[closed]` |
| h(burnt, T) = u + R·T | `gas_properties.gd:90` `cylinder_kernel.cpp:125` | ✅ `gas_properties_test.gd` | R = 287.05 J/(kg·K) | ✅ `[closed]` |
| temp_from_u(burnt, energy) Newton 5-iter | `gas_properties.gd:95` `cylinder_kernel.cpp:130` | ✅ `gas_properties_test.gd` — round trip error printed, gate is exact | Inverse of u(T); monotonic, 200–4000 K clamp | ✅ `[closed]` |
| C++/GDScript parity (1e-9) | `cylinder_kernel.cpp:19` | ✅ `tests/unit/engine/cylinder_native_test.gd` — single-step gate at 1e-9, 600-frame run on 3 presets | Both implementations must agree to 1e-9 | ✅ `[ind]` |

**Done — all six closed.** `tests/unit/engine/gas_properties_test.gd` (table points, u as the trapezoid, exact u↔T round trip) and `tests/unit/engine/cylinder_native_test.gd` (1e-9 single-step parity plus a 600-frame run on three presets).

---

## 2. Cylinder Thermodynamics (Four-Stroke)

| Model | Source in Code | Test | Reference Value | Status |
|-------|----------------|------|-----------------|--------|
| Volume vs crank angle (slider-crank) | `scripts/engine/cylinder.gd:480` | ❌ none | V(θ) = V_c + ½V_s[1-cosθ + (1-√(1-λ²sin²θ))/λ] λ=r/L | ❌ |
| Valve curtain area vs lift (Heywood) | `cylinder.gd:500` `cylinder_kernel.cpp:30` | ❌ none | A = π·d_valve·lift·Cd; Cd vs L/D from SAE 820154/962527 | ❌ |
| Orifice mass flow (Heywood App C) | `cylinder.gd:318` `cylinder_kernel.cpp:180` | ✅ `tests/unit/engine/orifice_flow_test.gd` — choked, subsonic, continuity at 0.5283, sign symmetry, linearity | Choked: ṁ = Cd·A·p0·√(γ/R/T0)·(2/(γ+1))^((γ+1)/(2(γ-1))) | ✅ `[closed]` |
| Wiebe burn fraction | `cylinder.gd:700` `cylinder_kernel.cpp:580` | ❌ none | x_b = 1-exp(-a·((θ-θ0)/Δθ)^(m+1)); a=5, m=2 typical | ❌ |
| **Heat transfer: Woschni (1967) SAE 670931** | `cylinder.gd:600` `cylinder_kernel.cpp:540` | ✅ `tests/unit/engine/woschni_validation_test.gd` (hand calc at motored / fired / gas-exchange points) + `woschni_test.gd` (conservation) | h = 3.26·B⁻⁰·²·p⁰·⁸·T⁻⁰·⁵⁵·w⁰·⁸; w = C1·v_p + C2·(V_d·T_r·(p-p_m))/p_r·V_r | ✅ `[hand]` |
| **Heat transfer: Annand (1963)** | `cylinder_kernel.cpp:550` (optional) | ❌ none | h = a·Re^b·Pr^c; a=0.52, b=0.7, c=0.33 (Annand) | ❌ |
| **Wall heat scale** | `cylinder.gd:640` `engine_sim.gd:80` | ❌ none | Global multiplier `wall_heat_scale` (default 1.0) | ❌ |
| **Endpoint energy solve: Newton 4-iter on m·u(T) - source + ½(p_old + mRT/V)·dV = 0** | `cylinder.gd:680` `cylinder_kernel.cpp:760` | ❌ none | Exact for any u(T); replaces linearized cv·T solve | ❌ |
| **Residual gas mixing by energy (u)** | `cylinder.gd:765` `cylinder_kernel.cpp:436` | ❌ none | u_mix = (m_air·u_air + m_res·u_res)/m_total; T from u | ❌ |
| **Compression ratio: geometric** | `cylinder.gd:220` | ❌ none | (V_s + V_c)/V_c | ❌ |
| **Compression ratio: effective (IVC)** | `cylinder.gd:235` | ❌ none | V_IVC / V_TDC | ❌ |

**Key references:** Heywood Ch.6 (valve flow), Ch.9 (combustion), Ch.12 (heat transfer); Woschni SAE 670931; Qasemian 2020 (IOP) for Woschni constants per phase.

---

## 3. Two-Stroke Cylinder

| Model | Source in Code | Test | Reference Value | Status |
|-------|----------------|------|-----------------|--------|
| Port timing (transfer, exhaust, intake) | `scripts/engine/two_stroke_cylinder.gd:180` | ❌ none | Geometric angles from spec | ❌ |
| Reed valve flow | `two_stroke_cylinder.gd:200` | ❌ none | Heywood App C orifice | ❌ |
| Scavenging (perfect mixing / perfect displacement) | `two_stroke_cylinder.gd:280` | ❌ none | Blair *Two-Stroke Engine* Ch.3 | ❌ |
| **Residual capture at transfer close** | `two_stroke_cylinder.gd:300` | ❌ none | _residual_kg = mass, _residual_temp = temp | ❌ |
| **Burn duration vs RPM** | `two_stroke_cylinder.gd:265` | ❌ none | burn_deg = BURN_DEG_BASE + BURN_DEG_PER_RPM·RPM | ❌ |
| **Crank radius inertia torque** | `two_stroke_cylinder.gd:395` | ❌ none | crank_r = stroke·0.5 (was 0 — bug fixed) | ❌ |
| Exhaust port backfire | `two_stroke_cylinder.gd:270` | ❌ none | Unlit charge + hot port → auto-ignite | ❌ |

**Gap:** No two-stroke specific validation data in `tests/fixtures/`. What does exist is a parity gate: the native
kernel and the GDScript reference agree field for field over 540 comparisons (`tests/unit/engine/two_stroke_native_test.gd`,
`[ind]`), so the two-stroke is at least one model in two languages — not a model checked against measurements.

---

## 4. ECU (Idle, Launch, Quickshifter, Overrun)

| Model | Source in Code | Test | Reference Value | Status |
|-------|----------------|------|-----------------|--------|
| Idle PID (target_rpm, spark trim) | `scripts/ecu/ecu.gd:180` `gdextension/src/ecu_model.cpp:80` | 🟡 `tests/unit/ecu/idle_test.gd` (holds idle) | Heywood §12.5; typical Kp=0.1, Ki=0.05 deg/(rpm·s) | 🟡 |
| **Launch control: PI controller** | `ecu.gd:150` `ecu_model.cpp:115` | ❌ none | Kp=10, Ki=30 (rel rpm error), bias limit ±1.0, lock at clutch_engage≥0.98 | ❌ |
| Quickshifter upshift cut | `ecu.gd:120` `ecu_model.cpp:95` | 🟡 `tests/unit/drivetrain/quickshift_shift_test.gd` | Cut time from spec profile; min RPM gate | 🟡 |
| Quickshifter downshift blip | `ecu.gd:135` `ecu_model.cpp:100` | 🟡 `tests/unit/drivetrain/downshift_blip_test.gd` | Blip throttle profile vs gear | 🟡 |
| Overrun fuel cut (decel) | `ecu.gd:200` `ecu_model.cpp:75` | ❌ none | OVERRUN_CUT=2.2×idle, RESUME=1.25×idle | ❌ |
| Power modes (F/M/L) λ & timing | `ecu.gd:220` `ecu_model.cpp:85` | ❌ none | λ_mult: F=1.0, M=1.05, L=1.1; timing offset | ❌ |

**Key gap:** No launch PI validation against measured clutch slip / RPM trace.

---

## 5. Drivetrain & Vehicle

| Model | Source in Code | Test | Reference Value | Status |
|-------|----------------|------|-----------------|--------|
| Clutch capacity (slipper) | `scripts/sim/engine_sim.gd:900` | ❌ none | τ_max = f(gear_load) × slipper_ramp (0.5 on overrun) | ❌ |
| Clutch torque transfer (stiffness) | `engine_sim.gd:920` | ❌ none | τ = k·Δω·dt; k = CLUTCH_STIFFNESS | ❌ |
| Gearbox ratios + efficiency | `scripts/model/bike/gearbox_model.gd` | ❌ none | DRIVE_EFFICIENCY=0.93 (crank→wheel) | ❌ |
| **Wheel slip ratio** | `scripts/sim/wheel.gd:26` | ❌ none | s = (ω·r - v)/v; clamp -1..1; MIN_SPEED=0.5 m/s | ❌ |
| **Tire μ(slip) curve** | `wheel.gd:35` | ❌ none | Peak 1.05 at 0.12 slip; locked 0.75 (simple peak model) | ❌ |
| **Pacejka Magic Formula (MF 6.2)** | ❌ not implemented | ❌ none | Fz, κ, α → Fx, Fy, Mz (tire data needed) | ❌ |
| **Dynamic load transfer** | `engine_sim.gd:1030` | ❌ none | ΔFz = ±m·a·h/L; h=0.62m, front_static=0.48 | ❌ |
| **ABS controller (hysteresis)** | `scripts/sim/abs_controller.gd` | ✅ `tests/unit/sim/abs_controller_test.gd` — apply slew, release faster than apply, cycles counted, lever handed back under the cutoff | Release at 1.15×target, reapply at 0.8×target; slew: release 60k, apply 12k N·m/s | ✅ `[hand]` (spec constants, not measured wheel data) |
| Brake torque (per wheel) | `engine_sim.gd:1040` | ❌ none | front: brake·brake_torque_nm; rear: ×0.35 share | ❌ |

**References:** Moto-Braking-Dynamics (Pacejka, load transfer, thermal fade); Heywood Ch.10 (vehicle dynamics).

---

## 6. Exhaust System (1D Gas Dynamics)

| Model | Source in Code | Test | Reference Value | Status |
|-------|----------------|------|-----------------|--------|
| Finite-volume solver (HLLC?) | `gdextension/src/exhaust_gas.cpp` | ❌ none | Toro Ch.10; Sod test 1 | ❌ |
| Wave propagation (c + u) | `exhaust_gas.cpp` | ❌ none | Msallam 2000 eq.1-2 | ❌ |
| Open-end reflection (Levine & Schwinger) | `exhaust_gas.cpp` | ❌ none | End correction 0.6133a; Silva 2009 fit | ❌ |
| Junction merging/splitting | `exhaust_gas.cpp` | ❌ none | Benson Vol.1 §4.1; Blair §2.1-2.2 | ❌ |
| Wall friction (Darcy) | `exhaust_gas.cpp` | ❌ none | Δp = f(L/D)·½ρu² | ❌ |
| Acoustic wall loss (Kirchhoff) | `exhaust_gas.cpp` | ❌ none | α_Np/m from Tiikoja SAE 2016-01-1816 | ❌ |

**Status:** Native C++ solver exists but **zero physics-validation tests**.

---

## 7. Intake System

| Model | Source in Code | Test | Reference Value | Status |
|-------|----------------|------|-----------------|--------|
| Native intake + turbo | `gdextension/src/intake_native.cpp` | ❌ none | Compressor map (Garrett GTX3076R in `assets/compressor_maps/`) | ❌ |
| Plenum pressure dynamics | `intake_native.cpp` | ❌ none | 0D volume exchange | ❌ |
| Throttle body flow | `intake_native.cpp` | ❌ none | Orifice + curtain area | ❌ |

---

## 8. Friction (FMEP)

| Model | Source in Code | Test | Reference Value | Status |
|-------|----------------|------|-----------------|--------|
| Chen-Flynn | `scripts/engine/cylinder.gd:800` `gdextension/src/cylinder_kernel.cpp:850` | ✅ `tests/unit/engine/friction_fmep_test.gd` | FMEP = C1 + C2·v_p + C3·v_p² + C4·IMEP | ✅ `[hand]` |
| Chen-Flynn constants (Reitz 2018) | `engine_sim.gd:75` | ✅ `friction_fmep_test.gd` — exact at 3000 rpm/40 bar and 13000 rpm/60 bar | C=0.25 bar, PF=0.005, MPSF=0.1, MPSSF=0 | ✅ `[hand]` |
| Pulkrabek / Patton 1989 (SAE 890836) | Referenced in `13_sources.md:8` | ❌ none | Component breakdown: piston, bearings, valvetrain, aux | ❌ |

---

## 9. Fuel & Combustion Chemistry

| Model | Source in Code | Test | Reference Value | Status |
|-------|----------------|------|-----------------|--------|
| Gasoline LHV / AFR / density | `scripts/sim/engine_spec.gd` | ❌ none | LHV=43 MJ/kg, AFR_stoich=14.7, ρ=720-775 kg/m³ (IEA AMF) | ❌ |
| Fuel film evaporation | `cylinder.gd:740` `cylinder_kernel.cpp:410` | ❌ none | FILM_DEPOSIT=0.2, evaporation rate ∝ (T - T_sat) | ❌ |
| Laminar flame speed (Metghalchi-Keck) | ❌ not used (Wiebe only) | ❌ none | S_u = S_u0·(T/T0)^α·(p/p0)^β·(1-2.1·EGR) | ❌ |
| Knock proxy | ❌ not implemented | ❌ none | Douaud-Eyzat or Livengood-Wu integral | ❌ |

---

## 10. Golden-Trace Regression (Full Dyno Sweep)

| Trace | Source | Bikes | Frames | Status |
|-------|--------|-------|--------|--------|
| `tests/fixtures/sim_golden_trace.json` | Regenerated 2026-11-12 after the gas-property, exhaust and driveline work | honda_cbr1000rrr_sp, kawasaki_h2r, kawasaki_zx25r, yamaha_yzf_r1m | 36 frames each (0–35) | ✅ **self-consistent** (regression gate only — no ground truth) |
| Measured dyno curves | `assets/dyno/*.json` | 5 bikes | Power/torque vs RPM | 🟡 Used for manual comparison only |

**Note on the trace (2026-11-12).** It is a self-consistency gate, not a physics check: it proves the simulation did not change between runs, nothing more. The `kawasaki_zx25r` torque column flips sign and magnitude between the two fixtures (+190 vs −188 N·m at 16k rpm), which is not a torque a 250cc makes in either direction and looks like an inertia artifact; it was recorded, not endorsed. `honda_cbr150r` is bit-identical across the regeneration.

**Gap:** No automated test comparing simulated dyno sweep vs measured curves with tolerance bands.

---

## 11. Measured Reference Data (Available)

| File | Type | Use For |
|------|------|---------|
| `assets/dyno/honda_cbr1000rrr_sp.json` | Dyno curve | Torque/power validation |
| `assets/dyno/kawasaki_h2r.json` | Dyno curve | Turbo validation (future) |
| `assets/dyno/kawasaki_zx25r.json` | Dyno curve | Small-bike validation |
| `assets/dyno/yamaha_yzf_r1m.json` | Dyno curve | High-RPM validation |
| `assets/dyno/honda_cbr250rr_2020.json` | Dyno curve | 250cc validation |
| `docs/cbr250rr_references/local/dyno/cbr250rr_reference_curve.json` | Measured dyno | CBR250RR regression |
| `docs/cbr250rr_references/local/sim_graphs/woschni_native.png` | Heat transfer comparison | Woschni validation |
| `docs/cbr250rr_references/local/atg/*.mr` + C++ source | ATG engine-sim | Cross-reference implementation |

---

## 12. Gaps Ranked by Impact (Dyno Accuracy → Realism)

| Rank | Gap | Module | Effort | Reference |
|------|-----|--------|--------|-----------|
| ~~1~~ | ✅ **Gas properties table validation** — closed 2026-11-12 by `tests/unit/engine/gas_properties_test.gd` | `gas_properties` | — | Keenan & Kaye tables `[table]` |
| ~~2~~ | ✅ **C++/GDScript parity test** (1e-9) — closed by `tests/unit/engine/cylinder_native_test.gd` | `gas_properties` + `cylinder_kernel` | — | Internal requirement `[ind]` |
| ~~3~~ | ✅ **Woschni at 3 operating points** — closed by `tests/unit/engine/woschni_validation_test.gd` (motored 270.6, fired 3603.2, gas exchange 110.2 W/(m²·K) at 3000 rpm, each against hand arithmetic) | `cylinder` | — | Qasemian 2020; Woschni SAE 670931 `[hand]` |
| 4 | **Valve flow Cd vs L/D** (3 points from Heywood Fig 6-18) | `cylinder` | 1 day | SAE 820154 / Heywood Fig 6-18 |
| ~~5~~ | ✅ **Orifice mass flow** — closed by `tests/unit/engine/orifice_flow_test.gd` (0.028293 kg/s choked, branches meet at pr 0.5283) | `cylinder` / `intake` | — | Heywood App C `[closed]` |
| 6 | **Closed-cylinder pressure trace vs motored data** | `cylinder` | 3 days | SAE 2002-01-0492 (or similar) |
| 7 | **Fired IMEP / peak P / CA50 vs measured** | `cylinder` + `engine_sim` | 3 days | GT-Power correlation targets (±3% / ±5% / ±1.5°) |
| 8 | **Exhaust open-end reflection** (Levine & Schwinger 0.6133a) | `exhaust_gas` | 2 days | Levine & Schwinger 1948; Silva 2009 |
| 9 | **Pacejka Magic Formula tire model** (replace simple μ(slip)) | `wheel` + `abs_controller` | 5 days | Moto-Braking-Dynamics; Pacejka MF 6.2 coeffs |
| ~~10~~ | ✅ **ABS hysteresis validation** — closed by `tests/unit/sim/abs_controller_test.gd` (spec constants, not measured wheel data) | `abs_controller` | — | Bosch ABS literature; Moto-Braking `[hand]` |
| 11 | **Launch PI control vs measured clutch slip/RPM** | `ecu` + `engine_sim` | 3 days | OEM launch data (rare) |
| ~~12~~ | ✅ **Chen-Flynn FMEP vs speed** — closed by `tests/unit/engine/friction_fmep_test.gd`, exact at 2 load/speed points | `cylinder` | — | Chen & Flynn 1965; Reitz 2018 constants `[hand]` |
| 13 | **Turbo compressor map validation** (Garrett GTX3076R) | `intake_native` | 3 days | `assets/compressor_maps/garrett_gtx3076r.json` |
| 14 | **Automated dyno sweep vs measured curves** (CI gate) | `tests/integration/dyno` | 2 days | `assets/dyno/*.json` |
| 15 | **Two-stroke validation data** | `two_stroke_cylinder` | 5 days | Blair Ch.3; SAE two-stroke papers |

---

## Quick Wins (Existing Public API, No New Production Code)

1. ~~**Gas properties table points**~~ — done: `tests/unit/engine/gas_properties_test.gd`.
2. ~~**C++/GDScript parity**~~ — done: `tests/unit/engine/cylinder_native_test.gd` (1e-9 single step, 600-frame run).
3. **Woschni at 2 points** — run motored (300K, 1 bar, 3000 RPM) and fired (peak 80 bar, 3000 RPM) cases, assert h within 10% of hand calc.
4. **Valve Cd at 3 L/D** — extract Heywood Fig 6-18 points (0.1, 0.25, 0.4), assert `valve_cd(L/D)`.
5. **Orifice choked flow** — hand calc from Heywood App C eq C.8, assert `orifice_mass_flow`.
6. **Exhaust end correction** — assert open-end reflection coefficient at ka=0.1, 0.5, 1.0 vs Levine & Schwinger.

---

## Notes on What Could Not Be Verified

- **Exhaust FV solver (HLLC, WENO, RK3)** — no tests found in `gdextension/` or `tests/`. The solver exists in `exhaust_gas.cpp` but physics validation is absent.
- **Intake native (turbo, compressor map)** — `assets/compressor_maps/garrett_gtx3076r.json` exists but no test reads it.
- **Two-stroke scavenging models** — perfect mixing vs displacement not benchmarked.
- **Fuel film evaporation constants** — FILM_DEPOSIT=0.2, evap rate — no source cited.
- **Chen-Flynn constants** — Reitz 2018 gives C=0.25 bar, PF=0.005, MPSF=0.1; units not fully stated (bar? kPa?).
- **SAE J1349 / DIN 70020 correction factors** — formulas quoted by secondary sites only; SAE docs not reached.
- **Toro Test 2 (near-vacuum)** — HLLC known issue; amt911 marks as finding (ignored test).

---

## CI Integration Target

Add to `run_test.bat` / GitHub Actions:
```bash
# Physics validation gate (must pass before merge)
python -m pytest tests/unit/engine/gas_properties_test.py -v
python -m pytest tests/unit/engine/woschni_validation_test.py -v
python -m pytest tests/unit/engine/valve_flow_test.py -v
python -m pytest tests/unit/engine/orifice_flow_test.py -v
python -m pytest tests/unit/exhaust/open_end_reflection_test.py -v
python -m pytest tests/integration/dyno/dyno_regression_test.py --tolerance=0.05
```

---

## References (Cross-Link)

- `docs/engine_physics/13_sources.md` — full bibliography with DOIs
- `docs/engine_physics/14_what_is_still_unverified.md` — known gaps narrative
- `docs/physics-validation.md` — this file (inventory + status)
- `tests/fixtures/sim_golden_trace.json` — regression baseline
- `assets/dyno/*.json` — measured dyno curves
- `amt911/engine-sim/docs/physics-validation.md` — external validation pattern (Nov 2026)
- `vICE` API — turbo matching, fuel DB, Cantera backend
- `Moto-Braking-Dynamics` — Pacejka, load transfer, thermal fade
- GT-Power SAE papers: 2018-01-0161, 2017-01-1794, 2016-01-1816, 2002-01-0492