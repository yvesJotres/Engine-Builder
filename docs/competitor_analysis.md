# Competitor Analysis & Reference Data

**Generated:** 2026-11-12
**Purpose:** Centralized reference for validation targets, competitor capabilities, and external data sources.

---

## 1. Competitor Capability Matrix

| Capability | Engine Builder (You) | amt911/engine-sim | vICE | Engine Sim (ange-yaghi) | Moto-Braking | GT-Power/WAVE |
|------------|---------------------|-------------------|------|------------------------|--------------|---------------|
| **Crank-resolved thermodynamics** | ✅ | ✅ | ✅ (0-D cycle) | ✅ | ❌ | ✅ |
| **Temp-dependent gas properties** | ✅ (29-pt tables) | ❌ (constant γ) | ❌ (polytropic) | ❌ | ❌ | ✅ |
| **1D exhaust gas dynamics** | ✅ (C++ FV) | ✅ (HLLC + WENO5-Z) | ❌ | ❌ | ❌ | ✅ |
| **1D intake + turbo** | ✅ (native) | ✅ (compressor map) | ✅ (mean-value) | ❌ | ❌ | ✅ |
| **Two-stroke support** | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |
| **ECU: idle / launch / quickshift / overrun** | ✅ (PI launch) | ❌ | ❌ | ❌ (RPM hold) | ❌ | ✅ |
| **Drivetrain: clutch / gearbox / chain** | ✅ | ❌ | ❌ | ✅ (basic) | ❌ | ✅ |
| **Wheel slip + ABS** | ✅ (hysteresis) | ❌ | ❌ | ✅ (basic brakes) | ✅ (Pacejka, no ABS) | ✅ |
| **Tire model** | Simple peak | ❌ | ❌ | Simple | **Pacejka MF 6.2** | ✅ |
| **Vehicle dynamics (load transfer)** | ✅ (CG height) | ❌ | ❌ | ❌ | ✅ | ✅ |
| **Friction (Chen-Flynn / Pulkrabek)** | ✅ | ✅ | ✅ (FMEP-speed) | ❌ | ❌ | ✅ |
| **Heat transfer (Woschni/Annand)** | ✅ | ✅ | ✅ (parametric) | ✅ (coeff only) | ❌ | ✅ |
| **Combustion (Wiebe + temp-dep)** | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| **Fuel film / wall wetting** | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Knock model** | ❌ | ❌ | ✅ (proxy) | ❌ | ❌ | ✅ |
| **Emissions (CO/NOx/soot)** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Full chemistry (Cantera)** | ❌ | ❌ | ✅ (optional) | ❌ | ❌ | ✅ (optional) |
| **Real-time 3D + audio** | ✅ (Godot) | ❌ | ❌ | ✅ (audio focus) | ❌ (web) | ❌ |
| **Physics validation tests** | 🟡 (this doc) | ✅ (40+ external) | 🟡 (Cantera ref) | ❌ | 🟡 (academic) | ✅ (1000+, proprietary) |
| **CI / mutation testing** | ❌ | ✅ (nextest, mutants) | 🟡 (docs only) | ❌ | ❌ | Internal |
| **Open source** | ✅ | ✅ (Rust) | ✅ (Python) | ✅ (C++) | ✅ (Py/TS) | ❌ |

---

## 2. Validation Targets from Commercial Tools (GT-Power/WAVE)

### SAE Correlation Papers (Public)

| Paper | Engine | Correlation Targets | Method |
|-------|--------|---------------------|--------|
| **SAE 2018-01-0161** | 1.6L GDI + VNT + LP-EGR + CVVL | Torque ±2%, BSFC ±3%, Turbo speed ±3%, P_intake ±5 kPa, P_exhaust ±5 kPa | Full-load speed sweep, chassis dyno |
| **SAE 2017-01-1794** | Turbo SI (intake) / NA (exhaust) | 1D pressure waves vs mic measurements | Fixed-gear WOT, chassis dyno |
| **SAE 2016-01-1816** (Tiikoja) | Pipe heat transfer | Wall temp, gas temp, pressure trace | Kirchhoff α validation |
| **SAE 2002-01-0492** | SI combustion | IMEP ±3%, Peak P ±5%, CA50 ±1.5° | Cylinder pressure transducer |

