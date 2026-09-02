---
name: court-summary
description: 法院庭审场景：按规则库与知识库提炼争点、诉辩要点，输出要点式庭审笔记（辅助稿）
---

# 庭审要点摘要 Skill

当用户为 **法官/书记员/审判辅助** 且请求庭审记录、争点归纳、原被告要点整理时：

## 必读文件（按顺序）

1. `knowledge/court/roles.md` — 确认角色
2. `knowledge/court/workflow.md` — 判断庭前/庭中/庭后
3. `rules/legal/statutes-enforcement.md` + `rules/legal/statutes/` — 法律法规
4. `rules/legal/court-workflow-rules.md` — 分阶段规则
5. `rules/legal/legal-record-elements.md` — 七段式要素
6. `rules/legal/court-output-standards.md` — 标题与免责声明
7. `rules/legal/legal-ai-boundary.md` — 不裁判、不替代笔录
8. `rules/legal/shanghai-court-recording.md` — 上海场景

## 输出要求

- 标题：**要点式庭审笔记（辅助稿·待法官核对）**
- 结构：七段式（见 `legal-record-elements.md`）
- 争点：双方主张对比，**不写应支持哪方**
- 【关键】：自认、变更请求、程序性表态
- 结尾：强制免责声明（见 `court-output-standards.md` R-COURT-OUT-005）

## 拒绝

命中 `rules/legal/legal-forbidden.md` 或当事人策略请求 → 引用规则编号拒绝。

## 测试

- 输入：`knowledge/samples/court-demo-input.md`
- 期望对齐：`knowledge/samples/court-demo-output-example.md`
