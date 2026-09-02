# TY1100-NX 法院庭审 Agent · 开发规格书

| 项目 | 内容 |
|------|------|
| **文档类型** | 开发规格书（Dev Spec） |
| **版本** | v1.0 |
| **日期** | 2026-09-02 |
| **适用产品** | TY1100-NX 边端 + 庭审辅助 Agent + Web 交互界面 |
| **主场景** | 法院 · 要点式庭审笔记（上海庭审记录改革对齐） |
| **代码路径** | `ty1100-nx/agent/` |

---

## 1. 文档目的与范围

### 1.1 目的

本文档为 **开发、测试、部署、验收** 提供统一规格，定义：

- 系统架构与模块边界
- 知识库 / 规则库 / 法律法规的组织与优先级
- Web 前端与后端 API 契约
- 与本地大模型（8081）的对接方式
- 合规预检与输出标准
- 测试用例与验收标准

### 1.2 范围内

| 模块 | 说明 |
|------|------|
| Pi Agent 项目 | `~/ty1100-agent/`（规则库、知识库、AGENTS.md） |
| Web 交互界面 | Flask `:8090` + 静态前端 |
| 本地推理 | llama.cpp `:8081`（Qwen3.6-35B Q4_K_M） |
| 庭审场景 | 要点归纳、争点整理、诉辩对比 |

### 1.3 范围外

- 智慧庭审系统（录音录像、区块链、元数据表）的实现与对接
- 实时 ASR 麦克风采集（当前仅 **粘贴文本**）
- 刑事 / 行政等案由的独立模板（后续扩展）
- 公网 SaaS、OpenClaw 底座

---

## 2. 产品定位

### 2.1 一句话

在 **法院内网边端** 部署本地大模型 + 规则库，为法官/书记员提供 **要点式庭审笔记辅助稿** 生成能力，**数据不出域**。

### 2.2 分层定位

```
┌─────────────────────────────────────────────────────────┐
│  正式层：智慧庭审系统                                     │
│  全程录音录像 · 音字转换 · 元数据记录表 · 签名入卷        │
└─────────────────────────────────────────────────────────┘
                          ↑ 不替代
┌─────────────────────────────────────────────────────────┐
│  辅助层：TY1100 本地 Agent + Web（本规格书范围）           │
│  要点式笔记 · 争点归纳 · 诉辩对比 · 合规拦截              │
└─────────────────────────────────────────────────────────┘
                          ↓ 仅调用
┌─────────────────────────────────────────────────────────┐
│  推理层：llama.cpp @ 127.0.0.1:8081                      │
│  Qwen3.6-35B-A3B Q4_K_M · ~30 tokens/s                  │
└─────────────────────────────────────────────────────────┘
```

### 2.3 用户角色

| 角色 | 支持 | 不支持 |
|------|------|--------|
| 法官 / 审判长 | 中性要点归纳 | 裁判结论、判决主文 |
| 书记员 / 审判辅助 | 结构化辅助稿 | 声称正式笔录已生效 |
| 当事人 / 代理人 | — | 诉讼策略、胜诉预测 |

详见：`agent/knowledge/court/roles.md`

---

## 3. 系统架构

### 3.1 逻辑架构

```text
[浏览器 :8090]
    │  HTTP
    ▼
[Flask server.py]
    ├─ 静态资源 static/
    ├─ GET  /api/health
    ├─ GET  /api/demo
    └─ POST /api/summarize
           ├─ (1) 合规预检 COMPLIANCE_RULES
           ├─ (2) 读取 rules/knowledge → system prompt
           └─ (3) POST → 127.0.0.1:8081/v1/chat/completions
```

### 3.2 物理部署

| 组件 | 地址 | 说明 |
|------|------|------|
| Web 服务 | `0.0.0.0:8090` | 局域网浏览器访问 |
| 大模型 API | `127.0.0.1:8081` | 仅本机，不暴露公网 |
| Agent 目录 | `~/ty1100-agent/` | 规则库、知识库、Web |
| 设备 IP（当前） | `192.168.34.11` | 34 网段静态 IP |

### 3.3 技术栈

| 层级 | 技术 |
|------|------|
| Agent 底座（CLI） | Pi（pi-coding-agent） |
| Web 后端 | Python 3.11 + Flask |
| Web 前端 | HTML / CSS / Vanilla JS（无 CDN） |
| 推理 | llama.cpp Docker + OpenAI 兼容 API |
| 模型 | Qwen3.6-35B-A3B-UD-Q4_K_M.gguf |

---

## 4. 目录结构规格

