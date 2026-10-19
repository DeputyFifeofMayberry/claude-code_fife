#Requires -Version 7.0
# Prints the claude-fife startup symbol: the ANSI art installed as
# assets\claude-symbol.ans. The launcher calls this for interactive sessions;
# run it by hand to preview the symbol.
[CmdletBinding()]
param(
    [string]$Path = ''
)
$ErrorActionPreference = 'Stop'

if (-not $Path) {
    $root = if ($env:CLAUDE_FIFE_ROOT) { $env:CLAUDE_FIFE_ROOT } else { 'C:\Users\barne\claude-fife' }
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($candidate in @(
        (Join-Path $root 'assets\claude-symbol.ans'),
        (Join-Path $repo 'fife\assets\claude-symbol.ans'),
        (Join-Path $repo 'assets\claude-symbol.ans')
    )) {
        if (Test-Path $candidate) { $Path = $candidate; break }
    }
}
if (-not $Path -or -not (Test-Path $Path)) {
    throw "claude symbol asset not found (expected assets\claude-symbol.ans under the fife root)"
}

$text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
# Write straight to the console stream so the escape sequences reach the
# terminal untouched and no PowerShell formatting is added. The console's
# default output encoding here is the OEM code page (437), which cannot carry
# the block glyphs, so switch to UTF-8 for this write and put it back before
# the engine starts.
$previous = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::Out.Write($text)
    if (-not $text.EndsWith("`n")) { [Console]::Out.Write("`n") }
    [Console]::Out.Flush()
} finally {
    [Console]::OutputEncoding = $previous
}
