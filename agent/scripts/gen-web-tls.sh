#!/bin/bash
# Generate self-signed TLS cert for Web UI (enables browser microphone on LAN IP via HTTPS)
set -e

sed -i 's/\r$//' "$0" 2>/dev/null || true

BASE="${TY1100_AGENT_BASE:-$HOME/ty1100-agent}"
CERT_DIR="$BASE/web/certs"
CERT="$CERT_DIR/cert.pem"
KEY="$CERT_DIR/key.pem"

mkdir -p "$CERT_DIR"

if [ -f "$CERT" ] && [ -f "$KEY" ]; then
  echo "TLS cert OK: $CERT"
  exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "WARN: openssl not found — Web will stay HTTP-only (no mic on LAN IP)"
  exit 1
fi

LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
LAN_IP="${TY1100_TLS_IP:-${LAN_IP:-127.0.0.1}}"

echo "→ Generating self-signed TLS cert (SAN IP: $LAN_IP, 127.0.0.1, localhost)"

if openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$KEY" -out "$CERT" -days 3650 \
  -subj "/CN=ty1100-court-local/O=TY1100" \
  -addext "subjectAltName=IP:${LAN_IP},IP:127.0.0.1,DNS:localhost" 2>/dev/null; then
  :
else
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$KEY" -out "$CERT" -days 3650 \
    -subj "/CN=${LAN_IP}/O=TY1100"
fi

chmod 600 "$KEY"
echo "TLS cert created: $CERT"
