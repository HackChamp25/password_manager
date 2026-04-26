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

# Get the directory where the current script is located
BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Create vault directory inside this folder
VAULT_DIR = os.path.join(BASE_DIR, "vault")
os.makedirs(VAULT_DIR, exist_ok=True)
# Restrict vault directory permissions (owner only)
if os.name != 'nt':  # Unix-like systems
    os.chmod(VAULT_DIR, stat.S_IRWXU)

SALT_FILE = os.path.join(VAULT_DIR, "salt.salt")
# Increased PBKDF2 iterations for better security (industry standard: 600k+ for new systems)
PBKDF2_ITERATIONS = 600_000


def generate_salt() -> bytes:
    """Generate a cryptographically secure random salt."""
    salt = os.urandom(32)  # Increased from 16 to 32 bytes for better security
    # Atomic write with secure permissions
    _atomic_write_file(SALT_FILE, salt, mode='wb')
    return salt


def load_salt() -> bytes:
    """Load salt from file or generate new one if it doesn't exist."""
    if not os.path.exists(SALT_FILE):
        return generate_salt()
    with open(SALT_FILE, 'rb') as f:
        return f.read()


def _atomic_write_file(filepath: str, data: bytes, mode: str = 'wb') -> None:
    """Atomically write file to prevent corruption and set secure permissions."""
    # Write to temporary file first
    dirname = os.path.dirname(filepath)
    fd, temp_path = tempfile.mkstemp(dir=dirname, prefix='.tmp_', suffix='_' + os.path.basename(filepath))
    try:
        with os.fdopen(fd, mode) as f:
            f.write(data)
        # Atomic move
        shutil.move(temp_path, filepath)
        # Set secure file permissions (owner read/write only)
        if os.name != 'nt':  # Unix-like systems
            os.chmod(filepath, stat.S_IRUSR | stat.S_IWUSR)
    except Exception:
        # Clean up temp file on error
        try:
            os.remove(temp_path)
        except:
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
    key = base64.urlsafe_b64encode(kdf.derive(password.encode('utf-8')))
    
    # Clear sensitive data from memory (best effort)
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
    """
    Attempt to securely clear sensitive data from memory (best effort).
    
    Note: Python's memory management makes true secure deletion difficult
    as objects may be copied and garbage collection is non-deterministic.
    This is a best-effort attempt to reduce exposure.
    """
    if isinstance(data, bytes):
        try:
            # Convert to mutable bytearray to attempt overwrite
            mutable = bytearray(data)
            # Overwrite with zeros (best effort)
            for i in range(len(mutable)):
                mutable[i] = 0
            # Fill with random data
            random_data = os.urandom(len(mutable))
            for i in range(len(mutable)):
                mutable[i] = random_data[i]
            # Clear references
            del mutable
            del random_data
        except:
            pass
        # Clear reference (Python GC will handle when possible)
        del data

