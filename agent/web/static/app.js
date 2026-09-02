/** TY1100 庭审辅助 Web 前端 */
const $ = (id) => document.getElementById(id);
const STORAGE_ROLE = "ty1100_role";
const STORAGE_TOKEN = "ty1100_token";
const STORAGE_HISTORY = "ty1100_history";
const MAX_HISTORY = 5;

let lastMarkdown = "";
let lastMeta = {};
let progressTimer = null;
let progressStart = 0;

function getToken() {
  return sessionStorage.getItem(STORAGE_TOKEN);
}

function authHeaders(extra = {}) {
  const h = { ...extra };
  const t = getToken();
  if (t) h.Authorization = `Bearer ${t}`;
  return h;
}

async function apiFetch(url, options = {}) {
  const res = await fetch(url, {
    ...options,
    headers: authHeaders(options.headers || {}),
  });
  if (res.status === 401) {
    sessionStorage.removeItem(STORAGE_TOKEN);
    sessionStorage.removeItem(STORAGE_ROLE);
    $("loginOverlay").classList.remove("hidden");
    throw new Error("登录已过期，请重新登录");
  }
  return res;
}

// --- Markdown ---
function renderMarkdown(text) {
  let html = text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");

  html = html.replace(/【关键】/g, '<mark class="key-mark">【关键】</mark>');
  html = html.replace(/(争点[一二三四五六七八九十\d]+[:：][^\n]*)/g, '<div class="dispute-line">$1</div>');
  html = html.replace(/^### (.+)$/gm, "<h3>$1</h3>");
  html = html.replace(/^## (.+)$/gm, "<h2>$1</h2>");
  html = html.replace(/^# (.+)$/gm, "<h1>$1</h1>");
  html = html.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");
  html = html.replace(/^---$/gm, "<hr>");

  const lines = html.split("\n");
  const out = [];
  let inUl = false;
  let inTable = false;

  for (const line of lines) {
    if (/^- /.test(line)) {
      if (!inUl) { out.push("<ul>"); inUl = true; }
      out.push("<li>" + line.slice(2) + "</li>");
      continue;
    }
    if (inUl) { out.push("</ul>"); inUl = false; }

    if (/^\|/.test(line)) {
      if (!inTable) { out.push("<table>"); inTable = true; }
      if (/^\|[\s\-:|]+\|$/.test(line)) continue;
      const cells = line.split("|").slice(1, -1).map((c) => c.trim());
      const isHeader = out[out.length - 1] === "<table>";
      const tag = isHeader ? "th" : "td";
      out.push("<tr>" + cells.map((c) => `<${tag}>${c}</${tag}>`).join("") + "</tr>");
      continue;
    }
    if (inTable) { out.push("</table>"); inTable = false; }

    if (line.startsWith("<h") || line.startsWith("<div") || line.startsWith("<hr") || line.startsWith("<mark")) {
      out.push(line);
    } else if (line.trim()) {
      out.push(`<p>${line}</p>`);
    }
  }
  if (inUl) out.push("</ul>");
  if (inTable) out.push("</table>");
  return out.join("\n");
}

// --- Auth ---
function getRole() {
  return sessionStorage.getItem(STORAGE_ROLE);
}

function setRole(role, username) {
  sessionStorage.setItem(STORAGE_ROLE, role);
  const label = role === "judge" ? `法官 · ${username || ""}` : `书记员 · ${username || ""}`;
  $("roleBadge").textContent = label.trim();
  $("loginOverlay").classList.add("hidden");
  updateConfirmButtons();
  if (role === "judge") {
    $("auditPanel").classList.remove("hidden");
    loadAudit();
  } else {
    $("auditPanel").classList.add("hidden");
  }
}

async function doLogin(role) {
  const username = ($("loginUser").value || "").trim();
  const password = $("loginPass").value || "";
  if (!username || !password) {
    alert("请输入用户名和密码");
    return;
  }
  const res = await fetch("/api/auth/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password, role }),
  });
  const data = await res.json();
  if (!res.ok) {
    alert(data.error || "登录失败");
    return;
  }
  sessionStorage.setItem(STORAGE_TOKEN, data.token);
  setRole(data.role || role, data.username || username);
}

function initAuth() {
  const token = getToken();
  const role = getRole();
  if (token && role) {
    setRole(role, "");
    $("loginOverlay").classList.add("hidden");
  } else {
    $("loginOverlay").classList.remove("hidden");
  }

  document.querySelectorAll(".role-card").forEach((btn) => {
    btn.addEventListener("click", () => doLogin(btn.dataset.role));
  });
  $("btnSwitchRole").addEventListener("click", async () => {
    const t = getToken();
    if (t) {
      try {
        await fetch("/api/auth/logout", { method: "POST", headers: authHeaders() });
      } catch (_) { /* ignore */ }
    }
    sessionStorage.removeItem(STORAGE_TOKEN);
    sessionStorage.removeItem(STORAGE_ROLE);
    $("loginOverlay").classList.remove("hidden");
  });
}

// --- Tabs ---
function initTabs() {
  document.querySelectorAll(".section-tabs .tab").forEach((tab) => {
    tab.addEventListener("click", () => {
      document.querySelectorAll(".section-tabs .tab").forEach((t) => t.classList.remove("active"));
      document.querySelectorAll(".section-area").forEach((a) => a.classList.remove("active"));
      tab.classList.add("active");
      $("sec-" + tab.dataset.tab).classList.add("active");
    });
  });
}

// --- Sections ---
function getSections() {
  return {
    pretrial: $("sec-pretrial").value.trim(),
    investigation: $("sec-investigation").value.trim(),
    evidence: $("sec-evidence").value.trim(),
    debate: $("sec-debate").value.trim(),
    closing: $("sec-closing").value.trim(),
  };
}

function hasAnyInput(sections) {
  return Object.values(sections).some((v) => v.length > 0);
}

function fillDemoFromText(content) {
  const marker = "**审判长：**";
  const idx = content.indexOf(marker);
  if (idx >= 0) {
    $("sec-investigation").value = content.slice(idx);
  } else {
    $("sec-investigation").value = content;
  }
  $("sec-evidence").value = "";
  $("sec-debate").value = "";
  $("sec-closing").value = "";
  document.querySelector('.tab[data-tab="investigation"]').click();
}

// --- File upload (client-side only) ---
function initFileUpload() {
  $("fileInput").addEventListener("change", (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      $("sec-investigation").value = reader.result;
      $("fileName").textContent = file.name;
      document.querySelector('.tab[data-tab="investigation"]').click();
    };
    reader.readAsText(file, "UTF-8");
  });
}

// --- Progress ---
function startProgress() {
  $("progressWrap").classList.remove("hidden");
  $("progressBar").style.width = "5%";
  progressStart = Date.now();
  progressTimer = setInterval(() => {
    const sec = Math.floor((Date.now() - progressStart) / 1000);
    $("progressText").textContent = `已用时 ${sec} 秒 · 本地 35B 推理中…`;
    const pct = Math.min(95, 5 + sec * 1.2);
    $("progressBar").style.width = pct + "%";
  }, 1000);
}

function stopProgress() {
  clearInterval(progressTimer);
  $("progressBar").style.width = "100%";
  setTimeout(() => $("progressWrap").classList.add("hidden"), 600);
}

function updateConfirmButtons() {
  const role = getRole();
  const hasNote = lastMarkdown && lastMarkdown.length > 20;
  const clerkBtn = $("btnConfirmClerk");
  const judgeBtn = $("btnConfirmJudge");
  clerkBtn.classList.toggle("hidden", role !== "clerk");
  judgeBtn.classList.toggle("hidden", role !== "judge");
  clerkBtn.disabled = !hasNote;
  judgeBtn.disabled = !hasNote;
}

function showMeta(data) {
  lastMeta = data || {};
  const cites = data.legal_cites || [];
  $("legalCites").textContent = cites.length
    ? `本次检索法条：${cites.join(" ")}`
    : "本次检索法条：—";
  const cit = data.citation;
  const warn = $("citationWarn");
  if (cit && cit.unverified && cit.unverified.length) {
    warn.classList.remove("hidden");
    warn.textContent = `引用校验：未在检索结果中的编号 ${cit.unverified.join(" ")}（请人工核对）`;
  } else if (cit && cit.cited && cit.cited.length) {
    warn.classList.add("hidden");
  } else {
    warn.classList.add("hidden");
  }
  const pii = data.pii_applied || [];
  const piiEl = $("piiNotice");
  if (pii.length) {
    piiEl.textContent = `PII 脱敏（送模型前）：${pii.join(" · ")}`;
    piiEl.classList.remove("hidden");
    piiEl.classList.add("active");
  } else if (data.pii_applied !== undefined) {
    piiEl.textContent = "未检测到需脱敏的身份证/手机/银行/邮箱";
    piiEl.classList.remove("hidden");
    piiEl.classList.remove("active");
  }

  updateConfirmButtons();
  if (data.checklist) {
    const ul = $("checklist");
    ul.innerHTML = data.checklist.results
      .map((r) => `<li class="${r.ok ? "ok" : "fail"}">${r.ok ? "✓" : "✗"} ${r.label}</li>`)
      .join("");
    $("checkSummary").textContent = `结构校验：${data.checklist.passed}/${data.checklist.total} 项通过`;
  }
}

function setOutputMarkdown(md, blocked = false, meta = {}) {
  lastMarkdown = md;
  const output = $("output");
  output.className = blocked ? "output blocked markdown-body" : "output markdown-body";
  output.innerHTML = renderMarkdown(md);
  const has = md.length > 20;
  $("btnCopy").disabled = !has;
  $("btnDownload").disabled = !has;
  if (!blocked && has) {
    if (meta.checklist) showMeta(meta);
    else validateChecklist(md);
  } else {
    updateConfirmButtons();
  }
  if (meta.legal_cites) showMeta(meta);
}

function initOutputTools() {
  $("btnCopy").addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(lastMarkdown);
      $("btnCopy").textContent = "已复制";
      setTimeout(() => { $("btnCopy").textContent = "复制"; }, 1500);
    } catch {
      alert("复制失败，请手动选择文本");
    }
  });

  $("btnDownload").addEventListener("click", () => {
    const caseNo = ($("caseNo").value || "庭审笔记").replace(/[^\u4e00-\u9fa5a-zA-Z0-9（）()-]/g, "");
    const blob = new Blob([lastMarkdown], { type: "text/markdown;charset=utf-8" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `要点式庭审笔记_${caseNo}.md`;
    a.click();
    URL.revokeObjectURL(a.href);
  });
}

// --- Checklist ---
async function validateChecklist(content) {
  try {
    const res = await apiFetch("/api/checklist/validate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content }),
    });
    const data = await res.json();
    showMeta({ checklist: data, legal_cites: lastMeta.legal_cites || [] });
  } catch {
    $("checkSummary").textContent = "结构校验不可用";
  }
}

