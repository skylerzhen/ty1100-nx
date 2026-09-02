# SSH tunnel so browser treats Web UI as localhost (enables microphone in Chrome/Edge)
param(
    [string]$DeviceIp = "192.168.34.11",
    [string]$User = "cix",
    [int]$LocalPort = 8090
)

Write-Host "Forwarding http://127.0.0.1:${LocalPort} -> ${DeviceIp}:${LocalPort}" -ForegroundColor Cyan
Write-Host "Open in browser: http://127.0.0.1:${LocalPort}/" -ForegroundColor Green
Write-Host "Then [开始录音] works. Ctrl+C to stop tunnel." -ForegroundColor Gray
ssh -N -L "${LocalPort}:127.0.0.1:${LocalPort}" "${User}@${DeviceIp}"
