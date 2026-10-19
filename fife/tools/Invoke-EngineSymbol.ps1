#Requires -Version 7.0
# Replaces the small Clawd mark at the top left of a new session with a 9x3
# Claude mark derived from assets\claude-symbol.ans: a rounded body with a
# lighter top edge, the same silhouette as the full 64x42 drawing.
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

$rows = @(
    ' ▄█████▄ '   # top edge, 9 cells
    '█████████'   # body, 9 cells
    ' ▀█████▀ '   # bottom edge, 9 cells
)

# Index in the 2.1.302 string table, the glyph it holds now, and the glyph
# that takes its place. Every replacement keeps the entry's code-unit count.
$patches = @(
    # Arms: down and one-up share these; up has its own.
    @{ Index = 59392; Old = ' ▐'; New = ' ▄' }
    @{ Index = 59393; Old = '▝▜'; New = '██' }
    @{ Index = 59394; Old = '█▀'; New = '██' }
    @{ Index = 59395; Old = '▗▟'; New = ' ▄' }
    @{ Index = 59396; Old = '▄'; New = ' ' }
    @{ Index = 59397; Old = ' ▜'; New = '██' }
    @{ Index = 59398; Old = '█▘'; New = '██' }
    # Eyes: open, left and right share the top edge; blinks keep the shape.
    @{ Index = 59399; Old = '▛███▛█'; New = '█████▄' }
    @{ Index = 59400; Old = '▟███▟█'; New = '█████▄' }
    @{ Index = 59401; Old = '█▟███▟'; New = '█████▄' }
    @{ Index = 59402; Old = '▂'; New = '█' }
    @{ Index = 59404; Old = '▛███'; New = '████' }
    # Feet: every stance is the same bottom edge, so the mark does not wobble.
    @{ Index = 59405; Old = ' ▝▝   ▝▝ '; New = $rows[2] }
    @{ Index = 59406; Old = ' ▝▝      '; New = $rows[2] }
    @{ Index = 59407; Old = '      ▝▝ '; New = $rows[2] }
    # The facing frames: every row becomes the matching mark row. The frames
    # paint their from..to span on the clawd background; the mark's cells in
    # those spans are full blocks, so the background does not show through.
    @{ Index = 59413; Old = ' ▐█▜██▛█ '; New = $rows[0] }
    @{ Index = 59415; Old = '  █▛██▛▌ '; New = $rows[0] }
    @{ Index = 59418; Old = '  ▐█▛█▜  '; New = $rows[0] }
    @{ Index = 59421; Old = '   ██▛▌  '; New = $rows[0] }
    @{ Index = 59424; Old = '   ▐██   '; New = $rows[0] }
    @{ Index = 59426; Old = '  █████▌ '; New = $rows[0] }
    @{ Index = 59427; Old = ' ▐██████ '; New = $rows[0] }
    @{ Index = 59428; Old = '   ▛██▌  '; New = $rows[0] }
    @{ Index = 59429; Old = '  ▐▜▛██  '; New = $rows[0] }
    @{ Index = 59430; Old = '  ▛██▛█▌ '; New = $rows[0] }
    @{ Index = 59431; Old = ' ▐▛███▜█ '; New = $rows[0] }
    @{ Index = 59414; Old = '▝▜██████▀'; New = $rows[1] }
    @{ Index = 59416; Old = ' ▝█████▛ '; New = $rows[1] }
    @{ Index = 59419; Old = '  ▐████  '; New = $rows[1] }
    @{ Index = 59422; Old = '   ███▌  '; New = $rows[1] }
    @{ Index = 59417; Old = '  ▘▘  ▘▘ '; New = $rows[2] }
    @{ Index = 59420; Old = '  ▝▝ ▝▝  '; New = $rows[2] }
    @{ Index = 59423; Old = '   ▘  ▘  '; New = $rows[2] }
    @{ Index = 59425; Old = '   ▝ ▝   '; New = $rows[2] }
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
        $recordMap['SymbolMark'] = 'claude-fife-mark-9x3'
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
    Write-Host "  symbol:    claude-fife-mark-9x3 ($($patches.Count) glyph entries)"
    Write-Host "  sha256:    $patchedHash"
    Write-Host "  signature: $patchedSignature (was $upstreamSignature)"
} else {
    Write-Host "  symbol:    already patched"
}
Write-Host "  version:   $versionOut"
Write-Host 'Restart claude-fife to see the new mark (the launcher installs the pin on the next launch).'
