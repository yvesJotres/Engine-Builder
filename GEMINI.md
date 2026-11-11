# Engine Builder — Agent Guidelines & Project Rules

## 1. Tooling & Execution Environment

### Godot 4.7.2 Executable
- **Path**: `D:\Program Files (x86)\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
- **Note**: Godot is not on system `PATH`. Always invoke by its full path.
- **Headless Tests**:
  - Run headless test:
    ```powershell
    & "D:\Program Files (x86)\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . -s <res_or_path_to_test>
    ```
  - **Import Step**: When adding or altering scripts with `class_name`, run `--headless --path . --import` once before running headless tests to avoid `Identifier not declared` errors:
    ```powershell
    & "D:\Program Files (x86)\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --import
    ```

### Python Executable
- Use `python3.14` or `py` (e.g. `C:\ProgramData\chocolatey\bin\python3.14.exe`).

---

## 2. Release & Patch Publishing Workflow

### Automatic Patch Publishing (Standing Approval)
- **Automatic & Pre-approved**: Do **NOT** stop to prompt for user confirmation before publishing OTA patches.
- **Workflow**:
  1. Verify changes against the test gate:
     ```powershell
     & "C:\ProgramData\chocolatey\bin\python3.14.exe" server/publish_update.py --draft
     ```
  2. Promote the draft:
     ```powershell
     & "C:\ProgramData\chocolatey\bin\python3.14.exe" server/publish_update.py --promote
     ```
  3. Report the published delta version and status.
- **Ship Script Changes via Server Patch, Never Rebuild APK unnecessarily**:
  - GDScript, scene, sound, UI, and asset updates are deployed as OTA patches.
  - An APK rebuild is **only** required when native binaries (`gdextension`) or Android manifest configurations change.
  - Never prompt or offer to rebuild APK for script/UI edits.

### Release Governance
- **Version Source**: `project.godot` (`application/config/version`).
- **Android Sync**: Android `version/name` must match `application/config/version`, and `version/code` must increment for every full APK release.
- **Windows Installer**: Installer version must always match `application/config/version`.

---

## 3. Device Testing & Debugging

- **Always Debug on Device When Available**:
  - Whenever a device/phone is reachable (via USB `adb` or wireless debugging over Tailscale/LAN), run the change on the device.
  - Capture screenshots and logcat traces to confirm visual and runtime stability (headless tests may pass while device shows UI errors or grey screens).
  - Check `adb devices` before concluding a task.
  - If the device is unreachable, explicitly report it and request the current wireless debugging port.

---

## 4. Diagnostics & Media Handling

### Audio Rendering & Comparisons
- Whenever rendering engine sounds (via Audio Lab or diagnostics), **always** provide both the **WAV audio file** and the **spectrogram PNG**. Do not send only one.

### Knowledge Graph (`graphify`)
- Use the existing graph in `graphify-out/graph.json` to query architecture, relationships, and code locations:
  ```powershell
  & "C:\ProgramData\chocolatey\bin\python3.14.exe" -m graphify query "<question>"
  ```
- Run incremental updates after creating or moving files:
  ```powershell
  & "C:\ProgramData\chocolatey\bin\python3.14.exe" -m graphify update .
  ```

---

## 5. Development Principles & Code Quality

- **Visual Realism & Depth**: When building or refining engine models, intake/exhaust paths, and UI controls, check visual fidelity on screen and implement realistic engineering behaviors.
- **Token Efficiency & Diagnostics**: Create dedicated probe scripts in `tools/diagnostics/` rather than burning context on repeated manual investigations.
- **Physics Fixes Over Fudge Factors**: Physics fixes are allowed when a preset's JSON cannot reach its reference. Change the simulator's physics in a general way, and add a test. Not allowed: torque or power multipliers, lookups of reference curves, per-bike adjustments, or guessed ECU maps.
- **Git Checkpoints**: Commit/push or save working states to Git before undertaking risky refactors.
