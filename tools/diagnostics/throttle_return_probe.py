#!/usr/bin/env python3
"""throttle_return_probe.py -- measure a throttle tube's return curve from a phone clip.

Why this exists
---------------
`THROTTLE_RETURN_SPEED` in scripts/app/main.gd is a guess ("like a return spring").
This probes a real grip so the number comes from a measurement instead of a feeling.

How it measures
---------------
A twisted throttle moves the grip's texture in one direction, so the tool:

  1. removes camera shake (FFT phase correlation, subpixel) between frames;
  2. finds the region that moved after that compensation (automatic ROI, or --roi);
  3. picks the direction the texture flows in, by projecting the ROI onto each
     candidate axis and keeping the direction whose 1-D correlation is sharpest;
  4. integrates the per-frame displacement into an angle-proportional trace;
  5. detects the release (the peak of that trace) and fits the decay that follows,
     as both an exponential (tau, seconds) and a linear rate (full travel per second,
     the same unit as THROTTLE_RETURN_SPEED);
  6. applies a confidence gate. A shaky handheld clip at 10 fps does not silently
     return a number -- it returns "not measurable" and says why.

Usage
-----
    uv run --quiet --with numpy --with pillow python tools/diagnostics/throttle_return_probe.py CLIP.mp4
    ... CLIP.mp4 --roi x0,y0,x1,y1        # crop to the grip yourself
    ... --model slide|rotate              # texture slides along the bar (default) or spins
    ... --selftest                        # synthetic clip with a known tau, checks recovery
    ... --sheet                           # write a labelled contact sheet to eyeball

Only numpy + pillow are needed; ffmpeg/ffprobe must be on PATH (ffmpeg 9 is installed here).
"""

from __future__ import annotations

import argparse
import glob
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import wave

import numpy as np
from PIL import Image, ImageDraw

MAIN_GD = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))), "scripts", "app", "main.gd")

# A frame pair is trusted only if the profiles correlate at least this well along the
# chosen axis (normalized correlation, 1.0 = identical shapes). Below it, the "motion"
# is texture noise rather than the grip.
MIN_CONFIDENCE = 0.5
# And the whole twist has to cover at least this many pixels, or subpixel shifts cannot
# be separated from sensor noise.
MIN_SPREAD_PX = 2.0


# ----------------------------------------------------------------------------- video io

def ffprobe(path: str) -> dict:
    out = subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height,r_frame_rate,nb_frames,duration",
        "-of", "json", path,
    ])
    st = json.loads(out)["streams"][0]
    num, den = st["r_frame_rate"].split("/")
    fps = float(num) / float(den) if float(den) else 0.0
    return {
        "w": int(st["width"]), "h": int(st["height"]), "fps": fps,
        "frames": int(st.get("nb_frames") or 0),
        "duration": float(st.get("duration") or 0.0),
    }


def extract_frames(path: str, outdir: str) -> list[str]:
    subprocess.check_call([
        "ffmpeg", "-y", "-v", "error", "-i", path,
        "-fps_mode", "passthrough", os.path.join(outdir, "f%05d.png"),
    ])
    return sorted(glob.glob(os.path.join(outdir, "f*.png")))


def frame_times(path: str) -> np.ndarray:
    """Presentation time of every decoded frame, in seconds.

    Deliberately NOT from r_frame_rate: WhatsApp and similar re-encoders keep a nominal
    30 fps in the header while shipping far fewer frames. A measured clip advertised
    29.92 fps and carried 22 frames across 2.2 s -- 10 fps -- which silently scales every
    fitted time by 3x. Timestamps are the only trustworthy clock.
    """
    out = subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "frame=best_effort_timestamp_time", "-of", "csv=p=0", path,
    ])
    stamps: list[float] = []
    for tok in out.decode().replace(",", " ").split():
        if tok in ("N/A", ""):
            continue
        stamps.append(float(tok))
    if len(stamps) < 2:
        return np.array([], dtype=np.float64)
    return np.sort(np.array(stamps, dtype=np.float64))


