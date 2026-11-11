"""Draw any dyno sample file as a two-axis dyno graph, after checking the points.

Input JSON (every key optional except the two series):
  {
    "title": "...",
    "axes": {
      "x":     {"label": "EngSpd (rpm)", "min": 3900, "max": 13700},
      "left":  {"label": "WhlPwr (hp)",  "min": 6.0,  "max": 36.5, "ticks": [10, 15, 20, 25, 30, 35]},
      "right": {"label": "EngTrq (N·m)", "min": 14.0, "max": 22.5}
    },
    "power_hp":  [[rpm, value], ...],   # drawn on the left axis
    "torque_nm": [[rpm, value], ...]    # drawn on the right axis
  }

Any axis without min/max is taken from the data with 5% padding. Any label without a value uses a default.
Checks before drawing (any failure stops the run, nothing is drawn):
  - each series has at least two points and no duplicate rpm
  - each series is sorted by rpm (sorted in place, with a note)
  - every value and rpm lies inside its declared axis range, so a value from the wrong series is caught

Run: python tools/diagnostics/plot_samples.py <samples.json> <out.png>
"""
import argparse
import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


def series_points(data: dict, key: str) -> list:
    return [tuple(p) for p in data.get(key, [])]


def check(name: str, pts: list, x_range: tuple, y_range: tuple) -> tuple:
    errors = []
    if len(pts) < 2:
        return pts, [f"{name}: needs at least two points, has {len(pts)}"]
    rpms = [p[0] for p in pts]
    if len(set(rpms)) != len(rpms):
        errors.append(f"{name}: duplicate rpm {sorted({r for r in rpms if rpms.count(r) > 1})}")
    if rpms != sorted(rpms):
        pts = sorted(pts, key=lambda p: p[0])
        print(f"note: {name} was not sorted by rpm; sorted for drawing")
    for r, v in pts:
        if not x_range[0] <= r <= x_range[1]:
            errors.append(f"{name}: rpm {r} outside x range {x_range}")
        if not y_range[0] <= v <= y_range[1]:
            errors.append(f"{name}: value {v} at {r} rpm outside its axis {y_range} (wrong series?)")
    return pts, errors


def padded(values: list) -> tuple:
    lo, hi = min(values), max(values)
    pad = (hi - lo) * 0.05 or 1.0
    return lo - pad, hi + pad


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("samples")
    ap.add_argument("out")
    args = ap.parse_args()

    data = json.loads(Path(args.samples).read_text(encoding="utf-8"))
    axes = data.get("axes", {})
    xa, la, ra = axes.get("x", {}), axes.get("left", {}), axes.get("right", {})
    power = series_points(data, "power_hp")
    torque = series_points(data, "torque_nm")

    all_rpm = [p[0] for p in power + torque] or [0, 1]
    x_range = (xa.get("min", min(all_rpm)), xa.get("max", max(all_rpm)))
    if "min" not in xa or "max" not in xa:
        x_range = padded(all_rpm)
    left_range = (la["min"], la["max"]) if "min" in la and "max" in la else padded([p[1] for p in power] or [0, 1])
    right_range = (ra["min"], ra["max"]) if "min" in ra and "max" in ra else padded([p[1] for p in torque] or [0, 1])

    power, e1 = check("power_hp", power, x_range, left_range)
    torque, e2 = check("torque_nm", torque, x_range, right_range)
    if e1 + e2:
        print("Checks failed, nothing drawn:")
        for e in e1 + e2:
            print("  - " + e)
        return 1

    fig, ax = plt.subplots(figsize=(10, 6.2), dpi=110)
    ax.set_xlim(*x_range)
    ax.set_ylim(*left_range)
    if la.get("ticks"):
        ax.set_yticks(la["ticks"])
    left_label = la.get("label", "power (hp)")
    right_label = ra.get("label", "torque (N·m)")
    ax.set_xlabel(xa.get("label", "engine speed (rpm)"))
    ax.set_ylabel(left_label)
    ax.grid(alpha=0.3)
    if power:
        ax.plot([p[0] for p in power], [p[1] for p in power], "-o", color="#1f77b4", ms=4, lw=1.6,
                label=f"{left_label}, {len(power)} points")
    ax2 = ax.twinx()
    ax2.set_ylim(*right_range)
    ax2.set_ylabel(right_label)
    if torque:
        ax2.plot([t[0] for t in torque], [t[1] for t in torque], "-o", color="#2ca02c", ms=4, lw=1.6,
                 label=f"{right_label}, {len(torque)} points")
    ax.set_title(data.get("title", Path(args.samples).stem))
    h1, l1 = ax.get_legend_handles_labels()
    h2, l2 = ax2.get_legend_handles_labels()
    if h1 or h2:
        ax.legend(h1 + h2, l1 + l2, loc="lower right", fontsize=8)
    fig.tight_layout()
    fig.savefig(args.out)
    print(f"ok: {len(power)} left-axis, {len(torque)} right-axis points -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