// --- History ---
function loadHistory() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_HISTORY) || "[]");
  } catch {
    return [];
  }
}

function saveHistory(entry) {
  const list = loadHistory();
  list.unshift(entry);
  if (list.length > MAX_HISTORY) list.length = MAX_HISTORY;
  localStorage.setItem(STORAGE_HISTORY, JSON.stringify(list));
  renderHistory();
}

function renderHistory() {
  const list = loadHistory();
  const ul = $("historyList");
  if (!list.length) {
    ul.innerHTML = '<li class="muted">暂无记录</li>';
    return;
  }
  ul.innerHTML = list
    .map(
      (h, i) =>
        `<li><button type="button" class="history-item" data-idx="${i}">${h.title}<br><small>${h.time}</small></button></li>`
    )
    .join("");
  ul.querySelectorAll(".history-item").forEach((btn) => {
    btn.addEventListener("click", () => {
      const item = list[Number(btn.dataset.idx)];
      setOutputMarkdown(item.content);
    });
  });
}

function initHistory() {
  renderHistory();
  $("btnClearHistory").addEventListener("click", () => {
    localStorage.removeItem(STORAGE_HISTORY);
    renderHistory();
  });
}

// --- Health ---
async function checkHealth() {
  const dot = $("statusDot");
  const text = $("statusText");
  try {
    const res = await fetch("/api/health");
    const data = await res.json();
    const asrEl = $("asrStatus");
    if (asrEl) {
      if (data.asr_ok) {
        const mode = data.asr_streaming_ready ? "流式+离线" : "离线";
        asrEl.textContent = `ASR 就绪 · ${mode} · 收件箱 ${data.asr_inbox_count || 0} 条`;
        asrStreamingReady = !!data.asr_streaming_ready;
        if (!data.asr_streaming_ready && data.asr_streaming_error) {
          asrEl.textContent += ` · 流式未就绪`;
        }
      } else {
        asrEl.textContent = `ASR 未就绪：${data.asr_error || "请安装并启动 8091 服务"}`;
        asrEl.classList.add("err");
        asrStreamingReady = false;
      }
    }
    if (data.llm_ok && data.asr_ok) {
      dot.className = "dot ok";
      text.textContent = `就绪 · 法条 ${data.legal_chunks || "?"} · ASR 在线`;
    } else if (data.llm_ok) {
      dot.className = "dot busy";
      text.textContent = `LLM 就绪 · ASR 离线`;
    } else {
      dot.className = "dot err";
      text.textContent = "本地模型未连接";
    }
  } catch {
    dot.className = "dot err";
    text.textContent = "服务异常";
  }
}

