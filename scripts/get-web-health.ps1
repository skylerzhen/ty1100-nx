# Shared health check for Web :8090 (HTTPS self-signed or HTTP fallback)
param(
    [string]$DeviceIp = "192.168.34.11",
    [int]$TimeoutSec = 15
)

$ErrorActionPreference = "Stop"
$urls = @(
    "https://${DeviceIp}:8090/api/health",
    "http://${DeviceIp}:8090/api/health"
)

foreach ($u in $urls) {
    try {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $health = Invoke-RestMethod -Uri $u -SkipCertificateCheck -TimeoutSec $TimeoutSec
        } else {
            if (-not ("TrustAllCerts" -as [type])) {
                add-type @"
using System.Net; using System.Net.Security;
public class TrustAllCerts { public static bool Init() {
  ServicePointManager.ServerCertificateValidationCallback = delegate { return true; }; return true; } }
"@
            }
            [void][TrustAllCerts]::Init()
            $health = Invoke-RestMethod -Uri $u -TimeoutSec $TimeoutSec
        }
        return @{
            Health = $health
            Url    = $u
            Scheme = if ($u -like "https://*") { "https" } else { "http" }
        }
    } catch {
        continue
    }
}

throw "Health check failed for ${DeviceIp}:8090 (tried https and http)"
