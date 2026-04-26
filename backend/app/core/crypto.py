"""Cryptographic utilities for secure password management"""
import base64
import os
import stat
import tempfile
import shutil
from typing import Tuple
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes, hmac
from cryptography.hazmat.backends import default_backend
from cryptography.fernet import Fernet

from app.paths import VAULT_DIR

# Restrict vault directory permissions (owner only) on non-Windows
if os.name != "nt" and os.path.exists(VAULT_DIR):
    try:
        os.chmod(VAULT_DIR, stat.S_IRWXU)
    except OSError:
        pass

SALT_FILE = os.path.join(VAULT_DIR, "salt.salt")
# Increased PBKDF2 iterations (OWASP-style targets)
PBKDF2_ITERATIONS = 600_000


def generate_salt() -> bytes:
    """Generate a cryptographically secure random salt."""
    salt = os.urandom(32)
    _atomic_write_file(SALT_FILE, salt, mode="wb")
    return salt


def load_salt() -> bytes:
    """Load salt from file or generate new one if it doesn't exist."""
    if not os.path.exists(SALT_FILE):
        return generate_salt()
    with open(SALT_FILE, "rb") as f:
        return f.read()


def _atomic_write_file(filepath: str, data: bytes, mode: str = "wb") -> None:
    """Atomically write file to prevent corruption and set secure permissions."""
    dirname = os.path.dirname(filepath)
    fd, temp_path = tempfile.mkstemp(dir=dirname, prefix=".tmp_", suffix="_" + os.path.basename(filepath))
    try:
        with os.fdopen(fd, mode) as f:
            f.write(data)
        shutil.move(temp_path, filepath)
        if os.name != "nt":
            os.chmod(filepath, stat.S_IRUSR | stat.S_IWUSR)
    except Exception:
        try:
            os.remove(temp_path)
        except OSError:
            pass
        raise


def get_key_from_password(password: str) -> bytes:
    """Derive encryption key from master password using PBKDF2."""
    if not password or len(password) < 8:
        raise ValueError("Master password must be at least 8 characters long")

    salt = load_salt()
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=PBKDF2_ITERATIONS,
        backend=default_backend()
    )
    key = base64.urlsafe_b64encode(kdf.derive(password.encode("utf-8")))
    del password
    return key


def get_fernet(key: bytes) -> Fernet:
    """Create Fernet cipher instance from key."""
    return Fernet(key)


def derive_hmac_key(master_key: bytes) -> bytes:
    """Derive a separate HMAC key from the master key for integrity verification."""
    h = hashes.Hash(hashes.SHA256(), backend=default_backend())
    h.update(b"HMAC_KEY_DERIVATION" + master_key)
    return h.finalize()


def compute_hmac(key: bytes, data: bytes) -> bytes:
    """Compute HMAC for data integrity verification."""
    h = hmac.HMAC(key, hashes.SHA256(), backend=default_backend())
    h.update(data)
    return h.finalize()


def verify_hmac(key: bytes, data: bytes, mac: bytes) -> bool:
    """Verify HMAC to detect tampering."""
    try:
        h = hmac.HMAC(key, hashes.SHA256(), backend=default_backend())
        h.update(data)
        h.verify(mac)
        return True
    except Exception:
        return False


def secure_delete(data: bytes) -> None:
    """Best-effort in-memory clear for sensitive byte strings."""
    if isinstance(data, bytes):
        try:
            mutable = bytearray(data)
            for i in range(len(mutable)):
                mutable[i] = 0
            random_data = os.urandom(len(mutable))
            for i in range(len(mutable)):
                mutable[i] = random_data[i]
            del mutable
            del random_data
        except Exception:
            pass
        del data