// --- Submit ---
function buildPayload() {
  return {
    phase: $("phase").value,
    case_no: $("caseNo").value,
    case_type: $("caseType").value,
    role: getRole() || "clerk",
    sections: getSections(),
  };
}

async function submitSync(payload) {
  const res = await apiFetch("/api/summarize", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || "请求失败");
  return data;
}

async function submitStream(payload) {
  const res = await apiFetch("/api/summarize/stream", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const data = await res.json();
    throw new Error(data.error || "请求失败");
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let full = "";
  let streamMeta = {};
  let streamDone = false;

  $("output").className = "output markdown-body";
  $("output").innerHTML = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const parts = buffer.split("\n\n");
    buffer = parts.pop() || "";

    for (const part of parts) {
      const line = part.trim();
      if (!line.startsWith("data:")) continue;
      const raw = line.slice(5).trim();
      if (raw === "[DONE]") continue;
      try {
        const obj = JSON.parse(raw);
        if (obj.blocked) {
          return { blocked: true, content: obj.content, rule_id: obj.rule_id };
        }
        if (obj.meta) {
          streamMeta.legal_cites = obj.legal_cites || [];
          streamMeta.pii_applied = obj.pii_applied || [];
          showMeta(streamMeta);
          continue;
        }
        if (obj.done) {
          streamDone = true;
          streamMeta.citation = obj.citation;
          streamMeta.checklist = obj.checklist;
          streamMeta.legal_cites = obj.legal_cites || streamMeta.legal_cites;
          streamMeta.pii_applied = obj.pii_applied || streamMeta.pii_applied;
          showMeta(streamMeta);
          continue;
        }
        if (obj.error) {
          if (streamDone) continue;
          throw new Error(obj.error);
        }
        if (obj.content) {
          full += obj.content;
          $("output").innerHTML = renderMarkdown(full);
        }
      } catch (e) {
        if (e.message && !e.message.includes("JSON")) throw e;
      }
    }
  }
  return { blocked: false, content: full, ...streamMeta };
}

