#Requires -Version 7.0
# Concurrency: claude-fife and OpenCode coexist in the same project directory.
$ErrorActionPreference = 'Stop'
$failures = @()
function Assert($cond, $msg) { if (-not $cond) { $script:failures += $msg } }

$env:Path = [Environment]::GetEnvironmentVariable('Path','User') + ';' + [Environment]::GetEnvironmentVariable('Path','Machine')

# Scratch project with a shared CLAUDE.md (both tools must read it, not own it)
$proj = 'C:\Users\barne\claude-fife\concurrency-probe'
New-Item -ItemType Directory -Force -Path $proj | Out-Null
Set-Content (Join-Path $proj 'CLAUDE.md') '# Concurrency probe - shared instructions file. When asked for a word, reply with the single word: shared-ok.' -Encoding UTF8
Set-Content (Join-Path $proj 'sample.txt') 'probe content' -Encoding UTF8

# 1. claude-fife session in the project
Push-Location $proj
try {
    $fifeOut = (& pwsh -NoProfile -File 'C:\Users\barne\claude-fife\bin\claude-fife.ps1' -p 'What word does CLAUDE.md tell you to reply with? Reply with only that word.' 2>&1 | Out-String)
    $fifeCode = $LASTEXITCODE
    Assert ($fifeCode -eq 0 -and $fifeOut -match 'shared-ok') "claude-fite did not answer per shared CLAUDE.md: $fifeOut"

    # 2. OpenCode session in the same project (simple no-tool prompt: no permissions needed)
    $ocCmd = Get-Command opencode -ErrorAction SilentlyContinue
    if (-not $ocCmd) {
        $candidates = @("$env:USERPROFILE\.local\bin\opencode.exe", "$env:USERPROFILE\AppData\Local\Microsoft\WinGet\Links\opencode.exe")
        foreach ($c in $candidates) { if (Test-Path $c) { $ocCmd = $c; break } }
    }
    if (-not $ocCmd) { $ocCmd = 'opencode' }
    $ocOut = (& $ocCmd 'run' 'Reply with the single word: opencode-ok' 2>&1 | Out-String)
    $ocCode = $LASTEXITCODE
    Assert ($ocCode -eq 0 -and $ocOut -match 'opencode-ok') "opencode failed in same project: $ocOut"
} finally { Pop-Location }

# 3. Fife state went to fife tree only; project has no .claude artifacts from fife
$fifeProjects = 'C:\Users\barne\claude-fife\config\projects'
Assert (Test-Path $fifeProjects) 'fife projects dir missing'
$encoded = Get-ChildItem $fifeProjects -Directory | Where-Object Name -like '*claude-fife-concurrency-probe*'
Assert ($encoded) 'no fife project dir recorded for the probe'

if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL: $_" }; exit 1 }
Write-Host 'PASS: Test-Concurrency'
