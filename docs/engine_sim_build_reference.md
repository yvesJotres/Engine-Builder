# Engine sim: build reference

What an engine simulator needs in order to be built, checked and tuned. This is general: it applies to any four-stroke engine in the project, not to one bike. Each input is described by what it is, the physics behind it, the form the sim uses, and where to source it.

Status key used in the tables: **Measured** (taken from the engine), **Published** (from a manufacturer or standard), **Estimate** (a working value that still needs a source), **Missing** (the model has no term for it yet).

---

## 1. How the sim is structured

- **Cylinder model:** `scripts/engine/cylinder.gd` (GDScript) and `gdextension/src/cylinder_kernel.cpp` (native C++). Both must give the same answers. The parity test is `tests/unit/engine/cylinder_native_test.gd`.
- **Engine loop:** `scripts/sim/engine_sim.gd`. Crank dynamics, friction, fuel and ECU are here.
- **Engine settings:** `scripts/sim/engine_spec.gd` holds the fields and their defaults. Each engine is a preset file in `assets/engines/`.
- **Dyno tools:** `tools/diagnostics/dyno_attempt.gd` runs one attempt with `key=value` overrides; `attempt_graphs.py` draws the graphs; `match_reference.py` compares each reference point.
- **Native rebuild:** `gdextension/build_win.bat template_debug` and `template_release`. Close Godot first, or the DLL stays locked.
- **Headless run:** the Godot console binary with `--headless --path . -s <script>`.

---

## 2. Geometry

| Input | What it is | Status | How to source |
|---|---|---|---|
| Bore | Cylinder diameter | Published | Factbook or workshop manual; measure if possible |
| Stroke | Piston travel | Published | Same |
| Displacement | Bore area × stroke × cylinders | Derived | Check it against the published figure |
| Compression ratio | (swept + clearance) / clearance | Published; check | Measure chamber volume; the published figure can differ by model year |
| Connecting-rod length | Centre to centre | Measured or published | Parts documentation or a measurement |
| Rod ratio | Rod length / crank radius | Derived | |
| Pin offset | Offset of the piston pin | Estimate | Usually zero if unknown |
| Firing interval | Crank angle between firings | Published | Engine type (twin, four, etc.) |

Geometry should be sourced once and then left alone. Changing it to match a dyno hides the real error.

---

## 3. Valvetrain and cam

| Input | What it is | Status | How to source |
|---|---|---|---|
| Valve diameter | Head size, per valve | Published | Factbook or measurement |
| Valve count | Valves per cylinder | Published | |
| Max valve lift | Peak lift, per valve | Published or measured | Lift check on the cam, or from the timing spec |
| Lift profile | Lift against cam angle | Measured | Dial gauge at 5° steps on the cam; this is the most useful single input |
| Opening and closing angles | Crank angle when the valve leaves and returns to the seat | Published at a set lift, usually 1 mm | Degree wheel on the installed engine |
| Duration | Angle the valve is open | Derived from the profile | Quote the lift it was measured at |
| Valve clearance | Gap between cam and follower | Published | Needed to convert cam lift to valve lift |
| Discharge coefficient | Real flow area / geometric flow area | Estimate in the sim | See section 5 |

---

## 4. Intake system

| Input | What it is | Status | How to source |
|---|---|---|---|
| Throttle-body bore | Smallest bore in the air path | Measured | Calipers |
| Intake runner length | Throttle to valve | Measured | Tape along the centreline |
| Intake runner area | Cross-section of the runner | Measured | Measure the bore |
| Port volume | Gas volume between throttle and valve | Estimate | Fill the port with fluid and read the volume |
| Port area | Minimum area in the port | Measured | Flow bench or measurement |
| Air filter and airbox restriction | Pressure loss before the throttle | Measured | Manometer across the filter at full throttle |
| Intake temperature | Temperature of the charge | Measured | Sensor at the intake |
| Loss coefficient | Dynamic pressure loss in the runner | Estimate | Needs a source |

The intake must be sourced as a system. A bigger valve on a short, small-bore runner gives a different breathing curve from the same valve on a long, narrow runner.

---

## 5. Valve flow

