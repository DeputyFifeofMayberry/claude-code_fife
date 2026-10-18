#Requires -Version 7.0
# Hardened secret sweep: the WHOLE fife root must be free of live secret values,
# except the two designated secret-bearing files. Missing expected files = FAIL.
param(
    [string]$FifeRoot = 'C:\Users\barne\claude-fife'
)
$ErrorActionPreference = 'Stop'
$failures = @()

$routerCfg = Join-Path $FifeRoot 'router\config.yaml'
$keyFile = Join-Path $FifeRoot 'router\api-key.txt'
foreach ($f in $routerCfg, $keyFile) {
    if (-not (Test-Path $f)) { $failures += "expected secret file missing: $f" }
}
if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL: $_" }; exit 1 }

$zai = (& python3 -c 'import sqlite3,json,pathlib; con=sqlite3.connect("file:"+str(pathlib.Path.home()/".local"/"share"/"opencode"/"opencode-local.db")+"?mode=ro", uri=True); r=con.execute("SELECT value FROM credential WHERE integration_id=? AND active=1 LIMIT 1", ("zai-coding-plan",)).fetchone(); print(json.loads(r[0])["key"])' | Out-String).Trim()
$localKey = (Get-Content $keyFile -Raw).Trim()
if ($zai.Length -lt 10) { $failures += 'could not read live z.ai key for sweep' }

$allowed = @((Resolve-Path $routerCfg).Path, (Resolve-Path $keyFile).Path)
$excludedNames = @('claude-fife-engine.exe', 'cli-proxy-api.exe')

$hits = Get-ChildItem $FifeRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $allowed -notcontains $_.FullName -and $excludedNames -notcontains $_.Name } |
    Select-String -Pattern @($zai, $localKey) -List -ErrorAction SilentlyContinue

if ($hits) {
    $failures += "secret values found in: $(($hits | ForEach-Object Path | Select-Object -Unique) -join ', ')"
}

# No prompt-dump logs anywhere in the fife tree (error logs carry headers+bodies)
$dumps = Get-ChildItem $FifeRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'error-*.log' -or $_.Name -like 'request-*.log' }
if ($dumps) { $failures += "request/error log dumps present: $($dumps.FullName -join ', ')" }

if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL: $_" }; exit 1 }
Write-Host 'PASS: Test-SecretSweep'
