#Requires -Version 7.0
# claude-fife setup: builds/repairs the fife tree on this machine.
# Idempotent. Secrets are provisioned into the fife tree only, never printed.
[CmdletBinding()]
param(
    [string]$Root = 'C:\Users\barne\claude-fife',
    [string]$BackupDir = 'C:\Users\barne\claude-fife-backup',
    [string]$RouterExeSource = '',
    [switch]$SkipPath
)
$ErrorActionPreference = 'Stop'
$fifeSrc = $PSScriptRoot

function Get-ZaiKey {
    $db = Join-Path $env:USERPROFILE '.local\share\opencode\opencode-local.db'
    if (-not (Test-Path $db)) { return $null }
    $py = (Get-Command python3 -ErrorAction SilentlyContinue).Source
    if (-not $py) { return $null }
    $code = 'import sqlite3,json,pathlib; con=sqlite3.connect("file:"+str(pathlib.Path.home()/".local"/"share"/"opencode"/"opencode-local.db")+"?mode=ro", uri=True); r=con.execute("SELECT value FROM credential WHERE integration_id=? AND active=1 LIMIT 1", ("zai-coding-plan",)).fetchone(); print(json.loads(r[0])["key"])'
    try { return (& $py -c $code 2>$null | Out-String).Trim() } catch { return $null }
}

function Get-OpenRouterKey {
    $k = $env:OPENROUTER_API_KEY
    if ($k) { return $k.Trim() }
    return $null
}

# 1. Tree
foreach ($d in 'bin','config','router','logs',(Join-Path 'router' 'auth')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Root $d) | Out-Null
}

# 2. Engine from verified backup + launchers
$recordFile = Join-Path $BackupDir 'SHA256.txt'
$backupExe = Join-Path $BackupDir 'claude-2.1.302.exe'
if (-not (Test-Path $backupExe)) { throw "Pinned engine backup missing: $backupExe (run fife\tools\Get-PinnedEngine.ps1)" }
$expectedHash = ((Get-Content $recordFile | Where-Object { $_ -like 'SHA256=*' }) -split '=',2)[1]
if ((Get-FileHash $backupExe -Algorithm SHA256).Hash -ne $expectedHash) { throw 'Backup engine hash mismatch - refusing to install.' }
Copy-Item $backupExe (Join-Path $Root 'bin\claude-fife-engine.exe') -Force
Copy-Item (Join-Path $fifeSrc 'launcher\claude-fife.ps1') (Join-Path $Root 'bin\claude-fife.ps1') -Force
Copy-Item (Join-Path $fifeSrc 'launcher\claude-fife.cmd') (Join-Path $Root 'bin\claude-fife.cmd') -Force

# 3. Settings (create once; never overwrite user edits)
$settingsOut = Join-Path $Root 'config\settings.json'
if (-not (Test-Path $settingsOut)) {
    Copy-Item (Join-Path $fifeSrc 'config\settings.template.json') $settingsOut
}

# 4. Router exe (pinned CLIProxyAPI v8.0.33, hash-verified)
$routerExe = Join-Path $Root 'router\cli-proxy-api.exe'
$routerPinFile = Join-Path $fifeSrc 'config\router-pin.txt'
$routerPin = @{};
foreach ($line in Get-Content $routerPinFile) { if ($line -match '^([^=]+)=(.*)$') { $routerPin[$Matches[1]] = $Matches[2] } }
if (-not (Test-Path $routerExe)) {
    if ($RouterExeSource -and (Test-Path $RouterExeSource)) {
        Copy-Item $RouterExeSource $routerExe
    } else {
        $zip = Join-Path ([System.IO.Path]::GetTempPath()) 'CLIProxyAPI_8.0.33_windows_amd64.zip'
        Invoke-WebRequest -Uri 'https://github.com/router-for-me/CLIProxyAPI/releases/download/v8.0.33/CLIProxyAPI_8.0.33_windows_amd64.zip' -OutFile $zip -UseBasicParsing
        $extract = Join-Path ([System.IO.Path]::GetTempPath()) 'cliproxy-extract'
        Expand-Archive $zip -DestinationPath $extract -Force
        Copy-Item (Join-Path $extract 'cli-proxy-api.exe') $routerExe
    }
}
$actualRouterHash = (Get-FileHash $routerExe -Algorithm SHA256).Hash
if ($actualRouterHash -ne $routerPin.SHA256) { throw "Router hash mismatch: expected $($routerPin.SHA256), got $actualRouterHash (pin: $($routerPin.RouterPin)). Refusing to install." }

