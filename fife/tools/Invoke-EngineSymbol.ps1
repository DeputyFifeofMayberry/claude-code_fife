#Requires -Version 7.0
# Replaces the small Clawd mark at the top left of a new session with a
# braille rendition of assets\claude-symbol.ans. The 9x3 corner holds 18x12
# braille dots, which keeps the art's silhouette and notches at that size.
#
# The mark is drawn by the engine's header component from glyph strings in
# the bytecode string table. The table keeps one UTF-16 entry per glyph
# fragment, and the component reads those entries at draw time. Every entry
# patched here keeps its exact code-unit count, so the table layout and the
# encoded offsets stay intact. The tool verifies each entry's current text
# before writing and refuses to patch an engine that is not the pinned build.
#
# The engine's own version (2.1.302) is left untouched. The patch changes the
# Authenticode hash; the pin record keeps the upstream hash and signature
# alongside the patched hash, as Invoke-EngineRebrand.ps1 does.
#
# Usage:
#   pwsh fife\tools\Invoke-EngineSymbol.ps1                     # patch the pin
#   pwsh fife\tools\Invoke-EngineSymbol.ps1 -Destination <path> # patch a copy
[CmdletBinding()]
param(
    [string]$Source = 'C:\Users\barne\claude-fife-backup\claude-2.1.302.exe',
    [string]$Destination = '',
    [string]$Record = 'C:\Users\barne\claude-fife-backup\SHA256.txt',
    [string]$Version = '2.1.302'
)
$ErrorActionPreference = 'Stop'
if ($Destination -eq '') { $Destination = $Source }
if (-not (Test-Path $Source)) { throw "Engine not found: $Source" }

# Layout of the 2.1.302 bytecode string table (same pin as the rebrand tool).
$tableBase = 122177408
$tableCount = 255962
$utf16 = [System.Text.Encoding]::Unicode

function Read-U32([byte[]]$d, [int]$o) {
    [int]$d[$o] -bor ([int]$d[$o+1] -shl 8) -bor ([int]$d[$o+2] -shl 16) -bor ([int]$d[$o+3] -shl 24)
}

function Get-Entry([byte[]]$d, [int]$index) {
    $p = $tableBase + (Read-U32 $d ($tableBase + 4 + 4 * $index))
    $w = Read-U32 $d $p
    [pscustomobject]@{
        Index      = $index
        Units      = ($w -band 0x7fffffff)
        Latin1     = (($w -band 0x80000000) -ne 0)
        TextOffset = $p + 8
    }
}

function Get-EntryText([byte[]]$d, $entry) {
    if ($entry.Latin1) {
        return [System.Text.Encoding]::Latin1.GetString($d, $entry.TextOffset, $entry.Units)
    }
    $utf16.GetString($d, $entry.TextOffset, $entry.Units * 2)
}

# A braille cell is a 2x4 dot matrix, so 9x3 cells give the mark an 18x12
# dot grid: the art's silhouette and notches survive at the corner's size.
$row0 = "`u{2800}`u{28e0}`u{28f6}`u{28f6}`u{28f6}`u{28f6}`u{28f6}`u{28e6}`u{2800}"
$row1 = "`u{2800}`u{28b8}`u{28ff}`u{28ff}`u{28ff}`u{28ff}`u{28ff}`u{28bf}`u{2800}"
$row2 = "`u{2800}`u{28e0}`u{28ec}`u{28ff}`u{28ff}`u{28ff}`u{28e7}`u{28e4}`u{2840}"
$armL = $row0.Substring(0, 2)
$top = $row0.Substring(2, 6)
$armR = $row0.Substring(8, 1)
$bodyL = $row1.Substring(0, 2)
$bodyM = $row1.Substring(2, 5)
$bodyR = $row1.Substring(7, 2)
$lid = $row0.Substring(2, 1)
$lidBody = $row0.Substring(3, 3)
$wink = $row0.Substring(2, 4)

# Index in the 2.1.302 string table, the glyph it holds now, and the glyph
# that takes its place. Every replacement keeps the entry's code-unit count.
$patches = @(
    # Arms: down and one-up share these; up has its own.
    @{ Index = 59392; Old = ' ▐'; New = $armL }
    @{ Index = 59393; Old = '▝▜'; New = $bodyL }
    @{ Index = 59394; Old = '█▀'; New = $bodyR }
    @{ Index = 59395; Old = '▗▟'; New = $armL }
    @{ Index = 59396; Old = '▄'; New = $armR }
    @{ Index = 59397; Old = ' ▜'; New = $bodyL }
    @{ Index = 59398; Old = '█▘'; New = $bodyR }
    # Eyes: open, left and right share the top edge; blinks keep the shape.
    @{ Index = 59399; Old = '▛███▛█'; New = $top }
    @{ Index = 59400; Old = '▟███▟█'; New = $top }
    @{ Index = 59401; Old = '█▟███▟'; New = $top }
    @{ Index = 59402; Old = '▂'; New = $lid }
    @{ Index = 59403; Old = '███'; New = $lidBody }
    @{ Index = 59404; Old = '▛███'; New = $wink }
    # Feet: every stance is the same bottom edge, so the mark does not wobble.
    @{ Index = 59405; Old = ' ▝▝   ▝▝ '; New = $row2 }
    @{ Index = 59406; Old = ' ▝▝      '; New = $row2 }
    @{ Index = 59407; Old = '      ▝▝ '; New = $row2 }
    # The middle of row 1 is the component's own literal, patched too.
    @{ Index = 59446; Old = '█████'; New = $bodyM }
    # The facing frames: every row becomes the matching mark row.
    @{ Index = 59413; Old = ' ▐█▜██▛█ '; New = $row0 }
    @{ Index = 59415; Old = '  █▛██▛▌ '; New = $row0 }
    @{ Index = 59418; Old = '  ▐█▛█▜  '; New = $row0 }
    @{ Index = 59421; Old = '   ██▛▌  '; New = $row0 }
    @{ Index = 59424; Old = '   ▐██   '; New = $row0 }
    @{ Index = 59426; Old = '  █████▌ '; New = $row0 }
    @{ Index = 59427; Old = ' ▐██████ '; New = $row0 }
    @{ Index = 59428; Old = '   ▛██▌  '; New = $row0 }
    @{ Index = 59429; Old = '  ▐▜▛██  '; New = $row0 }
    @{ Index = 59430; Old = '  ▛██▛█▌ '; New = $row0 }
    @{ Index = 59431; Old = ' ▐▛███▜█ '; New = $row0 }
    @{ Index = 59414; Old = '▝▜██████▀'; New = $row1 }
    @{ Index = 59416; Old = ' ▝█████▛ '; New = $row1 }
    @{ Index = 59419; Old = '  ▐████  '; New = $row1 }
    @{ Index = 59422; Old = '   ███▌  '; New = $row1 }
    @{ Index = 59417; Old = '  ▘▘  ▘▘ '; New = $row2 }
    @{ Index = 59420; Old = '  ▝▝ ▝▝  '; New = $row2 }
    @{ Index = 59423; Old = '   ▘  ▘  '; New = $row2 }
    @{ Index = 59425; Old = '   ▝ ▝   '; New = $row2 }
)

