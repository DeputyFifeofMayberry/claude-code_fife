# claude-fife — Setup, Restore, Re-pin, Limitations

Machine scope: this Windows machine, user `barne` only (by design).

## What exists where

| Thing | Location |
|---|---|
| Control-center repo (this repo) | `C:\Users\barne\Source\claude-code_fife` |
| Fife tree (engine, launchers, config, router) | `C:\Users\barne\claude-fife\` |
| Pinned engine backup v2.1.303 + hash record | `C:\Users\barne\claude-fife-backup\` |
| `claude-fife` command | `C:\Users\barne\claude-fife\bin\` (on user PATH) |
| Router OAuth logins (Claude + Codex subscriptions) | `C:\Users\barne\claude-fife\router\auth\` |
| Router local API key + z.ai key | `C:\Users\barne\claude-fife\router\api-key.txt`, `config.yaml` — never commit, never share |
| Installed build id (used by `claude-fife update`) | `C:\Users\barne\claude-fife\config\fife-version.txt` |
| Startup symbol (256-color ANSI art) | `C:\Users\barne\claude-fife\assets\claude-symbol.ans` |
| OpenCode | untouched, separate product/config |

## Defaults

`claude-fife --version` is answered by the launcher, not the engine: it names
the installed fife build (`config\fife-version.txt`) and the pinned Claude Code
engine version beside it.

`config\settings.json` is created from `fife\config\settings.template.json`.
The template disables auto-updates (`DISABLE_UPDATES=1` also blocks manual
`claude update`/`claude install`) and turns on background-by-default:
Bash/PowerShell commands move to the background after 2 seconds, and
subagents and MCP tool calls auto-background. Setup merges any missing keys
into an existing `settings.json` without overwriting local edits.
To turn the behavior off, set `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` to `1`
in the `env` block.

Interactive launches print the claude-fife startup symbol — the 256-color
ANSI art in `assets\claude-symbol.ans` — before the engine draws its welcome
screen. Non-interactive runs (`-p`, `--help`, redirected output) stay
byte-clean; `CLAUDE_FIFE_SYMBOL=never` turns the symbol off and
`CLAUDE_FIFE_SYMBOL=always` forces it on. See `docs\claude-symbol.md` for how
to update the art.

## Fresh setup (this machine, after the fife tree is deleted)

```powershell
git -C C:\Users\barne\Source clone https://github.com/DeputyFifeofMayberry/claude-code_fife.git   # if repo gone
pwsh C:\Users\barne\Source\claude-code_fife\fife\setup.ps1
```

Then re-authenticate the router's OAuth logins (interactive, browser):

```powershell
& C:\Users\barne\claude-fife\router\cli-proxy-api.exe --config C:\Users\barne\claude-fife\router\config.yaml -claude-login
& C:\Users\barne\claude-fife\router\cli-proxy-api.exe --config C:\Users\barne\claude-fife\router\config.yaml -codex-login
```

Setup reads the pinned engine from the backup dir and the z.ai key from
OpenCode's local credential store; it fails loudly if the backup is missing.

## Restore (backup -> working install)

If only the fife tree is damaged, re-run `fife\setup.ps1` — it rebuilds
everything from the backup and repo templates. Verify with
`fife\tools\Test-Acceptance.ps1` (all checks must pass).

## Updating (fork releases)

`claude-fife update` and `claude-fife upgrade` are answered by the launcher, not
the engine. They compare the installed build (`config\fife-version.txt`, written
by setup) with the latest release in `DeputyFifeofMayberry/claude-code_fife` and
print the release's asset name, SHA-256, and apply steps when a newer one
exists. `claude-fife install` is refused outright. The engine's own updater and
installer are never invoked: they ignore `DISABLE_AUTOUPDATER`, install upstream
Claude Code into `C:\Users\<user>\.local\bin\`, and would bypass the fife tree.
As defense in depth the launcher and settings template set `DISABLE_UPDATES=1`,
the engine's documented switch for blocking both manual `update` and `install`.

Applying a fork release means downloading and verifying the asset, then running
its `fife\setup.ps1`. A release that moves the engine pin also needs the
re-pin steps below.

## Upstream Claude Code check (report only)

Fife pins the engine, so upstream releases do not arrive on their own. On every
interactive launch the launcher reads Anthropic's latest release and GitHub's
fork-vs-upstream compare, then prints one line:

- green when nothing is pending:
  `claude-fife: upstream 2.1.303 - current (engine 2.1.303).`
- yellow when the fork is behind, naming the pinned and upstream versions, the
  upstream commits not yet merged, and up to five `CHANGELOG.md` bullets.

The check reports only; it never downloads, merges, or installs anything. It is
silent when a feed cannot be read, and it does not block the launch. `-p` and
`--print` runs skip it unless `CLAUDE_FIFE_UPSTREAM_CHECK=1`; `--version`,
`update`, `upgrade`, `install`, and `claude-fife upstream` never run the launch
check.

`claude-fife upstream` prints the full picture on demand: installed build,
pinned engine, upstream release and date, how far the fork is ahead/behind,
the unmerged commits (first 20), the changed files (first 10), changelog
highlights, and the merge/re-pin commands when there is anything to apply. It
ends with `This command changed nothing.` and exits 1 only when the feeds
cannot be read.

| Variable | Default | Meaning |
|---|---|---|
| `CLAUDE_FIFE_UPSTREAM_CHECK` | on | `0` silences the launch check; `1` forces it even for `-p` |
| `CLAUDE_FIFE_UPSTREAM_API` | `.../anthropics/claude-code/releases/latest` | release JSON URL or local file |
| `CLAUDE_FIFE_UPSTREAM_COMPARE_API` | `.../<fork>/compare/main...anthropics:main:main` | compare JSON URL or local file |
| `CLAUDE_FIFE_UPSTREAM_TIMEOUT_SEC` | `3` | timeout for each request |

GitHub's anonymous API allows 60 requests per hour per address; a failed or
malformed lookup is silent. Merging and re-pinning remain deliberate steps.

## Deliberate re-pin (moving to a newer engine, by hand)

1. Edit `fife\tools\Get-PinnedEngine.ps1` `$Version` (the backup exe name is
   derived from it) and the backup exe name in `fife\setup.ps1` to the new
   version.
2. Run `pwsh fife\tools\Get-PinnedEngine.ps1` — downloads the new binary,
   verifies it against the official manifest, rewrites the backup + record.
3. Update the banner-version constants in
   `fife\tools\Invoke-EngineRebrand.ps1` from the new binary: `$tableBase`,
   `$tableCount`, `$versionIndex`, `$versionHash`, and `$versionText`. For
   engine 2.1.303 they are `122177408`, `255988`, `11014`, `98 64 da 00`,
   and `2.1.303`.
4. Run `pwsh fife\tools\Invoke-EngineRebrand.ps1 -KeepOriginal -FifeVersion <build>`
   and confirm the banner version.
5. Re-run `pwsh fife\setup.ps1` and the full acceptance gauntlet
   (`fife\tools\Test-Acceptance.ps1`).
6. Commit the version bump (script changes only — never the binary).

If the fresh download of the pinned version ever becomes unobtainable while
the current binary still exists, `Get-PinnedEngine.ps1` falls back to copying
the installed engine and records `Provenance=copied-installed`.

## Rebranding the engine (in-session banner)

`claude-fife --version` is answered by the launcher, but the interactive
welcome banner and terminal title are drawn inside the engine binary and read
`Claude Code`. `fife\tools\Invoke-EngineRebrand.ps1` rewrites those UI labels in
place (`Claude Code` -> `claude-fife`, 11 bytes for 11 bytes) so the embedded
JS offsets stay valid.

The banner also shows the engine version (`v2.1.303`). The tool retitles that
to the fife build, taken from `config\fife-version.txt` in the installed tree
(or `-FifeVersion`), so the banner reads `claude-fife v2.1.303r1`.

```powershell
pwsh fife\tools\Invoke-EngineRebrand.ps1 -KeepOriginal
pwsh fife\tools\Invoke-EngineRebrand.ps1 -FifeVersion 2.1.303r1   # explicit
```

The version lives in the bytecode string table: a u32 count, one u32 offset
per string, then the packed entries. Growing the version entry moves the
strings after it, so the tool shifts them, adds the same amount to their
offsets, and shortens one later message by the same number of bytes so the
table keeps its exact size. The table position and count are pinned to
engine 2.1.303; the tool refuses to patch when they differ.

The tool refuses to patch unless the pinned engine contains the expected
occurrence counts (7 welcome banners, 3 header labels, 1 notification title,
1 terminal title, 1 bytecode string-table entry), so an engine bump fails
loudly instead of half-rebranding. Bun runs the embedded bytecode, not the JS
source, so the header label also exists as a length/hash-prefixed entry in the
bytecode string table; that entry is patched too (its length and hash bytes
stay intact, as the welcome entry demonstrates the runtime does not revalidate
them for value strings).
It records `Provenance=patched-rebrand`, the patched `SHA256`, the now
`HashMismatch` signature, the `BannerVersion`, and the upstream hash/signature
alongside.

A running engine locks its file on Windows, so run setup with claude-fife
closed. Otherwise the next launch's pin sync (`Ensure-EnginePin` in the
launcher) copies the patched pin into place before starting the engine.

Re-running `Get-PinnedEngine.ps1` restores an upstream binary; run the rebrand
again afterward.

## Known limitations (accepted in the design)

- **Pin forever**: upstream security fixes do not arrive until you re-pin.
  The launch check reports upstream drift, but nothing is merged or re-pinned
  automatically.
- **Shared project files**: `claude-fife` reads each project's `CLAUDE.md`
  and project `.claude\settings.json` like real Claude Code (shared with any
  other tool); all state/history/credentials are fife-only under
  `C:\Users\barne\claude-fife\config`.
- **OS credential store**: the engine may store credentials in Windows
  Credential Manager, keyed to the fife identity (pre-approved).
- **Cosmetic warning**: non-Anthropic model ids trigger a "doesn't recognize
  the model" context-window notice. Harmless.
- **Router lifetime**: the router keeps running after claude-fife exits
  (shared across sessions). Stop it manually via Task Manager
  (`cli-proxy-api.exe`) if needed; the launcher restarts it on demand.

## Real Claude Code

Uninstalled 2026-10-18 (binary + `%LOCALAPPDATA%\claude` removed) after the
acceptance gauntlet passed. `claude` no longer resolves; `claude-fife` is
the only Claude Code on this machine.
