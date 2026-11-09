"""Audio lab for the engine sound: render, measure, plot and compare, without writing a new script each time.

Commands (run from the project root):
  python tools/diagnostics/audio_lab/audio_lab.py render --preset yamaha_yzf_r1m --profile idle --exhaust on --intake off --name r1m_exhaust_only
  python tools/diagnostics/audio_lab/audio_lab.py stats out/audio/a.wav out/audio/b.wav
  python tools/diagnostics/audio_lab/audio_lab.py plot out/audio/a.wav [--at 2.0]
  python tools/diagnostics/audio_lab/audio_lab.py compare --preset yamaha_yzf_r1m --profile idle --variants base,exhaust_only,rasp_off,muffler_off
  python tools/diagnostics/audio_lab/audio_lab.py variants        (lists the named variants)

Outputs go to tools/diagnostics/out/audio/ (gitignored). Set GODOT to the Godot console exe if it is not at the default path.
"""
import argparse
import os
import struct
import subprocess
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
from scipy.signal import butter, find_peaks, sosfiltfilt, spectrogram, stft  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "tools" / "diagnostics" / "out" / "audio"
RATE = 44100
GODOT = os.environ.get(
    "GODOT",
    r"D:\Program Files (x86)\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
)

# named variants for compare: each is a list of render options
VARIANTS = {
    "base": [],
    "exhaust_only": ["--intake", "off"],
    "intake_only": ["--exhaust", "off"],
    "rasp_off": ["--rasp", "off"],
    "muffler_off": ["--muffler", "off"],
    "offline_solver": ["--solver", "offline"],
    "layers_off": ["--layers", "off"],
}


def _fix_header(path: Path) -> None:
    """The renderer leaves the WAV size fields at zero; write the real sizes so players open the file."""
    raw = bytearray(path.read_bytes())
    raw[4:8] = struct.pack("<I", len(raw) - 8)
    raw[40:44] = struct.pack("<I", len(raw) - 44)
    path.write_bytes(bytes(raw))


