#Requires -Version 7.0
# Rewrites the startup identity strings inside the pinned Claude Code engine so
# the in-session welcome banner and terminal title say claude-fife instead of
# Claude Code, and the banner's version shows the fife build (for example
# 2.1.303r1) instead of only the engine version (2.1.303).
#
# The engine is a Bun single-file executable. Its embedded JS is addressed by
# offsets recorded in the file, so a replacement that changes length would
# corrupt the executable. The label replacements swap one 11-byte label for
# another ("Claude Code" -> "claude-fife"), which keeps the file layout intact.
#
# The version lives in the bytecode string table: a u32 count, then one u32
# offset per string, then the packed entries (each [length | 0x80000000]
# [4-byte hash][bytes][padding to 4]). Bun resolves constants through that
# offset array, so a length change is possible if the offsets are updated:
# grow the version entry, shift the entries after it, and shorten one later
# message by the same amount so the table keeps its exact size. The offsets
# for the shifted entries move with them. This is pinned to engine 2.1.303 like
# the label counts; an engine bump fails loudly instead of patching a guess.
#
# The patch changes the Authenticode hash; the pin record keeps the upstream
# hash and signature status alongside the patched hash so provenance survives.
#
# Usage:
#   pwsh fife\tools\Invoke-EngineRebrand.ps1
#   pwsh fife\tools\Invoke-EngineRebrand.ps1 -Brand 'Claude Fife'
#   pwsh fife\tools\Invoke-EngineRebrand.ps1 -FifeVersion 2.1.303r1
[CmdletBinding()]
param(
    [string]$Source = 'C:\Users\barne\claude-fife-backup\claude-2.1.303.exe',
    [string]$Destination = '',
    [string]$Record = 'C:\Users\barne\claude-fife-backup\SHA256.txt',
    [string]$Version = '2.1.303',
    [string]$Platform = 'win32-x64',
    [string]$Brand = 'claude-fife',
    [string]$FifeVersion = '',
    [switch]$KeepOriginal
)
$ErrorActionPreference = 'Stop'

if ($Destination -eq '') { $Destination = $Source }
if ($Brand.Length -ne 'Claude Code'.Length) {
    throw "Brand must be exactly $('Claude Code'.Length) characters so offsets stay valid: '$Brand'"
}
if ($Brand -notmatch '^[\x20-\x7e]+$') { throw "Brand must be printable ASCII: '$Brand'" }

# Default the banner version to the installed tree's build tag, so the banner
# and `claude-fife --version` name the same build. Pass -FifeVersion to override.
if (-not $FifeVersion) {
    $fifeRoot = if ($env:CLAUDE_FIFE_ROOT) { $env:CLAUDE_FIFE_ROOT } else { 'C:\Users\barne\claude-fife' }
    $versionFile = Join-Path $fifeRoot 'config\fife-version.txt'
    if (Test-Path $versionFile) { $FifeVersion = (Get-Content $versionFile -Raw).Trim() }
}

# Each pattern is a UI label; the expected count is pinned to engine 2.1.303 so
# an engine bump fails loudly instead of quietly rebranding half the UI.
#
# The last rule targets the compiled bytecode's string table, not the JS source:
# Bun executes the embedded bytecode, so editing source literals alone does not
# change strings the running code pulls from its constant pool. Entries are
# [length | 0x80000000][4-byte hash][UTF-8 chars][padding to 4]; keep the length
# and hash bytes intact (the welcome entry, already patched this way, proves the
# runtime does not revalidate the hash for value strings). The hash below pins
# 2.1.303.
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

# --- Banner version ---------------------------------------------------------
# Layout of the 2.1.303 bytecode string table that holds the build object.
$tableBase = 122177408
$tableCount = 255988
$versionIndex = 11014
$versionHash = [byte[]](0x98, 0x64, 0xda, 0x00)
$versionText = '2.1.303'