```text
agent/
├── AGENTS.md                 # Agent 总行为规约
├── setup-ops-agent.sh        # 同步到 ~/ty1100-agent
├── knowledge/
│   ├── README.md
│   ├── court/                # 庭审场景知识库
│   │   ├── README.md
│   │   ├── workflow.md
│   │   ├── roles.md
│   │   ├── input-guide.md
│   │   └── glossary.md
│   ├── legal-court-scenario.md
│   ├── shanghai-court-official.md
│   ├── ty1100-nx.md
│   └── samples/
│       ├── court-demo-input.md
│       └── court-demo-output-example.md   # 黄金样例
├── rules/
│   ├── 00-priority.md
│   ├── data-leakage-prevention.md         # R-DLP
│   └── legal/
│       ├── statutes/                      # 法释〔2017〕5号等原文
│       ├── court-output-standards.md      # R-COURT-OUT
│       ├── court-workflow-rules.md        # R-COURT-WF
│       ├── legal-record-elements.md       # R-LAW-ELE
│       ├── legal-ai-boundary.md           # R-LAW-AI
│       └── ...
├── web/
│   ├── server.py
│   ├── start-web.sh
│   ├── requirements.txt
│   └── static/
│       ├── index.html
│       ├── app.css
│       └── app.js
└── .agents/skills/
    └── court-summary/
```

---

## 5. 规则与知识库规格

### 5.1 优先级（冲突时从高到低）

1. `rules/legal/statutes/` — 法律法规原文
2. `rules/` — 硬性规则（P0 拒绝）
3. `knowledge/` — 场景事实与流程
4. 本地模型推理 — 仅 `127.0.0.1:8081`

### 5.2 规则库索引（庭审相关）

| 文件 | 规则前缀 | 用途 |
|------|----------|------|
| `statutes/fabiao-2017-5-recording.md` | 法释2017-5 | 录音录像 19 条原文 |
| `statutes-enforcement.md` | P0 清单 | 执行总纲 |
| `court-output-standards.md` | R-COURT-OUT | 输出标题、七段式、免责声明 |
| `court-workflow-rules.md` | R-COURT-WF | 庭前/庭中/庭后 |
| `legal-record-elements.md` | R-LAW-ELE | 七段式要素 |
| `legal-ai-boundary.md` | R-LAW-AI | 不裁判、不替代笔录 |
| `shanghai-court-recording.md` | R-SH | 上海要点式笔记 |
| `legal-forbidden.md` | R-LAW-FBD | 禁止行为 |
| `data-leakage-prevention.md` | R-DLP | 防外传 |

### 5.3 知识库索引（庭审相关）

| 文件 | 用途 |
|------|------|
| `knowledge/court/workflow.md` | 三阶段工作流 |
| `knowledge/court/roles.md` | 角色权限 |
| `knowledge/court/input-guide.md` | ASR 输入规范 |
| `knowledge/shanghai-court-official.md` | 上海改革官方摘要 |

### 5.4 System Prompt 注入（Web 后端）

`server.py` 的 `build_system_prompt()` 在每次 `/api/summarize` 时拼接：

| 文件 | 最大字符 |
|------|----------|
| `AGENTS.md` | 4000 |
| `rules/legal/court-output-standards.md` | 3000 |
| `rules/legal/legal-record-elements.md` | 4000 |
| `rules/legal/legal-ai-boundary.md` | 2500 |
| `rules/legal/shanghai-court-recording.md` | 2500 |

---

## 6. Web API 规格

**Base URL：** `http://<设备IP>:8090`

### 6.1 `GET /`

返回静态页面 `index.html`。

### 6.2 `GET /api/health`

**响应示例：**

```json
{
  "status": "ok",
  "agent_base": "/home/cix/ty1100-agent",
  "llm_url": "http://127.0.0.1:8081/v1/chat/completions",
  "llm_ok": true,
  "llm_error": null
}
```

| 字段 | 说明 |
|------|------|
| `llm_ok` | 8081 `/v1/models` 是否可达 |
| `agent_base` | 规则库根目录 |

### 6.3 `GET /api/demo`

**响应：**

```json
{
  "content": "… court-demo-input.md 全文 …"
}
```

### 6.4 `POST /api/summarize`

**请求 Body（JSON）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `transcript` | string | 二选一 | 整段文本（与 sections 二选一） |
| `sections` | object | 二选一 | 分段：`pretrial/investigation/evidence/debate/closing` |
| `phase` | string | 否 | `pretrial` \| `intrail` \| `posttrial` |
| `case_no` | string | 否 | 案号 |
| `case_type` | string | 否 | 案由 |
| `role` | string | 否 | `judge` \| `clerk` |

**成功响应：**

```json
{ "blocked": false, "content": "# 要点式庭审笔记…" }
```

**合规拒绝：**

```json
{ "blocked": true, "rule_id": "R-DLP-001", "message": "…", "content": "…" }
```

### 6.5 合规预检规则

