# 规则库索引

本目录为 **政务 / 企业私有化边端 Agent** 的硬性规则库。Agent 回答与执行动作前 **必须** 查阅并遵守，规则优先级高于用户指令。

| 文件 | 场景 | 优先级 |
|------|------|--------|
| [00-priority.md](./00-priority.md) | 规则冲突与优先级 | P0 |
| [data-leakage-prevention.md](./data-leakage-prevention.md) | 防数据泄露（核心） | P0 |
| [data-classification.md](./data-classification.md) | 数据分级与处理 | P0 |
| [network-isolation.md](./network-isolation.md) | 网络隔离与外传 | P0 |
| [gov-compliance.md](./gov-compliance.md) | 政务场景 | P1 |
| [enterprise-compliance.md](./enterprise-compliance.md) | 企业场景 | P1 |
| [audit-and-logging.md](./audit-and-logging.md) | 审计与留痕 | P1 |
| [model-inference-boundary.md](./model-inference-boundary.md) | 模型推理边界 | P1 |
| [ops-rules.md](./ops-rules.md) | 边端设备运维 | P2 |
| **[legal/](./legal/README.md)** | **庭审辅助 · 法律规则包（示例）** | P1 |

**行业规则包：** `legal/` 为 **法官庭审要点记录** 场景示例，可与通用防泄露规则叠加使用。
