# 法律法规规则索引（庭审辅助场景）

本目录收录 **写入规则库的法律、司法解释及上海地区规范性文件要点**。Agent 须 **直接遵守** 下列条文；与 `legal-ai-boundary.md` 等场景规则冲突时，**法律法规优先**。

| 文件 | 名称 | 效力 |
|------|------|------|
| 包 | 文件 | 约块数 |
|----|------|--------|
| 庭审录音录像 | fabiao-2017-5-recording.md | 19 |
| 上海改革 | shanghai-hshfy-pilot-2020.md | 10 |
| 民诉法 | civil-procedure-core.md, civil-procedure-trial.md | 26 |
| 证据 | civil-evidence-full.md, civil-evidence-highlights.md | 25 |
| 民法典合同/侵权 | civil-code-contract.md | 20 |
| 民间借贷 | private-lending-2020.md | 15 |
| 婚姻家事 | civil-code-marriage-family.md | 15 |
| 劳动争议 | labor-dispute-law.md | 15 |
| 刑事庭审 | criminal-procedure-trial.md | 20 |
| 行政诉讼 | administrative-litigation.md | 15 |
| 在线诉讼 | online-litigation-rules.md | 15 |
| 个人信息 | personal-info-protection.md | 10 |
| 知识产权 | ip-litigation-highlights.md | 15 |
| 交通事故 | traffic-accident-tort.md | 15 |
| 消费维权 | consumer-protection-law.md | 10 |
| 公司纠纷 | company-law-disputes.md | 15 |
| 执行 | civil-enforcement-procedure.md | 15 |
| 调解 | mediation-people-court.md | 10 |
| 法庭纪律 | court-discipline-rules.md | 15 |
| 仲裁 | arbitration-law.md | 15 |
| 建设工程/房产 | construction-real-estate.md | 15 |
| 场景规则 | rules/legal/*.md | ~54 |

**统计命令：** `python agent/scripts/legal-corpus-stats.py` 或部署后 `.\scripts\legal-corpus-stats.ps1`

**Web 服务检索：** `agent/web/legal_retriever.py` 在 **本机** 索引本目录及 `rules/legal/` 下全部条文，按庭审输入 **离线 BM25+关键词** 匹配后注入 system prompt（不连外网）。

**免责声明：** 条文摘自公开文本；正式适用以国家法律法规数据库及法院最新文件为准。
