# Natural Feel Implementation Plan

**Target:** 95% natural feel improvement, <5% CPU overhead
**Timeline:** 3 weekends (20 hours)
**Branch:** `feat/natural-feel-v1`

---

## Phase 1: Foundation (Weekend 1) — Pacejka + Knock

### Task 1.1: Pacejka MF 6.2 Steady-State (`scripts/sim/wheel.gd`)
**Files:** `scripts/sim/wheel.gd`, `tests/unit/sim/pacejka_test.gd`
**Hours:** 4

```gdscript
# Add to Wheel class:
var pacejka_coeffs: Dictionary = {
	# Pure longitudinal (MF 6.2) — example 120/70ZR17 front
	"PCX1": 1.6, "PDX1": 1.0, "PDX2": -0.05, "PDX3": 0.0,
	"PEX1": 0.4, "PEX2": 0.0, "PEX3": 0.0, "PEX4": 0.0,
	"PKX1": 21.0, "PKX2": 10.0, "PKX3": -0.4,
	"PHX1": 0.0, "PHX2": 0.0,
	"PVX1": 0.0, "PVX2": 1.0e5,
	"RBX1": 1.0, "RBX2": 0.0, "RBX3": 0.0,
	"RCX1": 1.0, "REX1": 0.0, "REX2": 0.0,
	"RHX1": 0.0
}

func _pacejka_Fx(kappa: float, Fz: float) -> float:
	# MF 6.2 pure longitudinal — see Pacejka Eq. 4.E1-4.E9
	# Simplified: no camber, no combined slip
	var dx = pacejka_coeffs.PDX1 + pacejka_coeffs.PDX2 * dfz
	var Dx = dx * Fz
	var Cx = pacejka_coeffs.PCX1
	var EX = pacejka_coeffs.PEX1 + pacejka_coeffs.PEX2 * dfz + pacejka_coeffs.PEX3 * dfz^2 + pacejka_coeffs.PEX4 * sgn(kappa)
	var BCDx = pacejka_coeffs.PKX1 + pacejka_coeffs.PKX2 * dfz + pacejka_coeffs.PKX3 * dfz^2
	var Bx = BCDx / (Cx * Dx + 1e-9)
	var Shx = pacejka_coeffs.PHX1 + pacejka_coeffs.PHX2 * dfz
	var Svx = Fz * (pacejka_coeffs.PVX1 + pacejka_coeffs.PVX2 * dfz)
	var k = kappa + Shx
	var Fx = Dx * sin(Cx * atan(Bx * k - EX * (Bx * k - atan(Bx * k)))) + Svx
	return Fx

func mu(kappa: float) -> float:
	if pacejka_coeffs.is_empty():
		return _simple_mu(kappa)  # fallback
	var Fz = load_n
	if Fz <= 0.0: return 0.0
	return _pacejka_Fx(kappa, Fz) / Fz
```

**Validation:** `tests/unit/sim/pacejka_test.gd` — assert peak Fx at κ=0.12 ≈ 1.05×Fz, locked ≈ 0.75×Fz

---

### Task 1.2: Knock Proxy (Livengood-Wu) (`scripts/engine/cylinder.gd`, `scripts/engine/two_stroke_cylinder.gd`)
**Files:** `scripts/engine/cylinder.gd`, `scripts/engine/two_stroke_cylinder.gd`, `tests/unit/engine/knock_test.gd`
**Hours:** 2

```gdscript
# Add to Cylinder class:
const KNOCK_EA := 150000.0  # J/mol (typical for gasoline)
const KNOCK_N := 1.7        # pressure exponent
const KNOCK_A := 1.0e-6     # pre-exponential (calibrate)

var knock_integral: float = 0.0
var knock_retard_deg: float = 0.0

func _update_knock(dt: float, p: float, T: float) -> void:
	if not running: return
	knock_integral += dt * KNOCK_A * pow(p, KNOCK_N) * exp(-KNOCK_EA / (R * T))
	if knock_integral > 1.0:
		knock_retard_deg = min(knock_retard_deg + 2.0, 10.0)  # max 10° retard
		knock_integral = 0.0
	else:
		knock_retard_deg = max(knock_retard_deg - 0.5, 0.0)  # recover slowly

# In advance(), after combustion:
_update_knock(dt, pressure, temp)
```

