#Requires -Version 7.0
# The claude-fife startup symbol: the installed ANSI art and the launcher hook
# that shows it for interactive sessions.
$ErrorActionPreference = 'Stop'
# Interactive launches would otherwise run the upstream release check.
$env:CLAUDE_FIFE_UPSTREAM_CHECK = '0'
$failures = @()
function Assert($cond, $msg) { if (-not $cond) { $script:failures += $msg } }

$repo = Split-Path -Parent $PSScriptRoot
$asset = Join-Path $repo 'fife\assets\claude-symbol.ans'
$tool = Join-Path $repo 'fife\tools\Show-ClaudeSymbol.ps1'
$launcherPs1 = Join-Path $repo 'fife\launcher\claude-fife.ps1'

Assert (Test-Path $asset) 'symbol asset missing'
Assert (Test-Path $tool) 'symbol renderer missing'

$mod = Join-Path $repo 'fife\mods\fife-symbol'
$modManifest = Join-Path $mod '.claude-plugin\plugin.json'
Assert (Test-Path $modManifest) 'fife-symbol mod manifest missing'
Assert (Test-Path (Join-Path $mod 'hooks\register.tsx')) 'fife-symbol mod hooks module missing'
if (Test-Path $modManifest) {
    $manifest = Get-Content $modManifest -Raw | ConvertFrom-Json
    Assert ($manifest.name -eq 'fife-symbol') "mod name wrong: $($manifest.name)"
}
$modHooks = Join-Path $mod 'hooks\hooks.json'
if (Test-Path $modHooks) {
    $hooksJson = Get-Content $modHooks -Raw | ConvertFrom-Json
    Assert (@($hooksJson.modules) -contains './register.tsx') 'mod hooks.json does not load register.tsx'
}
if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL: $_" }; exit 1 }

$esc = [string][char]27

# The asset must carry the 256-color sequences and the block glyphs; a stripped
# or re-encoded copy would print as plain text.
$art = [System.IO.File]::ReadAllText($asset, [System.Text.Encoding]::UTF8)
Assert ($art.Contains($esc + '[38;5;236m')) 'asset lost its 256-color foreground sequences'
Assert ($art.Contains($esc + '[48;5;243m')) 'asset lost its 256-color background sequences'
Assert ($art.Contains([string][char]0x2588)) 'asset lost its full-block glyphs'
Assert ($art.Contains([string][char]0x2584)) 'asset lost its lower-half block glyphs'
Assert (($art -split "`n").Count -ge 30) 'asset is shorter than the expected symbol'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("fife-symbol-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# The renderer prints the asset byte-for-byte (plus a newline only when the file
# has none), so the terminal sees exactly the installed art.
$renderedFile = Join-Path $tmp 'rendered.ans'
& pwsh -NoProfile -File $tool -Path $asset > $renderedFile
Assert ($LASTEXITCODE -eq 0) 'renderer exited non-zero'
$rendered = [System.IO.File]::ReadAllText($renderedFile, [System.Text.Encoding]::UTF8)
Assert ($rendered.TrimEnd("`r", "`n") -eq $art.TrimEnd("`r", "`n")) 'renderer output differs from the asset'

# The renderer resolves the asset from the installed tree, then the repo, when
# given no -Path.
$env:CLAUDE_FIFE_ROOT = Join-Path $tmp 'fiferoot'
$renderedDefaultFile = Join-Path $tmp 'rendered-default.ans'
& pwsh -NoProfile -File $tool > $renderedDefaultFile
Assert ($LASTEXITCODE -eq 0) 'renderer default-path lookup failed'
Assert ((Get-Content $renderedDefaultFile -Raw).Contains($esc)) 'renderer default path printed no ANSI art'

# Launcher: stub engine records its argv and exits 0.
$argFile = Join-Path $tmp 'engine-args.txt'
$stub = Join-Path $tmp 'stub-engine.ps1'
@'
$args | Set-Content $env:STUB_ARGS -Encoding UTF8
exit 0
'@ | Set-Content $stub -Encoding UTF8
$env:STUB_ARGS = $argFile
$env:CLAUDE_FIFE_ENGINE_PATH = $stub
$env:CLAUDE_FIFE_ROUTER_EXE = Join-Path $tmp 'no-router.exe'
$env:CLAUDE_FIFE_ROUTER_URL = 'http://127.0.0.1:8317'
$env:CLAUDE_FIFE_HEALTH_URL = 'http://127.0.0.1:8399'
$env:CLAUDE_FIFE_ROUTER_WAIT_SEC = '3'
$env:CLAUDE_FIFE_EXIT_WITH_CODE = '1'

$env:CLAUDE_FIFE_SYMBOL = 'always'
$onOut = (& pwsh -NoProfile -File $launcherPs1 2>&1 | Out-String)
Assert ($onOut.Contains($esc + '[38;5;236m')) 'CLAUDE_FIFE_SYMBOL=always did not print the symbol'
Assert ($LASTEXITCODE -eq 0) 'launcher exit code wrong with symbol shown'

$env:CLAUDE_FIFE_SYMBOL = 'never'
$offOut = (& pwsh -NoProfile -File $launcherPs1 2>&1 | Out-String)
Assert (-not $offOut.Contains($esc + '[38;5;236m')) 'CLAUDE_FIFE_SYMBOL=never still printed the symbol'

# auto (the default) stays quiet whenever output is not a terminal, which is
# exactly the shape of piped and scripted runs.
Remove-Item Env:CLAUDE_FIFE_SYMBOL -ErrorAction SilentlyContinue
$autoOut = (& pwsh -NoProfile -File $launcherPs1 2>&1 | Out-String)
Assert (-not $autoOut.Contains($esc + '[38;5;236m')) 'auto mode printed the symbol into a redirected stream'

# Without an installed mod the engine gets no --plugin-dir; with one it does.
$recorded = @(Get-Content $argFile -ErrorAction SilentlyContinue)
Assert (-not ($recorded -contains '--plugin-dir')) 'launcher passed --plugin-dir with no installed mod'

$tempMod = Join-Path $env:CLAUDE_FIFE_ROOT 'config\mods\fife-symbol'
New-Item -ItemType Directory -Force -Path $tempMod | Out-Null
$null = (& pwsh -NoProfile -File $launcherPs1 2>&1 | Out-String)
$recorded = @(Get-Content $argFile -ErrorAction SilentlyContinue)
Assert ($recorded -contains '--plugin-dir') 'launcher did not load the installed fife-symbol mod'
$at = [array]::IndexOf($recorded, '--plugin-dir')
Assert ($at -ge 0 -and $recorded[$at + 1] -eq $tempMod) 'launcher --plugin-dir does not name the installed mod'

foreach ($name in 'CLAUDE_FIFE_ROOT', 'CLAUDE_FIFE_ENGINE_PATH', 'CLAUDE_FIFE_ROUTER_EXE', 'CLAUDE_FIFE_ROUTER_URL',
    'CLAUDE_FIFE_HEALTH_URL', 'CLAUDE_FIFE_ROUTER_WAIT_SEC', 'CLAUDE_FIFE_EXIT_WITH_CODE', 'STUB_ARGS') {
    Remove-Item "Env:$name" -ErrorAction SilentlyContinue
}
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL: $_" }; exit 1 }
Write-Host 'PASS: claude symbol asset and launcher hook'
