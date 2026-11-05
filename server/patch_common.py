"""Shared helpers for the patch publish scripts: file hashes and the signature the phones check.

The signing key stays on this PC in server/signing/private.pem (not in Git). The phones carry only the
public key, in scripts/updates/patcher.gd, so a copy of the server cannot publish a patch the phones accept.
"""
import base64
import hashlib
import os
import sys

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

HERE = os.path.dirname(os.path.abspath(__file__))
PRIVATE_KEY = os.path.join(HERE, "signing", "private.pem")


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def sign(path):
    """The base64 RSA signature of the file's bytes (SHA-256, PKCS#1 v1.5, what Godot's Crypto.verify checks)."""
    if not os.path.exists(PRIVATE_KEY):
        sys.exit("The signing key is missing. Run: python make_signing_key.py")
    with open(PRIVATE_KEY, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    with open(path, "rb") as f:
        return base64.b64encode(key.sign(f.read(), padding.PKCS1v15(), hashes.SHA256())).decode()
