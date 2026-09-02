#!/bin/bash
# Install local sherpa-onnx ASR on TY1100 (CPU, port 8091)
set -e
sed -i 's/\r$//' "$0" 2>/dev/null || true

BASE=~/ty1100-agent/asr
SRC=~/agent/asr
PIP_MIRROR="${TY1100_PIP_MIRROR:-https://pypi.tuna.tsinghua.edu.cn/simple}"
PIP_TIMEOUT="${TY1100_PIP_TIMEOUT:-600}"
MODEL_TAR="sherpa-onnx-paraformer-zh-2023-09-14.tar.bz2"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${MODEL_TAR}"
MODEL_ROOT="$BASE/models/sherpa-onnx-paraformer-zh-2023-09-14"
MIN_TAR_BYTES=210000000
MAX_TAR_BYTES=240000000

if [ -d "$SRC" ]; then
  mkdir -p "$BASE"
  cp -r "$SRC/." "$BASE/"
fi

if [ ! -f "$BASE/asr_server.py" ]; then
  echo "ERROR: missing $BASE/asr_server.py — deploy agent/asr first"
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ERROR: ffmpeg not found — run: sudo apt-get install -y ffmpeg"
  exit 1
fi

model_ready() {
  [ -n "$(find "$BASE/models" -name 'tokens.txt' 2>/dev/null | head -1)" ] && \
  [ -n "$(find "$BASE/models" -name '*.onnx' ! -path '*/test_wavs/*' 2>/dev/null | head -1)" ]
}

ensure_model() {
  if model_ready; then
    echo "→ Model OK under $BASE/models"
    return 0
  fi
  mkdir -p "$BASE/models"
  TMP="$BASE/models/$MODEL_TAR"
  if [ -f "$TMP" ]; then
    SZ=$(stat -c%s "$TMP" 2>/dev/null || echo 0)
    if [ "$SZ" -ge "$MIN_TAR_BYTES" ] && [ "$SZ" -le "$MAX_TAR_BYTES" ]; then
      if tar tjf "$TMP" 2>/dev/null | grep -q '\.onnx' && tar tjf "$TMP" 2>/dev/null | grep -q tokens.txt; then
        echo "→ Extract $MODEL_TAR ($(( SZ / 1024 / 1024 ))MB)"
        rm -rf "$MODEL_ROOT"
        tar xjf "$TMP" -C "$BASE/models"
        model_ready && return 0
        echo "WARN: extract done but files missing"
      else
        echo "WARN: tar invalid (no model.onnx inside), removing"
        rm -f "$TMP"
      fi
    else
      echo "WARN: removing bad tar ($SZ bytes, expect 210-240MB)"
      rm -f "$TMP"
    fi
  fi
  if [ "${TY1100_SKIP_MODEL_DOWNLOAD:-0}" = "1" ]; then
    echo "ERROR: model missing on device."
    echo "  Run on Windows FIRST: .\\scripts\\upload-asr-model.ps1"
    echo "  Then: .\\scripts\\install-asr-remote.ps1"
    find "$BASE/models" -maxdepth 3 -type f 2>/dev/null | head -10 || true
    exit 1
  fi
  echo "→ Download on device (slow). Prefer: upload-asr-model.ps1 on Windows"
  download_ok=0
  for url in \
    "https://ghfast.top/${MODEL_URL}" \
    "https://mirror.ghproxy.com/${MODEL_URL}" \
    "${MODEL_URL}"; do
    echo "  try: $url"
    if curl -L --connect-timeout 20 --max-time 7200 --progress-bar -o "$TMP" "$url"; then
      SZ=$(stat -c%s "$TMP" 2>/dev/null || echo 0)
      if [ "$SZ" -ge "$MIN_TAR_BYTES" ] && [ "$SZ" -le "$MAX_TAR_BYTES" ]; then
        download_ok=1
        break
      fi
    fi
    rm -f "$TMP"
  done
  if [ "$download_ok" -ne 1 ]; then
    echo "ERROR: download failed. Run: .\\scripts\\upload-asr-model.ps1"
    exit 1
  fi
  tar xjf "$TMP" -C "$BASE/models"
}

