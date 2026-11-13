# Engine Builder — Agent Team Setup

Plan derived from Hermes Bot Mode best practices (Wanderloots, "Is Hermes Bot Mode Worth It?", 2026-09-06)
plus the Engine Builder architecture (Godot 4.7, GDScript kernel + GDExtension, OTA patch server).

Core findings that shape this plan:

1. **A bot is a profile.** No new primitive. Identity = soul.md; brain = provider/model; capabilities = skills (lazy-loaded) + toolsets + MCP; continuity = memory.md/user.md; operations = workspace + terminal backend.
2. **More bots is not better.** Each bot needs one job and *only* the capabilities for that job.
3. **Tool pruning is the single biggest speed win.** Inherited defaults ran a researcher into 6 sub-agent spawns and 20 minutes of looping. Tool-call counters expose the waste.
4. **Keep bots warm (5) + bot idle timeout ≥10 min** ≈ 10x faster bot-to-bot handoff (RAM cost).
5. **Three comms modes:** individual bot chat (permanent, `/new` compacts) · bot-to-bot DM (no turn cap — infinite loop risk) · group room (bounded turns, pauses for human review). Group rooms share *conversation only* — not memory, tools, or permissions.
6. **Orchestrator = quality control**, specialists = bulk work. Reviewer may demand exactly one focused revision.
7. After a session: tell each bot to update its own memory — that removes a step from the next run.

---

## 1. Roster

| Handle | Role | Status |
|---|---|---|
| `@jes` (Jotres) | Technical Director / Orchestrator | **active** |
| `@physics` | Physics & Audio Programmer (simulation kernel) | **active** |
| `@engine` | Vehicle dynamics (car mode: diff, suspension, tires, aero) | reserved — trigger: car mode greenlit |
| `@graphics` | Renderer / performance / WASM-WebGPU port | reserved — trigger: frame budget or web export |
| `@tools` | Editor tooling, preset authoring, telemetry export | reserved — trigger: third-party preset authoring |
| `@build` | CI/CD, device farm, nightly dyno regression, signing | reserved — trigger: >1 daily patch or 2 machines |

Do **not** add: Art Director, UI/UX Designer, Game Designer, Writer, Marketer — no asset pipeline, no gameplay loop, no product design surface.

---

## 2. Per-bot configuration

### `@jes` — Technical Director
- **Owns:** frame loop, dyno automation, OTA patcher + `publish_update.py`, device test (adb), version governance, all glue GDScript, preset load/validate, git checkpoints.
- **Soul additions:** team protocol (below) + "do not derive physics; delegate to @physics" + "do not publish a patch without a green gate".
- **Brain:** `heavy-task` via `custom:9router` (:20128, 1M ctx, 64k out) · reasoning **low** (coordination, not derivation).
- **Toolsets ON:** file, terminal, code_execution, desktop_ui, kanban, todo, cronjob, memory, skills, session_search, project, vision (device screenshots), web.
- **Toolsets OFF:** delegation, computer_use, image_gen, video, video_gen, tts, stt, browser, connections.
- **Memory:** memory.md + user.md ON. External/hindsight OFF.
- **Workspace:** `D:/Projects/Engine Builder`.

### `@physics` — Physics & Audio Programmer
- **Owns:** `cylinder.gd`, `engine_sim.gd`, `engine_spec.gd`, `firing_orders.gd`, presets, `exhaust_gas.gd`, `exhaust_layout.gd`, `engine_sound.gd`, `audio_renderer.gd`, `wav_writer.gd`, IR library, physics/audio tests, `docs/engine_physics/`.
- **Soul additions:** physics-fixes-over-fudge-factors rule; the two gates; "do not touch app/UI/release code — return to @jes"; "return work to @jes, never straight to the user or another bot".
- **Brain:** `heavy-task` via `custom:9router` · reasoning **medium** (thermo/流体 derivation benefits; low is under-powered here).
- **Toolsets ON:** file, terminal, code_execution, web, vision (spectrogram reading), memory, skills, todo.
- **Toolsets OFF:** delegation, cronjob, kanban, session_search, browser, computer_use, desktop_ui, image_gen, video, video_gen, tts, stt, connections, clarify.
- **Memory:** memory.md + user.md ON.
- **Workspace:** `D:/Projects/Engine Builder`.

