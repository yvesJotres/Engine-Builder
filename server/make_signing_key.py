"""Makes the key pair that signs game patches. Run it once.

It writes the private key to signing/private.pem (keep it on this PC, back it up, never commit it) and
prints the public key. Paste the printed public key into PUBLIC_KEY in scripts/updates/patcher.gd and
publish a new APK, because the phones only trust the key they were built with.

If the private key is lost, no patch can be published that the phones accept until a new key and a new APK are made.
"""
import os

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from patch_common import PRIVATE_KEY


def main() -> None:
    if os.path.exists(PRIVATE_KEY):
        raise SystemExit("A signing key already exists at %s; it is not replaced." % PRIVATE_KEY)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    os.makedirs(os.path.dirname(PRIVATE_KEY), exist_ok=True)
    with open(PRIVATE_KEY, "wb") as f:
        f.write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                  serialization.NoEncryption()))
    public = key.public_key().public_bytes(serialization.Encoding.PEM,
                                           serialization.PublicFormat.SubjectPublicKeyInfo)
    print("Private key written to %s (keep it secret)." % PRIVATE_KEY)
    print("Public key for scripts/updates/patcher.gd:")
    print(public.decode())


if __name__ == "__main__":
    main()
