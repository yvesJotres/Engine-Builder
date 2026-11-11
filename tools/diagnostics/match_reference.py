"""Point-by-point comparison of a sim curve with the stored reference, at every reference rpm.

Reference power is taken as stored. Reference torque is derived from that power (N·m = hp × 7121 / rpm),
because the stored torque line disagrees with its own power below about 11,250 rpm.
The sim is cranked; the wheel figure uses the drivetrain factor DRIVETRAIN (an assumption, see the plan).
Reference modes:
  relabel (default): below 11,250 rpm the stored power and torque lines are swapped. Each point is read back on the chart's
      other axis (same height), which makes power = torque × rpm hold within about 3%. Above 11,250 rpm the stored values are used.
  stored: the file exactly as stored (torque and power taken as labelled).
The stored file is never edited.
Run: python tools/diagnostics/match_reference.py <attempt_csv_name> [drivetrain] [relabel|stored]
"""
import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REF = ROOT / "assets" / "dyno" / "honda_cbr250rr_2020.json"
HP_PER_NM_RPM = 1.0 / 7121.0  # hp = N·m × rpm / 7121


def load_sim(name: str, drivetrain: float) -> list:
    rows = []
    with (ROOT / "reports" / "sim_dyno" / "attempts" / f"{name}.csv").open(encoding="utf-8") as f:
        for line in f:
            p = line.strip().split(",")
            if len(p) == 8 and p[0].replace(".", "").isdigit():
                rows.append((float(p[0]), float(p[1]) * drivetrain, float(p[2]) * drivetrain))
    return rows


def interp(xs: list, ys: list, x: float) -> float:
    for i in range(1, len(xs)):
        if xs[i - 1] <= x <= xs[i]:
            t = (x - xs[i - 1]) / (xs[i] - xs[i - 1])
            return ys[i - 1] + t * (ys[i] - ys[i - 1])
    return float("nan")


SWAP_BELOW_RPM = 11250.0


def reference_points(mode: str) -> tuple:
    """Return (rpm list, hp list, N·m list) on the chart's power grid, following the mode."""
    ref = json.loads(REF.read_text(encoding="utf-8"))
    chart = json.loads((ROOT / "reports" / "cbr250rr_reference_curve.json").read_text(encoding="utf-8"))
    power = sorted(ref["power_samples"])
    rx = [p[0] for p in power]
    stored_hp = [p[1] for p in power]
    if mode == "stored":
        return rx, stored_hp, [h / HP_PER_NM_RPM / r for h, r in zip(stored_hp, rx)]
    L, R = chart["axes"]["left"], chart["axes"]["right"]
    tq_rpm = [p[0] for p in sorted(chart["torque_nm"])]
    tq_val = [p[1] for p in sorted(chart["torque_nm"])]
    hp_out, nm_out = [], []
    for r, hp in zip(rx, stored_hp):
        if r < SWAP_BELOW_RPM:
            stored_nm = interp(tq_rpm, tq_val, r)
            # stored torque read on the power axis (same height) gives the power; stored power read on the torque axis gives the torque
            hp_out.append(L["min"] + (stored_nm - R["min"]) / (R["max"] - R["min"]) * (L["max"] - L["min"]))
            nm_out.append(R["min"] + (hp - L["min"]) / (L["max"] - L["min"]) * (R["max"] - R["min"]))
        else:
            hp_out.append(hp)
            nm_out.append(hp / HP_PER_NM_RPM / r)
    return rx, hp_out, nm_out


def main() -> int:
    name = sys.argv[1] if len(sys.argv) > 1 else "woschni_native"
    drivetrain = float(sys.argv[2]) if len(sys.argv) > 2 else 0.87
    mode = sys.argv[3] if len(sys.argv) > 3 else "relabel"
    rx, ry, rnm = reference_points(mode)
    sim = load_sim(name, drivetrain)
    sx = [r[0] for r in sim]
    print(f"reference mode {mode}, drivetrain {drivetrain}")
    print(f"{'rpm':>6} {'ref hp':>7} {'sim hp':>7} {'hp err%':>8} | {'ref Nm':>7} {'sim Nm':>7} {'Nm err%':>8}")
    errs_hp, errs_nm = [], []
    for rpm in sorted(set(rx) | set(sx)):
        if rpm < rx[0] or rpm > rx[-1]:
            continue
        ref_hp = interp(rx, ry, rpm)
        ref_nm = interp(rx, rnm, rpm)
        sim_hp = interp(sx, [r[2] for r in sim], rpm)
        sim_nm = interp(sx, [r[1] for r in sim], rpm)
        eh = (sim_hp - ref_hp) / ref_hp * 100
        en = (sim_nm - ref_nm) / ref_nm * 100
        errs_hp.append(abs(eh))
        errs_nm.append(abs(en))
        print(f"{rpm:6.0f} {ref_hp:7.2f} {sim_hp:7.2f} {eh:8.1f} | {ref_nm:7.2f} {sim_nm:7.2f} {en:8.1f}")
    print(f"mean |hp err| {sum(errs_hp)/len(errs_hp):.1f}%  max {max(errs_hp):.1f}%")
    print(f"mean |Nm err| {sum(errs_nm)/len(errs_nm):.1f}%  max {max(errs_nm):.1f}%")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
