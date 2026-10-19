#Requires -Version 7.0
# Acceptance gauntlet: criteria 1-5 from the design.
$ErrorActionPreference = 'Stop'
$checks = New-Object System.Collections.Generic.List[string]
function Check([string]$name, [scriptblock]$sb) {
    try { $ok = & $sb; if ($ok) { $checks.Add("PASS $name") } else { $checks.Add("FAIL $name") } }
    catch { $checks.Add("FAIL $name - $($_.Exception.Message)") }
}
$env:Path = [Environment]::GetEnvironmentVariable('Path','User') + ';' + [Environment]::GetEnvironmentVariable('Path','Machine')
# Keep the acceptance gauntlet offline and deterministic; the upstream check
# has its own tests in Test-Launcher.ps1.
$env:CLAUDE_FIFE_UPSTREAM_CHECK = '0'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tests = Join-Path $repo 'tests'

Check '1a version via PATH (PowerShell)' { $v = (claude-fife --version 2>&1 | Out-String).Trim(); $v -match '^claude-fife ' -and $v -match '2\.1\.303' }
Check '1b version via cmd' { $v = (cmd /c 'claude-fife --version' 2>&1 | Out-String).Trim(); $v -match '^claude-fife ' -and $v -match '2\.1\.303' }
Check '1c help works' { ((claude-fife --help 2>&1 | Out-String)) -match 'Usage|claude' }
Check '2a anthropic backend prompt' {
    $env:CLAUDE_FIFE_EXIT_WITH_CODE = '1'
    $o = (& pwsh -NoProfile -File 'C:\Users\barne\claude-fife\bin\claude-fife.ps1' -p 'reply with the single word: ok' --model 'claude-sonnet-4-5-20250929' 2>&1 | Out-String); $c = $LASTEXITCODE; Remove-Item Env:CLAUDE_FIFE_EXIT_WITH_CODE -ErrorAction SilentlyContinue; $c -eq 0 -and $o -match 'ok' }
Check '2b zai backend prompt' {
    $env:CLAUDE_FIFE_EXIT_WITH_CODE = '1'
    $o = (& pwsh -NoProfile -File 'C:\Users\barne\claude-fife\bin\claude-fife.ps1' -p 'reply with the single word: ok' --model 'glm-5.3' 2>&1 | Out-String); $c = $LASTEXITCODE; Remove-Item Env:CLAUDE_FIFE_EXIT_WITH_CODE -ErrorAction SilentlyContinue; $c -eq 0 -and $o -match 'ok' }
Check '2c codex backend prompt' {
    $codexModel = ((Invoke-RestMethod -Uri 'http://127.0.0.1:8317/v1/models' -Headers @{ Authorization = "Bearer $((Get-Content 'C:\Users\barne\claude-fife\router\api-key.txt' -Raw).Trim())" }).data.id | Where-Object { $_ -match '^gpt-(5|6)' } | Select-Object -First 1)
    $env:CLAUDE_FIFE_EXIT_WITH_CODE = '1'
    $o = (& pwsh -NoProfile -File 'C:\Users\barne\claude-fife\bin\claude-fife.ps1' -p 'reply with the single word: ok' --model $codexModel 2>&1 | Out-String); $c = $LASTEXITCODE; Remove-Item Env:CLAUDE_FIFE_EXIT_WITH_CODE -ErrorAction SilentlyContinue; $c -eq 0 -and $o -match 'ok' }
Check '2d default launch served' {
    $env:CLAUDE_FIFE_EXIT_WITH_CODE = '1'
    $o = (& pwsh -NoProfile -File 'C:\Users\barne\claude-fife\bin\claude-fife.ps1' -p 'reply with the single word: ok' 2>&1 | Out-String); $c = $LASTEXITCODE; Remove-Item Env:CLAUDE_FIFE_EXIT_WITH_CODE -ErrorAction SilentlyContinue; $c -eq 0 -and $o -match 'ok' }
# Child-script output must not leak into the scriptblock's return value: Check
# treats any output as truthy, so a failing sub-test would pass. Capture it and
# keep only the boolean, printing the child's output when it fails.
Check '3 file-tree isolation' {
    $iso = & pwsh -NoProfile -File (Join-Path $tests 'Test-Isolation.ps1') 2>&1 | Out-String
    $isoCode = $LASTEXITCODE
    if ($isoCode -ne 0) { Write-Host $iso }
    ($isoCode -eq 0) -and -not ($Error | Where-Object { $_.Exception.Message -like '*not recognized*' })
}
Check '4a codex CLI healthy after router use' {
    $codex = & codex exec 'reply with the single word: ok' 2>&1 | Out-String
    $codexCode = $LASTEXITCODE
    if ($codexCode -ne 0) { Write-Host $codex }
    $codexCode -eq 0
}
Check '4b opencode healthy' { (& opencode run 'Reply with the single word: opencode-ok' 2>&1 | Out-String) -match 'opencode-ok' }
Check '5 concurrency in shared project' {
    $Error.Clear()
    $conc = & pwsh -NoProfile -File (Join-Path $tests 'Test-Concurrency.ps1') 2>&1 | Out-String
    $concCode = $LASTEXITCODE
    if ($concCode -ne 0) { Write-Host $conc }
    ($concCode -eq 0) -and -not ($Error | Where-Object { $_.Exception.Message -like '*not recognized*' })
}

# Secret-leak sweep: delegated to the hardened whole-fife-root sweep (also
# covers prompt-dump logs and the router-local key). The repo is swept too.
& pwsh -NoProfile -File (Join-Path $tests 'Test-SecretSweep.ps1')
$sweepCode = $LASTEXITCODE
$repoClean = $true
$zai = (& python3 -c 'import sqlite3,json,pathlib; con=sqlite3.connect("file:"+str(pathlib.Path.home()/".local"/"share"/"opencode"/"opencode-local.db")+"?mode=ro", uri=True); r=con.execute("SELECT value FROM credential WHERE integration_id=? AND active=1 LIMIT 1", ("zai-coding-plan",)).fetchone(); print(json.loads(r[0])["key"])' | Out-String).Trim()
$repoHits = Get-ChildItem $repo -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike '*\.git\*' -and $_.FullName -notlike '*\.superpowers*' } |
    Select-String -SimpleMatch $zai -List -ErrorAction SilentlyContinue
if ($repoHits) { $repoClean = $false }
Check '6 no secret leakage or prompt dumps (fife root + repo)' { ($sweepCode -eq 0) -and $repoClean }

$checks | ForEach-Object { Write-Host $_ }
$fails = @($checks | Where-Object { $_ -like 'FAIL*' })
if ($fails.Count) { Write-Host "ACCEPTANCE: $($checks.Count - $fails.Count)/$($checks.Count)"; exit 1 }
Write-Host 'ACCEPTANCE: all checks passed'
