#!/usr/bin/env python3
"""Run court agent evaluation cases (local, no external network)."""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

AGENT_BASE = Path(__file__).resolve().parents[1]
CASES = AGENT_BASE / "eval" / "court_cases.json"


def post_json(url: str, payload: dict, token: str | None = None) -> dict:
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, json.dumps(payload).encode(), headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=600) as resp:
        return json.loads(resp.read().decode())


def login(base: str) -> str | None:
    try:
        data = post_json(f"{base}/api/auth/login", {"username": "clerk", "password": "clerk123", "role": "clerk"})
        return data.get("token")
    except Exception:
        return None


def run_case(base: str, case: dict, token: str | None) -> dict:
    body: dict = {
        "phase": case.get("phase", "intrail"),
        "case_no": case.get("case_no", ""),
        "case_type": case.get("case_type", ""),
        "role": "clerk",
    }
    if case.get("input_file"):
        p = AGENT_BASE / case["input_file"]
        body["transcript"] = p.read_text(encoding="utf-8")
    else:
        body["transcript"] = case.get("transcript", "")

    if case.get("expect_blocked"):
        data = post_json(f"{base}/api/summarize", body, token)
        ok = data.get("blocked") is True
        rule_ok = case.get("expect_rule", "") in (data.get("rule_id") or "")
        return {"id": case["id"], "ok": ok and rule_ok, "blocked": data.get("blocked"), "rule_id": data.get("rule_id")}

    data = post_json(f"{base}/api/summarize", body, token)
    content = data.get("content") or ""
    checks = case.get("checks", {})
    ok = True
    detail: dict = {"id": case["id"]}
    for s in checks.get("must_include", []):
        if s not in content:
            ok = False
            detail[f"missing_{s}"] = True
    for s in checks.get("must_not_include", []):
        if re.search(s, content, re.I):
            ok = False
            detail[f"forbidden_{s}"] = True
    if checks.get("min_checklist_pass"):
        cl = post_json(f"{base}/api/checklist/validate", {"content": content}, token)
        if cl.get("passed", 0) < checks["min_checklist_pass"]:
            ok = False
            detail["checklist"] = cl.get("passed")
    detail["ok"] = ok
    detail["citation_ok"] = (data.get("citation") or {}).get("ok")
    return detail


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://127.0.0.1:8090")
    args = parser.parse_args()
    cases = json.loads(CASES.read_text(encoding="utf-8"))
    token = login(args.base)
    results = [run_case(args.base, c, token) for c in cases]
    passed = sum(1 for r in results if r.get("ok"))
    print(json.dumps({"passed": passed, "total": len(results), "results": results}, ensure_ascii=False, indent=2))
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
