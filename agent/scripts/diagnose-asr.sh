#!/bin/bash
# On-device ASR / streaming diagnostics
set -e
sed -i 's/\r$//' "$0" 2>/dev/null || true

echo "--- ASR process ---"
pgrep -af asr_server.py || echo "NO asr_server.py process"

echo "--- port 8091 ---"
ss -tlnp 2>/dev/null | grep 8091 || echo "8091 not listening"

echo "--- ASR /health ---"
curl -s http://127.0.0.1:8091/health || echo "health failed"
echo ""

echo "--- streaming model ---"
D=~/ty1100-agent/asr/models/sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23
if [ -d "$D" ]; then
  ls -lh "$D"/*.onnx "$D"/tokens.txt 2>/dev/null || ls -lh "$D"
else
  echo "MISSING $D"
fi

echo "--- Web streaming route ---"
if grep -q "api/asr/ws" ~/ty1100-agent/web/server.py 2>/dev/null; then
  echo "Web has /api/asr/ws"
else
  echo "Web OLD - no ws route (redeploy web)"
fi

echo "--- flask-sock ---"
if ~/ty1100-agent/web/.venv/bin/python -c "import flask_sock" 2>/dev/null; then
  echo "flask_sock OK"
else
  echo "flask_sock MISSING"
fi

echo "--- web.log (last 5) ---"
tail -5 ~/ty1100-agent/web/web.log 2>/dev/null || true

echo "--- asr.log (last 5) ---"
tail -5 ~/ty1100-agent/asr/asr.log 2>/dev/null || true
