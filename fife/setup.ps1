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

# 4. Router exe (pinned CLIProxyAPI v8.0.33)
$routerExe = Join-Path $Root 'router\cli-proxy-api.exe'
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

# 5. Router local key (create once)
$keyFile = Join-Path $Root 'router\api-key.txt'
if (-not (Test-Path $keyFile)) {
    [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N') | Set-Content $keyFile -Encoding ASCII -NoNewline
}
$localKey = (Get-Content $keyFile -Raw).Trim()

# 6. Router config (create once)
$routerCfg = Join-Path $Root 'router\config.yaml'
if (-not (Test-Path $routerCfg)) {
    $zai = Get-ZaiKey
    if (-not $zai) { Write-Warning 'z.ai credential not found in OpenCode store; router config written with placeholder - GLM backend will not work until provisioned.'; $zai = 'ZAI-KEY-NOT-PROVISIONED' }
    $yaml = Get-Content (Join-Path $fifeSrc 'config\router.template.yaml') -Raw
    $yaml = $yaml.Replace('__ROUTER_LOCAL_KEY__', $localKey)
    $yaml = $yaml.Replace('__AUTH_DIR__', ((Join-Path $Root 'router\auth') -replace '\\','/'))
    $yaml = $yaml.Replace('__ZAI_API_KEY__', $zai)
    Set-Content $routerCfg $yaml -Encoding UTF8
}

# 7. Restrict secret-bearing files to the current user
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
