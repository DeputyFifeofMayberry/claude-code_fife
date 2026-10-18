#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$failures = @()
function Assert($cond, $msg) { if (-not $cond) { $script:failures += $msg } }

$repo = Split-Path -Parent $PSScriptRoot
$setup = Join-Path $repo 'fife\setup.ps1'
Assert (Test-Path $setup) 'setup.ps1 missing'
if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL: $_" }; exit 1 }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("fife-setup-test-" + [guid]::NewGuid().ToString('N'))
$routerSrc = 'C:\Users\barne\AppData\Local\Temp\opencode\router-spike\cliproxy\cli-proxy-api.exe'

# Run setup twice (idempotency)
& pwsh -NoProfile -File $setup -Root $tmp -SkipPath -RouterExeSource $routerSrc | Out-Null
Assert ($LASTEXITCODE -eq 0) "setup run 1 failed ($LASTEXITCODE)"
& pwsh -NoProfile -File $setup -Root $tmp -SkipPath -RouterExeSource $routerSrc | Out-Null
Assert ($LASTEXITCODE -eq 0) "setup run 2 (idempotency) failed ($LASTEXITCODE)"

foreach ($d in 'bin','config','router','logs') {
    Assert (Test-Path (Join-Path $tmp $d)) "missing dir: $d"
}
$engine = Join-Path $tmp 'bin\claude-fife-engine.exe'
Assert (Test-Path $engine) 'engine not installed in bin'
if (Test-Path $engine) {
    Assert (((& $engine --version 2>&1 | Out-String).Trim()) -match '2\.1\.302') 'engine version wrong'
    $rec = Get-Content 'C:\Users\barne\claude-fife-backup\SHA256.txt' | Where-Object { $_ -like 'SHA256=*' }
    $expected = ($rec -split '=',2)[1]
    Assert ((Get-FileHash $engine -Algorithm SHA256).Hash -eq $expected) 'engine hash differs from backup record'
}
Assert (Test-Path (Join-Path $tmp 'bin\claude-fife.ps1')) 'launcher ps1 not copied to bin'
Assert (Test-Path (Join-Path $tmp 'bin\claude-fife.cmd')) 'launcher cmd not copied to bin'

$settings = Join-Path $tmp 'config\settings.json'
Assert (Test-Path $settings) 'settings.json not created'
if (Test-Path $settings) {
    $sj = Get-Content $settings -Raw | ConvertFrom-Json
    Assert ($sj.autoUpdates -eq $false) 'settings autoUpdates not false'
}

$cfgPath = Join-Path $tmp 'router\config.yaml'
Assert (Test-Path $cfgPath) 'router config not created'
$keyPath = Join-Path $tmp 'router\api-key.txt'
Assert (Test-Path $keyPath) 'router api-key.txt not created'
if (Test-Path $cfgPath) {
    $cfg = Get-Content $cfgPath -Raw
    Assert ($cfg -match 'host:\s*"127\.0\.0\.1"') 'router not bound to 127.0.0.1'
    Assert ($cfg -match 'port:\s*8317') 'router port not 8317'
    Assert ($cfg -match 'request-log:\s*false') 'router request-log not false'
    if (Test-Path $keyPath) {
        $localKey = (Get-Content $keyPath -Raw).Trim()
        Assert ($localKey.Length -ge 16) 'router local key too short'
        Assert ($cfg.Contains($localKey)) 'router local key not in config access keys'
    }
    # z.ai secret: must be in router config ONLY (within this temp root)
    $pycode = 'import sqlite3,json,pathlib; con=sqlite3.connect("file:"+str(pathlib.Path.home()/".local"/"share"/"opencode"/"opencode-local.db")+"?mode=ro", uri=True); r=con.execute("SELECT value FROM credential WHERE integration_id=? AND active=1 LIMIT 1", ("zai-coding-plan",)).fetchone(); print(json.loads(r[0])["key"])'
    $zai = (& python3 -c $pycode 2>$null | Out-String).Trim()
    Assert ($zai.Length -gt 10) 'could not read z.ai credential from OpenCode store for verification'
    if ($zai.Length -gt 10) {
        Assert ($cfg.Contains($zai)) 'z.ai key not provisioned into router config'
        $leaks = Get-ChildItem $tmp -Recurse -File | Where-Object { $_.FullName -ne $cfgPath } |
            Select-String -SimpleMatch $zai -List -ErrorAction SilentlyContinue
        Assert (-not $leaks) "z.ai key leaked into other files: $($leaks.Path -join ', ')"
        $repoLeaks = Get-ChildItem $repo -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notlike '*\.git\*' } |
            Select-String -SimpleMatch $zai -List -ErrorAction SilentlyContinue
        Assert (-not $repoLeaks) "z.ai key leaked into repo: $($repoLeaks.Path -join ', ')"
    }
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL: $_" }; exit 1 }
Write-Host 'PASS: Test-Setup'
