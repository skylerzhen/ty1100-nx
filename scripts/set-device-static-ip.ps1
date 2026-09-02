# Set TY1100 static IP from local Windows (no device monitor required)
# Usage: .\scripts\set-device-static-ip.ps1
#        .\scripts\set-device-static-ip.ps1 -DeviceIp 192.168.34.11 -NewIp 192.168.34.11

param(
    [string]$DeviceIp = "192.168.34.11",
    [string]$User = "cix",
    [string]$NewIp = "192.168.34.11",
    [string]$Gateway = "192.168.34.1"
)

$ErrorActionPreference = "Stop"

Write-Host "==> Upload set-static-ip.sh ..." -ForegroundColor Cyan
scp "$PSScriptRoot\..\agent\scripts\set-static-ip.sh" "${User}@${DeviceIp}:~/agent/scripts/"

Write-Host "==> Apply static IP on device (will prompt sudo password on device) ..." -ForegroundColor Cyan
ssh -t "${User}@${DeviceIp}" "find ~/agent/scripts -name set-static-ip.sh -exec sed -i 's/\r$//' {} \; ; bash ~/agent/scripts/set-static-ip.sh $NewIp $Gateway"

Write-Host ""
Write-Host "Test from PC:" -ForegroundColor Green
Write-Host "  ping $NewIp"
Write-Host "  ssh ${User}@${NewIp}"
