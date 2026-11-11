# 6. Valve flow and breathing

[Index](README.md) · Physics reference

## 6.1 Compressible orifice flow [T for the subsonic form; choked ratio confirmed in secondary sources]

Mass flow through a restriction of effective area A_eff = C_d · A_geo, with upstream pressure p_u, downstream p_d, upstream temperature T_u, and γ:

**Subsonic** (p_d / p_u above the critical ratio):

ṁ = C_d · A_geo · p_u / √(R T_u) · √(2γ / (γ − 1)) · [ (p_d/p_u)^(2/γ) − (p_d/p_u)^((γ+1)/γ) ]^(1/2)

**Choked** (p_d / p_u ≤ critical ratio):

Critical ratio = (2 / (γ + 1))^(γ / (γ − 1)) ≈ 0.528 for γ = 1.4 [D; the value 0.528 is also quoted by secondary sources, S].

ṁ = C_d · A_geo · p_u / √(R T_u) · √γ · (2 / (γ + 1))^((γ + 1) / (2 (γ − 1)))

For γ = 1.4 the choked coefficient is ≈ 0.685 [D]. The same choked form is quoted by a secondary source [S].

## 6.2 Valve flow area

For a poppet valve of head diameter D_v at lift L:
- **Curtain area** (flow past the seat, low lift): ideal form A_curtain = π · D_seat · L, where D_seat is the seat diameter and L the lift [S, NASA propulsion-control report as quoted by a FIRGELLI engineering page]. This ideal form ignores seat angle, stem and guide blockage and throat contours. A seat-angle factor (for example sin α, with α often 45°) appears in some texts, but I could not confirm the Heywood form that includes it [unverified].
- **Seat or throat area** (cap at high lift): A_max = π · D_v² / 4 [T, standard geometry; the seat diameter is what is used in practice].
- **Effective flow area:** A_eff = min(A_curtain, A_max) · C_d.

## 6.3 Discharge coefficient

- C_d is the ratio of actual to ideal flow [D, definition].
- C_d depends on lift-to-diameter ratio L/D_v [S, SAE 820154; SAE 962527]: it is low at small L/D and rises as the valve opens. Published figures for the low-lift region are roughly 0.3–0.4, approaching 0.4–0.45 near L/D = 0.25 [S].
- Steady-flow bench C_d can overstate the real dynamic flow at higher lift, by up to about 20% in one study [S, SAE 820154].
- Flow-bench measurements are commonly taken at 28 inH₂O (about 7 kPa, 28 × 249.09 Pa = 6.97 kPa [D]) pressure drop [T, common practice].

## 6.4 Breathing limit (Taylor)

**Inlet Mach index (Taylor):** Z = (A_p / A_i) · (S_p / (C_i · a)), where A_p = piston area, A_i = total inlet valve area, C_i = mean valve flow coefficient, a = speed of sound [S; secondary sources cite Taylor's text].

Breathing falls sharply once Z exceeds about 0.5–0.6 [S].

## 6.5 Gas-dynamic tuning

**Helmholtz frequency of an intake system** (neck area A_n, cavity volume V, effective length L_e):

f_H = (a / 2π) · √(A_n / (V · L_e)) [T, standard acoustics; not read in a source]

**Quarter-wave pipe:** f = a / (4 L_e) [T, standard acoustics].

**Tuning rule (secondary):** filling is best when the intake natural frequency is near a multiple of the intake-event frequency. One source gives the Helmholtz frequency near twice the piston frequency as a rule of thumb for four-stroke engines [S, thesis on volumetric-efficiency modelling].

**Runner length (secondary):** shorter runners favour high speed; longer runners help low and mid speed [S].

---