### Typical OEM Acceptance Criteria

| Metric | Target |
|--------|--------|
| Torque curve (full load) | ±2% across speed range |
| BSFC (best island) | ±3% |
| BSFC (part load) | ±5% |
| Peak cylinder pressure | ±5% |
| CA50 (combustion phasing) | ±1.5° CA |
| Turbo speed | ±3% |
| Exhaust manifold pressure | ±5 kPa |
| Intake manifold pressure | ±3 kPa |
| Volumetric efficiency | ±3% |
| FMEP vs speed | ±10% |

---

## 3. Reference Data Available in This Repo

| File | Type | Bikes | Use For |
|------|------|-------|---------|
| `assets/dyno/honda_cbr1000rrr_sp.json` | Measured dyno | CBR1000RR-R SP | Torque/power validation |
| `assets/dyno/kawasaki_h2r.json` | Measured dyno | H2R | Turbo validation (future) |
| `assets/dyno/kawasaki_zx25r.json` | Measured dyno | ZX-25R | Small-bike validation |
| `assets/dyno/yamaha_yzf_r1m.json` | Measured dyno | YZF-R1M | High-RPM validation |
| `assets/dyno/honda_cbr250rr_2020.json` | Measured dyno | CBR250RR 2020 | 250cc validation |
| `docs/cbr250rr_references/local/dyno/cbr250rr_reference_curve.json` | Measured dyno | CBR250RR | Regression baseline |
| `docs/cbr250rr_references/local/sim_graphs/woschni_native.png` | Heat transfer comparison | CBR250RR | Woschni validation |
| `docs/cbr250rr_references/local/atg/*.mr` + C++ | ATG engine-sim source | CBR250RR | Cross-reference implementation |
| `assets/compressor_maps/garrett_gtx3076r.json` | Compressor map | Generic | Turbo matching validation |

---

## 4. Key External References (From Competitors)

### amt911/engine-sim Physics Validation (Nov 2026)
**File:** `docs/physics-validation.md` (their repo)
- **40+ external value tests** across gas dynamics, valves, combustion, heat transfer, friction, acoustics
- **Pattern:** Every test asserts `[hand]`, `[closed]`, `[table]`, `[fig]`, `[meas]`, or `[ind]` reference
- **Gap list ranked by sound impact** — 15 gaps with quick wins identified
- **Mutation testing + coverage gates** in CI

### vICE (Python, 2026)
**API:** https://pablomarcel.github.io/vICE/api.html
- **Fuel database:** gasoline, methanol, E85, ethanol, methane — LHV, AFR, flame temp
- **Turbo tools:** Compressor/turbine maps, operating line, GT4088-like map
- **Cantera backend:** Optional equilibrium flame temp
- **Workflow:** JSON → Python → JSON → Plotly/HTML

### Moto-Braking-Dynamics (2026)
**Pacejka Magic Formula 6.2** coefficients for motorcycle tires
- **Load transfer:** ΔFz = m·a·h/L (h=0.62m, front_static=0.48)
- **Thermal fade:** Pad μ(T), fluid boiling, drum limits
- **Surface conditions:** Wet, gravel, thermoplastic markings

### ATG Engine-Sim (Local Copy)
**Location:** `docs/cbr250rr_references/local/atg/`
- `cbr250rr.mr`, `cbr250rr_sp.mr` — Model files
- `combustion_chamber.cpp`, `cylinder_head.cpp`, `fuel.cpp`, `gas_system.cpp` — Source
- **Laminar flame speed correlation** (Metghalchi-Keck)
- **Turbulence & flame-speed model**
- **Woschni heat transfer** implementation reference

