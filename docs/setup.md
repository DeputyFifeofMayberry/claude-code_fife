# claude-fife — Setup, Restore, Re-pin, Limitations

Machine scope: this Windows machine, user `barne` only (by design).

## What exists where

| Thing | Location |
|---|---|
| Control-center repo (this repo) | `C:\Users\barne\Source\claude-code_fife` |
| Fife tree (engine, launchers, config, router) | `C:\Users\barne\claude-fife\` |
| Pinned engine backup v2.1.302 + hash record | `C:\Users\barne\claude-fife-backup\` |
| `claude-fife` command | `C:\Users\barne\claude-fife\bin\` (on user PATH) |
| Router OAuth logins (Claude + Codex subscriptions) | `C:\Users\barne\claude-fife\router\auth\` |
| Router local API key + z.ai key | `C:\Users\barne\claude-fife\router\api-key.txt`, `config.yaml` — never commit, never share |
| OpenCode | untouched, separate product/config |

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

## Deliberate re-pin (moving to a newer engine, by hand)

1. Edit `fife\tools\Get-PinnedEngine.ps1` `$Version` (and the exe name in
   `fife\setup.ps1`) to the new version.
2. Run `pwsh fife\tools\Get-PinnedEngine.ps1` — downloads the new binary,
   verifies it against the official manifest, rewrites the backup + record.
3. Re-run `pwsh fife\setup.ps1` and the full acceptance gauntlet
   (`fife\tools\Test-Acceptance.ps1`).
4. Commit the version bump (script changes only — never the binary).

If the fresh download of the pinned version ever becomes unobtainable while
the current binary still exists, `Get-PinnedEngine.ps1` falls back to copying
the installed engine and records `Provenance=copied-installed`.

## Known limitations (accepted in the design)

- **Pin forever**: upstream security fixes do not arrive until you re-pin.
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
