# Engine Builder — Bot Mode Team Plan

**Status:** draft, awaiting sign-off. **Version:** 0.1.5 · **Repo:** `D:/Projects/Engine Builder`
**Author:** @jes · Models verified by live call, not catalog lookup.
**Roster:** 4 core seats. `@davinci` and `@hermes` are **out of this project** — davinci keeps his AI-stack profile, he just isn't on this team.

---

## 1. Design rules

1. **A bot is a profile.** Same primitive, no new concept. Handle = profile dir name.
2. **One job, one owner, one path set.** If two bots can edit the same file, the boundary is wrong.
3. **Tool access is a budget, not a right.** Every enabled tool is a 10–20 minute turn the bot might waste. Default OFF, enable by need.
4. **`delegation` ≠ `a2a`.** `a2a` is `message_agent` (talk to a teammate). `delegation` is spawning sub-agents — the tool that burned 20 min looping in the source test. Only the Foreman gets `a2a`; **nobody** gets `delegation`.
5. **Model tier follows the consequence of being wrong**, not "writes code". Cheap model where the compiler or a validator catches the mistake; expensive model where a wrong answer compiles fine and just produces a wrong number.
6. **DeepSeek is primary until Anthropic is re-authenticated.** Every seat runs `ds/*` for now.
7. **Fix duplicate authority before adding seats.** One orchestrator, and it does not build.

---

## 2. Roster — 4 core seats

| Handle | Title | One job | Owns (paths) | Model |
|---|---|---|---|---|
| `@foreman` *(now `steve`)* | Shop Foreman | Frame task, pick owner, review, stop at human gate | nothing — read-only | `ds/deepseek-v4-pro-max` |
| `@harness` *(now `jes`)* | Wiring Harness | Glue code, dyno automation, ship the build | `scripts/app`, `scripts/ui`, `scripts/controls`, `scripts/drivetrain`, `scripts/fuel`, `scripts/intake`, `scripts/ecu`, `scripts/dyno`, `scripts/updates`, `server/`, `installer/`, `scenes/`, `project.godot` | `ds/deepseek-v4-flash` |
| `@crank` *(now `physics`)* | Crankshaft | Thermodynamics + audio pipeline — the reference kernel | `scripts/engine`, `scripts/exhaust`, `scripts/audio`, `scripts/render`, `scripts/dyno/validate*` | `ds/deepseek-v4-pro` |
| `@native` *(new profile)* | Native Kernel | GDExtension twin, parity, C++ build | `gdextension/src`, `gdextension/SConstruct`, `gdextension/bin`, build scripts | `ds/deepseek-v4-pro` *(→ `anthropic/claude-sonnet-*` on re-auth)* |

### Why `@native` exists

`gdextension/src` = **25 C++ files** (`cylinder.cpp`, `cylinder_kernel.cpp`, `exhaust_gas.cpp`, `firing_orders.cpp`, `gearbox.cpp`, `ecu_native.cpp`, `flame_model.cpp`, …) mirroring the GDScript kernel, plus committed `libengine_sim.*.so/.dll` binaries. Recent history is exactly this seam: *"native: port the three two-stroke fixes to the C++ kernel"*, *"native: parity green again"*. One agent cannot hold both kernels in working memory, and thermodynamics reasoning and godot-cpp binding work are different disciplines. Split it.

**Hard rule between `@crank` and `@native`: parity is bidirectional.** A kernel change lands in GDScript first (reference), then ports to C++, and the parity suite must be green before the Foreman accepts it. Neither may edit the other's file to make a test pass.

### Optional 5th seat — `@bench` (Test Bench)

Only if presets become the bottleneck. Owns `assets/engines/*.json` (23 files), `calibration/`, `ecu_bins/`, `feature_profiles/`, `tests/fixtures`. Validates presets against schema, curates dyno reference data, checks every bike JSON has a published-figure test. Model `ds/deepseek-v4-flash`.

**Trigger:** more than ~2 preset/spec-verification tasks per week, or a calibration regression slips through. Not before.

---

## 2b. Model routing — verified against the live router

Tested by real completion call through 9router. **Do not trust the catalog list** — 1148 entries advertised, most routes have no working credentials.

| Route | Result | Verdict |
|---|---|---|
| `ds/deepseek-v4-pro` | 200, 1.5 s | ✅ kernel / native |
| `ds/deepseek-v4-pro-max` | 200, 1.2 s | ✅ foreman |
| `ds/deepseek-v4-flash` | 200, 0.7 s | ✅ glue / bulk |
| `ds/deepseek-v4-flash-vision-exp` | 200, 0.8 s | ✅ when vision is needed |
| `ds/deepseek-v4-pro-none` | 200, 1.3 s | ✅ no-think fallback |
| `heavy-task` | 200, 1.3 s | ✅ opaque alias — avoid, not reproducible |
| `gemini/gemini-3.8-flash` | **400** | thinking level MINIMAL unsupported — needs `reasoning_effort` ≥ medium |
| `anthropic/claude-*` | **404** | "No active credentials for provider: anthropic" |
| `cl/*` (Cline) | **401** | "re-authenticate your Cline account" — dead |
| `cx/*` (Codex) | **404** | no active credentials |

