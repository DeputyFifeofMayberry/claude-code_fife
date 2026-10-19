# claude-fife — Startup symbol

The claude-fife symbol is a 256-color ANSI drawing of the Claude mark,
`fife\assets\claude-symbol.ans`. The launcher prints it above the engine's
welcome screen when an interactive session starts, so the first thing a
session shows is the claude-fife symbol.

## Where it lives

| Copy | Location |
|---|---|
| Source of truth (repo) | `fife\assets\claude-symbol.ans` |
| Renderer (repo) | `fife\tools\Show-ClaudeSymbol.ps1` |
| Installed tree | `C:\Users\barne\claude-fife\assets\claude-symbol.ans` |
| Installed renderer | `C:\Users\barne\claude-fife\bin\Show-ClaudeSymbol.ps1` |

`fife\setup.ps1` creates `assets\` and copies both files into the fife tree.
The launcher shows the installed copy, falling back to the repo copy when run
from a checkout.

## When it is shown

- Interactive launches (a terminal on both stdin and stdout) show the symbol
  before the engine starts.
- Non-interactive launches stay byte-clean: `-p`/`--print`,
  `--output-format`, `--help`, `mcp`, `config`, and `doctor` never print it,
  and neither does any run whose output is redirected.
- `CLAUDE_FIFE_SYMBOL=never` turns it off; `CLAUDE_FIFE_SYMBOL=always` forces
  it on (useful in tests and demos).

A missing or unreadable asset is ignored: the session still starts.

## Updating the art

1. Replace `fife\assets\claude-symbol.ans` with the new art, keeping it UTF-8
   with its ANSI escape sequences intact.
2. Run `pwsh fife\setup.ps1` to install the copy into the fife tree (or copy it
   to `C:\Users\barne\claude-fife\assets\claude-symbol.ans` by hand).
3. Preview with `pwsh fife\tools\Show-ClaudeSymbol.ps1`.

`tests\Test-Symbol.ps1` checks that the asset still carries its 256-color
sequences and block glyphs, that the renderer reproduces it byte-for-byte, and
that the launcher honors the `always`/`never`/`auto` modes.

## Why the launcher draws it

The engine's own welcome logo is compiled into its Bun bytecode as a set of
58-byte art strings, sized for a monochrome banner and fixed at the pinned
engine version. A full 64x42 true-color drawing cannot be spliced into that
layout without growing the bytecode string table, which would move every
offset recorded after it. Drawing the symbol in the launcher keeps the art
exact, version-independent, and safe to change without touching the pinned
engine.
