# 11. Dyno standards and corrections

[Index](README.md) · Physics reference

**SAE J1349 (correction to standard conditions)** [S, formula from calculator and tuning sites; the SAE document was not reached]:

CF = 1.18 · (990 / p_d) · √((T + 273) / 298) − 0.18

The 1.18 and −0.18 terms are as quoted by several calculator and tuning sites [S]. The naturally aspirated form is for naturally aspirated engines only; forced-induction engines need a different factor. The SAE document itself was not reached, and the search results disagree on which revision (JUN90, AUG2004, later) keeps these constants.

p_d = dry air pressure in mbar, T = air temperature in °C. Power and torque are multiplied by CF.

**DIN 70020** [T, unverified]:

CF = (1013 / p) · √((273 + T) / 293)

The reference conditions (1013 mbar, 20 °C) match what German flow-meter and vendor sources describe [S]. The correction formula itself was not found in any source I could reach.

**Crank and wheel figures:** state which one a reference uses. The wheel figure is the crank figure multiplied by the drivetrain efficiency [D, definition].

**Flow-bench conditions:** state the pressure drop (commonly 28 inH₂O) and the correction method. CFM values are not comparable between heads without them [T, common practice].

---