def _read(path: Path) -> np.ndarray:
    raw = path.read_bytes()[44:]
    x = np.frombuffer(raw[: len(raw) // 4 * 4], dtype="<i2").astype(np.float64).reshape(-1, 2).mean(axis=1)
    return x / 32767.0


def render(args) -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    name = args.name or f"{args.preset}_{args.profile}"
    wav = OUT / f"{name}.wav"
    cmd = [GODOT, "--headless", "--path", str(ROOT), "-s", "res://tools/diagnostics/audio_lab/render_sound.gd", "--",
           f"preset={args.preset}", f"seconds={args.seconds}", f"profile={args.profile}", f"solver={args.solver}",
           f"intake={args.intake}", f"exhaust={args.exhaust}", f"rasp={args.rasp}", f"muffler={args.muffler}", f"layers={args.layers}", f"gains={args.gains}",
           f"out={wav}"]
    if args.raw:
        cmd.append(f"raw={OUT / (name + '_raw.f32')}")
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=1500)
    if "LAB_DONE" not in result.stdout:
        print(result.stdout[-2000:], result.stderr[-2000:], sep="\n")
        sys.exit(f"render failed: {name}")
    _fix_header(wav)
    print(f"rendered {wav}")
    return wav


def metrics(path: Path) -> dict:
    x = _read(path)
    fr, t, Z = stft(x, RATE, nperseg=4096, noverlap=3072)
    S = np.abs(Z)
    total = S[fr > 40].sum() + 1e-12
    band = (fr > 40) & (fr < 3000)
    tone = fr[band][np.argmax(S[band].mean(axis=1))]
    # crackle: sharp transients above 3 kHz, counted as peaks of their envelope well above the median
    sos = butter(4, 3000, btype="highpass", fs=RATE, output="sos")
    env = np.abs(sosfiltfilt(sos, x))
    env = np.convolve(env, np.ones(64) / 64, mode="same")
    peaks, _ = find_peaks(env, height=5 * np.median(env) + 1e-9, distance=int(0.01 * RATE))
    rms = np.sqrt(np.mean(x ** 2))
    return {
        "name": path.stem,
        "seconds": len(x) / RATE,
        "rms_dbfs": 20 * np.log10(rms + 1e-12),
        "peak": float(np.abs(x).max()),
        "share_gt1k": float(S[fr > 1000].sum() / total),
        "share_1_3k": float(S[(fr > 1000) & (fr < 3000)].sum() / total),
        "tone_hz": float(tone),
        "crackle_per_s": len(peaks) / (len(x) / RATE),
    }


def print_table(rows: list) -> None:
    print(f"{'name':28s} {'rms dBFS':>9s} {'peak':>7s} {'>1k':>6s} {'1-3k':>6s} {'tone Hz':>8s} {'crackle/s':>10s}")
    for r in rows:
        print(f"{r['name']:28s} {r['rms_dbfs']:9.1f} {r['peak']:7.2f} {r['share_gt1k']:6.3f} {r['share_1_3k']:6.3f} "
              f"{r['tone_hz']:8.0f} {r['crackle_per_s']:10.1f}")


def plot(path: Path, at: float) -> Path:
    x = _read(path)
    fig, ax = plt.subplots(2, 1, figsize=(11, 8), gridspec_kw={"height_ratios": [1.3, 1]})
    f, t, S = spectrogram(x, RATE, nperseg=2048, noverlap=1536)
    ax[0].pcolormesh(t, f, 10 * np.log10(S + 1e-12), shading="auto", vmin=-110, vmax=-30, cmap="magma")
    ax[0].set_ylim(0, 4000)
    ax[0].set_ylabel("Hz")
    ax[0].set_xlabel("s")
    ax[0].set_title(f"{path.stem}: spectrogram (0-4 kHz)")
    seg = x[int(at * RATE): int((at + 0.25) * RATE)]
    ax[1].plot(np.arange(len(seg)) / RATE * 1000, seg, lw=0.8)
    ax[1].set_xlabel("ms")
    ax[1].set_ylabel("amplitude")
    ax[1].set_title(f"waveform, 250 ms at {at:.1f} s")
    plt.tight_layout()
    out = OUT / f"{path.stem}_view.png"
    plt.savefig(out, dpi=110)
    plt.close(fig)
    print(f"plotted {out}")
    return out


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("render", help="render one sound to a WAV")
    r.add_argument("--preset", default="yamaha_yzf_r1m")
    r.add_argument("--profile", default="idle", choices=["idle", "decel", "crank", "crank_dry"])
    r.add_argument("--seconds", type=float, default=6.0)
    r.add_argument("--solver", default="live", choices=["live", "offline"])
    for opt in ["intake", "exhaust", "rasp", "muffler", "layers"]:
        r.add_argument(f"--{opt}", default="on", choices=["on", "off"])
    r.add_argument("--raw", action="store_true", help="also save the raw exhaust pulses")
    r.add_argument("--gains", default="", help="layer gains: valvetrain,mechanical,driveline,turbo,knock")
    r.add_argument("--name", default="")

    s = sub.add_parser("stats", help="measure WAV files and print a table")
    s.add_argument("files", nargs="+")

    pl = sub.add_parser("plot", help="spectrogram and waveform PNG")
    pl.add_argument("file")
    pl.add_argument("--at", type=float, default=2.0)

    c = sub.add_parser("compare", help="render named variants and print their measurements")
    c.add_argument("--preset", default="yamaha_yzf_r1m")
    c.add_argument("--profile", default="idle", choices=["idle", "decel"])
    c.add_argument("--seconds", type=float, default=6.0)
    c.add_argument("--variants", default="base,exhaust_only,rasp_off,muffler_off")

    sub.add_parser("variants", help="list the named variants")

    args = p.parse_args()
    if args.cmd == "render":
        render(args)
    elif args.cmd == "stats":
        print_table([metrics(Path(f)) for f in args.files])
    elif args.cmd == "plot":
        plot(Path(args.file), args.at)
    elif args.cmd == "compare":
        rows = []
        for v in args.variants.split(","):
            if v not in VARIANTS:
                sys.exit(f"unknown variant {v}; see the variants command")
            extra = []
            for item in VARIANTS[v]:
                extra.append(item)
            ns = argparse.Namespace(preset=args.preset, profile=args.profile, seconds=args.seconds, solver="live",
                                    intake="on", exhaust="on", rasp="on", muffler="on", layers="on", raw=False, gains="",
                                    name=f"{args.preset}_{args.profile}_{v}")
            for i in range(0, len(extra), 2):
                setattr(ns, extra[i][2:], extra[i + 1])
            wav = render(ns)
            rows.append(metrics(wav))
        print_table(rows)
    elif args.cmd == "variants":
        for k, v in VARIANTS.items():
            print(f"{k:16s} {' '.join(v) if v else '(as shipped)'}")


if __name__ == "__main__":
    main()