function Read-LenWord([byte[]]$d, [int]$o) {
    [pscustomobject]@{
        N  = [int]$d[$o] -bor ([int]$d[$o+1] -shl 8) -bor ([int]$d[$o+2] -shl 16)
        Hi = (([int]$d[$o+3] -band 0x80) -ne 0)
    }
}
function Write-LenWord([byte[]]$d, [int]$o, [int]$n) {
    $d[$o] = [byte]($n -band 0xff)
    $d[$o+1] = [byte](($n -shr 8) -band 0xff)
    $d[$o+2] = [byte](($n -shr 16) -band 0xff)
    $d[$o+3] = [byte]0x80
}
function Read-U32([byte[]]$d, [int]$o) {
    [int]$d[$o] -bor ([int]$d[$o+1] -shl 8) -bor ([int]$d[$o+2] -shl 16) -bor ([int]$d[$o+3] -shl 24)
}
function Write-U32([byte[]]$d, [int]$o, [int]$v) {
    $d[$o] = [byte]($v -band 0xff)
    $d[$o+1] = [byte](($v -shr 8) -band 0xff)
    $d[$o+2] = [byte](($v -shr 16) -band 0xff)
    $d[$o+3] = [byte](($v -shr 24) -band 0xff)
}
function Get-Span([int]$dataLen) {
    $size = 8 + $dataLen
    $size + ((4 - ($size % 4)) % 4)
}