**ECU Integration** (`scripts/ecu/ecu.gd`):
```gdscript
# In update(), after getting knock_retard_deg from cylinder:
var knock_trim = -max(cylinders.max_by("knock_retard_deg").knock_retard_deg, 0.0)
trim += knock_trim  # adds to spark retard
```

**Validation:** `tests/unit/engine/knock_test.gd` — at 15:1 AFR, 30° advance, 10000 RPM → knock integral > 1 within 2 sec

---

### Task 1.3: Metghalchi-Keck Flame Speed (`scripts/engine/cylinder.gd`, `scripts/engine/two_stroke_cylinder.gd`)
**Files:** `scripts/engine/cylinder.gd`, `scripts/engine/two_stroke_cylinder.gd`, `tests/unit/engine/flame_speed_test.gd`
**Hours:** 3

```gdscript
# Add to Cylinder class (from ATG source / Metghalchi-Keck 1982):
const MK_SU0_BM := 26.32  # cm/s
const MK_SU0_B2 := -84.72 # cm/s
const MK_PHI_M := 1.13

func _metghalchi_keck_su(T_u: float, p: float, phi: float, f_diluent: float) -> float:
	# S_u = S_u0 * (T_u/298)^α * (p/1atm)^β * (1 - 2.1*f)
	# S_u0 = B_m + B_2*(φ - φ_m)^2
	var S_u0 = MK_SU0_BM + MK_SU0_B2 * (phi - MK_PHI_M)^2
	var alpha = 2.18 - 0.8 * (phi - 1.0)
	var beta = -0.16 + 0.22 * (phi - 1.0)
	var Su = S_u0 * pow(T_u / 298.0, alpha) * pow(p / 101325.0, beta) * (1.0 - 2.1 * f_diluent)
	return max(Su * 0.01, 0.001)  # cm/s → m/s, floor at 1 mm/s

func _burn_duration_deg() -> float:
	# Replace fixed BURN_DEG_BASE + BURN_DEG_PER_RPM * RPM
	# burn_deg ≈ 720 * (flame_travel_distance / Su) / (bore * RPM/60)
	# Simplified: burn_deg ∝ 1/Su
	var Su = _metghalchi_keck_su(temp, pressure, lambda_to_phi(lambda), burnt)
	var base_deg = 30.0 * (0.5 / max(Su, 0.01))  # calibrate at Su=0.5 m/s → 30°
	return clampf(base_deg, 15.0, 60.0)
```

**Validation:** `tests/unit/engine/flame_speed_test.gd` — at φ=1.0, T=300K, p=1atm → Su ≈ 0.4 m/s; burn_deg ≈ 30° at 5000 RPM

---

## Phase 2: Turbo + Validation (Weekend 2)

### Task 2.1: Turbo Compressor Map (`gdextension/src/intake_native.cpp`)
**Files:** `gdextension/src/intake_native.cpp`, `gdextension/include/intake_native.h`, `tests/unit/intake/turbo_map_test.gd`
**Hours:** 2

```cpp
// Add to IntakeNative:
struct CompressorMap {
    std::vector<double> pr;      // pressure ratio
    std::vector<double> flow;    // corrected mass flow (kg/s)
    std::vector<double> eff;     // isentropic efficiency
    std::vector<double> speed;   // corrected speed (RPM)
    
    // Bilinear interp: PR, eff = f(flow, speed)
    std::pair<double, double> lookup(double mdot_corr, double N_corr) const;
};

void load_compressor_map(const char* json_path);  // loads garrett_gtx3076r.json

// In step():
// 1. Correct mdot, N for inlet T/P
// 2. Lookup PR, eff
// 3. Compute outlet T = T_in * (PR^((γ-1)/γ) - 1) / eff + T_in
// 4. Wastegate: if PR > target, bypass flow
```

**Validation:** `tests/unit/intake/turbo_map_test.gd` — at design point (mdot=0.05 kg/s, N=100k RPM) → PR=2.0, eff=0.72 ±0.02

---

### Task 2.2: SAE J1349 Correction (`scripts/dyno/dyno_report.gd`)
**Files:** `scripts/dyno/dyno_report.gd`
**Hours:** 0.5

