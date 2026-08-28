# Changelog

本仓库遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/) 格式。

## [0.2.0] - 2026-08-28

### Added

- 阶段性成果说明文档 `docs/项目阶段性说明.md`
- 政务/企业防数据泄露规则库（R-DLP / R-GOV / R-ENT 等 9 类规则）
- 部署场景知识库、合规检查 Skill
- setup 脚本改为目录同步，便于扩展行业规则包

### Changed

- AGENTS.md 重构为私有化合规 Agent
- 设备 IP：`192.168.34.9`

## [0.1.0] - 2026-08-27

### Added

- TY1100-NX 设备环境验收与性能测试文档（llama.cpp ~30 tokens/s）
- Pi Agent（pi-coding-agent）对接本地 Qwen3.6-35B（8081 API）
- Agent 项目：`agent/` 目录（知识库、规则库、巡检脚本、Skill）
- Pi 本地模型配置示例：`config/pi-models.json.example`
- 设备固定 IP 配置记录（192.168.34.10）
- 项目指南、测试规格书等参考文档

### Verified

- 8081 OpenAI 兼容 API 可用
- Pi print 模式问答正常
- 知识库问答（IP / 端口 / API 规则）正确

### Known Issues

- `scripts/inspect.sh` 中 `sudo docker` 可能因密码交互卡住，需先执行 `sudo -v`
- 运维 Agent 自动巡检联调未完成
- 设备默认凭据仅用于内网测试，生产环境应修改

## [Unreleased]

### Planned

- 完成运维 Agent 一键巡检联调
- Docker 免 sudo（usermod -aG docker cix）
- 可选：简易 HTTP 接口、向量 RAG

[0.1.0]: https://github.com/skylerzhen/ty1100-nx/releases/tag/v0.1.0
