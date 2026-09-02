# Test local legal retrieval API on device (requires login since auth enabled)
param(
    [string]$BaseUrl = "http://192.168.34.11:8090",
    [string]$User = "clerk",
    [string]$Pass = "clerk123"
)

$ErrorActionPreference = "Stop"

Write-Host "==> GET $BaseUrl/api/health (public)" -ForegroundColor Cyan
$health = Invoke-RestMethod -Uri "$BaseUrl/api/health" -Method Get
$health | ConvertTo-Json -Depth 5

Write-Host ""
Write-Host "==> POST $BaseUrl/api/auth/login" -ForegroundColor Cyan
$loginBody = @{ username = $User; password = $Pass; role = "clerk" } | ConvertTo-Json -Compress
$login = Invoke-RestMethod -Uri "$BaseUrl/api/auth/login" -Method Post -Body $loginBody -ContentType "application/json; charset=utf-8"
$token = $login.token
$headers = @{ Authorization = "Bearer $token" }

Write-Host ""
Write-Host "==> GET $BaseUrl/api/legal/index" -ForegroundColor Cyan
$index = Invoke-RestMethod -Uri "$BaseUrl/api/legal/index" -Method Get -Headers $headers
$index | ConvertTo-Json -Depth 5

Write-Host ""
Write-Host "==> POST $BaseUrl/api/legal/search" -ForegroundColor Cyan
$body = @{ query = "复制庭审录音录像"; case_type = "民事纠纷" } | ConvertTo-Json -Compress
$search = Invoke-RestMethod -Uri "$BaseUrl/api/legal/search" -Method Post -Body $body -ContentType "application/json; charset=utf-8" -Headers $headers
$search | ConvertTo-Json -Depth 6

Write-Host ""
Write-Host "Done. total_chunks=$($index.total_chunks)" -ForegroundColor Green