All five DeepSeek routes are capability-identical: **1M context, 384K max output, tool calling ✅, reasoning ✅**. The only structural differences are vision (flash has it, pro doesn't) and reasoning depth. So "pro" buys thinking, nothing else — spend it only where thinking *is* the job.

**Prefix legend:** `cl` = **Cline** (a VS Code extension's passthrough pool — *not* Claude), `cx` = Codex, `ds` = DeepSeek, `anthropic` = the real Anthropic API route.

**Upgrade path (blocked):** Yves holds a real Anthropic subscription. Once re-authenticated in the 9router dashboard, move `@native` and `@foreman` to `anthropic/claude-sonnet-*`. Every other seat stays on DeepSeek — C++ lifetime bugs and QA judgment are the only two jobs that earn the expensive model.

---

## 3. Tool matrix

Toolsets per the config's `known_builtin_toolsets`. `a2a` = `message_agent`.

| Toolset | foreman | harness | crank | native |
|---|:--:|:--:|:--:|:--:|
| `a2a` | ✅ | ✅ | ✅ | ✅ |
| `kanban` | ✅ | ✅ | — | — |
| `todo` | ✅ | ✅ | ✅ | ✅ |
| `session_search` | ✅ | ✅ | ✅ | ✅ |
| `memory` | ✅ | ✅ | ✅ | ✅ |
| `skills` | ✅ | ✅ | ✅ | ✅ |
| `clarify` | ✅ | ✅ | — | — |
| `file` | ✅ read | ✅ | ✅ | ✅ |
| `terminal` | ❌ | ✅ | ✅ | ✅ |
| `code_execution` | ❌ | ✅ | ✅ | ✅ |
| `web` | ❌ | ✅ | ✅ papers | ✅ docs |
| `vision` | ❌ | ✅ | ✅ | ✅ |
| `cronjob` | ❌ | ✅ | ❌ | ❌ |
| `browser` | ❌ | ❌ | ❌ | ❌ |
| `computer_use` | ❌ | ❌ | ❌ | ❌ |
| `image_gen` / `video_gen` | ❌ | ❌ | ❌ | ❌ |
| `tts` / `stt` | ❌ | ❌ | ❌ | ❌ |
| `discord` | ❌ | ❌ | ❌ | ❌ |
| `x_search` | ❌ | ❌ | ❌ | ❌ |
| `delegation` | ❌ | ❌ | ❌ | ❌ |
| `connections` (MCP) | ❌ | ✅ gitlab | ❌ | ✅ gitlab |

Notable cuts:
- **foreman loses `terminal` + `code_execution`.** QA by reading diffs and artifacts, not by editing. The single most important cut — an orchestrator with a shell stops delegating and starts doing.
- **harness loses `browser`, `image_gen`, `video_gen`.** Not needed; they cost turns.
- **crank loses `browser`, `cronjob`.** Research via `web` only.
- **nobody has `delegation`.** Sub-agent spawning is where the loop risk lives.
- **nobody has gen tools** now that davinci is off the project. Store art is a separate, later job — don't pre-provision for it.

---

## 4. Group rooms

| Room | Members | Purpose |
|---|---|---|
| **Engine Builder** | harness, crank, native | Build traffic. Code, kernel, parity. |
| **Release Gate** | foreman, harness, crank | Verdicts only. Dyno Δ < 2% on 3 ref bikes, WAV + spectrogram per IR, no clipping at 0 dBFS, zero Godot script errors, Android install + logcat clean. No code in this room. |

Group rooms share conversation only — not memory, not tools, not permissions. Each has a fenced turn limit; the Foreman reports and stops for Yves.

---

## 5. Handoff protocol (every `message_agent`)

```
OUTCOME:        one sentence, what done looks like
ACCEPTANCE:     checkable criteria (number or artifact, not opinion)
OWNER:          exactly one handle
DELIVERABLE:    exact path or artifact
STOP:           when to stop and report instead of iterating
```

**Three gates, deliberately split:**

- `@foreman` = **process gate** — did the owner deliver what was asked, is it complete, is it honest.
- `@harness` = **technical gate** — does it compile, does the dyno pass Δ < 2%, does the APK install with a clean logcat.
- Yves = **ship gate** — version bump, release, OTA publish, `git push`, deletion, money.

**Escalation ladder:** owner self-checks → foreman reviews (one focused revision max) → Yves. Never more than one revision loop; second miss escalates with the delta.

**Model escalation:** if a task resists two attempts, or spans more than two subsystems, the bot asks Yves for a model bump rather than grinding on flash. Cheaper than blanket-pro, and measurable.

---

## 6. Rollout

| Phase | Work | Who |
|---|---|---|
| **P0** ✅ done | `@steve` soul rewritten as Shop Foreman; `@physics` description corrected off "orchestrator" | jes |
| **P1** | Trim harness soul (drop "orchestrate" — that's the foreman's now) + tool pruning + models: foreman `pro-max`, harness `flash`, crank `pro`. Needs gateway restart. | jes, then Yves restarts |
| **P2** | Create `@native` via New Bot; I write `soul.md` + `profile.yaml` | Yves clicks, jes writes |
| **P3** | Two group rooms; `groups: [Engine Builder]` on each profile | Yves |
| **P4** | **Calibration run:** hand the team one real task. Measure turns, wall time, tokens, and whether it needed the Foreman at all. Then prune what didn't earn its place. | team |

P4 is the point of the whole exercise. If a single capable agent does it better, the team gets cut — same conclusion the source video reached.

---

## 7. Open decisions

1. **Names.** Adopt the shop set (`@foreman`, `@harness`, `@crank`, `@native`) or keep current handles? A handle *is* the profile dir name, so renaming = moving the dir with the gateway stopped, during the P1 restart. Titles are free; handles are the only risky bit.
2. **`@native` creation:** the `forge` handle was never created on disk, so there's nothing to rename — make it `@native` from the start.
3. **Dyno split.** Proposed, pending confirm: harness owns dyno *automation* (`scripts/dyno/*`), crank owns the dyno *gate function* (`validate*`).
