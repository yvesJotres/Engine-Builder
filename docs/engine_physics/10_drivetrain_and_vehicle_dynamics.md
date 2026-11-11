# 10. Drivetrain and vehicle dynamics

[Index](README.md) · Physics reference

## 10.1 Gearing

- Engine speed to road speed: v = ω_wheel · r_roll, and ω_wheel = ω_engine / (i_gear · i_final).
- Road speed in km/h for N in rpm and r_roll in m: **v (km/h) = 0.37699 · N · r_roll / (i_gear · i_final)** [D, from the unit conversion].

## 10.2 Drivetrain efficiency

- Chain drive per stage: about 0.97–0.99 [S, forum and manufacturer comparison pages].
- Gearbox per stage: about 0.95–0.98 [T, not confirmed].
- Crank to rear wheel: commonly 0.85–0.92 for a chain-driven motorcycle [S; Wikipedia gives a 5–20 % loss range].

## 10.3 Resistance forces

- Aerodynamic drag: F_d = ½ · ρ · C_d · A_f · v² [D, definition].
- Rolling resistance: F_r = C_rr · m · g [D, definition]. A 2021 peer-reviewed study measured five motorcycle tyres under ISO 18164 at C_rr = 0.0089 to 0.0137 [S, Energy Reports]. A forum estimate gives about 0.020 as an upper bound [S].
- Air density ρ: 1.18–1.225 kg/m³ at sea level, depending on temperature [T; see section 2].
- Top speed balances engine power against resistance: η_dt · P_engine = (½ · ρ · C_d · A_f · v² + C_rr · m · g) · v [D, derived].

## 10.4 Tyre radius

- Loaded radius is less than the free radius. Measure under rider load for the rolling calculation [T].

---
