#Requires -Version 7.0
# Acceptance gauntlet: criteria 1-5 from the design.
$ErrorActionPreference = 'Stop'
$checks = New-Object System.Collections.Generic.List[string]
function Check([string]$name, [scriptblock]$sb) {
    try { $ok = & $sb; if ($ok) { $checks.Add("PASS $name") } else { $checks.Add("FAIL $name") } }
    catch { $checks.Add("FAIL $name - $($_.Exception.Message)") }
}
$env:Path = [Environment]::GetEnvironmentVariable('Path','User') + ';' + [Environment]::GetEnvironmentVariable('Path','Machine')
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tests = Join-Path $repo 'tests'

Check '1a version via PATH (PowerShell)' { (claude-fife --version 2>&1 | Out-String).Trim() -match '2\.1\.302' }
Check '1b version via cmd' { (cmd /c 'claude-fife --version' 2>&1 | Out-String).Trim() -match '2\.1\.302' }
Check '1c help works' { ((claude-fife --help 2>&1 | Out-String)) -match 'Usage|claude' }
Check '2a anthropic backend prompt' {
    $o = (& pwsh -NoProfile -File 'C:\Users\barne\claude-fife\bin\claude-fife.ps1' -p 'reply with the single word: ok' --model 'claude-sonnet-4-5-20250929' 2>&1 | Out-String); $LASTEXITCODE -eq 0 -and $o -match 'ok' }
Check '2b zai backend prompt' {
    $o = (& pwsh -NoProfile -File 'C:\Users\barne\claude-fife\bin\claude-fife.ps1' -p 'reply with the single word: ok' --model 'glm-5.3' 2>&1 | Out-String); $LASTEXITCODE -eq 0 -and $o -match 'ok' }
Check '2c codex backend prompt' {
    $codexModel = ((Invoke-RestMethod -Uri 'http://127.0.0.1:8317/v1/models' -Headers @{ Authorization = "Bearer $((Get-Content 'C:\Users\barne\claude-fife\router\api-key.txt' -Raw).Trim())" }).data.id | Where-Object { $_ -match '^gpt-(5|6)' } | Select-Object -First 1)
    $o = (& pwsh -NoProfile -File 'C:\Users\barne\claude-fife\bin\claude-fife.ps1' -p 'reply with the single word: ok' --model $codexModel 2>&1 | Out-String); $LASTEXITCODE -eq 0 -and $o -match 'ok' }
Check '2d default launch served' {
    $o = (& pwsh -NoProfile -File 'C:\Users\barne\claude-fife\bin\claude-fife.ps1' -p 'reply with the single word: ok' 2>&1 | Out-String); $LASTEXITCODE -eq 0 -and $o -match 'ok' }
Check '3 file-tree isolation' { & pwsh -NoProfile -File (Join-Path $tests 'Test-Isolation.ps1'); ($LASTEXITCODE -eq 0) -and -not ($Error | Where-Object { $_.Exception.Message -like '*not recognized*' }) }
Check '4a codex CLI healthy after router use' { (& codex exec 'reply with the single word: ok' 2>&1 | Out-String); $LASTEXITCODE -eq 0 }
Check '4b opencode healthy' { (& opencode run 'Reply with the single word: opencode-ok' 2>&1 | Out-String) -match 'opencode-ok' }
Check '5 concurrency in shared project' { $Error.Clear(); & pwsh -NoProfile -File (Join-Path $tests 'Test-Concurrency.ps1'); ($LASTEXITCODE -eq 0) -and -not ($Error | Where-Object { $_.Exception.Message -like '*not recognized*' }) }

# Secret-leak sweep: live z.ai key must appear only in fife router config
$zai = (& python3 -c 'import sqlite3,json,pathlib; con=sqlite3.connect("file:"+str(pathlib.Path.home()/".local"/"share"/"opencode"/"opencode-local.db")+"?mode=ro", uri=True); r=con.execute("SELECT value FROM credential WHERE integration_id=? AND active=1 LIMIT 1", ("zai-coding-plan",)).fetchone(); print(json.loads(r[0])["key"])' | Out-String).Trim()
$allowed = (Resolve-Path 'C:\Users\barne\claude-fife\router\config.yaml').Path
$hits = Get-ChildItem $repo,'C:\Users\barne\claude-fife\logs','C:\Users\barne\claude-fife\router\logs' -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike '*\.git\*' -and $_.FullName -ne $allowed } |
    Select-String -SimpleMatch $zai -List -ErrorAction SilentlyContinue
Check '6 no secret leakage (repo + logs)' { -not $hits }

$checks | ForEach-Object { Write-Host $_ }
$fails = @($checks | Where-Object { $_ -like 'FAIL*' })
if ($fails.Count) { Write-Host "ACCEPTANCE: $($checks.Count - $fails.Count)/$($checks.Count)"; exit 1 }
Write-Host 'ACCEPTANCE: all checks passed'
