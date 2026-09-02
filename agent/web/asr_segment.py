"""Split ASR transcript into court phase sections by keywords."""

from __future__ import annotations

import re

# Order matters: more specific first
SECTION_RULES: list[tuple[str, re.Pattern[str]]] = [
    ("pretrial", re.compile(r"庭前准备|起诉状|答辩状|庭前会议", re.I)),
    ("closing", re.compile(r"最后陈述|陈述最后意见|最后意见", re.I)),
    ("debate", re.compile(r"法庭辩论|辩论阶段|发表辩论", re.I)),
    ("evidence", re.compile(r"举证质证|质证|出示证据|交换证据", re.I)),
    ("investigation", re.compile(r"法庭调查|现在进行法庭调查|调查阶段", re.I)),
]

DEFAULT_SECTION = "investigation"


def segment_transcript(text: str) -> dict[str, str]:
    """Return section_key -> text chunks (may be partial if no markers)."""
    text = text.strip()
    if not text:
        return {}

    hits: list[tuple[int, str, str]] = []
    for key, pat in SECTION_RULES:
        for m in pat.finditer(text):
            hits.append((m.start(), key, m.group(0)))

    if not hits:
        return {DEFAULT_SECTION: text}

    hits.sort(key=lambda x: x[0])
    sections: dict[str, list[str]] = {}
    for i, (pos, key, _label) in enumerate(hits):
        end = hits[i + 1][0] if i + 1 < len(hits) else len(text)
        chunk = text[pos:end].strip()
        if chunk:
            sections.setdefault(key, []).append(chunk)

    return {k: "\n\n".join(v) for k, v in sections.items()}


def merge_sections_to_transcript(sections: dict[str, str], labels: dict[str, str]) -> str:
    parts = []
    for key, label in labels.items():
        if sections.get(key):
            parts.append(f"{label}\n{sections[key]}")
    return "\n\n".join(parts)
