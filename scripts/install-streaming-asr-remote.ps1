# Install streaming ASR model + sync code + restart (keep existing offline model)
param(
    [string]$DeviceIp = "192.168.34.11",
    [string]$User = "cix"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$AgentSrc = Join-Path $ProjectRoot "agent"

Write-Host "==> 1/4 Upload streaming model (~70MB) ..." -ForegroundColor Cyan
& "$PSScriptRoot\upload-asr-streaming-model.ps1" -DeviceIp $DeviceIp -User $User

Write-Host "==> 2/4 Sync ASR + Web code ..." -ForegroundColor Cyan
scp -r "$AgentSrc\asr" "${User}@${DeviceIp}:~/agent/"
scp -r "$AgentSrc\web" "${User}@${DeviceIp}:~/agent/"
scp "$AgentSrc\scripts\restart-asr-service.sh" "${User}@${DeviceIp}:~/agent/scripts/"
scp "$AgentSrc\scripts\restart-web-service.sh" "${User}@${DeviceIp}:~/agent/scripts/"

Write-Host "==> 3/4 Remote sync ..." -ForegroundColor Cyan
ssh "${User}@${DeviceIp}" "find ~/agent -name '*.sh' -exec sed -i 's/\r$//' {} \; 2>/dev/null; bash ~/agent/setup-ops-agent.sh; TY1100_SKIP_MODEL_DOWNLOAD=1 TY1100_SKIP_STREAMING_DOWNLOAD=1 bash ~/agent/asr/install-asr.sh"

Write-Host "==> 4/4 Restart ASR + Web ..." -ForegroundColor Cyan
ssh "${User}@${DeviceIp}" "bash ~/ty1100-agent/scripts/restart-asr-service.sh; bash ~/ty1100-agent/scripts/restart-web-service.sh"

Write-Host ""
$r = & "$PSScriptRoot\get-web-health.ps1" -DeviceIp $DeviceIp
$h = $r.Health
if ($h.asr_streaming_ready) {
    Write-Host "SUCCESS: streaming ASR ready ($($h.asr_streaming_engine))" -ForegroundColor Green
} else {
    Write-Host "WARN: streaming not ready - $($h.asr_streaming_error)" -ForegroundColor Yellow
}
Write-Host "Open: https://${DeviceIp}:8090/ - click Start Recording for live transcript" -ForegroundColor Green
