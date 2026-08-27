#!/bin/bash
# 在 TY1100 设备上运行：bash setup-ops-agent.sh
set -e

BASE=~/ty1100-agent
mkdir -p "$BASE"/{scripts,rules,knowledge,.agents/skills/inspect}

cat > "$BASE/AGENTS.md" << 'EOF'
# TY1100-NX 边端运维 Agent

你是 TY1100-NX 边端 AI 设备的运维与知识助手。

## 工作方式

1. **知识问答**：优先查阅 `knowledge/` 目录下的文档
2. **规则约束**：必须遵守 `rules/` 目录下的硬性规则
3. **实时状态**：用户问 GPU、容器、API、内存、磁盘等实时信息时，用 `bash` 工具执行：
   - 一键巡检：`bash scripts/inspect.sh`
   - 或单独命令：`ixsmi`、`sudo docker ps`、`free -h`、`df -h /`
4. **API 测试**：测试推理服务时使用 `chat_template_kwargs.enable_thinking=false`

## 回答要求

- 用中文，结构清晰（可用表格/列表）
- 巡检结果需提炼：正常 / 警告 / 异常，并给出建议
- 知识库没有的信息，明确说「知识库未记录」
- 执行命令前说明要查什么；只读命令可直接执行

## 禁止

- 禁止建议在显存占用 >85% 时再加载 27B 以上模型
- 禁止建议关闭生产中的 llama 容器而不说明影响
- 禁止编造设备 IP、端口、性能数据
EOF

cat > "$BASE/knowledge/ty1100-nx.md" << 'EOF'
# TY1100-NX 设备知识库

## 基本信息
- 型号：TY1100-NX 边端 AI 算力终端
- 固定 IP：192.168.34.10
- GPU：Iluvatar MR-V100，32GB 显存
- CPU：12 核 ARM64
- 系统：Debian，CoreX SDK 4.4.0

## 推理服务
- 框架：llama.cpp（Docker 容器 llama）
- 模型：Qwen3.6-35B-A3B（Q4_K_M 量化）
- API：http://127.0.0.1:8081/v1/chat/completions
- 性能：约 30 tokens/s

## 使用规则
- 调用 API 时须加 chat_template_kwargs.enable_thinking=false，否则 content 为空
- 显存占用约 86%，不宜同时加载第二个大模型
- Docker 操作需要 sudo
- SSH：cix@192.168.34.10
EOF

cat > "$BASE/scripts/inspect.sh" << 'EOF'
#!/bin/bash
echo "=== TY1100-NX 巡检报告 ==="
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "主机: $(hostname)"
echo ""
echo "=== GPU ==="
ixsmi 2>/dev/null | head -25 || echo "ixsmi 不可用"
echo ""
echo "=== Docker 容器 ==="
sudo docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" 2>/dev/null || docker ps -a
echo ""
echo "=== 8081 推理 API ==="
curl -s --max-time 30 -o /dev/null -w "HTTP %{http_code} | 耗时 %{time_total}s\n" \
  http://127.0.0.1:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"ping"}],"max_tokens":8,"chat_template_kwargs":{"enable_thinking":false}}' \
  || echo "8081 API 不可达或超时"
echo ""
echo "=== 内存 ==="
free -h
echo ""
echo "=== 磁盘 (/) ==="
df -h /
echo ""
echo "=== 监听端口 ==="
ss -tlnp 2>/dev/null | grep -E '8081|18789' || sudo ss -tlnp 2>/dev/null | grep -E '8081|18789' || true
echo ""
echo "=== 巡检完成 ==="
EOF
chmod +x "$BASE/scripts/inspect.sh"

cat > "$BASE/rules/ops-rules.md" << 'EOF'
# TY1100-NX 运维硬性规则

## 显存与模型
- 显存占用 > 85%：禁止建议并行加载第二个 27B 以上模型
- 显存占用 > 90%：必须警告 OOM 风险

## API 调用
- Qwen3.6 调用必须设置 enable_thinking=false
- 推理 API 端口：8081

## Docker
- docker 命令需要 sudo
- 停止 llama 容器会导致 8081 中断

## 告警阈值
- GPU 温度警告 >75°C，异常 >85°C
- 显存警告 >85%，异常 >95%
- 8081 响应 >10s 为警告，不可达为异常
EOF

cat > "$BASE/.agents/skills/inspect/SKILL.md" << 'EOF'
---
name: inspect
description: TY1100-NX 一键巡检 GPU、Docker、API、内存、磁盘
---
用户要求巡检或查设备状态时，执行 bash scripts/inspect.sh，对照 rules/ops-rules.md 给出正常/警告/异常结论。
EOF

echo "✅ 运维 Agent 文件已更新"
echo "测试巡检: bash $BASE/scripts/inspect.sh"
echo "测试 Agent: cd $BASE && PI_OFFLINE=1 pi --provider llama-local --model Qwen3.6-35B-A3B-UD-Q4_K_M.gguf --api-key local -p \"请执行一键巡检并总结结果\""
