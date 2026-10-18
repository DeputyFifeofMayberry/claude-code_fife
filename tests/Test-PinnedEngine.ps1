#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$failures = @()
function Assert($cond, $msg) { if (-not $cond) { $script:failures += $msg } }

$backupDir = 'C:\Users\barne\claude-fife-backup'
$exe = Join-Path $backupDir 'claude-2.1.302.exe'
$record = Join-Path $backupDir 'SHA256.txt'

Assert (Test-Path $exe) "backup exe missing: $exe"
Assert (Test-Path $record) "hash record missing: $record"

if (Test-Path $record) {
    $kv = @{}
    foreach ($line in Get-Content $record) {
        if ($line -match '^([^=]+)=(.*)$') { $kv[$Matches[1]] = $Matches[2] }
    }
    Assert ($kv.ContainsKey('SHA256') -and $kv.SHA256 -match '^[0-9A-Fa-f]{64}$') 'SHA256 missing/malformed in record'
    Assert ($kv.Provenance -in @('fresh-download','copied-installed')) "Provenance missing/invalid: $($kv.Provenance)"
    Assert (-not [string]::IsNullOrWhiteSpace($kv.SignatureStatus)) 'SignatureStatus not recorded'
    Assert ($kv.Version -eq '2.1.302') "Version not recorded as 2.1.302: $($kv.Version)"
    if (Test-Path $exe) {
        $actual = (Get-FileHash $exe -Algorithm SHA256).Hash
        Assert ($actual -eq $kv.SHA256) 'exe hash does not match record'
    }
}

if (Test-Path $exe) {
    $version = (& $exe --version 2>&1 | Out-String).Trim()
    Assert ($version -match '2\.1\.302') "engine --version not 2.1.302: $version"
}

if ($failures.Count) {
    $failures | ForEach-Object { Write-Host "FAIL: $_" }
    exit 1
}
Write-Host 'PASS: Test-PinnedEngine'
