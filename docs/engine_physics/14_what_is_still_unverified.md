# 14. Fact-check log and what is still unverified

[Index](README.md) · Physics reference

This log covers the claims in sections 1–13, tagged as in the index. Later passes read the Metghalchi–Keck, Qasemian, Tadros and Reitz papers, and the MIT OCW corrections, in full. Items still open are listed at the end.

**Updated 2026-11-12** with competitor validation patterns (amt911/engine-sim, vICE, Moto-Braking-Dynamics, GT-Power SAE papers).

---

## Closed in the later passes

**Read in full text:**

- **Metghalchi and Keck (1982), Combustion and Flame 48, 191.** The text was extracted from the PDF in the James Keck memorial collection. It confirms:
  - The power-law form S_u = S_u0 (T_u/T0)^α (p/p0)^β (1 − 2.1 f), with T0 = 298 K, p0 = 1 atm, S_u in cm/s, p in atm, and f the diluent mass fraction (not the residual gas fraction).
  - α = 2.18 − 0.8(φ − 1) and β = −0.16 + 0.22(φ − 1).
  - S_u0 = B_m + B_2(φ − φ_m)², with isooctane values φ_m = 1.13, B_m = 26.32 cm/s, B_2 = −84.72 cm/s (read from the extracted table; check the printed digits before use in code).
  - The ATG engine-sim flame constants are not this fit. At φ = 1.13 they give about 0.30 m/s against 0.263 m/s, and the exponents differ.

- **Tadros et al. (2025), Algorithms 18(7), 415** (open access). It gives a "standard" Chen–Flynn set in its Table 4: A = 0.5, B = 0.006, C = 600, Q = 0.2. The units are not stated and cannot all be in bar with S in m/s. Its equation is FMEP = A + (1/n) Σ (B·P_max + C·S + Q·S²). Tagged [S].

**Confirmed by a peer-reviewed secondary paper (Qasemian and Rezaei 2020, read in full) [S]:**

- Woschni exponents B^−0.2, P^0.8, T^−0.55, w^0.8, and the gas-velocity form. C1 = 2.28 for compression and combustion/expansion, 6.18 for gas exchange; C2 = 0.00324 (listed as 3.24 × 10⁻³) for combustion and expansion, zero otherwise. The paper's constants are for an HCCI engine and it says they need correction.
- The coefficient 3.26 agrees with the paper's original prefactor X5 = 0.013 (Pa units) once converted: 3.26 × 1000^(−0.8) = 0.0130. This is a units check against one secondary source, not a check against SAE 670931.
- Gasoline LHV 42.9–44 MJ/kg; density 720–775 kg/m³; heat of vaporisation 350–440 kJ/kg; iso-octane density 690.3 kg/m³ and enthalpy of vaporisation 308.4 kJ/kg.
- Air composition and molar mass (two sources agree).
- CA50 optimum near 7–8° ATDC (two SAE papers); peak-pressure crank angle at MBT 12–14° ATDC (one SAE paper).
- Rolling resistance of motorcycle tyres 0.0089–0.0137 (2021 study).
- Annand form (Re exponent 0.7, bore as length scale, mean piston speed as velocity) and coefficient a = 0.35–0.8 (Colorado State notes).
- Rod ratio 3–4 for small engines (x-engineer.org).
- Friction near 10 % of indicated power at full load (Heywood Fig. 13.2, as quoted).
- SAE J1349 correction with the 1.18 and −0.18 terms (calculator and tuning sites).
- Taylor breathing limit Z ≈ 0.5–0.6 (forum sources).

**Confirmed by DOI or citation record [P]:**

- Woschni (1967), SAE 670931, DOI 10.4271/670931. The paper's text was not reached; only the citation.
- Patton, Nitschke, Heywood (1989), SAE 890836, DOI 10.4271/890836.

**Derived or standard definitions [D]:** unit conversions, torque–power constants, BMEP and power relations, swept volume, mean piston speed, cycle counts, choked-flow coefficient 0.685 and critical ratio 0.528, Wiebe a = 6.908, stoichiometric equation and A/F 15.1 for iso-octane, road-speed constant 0.37699.

---

## Corrections made so far

- **Metghalchi–Keck flame speed.** Section 7.3 now gives the full-text equations and isooctane parameters. The ATG constants do not match the 1982 fit.
- **Diluent factor f.** Described as the diluent mass fraction (simulated combustion products), not the residual gas fraction.
- **Chen–Flynn.** Added the standard set quoted in the 2025 paper, with its unit problem noted.
- **Woschni constants.** C1, C2, the exponents and the prefactor are now confirmed by a peer-reviewed paper (Qasemian and Rezaei 2020), tagged [S]. The 3.26 value matches the paper's 0.013 once units are converted.
- **Temperature-dependent gas properties.** Implemented 29-point cp tables for air and burnt gas (300–3000 K), trapezoidal u integration, Newton temp_from_u. Mirrors C++ exactly (1e-9 parity required).
- **Endpoint energy solve.** Newton 4-iteration on m·u(T) - source + ½(p_old + mRT/V)·dV = 0 — exact for any u(T).
- **Residual mixing by energy.** u_mix = (m_air·u_air + m_res·u_res)/m_total; T from u.
- **Two-stroke fixes.** Residual capture at transfer close, burn duration vs RPM, crank radius inertia (was 0).
- **Launch control PI.** Kp=10, Ki=30, bias limit ±1.0, lock at clutch_engage≥0.98.
- **Wheel/ABS model.** Slip ratio, μ(slip) peak 1.05 at 0.12, locked 0.75; load transfer; ABS hysteresis (release 1.15×, reapply 0.8×, slew 60k/12k N·m/s).

