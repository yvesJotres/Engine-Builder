"""Plot the digitized CBR250RR reference curve in the dyno-graph format.

Reads reports/cbr250rr_reference_curve.json and writes reports/cbr250rr_reference_curve.png.
Power (WhlPwr) is drawn on the left axis, torque (EngTrq) on the right axis, and the two curves cross near 11,400 rpm.
Each curve is one continuous line. Its colour changes at the crossing so that each line keeps its colour through it.
The power line is drawn on top of the torque line.
Run: python tools/diagnostics/plot_reference_curve.py [--data PATH] [--out PATH]
"""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
from matplotlib.lines import Line2D

POWER_COLOUR = "#f57c00"  # orange: the power curve before the crossing
TORQUE_COLOUR = "#1976bd"  # blue: the torque curve before the crossing


def _interp(points, x):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    if x <= xs[0]:
        return ys[0]
    if x >= xs[-1]:
        return ys[-1]
    for i in range(1, len(xs)):
        if xs[i] >= x:
            t = (x - xs[i - 1]) / (xs[i] - xs[i - 1])
            return ys[i - 1] + t * (ys[i] - ys[i - 1])
    return ys[-1]


def _to_left_axis(value, axes_def):
    right = axes_def["right"]
    left = axes_def["left"]
    return (value - right["min"]) / (right["max"] - right["min"]) * (left["max"] - left["min"]) + left["min"]


def _crossing(power, torque, axes_def):
    # the rpm where the two curves are closest between 10,000 and 12,000 rpm, both on the left axis scale
    best = None
    rpm = 10000.0
    while rpm <= 12000.0:
        gap = abs(_interp(power, rpm) - _to_left_axis(_interp(torque, rpm), axes_def))
        if best is None or gap < best[1]:
            best = (rpm, gap)
        rpm += 10.0
    return best[0]


def _with_crossing(points, x_cross, convert=lambda v: v):
    # the curve as one sorted list of (rpm, value), with the crossing point inserted so the colour change is exact
    pts = sorted((x, convert(y)) for x, y in points)
    pts.append((x_cross, convert(_interp(points, x_cross))))
    pts.sort()
    return pts


def _colour_line(segments_by_colour, xy, x_cross, colour_before, colour_after):
    # one continuous line made of segments: segments left of the crossing use colour_before, the rest colour_after
    for (x1, y1), (x2, y2) in zip(xy, xy[1:]):
        colour = colour_before if (x1 + x2) / 2 < x_cross else colour_after
        segments_by_colour.setdefault(colour, []).append([(x1, y1), (x2, y2)])


def _draw_layers(ax, segments_by_colour):
    # blue is the top layer; orange sits below it, so the blue line runs unbroken through the crossing
    layer = {TORQUE_COLOUR: 4, POWER_COLOUR: 3}
    for colour, segments in segments_by_colour.items():
        ax.add_collection(LineCollection(segments, colors=colour, linewidths=2, zorder=layer[colour]))


def plot(data: dict, output: Path) -> None:
    axes_def = data["axes"]
    power = data["power_hp"]
    torque = data["torque_nm"]

    x_cross = _crossing(power, torque, axes_def)
    # keep each line's colour through the crossing: the branch after the crossing that continues the
    # line's direction keeps its colour. Slopes are taken from 500 rpm before the crossing, on the left axis scale.
    p_at = _interp(power, x_cross)
    t_at = _to_left_axis(_interp(torque, x_cross), axes_def)
    p_slope = (p_at - _interp(power, x_cross - 500)) / 500
    t_slope = (t_at - _to_left_axis(_interp(torque, x_cross - 500), axes_def)) / 500
    window = [x_cross + k * 50 for k in range(1, 21)]

    def drift(series_value, extrapolated):
        return sum(abs(series_value(x) - extrapolated(x)) for x in window)

    p_ext = lambda x: p_at + p_slope * (x - x_cross)
    t_ext = lambda x: t_at + t_slope * (x - x_cross)
    p_after = lambda x: _interp(power, x)
    t_after = lambda x: _to_left_axis(_interp(torque, x), axes_def)
    keep_power_colour = drift(p_after, p_ext) + drift(t_after, t_ext) <= drift(p_after, t_ext) + drift(t_after, p_ext)
    power_after_colour = POWER_COLOUR if keep_power_colour else TORQUE_COLOUR
    torque_after_colour = TORQUE_COLOUR if keep_power_colour else POWER_COLOUR

    fig, ax = plt.subplots(figsize=(10, 6.4), layout="constrained")
    # both curves share one axes on the left-axis scale. Torque is converted to that scale; the right axis is a scale only.
    # Torque is drawn at zorder 2 and power at zorder 3, so the power line sits on top everywhere, including the crossing.
    torque_xy = _with_crossing(torque, x_cross, lambda v: _to_left_axis(v, axes_def))
    power_xy = _with_crossing(power, x_cross)
    segments_by_colour = {}
    _colour_line(segments_by_colour, torque_xy, x_cross, TORQUE_COLOUR, torque_after_colour)
    _colour_line(segments_by_colour, power_xy, x_cross, POWER_COLOUR, power_after_colour)
    _draw_layers(ax, segments_by_colour)

    ax.set_xlim(axes_def["x"]["min"], axes_def["x"]["max"])
    ax.set_ylim(axes_def["left"]["min"], axes_def["left"]["max"])
    ax.set_xticks(range(4000, 13001, 1000))
    ax.set_yticks(axes_def["left"]["ticks"])
    ax.set_xlabel(axes_def["x"]["label"])
    ax.set_ylabel(axes_def["left"]["label"])
    ax.grid(alpha=0.2)

    ax2 = ax.twinx()
    ax2.set_ylim(axes_def["right"]["min"], axes_def["right"]["max"])
    ax2.set_yticks(axes_def["right"]["ticks"])
    ax2.set_ylabel(axes_def["right"]["label"])

    legend_handles = [
        Line2D([], [], color=POWER_COLOUR, lw=2, label=f"WhlPwr (hp), peaks {max(p[1] for p in power):.1f} hp"),
        Line2D([], [], color=TORQUE_COLOUR, lw=2, label=f"EngTrq (N·m), peaks {max(p[1] for p in torque):.1f} N·m"),
    ]
    ax.legend(handles=legend_handles, loc="lower right", fontsize=9)
    ax.set_title(data.get("title", "Dyno reference curve"))

    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=150)
    plt.close(fig)


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data", type=Path, default=root / "reports" / "cbr250rr_reference_curve.json")
    parser.add_argument("--out", type=Path, default=root / "reports" / "cbr250rr_reference_curve.png")
    args = parser.parse_args()
    data = json.loads(args.data.read_text(encoding="utf-8"))
    plot(data, args.out)
    print(f"Saved {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
