"""HTTP client for local ASR service (FunASR on :8091)."""

from __future__ import annotations

import json
import os
import uuid
import urllib.error
import urllib.request
from pathlib import Path


def asr_base_url() -> str:
    return os.environ.get("TY1100_ASR_URL", "http://127.0.0.1:8091").rstrip("/")


def check_asr_health(timeout: float = 5.0) -> tuple[bool, dict | None, str | None]:
    url = f"{asr_base_url()}/health"
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = json.loads(resp.read().decode("utf-8"))
        ready = bool(body.get("ready")) or body.get("status") == "ok"
        return ready, body, None
    except Exception as e:
        return False, None, str(e)


def transcribe_file(path: Path, filename: str | None = None, timeout: int = 900) -> dict:
    """Send audio file to local ASR service. Returns {text, engine, chars, ...}."""
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(path)
    name = filename or path.name
    boundary = f"----ty1100{uuid.uuid4().hex}"
    file_bytes = path.read_bytes()

    parts: list[bytes] = [
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="file"; filename="{name}"\r\n'.encode(),
        b"Content-Type: application/octet-stream\r\n\r\n",
        file_bytes,
        b"\r\n",
        f"--{boundary}--\r\n".encode(),
    ]
    body = b"".join(parts)

    url = f"{asr_base_url()}/transcribe"
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        try:
            obj = json.loads(detail)
            detail = obj.get("detail") or obj.get("error") or detail
        except json.JSONDecodeError:
            pass
        raise RuntimeError(f"ASR 服务错误 ({e.code}): {detail}") from e
    except urllib.error.URLError as e:
        raise RuntimeError(f"ASR 服务不可达 ({url}): {e}") from e
