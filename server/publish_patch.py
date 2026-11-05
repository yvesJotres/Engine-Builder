"""Publishes a game patch (a Godot .pck) for the server to hand out to the app.

Usage:  python publish_patch.py ../build/patch/game.pck --version 2 --engine 4.7.2 --final

--final marks the patch as finished: the apps offer it to players. Without it, the patch is a draft and
the apps ignore it.

The version must go up every time. The app downloads a patch only when its version is higher than the
one it already has. Restart server.py after publishing if it was already running (it reads the files each
time, so a restart is not needed; it is just a safe habit).
"""
import argparse
import json
import os
import shutil

from patch_common import sha256, sign

HERE = os.path.dirname(os.path.abspath(__file__))
PATCH_DIR = os.path.join(HERE, "patches")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pck")
    parser.add_argument("--version", type=int, required=True)
    parser.add_argument("--engine", required=True, help="the Godot version the game was exported with, e.g. 4.7.2")
    parser.add_argument("--final", action="store_true", help="mark the patch as finished, so the apps offer it")
    parser.add_argument("--platform", choices=["android", "windows"], default="android",
                        help="which app the patch is for; each platform has its own patch channel")
    args = parser.parse_args()

    folder = PATCH_DIR if args.platform == "android" else os.path.join(PATCH_DIR, args.platform)
    os.makedirs(folder, exist_ok=True)
    destination = os.path.join(folder, "game.pck")
    shutil.copyfile(args.pck, destination)
    digest = sha256(destination)
    info = {"version": args.version, "sha256": digest, "size": os.path.getsize(destination), "engine": args.engine,
            "final": args.final, "signature": sign(destination)}
    with open(os.path.join(folder, "version.json"), "w", encoding="utf-8") as f:
        json.dump(info, f, indent=2)
    state = "final" if args.final else "draft"
    print("Published %s %s patch version %d (%d bytes, sha256 %s)" % (state, args.platform, args.version, info["size"], digest))


if __name__ == "__main__":
    main()