```gdscript
func sae_j1349_correction(p_meas: float, p_amb: float, T_amb: float) -> float:
	# P_std = 99.0 kPa, T_std = 298 K (25°C)
	const P_STD = 99000.0
	const T_STD = 298.0
	var cf = pow(P_STD / p_amb, 1.18) * pow(T_amb / T_STD, 0.18)
	return p_meas * cf

# Apply in dyno report generation
```

---

### Task 2.3: Woschni Validation & Tune (`tests/unit/engine/woschni_validation_test.gd`)
**Files:** `tests/unit/engine/woschni_validation_test.gd` (create), tune constants in `scripts/engine/cylinder.gd`
**Hours:** 4

```gdscript
# Test 1: Motored
# 300 K, 1 bar, 3000 RPM, B=0.086, S=0.056, CR=12
# Expected h ≈ 1250 W/m²K ±12%

# Test 2: Fired
# 2500 K, 80 bar, 3000 RPM, same geometry
# Expected h ≈ 8500 W/m²K ±12%

# Tune wall_heat_scale in engine_sim.gd to match both
```

**Deliverable:** Updated `WOSCHNI_C1_*`, `WOSCHNI_C2_*`, `wall_heat_scale` constants

---

### Task 2.4: Exhaust End Correction Validation (`tests/unit/exhaust/open_end_reflection_test.gd`)
**Files:** `tests/unit/exhaust/open_end_reflection_test.gd` (create)
**Hours:** 1

```gdscript
# Verify ExhaustNative.reflection_coeff(ka) matches Levine & Schwinger
# ka=0.01 → |R| ≈ 0.99995
# ka=0.1  → |R| ≈ 0.995
# ka=1.0  → phase lag → end correction 0.6133a
```

---

## Phase 3: Polish + CI (Weekend 3)

### Task 3.1: Mode Switch (Arcade vs Sim) (`scripts/sim/wheel.gd`, `scripts/app/main.gd`)
**Files:** `scripts/sim/wheel.gd`, `scripts/app/main.gd`, `scripts/ui/panel/control_panel.gd`
**Hours:** 2

```gdscript
# Wheel.gd
enum PhysicsMode { ARCADE, SIMULATION }
var physics_mode = PhysicsMode.SIMULATION

func mu(kappa: float) -> float:
	if physics_mode == PhysicsMode.ARCADE or pacejka_coeffs.is_empty():
		return _simple_mu(kappa)
	return _pacejka_mu(kappa)

# UI: Add toggle in control panel
```

---

### Task 3.2: CI Physics Gate (`run_test.bat`, `.github/workflows/physics.yml`)
**Files:** `run_test.bat`, `.github/workflows/physics.yml` (new)
**Hours:** 2

```yaml
# .github/workflows/physics.yml
name: Physics Validation
on: [push, pull_request]
jobs:
  physics-tests:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Godot
        uses: setup-godot@v1
      - name: Run validation tests
        run: |
          godot --headless -s addons/gut/gut_cmdln.gd \
            -gdir=res://tests/unit/engine \
            -ginclude="*validation*" \
            -ginclude="*valve*" \
            -ginclude="*orifice*" \
            -ginclude="*woschni*" \
            -ginclude="*knock*" \
            -ginclude="*flame_speed*"
      - name: Run dyno regression
        run: |
          godot --headless -s addons/gut/gut_cmdln.gd \
            -gdir=res://tests/integration/dyno \
            -ginclude="*regression*"
```

---

### Task 3.3: Dyno Regression Test (`tests/integration/dyno/dyno_regression_test.gd`)
**Files:** `tests/integration/dyno/dyno_regression_test.gd`
**Hours:** 3

```gdscript
# Tests all 5 bikes in assets/dyno/*.json
# ±5% torque, ±3% power tolerance
# Runs headless, outputs JSON summary for CI
```

---

### Task 3.4: Documentation Update (`docs/physics-validation.md`, `docs/QUICK_REFERENCE.md`)
**Files:** Update status tables
**Hours:** 1

---

## File Touch Summary