---

## 5. Validation Test Templates (From amt911 Pattern)

```gdscript
# Template: External value test
# Tag: [table] [hand] [closed] [fig] [meas] [ind]

func test_gas_properties_cp_air_table_points():
    # [table] Keenan & Kaye / Cengel Thermodynamics Appendix
    assert_eq(GasProperties.cp_air(300.0), 1005.0, 1.0)    # 300 K
    assert_eq(GasProperties.cp_air(1000.0), 1142.0, 2.0)   # 1000 K
    assert_eq(GasProperties.cp_air(2000.0), 1278.0, 3.0)   # 2000 K
    assert_eq(GasProperties.cp_air(3000.0), 1328.0, 5.0)   # 3000 K

func test_woschni_heat_transfer_motored():
    # [hand] Woschni SAE 670931, Qasemian 2020 Table 1
    # Motored: 300 K, 1 bar, 3000 RPM, B=0.086m, L=0.056m
    var h = Cylinder.woschni_h(300.0, 1e5, 3000.0, 0.086, 0.056, 1.0)
    assert_near(h, 1250.0, 150.0)  # W/(m²·K) — hand calc ~1250

func test_valve_cd_vs_ld():
    # [fig] Heywood Fig 6-18, p.229; SAE 820154
    assert_near(Cylinder.valve_cd(0.1), 0.35, 0.05)
    assert_near(Cylinder.valve_cd(0.25), 0.55, 0.05)
    assert_near(Cylinder.valve_cd(0.4), 0.70, 0.05)

func test_orifice_choked_flow():
    # [hand] Heywood App C eq C.8
    # Cd=0.7, A=1e-4 m², p0=5e5 Pa, T0=300 K, γ=1.4
    var mdot = GasProperties.orifice_mass_flow(0.7, 1e-4, 5e5, 300.0, 1.4)
    assert_near(mdot, 0.04667, 0.001)  # kg/s

func test_exhaust_open_end_reflection():
    # [closed] Levine & Schwinger 1948: end correction = 0.6133a
    # [ind] Silva et al. 2009 fit
    var R = ExhaustNative.reflection_coeff(0.1)  # ka=0.1
    assert_near(R, 0.995, 0.01)  # |R| ≈ 1 - (ka)²/2
```

---

## 6. Immediate Action Items

| Priority | Task | File to Create/Modify | Reference |
|----------|------|----------------------|-----------|
| **P0** | Gas properties table point tests | `tests/unit/engine/gas_properties_test.gd` | Keenan & Kaye tables |
| **P0** | C++/GDScript parity test (1e-9) | `tests/unit/engine/cylinder_native_test.gd` | amt911 pattern |
| **P0** | Woschni validation at 2 points | `tests/unit/engine/woschni_validation_test.gd` | Qasemian 2020, SAE 670931 |
| **P1** | Valve Cd vs L/D (3 points) | `tests/unit/engine/valve_flow_test.gd` | Heywood Fig 6-18 |
| **P1** | Orifice choked/subsonic flow | `tests/unit/engine/orifice_flow_test.gd` | Heywood App C |
| **P1** | Exhaust open-end reflection | `tests/unit/exhaust/open_end_reflection_test.gd` | Levine & Schwinger 1948 |
| **P2** | Pacejka tire model (replace μ(slip)) | `scripts/sim/wheel.gd` + test | Moto-Braking, Pacejka MF 6.2 |
| **P2** | ABS hysteresis validation | `tests/unit/sim/abs_controller_test.gd` | Bosch, Moto-Braking |
| **P2** | Automated dyno regression | `tests/integration/dyno/dyno_regression_test.gd` | `assets/dyno/*.json` ±5% |
| **P3** | Chen-Flynn FMEP validation | `tests/unit/engine/friction_test.gd` | Chen & Flynn 1965, Reitz 2018 |
| **P3** | Turbo compressor map test | `tests/unit/intake/turbo_map_test.gd` | `assets/compressor_maps/garrett_gtx3076r.json` |