async function submitSummary() {
  if (!getToken() || !getRole()) {
    $("loginOverlay").classList.remove("hidden");
    return;
  }

  const sections = getSections();
  if (!hasAnyInput(sections)) {
    alert("请至少填写一个阶段的庭审材料");
    return;
  }

  const btn = $("btnSubmit");
  const label = $("btnLabel");
  btn.disabled = true;
  label.textContent = "生成中…";
  $("statusDot").className = "dot busy";
  $("statusText").textContent = "推理中";
  startProgress();

  const payload = buildPayload();
  const useStream = $("useStream").checked;

  try {
    let data;
    if (useStream) {
      data = await submitStream(payload);
      const streamedText = (data.content || "").trim() || ($("output").innerText || "").trim();
      if (!data.blocked && !streamedText && !data.checklist) {
        $("output").innerHTML = "<p class='placeholder'>流式不可用，切换为普通模式…</p>";
        data = await submitSync(payload);
      } else if (!data.content && streamedText) {
        data.content = streamedText;
      }
    } else {
      $("output").innerHTML = "<p class='placeholder'>正在调用本地大模型…</p>";
      data = await submitSync(payload);
    }

    if (data.blocked) {
      setOutputMarkdown(data.content, true);
    } else {
      setOutputMarkdown(data.content, false, data);
      saveHistory({
        title: $("caseNo").value || "未命名案件",
        time: new Date().toLocaleString("zh-CN"),
        content: data.content,
      });
    }
  } catch (e) {
    setOutputMarkdown(`**错误**\n\n${e.message}`, true);
  } finally {
    stopProgress();
    btn.disabled = false;
    label.textContent = "生成要点式庭审笔记";
    checkHealth();
  }
}

