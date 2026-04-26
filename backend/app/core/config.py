"""Configuration management"""
import json
import os
from typing import Any, Dict

from app.paths import CONFIG_DIR, ensure_app_directories

CONFIG_FILE = os.path.join(CONFIG_DIR, "settings.json")


class Config:
    """Application configuration manager"""

    DEFAULT_CONFIG: Dict[str, Any] = {
        "auto_lock_minutes": 30,
        "theme": "light",
        "password_generator": {
            "default_length": 16,
            "include_uppercase": True,
            "include_lowercase": True,
            "include_digits": True,
            "include_symbols": True,
            "exclude_similar": True,
        },
        "vault": {
            "backup_enabled": True,
            "backup_count": 5,
        },
    }

    def __init__(self) -> None:
        ensure_app_directories()
        self.config = self._load_config()

    def _load_config(self) -> Dict[str, Any]:
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                    config = json.load(f)
                merged = self.DEFAULT_CONFIG.copy()
                merged.update(config)
                return merged
            except Exception:
                return self.DEFAULT_CONFIG.copy()
        return self.DEFAULT_CONFIG.copy()

    def save_config(self) -> None:
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(self.config, f, indent=2)

    def get(self, key: str, default: Any = None) -> Any:
        keys = key.split(".")
        value: Any = self.config
        for k in keys:
            if isinstance(value, dict) and k in value:
                value = value[k]
            else:
                return default
        return value

    def set(self, key: str, value: Any) -> None:
        keys = key.split(".")
        config: Any = self.config
        for k in keys[:-1]:
            if k not in config:
                config[k] = {}
            config = config[k]
        config[keys[-1]] = value
        self.save_config()
