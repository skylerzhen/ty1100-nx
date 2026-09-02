"""Local legal rule retrieval from rules/legal/ — offline only, no mock."""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from pathlib import Path

# Court-domain terms used for matching (local vocabulary, not external API)
LEGAL_VOCAB = [
    "录音录像", "庭审", "法庭笔录", "要点式", "书记员", "审判长", "诉讼参与人",
    "举证质证", "争议焦点", "最后陈述", "诉讼请求", "答辩", "自认", "质证",
    "复制", "删除", "迁移", "查阅", "誊录", "公开审理", "不公开", "简易程序",
    "当事人同意", "核对签字", "音字转换", "语音识别", "区块链", "元数据",
    "国家秘密", "商业秘密", "个人隐私", "保密", "中断", "休庭", "闭庭",
    "裁判", "判决", "调解", "回避", "管辖", "鉴定", "代理人", "律师",
    "互联网", "在线庭审", "繁简分流", "民间借贷", "借款", "利息", "LPR",
    "劳动仲裁", "经济补偿", "工伤", "加班", "劳动合同", "解除", "辞退",
    "刑事", "公诉", "辩护", "认罪认罚", "量刑", "非法证据", "附带民事",
    "行政", "行政行为", "复议", "负责人出庭", "规范性文件",
    "离婚", "抚养", "彩礼", "共同财产", "夫妻债务",
    "交通事故", "交强险", "残疾赔偿金", "责任认定",
    "商标", "专利", "著作权", "商业秘密", "侵权",
    "消费者", "欺诈", "三倍赔偿", "格式条款",
    "公司", "股东", "决议", "人格否认", "股权转让",
    "执行", "保全", "查封", "冻结", "失信", "拍卖",
    "个人信息", "敏感信息", "同意", "匿名化",
    "在线诉讼", "电子送达", "异步审理", "视频庭审",
    "法庭纪律", "旁听", "证人", "鉴定人",
    "证据保全", "书证", "物证", "电子数据", "证人证言",
    "违约", "解除", "定金", "违约金", "保证", "连带",
    "人身损害", "精神损害", "惩罚性赔偿",
]

# Input keyword -> prefer these article headings (substring match on chunk heading)
TRIGGER_HEADINGS: list[tuple[str, str]] = [
    (r"复制|拷贝|u\s*盘|删除|迁移|外传|上传|chatgpt|公网", "第十五条"),
    (r"笔录|签字|核对|音字|语音", "第六条"),
    (r"简易程序|替代.*笔录", "第八条"),
    (r"异议|补正|回放", "第七条"),
    (r"隐私|秘密|保密|脱敏", "第十六条"),
    (r"中断|休庭", "第三条"),
    (r"公开.*播放|直播", "第十二条"),
    (r"代理人|律师.*复制", "第十一条"),
    (r"要点式|复杂案件", "沪庭审改革-03"),
    (r"区块链|元数据", "沪庭审改革-04"),
    (r"在线|远程|互联网", "沪庭审改革-01"),
]

# Always include for court-summary generation (P0 + output standard)
BASELINE_HEADING_KEYS = [
    "第十五条",
    "第六条",
    "R-COURT-OUT-005",
    "沪庭审改革-03",
    "R-LAW-AI-003",
    "R-LAW-FBD-001",
]

# case_type keyword -> boost if source_file contains substring
CASE_TYPE_SOURCE_BOOST: list[tuple[str, str, float]] = [
    ("借贷", "private-lending", 6.0),
    ("借款", "private-lending", 6.0),
    ("劳动", "labor-dispute", 6.0),
    ("工伤", "labor-dispute", 4.0),
    ("交通", "traffic-accident", 6.0),
    ("事故", "traffic-accident", 4.0),
    ("离婚", "marriage-family", 6.0),
    ("抚养", "marriage-family", 4.0),
    ("刑事", "criminal-procedure", 6.0),
    ("行政", "administrative-litigation", 6.0),
    ("专利", "ip-litigation", 5.0),
    ("商标", "ip-litigation", 5.0),
    ("著作权", "ip-litigation", 5.0),
    ("建设工程", "construction-real-estate", 6.0),
    ("房屋", "construction-real-estate", 4.0),
    ("公司", "company-law", 5.0),
    ("消费", "consumer-protection", 5.0),
]


@dataclass(frozen=True)
class LegalChunk:
    chunk_id: str
    cite: str
    source_file: str
    heading: str
    body: str
    score: float = 0.0

    def prompt_block(self) -> str:
        return f"#### {self.cite} {self.heading}\n\n{self.body.strip()}\n"


