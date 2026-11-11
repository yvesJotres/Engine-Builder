"""Draw the dyno graph for each attempt, in the reference chart format, so attempts can be compared and backtracked.

Each attempt is a name, a Cylinder path (native or gd) and key=value overrides. Writes reports/sim_dyno/attempts/<name>.png,
<name>.json (the chart data) and <name>.csv (the raw dump). Edit ATTEMPTS to add more.
Run: python tools/diagnostics/attempt_graphs.py
"""
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import plot_reference_curve  # noqa: E402
import dyno_all_presets as presets  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "reports" / "sim_dyno" / "attempts"
PRESET = "honda_cbr250rr_2020"

ATTEMPTS = [
    ("baseline_native", "native", []),
    ("baseline_gd", "gd", []),
    ("intake_valve_18mm", "native", ["intake_valve_mm=18"]),
    # Cam and valve values from ATG assets/engines/honda/cbr250rr_sp.mr. All marked [EST] there, not measured.
    ("atg_sp_mr_cams", "native", ["intake_lift_mm=8", "exhaust_lift_mm=7.5", "intake_centre_deg=465",
                                  "exhaust_centre_deg=252", "intake_duration_deg=255.4", "exhaust_duration_deg=250.8",
                                  "intake_valve_mm=22.5", "exhaust_valve_mm=19"]),
    # Diagnostic: the preset's valve_cd 1.0 and wall_heat_scale 0.28 put back to the code defaults (Cd 0.7, wall heat 1.0).
    ("physical_cd_wall", "native", ["valve_cd=0.7", "wall_heat_scale=1.0"]),
    ("physical_cd_only", "native", ["valve_cd=0.7"]),
    # The preset itself after valve_cd 1.0 and wall_heat_scale 0.28 were removed from it (code defaults apply).
    ("preset_defaults", "native", []),
    # Woschni wall heat (Heywood SI form) replaces the crank-speed-only coefficient; GDScript path.
    ("woschni_gd", "gd", []),
    ("woschni_native", "native", []),
    # Intake runner at the factbook throttle bore (32 mm, preset notes) instead of the legacy 6.6 cm2 estimate.
    ("woschni_runner32", "native", ["runner_bore_mm=32"]),
    # Diagnostic sensitivity only: effective valve discharge coefficient (valve_cd) lowered from the code default 0.7.
    ("woschni_cd045", "native", ["valve_cd=0.45"]),
    ("woschni_cd035", "native", ["valve_cd=0.35"]),
    # Reitz friction (bar per m/s speed term) replaces the linear friction in engine_sim.gd; current code, no overrides.
    ("friction_reitz", "native", []),
    # Valve discharge curve against L/D (SAE 820154 / 962527 values) with the Reitz friction.
    ("cd_curve_native", "native", []),
    # Diagnostic sweep of the discharge curve magnitude: valve_cd scales the whole L/D curve (effective Cd = valve_cd/0.7 x curve).
    # At valve_cd 0.7 the high-lift plateau is 0.42; 0.85 / 1.0 / 1.2 give about 0.51 / 0.60 / 0.72 (literature range about 0.6).
    ("cd_sweep_085", "native", ["valve_cd=0.85"]),
    ("cd_sweep_100", "native", ["valve_cd=1.0"]),
    ("cd_sweep_120", "native", ["valve_cd=1.2"]),
    # Diagnostic sensitivity only: runner length (ATG cbr250rr_sp.mr [EST] 240 mm) with the Cd 0.45 diagnostic.
    ("cd045_runner240", "native", ["valve_cd=0.45", "runner_length_m=0.24"]),
    ("cd045_runner080", "native", ["valve_cd=0.45", "runner_length_m=0.08"]),
]


def dump(name: str, path: str, overrides: list) -> list:
    cmd = [presets.GODOT_DEFAULT, "--headless", "--path", str(ROOT), "-s", "tools/diagnostics/dyno_attempt.gd", "--",
           PRESET, path] + overrides
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
    lines = [line for line in proc.stdout.splitlines() if line.strip()]
    csv_path = OUT / f"{name}.csv"
    csv_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    rows = []
    for line in lines:
        parts = line.strip().split(",")
        if len(parts) == 8 and parts[0].replace(".", "").isdigit():
            rows.append((float(parts[0]), float(parts[1]), float(parts[2])))
    return rows


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    summary = []
    only = sys.argv[1:]  # attempt names to run; all when empty
    for name, path, overrides in ATTEMPTS:
        if only and name not in only:
            continue
        rows = dump(name, path, overrides)
        if not rows:
            summary.append(f"{name}: FAILED, no curve")
            print(summary[-1], flush=True)
            continue
        data = presets.build(PRESET, rows)
        data["title"] = f"CBR250RR (2020), {name}: {' '.join(overrides) or 'no overrides'} ({path} path)"
        (OUT / f"{name}.json").write_text(json.dumps(data, indent=1, ensure_ascii=False), encoding="utf-8")
        plot_reference_curve.plot(data, OUT / f"{name}.png")
        peak = max(rows, key=lambda r: r[2])
        summary.append(f"{name}: crank peak {peak[2]:.1f} hp at {peak[0]:.0f} rpm, wheel {peak[2] * 0.93:.1f} hp")
        print(summary[-1], flush=True)
    with (OUT / "summary.txt").open("a" if only else "w", encoding="utf-8") as f:
        f.write("\n".join(summary) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
