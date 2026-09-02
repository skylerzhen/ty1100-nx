#!/bin/bash
# Install systemd unit for court web (run on device via ssh -t)
set -e
sed -i 's/\r$//' "$0" 2>/dev/null || true

UNIT_SRC=~/ty1100-agent/systemd/ty1100-court-web.service
UNIT_DST=/etc/systemd/system/ty1100-court-web.service

if [ ! -f "$UNIT_SRC" ]; then
  echo "ERROR: missing $UNIT_SRC — deploy agent first"
  exit 1
fi

sudo sed "s|%h|$HOME|g" "$UNIT_SRC" > /tmp/ty1100-court-web.service
sudo mv /tmp/ty1100-court-web.service "$UNIT_DST"
sudo systemctl daemon-reload
sudo systemctl enable ty1100-court-web.service
sudo systemctl restart ty1100-court-web.service
sudo systemctl status ty1100-court-web.service --no-pager || true
echo "Installed ty1100-court-web.service"
