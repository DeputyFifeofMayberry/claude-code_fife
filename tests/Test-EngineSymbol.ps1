#Requires -Version 7.0
# The corner glyph patch: run the tool on a copy of the pinned engine, check
# the new mark's entries, the version and the record, then run it again.
$ErrorActionPreference = 'Stop'
$failures = @()
function Assert($cond, $msg) { if (-not $cond) { $script:failures += $msg } }

$repo = Split-Path -Parent $PSScriptRoot
$tool = Join-Path $repo 'fife\tools\Invoke-EngineSymbol.ps1'
$engine = 'C:\Users\barne\claude-fife-backup\claude-2.1.302.exe'
$record = 'C:\Users\barne\claude-fife-backup\SHA256.txt'

Assert (Test-Path $tool) 'glyph tool missing'
Assert (Test-Path $engine) "pinned engine missing: $engine"
Assert (Test-Path $record) "pin record missing: $record"
if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL: $_" }; exit 1 }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("fife-glyph-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$copy = Join-Path $tmp 'engine.exe'
$rec = Join-Path $tmp 'SHA256.txt'
Copy-Item $engine $copy -Force
Copy-Item $record $rec -Force

& pwsh -NoProfile -File $tool -Source $copy -Destination $copy -Record $rec | Out-Null
Assert ($LASTEXITCODE -eq 0) "glyph tool failed ($LASTEXITCODE)"

$tableBase = 122177408
function Read-U32([byte[]]$d, [int]$o) {
    [int]$d[$o] -bor ([int]$d[$o+1] -shl 8) -bor ([int]$d[$o+2] -shl 16) -bor ([int]$d[$o+3] -shl 24)
}
function Get-Text([byte[]]$d, [int]$index) {
    $p = $tableBase + (Read-U32 $d ($tableBase + 4 + 4 * $index))
    $w = Read-U32 $d $p
    $units = $w -band 0x7fffffff
    if (($w -band 0x80000000) -ne 0) { return [System.Text.Encoding]::Latin1.GetString($d, $p + 8, $units) }
    [System.Text.Encoding]::Unicode.GetString($d, $p + 8, $units * 2)
}

$bytes = [System.IO.File]::ReadAllBytes($copy)
$row0 = ' ▄█████▄ '
$row1 = '█████████'
$row2 = ' ▀█████▀ '
Assert ((Get-Text $bytes 59392) -eq ' ▄') 'top-left arm not patched'
Assert ((Get-Text $bytes 59399) -eq '█████▄') 'eyes not patched'
Assert ((Get-Text $bytes 59405) -eq $row2) 'feet not patched'
Assert ((Get-Text $bytes 59414) -eq $row1) 'facing row not patched'
Assert ((Get-Text $bytes 59431) -eq $row0) 'facing edge not patched'

$v = (& $copy --version 2>&1 | Out-String).Trim()
Assert ($v -match '2\.1\.302') "patched engine version wrong: $v"

$recLines = Get-Content $rec
Assert ($recLines -match '^SymbolMark=claude-fife-mark-9x3$') 'record missing SymbolMark'
Assert ($recLines -match '^SHA256=[0-9A-F]{64}$') 'record SHA256 malformed'
$newHash = ($recLines | Where-Object { $_ -like 'SHA256=*' }) -split '=', 2 | Select-Object -Last 1
Assert ((Get-FileHash $copy -Algorithm SHA256).Hash -eq $newHash) 'record SHA256 does not match the patched engine'

# Idempotent: a second run reports already patched and changes nothing.
$before = (Get-FileHash $copy -Algorithm SHA256).Hash
& pwsh -NoProfile -File $tool -Source $copy -Destination $copy -Record $rec | Out-Null
Assert ($LASTEXITCODE -eq 0) "glyph tool second run failed ($LASTEXITCODE)"
Assert ((Get-FileHash $copy -Algorithm SHA256).Hash -eq $before) 'second run rewrote the engine'

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL: $_" }; exit 1 }
Write-Host 'PASS: corner glyph patch'
