# Run eval suite against device Web API
param(
    [string]$DeviceIp = "192.168.34.11",
    [string]$User = "cix"
)

Write-Host "Running eval on device ..." -ForegroundColor Cyan
ssh "${User}@${DeviceIp}" "cd ~/ty1100-agent/web && .venv/bin/python ../eval/run_eval.py --base http://127.0.0.1:8090"
