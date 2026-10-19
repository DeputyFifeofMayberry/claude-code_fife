#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$failures = @()
function Assert($cond, $msg) { if (-not $cond) { $script:failures += $msg } }

$repo = Split-Path -Parent $PSScriptRoot
$tool = Join-Path $repo 'fife\tools\New-Package.ps1'
Assert (Test-Path $tool) 'New-Package.ps1 missing'
if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL: $_" }; exit 1 }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("fife-package-test-" + [guid]::NewGuid().ToString('N'))
& pwsh -NoProfile -File $tool -Version 'test' -OutputDir $tmp | Out-Null
Assert ($LASTEXITCODE -eq 0) "package build failed ($LASTEXITCODE)"

$zip = Join-Path $tmp 'claude-fife-vtest.zip'
Assert (Test-Path $zip) 'package zip not created'
if (Test-Path $zip) {
    $extract = Join-Path $tmp 'extract'
    Expand-Archive $zip -DestinationPath $extract -Force
    $root = Join-Path $extract 'claude-fife-vtest'
    Assert (Test-Path (Join-Path $root 'fife\setup.ps1')) 'setup.ps1 not in package'
    Assert (Test-Path (Join-Path $root 'fife\launcher\claude-fife.ps1')) 'launcher not in package'
    Assert (Test-Path (Join-Path $root 'fife\config\settings.template.json')) 'settings template not in package'
    Assert (Test-Path (Join-Path $root 'docs\setup.md')) 'setup docs not in package'
    Assert (Test-Path (Join-Path $root 'PACKAGE.md')) 'PACKAGE.md not in package'
    Assert (-not (Test-Path (Join-Path $root 'fife\setup.ps1.test'))) 'unexpected file in package'
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL: $_" }; exit 1 }
Write-Host 'PASS: Test-Package'
