# TY1100-NX Pi Agent 部署文档

| 项目 | 内容 |
|------|------|
| **文档日期** | 2026-08-27 |
| **设备** | TY1100-NX（cix-localhost） |
| **固定 IP** | 192.168.34.10 |
| **Agent 底座** | Pi（pi-coding-agent），非 OpenClaw |
| **本地模型** | Qwen3.6-35B-A3B（llama.cpp，8081） |

---

## 1. 背景与目标

Leader 要求在 TY1100-NX 上搭建 Agent，使用 **Pi 做底座**，场景为 **简单知识库 / 规则库**，对接设备上已有的本地大模型。

已完成：

- 设备环境验收与性能测试（llama.cpp ~30 tokens/s）
- Pi Agent 安装与本地模型对接
- 知识库 + 规则库 + 运维巡检脚本（项目骨架）
- 固定 IP，便于远程 SSH

未完成（后续）：

- 运维 Agent 一键巡检完整联调（sudo 密码交互待优化）
- OpenClaw 部署（Leader 明确改用 Pi）
- 向量 RAG / Web 界面

---

## 2. 设备与网络

### 2.1 访问方式

```powershell
# Windows SSH
ssh cix@192.168.34.10
# 密码：cix
```

### 2.2 固定 IP 配置

| 项目 | 值 |
|------|-----|
| 网卡 | enp49s0 |
| IP | 192.168.34.10/24 |
| 网关 | 192.168.34.1 |
| 连接名 | 有线连接 3 |

配置方式：`nmcli` 静态 IP（`ipv4.method manual`）。重启后 IP 不变。

### 2.3 硬件概要

| 项目 | 规格 |
|------|------|
| GPU | Iluvatar MR-V100，32GB 显存 |
| CPU | 12 核 ARM64 |
| 内存 | 15 GiB + 16 GiB SWAP |
| SDK | CoreX 4.4.0 |
| Docker | 29.6.0（需 sudo） |

---

## 3. 本地大模型服务（已有）

设备预装 **llama** Docker 容器，无需重复部署。

| 项目 | 值 |
|------|-----|
| 容器名 | llama |
| 模型 | Qwen3.6-35B-A3B-UD-Q4_K_M.gguf（Q4_K_M） |
| 端口 | **8081** |
| API | OpenAI 兼容 `/v1/chat/completions` |

### 3.1 调用示例

```bash
curl -s http://127.0.0.1:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"你好"}],"max_tokens":128,"chat_template_kwargs":{"enable_thinking":false}}'
```

### 3.2 重要说明

Qwen3.6 为思考型模型，**必须**设置 `chat_template_kwargs.enable_thinking=false`，否则 `content` 为空，输出全在 `reasoning_content`。

### 3.3 性能（2026-08-27 实测）

| 指标 | 值 |
|------|-----|
| 生成吞吐 | ~30 tokens/s |
| 官方 vLLM 35B 基准 | 30.34 tokens/s |

详见：`TY1100-NX_性能测试.md`

---

## 4. Pi Agent 安装

### 4.1 安装命令

```bash
sudo npm install -g --ignore-scripts @earendil-works/pi-coding-agent
pi --version   # 实测 0.84.3
```

### 4.2 本地模型配置

文件：`~/.pi/agent/models.json`

```json
{
  "providers": {
    "llama-local": {
      "baseUrl": "http://127.0.0.1:8081/v1",
      "api": "openai-completions",
      "apiKey": "local",
      "compat": {
        "supportsDeveloperRole": false,
        "supportsReasoningEffort": false
      },
      "models": [
        {
          "id": "Qwen3.6-35B-A3B-UD-Q4_K_M.gguf",
          "name": "Qwen3.6-35B Local",
          "reasoning": false,
          "contextWindow": 130000,
          "maxTokens": 4096
        }
      ]
    }
  }
}
```

### 4.3 启动 Pi（推荐离线模式）

**单次问答（print 模式，测完即退）：**

```bash
cd ~/ty1100-agent
PI_OFFLINE=1 pi --provider llama-local \
  --model Qwen3.6-35B-A3B-UD-Q4_K_M.gguf \
  --api-key local \
  -p "你的问题"
```

**交互模式：**

```bash
cd ~/ty1100-agent
PI_OFFLINE=1 pi --provider llama-local \
  --model Qwen3.6-35B-A3B-UD-Q4_K_M.gguf \
  --api-key local
```

交互模式退出：`Ctrl+C` 连按两次，或输入 `/quit`。

### 4.4 可选依赖

Pi 工具链建议安装（消除 fd/ripgrep 警告）：

```bash
sudo apt install -y ripgrep fd-find
```

---

## 5. Agent 项目结构

设备路径：`~/ty1100-agent/`

