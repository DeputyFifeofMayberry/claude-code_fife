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
$keyFile    = Join-Path $root 'router\api-key.txt'
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

if (-not (Test-Path $engine)) {
    Write-Error "claude-fife engine not found: $engine (run fife\setup.ps1)"
    exit 1
}

Ensure-Router

$managed = 'CLAUDE_CONFIG_DIR','DISABLE_AUTOUPDATER','ANTHROPIC_BASE_URL','ANTHROPIC_AUTH_TOKEN','CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY'
$saved = @{}
foreach ($name in $managed) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }

$code = 1
try {
    $env:CLAUDE_CONFIG_DIR = $configDir
    $env:DISABLE_AUTOUPDATER = '1'
    $env:ANTHROPIC_BASE_URL = $routerUrl
    if (Test-Path $keyFile) { $env:ANTHROPIC_AUTH_TOKEN = (Get-Content $keyFile -Raw).Trim() }
    $env:CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = '1'
    & $engine @args
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 0 }
} finally {
    foreach ($name in $managed) {
        if ($null -eq $saved[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    }
}

if ($env:CLAUDE_FIFE_EXIT_WITH_CODE -eq '1') { exit $code }
