#!/bin/bash
# Install systemd unit for local ASR (run on device via ssh -t)
set -e
sed -i 's/\r$//' "$0" 2>/dev/null || true

UNIT_SRC=~/ty1100-agent/systemd/ty1100-asr.service
UNIT_DST=/etc/systemd/system/ty1100-asr.service

if [ ! -f "$UNIT_SRC" ]; then
  echo "ERROR: missing $UNIT_SRC — deploy agent first"
  exit 1
fi

if [ ! -f ~/ty1100-agent/asr/.venv/bin/python ]; then
  echo "ERROR: ASR venv missing — run bash ~/agent/asr/install-asr.sh first"
  exit 1
fi

sudo sed "s|%h|$HOME|g" "$UNIT_SRC" > /tmp/ty1100-asr.service
sudo mv /tmp/ty1100-asr.service "$UNIT_DST"
sudo systemctl daemon-reload
sudo systemctl enable ty1100-asr.service
sudo systemctl restart ty1100-asr.service
sudo systemctl status ty1100-asr.service --no-pager || true
echo "Installed ty1100-asr.service"