$bannerVersion = $null
if ($FifeVersion) {
    if ($FifeVersion -notmatch '^[\x20-\x7e]+$') { throw "FifeVersion must be printable ASCII: '$FifeVersion'" }
    $vb = [System.Text.Encoding]::Latin1.GetBytes($FifeVersion)
    if ($vb.Length -ge 0x7fffffff) { throw "FifeVersion is absurdly long: '$FifeVersion'" }

    if ($bytes.Length -lt $tableBase -or (Read-U32 $bytes $tableBase) -ne $tableCount) {
        throw "banner version: bytecode string table not at the pinned location. Engine $Version may differ from the pinned build; refusing to write."
    }
    $offsets = [int[]]::new($tableCount)
    for ($i = 0; $i -lt $tableCount; $i++) { $offsets[$i] = Read-U32 $bytes ($tableBase + 4 + 4 * $i) }

    $verOffset = $offsets[$versionIndex]
    $verPos = $tableBase + $verOffset
    $lw = Read-LenWord $bytes $verPos
    $hashAtVer = [byte[]]$bytes[($verPos + 4)..($verPos + 7)]
    $textAtVer = [System.Text.Encoding]::Latin1.GetString($bytes, $verPos + 8, $lw.N)
    if (-not $lw.Hi -or $lw.N -ne $versionText.Length -or $textAtVer -ne $versionText -or
        [Convert]::ToHexString($hashAtVer) -ne [Convert]::ToHexString($versionHash)) {
        throw "banner version: expected entry '$versionText' at index $versionIndex, found '$textAtVer'. Engine $Version may differ from the pinned build; refusing to write."
    }
    if ($versionIndex + 1 -lt $tableCount -and $offsets[$versionIndex + 1] -ne $verOffset + (Get-Span $lw.N)) {
        throw 'banner version: version entry is not adjacent to the next string; refusing to write.'
    }

    $oldSpan = Get-Span $lw.N
    $newSpan = Get-Span $vb.Length
    $delta = $newSpan - $oldSpan
    if ($delta -le 0) { throw "banner version: '$FifeVersion' does not lengthen the banner version." }

    # A later message absorbs the growth so the table keeps its exact size.
    # Trim only trailing periods or spaces so the shortened text still reads.
    $targetIndex = -1; $trim = 0; $targetN = 0; $targetSpan = 0
    foreach ($want in '.', ' ') {
        for ($j = $versionIndex + 1; $j -lt [Math]::Min($versionIndex + 5000, $tableCount); $j++) {
            $q = $tableBase + $offsets[$j]
            $cand = Read-LenWord $bytes $q
            if (-not $cand.Hi -or $cand.N -lt 12) { continue }
            $span = Get-Span $cand.N
            for ($k = 1; $k -le 8 -and $k -lt $cand.N; $k++) {
                $m = $cand.N - $k
                if ((Get-Span $m) -ne ($span - $delta)) { continue }
                $ok = $true
                for ($t = $cand.N - $k; $t -lt $cand.N; $t++) {
                    if ([char]$bytes[$q + 8 + $t] -ne [char]$want) { $ok = $false; break }
                }
                if ($ok) { $targetIndex = $j; $trim = $k; $targetN = $cand.N; $targetSpan = $span; break }
            }
            if ($targetIndex -ge 0) { break }
        }
        if ($targetIndex -ge 0) { break }
    }
    if ($targetIndex -lt 0) {
        throw "banner version: no later string can absorb $delta byte(s) of table growth; refusing to write."
    }

    $targetPos = $tableBase + $offsets[$targetIndex]
    $regionLen = ($targetPos + $targetSpan) - $verPos
    $region = [byte[]]::new($regionLen)

    Write-LenWord $region 0 $vb.Length
    [Array]::Copy($bytes, $verPos + 4, $region, 4, 4)   # hash stays as pinned
    [Array]::Copy($vb, 0, $region, 8, $vb.Length)

    $betweenLen = $targetPos - ($verPos + $oldSpan)
    [Array]::Copy($bytes, $verPos + $oldSpan, $region, $newSpan, $betweenLen)

    $tAt = $newSpan + $betweenLen
    Write-LenWord $region $tAt ($targetN - $trim)
    [Array]::Copy($bytes, $targetPos + 4, $region, $tAt + 4, 4)
    [Array]::Copy($bytes, $targetPos + 8, $region, $tAt + 8, ($targetN - $trim))
    if ($tAt + ($targetSpan - $delta) -ne $regionLen) {
        throw 'banner version: rebuilt region does not preserve the table size; refusing to write.'
    }

    [Array]::Copy($region, 0, $bytes, $verPos, $regionLen)
    for ($i = $versionIndex + 1; $i -le $targetIndex; $i++) {
        $offsets[$i] += $delta
        Write-U32 $bytes ($tableBase + 4 + 4 * $i) $offsets[$i]
    }

    # Re-read what was just written: the entry must now name the fife build.
    $check = Read-LenWord $bytes $verPos
    $checkText = [System.Text.Encoding]::Latin1.GetString($bytes, $verPos + 8, $check.N)
    if ($checkText -ne $FifeVersion) {
        throw "banner version: wrote '$checkText' instead of '$FifeVersion'; refusing to save."
    }
    $bannerVersion = $FifeVersion
    Write-Host ("  retitled banner version to '{0}' ({1} entry, {2} bytes)" -f `
        $FifeVersion, $targetIndex, $delta)
}

[System.IO.File]::WriteAllBytes($Destination, $bytes)

# The binary is now modified, so the signature is recorded as it now reports;
# the upstream status and hash stay in the record as provenance.
$patchedSignature = (Get-AuthenticodeSignature $Destination).Status.ToString()
$patchedHash = (Get-FileHash $Destination -Algorithm SHA256).Hash

$recordLines = @(
    "SHA256=$patchedHash"
    "Version=$Version"
    "Provenance=patched-rebrand"
    "SignatureStatus=$patchedSignature"
    "Platform=$Platform"
    "Rebrand=$Brand"
)
if ($bannerVersion) { $recordLines += "BannerVersion=$bannerVersion" }
$recordLines += "UpstreamSHA256=$upstreamHash"
$recordLines += "UpstreamSignatureStatus=$upstreamSignature"
$recordLines | Set-Content -Path $Record -Encoding UTF8

$versionOut = (& $Destination --version 2>&1 | Out-String).Trim()
if ($versionOut -notmatch [regex]::Escape($Version)) {
    throw "Patched engine failed its version check: $versionOut"
}

Write-Host "Patched engine: $Destination"
Write-Host "  sha256:    $patchedHash"
Write-Host "  signature: $patchedSignature (was $upstreamSignature)"
Write-Host "  version:   $versionOut"
if ($bannerVersion) { Write-Host "  banner:    $bannerVersion" }
Write-Host 'Run fife\setup.ps1 (with claude-fife closed) or simply relaunch claude-fife to install the pin.'
