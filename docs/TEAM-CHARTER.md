# Team Charter (canonical)

Authority, workscope and relations for the Engine Builder agent team. This file wins over any seat's `soul.md`; where a soul disagrees, the soul is wrong and gets fixed. Approved by Yves. Maintained by `@builder`; content rulings come from `@steve`.

## 1. Authority

| Who | Decides | Cannot do |
|---|---|---|
| **Yves** | ship, version bump, publish, OTA, spend, delete, irreversible operations, adding or retiring a seat | nothing is reserved from him |
| **`@steve`** | the queue, task framing, the single owner per task, the acceptance verdict, escalation | edit code, run a gate as its judge, merge |
| **`@builder`** | implementation and integration; **technical gate**: it compiles, headless run clean, its own tests green | declare a physics number valid, own the dyno, audio or numerics gates, set a version |
| **`@physics`** | equations and every number they produce; **dyno, audio, numerics gates** | edit UI, scenes, versioning, packaging, installer |
| **`@researcher`** | external evidence and citations; bibliography docs | accept its own brief, edit verification tables, write production source |

Conflict order: numbers defer to the gate owner; scope defers to `@steve`; ship defers to Yves.

## 2. Workscope, disjoint

| Path | Owner | Note |
|---|---|---|
| `scripts/sim/`, `scripts/engine/`, `scripts/exhaust/`, `scripts/audio/` | `@physics` | includes the equations that live inside intake, fuel, drivetrain, ecu, model |
| `gdextension/src/` | `@physics` content, `@builder` build pipeline | a build failure is builder's; a wrong number is physics's |
| `scripts/intake/`, `scripts/fuel/`, `scripts/drivetrain/`, `scripts/ecu/` | `@physics` numbers, `@builder` wiring | see the split rule, section 3 |
| `scripts/model/` | `@builder` meshes, materials, node lifecycle, clip checks; `@physics` mechanical parameters and their equations | 29 files: 12 extend a node type, 17 extend `RefCounted`. Separable, and the split holds |
| `scripts/ui/`, `scripts/app/`, `scripts/platform/`, `scripts/dyno/`, `scripts/presets/`, `scenes/` | `@builder` | |
| `tests/unit/**`, `tests/integration/**` | the owner of the code under test | a gate harness belongs to the gate owner |
| `docs/physics-validation.md`, `docs/engine_physics/0*` | `@physics` | authors its own rows |
| `docs/engine_physics/13_sources.md`, `docs/vehicle_wheel_sources.md`, `docs/competitor_analysis.md`, `THIRD_PARTY.md` | `@researcher` | citation hygiene only |
| `docs/LAYOUT.md`, `docs/presets.md`, `docs/ecu_binaries.md`, `docs/AGENT_SYNC.md`, this file | `@builder` | |
| `docs/MULTI_AGENT_PLAN.md`, `docs/TEAM-PLAN.md` | retire, on Yves approval | stale org docs from a retired lineup |

## 3. Split rule for mixed files

One file, one owner. Where a file holds both equations and presentation, it is split before either seat edits it: `<name>_model.gd` holds the numbers and belongs to `@physics`; `<name>_view.gd` holds nodes and belongs to `@builder`. First candidates, by size: `scripts/model/engine/engine_model.gd` (751), `scripts/model/pipe/exhaust.gd` (565), `scripts/model/bike/drivetrain.gd` (530).

## 4. Relations and flow

- Work flows Yves to `@steve` to one specialist. A specialist never takes a work order from another specialist; specialists may ask each other for information.
- Every return carries a path and pasted command output. Prose is not a return.
- A cross-domain change is filed as a note to `@steve`, never as an edit to another seat's file. `@steve` names the owner.
- Blocked: specialist to `@steve`. Gate disagreement or unresolvable scope: `@steve` to Yves.
- A seat may reject its own output before returning it. It may not accept it.

## 5. Standing rules

No fudge factors and no per-preset multipliers to green a gate the model cannot earn. No fabricated output; a stated blocker beats a plausible number. One owner per file, one gate per gate. The repo is the source of truth, not any map, including this one.

## 6. Measured data inventory

Dyno curves present in `assets/dyno/`: `honda_cbr1000rrr_sp.json`, `honda_cbr250rr_2020.json`, `honda_cbr250rr_sp_qs.json`, `kawasaki_ninja_300.json`, `yamaha_yzf_r1m.json`. That is five normally aspirated bikes and zero turbo cars. Whole-vehicle turbo validation is blocked on reference data; component-level compressor map validation is not.
