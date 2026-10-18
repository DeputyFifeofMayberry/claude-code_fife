#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$failures = @()
function Assert($cond, $msg) { if (-not $cond) { $script:failures += $msg } }

$repo = Split-Path -Parent $PSScriptRoot
$launcherPs1 = Join-Path $repo 'fife\launcher\claude-fife.ps1'
$launcherCmd = Join-Path $repo 'fife\launcher\claude-fife.cmd'
Assert (Test-Path $launcherPs1) 'launcher ps1 missing'
Assert (Test-Path $launcherCmd) 'launcher cmd missing'
if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL: $_" }; exit 1 }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("fife-launcher-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# Stub engine (ps1): records args + env as JSON, exits 7.
$stub = Join-Path $tmp 'stub-engine.ps1'
@'
$out = $env:STUB_OUT
$rec = @{
  args = @($args | ForEach-Object { "$_" })
  configDir = $env:CLAUDE_CONFIG_DIR
  autoupdater = $env:DISABLE_AUTOUPDATER
  baseUrl = $env:ANTHROPIC_BASE_URL
  discovery = $env:CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY
}
$rec | ConvertTo-Json | Set-Content $out -Encoding UTF8
exit 7
'@ | Set-Content $stub -Encoding UTF8

$env:CLAUDE_FIFE_ENGINE_PATH = $stub
$env:CLAUDE_FIFE_ROOT = Join-Path $tmp 'fiferroot'
$env:CLAUDE_FIFE_ROUTER_EXE = Join-Path $tmp 'no-router.exe'
$env:CLAUDE_FIFE_ROUTER_URL = 'http://127.0.0.1:8317'
$env:CLAUDE_FIFE_HEALTH_URL = 'http://127.0.0.1:8399'
$env:CLAUDE_FIFE_ROUTER_WAIT_SEC = '3'
$env:STUB_OUT = Join-Path $tmp 'out1.json'
$env:CLAUDE_FIFE_EXIT_WITH_CODE = '1'

# (a)+(b)+(d) via ps1 subprocess
& pwsh -NoProfile -File $launcherPs1 -p 'hello world' --model glm-test 'say "hi"'
$code = $LASTEXITCODE
Assert ($code -eq 7) "ps1 exit code not propagated (got $code)"
$rec = Get-Content $env:STUB_OUT -Raw | ConvertFrom-Json
Assert (($rec.args -join '|') -eq '-p|hello world|--model|glm-test|say "hi"') "args mangled: $($rec.args -join '|')"
Assert ($rec.configDir -eq (Join-Path $env:CLAUDE_FIFE_ROOT 'config')) "config dir wrong: $($rec.configDir)"
Assert ($rec.autoupdater -eq '1') 'autoupdater not disabled for engine'
Assert ($rec.baseUrl -eq 'http://127.0.0.1:8317') "router base url wrong: $($rec.baseUrl)"
Assert ($rec.discovery -eq '1') 'gateway model discovery not enabled'

# (a)+(d) via cmd shim
$env:STUB_OUT = Join-Path $tmp 'out2.json'
& cmd /c "`"$launcherCmd`" -p hello --model glm-test"
$code = $LASTEXITCODE
Assert ($code -eq 7) "cmd exit code not propagated (got $code)"
$rec2 = Get-Content $env:STUB_OUT -Raw | ConvertFrom-Json
Assert (($rec2.args -join '|') -eq '-p|hello|--model|glm-test') "cmd args mangled: $($rec2.args -join '|')"

# (e1) router started only when unhealthy
$marker = Join-Path $tmp 'router-started.txt'
$routerStub = Join-Path $tmp 'stub-router.cmd'
"@echo off`r`necho started > `"$marker`"" | Set-Content $routerStub -Encoding ASCII
Set-Content (Join-Path $tmp 'router.yaml') 'stub' -Encoding ASCII
$env:CLAUDE_FIFE_ROUTER_EXE = $routerStub
$env:CLAUDE_FIFE_ROUTER_CONFIG = Join-Path $tmp 'router.yaml'
$env:STUB_OUT = Join-Path $tmp 'out3.json'
& pwsh -NoProfile -File $launcherPs1 --version
Assert (Test-Path $marker) 'router was not started when unhealthy'

# (e2) router NOT started when healthy (something already listening)
Remove-Item $marker -ErrorAction SilentlyContinue
$py = (Get-Command python3 -ErrorAction SilentlyContinue).Source
if ($py) {
    $srv = Start-Process -FilePath $py -ArgumentList '-m','http.server','8399','--bind','127.0.0.1' -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 2
    $env:STUB_OUT = Join-Path $tmp 'out4.json'
    & pwsh -NoProfile -File $launcherPs1 --version
    Assert (-not (Test-Path $marker)) 'router started even though port was healthy'
    Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue
} else {
    Write-Host 'SKIP: python3 not found for healthy-router test'
}

# (c) calling shell env untouched (in-process invocation)
$stubCmd = Join-Path $tmp 'stub-engine.cmd'
"@echo off`r`nexit /b 3" | Set-Content $stubCmd -Encoding ASCII
$env:CLAUDE_FIFE_ENGINE_PATH = $stubCmd
$env:CLAUDE_FIFE_EXIT_WITH_CODE = '0'
$beforeEnv = @{ CLAUDE_CONFIG_DIR = $env:CLAUDE_CONFIG_DIR; ANTHROPIC_BASE_URL = $env:ANTHROPIC_BASE_URL }
$env:CLAUDE_CONFIG_DIR = 'ORIGINAL-VALUE'
& $launcherPs1 --version
Assert ($env:CLAUDE_CONFIG_DIR -eq 'ORIGINAL-VALUE') 'launcher leaked CLAUDE_CONFIG_DIR into calling shell'
Assert ($env:ANTHROPIC_BASE_URL -eq $beforeEnv.ANTHROPIC_BASE_URL) 'launcher leaked ANTHROPIC_BASE_URL into calling shell'

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL: $_" }; exit 1 }
Write-Host 'PASS: Test-Launcher'
