# TY1100 庭审辅助 Web 界面

## 功能（v1.1）

- 法官 / 书记员身份选择
- **五段式分 Tab 输入**（法庭调查 / 举证质证 / 辩论 / 陈述 / 庭前）
- 本地 `.txt` 导入（浏览器本地读取，不上传外网）
- **流式输出**（SSE，不支持时自动降级）
- 生成进度条 + 计时
- 复制 / 下载 Markdown
- **七段式结构自动校验**
- **历史记录**（本机 localStorage，最近 5 条）
- 合规预检、Demo、阶段选择

## 部署

### 方式 A：本机 PowerShell 一条龙（**唯一标准方式**）

在项目根目录 `ty1100-nx` 下：

```powershell
cd C:\Users\five0\Desktop\ty1100-nx
.\scripts\deploy-from-windows.ps1
```

自动完成：`scp` 上传 → 远程 `setup` → 远程启动 Web → 提示浏览器地址。

**以后改代码、发版、联调，都用这一条。** 不要 SSH 进设备手动执行 bash。

仅重启 Web：

```powershell
.\scripts\restart-web-remote.ps1
```

### 方式 B：本机跑 Web + 隧道连设备模型（开发调试）

```powershell
.\scripts\dev-local-web.ps1
```

浏览器：`http://127.0.0.1:8090/`（Web 在 PC，8081 经 SSH 隧道）

### 方式 C：手动（不推荐）

<details>
<summary>展开手动步骤</summary>

#### 1. Windows 上传

```powershell
scp -r C:\Users\five0\Desktop\ty1100-nx\agent cix@192.168.34.11:~/
```

#### 2. 远程一条命令（仍在 PowerShell，不交互进设备）

```powershell
ssh cix@192.168.34.11 "find ~/agent -name '*.sh' -exec sed -i 's/\r$//' {} \; ; bash ~/agent/setup-ops-agent.sh"
```

</details>

| 位置 | 地址 |
|------|------|
| 设备本机 | http://127.0.0.1:8090/ |
| 局域网 PC | http://192.168.34.11:8090/ |

## 架构

```
浏览器 → Flask :8090 → 合规预检 → 规则库注入 system prompt → llama.cpp :8081
```

## 目录

```
agent/web/
├── server.py           # API + 静态文件
├── start-web.sh        # 启动脚本
├── requirements.txt    # Flask
└── static/
    ├── index.html
    ├── app.css
    └── app.js
```

## 环境变量（可选）

| 变量 | 默认 |
|------|------|
| `TY1100_AGENT_BASE` | `~/ty1100-agent` |
| `TY1100_LLM_URL` | `http://127.0.0.1:8081/v1/chat/completions` |
| `TY1100_WEB_PORT` | `8090` |

## 注意

- 首次生成约 30～90 秒（35B 本地推理）
- 须先确认 llama 容器在跑：`curl -s http://127.0.0.1:8081/v1/models`
- Web 仅内网使用，勿暴露到公网
