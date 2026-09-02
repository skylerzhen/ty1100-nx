#!/bin/bash
# 启动庭审辅助 Web 界面（设备上运行）
set -e

sed -i 's/\r$//' "$0" 2>/dev/null || true

BASE=~/ty1100-agent
WEB_DIR="$BASE/web"
VENV_DIR="$WEB_DIR/.venv"

if [ ! -f "$WEB_DIR/server.py" ]; then
  echo "错误: 未找到 $WEB_DIR/server.py"
  echo "请先运行: bash ~/agent/setup-ops-agent.sh"
  exit 1
fi

export TY1100_AGENT_BASE="$BASE"
export TY1100_WEB_HOST="${TY1100_WEB_HOST:-0.0.0.0}"
export TY1100_WEB_PORT="${TY1100_WEB_PORT:-8090}"

bash "$BASE/scripts/gen-web-tls.sh" 2>/dev/null || true
SSL_ARGS=""
WEB_SCHEME="http"
if [ -f "$WEB_DIR/certs/cert.pem" ] && [ -f "$WEB_DIR/certs/key.pem" ]; then
  SSL_ARGS="--ssl-cert $WEB_DIR/certs/cert.pem --ssl-key $WEB_DIR/certs/key.pem"
  WEB_SCHEME="https"
fi

# Debian 12 禁止 pip 装到系统 Python（PEP 668），使用虚拟环境
if [ ! -d "$VENV_DIR" ]; then
  echo "→ 创建 Python 虚拟环境…"
  python3 -m venv "$VENV_DIR"
fi

if ! "$VENV_DIR/bin/python" -c "import flask" 2>/dev/null; then
  echo "→ 安装 Flask（venv）…"
  "$VENV_DIR/bin/pip" install -r "$WEB_DIR/requirements.txt"
fi

cd "$WEB_DIR"
echo "→ 庭审辅助 Web: ${WEB_SCHEME}://${TY1100_WEB_HOST}:${TY1100_WEB_PORT}/"
echo "  本机: ${WEB_SCHEME}://127.0.0.1:${TY1100_WEB_PORT}/"
echo "  局域网: ${WEB_SCHEME}://$(hostname -I | awk '{print $1}'):${TY1100_WEB_PORT}/"
exec "$VENV_DIR/bin/python" server.py --host "$TY1100_WEB_HOST" --port "$TY1100_WEB_PORT" $SSL_ARGS
