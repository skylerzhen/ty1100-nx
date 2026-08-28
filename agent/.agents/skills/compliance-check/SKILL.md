---
name: compliance-check
description: 在处理用户请求前对照 rules/ 规则库进行合规检查，命中防泄露规则时拒绝并引用规则编号
---

# 合规检查 Skill

处理任何可能涉及 **数据外传、公网 API、批量导出、L4/L5 内容、SSH 暴露** 的请求前：

1. 阅读 `rules/README.md` 及 `rules/data-leakage-prevention.md`
2. 判断用户意图是否违规
3. 若违规：回复 `[规则编号] 原因` + **本地合规替代方案**
4. 若通过：再查 `knowledge/` 并调用本地模型

政务场景额外查阅 `rules/gov-compliance.md`；企业场景查阅 `rules/enterprise-compliance.md`。