async function loadDemo() {
  const res = await apiFetch("/api/demo");
  if (!res.ok) {
    alert("演示案例加载失败");
    return;
  }
  const data = await res.json();
  fillDemoFromText(data.content);
  $("caseNo").value = "（2026）某民初 001 号（虚构）";
  $("caseType").value = "民间借贷纠纷";
}

async function previewLegal() {
  const sections = getSections();
  if (!hasAnyInput(sections)) {
    alert("请至少填写一个阶段的庭审材料");
    return;
  }
  try {
    const res = await apiFetch("/api/legal/preview", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(buildPayload()),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || "预览失败");
    const ul = $("previewHits");
    const hits = data.hits || [];
    if (!hits.length) {
      ul.innerHTML = '<li class="muted">未命中条文（将使用基线条款）</li>';
    } else {
      ul.innerHTML = hits
        .map(
          (h) =>
            `<li><span class="cite">${h.cite}</span> <span class="score">${h.score}</span><br>${h.heading || ""}<br><small>${h.preview || ""}</small></li>`
        )
        .join("");
    }
    $("previewPanel").classList.remove("hidden");
    $("legalCites").textContent = `预览命中 ${hits.length} 条：${(data.legal_cites || []).join(" ")}`;
  } catch (e) {
    alert(e.message);
  }
}

function applyAsrSections(data) {
  const sections = data.sections || {};
  if (Object.keys(sections).length) {
    ["pretrial", "investigation", "evidence", "debate", "closing"].forEach((k) => {
      if (sections[k]) $("sec-" + k).value = sections[k];
    });
    const first = ["investigation", "evidence", "debate", "closing", "pretrial"].find((k) => sections[k]);
    if (first) document.querySelector(`.tab[data-tab="${first}"]`)?.click();
  } else if (data.text) {
    $("sec-investigation").value = data.text;
    document.querySelector('.tab[data-tab="investigation"]')?.click();
  }
  if (data.case_no) $("caseNo").value = data.case_no;
}

function setAsrProgress(msg, isErr = false) {
  const el = $("asrProgress");
  if (!msg) {
    el.classList.add("hidden");
    el.textContent = "";
    return;
  }
  el.textContent = msg;
  el.classList.remove("hidden");
  el.classList.toggle("err", isErr);
}

async function transcribeAudioBlob(blob, filename) {
  const form = new FormData();
  form.append("audio", blob, filename);
  form.append("case_no", $("caseNo").value || "");
  setAsrProgress("正在本地 ASR 转写（Paraformer）…");
  const res = await apiFetch("/api/asr/transcribe", { method: "POST", body: form });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || "转写失败");
  applyAsrSections(data);
  setAsrProgress(`转写完成 · ${data.chars || 0} 字 · ${data.engine || "ASR"}`);
  checkHealth();
  return data;
}

