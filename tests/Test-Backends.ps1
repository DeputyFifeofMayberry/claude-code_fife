#Requires -Version 7.0
# Proves all three backends answer through claude-fife, and the default is Anthropic.
$ErrorActionPreference = 'Stop'
$failures = @()
function Assert($cond, $msg) { if (-not $cond) { $script:failures += $msg } }

$env:Path = [Environment]::GetEnvironmentVariable('Path','User') + ';' + [Environment]::GetEnvironmentVariable('Path','Machine')

function Invoke-Fife([string[]]$fifeArgs) {
    $env:CLAUDE_FIFE_EXIT_WITH_CODE = '1'
    $out = (& pwsh -NoProfile -File 'C:\Users\barne\claude-fife\bin\claude-fife.ps1' @fifeArgs 2>&1 | Out-String)
    $code = $LASTEXITCODE
    Remove-Item Env:CLAUDE_FIFE_EXIT_WITH_CODE -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Code = $code; Out = $out }
}

# Anthropic subscription (default when --model omitted): pick a current Sonnet model id
$roster = (Invoke-RestMethod -Uri 'http://127.0.0.1:8317/v1/models' -Headers @{ Authorization = "Bearer $((Get-Content 'C:\Users\barne\claude-fife\router\api-key.txt' -Raw).Trim())" }).data.id
$anthroModel = $roster | Where-Object { $_ -match '^claude-sonnet-4-5' } | Select-Object -First 1
if (-not $anthroModel) { $anthroModel = $roster | Where-Object { $_ -match '^claude-sonnet' -and $_ -notmatch '-4-20250514$' } | Select-Object -First 1 }
$glmModel = 'glm-5.3'
$codexModel = $roster | Where-Object { $_ -match '^gpt-5' -or $_ -match '^gpt-6' } | Select-Object -First 1
Assert ($anthroModel) "no claude-sonnet model in roster"
Assert ($codexModel) "no gpt model in roster"

$r1 = Invoke-Fife @('-p', 'reply with the single word: ok', '--model', $anthroModel)
Assert ($r1.Code -eq 0 -and $r1.Out -match 'ok') "anthropic backend failed: $($r1.Out)"
$r2 = Invoke-Fife @('-p', 'reply with the single word: ok', '--model', $glmModel)
Assert ($r2.Code -eq 0 -and $r2.Out -match 'ok') "zai backend failed: $($r2.Out)"
$r3 = Invoke-Fife @('-p', 'reply with the single word: ok', '--model', $codexModel)
Assert ($r3.Code -eq 0 -and $r3.Out -match 'ok') "codex backend failed: $($r3.Out)"

# Codex CLI still works (refresh-token contention check)
$codexOut = (& codex exec 'reply with the single word: ok' 2>&1 | Out-String)
Assert ($LASTEXITCODE -eq 0) "codex CLI broken after router use: $codexOut"

# Default (no --model) is served by Anthropic
$r4 = Invoke-Fife @('-p', 'reply with the single word: ok')
Assert ($r4.Code -eq 0 -and $r4.Out -match 'ok') "default launch failed: $($r4.Out)"

# Isolation regression after real usage
& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Test-Isolation.ps1')
Assert ($LASTEXITCODE -eq 0) 'isolation regression failed'

if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL: $_" }; exit 1 }
Write-Host 'PASS: Test-Backends'
