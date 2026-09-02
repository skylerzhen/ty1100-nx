# Download streaming Zipformer-zh (~70MB) and upload to device for live mic ASR
param(
    [string]$DeviceIp = "192.168.34.11",
    [string]$User = "cix",
    [switch]$DownloadOnly,
    [ValidateSet("auto", "huggingface", "github")]
    [string]$Source = "auto"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$ModelDirName = "sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23"
$ModelTar = "$ModelDirName.tar.bz2"
$CacheRoot = Join-Path $ProjectRoot ".cache\asr-models"
$LocalModelDir = Join-Path $CacheRoot $ModelDirName
$LocalTar = Join-Path $CacheRoot $ModelTar
$RemoteDir = "~/ty1100-agent/asr/models/$ModelDirName"
$TarMinBytes = 60000000
$TarMaxBytes = 90000000

$HfBase = "https://hf-mirror.com/csukuangfj/$ModelDirName/resolve/main"
$HfFiles = @(
    @{ Name = "tokens.txt"; Min = 1000; Max = 500000 },
    @{ Name = "encoder-epoch-99-avg-1.int8.onnx"; Min = 20000000; Max = 45000000 },
    @{ Name = "decoder-epoch-99-avg-1.onnx"; Min = 1000000; Max = 10000000 },
    @{ Name = "joiner-epoch-99-avg-1.int8.onnx"; Min = 500000; Max = 5000000 }
)
$GithubUrls = @(
    "https://ghfast.top/https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$ModelTar",
    "https://mirror.ghproxy.com/https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$ModelTar",
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$ModelTar"
)

New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null
New-Item -ItemType Directory -Force -Path $LocalModelDir | Out-Null

function Download-CurlResume([string]$Url, [string]$OutFile) {
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        throw "curl.exe required for resume download"
    }
    $partial = Test-Path $OutFile
    if ($partial) {
        $mb = [math]::Round((Get-Item $OutFile).Length / 1MB, 1)
        Write-Host "  resume from $mb MB ..." -ForegroundColor Gray
    }
    $args = @(
        "-L", "--connect-timeout", "30", "--max-time", "0",
        "--retry", "8", "--retry-delay", "5", "--retry-all-errors",
        "--progress-bar"
    )
    if ($partial) { $args += "-C", "-" }
    $args += "-o", $OutFile, $Url
    & curl.exe @args
    if ($LASTEXITCODE -ne 0) { throw "curl failed ($LASTEXITCODE): $Url" }
}

function Test-HfStreamingModel() {
    foreach ($f in $HfFiles) {
        $path = Join-Path $LocalModelDir $f.Name
        if (-not (Test-Path $path)) { return $false }
        $len = (Get-Item $path).Length
        if ($len -lt $f.Min -or $len -gt $f.Max) { return $false }
    }
    return $true
}

function Test-StreamingTar([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    $len = (Get-Item $Path).Length
    if ($len -lt $TarMinBytes -or $len -gt $TarMaxBytes) { return $false }
    if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) { return $true }
    $listing = tar.exe -tjf $Path 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    return ($listing | Select-String "encoder.*\.onnx" -Quiet) -and ($listing | Select-String "tokens\.txt" -Quiet)
}

function Download-HuggingFace() {
    if (Test-HfStreamingModel) {
        Write-Host "==> HF streaming model cached: $LocalModelDir" -ForegroundColor Green
        return
    }
    Write-Host "==> Download from hf-mirror (4 files, ~70MB total, resume OK)" -ForegroundColor Cyan
    Write-Host "    Usually faster than GitHub in China. Re-run to resume if interrupted." -ForegroundColor Gray
    foreach ($f in $HfFiles) {
        $out = Join-Path $LocalModelDir $f.Name
        Write-Host "  $($f.Name) ..." -ForegroundColor Gray
        Download-CurlResume "$HfBase/$($f.Name)" $out
    }
    if (-not (Test-HfStreamingModel)) { throw "HF streaming download incomplete or corrupt" }
    Write-Host "  all files OK" -ForegroundColor Green
}

function Download-GithubTar() {
    if (Test-StreamingTar $LocalTar) {
        Write-Host "==> GitHub tar cached: $LocalTar" -ForegroundColor Green
        return
    }
    if ((Test-Path $LocalTar) -and -not (Test-StreamingTar $LocalTar)) {
        Write-Host "  removing corrupt tar ..." -ForegroundColor Yellow
        Remove-Item $LocalTar -Force
    }
    Write-Host "==> Download GitHub tar (~70MB) - slower; prefer hf-mirror (-Source huggingface)" -ForegroundColor Cyan
    foreach ($u in $GithubUrls) {
        Write-Host "  try: $u" -ForegroundColor Gray
        try {
            Download-CurlResume $u $LocalTar
            if (Test-StreamingTar $LocalTar) { return }
        } catch {
            Write-Host "  failed: $_" -ForegroundColor DarkYellow
        }
    }
    throw "Download failed for $ModelTar"
}

function Ensure-LocalModel() {
    if ($Source -eq "huggingface") {
        Download-HuggingFace
        return
    }
    if ($Source -eq "github") {
        Download-GithubTar
        if (-not (Test-Path $LocalModelDir) -or -not (Test-HfStreamingModel)) {
            Write-Host "  extract tar -> $LocalModelDir" -ForegroundColor Gray
            if (Test-Path $LocalModelDir) { Remove-Item $LocalModelDir -Recurse -Force }
            New-Item -ItemType Directory -Force -Path $LocalModelDir | Out-Null
            tar.exe -xjf $LocalTar -C $CacheRoot
        }
        return
    }
    try {
        Download-HuggingFace
    } catch {
        Write-Host "  hf-mirror failed, fallback GitHub tar ..." -ForegroundColor Yellow
        Download-GithubTar
        if (-not (Test-HfStreamingModel)) {
            if (Test-Path $LocalModelDir) { Remove-Item $LocalModelDir -Recurse -Force }
            tar.exe -xjf $LocalTar -C $CacheRoot
        }
    }
}

Ensure-LocalModel

if ($DownloadOnly) { exit 0 }

Write-Host "==> Upload to ${User}@${DeviceIp} ..." -ForegroundColor Cyan
ssh "${User}@${DeviceIp}" "mkdir -p ~/ty1100-agent/asr/models"
scp -r "$LocalModelDir" "${User}@${DeviceIp}:~/ty1100-agent/asr/models/"
Write-Host "==> Streaming model ready on device" -ForegroundColor Green
Write-Host "Next: ssh ${User}@${DeviceIp} 'bash ~/ty1100-agent/scripts/restart-asr-service.sh'" -ForegroundColor Gray
