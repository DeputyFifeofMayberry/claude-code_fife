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
  updates = $env:DISABLE_UPDATES
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
Assert (($rec.args -join '|') -eq '--allow-dangerously-skip-permissions|-p|hello world|--model|glm-test|say "hi"') "args mangled: $($rec.args -join '|')"
Assert ($rec.configDir -eq (Join-Path $env:CLAUDE_FIFE_ROOT 'config')) "config dir wrong: $($rec.configDir)"
Assert ($rec.autoupdater -eq '1') 'autoupdater not disabled for engine'
Assert ($rec.updates -eq '1') 'engine updates not disabled (DISABLE_UPDATES)'
Assert ($rec.baseUrl -eq 'http://127.0.0.1:8317') "router base url wrong: $($rec.baseUrl)"
Assert ($rec.discovery -eq '1') 'gateway model discovery not enabled'

# (a)+(d) via cmd shim
$env:STUB_OUT = Join-Path $tmp 'out2.json'
& cmd /c "`"$launcherCmd`" -p hello --model glm-test"
$code = $LASTEXITCODE
Assert ($code -eq 7) "cmd exit code not propagated (got $code)"
$rec2 = Get-Content $env:STUB_OUT -Raw | ConvertFrom-Json
Assert (($rec2.args -join '|') -eq '--allow-dangerously-skip-permissions|-p|hello|--model|glm-test') "cmd args mangled: $($rec2.args -join '|')"

# (e1) router started only when unhealthy
$marker = Join-Path $tmp 'router-started.txt'
$routerStub = Join-Path $tmp 'stub-router.cmd'
"@echo off`r`necho started > `"$marker`"" | Set-Content $routerStub -Encoding ASCII
Set-Content (Join-Path $tmp 'router.yaml') 'stub' -Encoding ASCII
$env:CLAUDE_FIFE_ROUTER_EXE = $routerStub
$env:CLAUDE_FIFE_ROUTER_CONFIG = Join-Path $tmp 'router.yaml'
$env:STUB_OUT = Join-Path $tmp 'out3.json'
& pwsh -NoProfile -File $launcherPs1 --help
Assert (Test-Path $marker) 'router was not started when unhealthy'

# (e2) router NOT started when healthy (something already listening)
Remove-Item $marker -ErrorAction SilentlyContinue
$py = (Get-Command python3 -ErrorAction SilentlyContinue).Source
if ($py) {
    $srv = Start-Process -FilePath $py -ArgumentList '-m','http.server','8399','--bind','127.0.0.1' -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 2
    $env:STUB_OUT = Join-Path $tmp 'out4.json'
    & pwsh -NoProfile -File $launcherPs1 --help
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
& $launcherPs1 --help
Assert ($env:CLAUDE_CONFIG_DIR -eq 'ORIGINAL-VALUE') 'launcher leaked CLAUDE_CONFIG_DIR into calling shell'
Assert ($env:ANTHROPIC_BASE_URL -eq $beforeEnv.ANTHROPIC_BASE_URL) 'launcher leaked ANTHROPIC_BASE_URL into calling shell'

# (g) --version names the fife build, not upstream Claude Code, and never
# reaches the engine.
$fakeRoot = $env:CLAUDE_FIFE_ROOT
New-Item -ItemType Directory -Force -Path (Join-Path $fakeRoot 'config') | Out-Null
Set-Content (Join-Path $fakeRoot 'config\fife-version.txt') '2.1.302r1' -Encoding UTF8 -NoNewline
$env:CLAUDE_FIFE_ENGINE_VERSION = '2.1.302'
$env:STUB_OUT = Join-Path $tmp 'out-version.json'
$versionOut = & pwsh -NoProfile -File $launcherPs1 --version 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 0) "version exit code wrong: $LASTEXITCODE"
Assert ($versionOut -match 'claude-fife 2\.1\.302r1') "fife build not named: $versionOut"
Assert ($versionOut -match 'Claude Code engine 2\.1\.302') "engine version not shown: $versionOut"
Assert (-not (Test-Path $env:STUB_OUT)) '--version reached the engine'
Remove-Item Env:CLAUDE_FIFE_ENGINE_VERSION -ErrorAction SilentlyContinue

