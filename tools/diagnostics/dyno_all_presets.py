"""Run the engine-sim dyno for every bundled preset and chart each one in the reference format.

For each preset in assets/engines/: runs tools/diagnostics/dyno_curve_dump.gd through Godot (headless), writes
reports/sim_dyno/<id>.json in the reference chart format, and draws reports/sim_dyno/<id>.png with plot_reference_curve.py.
A preset whose engine stalls produces no curve and is listed as failed. Writes reports/sim_dyno/summary.txt.
Run: python tools/diagnostics/dyno_all_presets.py [--godot PATH]
"""
import argparse
import json
import math
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import plot_reference_curve  # noqa: E402

GODOT_DEFAULT = r"D:\Program Files (x86)\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
EFFICIENCY = 0.93
OUT = ROOT / "reports" / "sim_dyno"


def run_dump(godot: str, preset_id: str) -> list:
    proc = subprocess.run(
        [godot, "--headless", "--path", str(ROOT), "-s", "tools/diagnostics/dyno_curve_dump.gd", "--", preset_id],
        capture_output=True, text=True, timeout=1800)
    rows = []
    for line in proc.stdout.splitlines():
        parts = line.strip().split(",")
        if len(parts) == 8 and parts[0].replace(".", "").isdigit():
            rows.append((float(parts[0]), float(parts[1]), float(parts[2])))
    return rows


def nice_ticks(lo: float, hi: float, count: int = 6) -> list:
    span = hi - lo
    raw = span / count
    magnitude = 10 ** math.floor(math.log10(raw))
    step = min((m * magnitude for m in (1, 2, 2.5, 5, 10) if m * magnitude >= raw), default=raw)
    start = math.ceil(lo / step) * step
    ticks = []
    value = start
    while value <= hi + 1e-9:
        ticks.append(round(value, 6))
        value += step
    return ticks


def build(preset_id: str, rows: list) -> dict:
    power = [[round(r), round(hp * EFFICIENCY, 2)] for r, _, hp in rows]
    torque = [[round(r), round(t, 2)] for r, t, _ in rows]
    p_lo, p_hi = min(v for _, v in power), max(v for _, v in power)
    t_lo, t_hi = min(v for _, v in torque), max(v for _, v in torque)
    left_lo = math.floor(p_lo * 0.9 / 5) * 5
    left_hi = math.ceil(p_hi * 1.1 / 5) * 5
    right_lo = math.floor(t_lo * 0.9)
    right_hi = math.ceil(t_hi * 1.1)
    left_ticks = nice_ticks(left_lo, left_hi)
    right_ticks = nice_ticks(right_lo, right_hi)
    return {
        "title": f"{preset_id}, engine sim dyno (estimated rear wheel = crank × 93%)",
        "source_note": "Engine sim dyno, full pull through all gears, 42 rpm bins. Power = crank hp × 0.93 (rear wheel estimate); torque = crank engine torque.",
        "axes": {
            "x": {"label": "EngSpd (rpm)", "min": math.floor(rows[0][0] * 0.95 / 100) * 100,
                  "max": math.ceil(rows[-1][0] * 1.03 / 100) * 100},
            "left": {"label": "WhlPwr (hp)", "min": left_lo, "max": left_hi, "ticks": left_ticks},
            "right": {"label": "EngTrq (N·m)", "min": right_lo, "max": right_hi, "ticks": right_ticks},
        },
        "power_hp": power,
        "torque_nm": torque,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--godot", default=GODOT_DEFAULT)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    presets = sorted(p.stem for p in (ROOT / "assets" / "engines").glob("*.json"))
    summary = []
    for preset_id in presets:
        rows = run_dump(args.godot, preset_id)
        if not rows:
            summary.append(f"{preset_id}: FAILED, the engine produced no curve")
            print(summary[-1], flush=True)
            continue
        data = build(preset_id, rows)
        json_path = OUT / f"{preset_id}.json"
        json_path.write_text(json.dumps(data, indent=1, ensure_ascii=False), encoding="utf-8")
        plot_reference_curve.plot(data, OUT / f"{preset_id}.png")
        peak_p = max(rows, key=lambda r: r[2])
        peak_t = max(rows, key=lambda r: r[1])
        summary.append(f"{preset_id}: wheel peak {peak_p[2] * EFFICIENCY:.1f} hp at {peak_p[0]:.0f} rpm, "
                       f"crank torque peak {peak_t[1]:.1f} N·m at {peak_t[0]:.0f} rpm")
        print(summary[-1], flush=True)
    (OUT / "summary.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