| File | Phase | Change Type |
|------|-------|-------------|
| `scripts/sim/wheel.gd` | 1, 3 | Major (Pacejka + mode switch) |
| `scripts/engine/cylinder.gd` | 1 | Major (knock + flame speed) |
| `scripts/engine/two_stroke_cylinder.gd` | 1 | Major (knock + flame speed) |
| `scripts/ecu/ecu.gd` | 1 | Minor (knock trim) |
| `gdextension/src/intake_native.cpp` | 2 | Major (turbo map) |
| `gdextension/include/intake_native.h` | 2 | Minor (API) |
| `scripts/dyno/dyno_report.gd` | 2 | Minor (SAE J1349) |
| `scripts/app/main.gd` | 3 | Minor (mode toggle) |
| `scripts/ui/panel/control_panel.gd` | 3 | Minor (UI toggle) |
| `tests/unit/sim/pacejka_test.gd` | 1 | New |
| `tests/unit/engine/knock_test.gd` | 1 | New |
| `tests/unit/engine/flame_speed_test.gd` | 1 | New |
| `tests/unit/intake/turbo_map_test.gd` | 2 | New |
| `tests/unit/engine/woschni_validation_test.gd` | 2 | New |
| `tests/unit/exhaust/open_end_reflection_test.gd` | 2 | New |
| `tests/integration/dyno/dyno_regression_test.gd` | 3 | New |
| `.github/workflows/physics.yml` | 3 | New (CI) |
| `run_test.bat` | 3 | Minor (add physics gate) |

---

## Acceptance Criteria (Definition of Done)

| Feature | Metric | Target |
|---------|--------|--------|
| Pacejka | Peak Fx at κ=0.12 | 1.05×Fz ±5% |
| Pacejka | Locked Fx at κ=1.0 | 0.75×Fz ±5% |
| Knock | Retard at 15:1 AFR, 30° adv, 10k RPM | >2° within 2 sec |
| Flame speed | φ=1.0, 300K, 1atm | Su = 0.4 m/s ±10% |
| Turbo | Design point (mdot=0.05, N=100k) | PR=2.0, eff=0.72 ±3% |
| Woschni | Motored h | 1250 W/m²K ±12% |
| Woschni | Fired h | 8500 W/m²K ±12% |
| Exhaust | ka=0.1 | |R| = 0.995 ±0.005 |
| Dyno regression | All 5 bikes | Torque ±5%, Power ±3% |
| CPU | Total physics/frame | < 100 μs (10× headroom) |

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Pacejka coefficients wrong for bike tires | Start with Moto-Braking coeffs; add per-bike override in EngineSpec |
| Knock integral too sensitive | Calibrate KNOCK_A on H2R (known knock-limited) first |
| Flame speed changes burn phasing too much | Clamp burn_deg 15-60°; validate against golden trace |
| Turbo map causes instability | Add wastegate PID; limit PR slew rate |
| CI fails on flaky tests | Mark validation tests as `required: true`; dyno regression as `required: false` initially |

---

## Rollback Plan

Each feature behind a feature flag:
```gdscript
# ProjectSettings or EngineSpec
physics/pacejka_enabled = true
physics/knock_enabled = true
physics/flame_speed_enabled = true
physics/turbo_enabled = true
```
If any breaks feel → toggle off instantly without code revert.

---

## Estimated Timeline

| Weekend | Tasks | Hours | Deliverable |
|---------|-------|-------|-------------|
| **1** | 1.1, 1.2, 1.3 | 9 | Pacejka + Knock + Flame Speed working |
| **2** | 2.1, 2.2, 2.3, 2.4 | 7.5 | Turbo + Validation tests passing |
| **3** | 3.1, 3.2, 3.3, 3.4 | 5.5 | Mode switch + CI gate + Docs |

**Total:** ~22 hours (buffer included)

---

## Post-Plan (Not in Scope)

| Feature | Reason Deferred |
|---------|-----------------|
| Transient Pacejka (relaxation) | 2-3× CPU; steady-state gives 90% feel |
| Cantera chemistry | 1000× CPU; knock proxy covers detonation |
| Multi-zone combustion | 10× CPU; single-zone + flame speed sufficient |
| Brake thermal fade | Only matters for 5+ min descents |
| Emissions (CO/NOx) | No feel impact |
| Detailed spray | Film evaporation already captures wall-wetting feel |