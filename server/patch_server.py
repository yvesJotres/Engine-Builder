"""Engine Builder patch server, run on your PC or a VPS.

Hands the game's patches to the app. It serves only what publish_update.py and publish_patch.py put in patches/.
The app checks each patch's signature against the public key in scripts/updates/patcher.gd, so a copy of this
server cannot publish a patch the app accepts. Drafts are never served.

Start it with:  python patch_server.py --port 8799 --secret YOUR_SECRET   (8799 is its own port; Flatframe uses 8787 and 8788)
(or set the ENGINE_BUILDER_SECRET environment variable). It refuses to start without a secret; --open is for local tests.
Endpoints (GET):
  /health                              public and secret-free: {ok, uptime_seconds, patches}
  /patch/library                       engine library (presets) - public, no secret needed
  /patch[/android|/windows]/info       version.json of the channel, without the draft (404 when nothing is published)
  /patch[/android|/windows]/game.pck   the full base patch
  /patch[/android|/windows]/delta.pck  the newest final delta
Every other request needs the header  X-Engine-Builder-Secret: <secret>.
"""
import argparse
import hmac
import json
import os
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.environ.get("ENGINE_BUILDER_DATA") or os.path.dirname(os.path.abspath(__file__))
PATCH_DIR = os.path.join(HERE, "patches")
LIBRARY_DIR = os.path.join(HERE, "library")
PATCH_ROUTE = re.compile(r"^/patch(?:/(android|windows))?/(info|game\.pck|delta\.pck)$")
LIBRARY_ROUTE = re.compile(r"^/patch/library$")
STARTED = time.time()
SECRET = ""

# Library cache
_LIBRARY_CACHE = None
_LIBRARY_MTIME = 0


def patch_dir(platform: str) -> str:
    # The Android patches sit in patches/ and the Windows ones in patches/windows/, as publish_update.py writes them
    return PATCH_DIR if platform == "android" else os.path.join(PATCH_DIR, platform)


def read_patch_info(platform: str):
    """The published base patch's version.json, or None when nothing is published for the platform."""
    folder = patch_dir(platform)
    path = os.path.join(folder, "version.json")
    if not os.path.exists(path) or not os.path.exists(os.path.join(folder, "game.pck")):
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def read_library():
    """The engine library (presets) from server/library/*.json files."""
    global _LIBRARY_CACHE, _LIBRARY_MTIME
    if not os.path.isdir(LIBRARY_DIR):
        return {}
    
    # Check mtime of directory contents
    dir_mtime = 0
    for fname in os.listdir(LIBRARY_DIR):
        if fname.endswith(".json"):
            mtime = os.path.getmtime(os.path.join(LIBRARY_DIR, fname))
            if mtime > dir_mtime:
                dir_mtime = mtime
    
    if _LIBRARY_CACHE is not None and dir_mtime <= _LIBRARY_MTIME:
        return _LIBRARY_CACHE
    
    # Rebuild from individual JSON files
    lib = {}
    for fname in sorted(os.listdir(LIBRARY_DIR)):
        if not fname.endswith(".json"):
            continue
        path = os.path.join(LIBRARY_DIR, fname)
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if _validate_preset(data, fname):
            flat = _flatten_preset(data)
            lib[flat.get("id", fname[:-5])] = flat
    
    _LIBRARY_CACHE = lib
    _LIBRARY_MTIME = dir_mtime
    return lib


def _validate_preset(data: dict, fname: str) -> bool:
    """Validate preset structure (ported from presets.gd)."""
    # Required top-level keys
    for key in ["display_name", "geometry", "valvetrain", "drivetrain", "ecu", "metadata"]:
        if key not in data:
            print(f"{fname}: missing required key '{key}'")
            return False
    
    # Geometry validation
    geo = data.get("geometry", {})
    if "cylinders" not in geo or "displacement_cc" not in geo:
        print(f"{fname}: geometry missing cylinders/displacement")
        return False
    
    # Verify fire_deg matches cylinders
    if "fire_deg" in geo and "cylinders" in geo:
        fire_deg = geo["fire_deg"]
        if not isinstance(fire_deg, list) or len(fire_deg) != geo["cylinders"]:
            print(f"{fname}: fire_deg length ({len(fire_deg) if isinstance(fire_deg, list) else 'N/A'}) != cylinders ({geo['cylinders']})")
            return False
    
    # Verify gear_ratios is array
    drv = data.get("drivetrain", {})
    if "gear_ratios" in drv and not isinstance(drv["gear_ratios"], list):
        print(f"{fname}: gear_ratios must be array")
        return False
    
    # ECU binary path
    if "ecu" not in data or "binary_path" not in data["ecu"]:
        print(f"{fname}: ecu.binary_path missing")
        return False
    
    return True


