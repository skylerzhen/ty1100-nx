# Full ASR setup: upload model from Windows -> install -> start (run this ONE script)
param(
    [string]$DeviceIp = "192.168.34.11",
    [string]$User = "cix",
    [switch]$SkipModelUpload
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$AgentSrc = Join-Path $ProjectRoot "agent"

Write-Host "======== TY1100 ASR install (3 steps) ========" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/3] Upload model from Windows (required, ~230MB) ..." -ForegroundColor Cyan
if ($SkipModelUpload) {
    Write-Host "  skipped (-SkipModelUpload, model already on device)" -ForegroundColor Gray
} else {
    & "$PSScriptRoot\upload-asr-model.ps1" -DeviceIp $DeviceIp -User $User
}

Write-Host ""
Write-Host "[2/3] Sync code + pip + warmup ..." -ForegroundColor Cyan
scp -r "$AgentSrc\asr" "${User}@${DeviceIp}:~/agent/"
scp "$AgentSrc\scripts\restart-asr-service.sh" "${User}@${DeviceIp}:~/agent/scripts/"
ssh "${User}@${DeviceIp}" "find ~/agent -name '*.sh' -exec sed -i 's/\r$//' {} \; 2>/dev/null; bash ~/agent/setup-ops-agent.sh; TY1100_SKIP_MODEL_DOWNLOAD=1 bash ~/agent/asr/install-asr.sh"

Write-Host ""
Write-Host "[3/3] Start ASR :8091 ..." -ForegroundColor Cyan
ssh "${User}@${DeviceIp}" "bash ~/ty1100-agent/scripts/restart-asr-service.sh"

Write-Host ""
$health = Invoke-RestMethod -Uri "http://${DeviceIp}:8090/api/health" -TimeoutSec 15
if ($health.asr_ok) {
    Write-Host "SUCCESS: ASR online ($($health.asr_engine))" -ForegroundColor Green
} else {
    Write-Host "FAILED: $($health.asr_error)" -ForegroundColor Red
    Write-Host "Log: ssh ${User}@${DeviceIp} 'tail -80 ~/ty1100-agent/asr/asr.log'" -ForegroundColor Yellow
    exit 1
}