---

## 3. Gates (the team's contract)

| Gate | Owner | Pass condition |
|---|---|---|
| Physics | `@physics` | dyno suite on 3 reference bikes; Δ < 2% on torque, power, BSFC, λ, EGT |
| Audio | `@physics` | WAV **and** spectrogram for every IR render; no clipping at 0 dBFS |
| Release | `@jes` | `publish_update.py --draft` clean → promote; device run (adb logcat + screenshot) when a phone is reachable |
| Escalate to human | `@jes` | APK rebuild (native/GDExtension or manifest change), version bump, destructive refactor |

No per-bike multipliers, no reference-curve lookups, no guessed ECU maps. A preset that cannot reach its reference means the *physics* changes, plus a test.

---

## 4. Communication topology

**Room 1 — `Engine Builder`** (exists; members `jes`, `physics`)
- All-hands daily work. User tags `@jes`; `@jes` tags `@physics`; results return to `@jes`; `@jes` reports to the user.
- Bounded turn budget per user message (default cap; keep ~6). Room pauses for human review instead of looping.
- Thread per task (dyno gate, patch ship, audio pass).

**Bot-to-bot DM** — one-off handoffs only (e.g. "run the gate on ZX-25R"). Never a conversation loop; the DM pipeline has no turn cap.

**Not used yet:** Kanban (adopt only when ownership/approval state must survive across sessions).

---

## 5. Team protocol (paste into both soul.md files)

```
TEAM PROTOCOL
- Every task statement carries: outcome, acceptance criteria, owner, deliverable, stop condition.
- Return work to the delegating bot, never straight to the user, unless asked directly.
- One focused revision per review cycle; the second attempt is reported, not silently retried.
- State the gate that proves the work before starting it (dyno / audio / release).
- Never write outside your owned paths. Need a change there? Return it with the diff request.
- Update your own memory.md at the end of a task with what you learned about this project.
```

---

## 6. Global settings to apply

| Setting | Value | Why |
|---|---|---|
| Keep bots warm | 5 | instant switching; the video's 10x win |
| Bot backend idle timeout | 15 min | long dyno renders and audio passes |
| Group room turn cap | ~6 | stops agent-to-agent runaway |
| Reasoning effort | jes=low, physics=medium | derivation vs coordination |
| Provider keys | per-profile `.env` | a bot with no key fails with HTTP 401 |

---

## 7. Bootstrap checklist

- [x] `@physics` profile + `soul.md` created
- [x] `@physics` `.env` keys installed (`HERMES_CUSTOM_9ROUTER_API_KEY`, `DEEPSEEK_API_KEY`, `BRAVE_SEARCH_API_KEY`) — 9router returns HTTP 200
- [x] `@physics` stale session policies repaired (`model` = `heavy-task`) — delivery admission works
- [x] DM channel verified end-to-end (`@physics`: "live. 9router key confirmed.")
- [x] Room `Engine Builder` exists with `jes` + `physics`
- [ ] `@physics` skills directory curated (currently only `graphify` linked)
- [ ] Toolset pruning applied to both profiles (section 2)
- [ ] Team protocol appended to both `soul.md`
- [ ] Keep-warm 5 + idle timeout 15 min
- [ ] Reasoning effort: physics → medium
- [ ] `@jes` live session model aligned with profile config (`deepseek-flash` vs `heavy-task`)
- [ ] First run: physics runs the dyno gate on 3 reference bikes and returns a Δ table

---

## 8. Cost note

`heavy-task` is a 9router *combo* alias (1M ctx, vision+audio+tools+reasoning), not a fixed model — cost and latency are decided server-side per request. If the physics loop gets expensive, move `@physics` to a cheaper coder model and keep `@jes` on `heavy-task` as quality control — that is exactly the split the video recommends (cheap specialist + strong orchestrator).
