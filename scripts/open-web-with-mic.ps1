# Open Web UI with microphone support via SSH localhost tunnel (no HTTPS needed)
param(
    [string]$DeviceIp = "192.168.34.11",
    [string]$User = "cix",
    [int]$LocalPort = 8090
)

$ErrorActionPreference = "Stop"
$url = "http://127.0.0.1:${LocalPort}/"

function Test-LocalPort {
    param([int]$Port)
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect("127.0.0.1", $Port)
        $c.Close()
        return $true
    } catch {
        return $false
    }
}

if (-not (Test-LocalPort $LocalPort)) {
    Write-Host "Starting SSH tunnel ${LocalPort} -> ${DeviceIp}:${LocalPort} ..." -ForegroundColor Cyan
    Start-Process -FilePath "ssh" -ArgumentList @(
        "-N", "-L", "${LocalPort}:127.0.0.1:${LocalPort}", "${User}@${DeviceIp}"
    ) -WindowStyle Minimized | Out-Null

    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        if (Test-LocalPort $LocalPort) { break }
        Start-Sleep -Milliseconds 400
    }
    if (-not (Test-LocalPort $LocalPort)) {
        Write-Error "Tunnel failed to bind localhost:${LocalPort}. Check SSH login to ${User}@${DeviceIp}."
    }
    Write-Host "Tunnel running (minimized ssh window). Close it to stop." -ForegroundColor Gray
} else {
    Write-Host "Port ${LocalPort} already in use — assuming tunnel is up." -ForegroundColor Yellow
}

Write-Host "Opening $url (microphone enabled on localhost)" -ForegroundColor Green
Start-Process $url
