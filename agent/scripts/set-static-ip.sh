#!/bin/bash
# Set static IPv4 on TY1100 (run via ssh from Windows — no local monitor needed)
# Usage: bash ~/agent/scripts/set-static-ip.sh [IP] [GATEWAY]
set -e

sed -i 's/\r$//' "$0" 2>/dev/null || true

IP="${1:-192.168.34.11}"
GW="${2:-192.168.34.1}"
PREFIX=24

echo "==> Active ethernet interface:"
IFACE=$(ip -o link show up | awk -F': ' '$2 !~ /^(lo|wl|docker|br-|veth)/ {print $2; exit}')
if [ -z "$IFACE" ]; then
  echo "ERROR: no UP ethernet interface found"
  ip link
  exit 1
fi
echo "    $IFACE"

echo "==> NetworkManager connection for $IFACE:"
CON=$(nmcli -t -f NAME,DEVICE con show --active | awk -F: -v d="$IFACE" '$2==d {print $1; exit}')
if [ -z "$CON" ]; then
  CON=$(nmcli -t -f NAME,DEVICE con show | awk -F: -v d="$IFACE" '$2==d {print $1; exit}')
fi
if [ -z "$CON" ]; then
  echo "ERROR: no nmcli connection for $IFACE. Run: nmcli con show"
  exit 1
fi
echo "    $CON"

echo "==> Apply static IP ${IP}/${PREFIX} gateway ${GW}"
sudo nmcli con mod "$CON" ipv4.addresses "${IP}/${PREFIX}"
sudo nmcli con mod "$CON" ipv4.gateway "$GW"
sudo nmcli con mod "$CON" ipv4.dns "$GW"
sudo nmcli con mod "$CON" ipv4.method manual
sudo nmcli con mod "$CON" connection.autoconnect yes
sudo nmcli con up "$CON"

sleep 2
echo ""
echo "==> Verify:"
ip -4 addr show "$IFACE" | grep inet || true
ip route | grep default || true
echo ""
echo "Done. SSH from PC: ssh cix@${IP}"
