"""Run one headless dyno pull for a preset and save its CSV, JSON and graph.

Usage: python tools/diagnostics/run_dyno.py <preset_id> [--path native|gd] [--name NAME] [key=value ...]
  preset_id  a file name in assets/engines without .json, e.g. honda_cbr250rr_2020
  --path     native (default, C++ kernel) or gd (GDScript path)
  --name     output name; default <preset_id>_<time>
  key=value  overrides passed to the dyno, e.g. valve_cd=1.0

Outputs go to reports/sim_dyno/runs/<name>.csv, .json and .png.
"""
import argparse
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import attempt_graphs  # noqa: E402
import dyno_all_presets as presets  # noqa: E402
import plot_reference_curve  # noqa: E402
import json  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "reports" / "sim_dyno" / "runs"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("preset_id")
    ap.add_argument("--path", choices=["native", "gd"], default="native")
    ap.add_argument("--name", default=None)
    ap.add_argument("overrides", nargs="*")
    args = ap.parse_args()

    if not (ROOT / "assets" / "engines" / f"{args.preset_id}.json").exists():
        print(f"No preset file assets/engines/{args.preset_id}.json")
        return 1
    name = args.name or f"{args.preset_id}_{datetime.now():%Y%m%d-%H%M%S}"
    OUT.mkdir(parents=True, exist_ok=True)

    attempt_graphs.PRESET = args.preset_id
    rows = attempt_graphs.dump(name, args.path, args.overrides)
    if not rows:
        print("The dyno produced no curve. See the CSV in reports/sim_dyno/attempts for the run output.")
        return 1

    data = presets.build(args.preset_id, rows)
    data["title"] = f"{args.preset_id}, {name}: {' '.join(args.overrides) or 'no overrides'} ({args.path} path)"
    (OUT / f"{name}.json").write_text(json.dumps(data, indent=1, ensure_ascii=False), encoding="utf-8")
    plot_reference_curve.plot(data, OUT / f"{name}.png")
    peak = max(rows, key=lambda r: r[2])
    torque = max(rows, key=lambda r: r[1])
    print(f"{name}: crank peak {peak[2]:.2f} hp at {peak[0]:.0f} rpm, wheel {peak[2] * 0.93:.2f} hp")
    print(f"  crank peak torque {torque[1]:.2f} Nm at {torque[0]:.0f} rpm")
    print(f"graph: {OUT / (name + '.png')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
