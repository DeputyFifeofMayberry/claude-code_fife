#Requires -Version 7.0
# claude-fife launcher: sets fife-only env (process scope, restored after),
# ensures the localhost router is healthy, forwards all args to the engine.
# No CmdletBinding/param block on purpose: engine flags like -p would collide
# with PowerShell common parameters. Everything lands in $args untouched.
$ErrorActionPreference = 'Stop'

$root       = if ($env:CLAUDE_FIFE_ROOT) { $env:CLAUDE_FIFE_ROOT } else { 'C:\Users\barne\claude-fife' }
$engine     = if ($env:CLAUDE_FIFE_ENGINE_PATH) { $env:CLAUDE_FIFE_ENGINE_PATH } else { Join-Path $root 'bin\claude-fife-engine.exe' }
$configDir  = Join-Path $root 'config'
$routerExe  = if ($env:CLAUDE_FIFE_ROUTER_EXE) { $env:CLAUDE_FIFE_ROUTER_EXE } else { Join-Path $root 'router\cli-proxy-api.exe' }
$routerCfg  = if ($env:CLAUDE_FIFE_ROUTER_CONFIG) { $env:CLAUDE_FIFE_ROUTER_CONFIG } else { Join-Path $root 'router\config.yaml' }
$routerUrl  = if ($env:CLAUDE_FIFE_ROUTER_URL) { $env:CLAUDE_FIFE_ROUTER_URL } else { 'http://127.0.0.1:8317' }
$healthUrl  = if ($env:CLAUDE_FIFE_HEALTH_URL) { $env:CLAUDE_FIFE_HEALTH_URL } else { $routerUrl }
$labelsProxy = Join-Path $root 'bin\model-labels-proxy.js'
$labelsFile  = Join-Path $root 'config\model-labels.json'
$labelsPort  = if ($env:CLAUDE_FIFE_LABELS_PORT) { [int]$env:CLAUDE_FIFE_LABELS_PORT } else { 8319 }
$labelsUrl   = "http://127.0.0.1:$labelsPort"
$keyFile    = Join-Path $root 'router\api-key.txt'
$backupDir  = if ($env:CLAUDE_FIFE_BACKUP_DIR) { $env:CLAUDE_FIFE_BACKUP_DIR } else { 'C:\Users\barne\claude-fife-backup' }
$waitSec    = if ($env:CLAUDE_FIFE_ROUTER_WAIT_SEC) { [int]$env:CLAUDE_FIFE_ROUTER_WAIT_SEC } else { 15 }

function Test-RouterHealth {
    try {
        $headers = @{}
        if (Test-Path $keyFile) { $headers['Authorization'] = "Bearer $((Get-Content $keyFile -Raw).Trim())" }
        Invoke-WebRequest -Uri "$healthUrl/v1/models" -Headers $headers -TimeoutSec 2 -UseBasicParsing | Out-Null
        return $true
    } catch {
        if ($_.Exception.Response) { return $true }  # any HTTP answer = server up
        return $false
    }
}

# The engine is a pinned, hash-verified file. When the pin is rebuilt (for
# example by a rebrand patch) but this tree still holds the old binary, install
# the pin before launching. A running engine locks its file, so a failure here
# is expected while another session is open; the next launch retries.
function Ensure-EnginePin {
    if ($env:CLAUDE_FIFE_ENGINE_PATH) { return }  # explicit override: never replace it
    $recordFile = Join-Path $backupDir 'SHA256.txt'
    if (-not (Test-Path $recordFile) -or -not (Test-Path $engine)) { return }
    $record = @{}
    foreach ($line in Get-Content $recordFile) {
        if ($line -match '^([^=]+)=(.*)$') { $record[$Matches[1]] = $Matches[2] }
    }
    if (-not $record.SHA256 -or -not $record.Version) { return }
    $pinExe = Join-Path $backupDir "claude-$($record.Version).exe"
    if (-not (Test-Path $pinExe)) { return }
    if ((Get-FileHash $engine -Algorithm SHA256).Hash -eq $record.SHA256) { return }
    try {
        Copy-Item $pinExe $engine -Force -ErrorAction Stop
        Write-Host 'claude-fife: installed pinned engine build.'
    } catch {
        Write-Warning 'claude-fife: engine pin update pending (binary in use); it will apply on the next launch.'
    }
}

