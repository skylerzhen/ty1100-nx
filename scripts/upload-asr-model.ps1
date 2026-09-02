# Download ASR model (prefer hf-mirror, resume-friendly) and upload to device
param(
    [string]$DeviceIp = "192.168.34.11",
    [string]$User = "cix",
    [switch]$DownloadOnly,
    [ValidateSet("auto", "huggingface", "github")]
    [string]$Source = "auto"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$ModelDirName = "sherpa-onnx-paraformer-zh-2023-09-14"
$ModelTar = "$ModelDirName.tar.bz2"
$CacheRoot = Join-Path $ProjectRoot ".cache\asr-models"
$LocalModelDir = Join-Path $CacheRoot $ModelDirName
$LocalTar = Join-Path $CacheRoot $ModelTar
$OnnxFile = Join-Path $LocalModelDir "model.int8.onnx"
$TokensFile = Join-Path $LocalModelDir "tokens.txt"
$OnnxMinBytes = 230000000
$OnnxMaxBytes = 250000000
$TarMinBytes = 210000000
$TarMaxBytes = 240000000

$HfBase = "https://hf-mirror.com/csukuangfj/sherpa-onnx-paraformer-zh-2023-09-14/resolve/main"
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

function Test-HfModel() {
    return (Test-Path $OnnxFile) -and (Test-Path $TokensFile) `
        -and ((Get-Item $OnnxFile).Length -ge $OnnxMinBytes) `
        -and ((Get-Item $OnnxFile).Length -le $OnnxMaxBytes) `
        -and ((Get-Item $TokensFile).Length -gt 1000)
}

function Test-GithubTar([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    $len = (Get-Item $Path).Length
    if ($len -lt $TarMinBytes -or $len -gt $TarMaxBytes) { return $false }
    if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) { return $true }
    $listing = tar.exe -tjf $Path 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    return ($listing | Select-String "\.onnx" -Quiet) -and ($listing | Select-String "tokens\.txt" -Quiet)
}

function Download-HuggingFace() {
    if (Test-HfModel) {
        Write-Host "==> HF model cached: $LocalModelDir" -ForegroundColor Green
        return
    }
    Write-Host "==> Download from hf-mirror (~232MB model.int8.onnx + tokens.txt)" -ForegroundColor Cyan
    Write-Host "    Slow network is normal. Supports resume — do NOT cancel; re-run to continue." -ForegroundColor Gray
    Download-CurlResume "$HfBase/tokens.txt" $TokensFile
    Write-Host "  tokens.txt OK" -ForegroundColor Green
    Download-CurlResume "$HfBase/model.int8.onnx" $OnnxFile
    if (-not (Test-HfModel)) { throw "HF download incomplete or corrupt" }
    $mb = [math]::Round((Get-Item $OnnxFile).Length / 1MB, 1)
    Write-Host "  model.int8.onnx OK ($mb MB)" -ForegroundColor Green
}

function Download-GithubTar() {
    if (Test-GithubTar $LocalTar) {
        Write-Host "==> GitHub tar cached: $LocalTar" -ForegroundColor Green
        return
    }
    if ((Test-Path $LocalTar) -and -not (Test-GithubTar $LocalTar)) {
        Write-Host "  removing incomplete tar ..." -ForegroundColor Yellow
        Remove-Item $LocalTar -Force
    }
    Write-Host "==> Download GitHub tar (~223MB) — slower; prefer hf-mirror" -ForegroundColor Cyan
    foreach ($url in $GithubUrls) {
        Write-Host "  try: $url" -ForegroundColor Gray
        try {
            Download-CurlResume $url $LocalTar
            if (Test-GithubTar $LocalTar) { return }
        } catch {
            Write-Host "  failed: $_" -ForegroundColor Yellow
        }
    }
    throw "GitHub tar download failed"
}

if ($Source -eq "huggingface" -or $Source -eq "auto") {
    try {
        Download-HuggingFace
        $useHf = $true
    } catch {
        if ($Source -eq "huggingface") { throw }
        Write-Host "WARN: hf-mirror failed, fallback GitHub tar ..." -ForegroundColor Yellow
        $useHf = $false
    }
}
if (-not $useHf) {
    Download-GithubTar
    Write-Host "==> Extract tar locally ..." -ForegroundColor Cyan
    Remove-Item $LocalModelDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $LocalModelDir | Out-Null
    tar.exe -xjf $LocalTar -C $CacheRoot
}

if ($DownloadOnly) { return }

Write-Host "==> Upload model to ${User}@${DeviceIp} ..." -ForegroundColor Cyan
ssh "${User}@${DeviceIp}" "mkdir -p ~/ty1100-agent/asr/models && rm -rf ~/ty1100-agent/asr/models/$ModelDirName"
scp -r "$LocalModelDir" "${User}@${DeviceIp}:~/ty1100-agent/asr/models/"

Write-Host "==> Verify on device ..." -ForegroundColor Cyan
$verifyCmd = @"
set -e
cd ~/ty1100-agent/asr/models/$ModelDirName
test -f tokens.txt
test -f model.int8.onnx || test -n "`$(find . -name '*.onnx' ! -path './test_wavs/*' | head -1)"
echo OK model ready
"@ -replace "`r", ""
ssh "${User}@${DeviceIp}" $verifyCmd
Write-Host "Model ready on device." -ForegroundColor Green