pip_install() {
  local attempt
  for attempt in 1 2 3; do
    echo "→ pip install (attempt $attempt)…"
    if "$BASE/.venv/bin/pip" install "$@" --default-timeout="$PIP_TIMEOUT" -i "$PIP_MIRROR"; then
      return 0
    fi
    sleep 10
  done
  return 1
}

if [ ! -d "$BASE/.venv" ] || ! "$BASE/.venv/bin/python" -c "import fastapi, sherpa_onnx" 2>/dev/null; then
  echo "→ Create ASR venv"
  rm -rf "$BASE/.venv"
  python3 -m venv "$BASE/.venv"
  pip_install -U pip wheel setuptools
  pip_install -r "$BASE/requirements.txt"
  "$BASE/.venv/bin/python" -c "import fastapi, uvicorn, sherpa_onnx; print('deps OK')"
else
  echo "→ ASR venv OK"
fi

ensure_model
if ! model_ready; then
  echo "ERROR: tokens.txt / paraformer .onnx not found"
  find "$BASE/models" -maxdepth 4 -type f 2>/dev/null | head -15
  exit 1
fi

export TY1100_ASR_MODEL_DIR="$MODEL_ROOT"

STREAM_MODEL="sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23"
STREAM_TAR="${STREAM_MODEL}.tar.bz2"
STREAM_ROOT="$BASE/models/${STREAM_MODEL}"
STREAM_MIN=60000000
STREAM_MAX=90000000

streaming_model_ready() {
  [ -f "$STREAM_ROOT/tokens.txt" ] || [ -n "$(find "$STREAM_ROOT" -name 'tokens.txt' 2>/dev/null | head -1)" ] && \
  [ -n "$(find "$STREAM_ROOT" -name 'encoder*.onnx' 2>/dev/null | head -1)" ] && \
  [ -n "$(find "$STREAM_ROOT" -name 'decoder*.onnx' 2>/dev/null | head -1)" ] && \
  [ -n "$(find "$STREAM_ROOT" -name 'joiner*.onnx' 2>/dev/null | head -1)" ]
}

ensure_streaming_model() {
  if streaming_model_ready; then
    echo "→ Streaming model OK under $BASE/models"
    return 0
  fi
  if [ "${TY1100_SKIP_STREAMING_DOWNLOAD:-0}" = "1" ]; then
    echo "WARN: streaming model missing — mic will use batch mode until uploaded"
    echo "  Windows: .\\scripts\\upload-asr-streaming-model.ps1"
    return 0
  fi
  mkdir -p "$BASE/models"
  TMP="$BASE/models/$STREAM_TAR"
  URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${STREAM_TAR}"
  echo "→ Download streaming Zipformer (~70MB) on device (slow)…"
  echo "  Prefer: .\\scripts\\upload-asr-streaming-model.ps1 on Windows"
  for mirror in \
    "https://ghfast.top/${URL}" \
    "https://mirror.ghproxy.com/${URL}" \
    "${URL}"; do
    echo "  try: $mirror"
    if curl -L --connect-timeout 20 --max-time 7200 --progress-bar -o "$TMP" "$mirror"; then
      SZ=$(stat -c%s "$TMP" 2>/dev/null || echo 0)
      if [ "$SZ" -ge "$STREAM_MIN" ] && [ "$SZ" -le "$STREAM_MAX" ]; then
        rm -rf "$STREAM_ROOT"
        tar xjf "$TMP" -C "$BASE/models"
        streaming_model_ready && return 0
      fi
    fi
    rm -f "$TMP"
  done
  echo "WARN: streaming model download failed — upload from Windows"
}

ensure_streaming_model

echo "→ Warmup ASR models"
"$BASE/.venv/bin/python" "$BASE/asr_server.py" --warmup

echo "✅ ASR installed at $BASE"