def load_gray(files: list[str], step: int = 1) -> np.ndarray:
    frames = [np.asarray(Image.open(f).convert("L").resize(
        (Image.open(f).width // step, Image.open(f).height // step)), dtype=np.float32)
        for f in files]
    return np.stack(frames)


# ----------------------------------------------------------------------------- motion

def _hann_nd(shape: tuple[int, ...]) -> np.ndarray:
    win = np.ones((1,) * len(shape), dtype=np.float32)
    for axis, n in enumerate(shape):
        h = np.hanning(n).astype(np.float32)
        win = win * h.reshape([n if a == axis else 1 for a in range(len(shape))])
    return win


def phase_shift(a: np.ndarray, b: np.ndarray,
                max_shift: int | tuple[int, ...] = 40) -> tuple[float, ...]:
    """Subpixel shift that best maps a onto b, one value per axis.

    The FFT cross-correlation peak sits at the (circular) index equal to the shift,
    so the unshifted inverse transform is used: index i means shift i when i <= n/2,
    else i - n. Searching only +-max_shift keeps camera shake from stealing the peak.
    """
    shape = a.shape
    if isinstance(max_shift, int):
        max_shift = tuple(max_shift for _ in shape)
    win = _hann_nd(shape)
    fa = np.fft.rfftn((a - a.mean()) * win)
    fb = np.fft.rfftn((b - b.mean()) * win)
    cross = fb * np.conj(fa)
    cross /= np.abs(cross) + 1e-9
    corr = np.fft.irfftn(cross, s=shape, axes=tuple(range(len(shape))))

    idx = tuple((np.arange(-ms, ms + 1) % n) for n, ms in zip(shape, max_shift))
    sub = corr[np.ix_(*idx)]
    pos = tuple(int(v) for v in np.unravel_index(int(np.argmax(sub)), sub.shape))
    shifts = [float(p - ms) for p, ms in zip(pos, max_shift)]

    # subpixel: parabola through the peak and its neighbours along each axis
    for axis, (p, ms) in enumerate(zip(pos, max_shift)):
        if 0 < p < sub.shape[axis] - 1:
            lo = list(pos)
            hi = list(pos)
            lo[axis] = p - 1
            hi[axis] = p + 1
            a0 = float(sub[tuple(lo)])
            a1 = float(sub[pos])
            a2 = float(sub[tuple(hi)])
            den = a0 - 2.0 * a1 + a2
            if abs(den) > 1e-12:
                shifts[axis] += 0.5 * (a0 - a2) / den

    peak = float(sub[pos])
    sharp = peak / (float(np.median(np.abs(sub))) + 1e-9)
    return (*shifts, sharp)


def shift_image(a: np.ndarray, dy: float, dx: float) -> np.ndarray:
    """Bilinear shift of a by (dy, dx) with edge clamping."""
    h, w = a.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    ys = np.clip(yy - dy, 0, h - 1.001)
    xs = np.clip(xx - dx, 0, w - 1.001)
    y0 = ys.astype(np.int32)
    x0 = xs.astype(np.int32)
    fy = ys - y0
    fx = xs - x0
    y1 = np.minimum(y0 + 1, h - 1)
    x1 = np.minimum(x0 + 1, w - 1)
    return (a[y0, x0] * (1 - fx) * (1 - fy) + a[y0, x1] * fx * (1 - fy)
            + a[y1, x0] * (1 - fx) * fy + a[y1, x1] * fx * fy)


def auto_roi(residuals: list[np.ndarray], grid: tuple[int, int] = (8, 6)) -> tuple[int, int, int, int]:
    """Bounding box of the blocks that keep moving after camera shake is removed."""
    acc = np.mean(np.stack(residuals), axis=0)
    h, w = acc.shape
    gy, gx = grid
    bh, bw = h // gy, w // gx
    cells = np.zeros((gy, gx), dtype=np.float32)
    for y in range(gy):
        for x in range(gx):
            cells[y, x] = acc[y * bh:(y + 1) * bh, x * bw:(x + 1) * bw].mean()
    cells /= cells.max() + 1e-9
    ys, xs = np.where(cells > 0.55)
    if len(ys) == 0:
        return 0, 0, w, h
    return (int(xs.min() * bw), int(ys.min() * bh),
            int((xs.max() + 1) * bw), int((ys.max() + 1) * bh))


def project_axis(img: np.ndarray, angle_deg: float) -> np.ndarray:
    """Sum the image along one axis, leaving a 1-D profile that shifts with the texture."""
    rad = math.radians(angle_deg)
    c, s = abs(math.cos(rad)), abs(math.sin(rad))
    h, w = img.shape
    dh = max(1, int(round(h * c + w * s)))
    # nearest-neighbour rotation is enough: projections are averages, not edges
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    xr = (xx - w / 2) * math.cos(rad) + (yy - h / 2) * math.sin(rad) + dh / 2
    xi = np.clip(xr.astype(np.int32), 0, dh - 1)
    prof = np.zeros(dh, dtype=np.float32)
    np.add.at(prof, xi.ravel(), img.ravel())
    cnt = np.bincount(xi.ravel(), minlength=dh).astype(np.float32)
    return prof / np.maximum(cnt, 1.0)


def correlate_1d(a: np.ndarray, b: np.ndarray, max_shift: int) -> tuple[float, float]:
    """Shift of b relative to a along a profile, plus the normalized correlation.

    Deliberately NOT phase-whitened: whitening divides by a near-zero spectrum on a
    flat profile and manufactures a delta peak, which is how a wrong axis wins.
    """
    if a.size < 8 or b.size < 8:
        return 0.0, 0.0
    am = a - a.mean()
    bm = b - b.mean()
    na = float(np.sqrt((am * am).sum()))
    nb = float(np.sqrt((bm * bm).sum()))
    if na < 1e-6 or nb < 1e-6:  # featureless profile: no direction information
        return 0.0, 0.0
    corr = np.fft.irfft(np.fft.rfft(bm) * np.conj(np.fft.rfft(am)), n=a.size) / (na * nb)
    idx = np.arange(-max_shift, max_shift + 1) % a.size
    sub = corr[idx]
    p = int(np.argmax(sub))
    shift = float(p - max_shift)
    if 0 < p < sub.size - 1:
        lo, mid, hi = float(sub[p - 1]), float(sub[p]), float(sub[p + 1])
        den = lo - 2.0 * mid + hi
        if abs(den) > 1e-12:
            shift += 0.5 * (lo - hi) / den
    return shift, float(sub[p])


def trace_direction(pairs: list[tuple[np.ndarray, np.ndarray]]) -> tuple[float, list[float], float]:
    """Pick the direction the texture actually flows in, then shift along it per pair.

    The winner is the axis with the largest *cumulative* displacement, not the sharpest
    single peak: random noise wanders back and forth and cancels, real twist accumulates.
    """
    best_angle, best_range, best_shifts, best_corr = 0.0, 0.0, [], 0.0
    for ang in np.arange(0.0, 180.0, 10.0):
        shifts, corrs = [], []
        for a, b in pairs:
            pa, pb = project_axis(a, float(ang)), project_axis(b, float(ang))
            ms = max(4, min(pa.size // 3, 40))
            s, c = correlate_1d(pa, pb, ms)
            shifts.append(s)
            corrs.append(c)
        cum = np.cumsum(shifts)
        spread = float(cum.max() - cum.min()) if cum.size else 0.0
        if spread > best_range:
            best_angle, best_range = float(ang), spread
            best_shifts = shifts
            best_corr = float(np.median(corrs))
    return best_angle, best_shifts, best_corr


def rotate_pair(a: np.ndarray, b: np.ndarray, max_deg: float = 10.0) -> tuple[float, float]:
    """Best small in-plane rotation (deg) mapping a onto b, with its sharpness.

    Used for end-on footage: the twist shows up as a spin of the grip's pattern
    about its own axis instead of a slide along the bar.
    """
    h, w = a.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cy, cx = (h - 1) / 2.0, (w - 1) / 2.0
    still = float(np.abs(b - a).mean())
    best = (0.0, 0.0)
    for deg in np.arange(-max_deg, max_deg + 0.01, 2.0):
        rad = math.radians(float(deg))
        c, s = math.cos(rad), math.sin(rad)
        xr = (xx - cx) * c + (yy - cy) * s + cx
        yr = -(xx - cx) * s + (yy - cy) * c + cy
        x0 = np.clip(xr.astype(np.int32), 0, w - 1)
        y0 = np.clip(yr.astype(np.int32), 0, h - 1)
        sad = float(np.abs(b - a[y0, x0])[10:-10, 10:-10].mean())
        if still / max(sad, 1e-6) > best[1]:
            best = (float(deg), still / max(sad, 1e-6))
    return best


# ----------------------------------------------------------------------------- fitting

def _crossing_time(t: np.ndarray, v: np.ndarray, i: int, thr: float,
                   rising: bool) -> float:
    """Sub-sample time at which v crosses thr between samples i and i+1."""
    v0, v1 = float(v[i]), float(v[i + 1])
    if (v1 - v0) == 0.0:
        return float(t[i])
    frac = (thr - v0) / (v1 - v0)
    frac = min(max(frac, 0.0), 1.0)
    return float(t[i] + frac * (t[i + 1] - t[i]))


def fit_return(times: np.ndarray, trace: np.ndarray) -> dict:
    """Return duration in seconds: the snap -> back at rest.

    Two things this deliberately does not do:

    * It does not look for the release at the extreme of the trace. The trace is a
      cumulative sum, so a repeating texture (grip ribs, a patterned glove) makes the
      integrated position drift past its start; on a real clip the trace settled at
      -11 px instead of 0, which put the "release" at the very end of the clip. The
      release is taken as the *fastest motion in the clip* instead -- letting go is
      always the sharpest event, the pull being slow by comparison.
    * It does not take rest from the position either, for the same drift reason. Rest is
      the first interval after the snap whose speed stays under the noise floor, and the
      rest level is whatever the trace settled at, wherever that is.
    """
    if trace.size < 6:
        return {"ok": False, "reason": "clip too short"}

    dt = np.diff(times)
    speed = np.abs(np.diff(trace)) / np.maximum(dt, 1e-6)
    if speed.size < 4:
        return {"ok": False, "reason": "clip too short"}

    i_snap = int(np.argmax(speed))
    if i_snap >= speed.size - 1:
        return {"ok": False, "reason": "the release is at the end of the clip; keep filming after it"}
    t_release = float(times[i_snap])

    # noise floor from the quietest quarter of the clip (there is always some idle time),
    # and the snap itself, so the threshold scales with how hard the grip was let go
    quiet = float(np.median(np.sort(speed)[:max(3, speed.size // 4)]))
    peak = float(speed[i_snap])
    thr = max(quiet * 3.0, 0.05 * peak)

    rest_i = None
    for i in range(i_snap, speed.size):
        if speed[i] < thr and (i + 1 >= speed.size or speed[i + 1] < thr):
            rest_i = i
            break
    if rest_i is None:
        return {"ok": False, "reason": "the grip never comes to rest inside the clip",
                "t_release": round(t_release, 3), "peak_speed_px_s": round(peak, 1)}

    if speed[rest_i] >= thr or rest_i == i_snap:
        t_rest = float(times[rest_i])
    else:
        t_rest = _crossing_time(times, speed, rest_i - 1, thr, rising=False)

    duration = max(0.0, t_rest - t_release)
    frame = float(np.median(dt)) if dt.size else 0.0

    # shape of the decay, for reference: exponential tau over the snap->rest window
    rest_level = float(np.median(trace[rest_i:]))
    window = np.abs(trace[i_snap:] - rest_level)
    t_window = times[i_snap:] - t_release
    full = float(window.max()) if window.size else 0.0
    tau = None
    if window.size >= 4 and full > 0:
        taus = np.geomspace(0.002, 5.0, 4000)
        sse = np.array([float(((window - full * np.exp(-t_window / tau)) ** 2).sum())
                        for tau in taus])
        if sse.min() < 0.15 * float((window ** 2).sum()):
            tau = round(float(taus[int(np.argmin(sse))]), 4)

    return {
        "ok": True,
        "return_duration_s": round(duration, 3),
        "return_duration_range_s": [round(max(0.0, duration - frame), 3),
                                    round(duration + frame, 3)],
        "t_release": round(t_release, 3),
        "t_rest": round(t_rest, 3),
        "frame_period_s": round(frame, 4),
        "samples_in_return": int(rest_i - i_snap + 1),
        "peak_speed_px_s": round(peak, 1),
        "noise_px_s": round(quiet, 1),
        "tau_s": tau,
        "full_scale_px": round(full, 2),
    }


def extract_audio(path: str, out_wav: str) -> str:
    subprocess.check_call(["ffmpeg", "-y", "-v", "error", "-i", path,
                           "-vn", "-ac", "1", out_wav])
    return out_wav


def audio_impact_time(wav: str, search_from: float = 0.0) -> dict:
    """Time of the loudest mechanical transient: the clank of the throttle hitting shut.

    The impact is the only sharp event in a clip of a grip worked by hand, and it resolves
    to well under a millisecond where the video resolves 100 ms.

    The noise floor is a low percentile of the *audible* 5 ms windows. A plain RMS of the
    opening samples fails here: clips that came through WhatsApp start with digital
    silence, which makes the ambient zero and latches the detector onto the first
    non-silent sample instead of the impact (measured: 0.347 s instead of 0.978 s).
    """
    w = wave.open(wav, "rb")
    sr, n = w.getframerate(), w.getnframes()
    x = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32) / 32768.0
    if w.getnchannels() == 2:
        x = x.reshape(-1, 2).mean(axis=1)
    if x.size < sr // 10:
        return {"ok": False, "reason": "audio track is empty"}

    hop = max(1, int(sr * 0.005))
    env = np.array([np.sqrt((x[k:k + hop] ** 2).mean())
                    for k in range(0, x.size - hop, hop)])
    if env.size < 10:
        return {"ok": False, "reason": "audio track too short"}
    audible = env[env > 1e-5]
    if audible.size == 0:
        return {"ok": False, "reason": "audio track is silent"}
    amb = float(np.percentile(audible, 20))
    peak = float(env.max())
    thr = max(amb * 8.0, peak * 0.02)

    from_win = max(0, int(search_from / 0.005))
    hits = np.where(env[from_win:] > thr)[0]
    if hits.size == 0:
        return {"ok": False, "reason": "no impact loud enough above the ambient noise"}
    i_win = from_win + int(hits[0])

    # refine to the sample where the impact actually starts
    lo = max(0, (i_win - 1) * hop)
    hi = min(x.size, (i_win + 1) * hop)
    seg = np.abs(x[lo:hi])
    over = np.where(seg > amb * 6.0)[0]
    i_on = lo + (int(over[0]) if over.size else 0)
    i_pk = int(np.argmax(np.abs(x[lo:hi]))) + lo

    return {"ok": True,
            "t_impact_s": round(i_on / sr, 4),
            "peak_s": round(i_pk / sr, 4),
            "ambient_rms": round(amb, 5),
            "peak_amplitude": round(float(np.abs(x).max()), 3),
            "sr": sr}


def clank_duration(path: str, release_s: float, search_from: float = 0.0) -> dict:
    """Return duration from a release marker to the audio clank that marks full closed."""
    tmp = tempfile.mkdtemp(prefix="throttle_clank_")
    try:
        wav = extract_audio(path, os.path.join(tmp, "a.wav"))
        imp = audio_impact_time(wav, search_from)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if not imp.get("ok"):
        return {"verdict": f"NOT MEASURABLE: {imp.get('reason')}", "ok": False}

    dur = imp["t_impact_s"] - release_s
    if dur <= 0:
        return {"verdict": ("NOT MEASURABLE: the clank precedes the release marker. The audio "
                            "and video clocks of this container are offset; pass --release-s "
                            "in the audio clock instead."),
                "ok": False, "t_impact_s": imp["t_impact_s"], "release_s": release_s}
    return {
        "ok": True,
        "method": "audio clank against a release marker",
        "release_s": round(release_s, 3),
        "t_impact_s": imp["t_impact_s"],
        "return_duration_s": round(dur, 4),
        "return_duration_ms": round(dur * 1000.0, 1),
        "peak_s": imp["peak_s"],
        "ambient_rms": imp["ambient_rms"],
        "verdict": (f"MEASURED: throttle return duration {dur * 1000.0:.0f} ms "
                    f"(release {release_s:.3f}s -> clank {imp['t_impact_s']:.3f}s)"),
    }


def sim_constant() -> float | None:
    """THROTTLE_RETURN_SPEED from main.gd, for comparison (full travel per second)."""
    try:
        with open(MAIN_GD, encoding="utf-8") as fh:
            m = re.search(r"const\s+THROTTLE_RETURN_SPEED\s*:=\s*([0-9.]+)", fh.read())
        return float(m.group(1)) if m else None
    except OSError:
        return None


# ----------------------------------------------------------------------------- driver

def analyse(path: str, roi: tuple[int, int, int, int] | None, model: str,
            step: int = 2, sheet: bool = False) -> dict:
    meta = ffprobe(path)
    tmp = tempfile.mkdtemp(prefix="throttle_probe_")
    try:
        files = extract_frames(path, tmp)
        frames = load_gray(files, step)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    n = len(frames)
    stamps = frame_times(path)
    if stamps.size == n:
        times = stamps - stamps[0]
        deltas = np.diff(stamps)
        deltas = deltas[deltas > 1e-6]
        fps_eff = 1.0 / float(np.median(deltas)) if deltas.size else meta["fps"]
    else:
        times = np.arange(n) / meta["fps"] if meta["fps"] > 0 else np.arange(n, dtype=float)
        fps_eff = meta["fps"]

    # 1. camera shake out, 2. crop to what still moves
    residuals, align = [], []
    for i in range(n - 1):
        dy, dx, _ = phase_shift(frames[i], frames[i + 1])
        aligned = shift_image(frames[i + 1], dy, dx)
        pad = max(8, min(frames[i].shape) // 8)
        residuals.append(np.abs(frames[i] - aligned)[pad:-pad, pad:-pad])
        align.append((dy, dx))
    if roi is None:
        x0, y0, x1, y1 = auto_roi(residuals)
        x1, y1 = min(x1, frames.shape[2]), min(y1, frames.shape[1])
    else:
        x0, y0, x1, y1 = (v // step for v in roi)
    crop = frames[:, y0:y1, x0:x1]
    if crop.shape[1] < 12 or crop.shape[2] < 12:
        raise SystemExit("ROI too small after downsampling; pass a larger --roi")

    # 3. track the texture
    pairs = [(crop[i], crop[i + 1]) for i in range(n - 1)]
    angle, shifts, gain = trace_direction(pairs)
    rot = None
    if model == "rotate":
        rots = [rotate_pair(a, b) for a, b in pairs]
        rot = {"per_pair_deg": [r[0] for r in rots],
               "gain": float(np.median([r[1] for r in rots]))}

    trace = np.concatenate([[0.0], np.cumsum(shifts)])
    fit = fit_return(times, trace)
    shake = float(np.mean([abs(d) for d, _ in align] + [abs(d) for _, d in align]))
    sim = sim_constant()

    result = {
        "clip": os.path.basename(path), "size": [meta["w"], meta["h"]],
        "fps": round(meta["fps"], 2), "fps_effective": round(fps_eff, 2),
        "frames": n, "duration_s": round(float(times[-1] - times[0]), 3),
        "roi": [int(x0 * step), int(y0 * step), int(x1 * step), int(y1 * step)],
        "flow_deg": angle, "confidence": round(gain, 2),
        "camera_shake_px": round(shake, 2), "model": model, "rotation": rot,
        "trace_px": [round(float(v), 2) for v in trace],
        "times_s": [round(float(t), 3) for t in times],
        "fit": fit, "sim_return_speed": sim,
    }

    # verdict: the headline answer is a duration in seconds; gate what the sampling
    # cannot support instead of printing a confident number from three samples
    spread = float(np.max(trace) - np.min(trace))
    result["spread_px"] = round(spread, 2)
    result["frame_period_s"] = round(1.0 / fps_eff, 3) if fps_eff > 0 else None
    dur = fit.get("return_duration_s")
    if dur is not None:
        result["return_duration_s"] = dur
        result["return_duration_range_s"] = fit["return_duration_range_s"]

    if gain < MIN_CONFIDENCE:
        result["verdict"] = ("NOT MEASURABLE: the grip's texture does not track from frame "
                             f"to frame (correlation {gain:.2f} < {MIN_CONFIDENCE}). The clip "
                             "is too shaky, too small, or the grip fills too little of the frame.")
    elif spread < MIN_SPREAD_PX:
        result["verdict"] = (f"NOT MEASURABLE: the whole twist covers only {spread:.1f} px "
                             f"(< {MIN_SPREAD_PX}); that is inside the noise floor. Get closer "
                             "or zoom in so the grip fills more of the frame.")
    elif not fit.get("ok"):
        result["verdict"] = f"NOT MEASURABLE: {fit.get('reason')}"
    elif fps_eff < 25:
        result["verdict"] = (
            f"COARSE: return duration {dur:.2f} s, but only "
            f"{fit['samples_in_return']} samples across it at {fps_eff:.0f} fps "
            f"(+-{fit['frame_period_s'] * 1000:.0f} ms). Treat it as an estimate; shoot at "
            "120 fps for the curve.")
    else:
        result["verdict"] = (
            f"MEASURED: throttle return duration {dur:.3f} s "
            f"({fit['samples_in_return']} samples, +-{fit['frame_period_s'] * 1000:.1f} ms)")
        if fit.get("tau_s"):
            result["note"] = (f"exponential tail, tau = {fit['tau_s']} s. "
                              f"THROTTLE_RETURN_SPEED is {sim} full-travel/s "
                              f"(= {1.0 / sim:.2f} s here)" if sim else
                              f"exponential tail, tau = {fit['tau_s']} s")

    if sheet:
        img = Image.fromarray(frames[0].astype(np.uint8)).convert("RGB")
        d = ImageDraw.Draw(img)
        d.rectangle([x0, y0, x1, y1], outline=(255, 60, 60), width=2)
        out = os.path.splitext(path)[0] + "_roi_sheet.png"
        cols = 6
        tw, th = (x1 - x0), (y1 - y0)
        rowsn = math.ceil(n / cols)
        s = Image.new("RGB", (cols * tw, rowsn * (th + 14)), (16, 16, 20))
        sd = ImageDraw.Draw(s)
        for i in range(n):
            t = Image.fromarray(frames[i, y0:y1, x0:x1].astype(np.uint8)).convert("RGB")
            x, y = (i % cols) * tw, (i // cols) * (th + 14)
            s.paste(t.resize((tw, th)), (x, y))
            sd.text((x + 2, y + th + 1), f"{i} {times[i]:.2f}s", fill=(230, 230, 230))
        s.save(out)
        result["sheet"] = out

    return result


# ----------------------------------------------------------------------------- selftest

def selftest() -> int:
    """Synthesise a clip with a known return time and check the probe recovers it."""
    tmp = tempfile.mkdtemp(prefix="throttle_selftest_")
    try:
        fps, dur = 120, 2.0
        n = int(fps * dur)
        w, h = 320, 240
        rng = np.random.default_rng(7)
        # a textured plate that slides left/right: the grip twisted on a bar
        tex = (rng.random((h + 200, w + 400)) * 90 + 60).astype(np.float32)
        for k in range(0, tex.shape[1], 17):  # vertical stripes to make flow obvious
            tex[:, k:k + 2] = 30.0
        tau_true = 0.18  # s, exponential return
        peak_px = 60.0
        pull_t = 0.9
        pos = []
        for i in range(n):
            t = i / fps
            if t < pull_t:
                x = peak_px * (t / pull_t)
            else:
                x = peak_px * math.exp(-(t - pull_t) / tau_true)
            pos.append(x)
        out = os.path.join(tmp, "synth.mp4")
        proc = subprocess.Popen([
            "ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "gray",
            "-s", f"{w}x{h}", "-r", str(fps), "-i", "-",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", out,
        ], stdin=subprocess.PIPE)
        assert proc.stdin is not None
        for i in range(n):
            off = 100 + pos[i]
            # subpixel sampling, so the ground truth is not stair-stepped by rounding
            x0i = int(math.floor(off))
            frac = off - x0i
            left = tex[60:60 + h, x0i:x0i + w]
            right = tex[60:60 + h, x0i + 1:x0i + w + 1]
            frame = left * (1.0 - frac) + right * frac
            noise = rng.normal(0, 2.0, frame.shape)
            proc.stdin.write(np.clip(frame + noise, 0, 255).astype(np.uint8).tobytes())
        proc.stdin.close()
        proc.wait()

        res = analyse(out, None, "slide", step=1)
        fit = res["fit"]
        print(json.dumps({k: res[k] for k in ("fps_effective", "confidence", "verdict")},
                         indent=1))
        print("fit:", json.dumps(fit, indent=1))
        if not fit.get("ok"):
            print("SELFTEST FAIL: no fit")
            return 1
        got = fit["return_duration_s"]
        # an exponential return is "done" at 3 tau (5% of peak speed), i.e. 0.54 s here
        want = 3.0 * tau_true
        err = abs(got - want) / want
        print(f"\ntrue return duration (3*tau) = {want:.3f}s   measured = {got}s   "
              f"error = {err * 100:.1f}%")
        print(f"range = {fit['return_duration_range_s']}s   tau fit = {fit.get('tau_s')}s")
        ok = err < 0.20
        print("SELFTEST PASS" if ok else "SELFTEST FAIL")
        return 0 if ok else 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("clip", nargs="?", help="video file to measure")
    ap.add_argument("--roi", help="x0,y0,x1,y1 crop around the grip, in source pixels")
    ap.add_argument("--model", choices=("slide", "rotate"), default="slide",
                    help="how the twist shows up: texture slides along the bar (default) "
                         "or spins about its axis (end-on footage)")
    ap.add_argument("--step", type=int, default=2, help="downsample factor (default 2)")
    ap.add_argument("--sheet", action="store_true", help="write a labelled contact sheet")
    ap.add_argument("--json", action="store_true", help="print only the JSON result")
    ap.add_argument("--selftest", action="store_true", help="verify against a known tau")
    ap.add_argument("--clank", action="store_true",
                    help="use the audio impact (throttle hitting shut) as the end of the "
                         "return; needs --release-frame or --release-s")
    ap.add_argument("--release-frame", type=int,
                    help="index of the frame where the hand lets go (0-based)")
    ap.add_argument("--release-s", type=float,
                    help="release time in seconds, if you know it in the audio clock")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()
    if not args.clip:
        ap.error("a clip is required unless --selftest is used")

    if args.clank:
        rel = args.release_s
        if rel is None and args.release_frame is not None:
            stamps = frame_times(args.clip)
            if args.release_frame >= stamps.size:
                ap.error(f"clip has {stamps.size} frames; --release-frame out of range")
            rel = float(stamps[args.release_frame])
        if rel is None:
            ap.error("--clank needs --release-frame N or --release-s T")
        res = clank_duration(args.clip, rel)
        print(json.dumps(res, indent=1))
        return 0 if res.get("ok") else 2

    roi = tuple(int(v) for v in args.roi.split(",")) if args.roi else None
    res = analyse(args.clip, roi, args.model, step=args.step, sheet=args.sheet)
    print(json.dumps(res, indent=1) if not args.json else json.dumps(res))
    return 0 if res["verdict"] == "MEASURED" else 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
