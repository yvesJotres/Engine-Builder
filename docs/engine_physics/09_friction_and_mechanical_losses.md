# 9. Friction and mechanical losses

[Index](README.md) · Physics reference

## 9.1 Empirical FMEP models

**Chen–Flynn family** [form varies by source; coefficients S, not confirmed]. Sources do not agree on one form:

- Linear-plus-quadratic in mean piston speed: FMEP = a + b · P_max + c · S_p + d · S_p² [S, several sources].
- Quadratic only: FMEP = a + b · P_cyl + c · v² [S, patent citing the Basshuysen and Schäfer handbook].

Coefficient sets reported in the sources I found (none confirmed against the 1965 paper or Heywood):

| Source | a (bar) | b | c | d |
|---|---|---|---|---|
| Basshuysen and Schäfer, quoted in a patent | 0.3–0.5 | 0.004–0.006 | 0.0006–0.0012 (on v²) | — |
| Reitz (2018), Princeton summer-school lecture, read in full; cites SAE 650733 | 0.25 | 0.005 | 0.1 | 0 |
| X-engineer.org article | 0.3 | 0.006 | 0.05 | not shown |
| Calculator site | 0.4 | 0.005 | 0.09 | 0.0009 |
| Modified form, methanol-engine paper | 0.4 | 0.0035 | 0.055 | 0.0010 |

The speed term is mean piston speed in some sources and S_f = ω·S/2 in others [S].

**Form and values from the Reitz (2018) lecture, read in full [S]:** FMEP = C + PF·P_max + MPSF·Speed_mp + MPSSF·Speed_mp², with C = 0.25 bar (constant part), PF = 0.005 (peak-cylinder-pressure factor), MPSF = 0.1 (mean-piston-speed factor), MPSSF = 0 (squared-speed factor). The slides attribute the form to Chen–Flynn (SAE 650733). **Units of the speed terms are not stated on the slides.** With mean piston speed in m/s, MPSF = 0.1 would add about 1.5 bar at 15 m/s, which looks high, so the units must be checked before use.

**Standard coefficient set quoted in a 2025 friction paper** [S, Tadros et al., Algorithms 18(7), 415]: the paper uses the Chen–Flynn form in the form FMEP = A_cf + (1/n_cyl) Σ (B_cf · P_max + C_cf · S + Q_cf · S²), with standard values A_cf = 0.5, B_cf = 0.006, C_cf = 600, Q_cf = 0.2. It says the standard values follow Chen and Flynn's original model. The units are not stated, and C_cf = 600 and Q_cf = 0.2 cannot both be in bar with S in m/s. The units must be checked against the original paper before use.

- The original 1965 paper (Chen and Flynn, SAE 650733) is titled "Development of a Single Cylinder Compression Ignition Research Engine". Its SAE record page shows only an abstract about engine design, with no friction equation. Full text is paywalled, so its constants are not confirmed here [S].
- Chen–Flynn reported about 13 % mean error and about 35 % maximum error against experimental data in one SAE study [S].

**Patton–Nitschke–Heywood model** [P for the citation, SAE 890836, confirmed by DOI; the list of terms is S, from a thesis summary]: a scaling-law friction model with terms for oil viscosity, ring tension, gas-pressure loading and liner roughness.

**Pipitone (2009):** a newer FMEP model that reports better accuracy than Chen–Flynn in its tests [S, SAE 2009-01-1984].

## 9.2 Sources of friction

- Piston rings and skirt against the bore: largest share; rises with piston speed and gas load [T].
- Crankshaft and rod bearings: rise with speed [T].
- Valve train: cam and follower friction [T].
- Pumping work (intake and exhaust strokes) is separate from FMEP and is included in IMEP [D, definition].

## 9.3 Typical values

- Friction is about 10 % of indicated power at full load and lower speeds, rising toward 50 % at light load (Heywood Fig. 13.2, as quoted in a secondary excerpt) [S]. The bar values were not confirmed.
- Inferred: at full load FMEP is about 10–25 % of IMEP [S, inference from the efficiency figures, not a sourced number].
- Mechanical efficiency falls as speed rises at full load [S, university lecture]. Naturally aspirated spark-ignition BMEP at maximum torque (about 2800 rpm) is quoted at 850–1050 kPa [S, lecture].

---
