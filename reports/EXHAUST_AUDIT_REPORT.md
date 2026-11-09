# Exhaust audit and status

Two read-only audits (physics and geometry; 3D attachment) and the fixes made from them.

## Fixed

| Area | Problem | Fix | Where |
|---|---|---|---|
| Two-stroke chamber | One chamber shared by all cylinders, fed by all of them at once | Each cylinder has its own four-section chain, built as layout pipes and run on the same solver | `scripts/engine/expansion_chamber.gd`, `scripts/exhaust/exhaust_layout.gd` |
| Two-stroke chamber | Energy terms in watts added to joules; no outlet; chamber advanced once per cylinder | Removed: the chamber is now part of the pipe solver, which conserves mass and energy | `scripts/engine/engine_sim.gd` |
| Two-stroke drawing | Cones drawn in the engine model, separate from the solver's pipes | The chamber is drawn from the same layout the solver runs | `scripts/drawing/engine_model.gd` |
| Solver damping | Attenuation used the gas speed (|u|) instead of the distance the wave travels | Uses the sound speed: loss per metre times c times dt | `scripts/exhaust/exhaust_gas.gd` |
| Solver output | Audio samples held each step's end value (a zero-order hold) | Samples are linearly interpolated across each step | `scripts/exhaust/exhaust_gas.gd` |
| Solver backflow | When gas flowed back from a pipe into a cylinder, the cylinder's enthalpy was removed from the pipe | Backflow removes the pipe cell's own enthalpy | `scripts/exhaust/exhaust_gas.gd` |
| Sound | Two-stroke sound came from nowhere | Two-stroke sound comes from the pipes; four-stroke sound unchanged | `scripts/main.gd`, `scripts/engine/engine_sim.gd` |
| Two-stroke engine | The cylinder list rejected the two-stroke cylinders (the engine never ran) | The list accepts both cylinder types | `scripts/engine/engine_sim.gd` |

## Verified by test

- `tests/unit/exhaust/exhaust_chamber_test.gd`: four chained sections per cylinder, total length equal to the spec, open stingers, solver stays finite.
- `tests/unit/engine/two_stroke_sim_test.gd`: both cylinders exist; the RD350 fires and climbs.
- `tests/unit/engine/two_stroke_model_test.gd`: the engine model does not draw the chamber; the crank still moves the pistons.

## Open

1. **Four-stroke live pipe solver is off.** Turned on, the solver drops the pipe to about 45 kPa at idle (the Sportster's idle then hunts around 1300 rpm and `idle_hold_test` fails). The two-stroke solver holds about 101 kPa. The cause is not found yet. The live four-stroke path stays on valve blowdown until it is fixed. You chose the live solver for both strokes; this is a deviation to review.
2. **Phone cost.** The live solver roughly doubles the sim's CPU cost on the ZX-25R on PC. Not measured on the phone.
3. **Pipe minimum cell.** Cells are at least 0.24 m (`CELL_M`), so the short catalyst, mid pipe and tailpipe are simulated longer than they are drawn. Lowering it multiplies cost by the step-size ratio.
4. **W engine attachment.** Not fixed in this pass. The audit found: cylinder ports sit inside neighbouring heads (cylinder 1 about 0.18 units from cylinder 2's axis), the stock collector is pushed to one side by the rear-axle test at `exhaust_layout.gd:84`, and the fixed 15-degree and 7.5-degree offsets ignore the bore. These need the engine model's W geometry and the layout's collector placement changed together.
5. **Two-stroke combustion at idle.** The RD350 still stalls at a closed throttle. The charge and scavenging model is the cause, outside the exhaust.
6. **Dead spec fields.** `expansion_chamber_volume_cc` and `runner_length_m` are read by nothing in the exhaust path.
7. **Hardcoded layout values.** Pipe radii do not scale with the bore; layout offsets are fixed numbers.
8. **Leftover debug scripts** in `tests/debug/` (`_gas*.gd`, `_sp*.gd`, `_rd*.gd`, `_tsdiag`, etc.). Deleting them was blocked; they are not run by any test or the publish gate.
