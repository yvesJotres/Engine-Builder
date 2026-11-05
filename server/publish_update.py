"""Exports the game patch from the current code and publishes it.

Usage:  python publish_update.py                       (publish a final Android patch: players get it)
        python publish_update.py --platform windows     (the Windows channel)
        python publish_update.py --draft                (store it, but players do not get it yet)
        python publish_update.py --promote              (make the stored draft final, so players get it)

Each platform has its own patch channel, because the exported data differs per platform (textures are
stored in the formats each device uses). Most updates are small deltas: only the files that changed since
the base patch are packed (Godot's --export-patch against the base pack). A full base patch is published
again when a delta would be large, or after MAX_DELTAS deltas, so the base never drifts too far from the code.

A draft is a delta kept in patches/<platform>/draft.pck with its own signature. The app only offers a
delta marked final, so a draft is invisible to players until --promote copies it to delta.pck.

The server file layout (server/patches for Android, server/patches/windows for Windows):
  game.pck     the full base patch (served to devices that need everything)
  version.json the base's description, plus "delta" (the newest final delta) and "draft" (a waiting draft)
  delta.pck    the newest final delta
  draft.pck    the draft delta, when there is one
"""
import argparse
import json
import os
import shutil
import subprocess
import sys

from patch_common import sha256, sign

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GODOT = r"D:\Program Files (x86)\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
ENGINE = "4.7.2"
PRESETS = {"android": "Android", "windows": "Windows Desktop"}
REBASE_RATIO = 0.6  # a delta bigger than this share of the full patch makes a new full base instead
MAX_DELTAS = 15  # after this many deltas, a new full base is published

# Set by use_platform() from --platform; the paths below depend on it
platform = "android"
PATCH_DIR = ""
BASE = ""
DELTA = ""
DRAFT = ""
VERSION_FILE = ""
FULL_EXPORT = ""
DELTA_EXPORT = ""


def use_platform(name: str) -> None:
    global platform, PATCH_DIR, BASE, DELTA, DRAFT, VERSION_FILE, FULL_EXPORT, DELTA_EXPORT
    platform = name
    PATCH_DIR = os.path.join(HERE, "patches") if name == "android" else os.path.join(HERE, "patches", name)
    BASE = os.path.join(PATCH_DIR, "game.pck")
    DELTA = os.path.join(PATCH_DIR, "delta.pck")
    DRAFT = os.path.join(PATCH_DIR, "draft.pck")
    VERSION_FILE = os.path.join(PATCH_DIR, "version.json")
    FULL_EXPORT = os.path.join(ROOT, "build", "patch", name, "game.pck")
    DELTA_EXPORT = os.path.join(ROOT, "build", "patch", name, "delta.pck")
    os.makedirs(os.path.dirname(FULL_EXPORT), exist_ok=True)
    os.makedirs(PATCH_DIR, exist_ok=True)


def read_info():
    if not os.path.exists(VERSION_FILE):
        return None
    with open(VERSION_FILE, encoding="utf-8") as f:
        return json.load(f)


def write_info(info):
    with open(VERSION_FILE, "w", encoding="utf-8") as f:
        json.dump(info, f, indent=2)


def export_full():
    export = subprocess.run([GODOT, "--headless", "--path", ROOT, "--export-pack", PRESETS[platform], FULL_EXPORT],
                            capture_output=True, text=True)
    return export.returncode == 0 and os.path.exists(FULL_EXPORT)


def export_delta(base):
    if os.path.exists(DELTA_EXPORT):
        os.remove(DELTA_EXPORT)
    export = subprocess.run([GODOT, "--headless", "--path", ROOT, "--export-patch", PRESETS[platform], DELTA_EXPORT,
                             "--patches", base], capture_output=True, text=True)
    return export.returncode == 0 and os.path.exists(DELTA_EXPORT)


def publish_full(version):
    publish = subprocess.run([sys.executable, os.path.join(HERE, "publish_patch.py"), FULL_EXPORT,
                              "--version", str(version), "--engine", ENGINE, "--final", "--platform", platform],
                             capture_output=True, text=True)
    if publish.returncode != 0:
        print(publish.stdout.strip(), publish.stderr.strip())
        return False
    if os.path.exists(DELTA):
        os.remove(DELTA)
    if os.path.exists(DRAFT):
        os.remove(DRAFT)
    info = read_info()
    info.pop("delta", None)
    info.pop("draft", None)
    info["delta_count"] = 0
    write_info(info)
    print("Published full %s patch version %d (%d bytes)" % (platform, version, info["size"]))
    return True


