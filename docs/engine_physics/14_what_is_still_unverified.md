# 14. Fact-check log and what is still unverified

[Index](README.md) · Physics reference

This log covers the claims in sections 1–13, tagged as in the index. Later passes read the Metghalchi–Keck, Qasemian, Tadros and Reitz papers, and the MIT OCW corrections, in full. Items still open are listed at the end.

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

## Corrections made so far
- **Metghalchi–Keck flame speed.** Section 7.3 now gives the full-text equations and isooctane parameters. The ATG constants do not match the 1982 fit.
- **Diluent factor f.** Described as the diluent mass fraction (simulated combustion products), not the residual gas fraction.
- **Chen–Flynn.** Added the standard set quoted in the 2025 paper, with its unit problem noted.
- **Woschni constants.** C1, C2, the exponents and the prefactor are now confirmed by a peer-reviewed paper (Qasemian and Rezaei 2020), tagged [S]. The 3.26 value matches the paper's 0.013 once units are converted.

## Still unverified (and why)
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

## Next steps that need you or a library
1. Heywood, *Internal Combustion Engine Fundamentals*, chapters 9 (flame development), 12 (heat transfer, Annand, wall temperatures) and 13 (friction, Chen–Flynn). A university library copy would close most of the [T] items.
2. SAE 670931 (Woschni) and SAE 650733 (Chen–Flynn) through a library or the SAE subscription.
3. The SAE J1349 and DIN 70020 standard texts.
4. A measured crank-and-wheel drivetrain efficiency for one motorcycle. This needs a test on a dyno or a coast-down with a known rolling resistance; I cannot do it from here.
