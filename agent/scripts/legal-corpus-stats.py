#!/usr/bin/env python3
"""Print local legal corpus statistics (offline index)."""

from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "web"))
from legal_retriever import LegalRetriever  # noqa: E402

base = Path(__file__).resolve().parents[1]
r = LegalRetriever(base)
r._ensure_index()
chunks = r._chunks or []
by_file = Counter(c.source_file for c in chunks)
print(f"total_chunks: {len(chunks)}")
print(f"source_files: {len(by_file)}")
for f, n in sorted(by_file.items(), key=lambda x: -x[1]):
    print(f"  {n:4d}  {f}")
