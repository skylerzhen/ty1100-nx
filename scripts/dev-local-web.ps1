# Local dev: Web on PC, model via SSH tunnel to device :8081
# Usage: .\scripts\dev-local-web.ps1

param(
    [string]$DeviceIp = "192.168.34.11",
    [string]$User = "cix",
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent)
)

$AgentBase = Join-Path $ProjectRoot "agent"
$WebDir = Join-Path $AgentBase "web"

Write-Host "==> Starting SSH tunnel :8081 (new window - keep it open) ..." -ForegroundColor Cyan
$tunnelCmd = "Write-Host 'SSH tunnel 8081 - close window to disconnect'; ssh -N -L 8081:127.0.0.1:8081 ${User}@${DeviceIp}"
Start-Process powershell -ArgumentList @("-NoExit", "-Command", $tunnelCmd)

Start-Sleep -Seconds 3

Write-Host "==> Checking local Python ..." -ForegroundColor Cyan
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { Write-Error "python not found - install Python 3.11+" }

Set-Location $WebDir
if (-not (Test-Path ".venv")) {
    python -m venv .venv
}
& .\.venv\Scripts\pip install -q -r requirements.txt

$env:TY1100_AGENT_BASE = $AgentBase
$env:TY1100_LLM_URL = "http://127.0.0.1:8081/v1/chat/completions"
$env:TY1100_WEB_HOST = "127.0.0.1"
$env:TY1100_WEB_PORT = "8090"

Write-Host ""
Write-Host "Local Web: http://127.0.0.1:8090/" -ForegroundColor Green
Write-Host "Agent base: $AgentBase" -ForegroundColor Gray
& .\.venv\Scripts\python server.py --host 127.0.0.1 --port 8090
