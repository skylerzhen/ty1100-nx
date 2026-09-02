# TY1100 court agent - deploy from local Windows (no interactive SSH on device)
# Usage: .\scripts\deploy-from-windows.ps1

param(
    [string]$DeviceIp = "192.168.34.11",
    [string]$User = "cix",
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = "Stop"
$AgentSrc = Join-Path $ProjectRoot "agent"

if (-not (Test-Path $AgentSrc)) {
    Write-Error "agent folder not found: $AgentSrc"
}

Write-Host "==> 1/3 Upload agent to ${User}@${DeviceIp} ..." -ForegroundColor Cyan
scp -r "$AgentSrc" "${User}@${DeviceIp}:~/"

Write-Host "==> 2/3 Remote install ..." -ForegroundColor Cyan
ssh "${User}@${DeviceIp}" "find ~/agent -name '*.sh' -exec sed -i 's/\r$//' {} \; 2>/dev/null; bash ~/agent/setup-ops-agent.sh"

Write-Host "==> 3/3 Remote restart Web ..." -ForegroundColor Cyan
ssh "${User}@${DeviceIp}" "bash ~/ty1100-agent/scripts/restart-web-service.sh"

Write-Host ""
Write-Host "==> Health check ..." -ForegroundColor Cyan
function Get-WebHealth {
    param([string]$Ip)
    $urls = @(
        "https://${Ip}:8090/api/health",
        "http://${Ip}:8090/api/health"
    )
    foreach ($u in $urls) {
        try {
            if ($PSVersionTable.PSVersion.Major -ge 7) {
                return @{ Health = (Invoke-RestMethod -Uri $u -SkipCertificateCheck -TimeoutSec 15); Url = $u }
            }
            # Windows PowerShell 5.1
            add-type @"
using System.Net; using System.Net.Security; using System.Security.Cryptography.X509Certificates;
public class TrustAllCerts { public static bool Init() {
  ServicePointManager.ServerCertificateValidationCallback = delegate { return true; }; return true; } }
"@
            [void][TrustAllCerts]::Init()
            return @{ Health = (Invoke-RestMethod -Uri $u -TimeoutSec 15); Url = $u }
        } catch {
            continue
        }
    }
    throw "Health check failed for ${Ip}:8090"
}

$scheme = "http"
try {
    $result = Get-WebHealth -Ip $DeviceIp
    $health = $result.Health
    $scheme = if ($result.Url -like "https://*") { "https" } else { "http" }
    Write-Host "  Web:       OK ($scheme, legal_chunks=$($health.legal_chunks), stream_audit=$($health.stream_audit))" -ForegroundColor Green
    Write-Host "  LLM 8081:  $(if ($health.llm_ok) { 'OK' } else { 'FAIL — ' + $health.llm_error })" -ForegroundColor $(if ($health.llm_ok) { 'Green' } else { 'Red' })
    if ($health.asr_ok) {
        Write-Host "  ASR 8091:  OK ($($health.asr_engine))" -ForegroundColor Green
    } else {
        Write-Host "  ASR 8091:  NOT RUNNING ($($health.asr_error))" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Web deployed OK. ASR is a separate one-time install:" -ForegroundColor Yellow
        Write-Host "    .\scripts\install-asr-remote.ps1" -ForegroundColor White
    }
} catch {
    Write-Host "  Health check failed: $_" -ForegroundColor Red
}

Write-Host ""
if ($scheme -eq "https") {
    Write-Host "Open (microphone): https://${DeviceIp}:8090/" -ForegroundColor Green
    Write-Host "  First visit: Advanced -> Continue (self-signed cert)" -ForegroundColor Gray
} else {
    Write-Host "Open: http://${DeviceIp}:8090/" -ForegroundColor Green
    Write-Host "Mic:  .\scripts\open-web-with-mic.ps1  OR redeploy for HTTPS" -ForegroundColor Yellow
}