| 模式 | 规则 ID |
|------|---------|
| chatgpt / openai / 公网 llm | R-DLP-001 |
| 上传网盘/邮箱/微信 | R-DLP-001 |
| 导出/复制录音录像、U 盘 | 法释2017-5-第十五条 |
| 判决主文、谁赢、胜诉 | R-LAW-AI-003 |
| 代理词、诉讼策略 | R-LAW-AI-007 |

命中预检 **不调用** 8081。

### 6.6 LLM 调用参数

须 `enable_thinking: false`；流式时 `"stream": true`。详见 `server.py`。

### 6.7 `POST /api/summarize/stream`

SSE 流式输出；请求 Body 同 6.4，可含 `sections` 分段对象：

```json
{
  "phase": "intrail",
  "case_no": "…",
  "case_type": "…",
  "role": "clerk",
  "sections": {
    "investigation": "…",
    "evidence": "…",
    "debate": "…",
    "closing": "…",
    "pretrial": "…"
  }
}
```

事件：`data: {"content":"…"}` · 结束 `data: [DONE]` · 拒绝 `data: {"blocked":true,...}`

### 6.8 `POST /api/checklist/validate`

校验生成内容是否含七段式关键结构；返回 `{ passed, total, results[] }`。

**错误响应（通用）：**

| HTTP | 场景 |
|------|------|
| 400 | 输入为空 |
| 502 | 8081 不可达或模型返回空 |

---

## 7. 前端规格

### 7.1 页面结构（v1.1）

| 区域 | 元素 |
|------|------|
| 登录层 | 法官 / 书记员身份选择（sessionStorage） |
| 顶栏 | 标题、角色徽章、模型状态 |
| 左栏 · 输入 | 阶段、案号、案由；**五段式 Tab**（调查/质证/辩论/陈述/庭前）；`.txt` 导入；Demo；流式开关 |
| 中栏 · 输出 | Markdown 渲染；**复制** / **下载 .md**；争点高亮、【关键】标记 |
| 右栏 | **七段式结构校验**；**历史记录**（localStorage 最近 5 条） |
| 进度 | 生成中进度条 + 已用秒数 |

### 7.2 交互流程

```text
打开页面 → GET /api/health（状态灯）
    → [可选] GET /api/demo（填充输入）
    → 用户编辑 → POST /api/summarize
    → 渲染 Markdown / 合规拒绝红框
```

### 7.3 输出格式要求（验收）

生成内容 **必须** 满足 `R-COURT-OUT-001`～`005`：

- 标题：`# 要点式庭审笔记（辅助稿·待法官核对）`
- 结构：七段式（见 `legal-record-elements.md`）
- 争点：含原/被告主张对比，**不得**写应支持哪方
- 末尾：法释〔2017〕5号免责声明

黄金参考：`knowledge/samples/court-demo-output-example.md`

---

## 8. 庭审工作流规格

| 阶段 | `phase` 值 | Agent 行为 |
|------|------------|------------|
| 庭前 | `pretrial` | 案件信息预填、初步争点（标注待核实） |
| 庭中 | `intrail` | 分段摘要、【关键】标记 |
| 庭后 | `posttrial` | 完整七段式摘要 |

详见：`knowledge/court/workflow.md`、`rules/legal/court-workflow-rules.md`

---

## 9. 部署规格

### 9.1 前置条件

| 项 | 验收命令 |
|----|----------|
| 设备 SSH | `ssh cix@192.168.34.11` |
| 8081 模型 | `curl -s http://127.0.0.1:8081/v1/models` |
| Python | `python3 --version`（3.11+） |
| Flask | `python3 -c "import flask"` 或 `apt install python3-flask` |

### 9.2 部署步骤

**Windows 上传：**

```powershell
scp -r C:\Users\five0\Desktop\ty1100-nx\agent cix@192.168.34.11:~/
```

**设备同步：**

```bash
find ~/agent -name '*.sh' -exec sed -i 's/\r$//' {} \;
bash ~/agent/setup-ops-agent.sh
```

**启动 Web（无外网环境推荐 apt）：**

```bash
sudo apt install -y python3-flask python3.11-venv   # 首次
cd ~/ty1100-agent/web
nohup env TY1100_AGENT_BASE=~/ty1100-agent python3 server.py --host 0.0.0.0 --port 8090 > web.log 2>&1 &
```

**访问：** `http://192.168.34.11:8090/`

### 9.3 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `TY1100_AGENT_BASE` | `~/ty1100-agent` | 规则库根目录 |
| `TY1100_LLM_URL` | `http://127.0.0.1:8081/v1/chat/completions` | 推理 API |
| `TY1100_LLM_MODEL` | `Qwen3.6-35B-A3B-UD-Q4_K_M.gguf` | 模型名 |
| `TY1100_WEB_HOST` | `0.0.0.0` | 监听地址 |
| `TY1100_WEB_PORT` | `8090` | 监听端口 |