@dataclass
class RetrievalResult:
    chunks: list[LegalChunk]
    query_terms: list[str]
    total_indexed: int


class LegalRetriever:
    """Index and search markdown rules under agent/rules/legal/."""

    def __init__(self, agent_base: Path) -> None:
        self.agent_base = Path(agent_base)
        self.legal_root = self.agent_base / "rules" / "legal"
        self._chunks: list[LegalChunk] | None = None

    def _ensure_index(self) -> None:
        if self._chunks is not None:
            return
        self._chunks = []
        if not self.legal_root.is_dir():
            return
        for path in sorted(self.legal_root.rglob("*.md")):
            if path.name.upper() == "README.MD":
                continue
            rel = path.relative_to(self.agent_base).as_posix()
            self._chunks.extend(self._parse_file(path, rel))

    def _parse_file(self, path: Path, rel: str) -> list[LegalChunk]:
        text = path.read_text(encoding="utf-8", errors="replace")
        chunks: list[LegalChunk] = []

        # Prefer ### (statute articles), else ##
        if re.search(r"^###\s+", text, re.M):
            parts = re.split(r"(?=^###\s+)", text, flags=re.M)
        else:
            parts = re.split(r"(?=^##\s+)", text, flags=re.M)

        for part in parts:
            part = part.strip()
            if not part or part.startswith("# ") and not part.startswith("##"):
                # File title only line — skip bare title chunk
                if re.match(r"^#\s+[^\n]+\n*$", part):
                    continue
            m = re.match(r"^(#{2,3})\s+(.+?)(?:\n|$)", part)
            if not m:
                continue
            heading = m.group(2).strip()
            body = part[m.end() :].strip()
            if len(body) < 20:
                continue
            cite = self._heading_to_cite(heading, rel)
            key = self._heading_key(heading)
            chunk_id = f"{rel}::{key}"
            chunks.append(
                LegalChunk(
                    chunk_id=chunk_id,
                    cite=cite,
                    source_file=rel,
                    heading=heading,
                    body=body[:4000],
                )
            )
        return chunks

    @staticmethod
    def _heading_key(heading: str) -> str:
        if m := re.search(r"第([一二三四五六七八九十百零〇\d]+)条", heading):
            return f"第{m.group(1)}条"
        if m := re.search(r"(沪庭审改革-\d+)", heading):
            return m.group(1)
        if m := re.search(r"(R-[A-Z0-9-]+-\d+)", heading):
            return m.group(1)
        if m := re.search(r"(法发2016-21-第\d+条)", heading):
            return m.group(1)
        return heading[:40]

    @staticmethod
    def _heading_to_cite(heading: str, rel: str) -> str:
        if m := re.search(r"第([一二三四五六七八九十百零〇\d]+)条", heading):
            if "fabiao" in rel or "2017" in rel:
                return f"[法释2017-5-第{m.group(1)}条]"
            return f"[第{m.group(1)}条]"
        if m := re.search(r"(沪庭审改革-\d+)", heading):
            return f"[{m.group(1)}]"
        if m := re.search(r"(R-[A-Z0-9-]+-\d+)", heading):
            return f"[{m.group(1)}]"
        if m := re.search(r"(法发2016-21-第\d+条)", heading):
            return f"[{m.group(1)}]"
        return f"[{Path(rel).stem}]"

    @staticmethod
    def extract_terms(text: str) -> set[str]:
        terms: set[str] = set()
        for w in LEGAL_VOCAB:
            if w in text:
                terms.add(w)
        for w in re.findall(r"[\u4e00-\u9fff]{2,6}", text):
            terms.add(w)
        return terms

    @staticmethod
    def _tokenize(text: str) -> list[str]:
        terms = LegalRetriever.extract_terms(text)
        tokens = list(terms)
        tokens.extend(re.findall(r"[\u4e00-\u9fff]{2}", text))
        return tokens

    @staticmethod
    def _bm25_score(query_tokens: list[str], doc_tokens: list[str], avgdl: float, N: int, df: dict[str, int]) -> float:
        if not query_tokens or not doc_tokens:
            return 0.0
        k1, b = 1.2, 0.75
        dl = len(doc_tokens)
        tf: dict[str, int] = {}
        for t in doc_tokens:
            tf[t] = tf.get(t, 0) + 1
        score = 0.0
        for q in set(query_tokens):
            if q not in tf:
                continue
            idf = math.log(1 + (N - df.get(q, 0) + 0.5) / (df.get(q, 0) + 0.5))
            freq = tf[q]
            score += idf * (freq * (k1 + 1)) / (freq + k1 * (1 - b + b * dl / max(avgdl, 1)))
        return score

    def retrieve(
        self,
        query: str,
        *,
        case_type: str = "",
        phase: str = "",
        top_k: int = 12,
        max_chars: int = 9000,
    ) -> RetrievalResult:
        self._ensure_index()
        all_chunks = self._chunks or []
        combined = f"{query}\n{case_type}\n{phase}".strip()
        query_terms = self.extract_terms(combined)
        query_tokens = self._tokenize(combined)

        doc_tokens_map: dict[str, list[str]] = {}
        df: dict[str, int] = {}
        for chunk in all_chunks:
            toks = self._tokenize(chunk.heading + "\n" + chunk.body)
            doc_tokens_map[chunk.chunk_id] = toks
            for t in set(toks):
                df[t] = df.get(t, 0) + 1
        N = max(len(all_chunks), 1)
        avgdl = sum(len(v) for v in doc_tokens_map.values()) / N

        scored: dict[str, LegalChunk] = {}
        for chunk in all_chunks:
            score = 0.0
            haystack = chunk.heading + "\n" + chunk.body
            for term in query_terms:
                if term in haystack:
                    score += 1.0 if len(term) <= 2 else 1.5
            score += self._bm25_score(query_tokens, doc_tokens_map[chunk.chunk_id], avgdl, N, df) * 3.0
            key = self._heading_key(chunk.heading)
            if key in BASELINE_HEADING_KEYS or any(k in chunk.heading for k in BASELINE_HEADING_KEYS):
                score += 5.0
            for pattern, heading_key in TRIGGER_HEADINGS:
                if re.search(pattern, combined, re.I) and heading_key in chunk.heading:
                    score += 8.0
            for kw, src_key, boost in CASE_TYPE_SOURCE_BOOST:
                if kw in case_type and src_key in chunk.source_file:
                    score += boost
            if score > 0:
                scored[chunk.chunk_id] = LegalChunk(
                    chunk_id=chunk.chunk_id,
                    cite=chunk.cite,
                    source_file=chunk.source_file,
                    heading=chunk.heading,
                    body=chunk.body,
                    score=score,
                )

        # Force baseline if index has them
        for chunk in all_chunks:
            key = self._heading_key(chunk.heading)
            if key in BASELINE_HEADING_KEYS or any(k in chunk.heading for k in BASELINE_HEADING_KEYS):
                if chunk.chunk_id not in scored:
                    scored[chunk.chunk_id] = LegalChunk(
                        chunk_id=chunk.chunk_id,
                        cite=chunk.cite,
                        source_file=chunk.source_file,
                        heading=chunk.heading,
                        body=chunk.body,
                        score=5.0,
                    )

        ranked = sorted(scored.values(), key=lambda c: (-c.score, c.source_file, c.heading))
        selected: list[LegalChunk] = []
        used_chars = 0
        for chunk in ranked[: top_k * 2]:
            block = chunk.prompt_block()
            if used_chars + len(block) > max_chars:
                break
            selected.append(chunk)
            used_chars += len(block)
            if len(selected) >= top_k:
                break

        return RetrievalResult(
            chunks=selected,
            query_terms=sorted(query_terms)[:30],
            total_indexed=len(all_chunks),
        )

    def format_for_prompt(self, result: RetrievalResult) -> str:
        if not result.chunks:
            return "（本地规则库未索引到条文，请检查 rules/legal/ 目录）"
        lines = [
            "## 本地规则库检索结果（离线 · 非 mock · 非外网）",
            "",
            f"已索引 {result.total_indexed} 个条文/规则块；本次命中 {len(result.chunks)} 条（BM25+关键词，离线）。",
            f"匹配词：{', '.join(result.query_terms[:15]) or '（基线条款）'}",
            "",
            "生成要点笔记时 **必须遵守** 下列条文；引用时使用方括号编号。",
            "",
        ]
        for chunk in result.chunks:
            lines.append(chunk.prompt_block())
        return "\n".join(lines)

    def search_preview(self, query: str, **kwargs) -> dict:
        result = self.retrieve(query, **kwargs)
        return {
            "query_terms": result.query_terms,
            "total_indexed": result.total_indexed,
            "hits": [
                {
                    "cite": c.cite,
                    "heading": c.heading,
                    "source": c.source_file,
                    "score": round(c.score, 2),
                    "preview": c.body[:200] + ("…" if len(c.body) > 200 else ""),
                }
                for c in result.chunks
            ],
        }


_retriever_cache: dict[str, LegalRetriever] = {}


def get_retriever(agent_base: Path) -> LegalRetriever:
    key = str(agent_base.resolve())
    if key not in _retriever_cache:
        _retriever_cache[key] = LegalRetriever(agent_base)
    return _retriever_cache[key]