---

## Still unverified (and why) — Ranked by Impact

| Rank | Item | Blocker | Competitor Reference |
|------|------|---------|---------------------|
| **1** | **Gas properties table validation** — cp_air/cp_burnt at 300/1000/2000/3000 K vs Keenan & Kaye tables | No unit tests exist | amt911: ✅ table points; vICE: Cantera backend |
| **2** | **C++/GDScript gas_properties parity** — 1e-9 agreement | `cylinder_native_test.gd` referenced but not found | amt911: mutation testing catches this |
| **3** | **Woschni heat transfer at 2 operating points** (motored + fired) vs hand calc | No validation test; Qasemian 2020 gives constants but "needs correction" | amt911: ✅ hand calc at 2 pts; GT-Power: wall temp/heat flux correlation |
| **4** | **Valve Cd vs L/D** (3 points from Heywood Fig 6-18) | No test; SAE 820154/962527 paywalled | amt911: ✅ 2 fig points + slope; Heywood Ch.6 |
| **5** | **Orifice mass flow** (choked + subsonic continuity at critical) | No test; Heywood App C | amt911: ✅ hand calc + continuity |
| **6** | **Closed-cylinder pressure trace** vs published motored data | No SAE 2002-01-0492 access | amt911: ❌ gap #1; GT-Power: ±3% IMEP target |
| **7** | **Fired IMEP / peak P / CA50** vs measured | No cylinder pressure data | GT-Power: ±3%/±5%/±1.5°; amt911: ❌ gap #2-3 |
| **8** | **Exhaust open-end reflection** (Levine & Schwinger 0.6133a) | No test; Silva 2009 fit | amt911: ✅ end correction + Silva fit |
| **9** | **Pacejka Magic Formula tire model** (replace simple μ(slip)) | Not implemented | Moto-Braking: ✅ full MF 6.2; amt911: ❌ |
| **10** | **ABS hysteresis validation** (release/reapply slip, slew rates) | No test | Moto-Braking: load transfer + thermal fade; Bosch lit |
| **11** | **Launch PI control** vs measured clutch slip/RPM trace | No OEM launch data | GT-Power: launch correlation rare |
| **12** | **Chen-Flynn FMEP** vs speed at 3 loads | Reitz 2018 gives C=0.25 bar, PF=0.005, MPSF=0.1 — units unclear | amt911: ✅ Chen-Flynn validation; Tadros 2025 table |
| **13** | **Turbo compressor map** (Garrett GTX3076R) validation | Map exists in assets, no test reads it | vICE: ✅ GT4088 map + operating line; amt911: ✅ Garrett |
| **14** | **Automated dyno sweep** vs measured curves (±5%) | Manual comparison only | GT-Power: full-load sweep correlation |
| **15** | **Two-stroke validation data** | No SAE two-stroke papers reached | Blair Ch.3; ATG source has 2-stroke? |

---

## Original unverified items (from earlier passes)

- **Woschni original text (SAE 670931).** The SAE page only shows a loading screen, and the full text is paywalled. Needs library access.
- **Chen–Flynn values for the speed terms.** The Reitz (2018) lecture gives C = 0.25 bar, PF = 0.005, MPSF = 0.1, MPSSF = 0, but does not state the units of the speed terms.
- **Chen–Flynn original coefficients (SAE 650733).** The SAE record opened: its title is "Development of a Single Cylinder Compression Ignition Research Engine", and the abstract is about engine design, with no friction equation. Full text is paywalled. The 2025 paper's table is a secondary source with unclear units.
- **Heywood's textbook.** The PDF in `docs/papers` is only the front matter and contents (9 pages). It gives the chapter pages: heat transfer is Chapter 12 (page 668), friction Chapter 13 (page 715 for total friction, page 719 for friction data), SI combustion Chapter 9 (page 402). The chapter text is not in our copy. Still needed for Annand's radiation term, wall temperatures, Wiebe m, flame-development values, and the valve curtain area with a seat-angle factor.
- **DIN 70020 formula.** Reference conditions confirmed; formula not found in any source reached [T].
- **SAE J1349 document.** Formula quoted by secondary sites; the revision that keeps these constants is not confirmed [S].
- **Iso-octane lower heating value (44.3 MJ/kg).** Not found in any source reached [T].
- **Wiebe exponent m ≈ 2.** Not confirmed; a secondary source says it is fitted per engine [S].
- **Wall temperatures (liner 400–450 K, head 450–500 K, piston crown 500–600 K).** Recalled only. The lecture notes give ordering and limits, not these means [T].
- **Gearbox efficiency per stage (0.95–0.98)** [T].
- **Helmholtz rule of thumb** (twice the piston frequency) [S].
- **Flame development 18–29°** [S, GitHub discussion citing Heywood Fig. 9-17].
- **Drivetrain efficiency range 0.85–0.92.** General sources only; a measured figure needs a crank and wheel test on one motorcycle.

