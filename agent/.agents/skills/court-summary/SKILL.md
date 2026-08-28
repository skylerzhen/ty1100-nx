---
name: court-summary
description: 按法律规则库提炼庭审中原被告最重要陈述、争议焦点与结构化要点摘要
---

# 庭审要点摘要 Skill

当用户为 **法官/审判辅助** 且请求「记录庭审最重要部分」「归纳争点」「整理原被告要点」时：

1. 必读 `rules/legal/legal-record-elements.md` 与 `rules/legal/legal-ai-boundary.md`
2. 按 **七段式模板** 输出（案件信息、诉辩、争点、举证质证、辩论、最后陈述、无争议/待查明事实）
3. **中立归纳**，不预测裁判结果
4. 结尾加：`本地 AI 辅助生成，待法官核对`
5. 命中 `rules/legal/legal-forbidden.md` 时拒绝并引用规则编号

测试材料见 `knowledge/legal-court-scenario.md`。
