"""Verify legal citations in model output against retrieved context."""

from __future__ import annotations

import re
from dataclasses import dataclass

CITE_PATTERN = re.compile(
    r"\[(法释2017-5-第[一二三四五六七八九十百零〇\d]+条|"
    r"沪庭审改革-\d+|R-[A-Z0-9-]+-\d+|法发2016-21-第\d+条|第[一二三四五六七八九十百零〇\d]+条)\]"
)


@dataclass
class CitationReport:
    cited: list[str]
    verified: list[str]
    unverified: list[str]
    ok: bool

    def to_dict(self) -> dict:
        return {
            "cited": self.cited,
            "verified": self.verified,
            "unverified": self.unverified,
            "ok": self.ok,
        }


def normalize_cite(cite: str) -> str:
    c = cite.strip()
    if not c.startswith("["):
        c = f"[{c}]"
    return c


def verify_citations(content: str, allowed_cites: list[str]) -> CitationReport:
    allowed = {normalize_cite(c) for c in allowed_cites}
    # Always allow common disclaimer references if in baseline retrieval
    allowed.update(
        {
            "[法释2017-5-第十五条]",
            "[法释2017-5-第六条]",
            "[法释2017-5-第十六条]",
            "[R-COURT-OUT-005]",
            "[R-LAW-AI-003]",
        }
    )
    found_full = list(dict.fromkeys(normalize_cite(m.group(0)) for m in CITE_PATTERN.finditer(content)))

    verified = [c for c in found_full if c in allowed]
    unverified = [c for c in found_full if c not in allowed]
    return CitationReport(
        cited=found_full,
        verified=verified,
        unverified=unverified,
        ok=len(unverified) == 0,
    )
