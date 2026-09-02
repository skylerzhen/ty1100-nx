"""Local audit logging for court web (JSONL, no external export)."""

from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def audit_dir(agent_base: Path) -> Path:
    d = agent_base / "logs" / "audit"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _today_file(agent_base: Path) -> Path:
    day = datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d")
    return audit_dir(agent_base) / f"{day}.jsonl"


def hash_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", errors="replace")).hexdigest()[:16]


def write_audit(agent_base: Path, event: dict[str, Any]) -> None:
    if os.environ.get("TY1100_AUDIT_DISABLE") == "1":
        return
    row = {
        "ts": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        **event,
    }
    path = _today_file(agent_base)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def list_recent(agent_base: Path, limit: int = 50) -> list[dict]:
    files = sorted(audit_dir(agent_base).glob("*.jsonl"), reverse=True)
    rows: list[dict] = []
    for fp in files:
        if not fp.is_file():
            continue
        for line in reversed(fp.read_text(encoding="utf-8", errors="replace").splitlines()):
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
            if len(rows) >= limit:
                return rows
    return rows