**Physics:** flow through a valve is the orifice equation for compressible gas, with the discharge coefficient (Cd) applied to the geometric flow area. Heywood gives the standard form.

**Flow area for a poppet valve:** the curtain area π · D · L (valve diameter D, lift L) applies at low lift. The seat area πD²/4 caps it at high lift.

**Discharge coefficient:** Cd rises with lift-to-diameter ratio (L/D). Source data reports values of roughly 0.3–0.4 at low L/D, rising toward 0.4–0.45 near L/D 0.25. Each engine's flow bench data should replace the generic curve.

**Sources:** Heywood, *Internal Combustion Engine Fundamentals*, valve flow chapter; SAE 962527 (discharge coefficients in engine simulation); SAE 820154 (static and dynamic poppet valve flow).

**Common mistake:** a single constant Cd across all lifts. Real valves flow differently at low lift and high lift.

---

## 6. Exhaust system

| Input | What it is | Status | How to source |
|---|---|---|---|
| Primary pipe length and diameter | Port to collector | Measured | Tape and calipers |
| Collector | Joining of the primaries | Measured | |
| Silencer volume and baffles | Back-pressure source | Measured or published | Teardown or manufacturer |
| Back pressure | Pressure at the exhaust port at full throttle | Measured | Pressure transducer upstream of the silencer |

Exhaust tuning changes mid-range torque through pressure waves. Two exhaust systems on one engine can give different curves, so record which system was fitted.

---

## 7. Combustion

| Input | What it is | Status | How to source |
|---|---|---|---|
| Burn duration | Crank angle from spark to end of burn | Estimate or measured | Heat release from a cylinder pressure trace |
| Burn shape | Mass-burned fraction against crank angle | Standard form (Wiebe) | Fit to a measured burn |
| Burn-duration dependence on rpm | Turbulence raises flame speed | Physics | Flame-speed model; see below |
| Laminar flame speed | Burn speed of the mixture at zero turbulence | Correlation | Metghalchi–Keck (1982) isooctane fit, read in full; ATG uses different constants (see `engine_physics/07_combustion.md`, 7.3) |
| Combustion efficiency | Share of fuel energy released | Estimate | Heat release analysis |
| Spark advance | Crank angle of spark against rpm and load | Measured | Ignition trace or ECU data |
| CA50 | Crank angle at which 50% of the charge is burned | Derived | Typically 8–12° after TDC at best torque |
| Air-fuel ratio | Mixture strength | Measured | Wideband lambda, downstream of the cylinders |

**Turbulence and burn duration:** in crank degrees, burn duration grows only slowly with speed, because turbulence speeds up the flame as the time per degree shrinks. Burn duration should follow turbulence, not a fixed rpm slope.

**Sources:** Heywood (chapter on combustion); MIT 2.61 lecture notes on SI combustion; the ATG flame-speed code (`fuel.cpp`, `combustion_chamber.cpp`).

---

## 8. Heat transfer

**Physics:** heat loss to the walls depends on gas velocity, temperature and pressure. The standard empirical form is the Woschni correlation.

**Woschni (1967, SAE 670931):** h = 3.26 · B^−0.2 · p^0.8 · T^−0.55 · w^0.8 (B in m, p in kPa, T in K, h in W/m²K). The exponents and C1/C2 are confirmed in a secondary paper (Qasemian and Rezaei 2020); the 3.26 coefficient is not confirmed (see `engine_physics/08_heat_transfer.md`).

**Gas velocity:** w = C1 · Sp + C2 · (Vd · Tr) / (pr · Vr) · (p − p0), where Sp is mean piston speed and p0 is the motored pressure.
- C1 = 2.28 for compression and expansion; 6.18 for gas exchange.
- C2 = 0.00324 m/(s·K) during combustion and expansion (confirmed in the same secondary paper; see `engine_physics/08_heat_transfer.md`).
- The exponents and C1/C2 are confirmed in a secondary paper, and the 3.26 prefactor matches its 0.013 in Pa units. The original SAE 670931 text is still unread (see `engine_physics/08_heat_transfer.md`).

**Wall temperatures:** typical liquid-cooled values are about 400–450 K for the liner and higher for the head and piston. Use measured values where possible.

