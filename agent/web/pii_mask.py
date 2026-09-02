"""Mask common PII before sending text to local LLM."""

from __future__ import annotations

import re

# ID card 18 / 15 digit
_ID_RE = re.compile(r"\b\d{6}(?:19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\d{3}[\dXx]\b")
_PHONE_RE = re.compile(r"(?<!\d)(1[3-9]\d{9})(?!\d)")
_BANK_RE = re.compile(r"\b\d{16,19}\b")
_EMAIL_RE = re.compile(r"[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+")


def mask_pii(text: str) -> tuple[str, list[str]]:
    """Returns (masked_text, list of mask types applied)."""
    applied: list[str] = []
    out = text

    def sub_count(pattern: re.Pattern[str], repl: str, label: str) -> None:
        nonlocal out
        new, n = pattern.subn(repl, out)
        if n:
            applied.append(f"{label}:{n}")
            out = new

    sub_count(_ID_RE, "[身份证已脱敏]", "id")
    sub_count(_PHONE_RE, "[手机号已脱敏]", "phone")
    sub_count(_BANK_RE, "[银行账号已脱敏]", "bank")
    sub_count(_EMAIL_RE, "[邮箱已脱敏]", "email")
    return out, applied
