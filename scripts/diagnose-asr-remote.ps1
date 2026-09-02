# Diagnose ASR + streaming on device
param(
    [string]$DeviceIp = "192.168.34.11",
    [string]$User = "cix"
)

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$DiagSh = Join-Path $ProjectRoot "agent\scripts\diagnose-asr.sh"

Write-Host "=== TY1100 ASR diagnose ===" -ForegroundColor Cyan
Write-Host ""

try {
    $r = & "$PSScriptRoot\get-web-health.ps1" -DeviceIp $DeviceIp
    $h = $r.Health
    Write-Host "[Web health]" -ForegroundColor Yellow
    Write-Host "  asr_ok:              $($h.asr_ok)"
    Write-Host "  asr_error:           $($h.asr_error)"
    Write-Host "  asr_streaming_ready: $($h.asr_streaming_ready)"
    Write-Host "  asr_streaming_error: $($h.asr_streaming_error)"
    Write-Host ""
    if ($h.asr_ok -and -not $h.asr_streaming_ready) {
        Write-Host "  >> Offline ASR OK, streaming NOT ready (need Zipformer model + Web ws route)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  Web health FAILED: $_" -ForegroundColor Red
}

Write-Host "[Device checks via SSH]" -ForegroundColor Yellow
scp "$DiagSh" "${User}@${DeviceIp}:/tmp/diagnose-asr.sh" | Out-Null
ssh "${User}@${DeviceIp}" "sed -i 's/\r$//' /tmp/diagnose-asr.sh; bash /tmp/diagnose-asr.sh"

Write-Host ""
Write-Host "Fix (recommended):" -ForegroundColor Cyan
Write-Host "  .\scripts\install-streaming-asr-remote.ps1"
