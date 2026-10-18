# Isolation Findings — claude-fife Task 3

Date: 2026-10-18. Method: `tests/Test-Isolation.ps1` snapshots top-level
entries of `%USERPROFILE%`, `%APPDATA%`, `%LOCALAPPDATA%` (Temp excluded —
constant system churn) before/after running the pinned engine with fife env,
and asserts no out-of-tree change and no `~/.claude*` recreation.

## Verified facts

With `CLAUDE_CONFIG_DIR=C:\Users\barne\claude-fife\config` and
`DISABLE_AUTOUPDATER=1`, engine v2.1.302 (`--version` and headless `-p`,
unauthenticated) created **only**:

- `config\.claude.json` — the state file that would normally be
  `~/.claude.json` moves **inside** the config dir. No separate state-file
  handling needed.
- `config\projects\<encoded-cwd>\` — per-project transcripts/memory.
- `config\sessions\`, `config\backups\` (incl. `.claude.json` backups).

Nothing was written to `%USERPROFILE%` top level, `%APPDATA%`, or
`%LOCALAPPDATA%`; `~/.claude` and `~/.claude.json` were **not** created.
No `claude`/`anthropic` entries appeared in Windows Credential Manager
pre-login (checked `cmdkey /list`). Credential storage location after the
Task 6 subscription login must be re-checked then; OS credential store use
is pre-approved by the user, any other out-of-tree file write is blocking.

## Consequences for the build

- Fife subtree layout confirmed: `bin\` (engine + shims), `config\`
  (= `CLAUDE_CONFIG_DIR`; holds `.claude.json`, projects, sessions,
  backups), `router\` (Task 2 contract), `logs\`.
- Launcher must set exactly: `CLAUDE_CONFIG_DIR=<fife>\config`,
  `DISABLE_AUTOUPDATER=1` (settings `autoUpdates: false` added in Task 5
  as belt-and-braces), plus router env per the Router Contract.
- Test watch scope excludes `%LOCALAPPDATA%\Temp` (system churn, and an
  early probe artifact taught us to keep probe projects inside the fife
  root). Probe project: `C:\Users\barne\claude-fife\probe-project\`
  (created by the test; harmless, may be deleted).
