# claude-fife — Startup symbol

The claude-fife symbol is a 256-color ANSI drawing of the Claude mark,
`fife\assets\claude-symbol.ans`. It appears in two places:

- the launcher prints it while an interactive session starts, above the
  engine's welcome screen;
- the `fife-symbol` mod draws the same art **inside the session**, in the band
  directly above the prompt, so the symbol is part of the running TUI and not
  just the moment before it paints.

## Where it lives

| Copy | Location |
|---|---|
| Art, source of truth (repo) | `fife\assets\claude-symbol.ans` |
| Splash renderer (repo) | `fife\tools\Show-ClaudeSymbol.ps1` |
| In-session mod (repo) | `fife\mods\fife-symbol\` |
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

## Updating the art

1. Replace `fife\assets\claude-symbol.ans` with the new art, keeping it UTF-8
   with its ANSI escape sequences intact.
2. Run `pwsh fife\setup.ps1` to install the copy (or copy it to
   `C:\Users\barne\claude-fife\assets\claude-symbol.ans` by hand). The mod
   reads the installed art, so no mod change is needed.
3. Preview the splash with `pwsh fife\tools\Show-ClaudeSymbol.ps1`.

`tests\Test-Symbol.ps1` checks the asset, the renderer, the mod files and the
launcher's `--plugin-dir`. The mod's own tests (`claude plugin test
fife\mods\fife-symbol`) cover the ANSI parser, the fit and the cell encoding.

## Why it is not patched into the engine

The engine's own welcome logo is compiled into its Bun bytecode as a set of
58-byte art strings, sized for a monochrome banner and fixed at the pinned
engine version. A full 64x42 true-color drawing cannot be spliced into that
layout without growing the bytecode string table, which would move every
offset recorded after it. Rendering the art from the launcher and from a mod
keeps it exact, version-independent, and safe to change without touching the
pinned engine.
