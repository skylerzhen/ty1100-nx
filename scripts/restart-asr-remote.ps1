# Restart ASR :8091 on device from Windows
param(
    [string]$DeviceIp = "192.168.34.11",
    [string]$User = "cix"
)

Write-Host "Restarting ASR on ${DeviceIp} ..." -ForegroundColor Cyan
ssh "${User}@${DeviceIp}" "bash ~/ty1100-agent/scripts/restart-asr-service.sh"

Write-Host ""
Write-Host "Health check ..." -ForegroundColor Cyan
try {
    $r = & "$PSScriptRoot\get-web-health.ps1" -DeviceIp $DeviceIp
    $h = $r.Health
    if ($h.asr_ok) {
        Write-Host "  ASR: OK ($($h.asr_engine))" -ForegroundColor Green
        if ($h.asr_streaming_ready) {
            Write-Host "  Streaming: OK ($($h.asr_streaming_engine))" -ForegroundColor Green
        } else {
            Write-Host "  Streaming: not ready ($($h.asr_streaming_error))" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ASR: FAIL - $($h.asr_error)" -ForegroundColor Red
        Write-Host "  Log: ssh ${User}@${DeviceIp} 'tail -50 ~/ty1100-agent/asr/asr.log'" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  Health check failed: $_" -ForegroundColor Red
}
