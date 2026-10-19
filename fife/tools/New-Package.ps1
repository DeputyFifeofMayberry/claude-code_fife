#Requires -Version 7.0
# Builds the claude-fife setup package zip. The Claude Code engine binary is not
# bundled: setup.ps1 installs the pinned, hash-verified engine from the backup
# produced by Get-PinnedEngine.ps1.
[CmdletBinding()]
param(
    [string]$Version = '2.1.302r1',
    [string]$OutputDir = (Join-Path $env:USERPROFILE 'claude-fife-packages')
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$name = "claude-fife-v$Version"

foreach ($p in 'fife\setup.ps1', 'fife\config\settings.template.json', 'docs\setup.md', 'LICENSE.md') {
    if (-not (Test-Path (Join-Path $repo $p))) { throw "Package input missing: $p" }
}

$stageParent = Join-Path ([System.IO.Path]::GetTempPath()) ("$name-" + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $stageParent $name
New-Item -ItemType Directory -Force -Path $stage | Out-Null
try {
    Copy-Item (Join-Path $repo 'fife') $stage -Recurse
    New-Item -ItemType Directory -Force -Path (Join-Path $stage 'docs') | Out-Null
    Copy-Item (Join-Path $repo 'docs\setup.md') (Join-Path $stage 'docs\setup.md')
    Copy-Item (Join-Path $repo 'LICENSE.md') $stage

    $commit = (& git -C $repo rev-parse --short HEAD 2>$null | Out-String).Trim()
    if (-not $commit) { $commit = 'unknown' }
    $readme = @"
# claude-fife v$Version

Setup package for claude-fife. The Claude Code engine binary is not bundled.
``fife\setup.ps1`` installs the pinned, hash-verified engine (2.1.302) from the
backup produced by ``fife\tools\Get-PinnedEngine.ps1``.

## Install

1. ``pwsh fife\tools\Get-PinnedEngine.ps1`` (once, if no verified backup exists)
2. ``pwsh fife\setup.ps1``

See ``docs\setup.md`` for restore and re-pin procedures.

Built from commit $commit.
"@
    Set-Content (Join-Path $stage 'PACKAGE.md') $readme -Encoding UTF8

    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $zip = Join-Path $OutputDir "$name.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal
    Write-Host "Package: $zip"
    Write-Host "SHA256: $((Get-FileHash $zip -Algorithm SHA256).Hash)"
    Write-Host "Commit: $commit"
} finally {
    Remove-Item $stageParent -Recurse -Force -ErrorAction SilentlyContinue
}
