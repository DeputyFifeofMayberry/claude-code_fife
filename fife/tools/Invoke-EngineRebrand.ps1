#Requires -Version 7.0
# Rewrites the startup identity strings inside the pinned Claude Code engine so
# the in-session welcome banner and terminal title say claude-fife instead of
# Claude Code. The engine's own version (2.1.302) is left untouched.
#
# The engine is a Bun single-file executable. Its embedded JS is addressed by
# offsets recorded in the file, so a replacement that changes length would
# corrupt the executable. Every replacement here swaps one 11-byte label for
# another ("Claude Code" -> "claude-fife"), which keeps the file layout intact.
# The patch changes the Authenticode hash; the pin record keeps the upstream
# hash and signature status alongside the patched hash so provenance survives.
#
# Usage:
#   pwsh fife\tools\Invoke-EngineRebrand.ps1
#   pwsh fife\tools\Invoke-EngineRebrand.ps1 -Brand 'Claude Fife'
[CmdletBinding()]
param(
    [string]$Source = 'C:\Users\barne\claude-fife-backup\claude-2.1.302.exe',
    [string]$Destination = '',
    [string]$Record = 'C:\Users\barne\claude-fife-backup\SHA256.txt',
    [string]$Version = '2.1.302',
    [string]$Platform = 'win32-x64',
    [string]$Brand = 'claude-fife',
    [switch]$KeepOriginal
)
$ErrorActionPreference = 'Stop'

if ($Destination -eq '') { $Destination = $Source }
if ($Brand.Length -ne 'Claude Code'.Length) {
    throw "Brand must be exactly $('Claude Code'.Length) characters so offsets stay valid: '$Brand'"
}
if ($Brand -notmatch '^[\x20-\x7e]+$') { throw "Brand must be printable ASCII: '$Brand'" }

# Each pattern is a UI label; the expected count is pinned to engine 2.1.302 so
# an engine bump fails loudly instead of quietly rebranding half the UI.
#
# The last rule targets the compiled bytecode's string table, not the JS source:
# Bun executes the embedded bytecode, so editing source literals alone does not
# change strings the running code pulls from its constant pool. Entries are
# [length | 0x80000000][4-byte hash][UTF-8 chars][NUL]; keep the length and hash
# bytes intact (the welcome entry, already patched this way, proves the runtime
# does not revalidate the hash for value strings). The hash below pins 2.1.302.
$b = [string][char]0x0b + [string][char]0 + [string][char]0 + [string][char]0x80
$h = [string][char]0xc9 + [string][char]0x2f + [string][char]0x86 + [string][char]0
$nul = [string][char]0
$patches = @(
    @{ Find = 'Welcome to Claude Code'; Replace = "Welcome to $Brand"; Expected = 7; What = 'welcome banners' }
    @{ Find = 'children:"Claude Code"'; Replace = "children:`"$Brand`""; Expected = 3; What = 'header labels' }
    @{ Find = 'var p="Claude Code"'; Replace = "var p=`"$Brand`""; Expected = 1; What = 'notification title' }
    @{ Find = 'var YTt="Claude Code"'; Replace = "var YTt=`"$Brand`""; Expected = 1; What = 'terminal title' }
    @{ Find = "$b${h}Claude Code${nul}"; Replace = "$b${h}$Brand${nul}"; Expected = 1; What = 'bytecode header label' }
)

Add-Type -TypeDefinition @'
using System;

public static class FifeEnginePatcher
{
    public static int Replace(byte[] data, byte[] pattern, byte[] replacement, int expected)
    {
        if (pattern.Length != replacement.Length)
            throw new ArgumentException("pattern and replacement must have equal length");
        int count = 0, start = 0;
        var span = data.AsSpan();
        while (start < span.Length)
        {
            int idx = span.Slice(start).IndexOf(pattern);
            if (idx < 0) break;
            int at = start + idx;
            replacement.CopyTo(data.AsSpan(at));
            start = at + pattern.Length;
            count++;
        }
        if (count != expected)
            throw new InvalidOperationException(
                $"expected {expected} occurrence(s), found {count}");
        return count;
    }
}
'@

if (-not (Test-Path $Source)) { throw "Engine not found: $Source" }
$upstreamHash = (Get-FileHash $Source -Algorithm SHA256).Hash
$upstreamSignature = (Get-AuthenticodeSignature $Source).Status.ToString()

if ($KeepOriginal) {
    $original = "$Source.upstream"
    if (-not (Test-Path $original)) { Copy-Item $Source $original }
    Write-Host "Upstream engine preserved: $original"
}

$bytes = [System.IO.File]::ReadAllBytes($Source)
foreach ($p in $patches) {
    $find = [System.Text.Encoding]::Latin1.GetBytes($p.Find)
    $repl = [System.Text.Encoding]::Latin1.GetBytes($p.Replace)
    try {
        $n = [FifeEnginePatcher]::Replace($bytes, $find, $repl, [int]$p.Expected)
        Write-Host ("  patched {0} {1} occurrence(s)" -f $n, $p.What)
    } catch {
        throw "$($p.What): $($_.Exception.Message). Engine $Version may differ from the pinned build; refusing to write."
    }
}

[System.IO.File]::WriteAllBytes($Destination, $bytes)

# The binary is now modified, so the signature is recorded as it now reports;
# the upstream status and hash stay in the record as provenance.
$patchedSignature = (Get-AuthenticodeSignature $Destination).Status.ToString()
$patchedHash = (Get-FileHash $Destination -Algorithm SHA256).Hash

@(
    "SHA256=$patchedHash"
    "Version=$Version"
    "Provenance=patched-rebrand"
    "SignatureStatus=$patchedSignature"
    "Platform=$Platform"
    "Rebrand=$Brand"
    "UpstreamSHA256=$upstreamHash"
    "UpstreamSignatureStatus=$upstreamSignature"
) | Set-Content -Path $Record -Encoding UTF8

$versionOut = (& $Destination --version 2>&1 | Out-String).Trim()
if ($versionOut -notmatch [regex]::Escape($Version)) {
    throw "Patched engine failed its version check: $versionOut"
}

Write-Host "Patched engine: $Destination"
Write-Host "  sha256:    $patchedHash"
Write-Host "  signature: $patchedSignature (was $upstreamSignature)"
Write-Host "  version:   $versionOut"
Write-Host 'Run fife\setup.ps1 (with claude-fife closed) or simply relaunch claude-fife to install the pin.'