function Ensure-Router {
    if (-not (Test-Path $routerExe)) { return }
    if (-not (Test-Path $routerCfg)) {
        # NEVER start the router without its config: the upstream default binds
        # all interfaces, which would expose OAuth-backed endpoints on the LAN.
        Write-Warning 'claude-fife: router config missing - starting engine WITHOUT router. Run fife\setup.ps1 to repair.'
        return
    }
    if (Test-RouterHealth) { return }
    Start-Process -FilePath $routerExe -ArgumentList @('--config', $routerCfg) -WorkingDirectory (Split-Path -Parent $routerExe) -WindowStyle Hidden | Out-Null
    $deadline = (Get-Date).AddSeconds($waitSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-RouterHealth) { return }
        Start-Sleep -Milliseconds 500
    }
    Write-Warning 'claude-fife: router did not become healthy in time; launching engine anyway.'
}

function Test-LabelsHealth {
    try {
        $headers = @{}
        if (Test-Path $keyFile) { $headers['Authorization'] = "Bearer $((Get-Content $keyFile -Raw).Trim())" }
        Invoke-WebRequest -Uri "$labelsUrl/v1/models" -Headers $headers -TimeoutSec 2 -UseBasicParsing | Out-Null
        return $true
    } catch {
        if ($_.Exception.Response) { return $true }
        return $false
    }
}

# The labels proxy only annotates /v1/models; message traffic is pure passthrough.
# If node or the proxy files are missing, fall back to the router directly so the
# picker loses its labels but the session still works.
function Ensure-LabelsProxy {
    if (-not (Test-Path $labelsProxy) -or -not (Test-Path $labelsFile)) { return }
    $node = (Get-Command node -ErrorAction SilentlyContinue).Source
    if (-not $node) { Write-Warning 'claude-fife: node not found - model labels disabled, using router directly.'; return }
    if (Test-LabelsHealth) { $script:baseUrl = $labelsUrl; return }
    Start-Process -FilePath $node -ArgumentList @($labelsProxy, $labelsFile, "$labelsPort", $routerUrl) -WindowStyle Hidden | Out-Null
    $deadline = (Get-Date).AddSeconds($waitSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-LabelsHealth) { $script:baseUrl = $labelsUrl; return }
        Start-Sleep -Milliseconds 250
    }
    Write-Warning 'claude-fife: model-labels proxy did not start - using router directly.'
}

