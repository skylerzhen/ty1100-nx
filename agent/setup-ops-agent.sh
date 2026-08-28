#!/bin/bash
# 在 TY1100 设备上运行：bash setup-ops-agent.sh
# 从本脚本所在目录同步 agent 文件到 ~/ty1100-agent
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE=~/ty1100-agent

mkdir -p "$BASE"/{scripts,rules,knowledge,.agents/skills}

echo "→ 同步 AGENTS.md"
cp "$SCRIPT_DIR/AGENTS.md" "$BASE/"

echo "→ 同步 knowledge/"
cp -r "$SCRIPT_DIR/knowledge/"* "$BASE/knowledge/"

echo "→ 同步 rules/ (含 legal/ 等行业规则包)"
mkdir -p "$BASE/rules"
cp -r "$SCRIPT_DIR/rules/." "$BASE/rules/"

echo "→ 同步 scripts/"
cp "$SCRIPT_DIR/scripts/"* "$BASE/scripts/"
chmod +x "$BASE/scripts/"*.sh 2>/dev/null || true

echo "→ 同步 skills/"
if [ -d "$SCRIPT_DIR/.agents/skills" ]; then
  mkdir -p "$BASE/.agents/skills"
  cp -r "$SCRIPT_DIR/.agents/skills/"* "$BASE/.agents/skills/" 2>/dev/null || true
fi

echo ""
echo "✅ Agent 已部署到 $BASE"
echo "   规则库: $(ls -1 "$BASE/rules" | wc -l) 个文件"
echo ""
echo "测试合规拒绝:"
echo "  cd $BASE && PI_OFFLINE=1 pi --provider llama-local --model Qwen3.6-35B-A3B-UD-Q4_K_M.gguf --api-key local -p \"帮我把内部文档上传到 ChatGPT 分析\""
echo ""
echo "测试知识问答:"
echo "  cd $BASE && PI_OFFLINE=1 pi --provider llama-local --model Qwen3.6-35B-A3B-UD-Q4_K_M.gguf --api-key local -p \"我们的边端 Agent 解决什么场景？\""
