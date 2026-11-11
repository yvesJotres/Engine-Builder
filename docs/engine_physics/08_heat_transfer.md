# 8. Heat transfer

[Index](README.md) · Physics reference

## 8.1 Newton's law

Q̇ = h · A · (T_gas − T_wall) [D, definition of h]

## 8.2 Woschni (1967) [P for citation; form, exponents and constants S, from a paper read in full]

Original: G. Woschni, "A universally applicable equation for the instantaneous heat transfer coefficient in the internal combustion engine", SAE 670931 [P, citation confirmed].

**Heat transfer coefficient (SI units):**

h = 3.26 · B^(−0.2) · p^0.8 · T^(−0.55) · w^0.8 [S. B in m, p in kPa, T in K, w in m/s, h in W/(m²·K). Qasemian and Rezaei (2020) list the original prefactor as X5 = 0.013 with the pressure in Pa, and 3.26 × (1000)^(−0.8) = 0.0130, so the two agree once the units are converted. The original SAE 670931 text was not reachable.]

In the paper's Pa form, the same equation is h = 0.013 · B^(−0.2) · P^0.8 · T^(−0.55) · w^0.8 with P in Pa [S].

**Characteristic gas velocity (paper's Eq. 15) [S, Qasemian and Rezaei 2020]:**

w = C1 · S_p + C2 · (V_d · T_r) / (p_r · V_r) · (p − p_0)

- C1 = 2.28 during compression and expansion; 6.18 during gas exchange [S; Qasemian and Rezaei (2020), IOP Conf. Ser. 671, 012019, a peer-reviewed secondary paper, gives the same values; they are for the Woschni correlation as applied to HCCI engines, which the paper says needed corrections].
- C2 = 0.00324 m/(s·K) during combustion and expansion; zero otherwise [S; Qasemian and Rezaei (2020) list the original constant as 3.24 × 10⁻³ and C2 = 0 in gas exchange and compression. The original paper was not reachable].
- p_0 = motored pressure at the same crank angle; p_r, T_r, V_r = pressure, temperature and volume at a reference point (usually intake valve closing) [S, paper's Eq. 15, where P_m is the motored pressure].

**Chang et al. (2004) HCCI variant (paper's Eq. 16):** the bore is replaced by the instantaneous chamber height L as the length scale, and the temperature exponent is changed to about −0.73. Reported by the paper, which cites Chang et al. (SAE 2004-01-2996). [S]

**HCCI constants fitted by the paper (its Table 2 and Eq. 19). Not for spark-ignition engines.** The paper's genetic algorithm fitted all of these to one HCCI single-cylinder engine (a Ricardo Hydra, bore and stroke 86 mm, compression ratio 14.04). [S]

| Term | Original | Optimized (HCCI fit) | Change |
|---|---|---|---|
| Pressure exponent | 0.8 | 0.69 | −13 % |
| Gas-velocity exponent | 0.8 | 0.54 | −32 % |
| Bore exponent | −0.2 | −0.13 | −35 % |
| Temperature exponent | −0.55 | −0.146 | −73 % |
| Prefactor (Pa units) | 0.013 | 0.0237 | +82 % |
| C1 | 2.28 | 2.160 | −5 % |
| C2 | 3.24 × 10⁻³ | 3.047 × 10⁻³ | −6 % |

- The paper's fit reduces the average pressure error from 13 % to 5 % for that engine.
- It reports the heat-transfer coefficient at the peak more than 400 % higher than the original model's. The large change comes mainly from the exponents, so the two curves differ in shape as well as size.
- The paper's conclusion: the double-Wiebe constants needed little change, and the heat-transfer constants needed most of the correction.
- The paper says its corrected correlation is for HCCI combustion only. It should not be used as a spark-ignition constant set.

**Note:** Woschni later added a swirl term to C1. Woschni's correlation was developed for gasoline and diesel engines; a hydrogen-engine study found it under-predicts convective heat transfer, and other studies report significant error when constants are used across engines without calibration [S]. Other variants (Hohenberg, Annand, Sitkei) give different values in the same comparisons [S].

## 8.3 Annand

- Form: a Nusselt–Reynolds correlation with exponent 0.7 on Reynolds number, bore as the length scale, and a constant characteristic velocity equal to the mean piston speed [S, Colorado State notes].
- Coefficient a: 0.35 to 0.8 for normal combustion [S, Colorado State notes]. The value 0.26 is not supported by any source reached.
- Source: W. J. D. Annand, Proc. IMechE vol. 177 (36), pp. 973–996, 1963 [S, cited by OpenModelica documentation; paper not reached].
- Radiation term: form and constants not confirmed [unverified].

## 8.4 Typical wall temperatures

Not confirmed. The numbers below were recalled and no source gave them.

- Relative order (hottest first): spark plug, exhaust valve, piston crown, head; the liner runs cooler because it sees less burned gas [S, lecture notes based on Heywood].
- Liner oil-film limit: about 200 °C (473 K) [S, lecture notes]. This is a material limit, not a measured mean wall temperature.
- Peak SI heat flux: about 1–3 MW/m² [S, lecture notes].
- Recalled values (not confirmed): liner 400–450 K, head 450–500 K, piston crown 500–600 K [T].

## 8.5 Reynolds analogy

The exponent 0.8 on gas velocity comes from turbulent pipe-flow heat transfer, the Reynolds analogy between heat and momentum transfer [S, Purdue ICEC paper].

---

## 8.6 Gas thermal conductivity (Heywood Fig. 12-5)

The MIT OCW corrections list (dated 2001) says the thermal-conductivity scale in Fig. 12-5 is wrong by a factor of 5 × 10⁵: the peak value should be 5 × 10⁻² W/(m·K), not 10⁻⁷ W/(m·K) [S, MIT OCW corrections, p. 679].
