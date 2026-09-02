# 法院庭审辅助 · 知识库总入口

> **部署：** TY1100-NX 边端 + Pi Agent + 本地 Qwen（8081）  
> **数据边界：** 庭审内容 **不出法院内网 / 不上公网**  
> **场景：** 上海及全国法院 **要点式庭审笔记** 辅助（复杂案件）

## 一句话定位

```
正式层：智慧庭审系统（录音录像 + 音字转换 + 元数据表 + 签名入卷）
辅助层：TY1100 本地 Agent（要点归纳 · 争点整理 · 诉辩对比摘要）
```

Agent **不替代** 裁判、书记员法定职责、正式笔录或智慧庭审系统。

## 知识库地图

| 文档 | 何时读 |
|------|--------|
| [workflow.md](./workflow.md) | 庭前准备、庭中分段、庭后整理 |
| [roles.md](./roles.md) | 判断请求者身份与可提供服务范围 |
| [input-guide.md](./input-guide.md) | 如何粘贴 ASR 转写、起诉状摘要 |
| [glossary.md](./glossary.md) | 统一术语（法庭调查、争点、三性等） |
| [../legal-court-scenario.md](../legal-court-scenario.md) | 场景定义、与智慧法院关系 |
| [../shanghai-court-official.md](../shanghai-court-official.md) | 上海改革官方要点 |
| [../samples/court-demo-input.md](../samples/court-demo-input.md) | 测试输入 |
| [../samples/court-demo-output-example.md](../samples/court-demo-output-example.md) | 标准输出样例 |

## 规则库对应（必读）

| 规则 | 内容 |
|------|------|
| `rules/legal/statutes/` | 法释〔2017〕5号等法律法规原文 |
| `rules/legal/legal-record-elements.md` | 七段式输出要素 |
| `rules/legal/legal-ai-boundary.md` | AI 不得裁判、不得替代笔录 |
| `rules/legal/shanghai-court-recording.md` | 上海要点式笔记规则 |
| `rules/legal/court-workflow-rules.md` | 分阶段行为规则 |
| `rules/legal/court-output-standards.md` | 输出格式与免责声明 |
| `rules/legal/legal-party-privacy.md` | 当事人隐私 |
| `rules/legal/legal-forbidden.md` | 禁止行为清单 |

## 典型用户话术 → Agent 动作

| 用户说 | Agent 做 |
|--------|----------|
| 「归纳今天庭审争点」 | 读输入 → 七段式摘要 → 不判输赢 |
| 「整理原被告要点」 | 诉辩对比 + 争点表 |
| 「这段 ASR 转写帮我提炼」 | 按 `input-guide.md` 分段处理 |
| 「帮我写判决主文」 | **拒绝** `[R-LAW-AI-001]`，仅可归纳争点 |
| 「把庭审录音发 ChatGPT」 | **拒绝** `[R-LAW-FBD-001]` |
| 「导出录音到 U 盘」 | **拒绝** `[法释2017-5-第十五条]` |

## Demo 命令（设备上）

### Web 界面（推荐）

```bash
bash ~/ty1100-agent/web/start-web.sh
# 浏览器打开 http://<设备IP>:8090/
```

### 命令行

```bash
cd ~/ty1100-agent
PI_OFFLINE=1 pi --provider llama-local --model Qwen3.6-35B-A3B-UD-Q4_K_M.gguf --api-key local \
  -p "请阅读 knowledge/samples/court-demo-input.md，按 rules/legal/legal-record-elements.md 与 rules/legal/court-output-standards.md 输出要点式庭审笔记"
```
