# 7. Combustion

[Index](README.md) · Physics reference

## 7.1 Burn shape: Wiebe function [T; the form and a = 6.908 confirmed in a secondary source; the double-Wiebe extension is in 7.1b]

Mass-burned fraction against crank angle θ, starting at θ₀ with burn duration Δθ:

x_b = 1 − exp[ −a · ((θ − θ₀) / Δθ)^(m + 1) ]

- a = 6.908 gives 99.9 % burned at the end of Δθ [D: −ln(0.001) = 6.908; the sign convention in the formula above is confirmed in a secondary source, S].
- m: the value of about 2 often quoted for spark-ignition engines was not confirmed. A secondary source says m is fitted per engine and operating point [S].

## 7.1b Double-Wiebe burn for HCCI (Qasemian and Rezaei 2020, read in full) [S]

Two burn fractions are added together. Most of the charge burns at the normal rate, and a fraction w_wall burns slowly, with a duration k_wall times the standard one. The paper uses it to represent slow burn near the walls, without a separate wall zone.

- **Slow-burn fraction** w_wall: the paper gives 0.155 for HCCI engines, from a previous study.
- **Slow-to-standard duration ratio** k_wall: 10 for HCCI engines, from the same study.
- **Shape exponent** m: the paper says large m makes combustion very slow to start. It is adjusted per engine.
- **Start of combustion** θ0: treated as an adjustable value, a little later than spark timing. The paper relates θ0 to the 50 % burn angle and the 10–90 % duration through an empirical formula.
- The paper's optimized fit did not change the double-Wiebe constants much (the paper's conclusion). Its main correction was to the heat-transfer constants.

These HCCI values are not from an SI engine. Do not use them for spark-ignition combustion without a source for that engine.

## 7.2 Burn timing

- **Flame development (spark to 10 % burned):** about 18–29° of crank rotation over 750–3,000 rpm in one reported measurement [S, citing Heywood Fig. 9-17].
- **Rapid burn (10 % to 90 %):** about 35–50° at medium speed and part load [S]; longer at full load and high speed [T].
- **Burn duration in crank degrees** increases slowly with speed, because turbulence raises flame speed while time per degree shrinks [S].
- **Best torque timing:** CA50 (crank angle at 50 % burned) near 7–8° after TDC is reported as the optimum in two SAE papers (SAE 852090 and SAE 2012-01-0902) [S]. An engine-calculator page gives 8–12° after TDC [S].
- **Spark advance for best torque (MBT):** an engine-calculator page gives 28–42° before TDC as typical, indicative only [S]. At MBT, the crank angle of peak cylinder pressure is 12–14° after TDC in one SAE paper [S].

## 7.3 Laminar flame speed [P, read from Metghalchi and Keck (1982), Combustion and Flame 48, 191, full text]

**Power-law form** (their Eq. 24, simple power law):

S_u = S_u0 · (T_u / T0)^α · (p / p0)^β · (1 − 2.1 f)

- T0 = 298 K, p0 = 1 atm.
- S_u in cm/s, p in atm, T_u in K.
- f = mass fraction of diluent (simulated combustion products, 85 % N₂ and 15 % CO₂ in their tests). It is not the same as the residual-gas fraction of an engine cycle.
- The paper says the fit holds within about ±10 % over p = 0.4–50 atm, T_u = 298–700 K, and equivalence ratio 0.8–1.5.

**Exponents, as functions of equivalence ratio φ** [P]:
- α = 2.18 − 0.8 · (φ − 1)
- β = −0.16 + 0.22 · (φ − 1)

**Reference flame speed S_u0** [P]:
- S_u0 = B_m + B_2 · (φ − φ_m)², with φ_m the equivalence ratio of the peak.
- Isooctane (their Table 3A, 298 K): φ_m = 1.13, B_m = 26.32 cm/s, B_2 = −84.72 cm/s. These were read from the extracted text; check the digits against the printed table before use in code.
- Methanol (same table): φ_m = 1.11, B_m = 36.92 cm/s, B_2 = −140.51 cm/s.

**Comparison with the ATG engine-sim code** [read from the ATG source file `fuel.cpp`; the code gives no citation]:
- ATG uses S_L0 = 0.305 m/s − 0.549 m/s · (φ − 1.21)², α = 2.4 − 0.271 φ^3.51, β = −0.357 + 0.14 φ^2.77.
- These are not the Metghalchi–Keck isooctane fit. ATG's peak is at φ = 1.21 with about 0.305 m/s. At φ = 1.13, ATG gives about 0.30 m/s against 0.263 m/s from the 1982 fit, and the exponents differ at every φ (at φ = 1.13: ATG α ≈ 1.98 vs 2.08 for the 1982 fit; ATG β ≈ −0.16 vs −0.13). The ATG code does not cite a source for its constants. Its fuel is labelled "gasoline", and the paper's fit is for isooctane (with methanol and indolene data as well).

**Source:** M. Metghalchi and J. C. Keck (1982), Combustion and Flame 48, 191–210. Local copy from the James Keck memorial collection (https://james-keck-memorial-collection.unibs.it/JCKeck-papers/MetghalchiKeck-CombustionFlame-48-191-1982.pdf).

## 7.4 Turbulent flame speed

Turbulent flame speed rises with turbulence intensity relative to laminar speed. Burn models that use this relation (for example the ATG flame model) tie burn duration to engine speed through the mean piston speed [S, ATG combustion code].

## 7.5 Combustion efficiency and heat release

- Fuel energy released: Q = ṁ_f · LHV · η_c [D, definition], with η_c typically 0.95–0.99 at good mixtures [T].
- Heat transfer to the coolant and surroundings is about one-third of fuel energy in one heat-transfer paper, with the exhaust taking about 30 % [S]. Coolant share alone is reported between about 20 % and 35 % across sources, not confirmed for one engine [S]. A recalled 25–35 % figure is not confirmed [T].

---