def promote() -> int:
    info = read_info()
    draft = info.get("draft") if info else None
    if not draft:
        print("No draft waiting for %s. Publish one with --draft first." % platform)
        return 1
    if int(draft["base_version"]) != int(info["version"]):
        print("The draft was made for base %d, but the base is now %d. Publish the draft again."
              % (int(draft["base_version"]), int(info["version"])))
        return 1
    shutil.copyfile(DRAFT, DELTA)
    promoted = dict(draft, final=True)
    info["delta"] = promoted
    info["delta_count"] = int(info.get("delta_count", 0)) + 1
    info.pop("draft", None)
    os.remove(DRAFT)
    write_info(info)
    print("Promoted %s delta %d on base %d: players are offered it now" % (
        platform, promoted["version"], promoted["base_version"]))
    return 0


GATE_TESTS = ["test_engine", "clutch_stability_test", "touch_controls_test", "spark_check", "ir_check"]


def run_tests() -> bool:
    """Runs every asserting test and the server's own tests. A failure stops the publish."""
    for name in GATE_TESTS:
        print("test gate: %s ..." % name, flush=True)
        run = subprocess.run([GODOT, "--headless", "--path", ROOT, "-s", "res://tests/%s.gd" % name],
                             capture_output=True, text=True, timeout=1200)
        if run.returncode != 0:
            lines = [l for l in run.stdout.splitlines() if "FAIL" in l or "ERROR" in l][:10]
            print("TEST GATE FAILED: %s (exit code %d)" % (name, run.returncode))
            for line in lines:
                print("  " + line)
            return False
    print("test gate: server tests ...", flush=True)
    run = subprocess.run([sys.executable, "-m", "unittest", "test_patch_server"], cwd=HERE, capture_output=True, text=True,
                         timeout=600)
    if run.returncode != 0:
        print("TEST GATE FAILED: test_patch_server")
        print(run.stderr[-1500:])
        return False
    print("test gate: all passed")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=sorted(PRESETS), default="android")
    parser.add_argument("--rebase", action="store_true", help="publish a new signed full base instead of a delta")
    parser.add_argument("--draft", action="store_true", help="store the patch as a draft: players are not offered it")
    parser.add_argument("--promote", action="store_true", help="make the waiting draft final, so players are offered it")
    parser.add_argument("--skip-tests", action="store_true", help="publish without the test gate (emergency only)")
    args = parser.parse_args()
    use_platform(args.platform)
    if args.promote:
        return promote()

    if not args.skip_tests and not run_tests():
        print("Nothing was published.")
        return 1
    if not export_full():
        print("The full %s export failed." % platform)
        return 1
    info = read_info()
    numbers = [0] if info is None else [int(info["version"]), int((info.get("delta") or {}).get("version", 0)),
                                        int((info.get("draft") or {}).get("version", 0))]
    version = max(numbers) + 1
    if info is None or not os.path.exists(BASE) or args.rebase:
        if args.draft:
            print("A draft must be a delta on the current base. Publish a full base first, without --draft.")
            return 1
        return 0 if publish_full(version) else 1
    base_version = int(info["version"])
    if not export_delta(BASE):
        print("The delta export failed; publishing a full patch instead.")
        if args.draft:
            return 1
        return 0 if publish_full(version) else 1
    delta_size = os.path.getsize(DELTA_EXPORT)
    full_size = os.path.getsize(FULL_EXPORT)
    deltas = int(info.get("delta_count", 0))
    if deltas >= MAX_DELTAS or delta_size > REBASE_RATIO * full_size:
        if args.draft:
            print("This change is too big for a delta. Publish it as a full base instead, without --draft.")
            return 1
        return 0 if publish_full(version) else 1
    if args.draft:
        shutil.copyfile(DELTA_EXPORT, DRAFT)
        info["draft"] = {"version": version, "base_version": base_version, "sha256": sha256(DRAFT),
                         "size": delta_size, "final": False, "signature": sign(DRAFT)}
        write_info(info)
        print("Stored %s draft %d on base %d (%d bytes). Test it, then run --promote." % (
            platform, version, base_version, delta_size))
        return 0
    shutil.copyfile(DELTA_EXPORT, DELTA)
    info["delta"] = {"version": version, "base_version": base_version, "sha256": sha256(DELTA),
                     "size": delta_size, "final": True, "signature": sign(DELTA)}
    info["delta_count"] = deltas + 1
    info.pop("draft", None)
    write_info(info)
    print("Published delta %s patch version %d on base %d (%d bytes instead of %d)" % (
        platform, version, base_version, delta_size, full_size))
    return 0


if __name__ == "__main__":
    sys.exit(main())
