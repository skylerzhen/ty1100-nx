# Install systemd auto-start for court web on device
param(
    [string]$DeviceIp = "192.168.34.11",
    [string]$User = "cix"
)

Write-Host "Installing systemd unit (sudo password required) ..." -ForegroundColor Cyan
ssh -t "${User}@${DeviceIp}" "bash ~/ty1100-agent/scripts/install-systemd.sh"