# (f) update/upgrade are answered from the fork release; the verb never reaches
# the engine (whose updater would install upstream Claude Code outside the tree).
$env:CLAUDE_FIFE_EXIT_WITH_CODE = '1'
$fakeRoot = $env:CLAUDE_FIFE_ROOT
New-Item -ItemType Directory -Force -Path (Join-Path $fakeRoot 'config') | Out-Null
Set-Content (Join-Path $fakeRoot 'config\fife-version.txt') '2.1.302r1' -Encoding UTF8 -NoNewline
$feed = Join-Path $tmp 'release.json'
@{
  tag_name = 'v2.1.302r1'
  name     = 'claude-fife v2.1.302r1'
  body     = 'Setup package pinned to Claude Code 2.1.302.'
  assets   = @(@{
      name                 = 'claude-fife-v2.1.302r1.zip'
      digest               = 'sha256:90eedd8231b3fab386be8229fb376dece297196bf73a7f4b2eb4212e44838b5d'
      browser_download_url = 'https://example.invalid/claude-fife-v2.1.302r1.zip'
    })
} | ConvertTo-Json -Depth 5 | Set-Content $feed -Encoding UTF8

$env:CLAUDE_FIFE_RELEASES_API = $feed
$env:CLAUDE_FIFE_ENGINE_PATH = $stub
$env:STUB_OUT = Join-Path $tmp 'out-update1.json'
$updateOut = & pwsh -NoProfile -File $launcherPs1 update 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 0) "update exit code wrong: $LASTEXITCODE"
Assert ($updateOut -match 'Up to date with the latest fork release') "same version not reported up to date: $updateOut"
$recU = Get-Content $env:STUB_OUT -Raw | ConvertFrom-Json
Assert (($recU.args -join '|') -eq '--version') "update verb reached the engine: $($recU.args -join '|')"

@{
  tag_name = 'v2.1.303r1'
  name     = 'claude-fife v2.1.303r1'
  body     = 'Setup package pinned to Claude Code 2.1.303.'
  assets   = @(@{
      name                 = 'claude-fife-v2.1.303r1.zip'
      digest               = 'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
      browser_download_url = 'https://example.invalid/claude-fife-v2.1.303r1.zip'
    })
} | ConvertTo-Json -Depth 5 | Set-Content $feed -Encoding UTF8
$updateOut2 = & pwsh -NoProfile -File $launcherPs1 upgrade 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 0) "upgrade exit code wrong: $LASTEXITCODE"
Assert ($updateOut2 -match 'newer fork release is available: 2\.1\.303r1') "newer release not reported: $updateOut2"
Assert ($updateOut2 -match '0123456789ABCDEF') "release asset hash not shown: $updateOut2"
Assert ($updateOut2 -match 'fife\\setup\.ps1') "apply instructions missing: $updateOut2"

# A repo setup records dev-<commit>; the release body names its source commit.
Set-Content (Join-Path $fakeRoot 'config\fife-version.txt') 'dev-a0ea2de' -Encoding UTF8 -NoNewline
@{
  tag_name = 'v2.1.302r1'
  name     = 'claude-fife v2.1.302r1'
  body     = "Setup package pinned to Claude Code 2.1.302.`n`nSource commit: ``a0ea2de``"
  assets   = @(@{
      name                 = 'claude-fife-v2.1.302r1.zip'
      digest               = 'sha256:90eedd8231b3fab386be8229fb376dece297196bf73a7f4b2eb4212e44838b5d'
      browser_download_url = 'https://example.invalid/claude-fife-v2.1.302r1.zip'
    })
} | ConvertTo-Json -Depth 5 | Set-Content $feed -Encoding UTF8
$env:CLAUDE_FIFE_ENGINE_VERSION = '2.1.302'
$devOut = & pwsh -NoProfile -File $launcherPs1 update 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 0) "dev build update exit code wrong: $LASTEXITCODE"
Assert ($devOut -match 'based on the latest fork release \(2\.1\.302r1, commit a0ea2de\)') "dev build from release commit not recognized: $devOut"
Remove-Item Env:CLAUDE_FIFE_ENGINE_VERSION -ErrorAction SilentlyContinue

$env:CLAUDE_FIFE_RELEASES_API = Join-Path $tmp 'missing-release.json'
& pwsh -NoProfile -File $launcherPs1 update 2>&1 | Out-Null
Assert ($LASTEXITCODE -eq 1) "unreachable release feed should exit 1, got $LASTEXITCODE"

# the engine installer verb is blocked outright
$env:STUB_OUT = Join-Path $tmp 'out-install.json'
$installOut = & pwsh -NoProfile -File $launcherPs1 install latest 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 1) "install should be blocked, got $LASTEXITCODE"
Assert ($installOut -match 'engine installer is disabled') "install block message missing: $installOut"
Assert (-not (Test-Path $env:STUB_OUT)) 'install reached the engine'

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL: $_" }; exit 1 }
Write-Host 'PASS: Test-Launcher'
