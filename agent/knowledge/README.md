# 知识库索引

Agent 回答前查阅本目录，获取 **机构事实、场景说明、设备信息**。规则约束见 `rules/`；冲突时 **规则优先于知识库**。

## 当前主场景：法院庭审辅助（上海试点对齐）

| 文件 | 说明 |
|------|------|
| **[court/README.md](./court/README.md)** | **庭审场景总入口**（工作流、角色、输入格式） |
| [court/workflow.md](./court/workflow.md) | 庭前 / 庭中 / 庭后工作流 |
| [court/roles.md](./court/roles.md) | 法官、书记员、代理人等角色与权限 |
| [court/input-guide.md](./court/input-guide.md) | ASR 转写、材料粘贴、分段输入规范 |
| [court/glossary.md](./court/glossary.md) | 庭审常用术语 |
| [legal-court-scenario.md](./legal-court-scenario.md) | 场景定义与智慧法院关系 |
| [shanghai-court-official.md](./shanghai-court-official.md) | 上海庭审记录改革官方要点 |
| [samples/court-demo-input.md](./samples/court-demo-input.md) | 虚构民事借贷 Demo 输入 |
| [samples/court-demo-output-example.md](./samples/court-demo-output-example.md) | 期望输出样例（黄金参考） |

## 设备与部署

| 文件 | 说明 |
|------|------|
| [ty1100-nx.md](./ty1100-nx.md) | 边端设备、推理 API、性能 |
| [deployment-scenario.md](./deployment-scenario.md) | 政务 / 企业私有化部署说明 |

## 使用顺序（庭审请求）

1. 确认用户角色 → `court/roles.md`
2. 判断所处阶段 → `court/workflow.md`
3. 按输入规范处理材料 → `court/input-guide.md`
4. 上海场景 → `shanghai-court-official.md`
5. 结构化输出 → 配合 `rules/legal/legal-record-elements.md`