async function loadAsrLatest() {
  try {
    const res = await apiFetch("/api/asr/latest");
    if (!res.ok) {
      alert("暂无转写记录。请先「上传音频」或「开始录音」进行本地语音识别。");
      return;
    }
    const data = await res.json();
    applyAsrSections(data);
    setAsrProgress(`已导入 ${data.source || "ASR"} · ${(data.text || "").length} 字`);
  } catch (e) {
    alert(e.message);
  }
}

// --- Browser microphone → streaming / batch ASR ---
let mediaRecorder = null;
let recordChunks = [];
let asrStreamingReady = false;
let asrWs = null;
let audioCtx = null;
let micStream = null;
let scriptNode = null;
let streamingActive = false;

function asrWsUrl() {
  const proto = location.protocol === "https:" ? "wss:" : "ws:";
  const token = getToken();
  let url = `${proto}//${location.host}/api/asr/ws`;
  if (token) url += `?token=${encodeURIComponent(token)}`;
  return url;
}

function resampleTo16k(float32, fromRate) {
  if (fromRate === 16000) return float32;
  const ratio = fromRate / 16000;
  const outLen = Math.max(1, Math.floor(float32.length / ratio));
  const out = new Float32Array(outLen);
  for (let i = 0; i < outLen; i++) {
    const idx = i * ratio;
    const i0 = Math.floor(idx);
    const i1 = Math.min(i0 + 1, float32.length - 1);
    const t = idx - i0;
    out[i] = float32[i0] * (1 - t) + float32[i1] * t;
  }
  return out;
}

function floatToInt16(f32) {
  const out = new Int16Array(f32.length);
  for (let i = 0; i < f32.length; i++) {
    const s = Math.max(-1, Math.min(1, f32[i]));
    out[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
  }
  return out;
}

function setLiveTranscript(text, active = true) {
  const box = $("asrLiveBox");
  const el = $("asrLiveText");
  if (!box || !el) return;
  box.classList.remove("hidden");
  el.textContent = text || "（等待语音…）";
  el.classList.toggle("live", active && !!text);
  el.classList.toggle("muted", !text);
}

function cleanupStreamingAudio() {
  streamingActive = false;
  try { scriptNode?.disconnect(); } catch (_) {}
  try { audioCtx?.close(); } catch (_) {}
  micStream?.getTracks().forEach((t) => t.stop());
  scriptNode = null;
  audioCtx = null;
  micStream = null;
}

async function saveStreamingTranscript(text) {
  if (!text.trim()) return;
  const res = await apiFetch("/api/asr/ingest", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      text,
      case_no: $("caseNo").value || "",
      source: "live-stream-asr",
      auto_segment: true,
    }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || "保存转写失败");
  applyAsrSections({ text, sections: data.sections, case_no: $("caseNo").value });
  setAsrProgress(`流式转写完成 · ${text.length} 字`);
  checkHealth();
}

