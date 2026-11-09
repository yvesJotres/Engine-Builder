"""Plot a source sweep against its bundled online wheel-dyno reference."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preset", default="honda_cbr1000rrr_sp")
    parser.add_argument("--check", action="store_true", help="exit nonzero if the accuracy contract fails")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    result = json.loads((root / "build" / f"dyno_{args.preset}_repaired.json").read_text(encoding="utf-8"))
    reference = json.loads((root / "assets/dyno" / f"{args.preset}.json").read_text(encoding="utf-8"))
    assert result["reference_id"] == reference["preset_id"] == args.preset
    assert reference["basis"] == "rear_wheel" and reference["power_unit"] == "mechanical_hp"
    comparison = result["online_comparison"]
    efficiency = result["wheel_estimate_efficiency"]
    normalization = result["online_normalization"]
    curve = result["curve"]
    x = [point["rpm"] for point in curve]
    wheel_hp = [point["hp"] * efficiency * normalization for point in curve]
    wheel_torque = [point["torque"] * efficiency * normalization for point in curve]
    ref_x = [point[0] for point in reference["power_samples"]]
    ref_hp = [point[1] for point in reference["power_samples"]]
    ref_torque = [hp * 745.7 / (rpm * 6.283185307179586 / 60) for rpm, hp in reference["power_samples"]]
    fig, axes = plt.subplots(1, 2, figsize=(13, 5.5), layout="constrained")
    for ax, simulated, measured, ylabel in zip(axes, [wheel_hp, wheel_torque], [ref_hp, ref_torque], ["Rear-wheel power (mechanical hp)", "Engine-equivalent rear-wheel torque (Nm)"]):
        ax.plot(x, simulated, label=f"Source × {efficiency:.2f} driveline × {normalization:.4f} DIN", color="#1976bd", linewidth=2)
        ax.plot(ref_x, measured, "o--", markersize=3, label="BSD stock / BikeSocial — approximate trace", color="#444444", linewidth=1.5)
        ax.set(xlabel="Engine speed (rpm)", ylabel=ylabel, xlim=(3500, 15000))
        ax.grid(alpha=0.2)
        ax.legend(fontsize=8, loc="upper left")
    uncertainty = reference["curve_uncertainty_hp"]
    axes[0].fill_between(ref_x, [p - uncertainty for p in ref_hp], [p + uncertainty for p in ref_hp], alpha=0.12, color="#555555")
    axes[0].scatter([reference["peak_power_rpm"]], [reference["peak_power_hp"]], color="#111111", zorder=4)
    axes[1].scatter([reference["peak_torque_rpm"]], [reference["peak_torque_lb_ft"] * 1.3558179483314], color="#111111", zorder=4)
    matched = all(comparison[key] for key in ["power_pass", "torque_pass", "peak_rpm_pass", "curve_pass"])
    fig.suptitle(f"2020 CBR1000RR-R Fireblade SP · {result['physics_hz']:.0f} Hz source sweep\n"
                 f"Peak errors: power {comparison['power_error']:+.1%}, torque {comparison['torque_error']:+.1%} · "
                 f"Full curve {'MATCHED' if matched else 'NOT MATCHED'}", fontsize=13)
    fig.supxlabel("Reference: stock UK base RR-R powertrain, shared with SP · DIN normalized from model air (300 K / 101325 Pa) · provisional cams and runners", fontsize=9)
    output = root / "reports" / f"{args.preset}_dyno_comparison.png"
    fig.savefig(output, dpi=160)
    plt.close(fig)
    (root / "build/accuracy" / f"{args.preset}_online_comparison.json").write_text(json.dumps(comparison, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(comparison, indent=2))
    print(f"Saved {output}")
    return 1 if args.check and not matched else 0


if __name__ == "__main__":
    raise SystemExit(main())
