"""Logging configuration"""
import logging
import os
from logging.handlers import RotatingFileHandler

from app.paths import ensure_app_directories, LOGS_DIR

LOG_FILE = os.path.join(LOGS_DIR, "password_manager.log")


def setup_logger(name: str = "PasswordManager", level: int = logging.INFO) -> logging.Logger:
    ensure_app_directories()
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    logger = logging.getLogger(name)
    logger.setLevel(level)
    if logger.handlers:
        return logger
    formatter = logging.Formatter(
        "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    file_handler = RotatingFileHandler(
        LOG_FILE, maxBytes=10 * 1024 * 1024, backupCount=5, encoding="utf-8"
    )
    file_handler.setLevel(logging.DEBUG)
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.WARNING)
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)
    return logger