async function startStreamingRecord() {
  const btn = $("btnAsrRecord");
  setLiveTranscript("", false);
  setAsrProgress("连接流式 ASR…");

  await new Promise((resolve, reject) => {
    let opened = false;
    const timer = setTimeout(() => reject(new Error("流式 ASR 连接超时（10s）")), 10000);
    asrWs = new WebSocket(asrWsUrl());
    asrWs.onopen = () => {
      opened = true;
      setAsrProgress("等待 ASR 就绪…");
    };
    asrWs.onerror = () => {
      clearTimeout(timer);
      reject(new Error("无法连接流式 ASR（请确认 Web 已部署 flask-sock 且 ASR 8091 在线）"));
    };
    asrWs.onclose = () => {
      if (!opened) {
        clearTimeout(timer);
        reject(new Error("WebSocket 已关闭，请 Ctrl+F5 刷新后重试"));
      }
    };
    asrWs.onmessage = (ev) => {
      let msg;
      try { msg = JSON.parse(ev.data); } catch { return; }
      if (msg.type === "ready") {
        clearTimeout(timer);
        resolve();
        return;
      }
      if (msg.type === "partial") {
        setLiveTranscript(msg.text || "", true);
        setAsrProgress("实时转写中…");
      } else if (msg.type === "final") {
        setLiveTranscript(msg.text || "", false);
        cleanupStreamingAudio();
        btn.textContent = "开始录音";
        btn.classList.remove("recording");
        saveStreamingTranscript(msg.text || "").catch((e) => {
          setAsrProgress(e.message, true);
          alert(e.message);
        });
        asrWs = null;
      } else if (msg.type === "error") {
        clearTimeout(timer);
        setAsrProgress(msg.message || "ASR 错误", true);
        alert(msg.message || "ASR 错误");
        reject(new Error(msg.message || "ASR 错误"));
      }
    };
  });

  micStream = await navigator.mediaDevices.getUserMedia({
    audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true },
  });
  audioCtx = new AudioContext();
  if (audioCtx.state === "suspended") {
    await audioCtx.resume();
  }
  const source = audioCtx.createMediaStreamSource(micStream);
  scriptNode = audioCtx.createScriptProcessor(4096, 1, 1);
  scriptNode.onaudioprocess = (ev) => {
    if (!streamingActive || !asrWs || asrWs.readyState !== WebSocket.OPEN) return;
    const input = ev.inputBuffer.getChannelData(0);
    const resampled = resampleTo16k(input, audioCtx.sampleRate);
    const pcm = floatToInt16(resampled);
    asrWs.send(pcm.buffer);
  };
  source.connect(scriptNode);
  scriptNode.connect(audioCtx.destination);
  streamingActive = true;
  btn.textContent = "停止录音";
  btn.classList.add("recording");
  setAsrProgress("实时转写中… 发言时右侧会滚动出字");
}

function stopStreamingRecord() {
  streamingActive = false;
  cleanupStreamingAudio();
  if (asrWs && asrWs.readyState === WebSocket.OPEN) {
    asrWs.send(JSON.stringify({ type: "stop" }));
  }
}

async function startBatchRecord() {
  const btn = $("btnAsrRecord");
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  recordChunks = [];
  mediaRecorder = new MediaRecorder(stream, {
    mimeType: MediaRecorder.isTypeSupported("audio/webm") ? "audio/webm" : "audio/mp4",
  });
  mediaRecorder.ondataavailable = (e) => {
    if (e.data.size > 0) recordChunks.push(e.data);
  };
  mediaRecorder.onstop = async () => {
    stream.getTracks().forEach((t) => t.stop());
    const blob = new Blob(recordChunks, { type: mediaRecorder.mimeType || "audio/webm" });
    try {
      await transcribeAudioBlob(blob, "court-recording.webm");
    } catch (e) {
      setAsrProgress(e.message, true);
      alert(e.message);
    }
  };
  mediaRecorder.start();
  btn.textContent = "停止并转写";
  btn.classList.add("recording");
  setAsrProgress("录音中（离线模式）… 结束后一次性转写");
}

async function toggleAsrRecord() {
  const btn = $("btnAsrRecord");
  if (streamingActive || (mediaRecorder && mediaRecorder.state === "recording")) {
    if (streamingActive) {
      stopStreamingRecord();
      btn.textContent = "开始录音";
      btn.classList.remove("recording");
    } else {
      mediaRecorder.stop();
      btn.textContent = "开始录音";
      btn.classList.remove("recording");
    }
    return;
  }
  if (!canUseMicrophone()) {
    alert(micBlockedReason());
    return;
  }
  try {
    if (asrStreamingReady) {
      try {
        await startStreamingRecord();
      } catch (e) {
        setAsrProgress(`流式失败: ${e.message}，改用离线录音…`, true);
        await startBatchRecord();
      }
    } else {
      await startBatchRecord();
    }
  } catch (e) {
    alert(micBlockedReason() || "无法访问麦克风：" + e.message);
  }
}

