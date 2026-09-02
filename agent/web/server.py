#!/usr/bin/env python3
"""TY1100 法院庭审辅助 · 本地 Web 服务（仅内网，对接 8081 本地模型）"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import re
import tempfile
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Generator
from urllib.parse import urlparse

from flask import Flask, Response, g, jsonify, request, send_from_directory, stream_with_context

from asr_client import asr_base_url, check_asr_health, transcribe_file
from asr_segment import segment_transcript
from audit_log import hash_text, list_recent, write_audit
from auth import auth_disabled, login, logout, validate_token
from citation_verify import verify_citations
from legal_retriever import get_retriever
from pii_mask import mask_pii

APP_DIR = Path(__file__).resolve().parent
AGENT_BASE = Path(os.environ.get("TY1100_AGENT_BASE", Path.home() / "ty1100-agent"))
LLM_URL = os.environ.get("TY1100_LLM_URL", "http://127.0.0.1:8081/v1/chat/completions")
LLM_MODEL = os.environ.get("TY1100_LLM_MODEL", "Qwen3.6-35B-A3B-UD-Q4_K_M.gguf")
WEB_HOST = os.environ.get("TY1100_WEB_HOST", "0.0.0.0")
WEB_PORT = int(os.environ.get("TY1100_WEB_PORT", "8090"))

ASR_INBOX = AGENT_BASE / "data" / "asr_inbox"
ASR_ALLOWED_SUFFIX = {".wav", ".mp3", ".m4a", ".aac", ".flac", ".ogg", ".webm", ".opus"}
ASR_MAX_MB = int(os.environ.get("TY1100_ASR_MAX_MB", "200"))

app = Flask(__name__, static_folder="static", static_url_path="")

COMPLIANCE_RULES: list[tuple[str, str, str]] = [
    (r"chatgpt|openai|claude|通义|文心|公网\s*llm|境外", "R-DLP-001", "禁止将庭审内容上传公网 LLM；请在本机边端完成处理。"),
    (r"上传.*(网盘|邮箱|微信|qq|外网)|发到.*chatgpt", "R-DLP-001", "禁止将案件材料外传；请使用本地要点归纳功能。"),
    (r"导出.*(录音|录像)|复制.*(录音|录像)|u\s*盘|拷贝.*庭审", "法释2017-5-第十五条", "未经许可不得复制、删除或迁移庭审录音录像。"),
    (r"判决主文|应判.*(胜诉|败诉)|谁赢|一定能赢|帮我赢", "R-LAW-AI-003", "不得预测裁判结果或代写判决主文；可归纳争议焦点与双方主张。"),
    (r"代理词|诉讼策略|怎么反驳", "R-LAW-AI-007", "本系统面向审判辅助，不为一方当事人提供诉讼策略。"),
]

SECTION_LABELS = {
    "pretrial": "【庭前材料】",
    "investigation": "【法庭调查】",
    "evidence": "【举证质证】",
    "debate": "【法庭辩论】",
    "closing": "【最后陈述】",
}

CHECKLIST_ITEMS = [
    {"id": "title", "label": "标题：要点式庭审笔记（辅助稿·待法官核对）", "pattern": r"要点式庭审笔记"},
    {"id": "sec1", "label": "1. 案件信息", "pattern": r"案件信息"},
    {"id": "sec2", "label": "2. 诉讼请求与答辩要点", "pattern": r"诉讼请求|答辩要点"},
    {"id": "sec3", "label": "3. 争议焦点", "pattern": r"争议焦点|争点"},
    {"id": "sec4", "label": "4. 举证质证要点", "pattern": r"举证质证"},
    {"id": "sec5", "label": "5. 法庭辩论要点", "pattern": r"法庭辩论"},
    {"id": "sec6", "label": "6. 最后陈述", "pattern": r"最后陈述"},
    {"id": "sec7", "label": "7. 无争议/待查明事实", "pattern": r"无争议|待查明"},
    {"id": "disclaimer", "label": "末尾免责声明（法释〔2017〕5号）", "pattern": r"法释〔2017〕5号|不具有正式法庭笔录效力"},
    {"id": "neutral", "label": "未出现裁判预测用语", "pattern": None, "forbidden": r"应支持|应判.*胜诉|原告必胜|被告必胜"},
]

PHASE_HINTS = {
    "pretrial": "当前阶段：庭前准备。可预填案件信息与初步争点（标注待庭审核实）。",
    "intrail": "当前阶段：庭中。保留阶段标签，对自认/变更请求等标【关键】。",
    "posttrial": "当前阶段：庭后。输出完整七段式要点摘要。",
}


def get_session() -> dict | None:
    if auth_disabled():
        return {"username": "local", "role": request.headers.get("X-TY1100-Role") or "clerk"}
    auth = request.headers.get("Authorization", "")
    token = auth[7:].strip() if auth.startswith("Bearer ") else None
    return validate_token(token)


def require_auth():
    sess = get_session()
    if not sess:
        return jsonify({"error": "未登录或会话过期"}), 401
    g.session = sess
    return None


@app.before_request
def _auth_guard():
    if request.method == "OPTIONS":
        return None
    path = request.path or ""
    if not path.startswith("/api/"):
        return None
    public = {"/api/health", "/api/auth/login"}
    if path in public:
        return None
    err = require_auth()
    return err


def enrich_response(content: str, legal_cites: list[str], meta: dict) -> dict:
    citation = verify_citations(content, legal_cites)
    checklist_results = []
    for item in CHECKLIST_ITEMS:
        ok = False
        if item.get("forbidden"):
            ok = not re.search(item["forbidden"], content, re.I)
        elif item.get("pattern"):
            ok = bool(re.search(item["pattern"], content, re.I))
        checklist_results.append({"id": item["id"], "label": item["label"], "ok": ok})
    passed = sum(1 for r in checklist_results if r["ok"])
    return {
        "blocked": False,
        "content": content,
        "legal_cites": legal_cites,
        "citation": citation.to_dict(),
        "checklist": {"results": checklist_results, "passed": passed, "total": len(checklist_results)},
        **meta,
    }


def write_stream_audit(
    session: dict,
    *,
    case_no: str,
    transcript: str,
    pii_applied: list | None,
    legal_cites: list[str],
    citation_ok: bool,
    checklist_passed: int,
) -> None:
    """Write audit without touching Flask request context (safe inside SSE generator)."""
    write_audit(
        AGENT_BASE,
        {
            "action": "summarize_stream",
            "user": session.get("username"),
            "role": session.get("role"),
            "case_no": case_no,
            "input_hash": hash_text(transcript),
            "pii_applied": pii_applied,
            "legal_cites": legal_cites,
            "citation_ok": citation_ok,
            "checklist_passed": checklist_passed,
        },
    )


def audit_event(action: str, session: dict | None = None, **fields):
    sess = session if session is not None else (getattr(g, "session", None) or {})
    write_audit(
        AGENT_BASE,
        {
            "action": action,
            "user": sess.get("username"),
            "role": sess.get("role"),
            **fields,
        },
    )


def compliance_check(text: str) -> tuple[bool, str | None, str | None]:
    for pattern, rule_id, message in COMPLIANCE_RULES:
        if re.search(pattern, text, re.I):
            return True, rule_id, message
    return False, None, None


def read_agent_file(rel: str, max_chars: int = 12000) -> str:
    path = AGENT_BASE / rel
    if not path.is_file():
        return f"（文件未找到: {rel}）"
    content = path.read_text(encoding="utf-8", errors="replace")
    if len(content) > max_chars:
        return content[:max_chars] + "\n\n…（已截断）"
    return content


def build_system_prompt(transcript: str = "", case_type: str = "", phase: str = "") -> tuple[str, list[str]]:
    """Core rules + locally retrieved statutes (offline index). Returns (prompt, cite list)."""
    core_parts = [
        read_agent_file("AGENTS.md", 3500),
        read_agent_file("rules/legal/legal-ai-boundary.md", 2500),
        read_agent_file("rules/legal/court-output-standards.md", 3000),
    ]
    retriever = get_retriever(AGENT_BASE)
    retrieval = retriever.retrieve(
        transcript,
        case_type=case_type,
        phase=phase,
        top_k=12,
        max_chars=9000,
    )
    retrieved_block = retriever.format_for_prompt(retrieval)
    cites = [c.cite for c in retrieval.chunks]

    prompt = (
        "你是部署在法院边端 TY1100 上的庭审辅助 Agent。"
        "下列规则来自本机 rules/legal/ 目录；法律依据由本地检索模块按输入匹配，非外网、非 mock。\n\n"
        + "\n\n---\n\n".join(core_parts)
        + "\n\n---\n\n"
        + retrieved_block
        + "\n\n务必：输出标题为「要点式庭审笔记（辅助稿·待法官核对）」；七段式结构；中立不判输赢；"
        "引用上文检索到的法条编号；末尾含法释〔2017〕5号免责声明。"
    )
    return prompt, cites


def build_transcript(body: dict) -> str:
    transcript = (body.get("transcript") or "").strip()
    if transcript:
        return transcript

    sections = body.get("sections") or {}
    parts: list[str] = []
    for key, label in SECTION_LABELS.items():
        text = (sections.get(key) or "").strip()
        if text:
            parts.append(f"{label}\n{text}")
    return "\n\n".join(parts)


def build_user_prompt(phase: str, case_no: str, case_type: str, transcript: str) -> str:
    meta = []
    if case_no:
        meta.append(f"案号：{case_no}")
    if case_type:
        meta.append(f"案由：{case_type}")
    meta_str = "\n".join(meta) if meta else "（未填写）"

    return f"""请根据以下材料，按 rules/legal/court-output-standards.md 与 legal-record-elements.md 输出「要点式庭审笔记（辅助稿·待法官核对）」。

