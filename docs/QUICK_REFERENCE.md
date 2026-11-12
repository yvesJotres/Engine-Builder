# Engine Builder — Quick Reference Card

**Generated:** 2026-11-12
**Purpose:** One-page summary of validation targets, key files, and next actions.

---

## 🎯 Top 5 Validation Targets (This Week)

| # | Target | File to Create | Reference |
|---|--------|----------------|-----------|
| 1 | Gas properties table points (300/1000/2000/3000 K) | `tests/unit/engine/gas_properties_test.gd` | Keenan & Kaye tables |
| 2 | C++/GDScript parity (1e-9) | `tests/unit/engine/cylinder_native_test.gd` | `cylinder_kernel.cpp:19` |
| 3 | Woschni at 2 points (motored + fired) | `tests/unit/engine/woschni_validation_test.gd` | Qasemian 2020 Table 1 |
| 4 | Valve Cd vs L/D (3 points) | `tests/unit/engine/valve_flow_test.gd` | Heywood Fig 6-18 |
| 5 | Orifice choked/subsonic flow | `tests/unit/engine/orifice_flow_test.gd` | Heywood App C |

---

## 📁 Key Reference Files

| Category | File | Use For |
|----------|------|---------|
| **Validation inventory** | `docs/physics-validation.md` | Complete test status + gaps |
| **Competitor analysis** | `docs/competitor_analysis.md` | External references, patterns |
| **Test templates** | `docs/validation_test_templates.md` | Copy-paste GDScript tests |
| **Unverified log** | `docs/engine_physics/14_what_is_still_unverified.md` | Ranked gaps + action items |
| **Sources** | `docs/engine_physics/13_sources.md` | Paper DOIs + local copies |
| **Measured dyno** | `assets/dyno/*.json` (5 bikes) | Regression baseline |
| **Compressor map** | `assets/compressor_maps/garrett_gtx3076r.json` | Turbo validation |
| **CBR250RR ref** | `docs/cbr250rr_references/local/` | ATG source, dyno curves, photos |
| **Golden trace** | `tests/fixtures/sim_golden_trace.json` | Regression (36 frames × 4 bikes) |

---

## 🔬 External Validation Targets (From Competitors)

| Source | Key Data | Access |
|--------|----------|--------|
| **amt911/engine-sim** | 40+ external-value tests, mutation testing | GitHub (open) |
| **vICE** | Fuel DB, turbo matching, Cantera backend | GitHub + GitHub Pages |
| **Moto-Braking** | Pacejka MF 6.2, load transfer, thermal fade | GitHub (open) |
| **GT-Power SAE 2018-01-0161** | Turbo GDI correlation: ±2% torque, ±3% BSFC | EPA snapshot (open) |
| **GT-Power SAE 2017-01-1794** | Exhaust acoustic correlation | SAE (paywalled) |
| **Levine & Schwinger 1948** | Open-end correction 0.6133a | Phys. Rev. (open) |
| **Silva et al. 2009** | Exhaust reflection fit | J. Sound Vib. (paywalled) |

---

## ⚡ Quick Commands

```bash
# Run physics validation tests (when created)
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/engine -ginclude="*validation*"

# Run dyno regression (when created)
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration/dyno -ginclude="*regression*"

# Check golden trace diff
git diff tests/fixtures/sim_golden_trace.json

# Build native extension
cd gdextension && ./build.bat

# Run all tests
./run_test.bat
```

---

## 🏷️ External Value Tags (Use in Tests)

| Tag | Meaning | Example |
|-----|---------|---------|
| `[hand]` | Hand evaluation of cited formula | `assert_near(h, 1250, 150)  # [hand] Woschni calc` |
| `[closed]` | Exact closed form / limit | `assert_eq(R, 0.5283)  # [closed] critical pressure ratio` |
| `[table]` | Published table value | `assert_eq(cp_air(300), 1005)  # [table] Keenan & Kaye` |
| `[fig]` | Value read from published figure | `assert_near(Cd, 0.95, 0.05)  # [fig] Heywood Fig 6-18` |
| `[meas]` | Published measurement | `assert_near(torque, 120, 5)  # [meas] dyno curve` |
| `[ind]` | Independent implementation | `assert_near(cpp, gd, 1e-9)  # [ind] C++ vs GDScript` |

---

## 📊 Competitor Capability Summary

| Feature | You | amt911 | vICE | Moto-Braking | GT-Power |
|---------|-----|--------|------|--------------|----------|
| Temp-dependent gas props | ✅ | ❌ | ❌ | ❌ | ✅ |
| 1D exhaust waves | ✅ | ✅ | ❌ | ❌ | ✅ |
| Two-stroke | ✅ | ❌ | ❌ | ❌ | ✅ |
| PI launch control | ✅ | ❌ | ❌ | ❌ | ✅ |
| ABS + wheel slip | ✅ | ❌ | ❌ | ❌ (no ABS) | ✅ |
| Pacejka tire | ❌ | ❌ | ❌ | ✅ | ✅ |
| Turbo matching | ❌ (map only) | ✅ | ✅ | ❌ | ✅ |
| Validation tests | 🟡 (planned) | ✅ 40+ | 🟡 (Cantera) | 🟡 (academic) | ✅ 1000+ |
| Real-time 3D/audio | ✅ | ❌ | ❌ | ❌ | ❌ |

---

## 📅 Next Actions (Priority Order)

1. **P0** — Create 5 validation test files (gas_props, parity, Woschni, valve, orifice)
2. **P1** — Exhaust open-end reflection test (Levine & Schwinger)
3. **P2** — Pacejka tire model + ABS hysteresis tests
4. **P2** — Automated dyno regression (±5% on 5 bikes)
5. **P3** — Chen-Flynn friction + Turbo compressor map tests

---

## 📚 Papers to Acquire (Library/SAE)

| Paper | Why | Status |
|-------|-----|--------|
| SAE 670931 (Woschni) | Original constants, units | Paywalled |
| SAE 650733 (Chen-Flynn) | Original friction eq | Paywalled |
| SAE 820154 / 962527 | Valve Cd vs L/D | Paywalled |
| Heywood Ch.9,12,13 | Flame, heat transfer, friction | Library only |
| SAE J1349 / DIN 70020 | Correction formulas | Paywalled |
| SAE 2002-01-0492 | SI combustion validation | Paywalled |
| Pacejka MF 6.2 | Tire coefficients | Book (€200) |

---

## 🔗 Cross-References

- `docs/physics-validation.md` ← Master inventory (start here)
- `docs/competitor_analysis.md` ← Deep dive on each competitor
- `docs/validation_test_templates.md` ← Copy-paste test code
- `docs/engine_physics/14_what_is_still_unverified.md` ← Ranked gaps + action items
- `docs/engine_physics/13_sources.md` ← Bibliography with DOIs