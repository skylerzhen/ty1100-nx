# Run legal corpus stats on device
param(
    [string]$DeviceIp = "192.168.34.11",
    [string]$User = "cix"
)

ssh "${User}@${DeviceIp}" "python3 ~/ty1100-agent/scripts/legal-corpus-stats.py 2>/dev/null || ~/ty1100-agent/web/.venv/bin/python ~/ty1100-agent/scripts/legal-corpus-stats.py"
