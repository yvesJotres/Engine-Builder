"""Engine Builder patch server, run on your PC or a VPS.

Hands the game's patches to the app. It serves only what publish_update.py and publish_patch.py put in patches/.
The app checks each patch's signature against the public key in scripts/updates/patcher.gd, so a copy of this
server cannot publish a patch the app accepts. Drafts are never served.

Start it with:  python patch_server.py --port 8799 --secret YOUR_SECRET   (8799 is its own port; Flatframe uses 8787 and 8788)
(or set the ENGINE_BUILDER_SECRET environment variable). It refuses to start without a secret; --open is for local tests.
Endpoints (GET):
  /health                              public and secret-free: {ok, uptime_seconds, patches}
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
PATCH_ROUTE = re.compile(r"^/patch(?:/(android|windows))?/(info|game\.pck|delta\.pck)$")
STARTED = time.time()
SECRET = ""


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

    def log_message(self, fmt, *args):  # one line per request: method and path
        if hasattr(self, "command"):
            print("%s %s" % (self.command, self.path.split("?")[0]), flush=True)

    def send_json(self, status: int, body: dict) -> None:
        raw = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def secret_ok(self) -> bool:
        if SECRET == "":
            return True
        # Headers arrive decoded as latin-1; encoding back gives the bytes the app sent (UTF-8)
        sent = self.headers.get("X-Engine-Builder-Secret", "").encode("latin-1", "replace")
        return hmac.compare_digest(sent, SECRET.encode("utf-8"))

    def do_GET(self):
        if self.path == "/health":
            return self.send_json(200, health())
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
    SECRET = args.secret
    print("Engine Builder patch server on %s:%d (patches %s)" % (args.host, args.port, PATCH_DIR), flush=True)
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
