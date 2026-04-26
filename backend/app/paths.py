"""Repository-root paths and directory layout (single source of truth)."""
import os
import stat

# backend/app/ -> repo root
_APP_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(_APP_DIR, "..", ".."))
VAULT_DIR = os.path.join(REPO_ROOT, "vault")
CONFIG_DIR = os.path.join(REPO_ROOT, "config")
LOGS_DIR = os.path.join(REPO_ROOT, "logs")

_dirs_ready: bool = False


def ensure_app_directories() -> None:
    """Create vault, config, and log dirs; tighten vault perms on Unix."""
    global _dirs_ready
    if _dirs_ready:
        return
    for path in (VAULT_DIR, CONFIG_DIR, LOGS_DIR):
        os.makedirs(path, exist_ok=True)
    if os.name != "nt":
        try:
            os.chmod(VAULT_DIR, stat.S_IRWXU)
        except OSError:
            pass
    _dirs_ready = True
