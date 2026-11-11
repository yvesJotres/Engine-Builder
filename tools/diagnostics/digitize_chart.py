"""Digitize a dyno chart image: find the green sample markers, convert them to values, save samples and render.

Works on any chart whose two curves are drawn with marker dots of one colour (the SuperFlow stock chart is green).

Step 1 - find the axis labels (prints label positions in pixels to help calibration):
  python tools/diagnostics/digitize_chart.py <chart.png> --find-labels

Step 2 - digitize with the calibration (pixel:value pairs read from two labels on each axis):
  python tools/diagnostics/digitize_chart.py <chart.png> <out.json> \
      --x 75:4000,556:13000 --left 67:35,372:10 --right 53:22,383:15 \
      --left-label "WhlPwr (hp)" --right-label "EngTrq (N·m)" \
      --left-series upper --overlay <check.png> --render <graph.png>

  --left-series upper|lower : which curve is the left-axis series (upper = higher on screen, lower = lower on screen)
  --overlay                 : writes the chart with each point drawn on it, to check the digitizing
  --render                  : draws the graph with tools/diagnostics/plot_samples.py

Outputs a samples JSON in the format plot_samples.py reads (power_hp = left axis, torque_nm = right axis).
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = Path(__file__).resolve().parent


def parse_cal(text: str) -> tuple:
    """'p1:v1,p2:v2' -> (slope, intercept) so that value = intercept + slope * pixel."""
    (p1, v1), (p2, v2) = [tuple(float(x) for x in pair.split(":")) for pair in text.split(",")]
    slope = (v2 - v1) / (p2 - p1)
    return slope, v1 - slope * p1


def find_labels(img: np.ndarray) -> None:
    dark = img.sum(axis=2) < 300

    def groups(mask: np.ndarray, gap: int) -> list:
        idx = np.where(mask)[0]
        if len(idx) == 0:
            return []
        out, s, p = [], idx[0], idx[0]
        for i in idx[1:]:
            if i - p > gap:
                out.append((s, p))
                s = i
            p = i
        out.append((s, p))
        return [int((s + e) / 2) for s, e in out]

    grey = (np.abs(img[..., 0] - img[..., 1]) < 12) & (np.abs(img[..., 1] - img[..., 2]) < 12) & (img[..., 0] < 235)
    rows = np.where(grey.sum(axis=1) > img.shape[1] * 0.4)[0]
    cols = np.where(grey.sum(axis=0) > img.shape[0] * 0.3)[0]
    print(f"image {img.shape[1]}x{img.shape[0]} px")
    print(f"long grey horizontal lines (plot bottom/top) at rows: {rows.tolist()[:6]}...")
    print(f"long grey vertical lines (plot sides) at columns: {cols.tolist()[:6]}...")
    if len(rows):
        y0 = int(rows.max()) + 4
        print(f"x-axis labels (centre px, below row {y0}): {groups(dark[y0:y0 + 22].any(axis=0), 4)}")
    if len(cols):
        xl, xr = int(cols.min()), int(cols.max())
        print(f"left-axis labels (centre px, left of col {xl}): {groups(dark[:, max(0, xl - 26):xl - 2].any(axis=1), 3)}")
        print(f"right-axis labels (centre px, right of col {xr}): {groups(dark[:, xr + 4:min(img.shape[1], xr + 40)].any(axis=1), 3)}")
    print("Pick two labels on each axis and pass them to --x, --left, --right as pixel:value.")


def markers(img: np.ndarray, min_px: int) -> list:
    R, G, B = img[..., 0], img[..., 1], img[..., 2]
    green = (G > 150) & (R < 140) & (B < 140) & (G - R > 60)
    lab, _ = ndimage.label(green, structure=np.ones((3, 3)))
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        if sl is None or (lab[sl] == i + 1).sum() < min_px:
            continue
        ys, xs = sl
        out.append(((xs.start + xs.stop - 1) / 2.0, (ys.start + ys.stop - 1) / 2.0))
    return sorted(set(out))


def chains(pts: list, max_dx: float, max_dy: float) -> list:
    """Link markers left to right into curves. A marker joins the curve it is closest to in height."""
    out = []
    for x, y in pts:
        best, best_cost = None, None
        for c in out:
            lx, ly = c[-1]
            dx = x - lx
            if len(c) >= 2:  # predict the next height from the curve's last two points
                px, py = c[-2]
                slope = (ly - py) / (lx - px) if lx != px else 0.0
                pred = ly + slope * dx
            else:
                pred = ly
            dy = abs(y - pred)
            if 0 < dx <= max_dx and dy <= max_dy:
                cost = dy + 0.1 * dx
                if best_cost is None or cost < best_cost:
                    best, best_cost = c, cost
        if best is None:
            out.append([(x, y)])
        else:
            best.append((x, y))
    return sorted(out, key=len, reverse=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--find-labels", action="store_true")
    ap.add_argument("--x")
    ap.add_argument("--left")
    ap.add_argument("--right")
    ap.add_argument("--x-label", default="engine speed (rpm)")
    ap.add_argument("--left-label", default="power (hp)")
    ap.add_argument("--right-label", default="torque (N·m)")
    ap.add_argument("--title", default=None)
    ap.add_argument("--left-series", choices=["upper", "lower"], default="upper")
    ap.add_argument("--min-marker-px", type=int, default=20)
    ap.add_argument("--max-dx", type=float, default=40.0)
    ap.add_argument("--max-dy", type=float, default=14.0)
    ap.add_argument("--overlay")
    ap.add_argument("--render")
    args = ap.parse_args()

    img = np.array(Image.open(args.image).convert("RGB")).astype(int)
    if args.find_labels:
        find_labels(img)
        return 0
    if not (args.out and args.x and args.left and args.right):
        ap.error("out, --x, --left and --right are needed to digitize (or use --find-labels)")

    xs = parse_cal(args.x)
    ls = parse_cal(args.left)
    rs = parse_cal(args.right)
    pts = markers(img, args.min_marker_px)
    curves = [c for c in chains(pts, args.max_dx, args.max_dy) if len(c) >= 3][:2]
    if len(curves) < 2:
        print(f"Found {len(pts)} markers but only {len(curves)} curve(s); adjust --max-dx / --max-dy.")
        return 1
    upper, lower = sorted(curves, key=lambda c: np.mean([p[1] for p in c]))
    left_curve, right_curve = (upper, lower) if args.left_series == "upper" else (lower, upper)

    # parse_cal gives (slope, intercept): value = intercept + slope * pixel, for x (rpm) and both y axes
    rpm_of = lambda x: xs[1] + xs[0] * x  # noqa: E731

    def to_points(curve, cal):
        slope, icpt = cal
        return sorted(([round(rpm_of(x)), round(icpt + slope * y, 2)] for x, y in curve), key=lambda p: p[0])

    power = to_points(left_curve, ls)
    torque = to_points(right_curve, rs)
    data = {
        "title": args.title or Path(args.image).stem,
        "source": f"digitized from {Path(args.image).name}: green marker centres, axis calibration {args.x} / {args.left} / {args.right}",
        "axes": {
            "x": {"label": args.x_label, "min": min(p[0] for p in power + torque) - 100,
                  "max": max(p[0] for p in power + torque) + 100},
            "left": {"label": args.left_label, "min": min(p[1] for p in power) - 1,
                     "max": max(p[1] for p in power) + 1},
            "right": {"label": args.right_label, "min": min(p[1] for p in torque) - 0.5,
                      "max": max(p[1] for p in torque) + 0.5},
        },
        "power_hp": power,
        "torque_nm": torque,
    }
    Path(args.out).write_text(json.dumps(data, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"markers {len(pts)}; curves {len(left_curve)} (left) and {len(right_curve)} (right) -> {args.out}")

    if args.overlay:
        ov = Image.open(args.image).convert("RGB")
        dr = ImageDraw.Draw(ov)
        for x, y in left_curve:
            dr.ellipse([x - 4, y - 4, x + 4, y + 4], outline=(255, 0, 255), width=2)
        for x, y in right_curve:
            dr.ellipse([x - 4, y - 4, x + 4, y + 4], outline=(255, 255, 0), width=2)
        ov.save(args.overlay)
        print(f"overlay -> {args.overlay} (magenta = left-axis series, yellow = right-axis series)")
    if args.render:
        r = subprocess.run([sys.executable, str(HERE / "plot_samples.py"), args.out, args.render])
        return r.returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