$bytes = [System.IO.File]::ReadAllBytes($Source)
if ($bytes.Length -lt $tableBase -or (Read-U32 $bytes $tableBase) -ne $tableCount) {
    throw "bytecode string table not at the pinned location. Engine $Version may differ from the pinned build; refusing to write."
}

$toPatch = @()
$already = 0
foreach ($p in $patches) {
    $entry = Get-Entry $bytes $p.Index
    if ($entry.Latin1) {
        throw "glyph $($p.Index): expected a UTF-16 entry, found a Latin-1 entry. Engine $Version may differ from the pinned build; refusing to write."
    }
    $current = Get-EntryText $bytes $entry
    if ($current -eq $p.Old) {
        $toPatch += [pscustomobject]@{ Patch = $p; Entry = $entry }
    } elseif ($current -eq $p.New) {
        $already++
    } else {
        throw "glyph $($p.Index): expected '$($p.Old)', found '$current'. Engine $Version may differ from the pinned build; refusing to write."
    }
}
if ($already -gt 0 -and $toPatch.Count -gt 0) {
    throw "the engine holds a partial symbol patch ($already up to date, $($toPatch.Count) old); refusing to write."
}

$upstreamHash = (Get-FileHash $Source -Algorithm SHA256).Hash
$upstreamSignature = (Get-AuthenticodeSignature $Source).Status.ToString()

if ($toPatch.Count -gt 0) {
    foreach ($item in $toPatch) {
        $newBytes = $utf16.GetBytes($item.Patch.New)
        if ($newBytes.Length -ne $item.Entry.Units * 2) {
            throw "glyph $($item.Patch.Index): replacement changes the entry length; refusing to write."
        }
        [Array]::Copy($newBytes, 0, $bytes, $item.Entry.TextOffset, $newBytes.Length)
    }
    [System.IO.File]::WriteAllBytes($Destination, $bytes)
    $patchedHash = (Get-FileHash $Destination -Algorithm SHA256).Hash
    $patchedSignature = (Get-AuthenticodeSignature $Destination).Status.ToString()

    if (Test-Path $Record) {
        $recordMap = [ordered]@{}
        foreach ($line in Get-Content $Record) {
            if ($line -match '^([^=]+)=(.*)$') { $recordMap[$Matches[1]] = $Matches[2] }
        }
        $recordMap['SHA256'] = $patchedHash
        $recordMap['SymbolMark'] = 'claude-fife-mark-braille-18x12'
        if (-not $recordMap.Contains('UpstreamSHA256')) { $recordMap['UpstreamSHA256'] = $upstreamHash }
        if (-not $recordMap.Contains('UpstreamSignatureStatus')) { $recordMap['UpstreamSignatureStatus'] = $upstreamSignature }
        $recordMap.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } |
            Set-Content -Path $Record -Encoding UTF8
    }
    $patched = $true
} else {
    $patched = $false
    $patchedHash = (Get-FileHash $Destination -Algorithm SHA256).Hash
}

# Re-read what was written: every entry must now hold the mark.
$check = [System.IO.File]::ReadAllBytes($Destination)
foreach ($p in $patches) {
    $entry = Get-Entry $check $p.Index
    $text = Get-EntryText $check $entry
    if ($text -ne $p.New) { throw "glyph $($p.Index): wrote '$text' instead of '$($p.New)'; refusing to save." }
}

$versionOut = (& $Destination --version 2>&1 | Out-String).Trim()
if ($versionOut -notmatch [regex]::Escape($Version)) {
    throw "Patched engine failed its version check: $versionOut"
}

Write-Host "Patched engine: $Destination"
if ($patched) {
    Write-Host "  symbol:    claude-fife-mark-braille-18x12 ($($patches.Count) glyph entries)"
    Write-Host "  sha256:    $patchedHash"
    Write-Host "  signature: $patchedSignature (was $upstreamSignature)"
} else {
    Write-Host "  symbol:    already patched"
}
Write-Host "  version:   $versionOut"
Write-Host 'Restart claude-fife to see the new mark (the launcher installs the pin on the next launch).'
