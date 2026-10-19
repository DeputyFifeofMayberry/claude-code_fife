# claude-fife — Startup symbol

The claude-fife symbol is a 256-color ANSI drawing of the Claude mark,
`fife\assets\claude-symbol.ans`. It appears in three places:

- the launcher prints it while an interactive session starts, above the
  engine's welcome screen;
- the `fife-symbol` mod draws the same art **inside the session**, in the band
  directly above the prompt, so the symbol is part of the running TUI;
- a 9x3 corner mark derived from the art sits at the top left of every new
  session, beside the version.

## Where it lives

| Copy | Location |
|---|---|
| Art, source of truth (repo) | `fife\assets\claude-symbol.ans` |
| Splash renderer (repo) | `fife\tools\Show-ClaudeSymbol.ps1` |
| In-session mod (repo) | `fife\mods\fife-symbol\` |
| Corner glyph patcher (repo) | `fife\tools\Invoke-EngineSymbol.ps1` |
| Art, installed tree | `C:\Users\barne\claude-fife\assets\claude-symbol.ans` |
| Splash renderer, installed | `C:\Users\barne\claude-fife\bin\Show-ClaudeSymbol.ps1` |
| Mod, installed | `C:\Users\barne\claude-fife\config\mods\fife-symbol\` |

`fife\setup.ps1` creates `assets\` and `config\mods\`, copies the art and the
splash renderer into the fife tree, and installs the mod folder. The launcher
loads the mod with `--plugin-dir <root>\config\mods\fife-symbol` when it is
present; a bare checkout without setup still starts.

## When it is shown

`CLAUDE_FIFE_SYMBOL` picks the mode, for the splash and the in-session symbol
alike:

- `auto` (default): the splash prints for an interactive launch, and the
  in-session band draws the symbol until the first prompt is submitted.
- `always`: the splash always prints, and the in-session symbol stays in the
  band for the whole session.
- `never`: neither appears.

The splash never prints for `-p`/`--print`, `--output-format`, `--help`,
`mcp`, `config`, `doctor`, or any run whose output is redirected. A missing or
unreadable asset is ignored: the session still starts.

## Inside the session

The mod is a hooks module named `fife-symbol`. It hangs a `ui.render` hook on
the `AbovePrompt` band and draws the art as one terminal `Raster`: the parsed
ANSI cells (glyph, foreground, background) are packed as base64 u32 triplets,
so the full 256-color drawing is reproduced exactly. It shrinks to the band's
`bodyColumns`/`maxRows` when the terminal or the fullscreen slot is smaller,
never enlarging, and yields when a survey holds the band. The art is read from
`<mod root>\..\..\assets\claude-symbol.ans`, which is `fife\assets` in a
checkout and `<fife root>\assets` in the installed tree.

The mod passes in every case that is not the terminal surface, so desktop,
VS Code and mobile sessions are untouched.

## The corner glyph

A new session's header draws a 3-row x 9-column animated glyph at the top
left. `fife\tools\Invoke-EngineSymbol.ps1` replaces its glyph constants with a
braille rendition of the art. A braille cell is a 2x4 dot matrix, so the 9x3
corner holds an 18x12 dot grid — four times the resolution of a plain block
cell — and the art's silhouette and notches survive at that size:

```
⠀⣠⣶⣶⣶⣶⣶⣦⠀
⠀⢸⣿⣿⣿⣿⣿⢿⠀
⠀⣠⣬⣿⣿⣿⣧⣤⡀
```

The engine draws that glyph from UTF-16 entries in its Bun bytecode string
table: one entry per arm, eye and foot fragment, one for the middle of the
body row, and one per row of every facing frame. The tool replaces those
entries one for one with the same code-unit counts, so the table layout and
every recorded offset stay intact.

The patch is pinned to engine 2.1.303: the tool checks the table position,
count and every entry's current text before writing and refuses any other
build. The entry indices happen to match 2.1.302's; a later engine may shift
them, so re-derive them from the bytecode table before re-pinning.

## Applying the corner glyph

The glyph lives in the pinned engine binary, so it is applied by patching that
binary the same way the identity rebrand is. Run the rebrand first, then the
glyph patch, because the rebrand rewrites the pin record from scratch:

```powershell
pwsh fife\tools\Invoke-EngineRebrand.ps1 -KeepOriginal -FifeVersion 2.1.303r2
pwsh fife\tools\Invoke-EngineSymbol.ps1
```

The patcher updates the pin record's `SHA256` and adds
`SymbolMark=claude-fife-mark-braille-18x12`, keeping the upstream hash and
signature lines as provenance. Running sessions do not block the new pin:
`Ensure-EnginePin` in the launcher renames the in-use engine aside and installs
the patched build at the canonical path, so it applies on the next launch.
Sessions already open keep the renamed image until they exit; the
`claude-fife-engine.exe.old-*` files next to `bin\` can be deleted once no
session is running.

## Updating the art

1. Replace `fife\assets\claude-symbol.ans` with the new art, keeping it UTF-8
   with its ANSI escape sequences intact.
2. Run `pwsh fife\setup.ps1` to install the copy (or copy it to
   `C:\Users\barne\claude-fife\assets\claude-symbol.ans` by hand). The splash
   and the mod read the installed art, so no mod change is needed.
3. Preview the splash with `pwsh fife\tools\Show-ClaudeSymbol.ps1`.
4. If the corner mark should follow the new art, update its rows in
   `fife\tools\Invoke-EngineSymbol.ps1` and re-run it on a fresh rebranded pin.

## Tests

`tests\Test-Symbol.ps1` checks the asset, the splash renderer, the mod files
and the launcher's `--plugin-dir`. `tests\Test-EngineSymbol.ps1` patches a
copy of the pinned engine and checks the glyph entries, the version and the pin
record. The mod's own tests (`claude plugin test fife\mods\fife-symbol`) cover
the ANSI parser, the fit and the cell encoding.

## Why the full art is not in the corner

The corner is a fixed 3-row x 9-column glyph in the engine's header layout;
the full 64x42 true-color drawing cannot be placed there, and a plain block
downscale collapses to a blob because 42 rows become 3. The braille rendition
recovers as much of the shape as that footprint allows (18x12 dots), and the
splash and the in-session band carry the full drawing at its native size.
