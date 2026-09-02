#!/bin/bash
# 在 TY1100 设备上运行：bash setup-ops-agent.sh
# 从本脚本所在目录同步 agent 文件到 ~/ty1100-agent
set -e

# Windows 上传时可能带 CRLF，先自愈
sed -i 's/\r$//' "$0" 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE=~/ty1100-agent

mkdir -p "$BASE"/{scripts,rules,knowledge,.agents/skills}

echo "→ 同步 AGENTS.md"
cp "$SCRIPT_DIR/AGENTS.md" "$BASE/"

echo "→ 同步 knowledge/"
mkdir -p "$BASE/knowledge"
cp -r "$SCRIPT_DIR/knowledge/." "$BASE/knowledge/"

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

echo "→ 同步 web/ (交互前端)"
if [ -d "$SCRIPT_DIR/web" ]; then
  mkdir -p "$BASE/web"
  cp -r "$SCRIPT_DIR/web/." "$BASE/web/"
  chmod +x "$BASE/web/start-web.sh" 2>/dev/null || true
  find "$BASE/web" -name '*.sh' -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
fi

echo "→ 同步 systemd/"
if [ -d "$SCRIPT_DIR/systemd" ]; then
  mkdir -p "$BASE/systemd"
  cp -r "$SCRIPT_DIR/systemd/." "$BASE/systemd/"
fi

echo "→ 同步 eval/"
if [ -d "$SCRIPT_DIR/eval" ]; then
  mkdir -p "$BASE/eval"
  cp -r "$SCRIPT_DIR/eval/." "$BASE/eval/"
fi

echo "→ 同步 asr/ (本地 FunASR 服务)"
if [ -d "$SCRIPT_DIR/asr" ]; then
  mkdir -p "$BASE/asr"
  cp -r "$SCRIPT_DIR/asr/." "$BASE/asr/"
  chmod +x "$BASE/asr/install-asr.sh" 2>/dev/null || true
  find "$BASE/asr" -name '*.sh' -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
fi

echo ""
echo "✅ Agent 已部署到 $BASE"
LEGAL_MD=$(find "$BASE/rules/legal" -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l)
echo "   法律规则 md 文件: $LEGAL_MD 个"
echo "   规则库顶层: $(ls -1 "$BASE/rules" | wc -l) 项"
echo ""
echo "启动 Web 界面:"
echo "  bash $BASE/web/start-web.sh"
echo "  浏览器访问 http://<设备IP>:8090/"