# 5. Router local key (create once)
$keyFile = Join-Path $Root 'router\api-key.txt'
if (-not (Test-Path $keyFile)) {
    [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N') | Set-Content $keyFile -Encoding ASCII -NoNewline
}
$localKey = (Get-Content $keyFile -Raw).Trim()

# 6. Router config (create once); repair if the local key drifted (partial restore)
$routerCfg = Join-Path $Root 'router\config.yaml'
if (-not (Test-Path $routerCfg)) {
    $zai = Get-ZaiKey
    if (-not $zai) { Write-Warning 'z.ai credential not found in OpenCode store; router config written with placeholder - GLM backend will not work until provisioned.'; $zai = 'ZAI-KEY-NOT-PROVISIONED' }
    $yaml = Get-Content (Join-Path $fifeSrc 'config\router.template.yaml') -Raw
    $yaml = $yaml.Replace('__ROUTER_LOCAL_KEY__', $localKey)
    $yaml = $yaml.Replace('__AUTH_DIR__', ((Join-Path $Root 'router\auth') -replace '\\','/'))
    $yaml = $yaml.Replace('__ZAI_API_KEY__', $zai)
    $orKey = Get-OpenRouterKey
    if (-not $orKey) { Write-Warning 'OPENROUTER_API_KEY not set; router config written with placeholder - OpenRouter models will not work until provisioned.'; $orKey = 'OPENROUTER-KEY-NOT-PROVISIONED' }
    $yaml = $yaml.Replace('__OPENROUTER_API_KEY__', $orKey)
    Set-Content $routerCfg $yaml -Encoding UTF8
} elseif (-not (Get-Content $routerCfg -Raw).Contains($localKey)) {
    Write-Warning 'router config.yaml does not contain the current api-key.txt value (partial restore?) - repairing the access key line.'
    $cfg = Get-Content $routerCfg -Raw
    $cfg = $cfg -replace '(?m)^(access:\s*\n\s*api-keys:\s*\n\s*-\s*")[^"]*(")', "`$1$localKey`$2"
    Set-Content $routerCfg $cfg -Encoding UTF8
}

# 6b. Existing config without the OpenRouter provider: append the block from the
# template (the claude: list is last in the file). Only when a real key is
# available, so a placeholder never ends up advertising models that cannot work.
$cfgNow = Get-Content $routerCfg -Raw
if ($cfgNow -notmatch '(?m)^\s*-\s*name:\s*openrouter\s*$') {
    $orKey = Get-OpenRouterKey
    if (-not $orKey) {
        Write-Warning 'router config has no openrouter provider and OPENROUTER_API_KEY is not set; skipping. Set it and re-run setup.'
    } else {
        $tpl = Get-Content (Join-Path $fifeSrc 'config\router.template.yaml') -Raw
        $m = [regex]::Match($tpl, '(?ms)^    - name: openrouter\s*$.*')
        if (-not $m.Success) { throw 'openrouter block not found in router.template.yaml' }
        $block = $m.Value.Replace('__OPENROUTER_API_KEY__', $orKey).TrimEnd() -replace '\r?\n', "`n"
        $eol = if ($cfgNow.Contains("`r`n")) { "`r`n" } else { "`n" }
        $block = $block -replace "`n", $eol
        $new = $cfgNow.TrimEnd() + $eol + $block + $eol
        Set-Content $routerCfg $new -Encoding UTF8 -NoNewline
        if ((Get-Content $routerCfg -Raw) -notmatch '(?m)^\s*-\s*name:\s*openrouter\s*$') { throw 'openrouter block not present after write' }
        Write-Host 'Added openrouter provider to router config.'
    }
}

# 7. Restrict secret-bearing files and the OAuth token dir to the current user
$authDir = Join-Path $Root 'router\auth'
if (Test-Path $authDir) {
    & icacls $authDir /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" | Out-Null
}
foreach ($f in @($keyFile, $routerCfg)) {
    if (Test-Path $f) {
        & icacls $f /inheritance:r /grant:r "$($env:USERNAME):F" | Out-Null
    }
}

# 8. PATH (user scope, once)
if (-not $SkipPath) {
    $binDir = Join-Path $Root 'bin'
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = $userPath -split ';' | Where-Object { $_ }
    if ($parts -notcontains $binDir) {
        [Environment]::SetEnvironmentVariable('Path', (($parts + $binDir) -join ';'), 'User')
        Write-Host "Added $binDir to user PATH (new shells will see claude-fife)."
    }
}

Write-Host "claude-fife setup complete at $Root"
