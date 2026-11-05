"""Tests for the patch server and the signatures the app checks. Run:  python -m unittest test_patch_server -v"""
import base64
import json
import os
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import padding

import patch_common
import patch_server

SECRET = "test-secret"


class PatchServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        patch_server.PATCH_DIR = os.path.join(cls.tmp, "patches")
        os.makedirs(patch_server.PATCH_DIR)
        cls.pck = os.path.join(patch_server.PATCH_DIR, "game.pck")
        with open(cls.pck, "wb") as f:
            f.write(b"PCK-test-bytes")
        info = {"version": 2, "sha256": patch_common.sha256(cls.pck), "size": os.path.getsize(cls.pck),
                "engine": "4.7.2", "final": True, "signature": patch_common.sign(cls.pck),
                "draft": {"version": 3, "final": False}}
        with open(os.path.join(patch_server.PATCH_DIR, "version.json"), "w", encoding="utf-8") as f:
            json.dump(info, f)
        patch_server.SECRET = SECRET
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), patch_server.Handler)
        cls.base = "http://127.0.0.1:%d" % cls.httpd.server_address[1]
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        patch_server.SECRET = ""

    def get(self, path, secret=SECRET):
        request = urllib.request.Request(self.base + path)
        if secret:
            request.add_header("X-Engine-Builder-Secret", secret)
        try:
            with urllib.request.urlopen(request) as response:
                return response.status, response.read()
        except urllib.error.HTTPError as error:
            return error.code, error.read()

    def test_health_needs_no_secret(self):
        status, body = self.get("/health", secret=None)
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["patches"]["android"]["base"], 2)

    def test_patch_routes_refuse_a_wrong_or_missing_secret(self):
        self.assertEqual(self.get("/patch/info", secret=None)[0], 403)
        self.assertEqual(self.get("/patch/info", secret="wrong")[0], 403)

    def test_info_hides_the_draft(self):
        status, body = self.get("/patch/info")
        self.assertEqual(status, 200)
        info = json.loads(body)
        self.assertNotIn("draft", info)
        self.assertEqual(info["version"], 2)

    def test_game_pck_is_served_unchanged_and_its_signature_verifies(self):
        status, body = self.get("/patch/game.pck")
        self.assertEqual(status, 200)
        self.assertEqual(body, b"PCK-test-bytes")
        info = json.loads(self.get("/patch/info")[1])
        self.assertTrue(verify(body, info["signature"]))

    def test_tampered_bytes_fail_the_signature(self):
        info = json.loads(self.get("/patch/info")[1])
        self.assertFalse(verify(b"PCK-test-bytes-changed", info["signature"]))

    def test_missing_delta_and_unknown_routes(self):
        self.assertEqual(self.get("/patch/delta.pck")[0], 404)
        self.assertEqual(self.get("/app/notice")[0], 404)


def verify(data: bytes, signature_b64: str) -> bool:
    """The same check as Godot's Crypto.verify in patcher.gd: SHA-256, PKCS#1 v1.5, the app's public key."""
    with open(patch_common.PRIVATE_KEY, "rb") as f:
        public = serialization.load_pem_private_key(f.read(), password=None).public_key()
    try:
        public.verify(base64.b64decode(signature_b64), data, padding.PKCS1v15(),
                      patch_common.hashes.SHA256())
        return True
    except Exception:
        return False


if __name__ == "__main__":
    unittest.main()