{PHASE_HINTS.get(phase, PHASE_HINTS["intrail"])}

【案件信息（用户填写）】
{meta_str}

【庭审材料 / ASR 转写（已按阶段分段）】
{transcript}
"""


def llm_payload(messages: list[dict], stream: bool = False) -> dict:
    return {
        "model": LLM_MODEL,
        "messages": messages,
        "max_tokens": 2048,
        "temperature": 0.3,
        "stream": stream,
        "chat_template_kwargs": {"enable_thinking": False},
    }


def call_llm(messages: list[dict]) -> str:
    data = json.dumps(llm_payload(messages)).encode("utf-8")
    req = urllib.request.Request(LLM_URL, data=data, headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except urllib.error.URLError as e:
        raise RuntimeError(f"本地模型不可达 ({LLM_URL}): {e}") from e

    msg = body.get("choices", [{}])[0].get("message", {})
    content = (msg.get("content") or "").strip()
    if not content and msg.get("reasoning_content"):
        raise RuntimeError("模型返回为空，请确认 enable_thinking=false 已生效")
    return content


def stream_llm(messages: list[dict]) -> Generator[str, None, None]:
    parsed = urlparse(LLM_URL)
    host, port = parsed.hostname, parsed.port or (443 if parsed.scheme == "https" else 80)
    path = parsed.path or "/v1/chat/completions"
    payload = json.dumps(llm_payload(messages, stream=True)).encode("utf-8")

    conn = http.client.HTTPConnection(host, port, timeout=300)
    try:
        conn.request("POST", path, payload, {"Content-Type": "application/json"})
        resp = conn.getresponse()
        if resp.status != 200:
            yield f"data: {json.dumps({'error': resp.read().decode('utf-8', errors='replace')})}\n\n"
            return
        while True:
            line = resp.readline()
            if not line:
                break
            text = line.decode("utf-8", errors="replace").strip()
            if not text.startswith("data:"):
                continue
            chunk = text[5:].strip()
            if chunk == "[DONE]":
                yield "data: [DONE]\n\n"
                break
            try:
                obj = json.loads(chunk)
                delta = obj.get("choices", [{}])[0].get("delta", {})
                content = delta.get("content") or ""
                if content:
                    yield f"data: {json.dumps({'content': content})}\n\n"
            except json.JSONDecodeError:
                continue
    finally:
        conn.close()


def parse_summarize_request(body: dict) -> tuple[str | None, dict | None]:
    """Returns (error_message, prepared_dict) or (None, data)."""
    transcript = build_transcript(body)
    if not transcript:
        return "请输入庭审材料或至少填写一个阶段段落", None

    phase = body.get("phase") or "intrail"
    case_no = (body.get("case_no") or "").strip()
    case_type = (body.get("case_type") or "").strip()
    role = body.get("role") or getattr(g, "session", {}).get("role") or "clerk"

    if role not in ("judge", "clerk"):
        return "无效角色", None

    check_text = transcript
    blocked, rule_id, rule_msg = compliance_check(check_text)
    if blocked:
        return None, {
            "blocked": True,
            "rule_id": rule_id,
            "message": rule_msg,
            "content": f"**合规拒绝** [{rule_id}]\n\n{rule_msg}",
        }

    masked_transcript, pii_applied = mask_pii(transcript)
    system_prompt, legal_cites = build_system_prompt(masked_transcript, case_type, phase)
    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": build_user_prompt(phase, case_no, case_type, masked_transcript)},
    ]
    return None, {
        "blocked": False,
        "messages": messages,
        "transcript": transcript,
        "masked_transcript": masked_transcript,
        "pii_applied": pii_applied,
        "legal_cites": legal_cites,
        "case_no": case_no,
        "case_type": case_type,
        "phase": phase,
    }


@app.get("/")
def index():
    return send_from_directory(app.static_folder, "index.html")


@app.post("/api/auth/login")
def auth_login():
    body = request.get_json(silent=True) or {}
    username = (body.get("username") or "").strip()
    password = body.get("password") or ""
    role = body.get("role")
    if not username or not password:
        return jsonify({"error": "用户名和密码必填"}), 400
    token, err = login(AGENT_BASE, username, password, role)
    if err:
        audit_event("login_failed", username=username)
        return jsonify({"error": err}), 401
    sess = validate_token(token)
    audit_event("login", username=username, role=sess.get("role") if sess else role)
    return jsonify({"token": token, "role": sess.get("role"), "username": username})


@app.post("/api/auth/logout")
def auth_logout():
    auth = request.headers.get("Authorization", "")
    token = auth[7:].strip() if auth.startswith("Bearer ") else None
    logout(token)
    return jsonify({"ok": True})


@app.get("/api/auth/me")
def auth_me():
    sess = get_session()
    if not sess:
        return jsonify({"error": "未登录"}), 401
    return jsonify(sess)


@app.get("/api/health")
def health():
    llm_ok, llm_error = False, None
    try:
        req = urllib.request.Request(LLM_URL.replace("/chat/completions", "/models"), method="GET")
        with urllib.request.urlopen(req, timeout=5):
            llm_ok = True
    except Exception as e:
        llm_error = str(e)
    retriever = get_retriever(AGENT_BASE)
    retriever._ensure_index()
    chunks = len(retriever._chunks or [])
    asr_ok, asr_info, asr_error = check_asr_health()
    ASR_INBOX.mkdir(parents=True, exist_ok=True)
    asr_count = len(list(ASR_INBOX.glob("*.json")))
    return jsonify({
        "status": "ok",
        "agent_base": str(AGENT_BASE),
        "llm_url": LLM_URL,
        "llm_ok": llm_ok,
        "llm_error": llm_error,
        "legal_chunks": chunks,
        "auth_required": not auth_disabled(),
        "retrieval": "bm25+keyword",
        "stream_audit": "direct-v3",
        "asr_url": asr_base_url(),
        "asr_ok": asr_ok,
        "asr_error": asr_error,
        "asr_engine": (asr_info or {}).get("engine"),
        "asr_inbox_count": asr_count,
    })


@app.get("/api/demo")
def demo():
    path = AGENT_BASE / "knowledge/samples/court-demo-input.md"
    if not path.is_file():
        return jsonify({"error": "演示文件不存在"}), 404
    return jsonify({"content": path.read_text(encoding="utf-8")})


@app.post("/api/legal/preview")
def legal_preview():
    """Preview retrieval for current form input (no LLM)."""
    body = request.get_json(silent=True) or {}
    transcript = build_transcript(body)
    if not transcript:
        return jsonify({"error": "请输入庭审材料"}), 400
    case_type = (body.get("case_type") or "").strip()
    phase = body.get("phase") or "intrail"
    retriever = get_retriever(AGENT_BASE)
    preview = retriever.search_preview(transcript, case_type=case_type, phase=phase)
    preview["legal_cites"] = [h["cite"] for h in preview.get("hits", [])]
    return jsonify(preview)


@app.post("/api/legal/search")
def legal_search():
    """Preview local legal retrieval (offline rules/legal index)."""
    body = request.get_json(silent=True) or {}
    query = (body.get("query") or body.get("q") or "").strip()
    case_type = (body.get("case_type") or "").strip()
    phase = body.get("phase") or ""
    if not query:
        return jsonify({"error": "query required"}), 400
    retriever = get_retriever(AGENT_BASE)
    return jsonify(retriever.search_preview(query, case_type=case_type, phase=phase))


@app.get("/api/legal/index")
def legal_index():
    retriever = get_retriever(AGENT_BASE)
    retriever._ensure_index()
    chunks = retriever._chunks or []
    return jsonify({
        "agent_base": str(AGENT_BASE),
        "total_chunks": len(chunks),
        "sources": sorted({c.source_file for c in chunks}),
        "offline": True,
    })


@app.get("/api/checklist")
def checklist_spec():
    return jsonify({"items": [{"id": i["id"], "label": i["label"]} for i in CHECKLIST_ITEMS]})


@app.post("/api/checklist/validate")
def checklist_validate():
    body = request.get_json(silent=True) or {}
    content = body.get("content") or ""
    results = []
    for item in CHECKLIST_ITEMS:
        ok = False
        if item.get("forbidden"):
            ok = not re.search(item["forbidden"], content, re.I)
        elif item.get("pattern"):
            ok = bool(re.search(item["pattern"], content, re.I))
        results.append({"id": item["id"], "label": item["label"], "ok": ok})
    passed = sum(1 for r in results if r["ok"])
    return jsonify({"results": results, "passed": passed, "total": len(results)})


@app.get("/api/audit/recent")
def audit_recent():
    sess = getattr(g, "session", {})
    if sess.get("role") != "judge":
        return jsonify({"error": "仅法官可查看审计日志"}), 403
    limit = int(request.args.get("limit", 50))
    return jsonify({"events": list_recent(AGENT_BASE, limit=limit)})


def store_asr_result(
    text: str,
    *,
    sections: dict[str, str] | None = None,
    case_no: str = "",
    source: str = "local-asr",
    section: str = "investigation",
    engine: str | None = None,
    audio_file: str | None = None,
    auto_segment: bool = True,
) -> tuple[str, dict]:
    """Persist transcript to inbox; returns (filename, payload)."""
    text = text.strip()
    if not text:
        raise ValueError("empty transcript")
    ASR_INBOX.mkdir(parents=True, exist_ok=True)
    if not sections and auto_segment:
        sections = segment_transcript(text)
    name = datetime.now().strftime("%Y%m%d_%H%M%S") + ".json"
    payload = {
        "text": text,
        "sections": sections or {},
        "section": section,
        "case_no": case_no,
        "source": source,
        "engine": engine,
        "audio_file": audio_file,
    }
    (ASR_INBOX / name).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return name, payload


@app.post("/api/asr/transcribe")
def asr_transcribe():
    """Transcribe uploaded audio via local FunASR service (:8091), segment, store inbox."""
    upload = request.files.get("audio") or request.files.get("file")
    if not upload or not upload.filename:
        return jsonify({"error": "请上传音频文件（字段名 audio 或 file）"}), 400

    suffix = Path(upload.filename).suffix.lower() or ".wav"
    if suffix not in ASR_ALLOWED_SUFFIX:
        return jsonify({"error": f"不支持的音频格式: {suffix}"}), 400

    raw = upload.read()
    if not raw:
        return jsonify({"error": "音频文件为空"}), 400
    if len(raw) > ASR_MAX_MB * 1024 * 1024:
        return jsonify({"error": f"音频过大（上限 {ASR_MAX_MB}MB）"}), 413

    asr_ok, _, asr_err = check_asr_health()
    if not asr_ok:
        return jsonify({"error": f"本地 ASR 服务未就绪: {asr_err or 'check /api/health'}"}), 503

    body = request.form or {}
    case_no = (body.get("case_no") or "").strip()

    with tempfile.TemporaryDirectory(prefix="ty1100_upload_") as td:
        src = Path(td) / f"upload{suffix}"
        src.write_bytes(raw)
        try:
            result = transcribe_file(src, filename=upload.filename)
        except RuntimeError as e:
            return jsonify({"error": str(e)}), 502

    text = (result.get("text") or "").strip()
    if not text:
        return jsonify({"error": "ASR 未识别到有效文本，请检查音频质量或音量"}), 422

    name, payload = store_asr_result(
        text,
        case_no=case_no,
        source="local-asr",
        engine=result.get("engine"),
        audio_file=upload.filename,
    )
    audit_event(
        "asr_transcribe",
        file=name,
        input_hash=hash_text(text),
        segments=list(payload.get("sections", {}).keys()),
        audio_file=upload.filename,
        engine=result.get("engine"),
    )
    return jsonify({
        "ok": True,
        "file": name,
        "text": text,
        "chars": len(text),
        "sections": payload.get("sections", {}),
        "engine": result.get("engine"),
    })


@app.post("/api/asr/ingest")
def asr_ingest():
    """Webhook: external court ASR system pushes text transcript (already recognized)."""
    body = request.get_json(silent=True) or {}
    text = (body.get("text") or "").strip()
    if not text:
        return jsonify({"error": "text required"}), 400

    sections = body.get("sections") or {}
    if body.get("auto_segment", True) and not sections:
        sections = segment_transcript(text)

    name, payload = store_asr_result(
        text,
        sections=sections,
        case_no=body.get("case_no", ""),
        source=body.get("source", "court-asr"),
        section=body.get("section", "investigation"),
        auto_segment=False,
    )
    audit_event("asr_ingest", file=name, input_hash=hash_text(text), segments=list(sections.keys()))
    return jsonify({"ok": True, "file": name, "chars": len(text), "sections": sections})


@app.get("/api/asr/status")
def asr_status():
    ASR_INBOX.mkdir(parents=True, exist_ok=True)
    files = sorted(ASR_INBOX.glob("*.json"), reverse=True)[:20]
    asr_ok, asr_info, asr_error = check_asr_health()
    return jsonify({
        "inbox": str(ASR_INBOX),
        "count": len(list(ASR_INBOX.glob("*.json"))),
        "recent": [f.name for f in files],
        "asr_url": asr_base_url(),
        "asr_ok": asr_ok,
        "asr_error": asr_error,
        "asr_engine": (asr_info or {}).get("engine"),
    })


@app.get("/api/asr/latest")
def asr_latest():
    ASR_INBOX.mkdir(parents=True, exist_ok=True)
    files = sorted(ASR_INBOX.glob("*.json"), reverse=True)
    if not files:
        return jsonify({"error": "no asr data"}), 404
    return jsonify(json.loads(files[0].read_text(encoding="utf-8")))


@app.post("/api/notes/confirm")
def notes_confirm():
    body = request.get_json(silent=True) or {}
    content = (body.get("content") or "").strip()
    if not content:
        return jsonify({"error": "content required"}), 400
    sess = getattr(g, "session", {})
    role = sess.get("role")
    confirm_type = body.get("confirm_type") or role
    if confirm_type not in ("clerk", "judge"):
        return jsonify({"error": "invalid confirm_type"}), 400
    if role != confirm_type:
        return jsonify({"error": f"当前登录角色无法执行{confirm_type}确认"}), 403

    action = "note_confirm_clerk" if confirm_type == "clerk" else "note_confirm_judge"
    audit_event(
        action,
        case_no=body.get("case_no", ""),
        confirm_role=confirm_type,
        input_hash=hash_text(content),
        citation_ok=body.get("citation_ok"),
        checklist_passed=body.get("checklist_passed"),
    )
    msg = "书记员已确认辅助稿（待法官审核）" if confirm_type == "clerk" else "法官已确认辅助稿（记入审计）"
    return jsonify({"ok": True, "confirm_type": confirm_type, "message": msg})


@app.post("/api/summarize")
def summarize():
    body = request.get_json(silent=True) or {}
    err, data = parse_summarize_request(body)
    if err:
        return jsonify({"error": err}), 400
    if data.get("blocked"):
        audit_event(
            "summarize_blocked",
            rule_id=data.get("rule_id"),
            case_no=body.get("case_no"),
            input_hash=hash_text(data.get("transcript", "")),
        )
        return jsonify(data)

    try:
        content = call_llm(data["messages"])
    except RuntimeError as e:
        return jsonify({"error": str(e)}), 502
    resp = enrich_response(content, data.get("legal_cites", []), {})
    audit_event(
        "summarize",
        case_no=data.get("case_no"),
        case_type=data.get("case_type"),
        phase=data.get("phase"),
        input_hash=hash_text(data.get("transcript", "")),
        pii_applied=data.get("pii_applied"),
        legal_cites=data.get("legal_cites"),
        citation_ok=resp["citation"]["ok"],
        checklist_passed=resp["checklist"]["passed"],
    )
    resp["pii_applied"] = data.get("pii_applied", [])
    return jsonify(resp)


@app.post("/api/summarize/stream")
def summarize_stream():
    body = request.get_json(silent=True) or {}
    err, data = parse_summarize_request(body)
    if err:
        return jsonify({"error": err}), 400
    if data.get("blocked"):
        def blocked_gen():
            yield f"data: {json.dumps({'blocked': True, 'rule_id': data['rule_id'], 'content': data['content']})}\n\n"
        return Response(blocked_gen(), mimetype="text/event-stream")

    legal_cites = data.get("legal_cites", [])
    sess = getattr(g, "session", None) or {}
    audit_session = {
        "username": sess.get("username") or body.get("username"),
        "role": sess.get("role") or body.get("role"),
    }
    stream_case_no = data.get("case_no", "")
    stream_transcript = data.get("transcript", "")
    stream_pii = data.get("pii_applied")

    @stream_with_context
    def generate():
        full = ""
        yield f"data: {json.dumps({'meta': True, 'legal_cites': legal_cites, 'pii_applied': stream_pii or []})}\n\n"

        try:
            for chunk in stream_llm(data["messages"]):
                yield chunk
                if chunk.startswith("data:"):
                    raw = chunk[5:].strip()
                    if raw == "[DONE]":
                        continue
                    try:
                        obj = json.loads(raw)
                        if obj.get("content"):
                            full += obj["content"]
                    except json.JSONDecodeError:
                        continue
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"
            return

        if not full.strip():
            return

        resp = enrich_response(full, legal_cites, {})
        try:
            write_stream_audit(
                audit_session,
                case_no=stream_case_no,
                transcript=stream_transcript,
                pii_applied=stream_pii,
                legal_cites=legal_cites,
                citation_ok=resp["citation"]["ok"],
                checklist_passed=resp["checklist"]["passed"],
            )
        except Exception:
            pass

        yield f"data: {json.dumps({'done': True, 'citation': resp['citation'], 'checklist': resp['checklist'], 'legal_cites': legal_cites, 'pii_applied': stream_pii or []})}\n\n"

    return Response(generate(), mimetype="text/event-stream", headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


def resolve_ssl_context(args: argparse.Namespace) -> tuple[str, str] | None:
    cert = args.ssl_cert or os.environ.get("TY1100_WEB_SSL_CERT", "")
    key = args.ssl_key or os.environ.get("TY1100_WEB_SSL_KEY", "")
    if cert and key:
        return cert, key
    default_cert = APP_DIR / "certs" / "cert.pem"
    default_key = APP_DIR / "certs" / "key.pem"
    if default_cert.is_file() and default_key.is_file():
        return str(default_cert), str(default_key)
    return None


def main():
    parser = argparse.ArgumentParser(description="TY1100 庭审辅助 Web")
    parser.add_argument("--host", default=WEB_HOST)
    parser.add_argument("--port", type=int, default=WEB_PORT)
    parser.add_argument("--ssl-cert", default="", help="TLS certificate (PEM)")
    parser.add_argument("--ssl-key", default="", help="TLS private key (PEM)")
    args = parser.parse_args()
    ssl_ctx = resolve_ssl_context(args)
    scheme = "https" if ssl_ctx else "http"
    print(f"Agent 目录: {AGENT_BASE}")
    print(f"本地模型: {LLM_URL}")
    print(f"访问地址: {scheme}://{args.host}:{args.port}/")
    if ssl_ctx:
        print("HTTPS 已启用 — 浏览器首次访问需信任自签证书，之后可使用麦克风")
    app.run(host=args.host, port=args.port, debug=False, threaded=True, ssl_context=ssl_ctx)


if __name__ == "__main__":
    main()