桌面备份：`C:\Users\five0\Desktop\ty1100-agent\`

```
ty1100-agent/
├── AGENTS.md                    # Agent 行为规则（Pi 启动自动加载）
├── knowledge/
│   └── ty1100-nx.md             # 设备知识库
├── rules/
│   └── ops-rules.md             # 运维硬性规则与告警阈值
├── scripts/
│   └── inspect.sh               # 一键巡检脚本
├── .agents/skills/inspect/
│   └── SKILL.md                 # Pi Skill：识别「巡检」意图
└── setup-ops-agent.sh           # 一键安装/更新脚本
```

### 5.1 安装 / 更新项目文件

**Windows 上传：**

```powershell
scp C:\Users\five0\Desktop\ty1100-agent\setup-ops-agent.sh cix@192.168.34.10:~/
```

**设备执行：**

```bash
bash ~/setup-ops-agent.sh
```

### 5.2 知识库（knowledge/）

记录设备静态信息：型号、IP、GPU、API 端口、性能、使用规则等。

验证问题示例：

- 「TY1100 的固定 IP 是多少？」
- 「推理 API 端口是多少？」

### 5.3 规则库（rules/）

硬性约束，Agent 回答时需遵守：

- 显存 >85% 禁止建议再起第二个大模型
- API 调用必须 `enable_thinking=false`
- Docker 需 sudo
- GPU 温度 / 显存 / 磁盘 / API 响应告警阈值

### 5.4 运维巡检（scripts/inspect.sh）

检查项：GPU（ixsmi）、Docker 容器、8081 API、内存、磁盘、端口监听。

```bash
sudo -v   # 先缓存 sudo，避免脚本卡住
bash ~/ty1100-agent/scripts/inspect.sh
```

### 5.5 Agent 能力说明

| 能力 | 实现方式 |
|------|----------|
| 知识库问答 | 读 `knowledge/` + AGENTS.md 约束 |
| 规则约束 | 读 `rules/ops-rules.md` |
| 实时运维 | Pi `bash` 工具执行 inspect.sh 或 ixsmi/docker 等 |
| 本地推理 | 8081 llama API，经 Pi models.json |

---

## 6. 已验证结果

| 测试项 | 结果 |
|--------|------|
| SSH 远程管理 | 通过 |
| 8081 推理 API | 通过（200） |
| Pi 接本地模型 | 通过 |
| 知识库问答（IP/端口） | 通过，答案正确 |
| 关 thinking 后中文回复 | 通过 |
| 固定 IP | 已配置 |
| setup-ops-agent.sh 上传 | 通过 |
| 运维巡检 Agent 联调 | **待完成**（sudo 交互问题） |

---

## 7. 给 Leader 的汇报要点

1. **TY1100-NX 边端环境可用**，35B 本地模型推理约 30 tokens/s，与官方基准同量级。
2. **按指示用 Pi（非 OpenClaw）搭建了 Agent**，对接本地 Qwen3.6-35B。
3. **场景**：知识库 + 规则库 + 运维巡检脚本，支持设备信息问答，可扩展为实时查 GPU/容器/API。
4. **固定 IP** 192.168.34.10，后续远程开发无需显示器。

---

## 8. 后续待办

- [ ] 解决 inspect.sh 的 sudo 免密或预先 `sudo -v`
- [ ] 完成「请执行一键巡检并总结」Agent 联调
- [ ] 测试人员姓名写入性能报告
- [ ] 可选：cix 加入 docker 组，省去 sudo
- [ ] 可选：简易 HTTP 接口包装 Pi print 模式
- [ ] 可选：向量 RAG（文档量大时）

---

## 9. 常见问题

| 问题 | 处理 |
|------|------|
| API 返回 404 | 检查端口 8081、路径 `/v1/chat/completions` |
| content 为空 | 加 `enable_thinking: false` |
| npm 全局安装 EACCES | 加 `sudo` |
| Pi 里 Ctrl+C 无反应 | 连按两次 Ctrl+C，或 `/quit` |
| scp 在设备里跑失败 | scp 要在 **Windows PowerShell** 执行，不是 SSH 里 |
| inspect.sh 卡住 | 先 `sudo -v` 输入密码 |
| 显存 86% | 不宜再起第二个大模型 |

---

## 10. 相关文件（桌面）

| 文件 | 说明 |
|------|------|
| `TY1100-NX_性能测试.md` | 性能测试定稿 |
| `TY1100-NX项目指南.md` | 项目总览 |
| `ty1100-agent/` | Agent 项目源码备份 |
| `TY1100-NX_Pi_Agent部署文档.md` | 本文档 |

---

**文档状态：** 2026-08-27 整理，涵盖 Pi Agent + 知识库/规则库/运维骨架部署。