---

## 7. Bibliography (Cross-Reference)

| Source | Type | Access | Local Copy |
|--------|------|--------|------------|
| Heywood, *IC Engine Fundamentals* | Textbook | Ch.6,9,10,12,13 | `docs/papers/DE0047750EE...pdf` (front matter only) |
| Woschni SAE 670931 | Paper | DOI: 10.4271/670931 | — |
| Qasemian 2020 (IOP) | Paper | Open access | `docs/papers/Qasemian_2020...pdf` |
| Chen & Flynn SAE 650733 | Paper | DOI: 10.4271/650733 | — |
| Patton et al. SAE 890836 | Paper | DOI: 10.4271/890836 | — |
| Metghalchi & Keck 1982 | Paper | Open access (Keck collection) | — |
| SAE 820154 / 962527 | Papers | SAE Mobilus | — |
| Levine & Schwinger 1948 | Paper | Phys. Rev. 73 | — |
| Silva et al. 2009 | Paper | J. Sound Vib. 322 | — |
| Toro, *Riemann Solvers* | Textbook | Ch.10 (Sod test) | — |
| Borges et al. 2008 | Paper | J. Comput. Phys. 227 | — |
| GT-Power SAE 2018-01-0161 | Paper | EPA snapshot / ResearchGate | — |
| GT-Power SAE 2017-01-1794 | Paper | SAE Mobilus | — |
| Moto-Braking-Dynamics | Repo | GitHub: kzc0des/Moto-Braking-Dynamics | — |
| amt911/engine-sim | Repo | GitHub: amt911/engine-sim | — |
| vICE | Repo + Docs | GitHub: pablomarcel/vICE + GitHub Pages | — |

---

## 8. Competitor Code Patterns to Adopt

### From amt911 (Rust)
- **Physics-validation.md** as living document (this file)
- **Mutation testing** (cargo mutants + nextest)
- **Coverage gates** (skip long engine sims in coverage, run in full test)
- **External-value test tags** `[hand]`, `[table]`, `[closed]`, `[fig]`, `[meas]`, `[ind]`
- **Gap list ranked by impact** with quick wins identified

### From vICE (Python)
- **JSON → solver → JSON → plots** workflow
- **Fuel database** with multiple fuels
- **Turbo matching tools** (compressor map + operating line)
- **Cantera optional backend** for validation
- **Sphinx documentation** with API reference

### From Moto-Braking (Python/TS)
- **Pacejka MF 6.2** parameter structure
- **Load transfer** with CG height
- **Thermal fade** modeling (pad, fluid, drum)
- **Surface condition** enum (dry, wet, gravel, markings)

### From ATG (C++)
- **Laminar flame speed** correlation (Metghalchi-Keck)
- **Turbulence-flame interaction** model
- **Woschni implementation** reference

---

## 9. Measurement Data Sources (For Future Validation)

| Source | Data Type | Access |
|--------|-----------|--------|
| SAE J1349 / DIN 70020 | Dyno correction factors | SAE (paid) / secondary sites |
| ISO 18164 | Motorcycle rolling resistance | Energy Reports 2021 (open) |
| IEA AMF | Gasoline properties (LHV, density, AFR) | Open |
| Sandia ECN | Fuel properties table (iso-octane) | Open |
| Engineering Toolbox | Air composition, molar mass | Open |
| NPTEL | Liquid fuel properties | Open |
| Colorado State | Engine heat transfer correlations | Open (course notes) |
| OpenModelica | Annand heat transfer citation | Open |
| MIT 2.61 OCW | Heywood chapter map, corrections | Open |

---

## 10. Maintenance

- **Update this file** when new validation tests are added
- **Mark status** ✅/🟡/❌ in Section 1–10 tables
- **Add new gaps** to ranked list (Section 12)
- **Cross-reference** competitor releases (amt911 moves fast — check monthly)
- **Archive** superseded data in `calibration/backups/`