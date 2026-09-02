# R-OPS 边端设备运维规则

## 网络

| 项目 | 当前值 |
|------|--------|
| 设备 IP | `192.168.34.11`（静态 IP，绑定固定网口） |
| 网段 | `192.168.34.0/24` |
| 网关 | `192.168.34.1` |

**注意：** 设备双网口，换口可能导致 IP 变化；固定 IP 须绑定当前使用的网口。

## Docker

- docker 命令需要 `sudo`
- 停止 `llama` 容器会导致 8081 推理中断，须 **[R-AUD-001]** 留痕提醒

## 告警阈值

| 指标 | 警告 | 异常 |
|------|------|------|
| GPU 温度 | > 75°C | > 85°C |
| 显存占用 | > 85% | > 95% |
| 根分区磁盘 | > 80% | > 90% |
| 8081 API | 响应 > 10s | 不可达 |

## 部署（固定流程）

**一律在本机 Windows PowerShell 执行，不要 SSH 进设备交互终端。**

| 操作 | 本机命令 |
|------|----------|
| 上传 + 安装 + 启动 Web | `cd ty1100-nx` → `.\scripts\deploy-from-windows.ps1` |
| 仅重启 Web | `.\scripts\restart-web-remote.ps1` |
| 开机自启 systemd | `.\scripts\install-systemd-remote.ps1` |
| 跑评测集 | `.\scripts\run-eval-remote.ps1` |
| 测法律检索 API | `.\scripts\test-legal-api.ps1` |

设备 IP：`192.168.34.11`，网口 `enp1s0`（`有线连接 2`）。  
Web 登录默认：`judge/judge123` 或 `clerk/clerk123`（生产请配置 `web/auth.users.json`）。  
审计日志：`~/ty1100-agent/logs/audit/`。
