# Restart Web on device from local Windows PowerShell
param(
    [string]$DeviceIp = "192.168.34.11",
    [string]$User = "cix"
)

Write-Host "Restarting Web on ${DeviceIp} ..." -ForegroundColor Cyan
ssh "${User}@${DeviceIp}" "bash ~/ty1100-agent/scripts/restart-web-service.sh"
Write-Host "Try microphone: https://${DeviceIp}:8090/ (trust cert once)" -ForegroundColor Green
Write-Host "Or tunnel:      .\scripts\open-web-with-mic.ps1" -ForegroundColor Gray