function canUseMicrophone() {
  return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia);
}

function micBlockedReason() {
  if (canUseMicrophone()) return "";
  const host = location.hostname;
  const secure = location.protocol === "https:" || host === "localhost" || host === "127.0.0.1";
  if (!secure) {
    const httpsUrl = `https://${host}${location.port ? ":" + location.port : ""}/`;
    return `浏览器在 HTTP 下禁止麦克风。请改用 ${httpsUrl}（首次点「高级 → 继续访问」），或 Windows 执行 .\\scripts\\open-web-with-mic.ps1`;
  }
  return "当前浏览器不支持麦克风 API，请使用「上传音频」。";
}

function initMicAvailability() {
  const btn = $("btnAsrRecord");
  const hint = $("asrMicHint");
  const reason = micBlockedReason();
  if (reason) {
    btn.disabled = true;
    btn.title = reason;
    hint.textContent = reason;
    hint.classList.remove("hidden");
  } else {
    btn.disabled = false;
    hint.classList.add("hidden");
  }
}

function initAsrPanel() {
  initMicAvailability();
  $("btnAsrRecord").addEventListener("click", toggleAsrRecord);
  $("btnAsrLatest").addEventListener("click", loadAsrLatest);
  $("asrFileInput").addEventListener("change", async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    try {
      await transcribeAudioBlob(file, file.name);
    } catch (err) {
      setAsrProgress(err.message, true);
      alert(err.message);
    }
    e.target.value = "";
  });
}

async function confirmNote(confirmType) {
  if (!lastMarkdown) return;
  const role = getRole();
  if (role !== confirmType) {
    alert(`请使用${confirmType === "judge" ? "法官" : "书记员"}账号登录后再确认`);
    return;
  }
  try {
    const res = await apiFetch("/api/notes/confirm", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        content: lastMarkdown,
        case_no: $("caseNo").value,
        confirm_type: confirmType,
        citation_ok: lastMeta.citation?.ok,
        checklist_passed: lastMeta.checklist?.passed,
      }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || "确认失败");
    alert(data.message || "已确认");
    if (role === "judge") loadAudit();
  } catch (e) {
    alert(e.message);
  }
}

async function loadAudit() {
  if (getRole() !== "judge") return;
  try {
    const res = await apiFetch("/api/audit/recent?limit=30");
    if (!res.ok) return;
    const data = await res.json();
    const ul = $("auditList");
    const events = data.events || [];
    if (!events.length) {
      ul.innerHTML = '<li class="muted">暂无审计记录</li>';
      return;
    }
    ul.innerHTML = events
      .map((ev) => {
        const t = (ev.ts || ev.time || "").replace("T", " ").slice(0, 19);
        const who = ev.user || ev.role || "—";
        const extra = ev.case_no ? ` · ${ev.case_no}` : "";
        return `<li><span class="action">${ev.action}</span> · ${who}${extra}<br><span class="time">${t}</span></li>`;
      })
      .join("");
  } catch {
    $("auditList").innerHTML = '<li class="muted">审计加载失败</li>';
  }
}

function clearInput() {
  ["pretrial", "investigation", "evidence", "debate", "closing"].forEach((k) => {
    $("sec-" + k).value = "";
  });
  $("fileName").textContent = "";
}

// --- Init ---
function init() {
  initAuth();
  initTabs();
  initFileUpload();
  initOutputTools();
  initHistory();
  initAsrPanel();
  $("btnDemo").addEventListener("click", loadDemo);
  $("btnLegalPreview").addEventListener("click", previewLegal);
  $("btnClear").addEventListener("click", clearInput);
  $("btnConfirmClerk").addEventListener("click", () => confirmNote("clerk"));
  $("btnConfirmJudge").addEventListener("click", () => confirmNote("judge"));
  $("btnRefreshAudit").addEventListener("click", loadAudit);
  $("btnSubmit").addEventListener("click", submitSummary);
  checkHealth();
  setInterval(checkHealth, 60000);
}

init();