def _flatten_preset(data: dict) -> dict:
    """Flatten preset structure (ported from presets.gd)."""
    flat = {}
    # Copy display_name
    if "display_name" in data:
        flat["display_name"] = data["display_name"]
    # Flatten geometry
    if "geometry" in data:
        for key in data["geometry"]:
            flat[key] = data["geometry"][key]
    # Flatten valvetrain
    if "valvetrain" in data:
        for key in data["valvetrain"]:
            flat[key] = data["valvetrain"][key]
    # Flatten drivetrain
    if "drivetrain" in data:
        for key in data["drivetrain"]:
            flat[key] = data["drivetrain"][key]
    # Flatten ecu
    if "ecu" in data:
        for key in data["ecu"]:
            flat[key] = data["ecu"][key]
    # Store raw ecu binary path for EngineSim
    revision = data.get("metadata", {}).get("revision", 0)
    if isinstance(revision, int) and not isinstance(revision, bool) and revision > 0:
        flat["preset_revision"] = revision
    if "ecu" in data and "binary_path" in data["ecu"]:
        flat["ecu_binary"] = data["ecu"]["binary_path"]
    return flat


def health() -> dict:
    patches = {}
    for platform in ("android", "windows"):
        info = read_patch_info(platform)
        if info is not None:
            patches[platform] = {"base": info["version"], "delta": (info.get("delta") or {}).get("version")}
    return {"ok": True, "uptime_seconds": round(time.time() - STARTED), "patches": patches}


class Handler(BaseHTTPRequestHandler):
    server_version = "EngineBuilderPatches/1.0"
    timeout = 10  # seconds a silent connection may stay open

    def __init__(self, *args, **kwargs):
        with open("handler_init.log", "a") as f:
            f.write(f"Handler __init__\n")
        super().__init__(*args, **kwargs)

    def log_message(self, fmt, *args):  # one line per request: method and path
        if hasattr(self, "command"):
            print("%s %s" % (self.command, self.path.split("?")[0]), flush=True)

    def send_json(self, status: int, body: dict) -> None:
        body['_debug_server_pid'] = os.getpid()
        raw = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def secret_ok(self) -> bool:
        print(f"DEBUG secret_ok: SECRET={repr(SECRET)}, header={repr(self.headers.get('X-Engine-Builder-Secret', ''))}", flush=True)
        if SECRET == "":
            return True
        # Headers arrive decoded as latin-1; encoding back gives the bytes the app sent (UTF-8)
        sent = self.headers.get("X-Engine-Builder-Secret", "").encode("latin-1", "replace")
        return hmac.compare_digest(sent, SECRET.encode("utf-8"))

    def do_GET(self):
        with open("request_debug.log", "a") as f:
            f.write(f"do_GET: path={self.path}\n")
        print(f"DEBUG do_GET: path={self.path}", flush=True)
        if self.path == "/health":
            return self.send_json(200, health())
        if LIBRARY_ROUTE.match(self.path.split("?")[0]):
            lib = read_library()
            if not lib:
                return self.send_json(404, {"error": "no library published"})
            return self.send_json(200, lib)
        if not self.secret_ok():
            return self.send_json(403, {"error": "bad secret"})
        route = PATCH_ROUTE.match(self.path.split("?")[0])
        if route is None:
            return self.send_json(404, {"error": "not found"})
        platform = route.group(1) or "android"
        kind = route.group(2)
        info = read_patch_info(platform)
        if info is None:
            return self.send_json(404, {"error": "no patch published"})
        if kind == "info":
            return self.send_json(200, {key: value for key, value in info.items() if key != "draft"})
        path = os.path.join(patch_dir(platform), kind)
        if not os.path.exists(path):
            return self.send_json(404, {"error": "no such patch file"})
        with open(path, "rb") as f:
            raw = f.read()
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


def main() -> None:
    global SECRET
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=int(os.environ.get("ENGINE_BUILDER_PORT", "8799")))
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--secret", default=os.environ.get("ENGINE_BUILDER_SECRET", ""))
    parser.add_argument("--open", action="store_true", help="run without a secret (local tests only)")
    args = parser.parse_args()
    if not args.secret and not args.open:
        print("Refusing to start without a secret. Pass --secret or set ENGINE_BUILDER_SECRET.", file=sys.stderr)
        sys.exit(2)
    SECRET = "" if args.open else args.secret
    print(f"DEBUG STARTUP: args.open={args.open}, args.secret={repr(args.secret)}, SECRET={repr(SECRET)}", flush=True)
    print("Engine Builder patch server on %s:%d (patches %s)" % (args.host, args.port, PATCH_DIR), flush=True)
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
