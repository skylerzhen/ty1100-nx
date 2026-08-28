# TY1100-NX

天数智芯 **TY1100-NX** 边端 AI 终端上的 **开源模型性能测试** 与 **Pi Agent** 部署项目。

基于 **Pi（pi-coding-agent）** 底座，对接本地 **Qwen3.6-35B**（llama.cpp），实现知识库 / 规则库 / 运维巡检场景。

## 项目状态

| 模块 | 状态 |
|------|------|
| 设备环境验收 | ✅ 完成 |
| 35B 推理性能（~30 tokens/s） | ✅ 完成 |
| Pi + 本地模型对接 | ✅ 完成 |
| 知识库 / 规则库 Agent | ✅ 骨架完成 |
| 运维一键巡检 | ⏳ 待联调 |

**版本：** v0.1.0 · 详见 [CHANGELOG.md](./CHANGELOG.md)

## 仓库结构

```
ty1100-nx/
├── agent/                  # Pi Agent 项目（部署到设备 ~/ty1100-agent）
│   ├── AGENTS.md           # Agent 行为规则
│   ├── knowledge/          # 知识库
│   ├── rules/              # 规则库
│   ├── scripts/            # 运维脚本（inspect.sh）
│   ├── .agents/skills/     # Pi Skills
│   └── setup-ops-agent.sh  # 设备端一键安装
├── config/
│   └── pi-models.json.example   # Pi 本地模型配置模板
├── docs/                   # 文档与测试报告
└── CHANGELOG.md
```

## 快速开始

### 1. 连接设备

```powershell
ssh cix@<设备IP>
```

默认内网 IP：`192.168.34.10`（已配置静态 IP）

### 2. 安装 Pi Agent 项目

在 **Windows** 上传安装脚本：

```powershell
scp agent/setup-ops-agent.sh cix@192.168.34.10:~/
```

在 **设备** 执行：

```bash
bash ~/setup-ops-agent.sh
```

### 3. 配置 Pi 本地模型

```bash
mkdir -p ~/.pi/agent
cp ~/ty1100-agent/../config/pi-models.json.example ~/.pi/agent/models.json
# 或从本仓库 config/pi-models.json.example 复制内容
sudo npm install -g --ignore-scripts @earendil-works/pi-coding-agent
```

### 4. 运行 Agent

```bash
cd ~/ty1100-agent
PI_OFFLINE=1 pi --provider llama-local \
  --model Qwen3.6-35B-A3B-UD-Q4_K_M.gguf \
  --api-key local \
  -p "TY1100 的推理 API 端口是多少？"
```

### 5. 一键巡检

```bash
sudo -v
bash ~/ty1100-agent/scripts/inspect.sh
```

## 本地大模型 API

| 项目 | 值 |
|------|-----|
| 端口 | 8081 |
| 路径 | `/v1/chat/completions` |
| 模型 | Qwen3.6-35B-A3B Q4_K_M |

**重要：** 请求须包含 `"chat_template_kwargs":{"enable_thinking":false}`，否则 `content` 为空。

```bash
curl -s http://127.0.0.1:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"你好"}],"max_tokens":64,"chat_template_kwargs":{"enable_thinking":false}}'
```

## 文档

| 文档 | 说明 |
|------|------|
| [docs/项目阶段性说明.md](./docs/项目阶段性说明.md) | **阶段性成果说明（可转发同事）** |
| [docs/TY1100-NX_Pi_Agent.md](./docs/TY1100-NX_Pi_Agent.md) | Pi Agent 部署完整文档 |
| [docs/TY1100-NX_性能测试.md](./docs/TY1100-NX_性能测试.md) | 性能测试报告 |
| [docs/TY1100-NX项目指南.md](./docs/TY1100-NX项目指南.md) | 项目总览与连接指南 |

## 硬件环境

- **设备：** TY1100-NX（Iluvatar MR-V100，32GB 显存）
- **CPU：** 12 核 ARM64
- **SDK：** CoreX 4.4.0
- **推理框架：** llama.cpp（官方 Docker 镜像）

## 开发说明

- Agent 底座：**Pi**（pi-mono / pi-coding-agent），非 OpenClaw
- 设备端项目路径：`~/ty1100-agent`
- 修改 `agent/` 后重新 `scp setup-ops-agent.sh` 或在设备上 `bash setup-ops-agent.sh`

## License

Internal project — 仅供团队内部使用。

## 多设备同步（Cursor / 其他电脑）

仓库托管在 GitHub，任意电脑用 **同一 GitHub 账号** 拉取即可同步。

### 首次在新电脑上获取项目

```powershell
# 1. 克隆（需已登录 GitHub：gh auth login）
git clone https://github.com/skylerzhen/ty1100-nx.git
cd ty1100-nx

# 2. 用 Cursor 打开文件夹
# File → Open Folder → 选择 ty1100-nx 目录
```

或在 Cursor 中：**Clone Repo** → 粘贴 `https://github.com/skylerzhen/ty1100-nx.git`

### 日常同步

**在当前电脑改完并上传：**

```powershell
cd ty1100-nx
git add -A
git commit -m "更新说明"
git push
# 若 push 失败（代理问题）：
git -c http.proxy= -c https.proxy= push
```

**在另一台电脑拉最新：**

```powershell
cd ty1100-nx
git pull
```

Cursor 内置 Source Control 面板也可直接 Pull / Push / Sync。

### 注意

- 仓库为 **Private**，需 GitHub 账号 `skylerzhen` 有访问权限
- 设备 SSH 密码、API Key 等 **不要提交到 Git**（已在 `.gitignore` 排除 `.env`）
- 边端设备上的 `~/ty1100-agent` 需单独用 `scp` 同步，不经过 GitHub

## 作者

skylerz