---

## Next steps that need you or a library

1. Heywood, *Internal Combustion Engine Fundamentals*, chapters 9 (flame development), 12 (heat transfer, Annand, wall temperatures) and 13 (friction, Chen–Flynn). A university library copy would close most of the [T] items.
2. SAE 670931 (Woschni) and SAE 650733 (Chen–Flynn) through a library or the SAE subscription.
3. The SAE J1349 and DIN 70020 standard texts.
4. A measured crank-and-wheel drivetrain efficiency for one motorcycle. This needs a test on a dyno or a coast-down with a known rolling resistance; I cannot do it from here.

---

## Competitor-Driven Action Items (Priority Order)

| Priority | Action | File | Reference |
|----------|--------|------|-----------|
| **P0** | Create `tests/unit/engine/gas_properties_test.gd` with table point assertions | New file | amt911 pattern; Keenan & Kaye tables |
| **P0** | Create `tests/unit/engine/cylinder_native_test.gd` for C++/GDScript 1e-9 parity | New file | `cylinder_kernel.cpp:19` reference |
| **P0** | Create `tests/unit/engine/woschni_validation_test.gd` with 2 hand-calc points | New file | Qasemian 2020 Table 1; amt911 pattern |
| **P1** | Create `tests/unit/engine/valve_flow_test.gd` (Cd vs L/D, curtain area) | New file | Heywood Fig 6-18; SAE 820154 |
| **P1** | Create `tests/unit/engine/orifice_flow_test.gd` (choked/subsonic/continuity) | New file | Heywood App C; amt911 pattern |
| **P1** | Create `tests/unit/exhaust/open_end_reflection_test.gd` (Levine & Schwinger) | New file | Levine & Schwinger 1948; Silva 2009 |
| **P2** | Implement Pacejka MF 6.2 in `scripts/sim/wheel.gd` + test | Modify + new | Moto-Braking-Dynamics coeffs |
| **P2** | Create `tests/unit/sim/abs_controller_test.gd` (hysteresis, cycles) | New file | Bosch ABS; Moto-Braking |
| **P2** | Create `tests/integration/dyno/dyno_regression_test.gd` (all 5 bikes ±5%) | New file | `assets/dyno/*.json`; GT-Power targets |
| **P3** | Create `tests/unit/engine/friction_test.gd` (Chen-Flynn at 3 loads) | New file | Chen & Flynn 1965; Reitz 2018 |
| **P3** | Create `tests/unit/intake/turbo_map_test.gd` (Garrett GTX3076R) | New file | vICE GT4088; `assets/compressor_maps/` |

---

## Validation Infrastructure Needed

- **CI gate** for physics validation tests (run on every PR)
- **Mutation testing** (like amt911's cargo mutants) for GDScript — investigate `gut` mutation support
- **Coverage gate** excluding long dyno sweeps (like amt911's 10-min coverage vs 3-4h full)
- **Golden trace acceptance** — automated `git diff tests/fixtures/sim_golden_trace.json` review
- **External value tags** in test names/comments: `[hand]`, `[table]`, `[closed]`, `[fig]`, `[meas]`, `[ind]`

---

## References for Unverified Items

| Item | Primary Source | Access |
|------|----------------|--------|
| Woschni original | SAE 670931 | Paywalled |
| Chen-Flynn original | SAE 650733 | Paywalled (abstract only) |
| Heywood Ch.9,12,13 | McGraw-Hill 1988 | Library only (front matter in repo) |
| SAE 820154 / 962527 | Valve flow coefficients | Paywalled |
| SAE J1349 / DIN 70020 | Correction standards | Paywalled / not found |
| SAE 2002-01-0492 | SI combustion validation | Paywalled |
| GT-Power 2018-01-0161 | Turbo GDI correlation | EPA snapshot (open) |
| GT-Power 2017-01-1794 | Acoustic correlation | SAE Mobilus (paywalled) |
| Pacejka MF 6.2 | *Tire and Vehicle Dynamics* | Book (€200) / Moto-Braking extraction |
| Levine & Schwinger 1948 | Open-end correction | Phys. Rev. 73 (open via archives) |
| Silva et al. 2009 | Exhaust reflection fit | J. Sound Vib. 322 (paywalled) |