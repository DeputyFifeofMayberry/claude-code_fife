#Requires -Version 7.0
# Verifies the pinned engine, run with fife env, writes only inside the fife root.
# Windows Credential Manager entries are pre-approved (checked separately, not here).
$ErrorActionPreference = 'Stop'
$failures = @()
function Assert($cond, $msg) { if (-not $cond) { $script:failures += $msg } }

$engine = 'C:\Users\barne\claude-fife-backup\claude-2.1.303.exe'
$fifeRoot = 'C:\Users\barne\claude-fife'
$configDir = Join-Path $fifeRoot 'config'

function Snapshot([string[]]$roots) {
    $map = @{}
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne (Join-Path $env:LOCALAPPDATA 'Temp') } |
            ForEach-Object {
                $map[$_.FullName] = "$($_.LastWriteTimeUtc.Ticks):$($_.Length)"
            }
    }
    return $map
}

$watch = @($env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA)
$before = Snapshot $watch

$env:CLAUDE_CONFIG_DIR = $configDir
$env:DISABLE_AUTOUPDATER = '1'
New-Item -ItemType Directory -Force -Path $configDir | Out-Null

$v = (& $engine --version 2>&1 | Out-String).Trim()
Assert ($v -match '2\.1\.302') "version run failed: $v"
# Headless prompt attempt: may fail on auth pre-login; file placement is under test.
$probeDir = Join-Path $fifeRoot 'probe-project'
New-Item -ItemType Directory -Force -Path $probeDir | Out-Null
Push-Location $probeDir
try { & $engine -p 'reply ok' 2>&1 | Out-Null } catch { }
Pop-Location

$after = Snapshot $watch
foreach ($k in $after.Keys) {
    if ($k -like "$fifeRoot*") { continue }
    if (-not $before.ContainsKey($k) -or $before[$k] -ne $after[$k]) {
        # Only top-level entries are watched; the fife root itself is allowed.
        $failures += "out-of-tree change: $k"
    }
}
Assert (-not (Test-Path (Join-Path $env:USERPROFILE '.claude'))) '~/.claude was created'
Assert (-not (Test-Path (Join-Path $env:USERPROFILE '.claude.json'))) '~/.claude.json was created'

if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL: $_" }; exit 1 }
Write-Host 'PASS: Test-Isolation'
