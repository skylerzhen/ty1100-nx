#!/bin/bash
# Restart local ASR service (FunASR :8091)
set -e
sed -i 's/\r$//' "$0" 2>/dev/null || true

BASE=~/ty1100-agent/asr

if [ ! -f "$BASE/asr_server.py" ]; then
  echo "ERROR: missing $BASE/asr_server.py — run install-asr.sh first"
  exit 1
fi

if [ ! -d "$BASE/.venv" ]; then
  echo "ERROR: missing ASR venv — run bash ~/agent/asr/install-asr.sh"
  exit 1
fi

pkill -f 'asr_server.py' 2>/dev/null || true
fuser -k 8091/tcp 2>/dev/null || true
sleep 1

cd "$BASE"
export TY1100_ASR_DEVICE="${TY1100_ASR_DEVICE:-cpu}"
export TY1100_ASR_MODEL_DIR="${TY1100_ASR_MODEL_DIR:-$BASE/models/sherpa-onnx-paraformer-zh-2023-09-14}"

if ! "$BASE/.venv/bin/python" -c "import fastapi, sherpa_onnx" 2>/dev/null; then
  echo "ERROR: ASR venv incomplete — run: bash ~/agent/asr/install-asr.sh"
  exit 1
fi
nohup .venv/bin/python asr_server.py --host 0.0.0.0 --port 8091 > asr.log 2>&1 &
sleep 5

CODE=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8091/health || echo 000)
BODY=$(curl -s http://127.0.0.1:8091/health || echo '{}')
READY=$(echo "$BODY" | grep -o '"ready":[^,}]*' | head -1 || echo '')

echo "HTTP /health = $CODE $READY"
if [ "$CODE" != "200" ]; then
  echo "ERROR: ASR not ready"
  tail -40 "$BASE/asr.log" || true
  exit 1
fi
echo "ASR restarted OK"
