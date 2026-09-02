"""Session auth for court web (local users file, no external IdP)."""

from __future__ import annotations

import hashlib
import json
import os
import secrets
import time
from pathlib import Path
from typing import Any

SESSION_TTL_SEC = int(os.environ.get("TY1100_SESSION_TTL", "28800"))  # 8h
_sessions: dict[str, dict[str, Any]] = {}


def _users_path(agent_base: Path) -> Path:
    custom = os.environ.get("TY1100_AUTH_USERS_FILE")
    if custom:
        return Path(custom)
    return agent_base / "web" / "auth.users.json"


def _hash_password(password: str, salt: str) -> str:
    return hashlib.sha256(f"{salt}:{password}".encode()).hexdigest()


def load_users(agent_base: Path) -> dict[str, dict]:
    path = _users_path(agent_base)
    if not path.is_file():
        # Default dev users if no file (change in production)
        salt = os.environ.get("TY1100_AUTH_SALT", "ty1100-local")
        return {
            "judge": {"role": "judge", "password_hash": _hash_password("judge123", salt), "salt": salt},
            "clerk": {"role": "clerk", "password_hash": _hash_password("clerk123", salt), "salt": salt},
        }
    data = json.loads(path.read_text(encoding="utf-8"))
    return data.get("users", data)


def login(agent_base: Path, username: str, password: str, role: str | None = None) -> tuple[str | None, str | None]:
    users = load_users(agent_base)
    user = users.get(username)
    if not user:
        return None, "用户不存在"
    salt = user.get("salt") or os.environ.get("TY1100_AUTH_SALT", "ty1100-local")
    if user.get("password_hash") != _hash_password(password, salt):
        return None, "密码错误"
    if role and user.get("role") != role:
        return None, "角色不匹配"
    token = secrets.token_urlsafe(32)
    _sessions[token] = {
        "username": username,
        "role": user.get("role", role or "clerk"),
        "exp": time.time() + SESSION_TTL_SEC,
    }
    return token, None


def validate_token(token: str | None) -> dict | None:
    if not token:
        return None
    sess = _sessions.get(token)
    if not sess:
        return None
    if sess["exp"] < time.time():
        _sessions.pop(token, None)
        return None
    return sess


def logout(token: str | None) -> None:
    if token:
        _sessions.pop(token, None)


def auth_disabled() -> bool:
    return os.environ.get("TY1100_AUTH_DISABLE") == "1"