**Sources:** Woschni, SAE 670931; Heywood; Annand (1963) as the comparison; SAE 2014 heat-transfer comparison (`https://saemobilus.sae.org/papers/heat-transfer-evaluation-internal-combustion-engine-operating-wet-ethanol-fuel-part-b-2014-36-0357`).

**Note:** ATG's engine-sim does not model wall heat transfer at all, so it cannot check this term.

---

## 9. Friction and mechanical losses

| Input | What it is | Status | How to source |
|---|---|---|---|
| Friction mean effective pressure (FMEP) | Friction loss per unit displacement | Empirical | Motoring test or coast-down |
| Chen–Flynn form | FMEP = a + b·Pmax + c·Sp² | Form varies by source; coefficients conflict and are unconfirmed (see `engine_physics/09_friction_and_mechanical_losses.md`) | Chen & Flynn (1965, SAE 650733, paywalled); Heywood |
| Patton–Heywood model | Friction from scaling laws (oil viscosity, ring tension, gas load, bore roughness) | Empirical | SAE 890836 |
| Crank and bearing friction | Constant and speed-dependent parts | Estimate | Motoring test |
| Oil temperature effect | Viscosity changes with temperature | Estimate | Oil temperature measurement |

**Important:** friction rises with piston speed and cylinder pressure. A model that is linear in rpm alone misses the pressure term, which matters most under load at low rpm.

**Sources:** SAE 890836 (Patton, Nitschke, Heywood); Pipitone (SAE 2009-01-1984) on the limits of Chen–Flynn; ATG `combustion_chamber.cpp` (Coulomb friction that grows with side force).

---

## 10. Drivetrain and vehicle

| Input | What it is | Status | How to source |
|---|---|---|---|
| Primary ratio | Crank to clutch | Published | Parts or factbook |
| Gear ratios | Each gear | Published | Parts or factbook; check the model year |
| Final drive | Sprocket or belt ratio | Published | Sprocket counts |
| Drivetrain efficiency | Crank to wheel | Estimate | Measure with paired crank and wheel tests, or a coast-down |
| Tyre size and rolling radius | Wheel radius under load | Measured | Tyre under rider load |
| Mass | Curb and rider | Published, then measured | Weigh the machine |
| Drag area | Aerodynamic drag | Estimate | Coast-down or wind-tunnel data |

**Drivetrain loss:** published estimates for a chain-driven motorcycle run from about 5% to 20%. Treat any single figure as an assumption until it is measured.

**Top speed in each gear:** speed = (rpm × tyre circumference) / (60 × gear ratio × final drive). Check it against GPS-logged speed, not the speedometer.

---

## 11. Fuel, ignition and ECU

| Input | What it is | Status | How to source |
|---|---|---|---|
| Fuel type and octane | Energy and burn properties | Published | Fuel spec |
| Lower heating value | Energy per kg of fuel | Published | Standard tables |
| Air-fuel ratio, stoichiometric | 14.7 for gasoline | Published | Standard |
| Fuel map at wide-open throttle | Mixture against rpm | Measured | Wideband log on a dyno or the road |
| Ignition map | Advance against rpm and load | Measured | Ignition trace or ECU read |
| ECU binary | Stored maps | Read-only | Use the parser; do not modify without a reason |
| Rev limiter | Maximum rpm | Published or measured | |

Wideband logs must note intake air temperature, barometric pressure and coolant temperature. Without them, the fuel and power figures cannot be compared.

---

## 12. Dyno method and comparison

- **Crank versus wheel:** record which figure each reference uses. Convert with a measured drivetrain loss, not an assumed one.
- **Correction standard:** note whether the reference used SAE or DIN correction, the ambient temperature and the altitude.
- **Reference torque and power:** torque and power are linked by torque × rpm / 7121 (hp) or torque × rpm / 9549 (kW). If a chart's two lines disagree, check the axis labels before trusting either line.
- **Error metric:** compare at every reference point, not just at the peaks. Report power and torque separately for each rpm.
- **Attempts:** each attempt needs a graph, its settings and its peaks.

---

## 13. Data to collect for any engine

