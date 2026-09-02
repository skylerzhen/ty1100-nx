#!/bin/bash
# Restart court Web on device (called from Windows deploy-from-windows.ps1 via ssh)
set -e

sed -i 's/\r$//' "$0" 2>/dev/null || true

BASE=~/ty1100-agent
WEB="$BASE/web"

if [ ! -f "$WEB/server.py" ]; then
  echo "ERROR: missing $WEB/server.py — run setup-ops-agent.sh first"
  exit 1
fi

if [ ! -f "$WEB/legal_retriever.py" ]; then
  echo "ERROR: missing legal_retriever.py — deploy latest agent/web first"
  exit 1
fi

if ! grep -q 'api/legal/index' "$WEB/server.py"; then
  echo "ERROR: server.py is old (no /api/legal/index)"
  exit 1
fi

if ! grep -q 'stream_audit' "$WEB/server.py"; then
  echo "ERROR: server.py is old (no stream_audit fix) — redeploy agent/web"
  exit 1
fi

pkill -f 'ty1100-agent/web' 2>/dev/null || true
pkill -f 'server.py --host' 2>/dev/null || true
pkill -f 'server.py --port 8090' 2>/dev/null || true
fuser -k 8090/tcp 2>/dev/null || true
sleep 2

cd "$WEB"
if [ ! -d .venv ]; then
  python3 -m venv .venv
fi
.venv/bin/pip install -q -r requirements.txt 2>/dev/null || true

export TY1100_AGENT_BASE="$BASE"
export TY1100_ASR_URL="${TY1100_ASR_URL:-http://127.0.0.1:8091}"

bash "$BASE/scripts/gen-web-tls.sh" 2>/dev/null || true
SSL_ARGS=""
WEB_SCHEME="http"
if [ -f "$WEB/certs/cert.pem" ] && [ -f "$WEB/certs/key.pem" ]; then
  SSL_ARGS="--ssl-cert $WEB/certs/cert.pem --ssl-key $WEB/certs/key.pem"
  WEB_SCHEME="https"
fi

nohup .venv/bin/python server.py --host 0.0.0.0 --port 8090 $SSL_ARGS > web.log 2>&1 &
sleep 3

CURL_TLS=""
[ "$WEB_SCHEME" = "https" ] && CURL_TLS="-k"
ROOT_CODE=$(curl -s $CURL_TLS -o /dev/null -w '%{http_code}' ${WEB_SCHEME}://127.0.0.1:8090/ || echo 000)
HEALTH_JSON=$(curl -s $CURL_TLS ${WEB_SCHEME}://127.0.0.1:8090/api/health || echo '{}')
HEALTH_CODE=$(curl -s $CURL_TLS -o /dev/null -w '%{http_code}' ${WEB_SCHEME}://127.0.0.1:8090/api/health || echo 000)
CHUNKS=$(echo "$HEALTH_JSON" | grep -o '"legal_chunks":[0-9]*' | grep -o '[0-9]*' || echo 0)

echo "${WEB_SCHEME^^} / = $ROOT_CODE"
echo "${WEB_SCHEME^^} /api/health = $HEALTH_CODE"
echo "legal_chunks = $CHUNKS"
if [ "$WEB_SCHEME" = "https" ]; then
  LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  echo "Mic OK URL: https://${LAN_IP}:8090/ (trust cert once in browser)"
fi

if [ "$ROOT_CODE" != "200" ] || [ "$HEALTH_CODE" != "200" ]; then
  echo "ERROR: Web not ready"
  pgrep -af 'server.py' || true
  tail -30 web.log || true
  exit 1
fi

if [ "${CHUNKS:-0}" -lt 50 ]; then
  echo "WARN: legal_chunks low ($CHUNKS) — check rules/legal/ sync"
fi

echo "Web restarted OK"
