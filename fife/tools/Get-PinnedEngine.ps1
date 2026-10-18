#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Destination = 'C:\Users\barne\claude-fife-backup\claude-2.1.302.exe',
    [string]$Version = '2.1.302',
    [string]$Platform = 'win32-x64',
    [string]$InstalledFallback = 'C:\Users\barne\.local\bin\claude.exe'
)
$ErrorActionPreference = 'Stop'

$backupDir = Split-Path -Parent $Destination
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$base = 'https://downloads.claude.ai/claude-code-releases'
$provenance = $null
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "claude-$Version-$Platform.exe"
$source = $null

try {
    $manifest = Invoke-RestMethod -Uri "$base/$Version/manifest.json"
    $expected = $manifest.platforms.$Platform.checksum
    if (-not $expected) { throw "manifest has no checksum for $Platform" }
    Invoke-WebRequest -Uri "$base/$Version/$Platform/claude.exe" -OutFile $tmp -UseBasicParsing
    $dlHash = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
    if ($dlHash -ne $expected.ToLower()) { throw 'downloaded checksum does not match manifest' }
    $source = $tmp
    $provenance = 'fresh-download'
} catch {
    Write-Warning "Fresh download unavailable or unverifiable ($($_.Exception.Message)); falling back to installed binary."
    if (-not (Test-Path $InstalledFallback)) { throw 'No fresh download and no installed fallback binary.' }
    $source = $InstalledFallback
    $provenance = 'copied-installed'
}

Copy-Item $source (Join-Path $backupDir 'claude-2.1.302.exe') -Force
if ($Destination -ne (Join-Path $backupDir 'claude-2.1.302.exe')) {
    Copy-Item $source $Destination -Force
}

$exePath = Join-Path $backupDir 'claude-2.1.302.exe'
$versionOut = (& $exePath --version 2>&1 | Out-String).Trim()
if ($versionOut -notmatch [regex]::Escape($Version)) { throw "engine --version mismatch: $versionOut" }

$hash = (Get-FileHash $exePath -Algorithm SHA256).Hash
$sig = (Get-AuthenticodeSignature $exePath).Status.ToString()

@(
    "SHA256=$hash"
    "Version=$Version"
    "Provenance=$provenance"
    "SignatureStatus=$sig"
    "Platform=$Platform"
) | Set-Content -Path (Join-Path $backupDir 'SHA256.txt') -Encoding UTF8

Write-Host "Pinned engine $Version ($provenance, signature $sig) -> $exePath"