1. Lift profile for each valve, every 5° of cam angle (dial gauge).
2. Installed valve timing at 1 mm lift (degree wheel).
3. Bore, stroke, rod length, compression ratio (measured).
4. Throttle bore, runner length and area, port area, airbox volume, filter restriction.
5. Exhaust primary, collector and silencer geometry, back pressure.
6. Wideband air-fuel ratio, ignition advance and intake temperature, at wide-open throttle, against rpm.
7. Motoring friction (coast-down with clutch disengaged, or a motoring test).
8. Drivetrain efficiency (paired crank and wheel measurement, or a coast-down).
9. Top speed in each gear (GPS-logged).

---

## 14. Known gaps in the sim (general)

Closed:

- **Cd curve against lift-to-diameter** — closed. `Cylinder.discharge_cd()` (`cylinder.gd`, `cylinder_kernel.cpp`) runs 0.30 at zero lift up to 0.42 at L/D 0.25, inside the published 0.3–0.45 band (`engine_physics/06`). The sim also scales it by each preset's `valve_cd`. Above L/D 0.25 it is flat; SAE 820154 has Cd falling there, so a measured curve is still the upgrade.
- **Friction pressure and piston-speed term** — closed. The four-stroke path uses the Chen–Flynn form from Reitz (2018): constant 0.25 bar + 0.005 bar per bar of peak cylinder pressure + 0.1 bar per m/s of mean piston speed (`engine_sim.gd`, `REITZ_*`). The two-stroke path still uses a simpler friction model.
- **SAE J1349 correction** — closed. The dyno uses the researched form, CF = 1.18 (990/p_dry) √(T/298) − 0.18, rather than a plain pressure ratio (`engine_physics/11`).

Still open:

- **CA50 target.** The sim targets 10° ATDC, inside the researched 7–12° window (`engine_physics/07`). The SAE papers put best torque at 7–8°; retarding the target to 8° was tried and produced a pop at steady idle and a fuel-flow dropout in the audio read, so it needs a separate idle/cruise schedule with dyno evidence rather than one constant.

- **A fixed burn-duration formula should be replaced by a turbulence-driven flame model.** The sim still burns over spark + (45 + 0.002·rpm) degrees. `engine_physics/07` has the pieces (Metghalchi–Keck laminar speed, turbulence through mean piston speed) but no sourced turbulence-intensity constant, so this needs a source before it can be implemented without a fitted number. A native flame model exists in `gdextension/src/flame_model.cpp` but is an ATG port with ATG's constants, which `engine_physics/07.3` shows are not the Metghalchi–Keck fit; it is not wired into the cylinder path.
- **Intake charge temperature is not modelled** (no heating from the head or port); residual gas and intake restriction are not modelled.
- **Drivetrain efficiency is unmeasured and shared.** The sim uses one 0.93 for every vehicle. The researched chain-driven bike range is 0.85–0.92 (`engine_physics/10`), so 0.93 is one point high; lowering it to 0.92 dropped the Bugatti's measured crank torque 8.7% (838 to 765 N·m), because the constant also sets the clutch/driveline coupling. The fix is one efficiency per vehicle plus a measured crank-and-wheel figure, not a different global number.
- **Any input that has no effect should be removed** from the settings and the UI.
- **The native and GDScript paths must agree.** `research_conformance_test.gd` compares the two constant sets without a rebuild; `cylinder_native_test.gd` compares the two over a long run and needs the rebuilt library.

---

## 15. Validation

- **Reference data:** the published power and torque at the engine's peak points, plus the full curve from a dyno chart, with its source noted.
- **Other models:** ATG engine-sim (comparison only; its engine files are often estimates) and published textbook examples.
- **Physics sources:** Heywood, *Internal Combustion Engine Fundamentals*; Woschni SAE 670931; Patton et al. SAE 890836; Chen & Flynn (1965); MIT 2.61 lecture notes.

---

## 16. Rules for changes

- Do not change geometry that is already measured or published; do not edit reference data files.
- Every physics change needs a cited source and a list of the engines it affects.
- No fitted constants, multipliers or reference lookups in code. Sweeps are diagnostics only and never go into code.
- Keep the GDScript and native paths in step; rebuild the native library; run the parity test.
- Show a graph after every attempt, with its settings and peaks.
- After any shared physics change, run every engine preset and report any engine that moves more than 5%.