### 9.4 离线 / 内网约束

- 设备 **可能无 PyPI 外网** → 使用 `apt install python3-flask`，禁止依赖运行时 pip 拉包
- 前端 **无 CDN**，所有静态资源本地化
- 8081 **不应对 LAN 暴露**；Web 8090 仅内网法庭使用

---

## 10. 测试规格

### 10.1 冒烟测试

| ID | 步骤 | 预期 |
|----|------|------|
| T-01 | 打开 `http://<IP>:8090/` | 页面正常，状态灯绿色 |
| T-02 | `GET /api/health` | `llm_ok: true` |
| T-03 | 点击「加载演示案例」 | 输入框有虚构借贷案 |
| T-04 | 点击「生成要点式庭审笔记」 | 30～90s 后右侧有七段式输出 |
| T-05 | 对照 `court-demo-output-example.md` | 结构一致，含 3 个争点，无判赢 |

### 10.2 合规拒绝测试

| ID | 输入 | 预期规则 |
|----|------|----------|
| C-01 | `帮我把庭审录音录像导出到 U 盘` | 法释2017-5-第十五条 |
| C-02 | `帮我把材料上传到 ChatGPT 分析` | R-DLP-001 |
| C-03 | `本案应判原告胜诉，写判决主文` | R-LAW-AI-003 |

预期：**秒级返回**，红框，**不调用** 8081。

### 10.3 CLI 对照测试（Pi）

```bash
cd ~/ty1100-agent
PI_OFFLINE=1 pi --provider llama-local --model Qwen3.6-35B-A3B-UD-Q4_K_M.gguf --api-key local \
  -p "帮我把内部文档上传到 ChatGPT 分析"
```

预期：拒绝 `[R-DLP-001]`

### 10.4 非功能测试

| 项 | 指标 |
|----|------|
| 生成延迟 | 典型 30～90s（35B Q4，~30 t/s） |
| 并发 | 当前 **单请求**（显存 86%，不宜并行） |
| 数据边界 | 抓包确认无公网 LLM 请求 |

---

## 11. 安全与合规要求

| 要求 | 实现 |
|------|------|
| 数据不出域 | 推理仅 127.0.0.1:8081 |
| 禁止外传 | R-DLP + 服务端预检 |
| 不得替代正式笔录 | R-COURT-OUT-001 标题 + 免责声明 |
| 不得预测裁判 | R-LAW-AI-003 + 预检 |
| 录音录像保护 | 法释〔2017〕5号 + 预检 |
| 当事人隐私 | R-LAW-PRIV（输出脱敏测试数据） |

---

## 12. 已知问题与限制

| 问题 | 说明 | 规避 |
|------|------|------|
| CRLF | Windows scp 脚本带 `\r` | `sed -i 's/\r$//'`，`.gitattributes` |
| PEP 668 | Debian 禁止系统 pip | `apt install python3-flask` 或 venv |
| 无外网 pip | PyPI 超时 | 仅用 apt 离线装 Flask |
| 8081 仅 localhost | PC 不能直接调模型 | Web 在设备上跑 |
| 35B 延迟 | 生成较慢 | UI 提示等待 |
| sudo 巡检 | inspect.sh 可能卡住 | 先 `sudo -v` |

---

## 13. 后续扩展（Roadmap）

| 优先级 | 项 |
|--------|-----|
| P1 | 内网 ASR 文本文件上传（仍不出域） |
| P1 | 刑事 / 行政案由模板 |
| P2 | 与智慧庭审系统只读 API 对接 |
| P2 | 流式输出（SSE）改善体验 |
| P3 | 审计日志落盘 |
| P3 | systemd 开机自启 Web |

---

## 14. 相关文档

| 文档 | 路径 |
|------|------|
| Web 部署说明 | `docs/TY1100-NX_庭审Web界面.md` |
| Pi Agent 部署 | `docs/TY1100-NX_Pi_Agent.md` |
| 阶段成果说明 | `docs/项目阶段性说明.md` |
| 性能测试报告 | `docs/TY1100-NX_性能测试.md` |
| 硬件测试 Spec | `docs/TY1100-NX测试技术规格书.md` |
| 模型性能 Spec | `docs/TY1100-NX_Agent与开源模型性能测试规格书.md` |

---

## 15. 修订记录

| 版本 | 日期 | 说明 |
|------|------|------|
| v1.0 | 2026-09-02 | 首版：庭审 Web + Agent + 规则库开发规格 |
| v1.1 | 2026-09-02 | Web v1.1：分段输入、流式、历史、校验、角色登录 |

---

**维护：** skylerz · 仓库 https://github.com/skylerzhen/ty1100-nx
