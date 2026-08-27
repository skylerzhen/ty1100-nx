---
name: inspect
description: 对 TY1100-NX 边端设备执行一键巡检，检查 GPU、Docker、推理 API、内存、磁盘状态
---

# 设备一键巡检

当用户要求巡检、检查设备状态、看 GPU/容器/API 是否正常时，执行：

```bash
bash scripts/inspect.sh
```

执行完成后：
1. 解析输出中的关键指标
2. 对照 `rules/ops-rules.md` 中的告警阈值
3. 给出 **正常 / 警告 / 异常** 结论和简短建议

若用户只问单项（如「GPU 怎么样」），可只跑对应命令，不必全量巡检。