# The startup symbol is the ANSI art in assets\claude-symbol.ans: a
# 256-color drawing of the Claude mark shown above the engine's welcome
# screen. Piped runs and -p/--print stay byte-clean, so the symbol only
# appears for an interactive session unless CLAUDE_FIFE_SYMBOL says otherwise
# (always|never).
function Show-ClaudeSymbol([string[]]$EngineArgs) {
    $mode = if ($env:CLAUDE_FIFE_SYMBOL) { $env:CLAUDE_FIFE_SYMBOL.ToLowerInvariant() } else { 'auto' }
    if ($mode -in @('never', '0', 'off', 'false')) { return }
    if ($mode -notin @('always', '1', 'on', 'true')) {
        if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) { return }
        if (@($EngineArgs | Where-Object { $_ -match '^(--print|-p|--help|-h|--output-format(=.*)?|mcp|config|doctor)$' }).Count -gt 0) { return }
    }
    $tool = Join-Path $root 'bin\Show-ClaudeSymbol.ps1'
    if (-not (Test-Path $tool)) { $tool = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\Show-ClaudeSymbol.ps1' }
    $symbol = Join-Path $root 'assets\claude-symbol.ans'
    if (-not (Test-Path $symbol)) { $symbol = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\claude-symbol.ans' }
    if (-not (Test-Path $tool) -or -not (Test-Path $symbol)) { return }
    # A broken or missing asset must never keep the session from starting.
    try { & $tool -Path $symbol } catch { }
}

$script:baseUrl = $routerUrl

# `update` and `upgrade` are engine verbs that install upstream Claude Code into
# the native-install directory (C:\Users\<user>\.local\bin\claude.exe), outside
# the fife tree, and ignore DISABLE_AUTOUPDATER. Fife versions come only from
# the fork's GitHub releases, so these verbs are answered here and never
# forwarded to the engine.
function ConvertTo-FifeVersion([string]$Text) {
    $m = [regex]::Match($Text, '^(?:v)?(\d+(?:\.\d+){1,3})(?:r(\d+))?$')
    if (-not $m.Success) { return $null }
    [pscustomobject]@{
        Base = [version]$m.Groups[1].Value
        Rev  = if ($m.Groups[2].Success) { [int]$m.Groups[2].Value } else { 0 }
    }
}

function Compare-FifeVersion([string]$Left, [string]$Right) {
    $l = ConvertTo-FifeVersion $Left
    $r = ConvertTo-FifeVersion $Right
    if (-not $l -or -not $r) { return $null }
    if ($l.Base -ne $r.Base) { if ($l.Base -lt $r.Base) { return -1 } else { return 1 } }
    if ($l.Rev -ne $r.Rev) { if ($l.Rev -lt $r.Rev) { return -1 } else { return 1 } }
    return 0
}

function Get-FifeBuildId {
    $versionFile = Join-Path $root 'config\fife-version.txt'
    if (Test-Path $versionFile) { return (Get-Content $versionFile -Raw).Trim() }
    return $null
}

function Get-EngineVersion {
    if ($env:CLAUDE_FIFE_ENGINE_VERSION) { return $env:CLAUDE_FIFE_ENGINE_VERSION }
    if (Test-Path $engine) {
        $vout = (& $engine --version 2>$null | Out-String).Trim()
        if ($vout -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
    }
    return $null
}

# The engine prints its own upstream identity (`2.1.302 (Claude Code)`). A fife
# install names the fife build first and keeps the engine version alongside, so
# `claude-fife --version` answers for the tree that is actually running.
function Show-FifeVersion {
    $build = Get-FifeBuildId
    $engineVersion = Get-EngineVersion
    $buildPart = if ($build) { $build } else { 'build unrecorded' }
    $enginePart = if ($engineVersion) { "Claude Code engine $engineVersion" } else { 'engine version unknown' }
    Write-Output "claude-fife $buildPart ($enginePart)"
}

function Show-FifeRelease($Release, $Asset) {
    if ($Release.body -and $Release.body -match '(?i)Claude Code (\d+\.\d+\.\d+)') {
        Write-Host "  engine pin:  $($Matches[1])"
    }
    if ($Asset) {
        Write-Host "  asset:       $($Asset.name)"
        if ($Asset.digest -match '^sha256:([0-9a-fA-F]+)$') { Write-Host "  sha256:      $($Matches[1].ToUpper())" }
        if ($Asset.browser_download_url) { Write-Host "  download:    $($Asset.browser_download_url)" }
    }
    Write-Host 'To apply: download the asset, verify its SHA-256, then run pwsh <package>\fife\setup.ps1'
}

function Invoke-FifeUpdate {
    $repoSlug = if ($env:CLAUDE_FIFE_RELEASES_REPO) { $env:CLAUDE_FIFE_RELEASES_REPO } else { 'DeputyFifeofMayberry/claude-code_fife' }
    $feed = if ($env:CLAUDE_FIFE_RELEASES_API) { $env:CLAUDE_FIFE_RELEASES_API } else { "https://api.github.com/repos/$repoSlug/releases/latest" }

    $installed = Get-FifeBuildId
    $engineVersion = Get-EngineVersion

    try {
        $release = if ($feed -match '^https?://') {
            Invoke-RestMethod -Uri $feed -Headers @{ 'User-Agent' = 'claude-fife-update'; 'Accept' = 'application/vnd.github+json' } -TimeoutSec 20
        } else {
            Get-Content $feed -Raw | ConvertFrom-Json
        }
    } catch {
        Write-Host "claude-fife update: could not read the fork release feed ($feed)."
        Write-Host 'Nothing was changed. Upstream Claude Code updates are never used.'
        return 1
    }

    $tag = $release.tag_name -replace '^v', ''
    $latest = ConvertTo-FifeVersion $tag
    $asset = @($release.assets | Where-Object { $_ -and $_.name -like 'claude-fife-*.zip' }) | Select-Object -First 1
    $shown = if ($installed) { $installed } elseif ($engineVersion) { "engine $engineVersion (no package version recorded)" } else { 'unknown' }

    Write-Host 'claude-fife update'
    Write-Host "  installed:   $shown"
    Write-Host "  latest fork: $tag"

    $cmp = if ($installed) { Compare-FifeVersion $installed $tag } else { $null }
    if ($null -ne $cmp -and $cmp -eq 0) {
        Write-Host 'Up to date with the latest fork release.'
    } elseif ($null -ne $cmp -and $cmp -gt 0) {
        Write-Host 'Installed build is newer than the latest fork release.'
    } elseif ($null -ne $cmp -and $cmp -lt 0) {
        Write-Host "A newer fork release is available: $tag"
        Show-FifeRelease $release $asset
    } else {
        $engineCmp = if ($engineVersion -and $latest) { Compare-FifeVersion $engineVersion $latest.Base.ToString() } else { $null }
        if ($engineCmp -eq 0) {
            # A repo setup records dev-<commit>; releases name their source commit.
            $installedCommit = if ($installed -match '^dev-([0-9a-f]{7,40})$') { $Matches[1] } else { $null }
            $releaseCommit = if ($release.body -match '(?i)Source commit:\s*`?([0-9a-f]{7,40})') { $Matches[1] } else { $null }
            if ($installedCommit -and $releaseCommit -and $releaseCommit.StartsWith($installedCommit)) {
                Write-Host "Installed build is based on the latest fork release ($tag, commit $installedCommit)."
            } elseif ($installedCommit) {
                Write-Host "Installed engine $engineVersion is current; tree is a dev build at commit $installedCommit (latest release: $tag)."
            } else {
                Write-Host "Installed engine $engineVersion matches the latest fork release ($tag); no package revision recorded."
            }
        } else {
            Write-Host 'Installed version could not be compared with the latest fork release.'
            Show-FifeRelease $release $asset
        }
    }
    Write-Host 'Upstream Claude Code updates are never used; the engine changes only by re-pin (docs\setup.md).'
    return 0
}

if ($args.Count -ge 1 -and $args[0] -match '(?i)^(update|upgrade|install)$') {
    $updateCode = if ($args[0] -match '(?i)^install$') {
        # `install` fetches a native build from upstream into the same
        # out-of-tree directory; fife trees come only from fork packages.
        Write-Host 'claude-fife: the engine installer is disabled. This tree is installed from the fork release package.'
        Write-Host 'Use fife\setup.ps1 to restore it (see docs\setup.md).'
        1
    } else {
        Invoke-FifeUpdate
    }
    if ($env:CLAUDE_FIFE_EXIT_WITH_CODE -eq '1') { exit $updateCode }
    return
}

# The engine's `--version` reports upstream Claude Code. Answer it here so the
# command names the fife build, while still carrying the engine version.
if ($args.Count -ge 1 -and $args[0] -match '^(--version|-v|-V)$') {
    Show-FifeVersion
    if ($env:CLAUDE_FIFE_EXIT_WITH_CODE -eq '1') { exit 0 }
    return
}

if (-not (Test-Path $engine)) {
    Write-Error "claude-fife engine not found: $engine (run fife\setup.ps1)"
    exit 1
}

Show-ClaudeSymbol $args
Ensure-EnginePin
Ensure-Router
Ensure-LabelsProxy

$managed = 'CLAUDE_CONFIG_DIR','DISABLE_AUTOUPDATER','DISABLE_UPDATES','ANTHROPIC_BASE_URL','ANTHROPIC_AUTH_TOKEN','CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY'
$saved = @{}
foreach ($name in $managed) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }

$code = 1
try {
    $env:CLAUDE_CONFIG_DIR = $configDir
    $env:DISABLE_AUTOUPDATER = '1'
    # Blocks `claude update`/`claude install` inside the engine too; the
    # launcher also intercepts those verbs (see Invoke-FifeUpdate above).
    $env:DISABLE_UPDATES = '1'
    $env:ANTHROPIC_BASE_URL = $script:baseUrl
    if (Test-Path $keyFile) { $env:ANTHROPIC_AUTH_TOKEN = (Get-Content $keyFile -Raw).Trim() }
    $env:CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = '1'
    & $engine --allow-dangerously-skip-permissions @args
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 0 }
} finally {
    foreach ($name in $managed) {
        if ($null -eq $saved[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    }
}

if ($env:CLAUDE_FIFE_EXIT_WITH_CODE -eq '1') { exit $code }
