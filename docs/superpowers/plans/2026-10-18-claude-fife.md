# claude-fife Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `claude-fife` — the genuine Claude Code v2.1.302 engine, pinned and isolated under `C:\Users\barne\claude-fife\`, switchable in-session between Anthropic (default), z.ai GLM, and ChatGPT/Codex subscription backends — then remove real `claude`.

**Architecture:** An unmodified, pinned Claude Code binary runs with `CLAUDE_CONFIG_DIR` pointed into a self-contained fife tree, launched by a `claude-fife` PowerShell/cmd shim that sets fife-only environment and ensures a localhost translation router (selected through an upfront evaluation gate) is running. The fork repo is the control center: setup script, launcher source, templates, verification scripts, and docs; secrets are provisioned at setup time from their existing machine locations and are never committed.

**Tech Stack:** Windows PowerShell 7 (launcher/setup/tests), genuine Claude Code native binary v2.1.302, router selected in Task 2 (candidates: claude-code-router, LiteLLM, CLIProxyAPI, small custom proxy), Pester-style test scripts under `tests/`, git (control-center repo at `C:\Users\barne\Source\claude-code_fife`).

**Spec:** `docs/superpowers/specs/2026-10-18-claude-fife-design.md`

## Global Constraints

- Fife root is exactly `C:\Users\barne\claude-fife\`; pristine binary backup is exactly `C:\Users\barne\claude-fife-backup\`.
- Engine version pinned at **2.1.302** forever; auto-updater disabled in both settings and environment. No binary patching, no internal rebranding.
- All fife files live under the fife root. Windows Credential Manager entries keyed to the fife identity are acceptable; any other out-of-tree file write is a blocking finding — stop and report, do not paper over.
- Anthropic backend = Claude **subscription** (interactive OAuth login performed by the user). No silent switch to API-key billing.
- z.ai credentials are read from `C:\Users\barne\.config\opencode\opencode.json` at setup time; Codex credentials from the existing `C:\Users\barne\.codex\auth.json` login. Secrets are never printed, logged, or committed; templates in git contain placeholders only.
- Router (if approved) binds **localhost only**, logs no prompt/response content, and must not break the existing Codex CLI login (refresh-token contention is a gate criterion).
- Starting content is factory fresh: no plugins, skills, hooks, or MCP servers beyond backend wiring.
- Scope is this machine / this user only. Project `CLAUDE.md` (and project `.claude/settings.json`) remain shared by design; all state/history/settings/credentials are fife-only.
- Real `claude` is not uninstalled until Task 8 acceptance passes and the user confirms.
- Human gates: Task 2 (router choice), Task 6 Step 1 (user performs Anthropic login), Task 9 (user confirms uninstall). Do not proceed past a gate without explicit user approval.

## Review Focus

- **Secret leakage**: a setup/launcher/router log line, test snapshot, or git commit containing a z.ai key, Codex token, or Anthropic credential. Expected: automated grep over repo + logs finds only placeholders.
- **Codex login invalidation**: router refreshing the shared ChatGPT OAuth grant until `codex` CLI demands re-login. Expected: `codex` still runs after claude-fife Codex-backend use.
- **Out-of-tree engine writes**: engine creating/recreating `~/.claude`, `~/.claude.json`, or `%APPDATA%` state during fife sessions. Expected: before/after snapshots show writes only under the fife root (Credential Manager excepted).
- **Argument mangling**: quoted args, `--model`, `-p`, and subcommands arriving altered at the engine through the `.ps1`/`.cmd` shims. Expected: passthrough tests prove byte-identical forwarding from both shells.
- **Environment leakage**: fife env vars (`CLAUDE_CONFIG_DIR`, backend endpoints/tokens) persisting into the calling shell or OpenCode sessions. Expected: post-run shell environment is unchanged.

---

### Task 1: Acquire and preserve the pinned v2.1.302 binary

**Files:**
- Create: `fife/tools/Get-PinnedEngine.ps1`
- Create: `tests/Test-PinnedEngine.ps1`
- Create (runtime, gitignored): `C:\Users\barne\claude-fife-backup\claude-2.1.302.exe`, `C:\Users\barne\claude-fife-backup\SHA256.txt`

**Interfaces:**
- Consumes: nothing.
- Produces: `Get-PinnedEngine -Destination <path>` leaves a verified engine at `<path>`; backup copy + recorded SHA-256 and Authenticode status that Tasks 5 and 9 rely on. Provenance (`fresh-download` vs `copied-installed`) recorded in `SHA256.txt`.

- [ ] **Step 1: Write the failing test** — `tests/Test-PinnedEngine.ps1` asserts: backup exe exists, `(Get-FileHash).Hash` equals `SHA256.txt` content, `& $exe --version` output matches `2.1.302`, signature status recorded (not assumed valid).
- [ ] **Step 2: Run it, verify it fails** — `pwsh tests/Test-PinnedEngine.ps1` → FAIL (backup missing).
- [ ] **Step 3: Implement `Get-PinnedEngine.ps1`** — Attempt a fresh v2.1.302 artifact from Anthropic's distribution channels first (check the native-installer release manifest/channels for a versioned artifact; do not hardcode a guessed URL — resolve it from the installer script/manifest at implementation time). If no versioned artifact is obtainable, copy `C:\Users\barne\.local\bin\claude.exe`. Either way: verify `--version` = 2.1.302, compute SHA-256, record signature status + provenance, write both files to the backup dir. Never print file contents beyond hash/version.
- [ ] **Step 4: Run test, verify PASS.**
- [ ] **Step 5: Commit** — script + test only (binary and hash record stay out of git; add `claude-fife-backup` note to docs later). `git commit -m "feat: pinned engine acquisition with provenance"`

### Task 2: Router evaluation and decision gate (HUMAN GATE)

**Files:**
- Create: `docs/router-evaluation.md`
- Create: `docs/router-decision.md` (at gate)

**Interfaces:**
- Consumes: Task 1 engine (for passthrough smoke checks).
- Produces: the **Router Contract** consumed by Tasks 4–6, recorded in `docs/router-decision.md`: chosen option (or `none`), router executable/config location under the fife root, listen address/port, how the engine is pointed at it (env vars), the `/model` naming scheme covering Anthropic / GLM / Codex models, start/stop/health-check commands, and its Codex-OAuth token-refresh strategy.

- [ ] **Step 1: Build the evaluation matrix** in `docs/router-evaluation.md` for claude-code-router, LiteLLM, CLIProxyAPI, and a small custom proxy, scored only on the spec criteria: ChatGPT-subscription OAuth support, refresh-token safety alongside Codex CLI, Anthropic passthrough fidelity (streaming, tool use, prompt caching), z.ai Anthropic-compatible endpoint support, `/model` naming, Windows operability, localhost binding, log redaction, maintenance burden.
- [ ] **Step 2: Spike the top candidate(s)** (time-box: one working day of effort) in a throwaway dir outside the repo: prove (a) Anthropic-protocol request round-trips, (b) z.ai GLM answers, (c) ChatGPT/Codex subscription answers **and** `codex` CLI still works afterwards, (d) Anthropic subscription login can serve as launch default alongside switching — or document precisely why it cannot.
- [ ] **Step 3: Write `docs/router-decision.md`** with the comparison, spike evidence, and one recommendation, including the explicit fallback options (no-router direct modes; drop Codex backend; drop in-session switching) if no candidate passes (c) or (d).
- [ ] **Step 4: GATE — present the decision doc to the user and stop.** Record the user's choice verbatim in `docs/router-decision.md`. No backend wiring is built before this approval.
- [ ] **Step 5: Commit** the evaluation + decision docs.

### Task 3: Empirical isolation probe

**Files:**
- Create: `tests/Test-Isolation.ps1`
- Create: `docs/isolation-findings.md`
- Create (runtime): `C:\Users\barne\claude-fife\config\` (probe target)

**Interfaces:**
- Consumes: Task 1 engine.
- Produces: verified facts Tasks 4–5 depend on: exact env/settings that keep engine writes inside the fife root (incl. where `.claude.json`-equivalent lands under `CLAUDE_CONFIG_DIR`), auto-update disablement that holds, and any Credential Manager entries created. `Test-Isolation.ps1` becomes the regression test for the Review Focus out-of-tree item.

- [ ] **Step 1: Write the test** — snapshot (paths + hashes) of `%USERPROFILE%` top level, `%APPDATA%`, `%LOCALAPPDATA%` before; run engine `--version` and a headless `-p "reply ok"` session with `CLAUDE_CONFIG_DIR=C:\Users\barne\claude-fife\config` and auto-update disabled; snapshot after; assert no new/modified files outside the fife root and no `~/.claude*` recreation. (Backend auth may fail in probe — file placement, not model output, is under test; use `--help`/version paths if `-p` refuses unauthenticated.)
- [ ] **Step 2: Run it** — record actual failures as findings; do not weaken assertions to force a pass.
- [ ] **Step 3: Write `docs/isolation-findings.md`** — observed write locations, required env/settings (incl. `autoUpdates` off), Credential Manager entries seen, and how each item maps to the fife subtree layout (`bin\`, `config\`, `router\`, `logs\`).
- [ ] **Step 4: Adjust test to the approved boundary** — only Credential Manager entries may be allow-listed, each named explicitly. Any other out-of-tree write → stop, report to user (per Global Constraints), and await direction before Task 4.
- [ ] **Step 5: Run test PASS; commit** test + findings.

### Task 4: `claude-fife` launcher shims

**Files:**
- Create: `fife/launcher/claude-fife.ps1`, `fife/launcher/claude-fife.cmd`
- Create: `tests/Test-Launcher.ps1`

**Interfaces:**
- Consumes: Task 1 engine path (`C:\Users\barne\claude-fife\bin\claude-fife-engine.exe`), Task 3 env/settings contract, Task 2 Router Contract (start/health-check commands; inert if contract = `none`).
- Produces: `Invoke-ClaudeFife` behavior later tasks assume: sets `CLAUDE_CONFIG_DIR` + auto-update-off + router endpoint env per contract, ensures router healthy (starting it if needed), forwards `$args` unchanged to the engine, propagates exit code, restores/leaves calling-shell env untouched. Script param contract: `claude-fife.ps1 [-EngineArgs...]` via `ValueFromRemainingArguments`.

- [ ] **Step 1: Write failing tests** — with a stub "engine" script that echoes its args + relevant env: (a) args with spaces/quotes/`--model x`/`-p` arrive byte-identical via both `.ps1` and `.cmd`; (b) engine sees `CLAUDE_CONFIG_DIR` = fife config and auto-update disabled; (c) caller shell env identical before/after; (d) engine exit code (e.g. 7) propagates; (e) router health-check invoked, router started only when unhealthy (per contract; skipped if `none`).
- [ ] **Step 2: Run, verify FAIL.**
- [ ] **Step 3: Implement the shims** — `.ps1` does env scoping (process-level only), router ensure, invocation via `& $engine @args`, `exit $LASTEXITCODE`; `.cmd` forwards `%*` to the `.ps1`. No secret values in either file; backend tokens are read from fife-tree files/env at runtime, never literals.
- [ ] **Step 4: Run tests PASS** (stub), then a real-engine smoke: `claude-fife --version` → `2.1.302 (Claude Code)` from both PowerShell and `cmd /c`.
- [ ] **Step 5: Commit** launcher + tests.

### Task 5: Idempotent setup script (control center)

**Files:**
- Create: `fife/setup.ps1`
- Create: `fife/config/settings.template.json`, `fife/config/providers.template.json` (placeholders only)
- Modify: `.gitignore` (fife runtime outputs, any local secret-bearing files)
- Create: `tests/Test-Setup.ps1`

**Interfaces:**
- Consumes: Tasks 1 (backup restore source), 3 (layout/env facts), 4 (launcher files in repo).
- Produces: `setup.ps1 [-Root 'C:\Users\barne\claude-fife']` that builds/repairs the full tree: `bin\` (engine restored from `C:\Users\barne\claude-fife-backup\` w/ hash check + launcher shims), `config\` (settings from template, auto-update off), `router\` (per Task 2 contract), `logs\`; provisions z.ai credential from the OpenCode config into the fife tree without printing it; registers `claude-fife` on the user PATH (fife `bin\`); safe to re-run.

- [ ] **Step 1: Write failing tests** — run setup against a temp `-Root`: assert tree exists, engine `--version` = 2.1.302, settings parse and disable auto-update, no file under the repo or temp root matches secret patterns from the live OpenCode config (grep for the actual key value, assert 0 hits outside the designated fife secret file), PATH contains fife `bin` exactly once. Run setup twice → identical result (idempotency).
- [ ] **Step 2: Run, verify FAIL.**
- [ ] **Step 3: Implement `setup.ps1`** — build steps small and ordered; each step check-before-act; secret provisioning reads JSON, writes only the designated fife-tree secret file with user-only ACL, emits no values to console/log.
- [ ] **Step 4: Run tests PASS**, then run real setup against `C:\Users\barne\claude-fife`.
- [ ] **Step 5: Commit** setup, templates, `.gitignore`, tests. Verify `git status` shows no secret-bearing file staged.

### Task 6: Backend wiring — Anthropic default, z.ai, Codex (per Router Contract)

**Files:**
- Create/Modify: `fife/router/` config (per Task 2 contract), `fife/config/providers.template.json` (model roster, placeholders)
- Create: `tests/Test-Backends.ps1`

**Interfaces:**
- Consumes: Task 2 Router Contract (model naming scheme, endpoint env), Task 5 tree.
- Produces: working backends with this test contract: `claude-fife -p "reply with the single word: ok" --model <roster-name>` succeeds for one roster entry per provider; default launch (no `--model`) targets Anthropic.

- [ ] **Step 1 (HUMAN GATE): Anthropic subscription login** — user runs `claude-fife` interactively once and completes the Claude subscription OAuth. Executor verifies only that a subsequent `-p` prompt succeeds; executor never handles credentials.
- [ ] **Step 2: Write failing backend tests** — one assertion per provider using the contract's roster names: response succeeds and (where the router exposes it) reports the expected provider/model. Default-model assertion: no `--model` run is served by Anthropic.
- [ ] **Step 3: Wire providers** — router config (or direct-mode env profiles if contract = `none`, with the spec-promised switching behavior re-confirmed against the gate decision): Anthropic default, z.ai GLM roster from the provisioned credential, Codex roster using the existing subscription login via the gate-approved mechanism.
- [ ] **Step 4: Run tests PASS**, including in-session switching proof: one interactive session, `/model` through all three providers, each answering.
- [ ] **Step 5: Non-interference checks** — `codex` CLI answers a trivial prompt (login intact); OpenCode still launches; re-run `tests/Test-Isolation.ps1` PASS.
- [ ] **Step 6: Commit** config templates + tests (no secret-bearing router config if it embeds tokens — template it and provision in setup instead; extend Task 5 setup if the gate's router needs that).

### Task 7: Concurrency with OpenCode in a shared project

**Files:**
- Create: `tests/Test-Concurrency.ps1`

**Interfaces:**
- Consumes: Task 6 working `claude-fife`.
- Produces: evidence for acceptance criterion 5.

- [ ] **Step 1: Write the test** — in a scratch git project: start an OpenCode session and a `claude-fife` session against the same directory; assert both respond, fife transcript/state files appear only under the fife config tree, the project's shared `CLAUDE.md` is what fife read, and neither tool errors on the other's files.
- [ ] **Step 2: Run PASS.** Any collision → record in `docs/isolation-findings.md` and report before proceeding.
- [ ] **Step 3: Commit** test (+ findings update if any).

### Task 8: Acceptance gauntlet

**Files:**
- Create: `fife/tools/Test-Acceptance.ps1`
- Create: `docs/acceptance-results.md`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: `Test-Acceptance.ps1` implementing spec acceptance criteria 1–5 as named checks with PASS/FAIL output; results recorded in `docs/acceptance-results.md`.

- [ ] **Step 1: Implement the gauntlet** — checks: version/help/subcommand smoke from PowerShell and cmd; one real prompt per backend + in-session `/model` switch; file-tree proof via `Test-Isolation.ps1`; `codex` + OpenCode health; concurrency test. Secret-grep across repo, fife `logs\`, and router logs (0 hits for live secret values).
- [ ] **Step 2: Run it; fix or report failures.** All checks PASS required.
- [ ] **Step 3: Record results** in `docs/acceptance-results.md` (date, engine hash, per-check outcome) and commit everything.

### Task 9: Remove real `claude` (HUMAN GATE, final)

**Files:**
- Modify: `docs/acceptance-results.md` (post-removal re-verification)
- Create: `docs/setup.md` (install/restore/re-pin/uninstall documentation)

- [ ] **Step 1: GATE** — show the user Task 8 results; proceed only on explicit confirmation.
- [ ] **Step 2: Uninstall real Claude Code** via its documented uninstall (remove `C:\Users\barne\.local\bin\claude.exe` and installer registration as applicable). Do not touch the fife tree or the backup.
- [ ] **Step 3: Re-verify** — `claude` no longer resolves in PowerShell or cmd; `claude-fife --version` and one prompt per backend still pass; `tests/Test-Isolation.ps1` still PASS.
- [ ] **Step 4: Write `docs/setup.md`** — fresh-setup procedure from the fork on this machine, restore-from-backup procedure, deliberate re-pin procedure (new version → new backup → hash record → re-run Tasks 3–8 checks), and the known limitations (shared project `CLAUDE.md`, OS credential store, pin-forever security note).
- [ ] **Step 5: Final commit.** Ask the user before pushing anything to GitHub.

---

## Self-Review Notes

- **Spec coverage:** engine/isolation/backends/router-gate/factory-fresh/repo-control-center/acceptance/uninstall-last each map to Tasks 1–9. Credential-reuse and subscription-billing decisions are Global Constraints enforced in Tasks 5–6. Concurrency-with-OpenCode is Task 7.
- **Gate integrity:** Tasks 4–6 consume only the Task 2 Router Contract, so a `none` outcome re-plans Tasks 4–6 against the user's gate choice instead of invalidating Tasks 1, 3, 5.
- **Known dependency:** Task 3 Step 1's `-p` probe may be limited pre-auth (Task 6 login); the task explicitly falls back to `--help`/version file-placement checks.
