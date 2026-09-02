# Upload local audio file to device for real ASR transcription
param(
    [Parameter(Mandatory = $true)]
    [string]$AudioPath,
    [string]$BaseUrl = "http://192.168.34.11:8090",
    [string]$User = "clerk",
    [string]$Pass = "clerk123",
    [string]$CaseNo = ""
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $AudioPath)) {
    Write-Error "File not found: $AudioPath"
}

Write-Host "==> Login" -ForegroundColor Cyan
$loginBody = @{ username = $User; password = $Pass; role = "clerk" } | ConvertTo-Json -Compress
$login = Invoke-RestMethod -Uri "$BaseUrl/api/auth/login" -Method Post -Body $loginBody -ContentType "application/json; charset=utf-8"
$token = $login.token

Write-Host "==> POST /api/asr/transcribe" -ForegroundColor Cyan
$boundary = [System.Guid]::NewGuid().ToString()
$fileBytes = [System.IO.File]::ReadAllBytes((Resolve-Path $AudioPath))
$fileName = [System.IO.Path]::GetFileName($AudioPath)

$bodyLines = @(
    "--$boundary",
    "Content-Disposition: form-data; name=`"case_no`"",
    "",
    $CaseNo,
    "--$boundary",
    "Content-Disposition: form-data; name=`"audio`"; filename=`"$fileName`"",
    "Content-Type: application/octet-stream",
    ""
)
$bodyStart = [System.Text.Encoding]::UTF8.GetBytes(($bodyLines -join "`r`n") + "`r`n")
$bodyEnd = [System.Text.Encoding]::UTF8.GetBytes("`r`n--$boundary--`r`n")
$body = New-Object byte[] ($bodyStart.Length + $fileBytes.Length + $bodyEnd.Length)
[Array]::Copy($bodyStart, 0, $body, 0, $bodyStart.Length)
[Array]::Copy($fileBytes, 0, $body, $bodyStart.Length, $fileBytes.Length)
[Array]::Copy($bodyEnd, 0, $body, $bodyStart.Length + $fileBytes.Length, $bodyEnd.Length)

$headers = @{
    Authorization = "Bearer $token"
    "Content-Type" = "multipart/form-data; boundary=$boundary"
}

$result = Invoke-RestMethod -Uri "$BaseUrl/api/asr/transcribe" -Method Post -Headers $headers -Body $body
$result | ConvertTo-Json -Depth 5
Write-Host ""
Write-Host "Done. chars=$($result.chars) file=$($result.file)" -ForegroundColor Green
