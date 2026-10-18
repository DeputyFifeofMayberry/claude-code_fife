# claude-fife: Isolated Claude Code Daily Driver — Design

Date: 2026-10-18
Status: Approved design (brainstorming complete). Implementation plan to follow.

## Intent and why

The user wants a personal fork-branded Claude Code (`claude-fife`) as their
daily driver: behavior identical to real Claude Code, but with its own file
trees so it never shares config, state, history, or credentials with the real
`claude` installation. Real Claude Code was factory-reset on 2026-10-17
(`~/.claude` and `~/.claude.json` deleted; binary v2.1.302 left installed) and
is to be removed once `claude-fife` works.

The fork repository (`DeputyFifeofMayberry/claude-code_fife`, a fork of
`anthropics/claude-code`) contains no CLI source and nothing buildable into an
executable — it is docs, plugins, and the published `mods/`. Therefore the
engine is the genuine Claude Code binary, pinned and isolated, and the fork
repo serves as the control center for the setup.

## Goals

1. A `claude-fife` command on Windows (PowerShell + cmd) that behaves exactly
   like `claude` — all subcommands, flags, and arguments pass through 1:1.
2. Complete user-level isolation: config, settings, history, transcripts,
   credentials, and cache live under `C:\Users\barne\claude-fife\` and never
   in `~/.claude` or `~/.claude.json`.
3. Three backends, switchable in-session via `/model`:
   - Anthropic (default at launch),
   - z.ai coding plan (GLM models), credentials reused from the user's
     OpenCode config,
   - ChatGPT/Codex subscription (OAuth), credentials reused from the existing
     Codex CLI login on this machine.
4. Factory-fresh starting content: no plugins, skills, hooks, or MCP servers
   on day one beyond what the backend wiring requires.
5. Reproducible from the fork repo **on this machine, for this user**: clone
   repo, run the setup script, get a working `claude-fife`. Portability to
   other machines/users is explicitly out of scope.
6. Real `claude` uninstalled as the final step, after acceptance passes.

## Non-goals

- No patching of the Claude Code binary and no internal rebranding (help
  text, banners, strings still say Claude Code).
- No `CLAUDE-FIFE.md` / `.claude-fife/` project-level rename (accepted
  softening below).
- No tracking of upstream Claude Code releases; no auto-update.
- No plugins/skills/MCP migration from OpenCode (factory fresh).
- No changes to OpenCode's own config or behavior.

## Anti-goals (failure even if it "works")

- `claude-fife` ever reading or writing `~/.claude` or `~/.claude.json`.
- Any secret (z.ai key, Codex tokens, Anthropic credentials) committed to
  git, printed to logs, or written outside the fife tree.
- Breaking the existing Codex CLI login (e.g. by invalidating its OAuth
  refresh token through competing refreshes) or breaking OpenCode.
- Removing real `claude` before `claude-fife` passes acceptance.
- Router (if any) listening on anything other than localhost, or logging
  prompt/response content.

## Constraints and verified machine facts

- Windows, PowerShell primary shell. Real engine:
  `C:\Users\barne\.local\bin\claude.exe`, version **2.1.302**
  (verified `--version`).
- `~/.claude` and `~/.claude.json` do not exist (post-reset).
- Codex CLI installed (`codex` on PATH) with ChatGPT subscription tokens in
  `~/.codex/auth.json` (no OpenAI API key).
- OpenCode config (`~/.config/opencode/opencode.json`) contains the z.ai/GLM
  provider credentials.
- No Anthropic credentials exist anywhere on the machine; the Anthropic
  backend requires one fresh interactive login performed by the user.
- Claude Code speaks only the Anthropic API natively. z.ai exposes an
  Anthropic-compatible endpoint. ChatGPT/Codex subscription does not speak
  the Anthropic API at all — in-session switching across all three therefore
  requires a local translation router, whose selection is gated (below).

## Decisions (user's, from brainstorming)

| Topic | Decision |
|---|---|
| Engine | Genuine Claude Code binary, renamed/isolated, unmodified. |
| Version | Pin forever at v2.1.302. Auto-updater disabled. |
| Binary source | Fresh download of v2.1.302 preferred; see Risks for fallback. |
| Command | `claude-fife` launcher shim is acceptable (not required to be an `.exe`). |
| Fife root | `C:\Users\barne\claude-fife\` — self-contained: binary, config, state, router, cache, logs. |
| Isolation | Fully separate user-level trees. |
| Project files | Softened: `claude-fife` reads the project's existing `CLAUDE.md` (shared instructions). All state/settings/history remain in fife trees. |
| Backends | Anthropic (default), z.ai GLM, ChatGPT/Codex subscription. |
| Switching | In-session via `/model`, across providers. |
| Router | NOT pre-approved. Plan must evaluate options first, with a decision gate (below). |
| Starting content | Factory fresh. |
| Credentials | Reuse z.ai (OpenCode config) and Codex (existing login); Anthropic = **Claude subscription** via one fresh user-performed interactive OAuth login. If the router gate proves the router cannot legitimately reuse that subscription login, the gate returns to the user rather than silently switching billing paths. |
| Isolation boundary | All fife **files** under the fife tree. Windows Credential Manager entries (keyed to the fife identity) are acceptable — real Claude Code uses OS credential stores too. Any other out-of-tree file write found in verification is a blocking finding to report, not to paper over. |
| Binary durability | Pristine v2.1.302 binary backed up **outside** the fife tree on this machine (my call: `C:\Users\barne\claude-fife-backup\`), with SHA-256 + signature status recorded in the repo. The binary itself is never committed (public fork; redistribution). Repo holds hash + restore procedure only. |
| Reproducibility scope | This Windows machine, this user account only. Hardcoded root and known credential-source locations are acceptable. |
| Concurrency that matters | `claude-fife` alongside OpenCode in the same project. |
| Real `claude` | Keep until acceptance passes; uninstall as the last step. |
| Fork repo role | Control center: setup script, launcher source, provider profiles, settings templates, docs — versioned in git. |

## My calls (settled by the author, flagged for user review)

- Local clone of the control-center repo: `C:\Users\barne\Source\claude-code_fife`
  (already cloned during design; `main` @ `dd6bee3`).
- Shim form: a PowerShell launcher (`claude-fife.ps1`) plus a `claude-fife.cmd`
  forwarder so the command works from both PowerShell and cmd. Exact PATH
  placement (fife `bin\` added to user PATH) to be fixed in the plan.
- Proposed fife subtree layout (plan may adjust after empirical verification
  of where the engine actually writes when `CLAUDE_CONFIG_DIR` is set):
  - `bin\` — pinned engine + launcher shims
  - `config\` — target of `CLAUDE_CONFIG_DIR` for fife sessions
  - `router\` — router binary/config/logs (only if the gate approves one)
  - `logs\` — launcher/setup logs (no prompt content, no secrets)
- Project-level `.claude/settings.json` in a shared project is treated as
  shared project settings (same softening as `CLAUDE.md`); fife-only project
  overrides are out of scope unless the plan finds a clean mechanism.

## Architecture sketch

1. **Launcher (`claude-fife`)**: sets fife-only environment
   (`CLAUDE_CONFIG_DIR` → fife config tree, auto-update disabled, backend
   endpoint/model variables as required by the chosen backend mode), ensures
   the router is running if the design requires one, then invokes the pinned
   engine with all arguments unchanged. Must not leak fife environment into
   the calling shell or into OpenCode.
2. **Engine**: unmodified Claude Code v2.1.302, stored inside the fife tree,
   auto-updater disabled via settings/env so the pin holds.
3. **Router (gated)**: a localhost-only translation layer
   `claude-fife → router → {Anthropic | z.ai | OpenAI/Codex}` enabling
   cross-provider `/model` switching. Selection happens in the evaluation
   phase; candidates include existing tools (claude-code-router, LiteLLM,
   CLIProxyAPI class) versus a small custom proxy. Evaluation criteria:
   ChatGPT-subscription OAuth support and token-refresh safety, Anthropic
   passthrough fidelity (tool use, streaming, prompt caching),
   z.ai endpoint support, `/model` naming, Windows operability, localhost
   binding, log redaction, maintenance burden.
4. **Control center (fork repo)**: idempotent `setup.ps1` that builds the
   fife tree from any machine state (including "claude already removed"),
   launcher source, provider profile templates, this design, and setup docs.
   Secrets are read from their existing machine locations at setup time and
   written only into the fife tree; never committed (`.gitignore` enforced).

## Decision gate: router evaluation

The plan's first phase is a time-boxed router evaluation, ending in a written
comparison and a user-approved choice (including the "no router — drop
in-session cross-provider switching or drop the Codex backend" fallback)
before any backend wiring is built. Known hard problem: two clients (Codex
CLI and the router) sharing one ChatGPT OAuth grant can invalidate each
other's refresh tokens; the evaluation must state how the chosen option
avoids or accepts this, and must not proceed on an option that silently
breaks `codex`.

## Acceptance criteria

User-approved wording: "`claude-fife` installed, commands like `claude-fife`
work exactly as real claude would, all 3 backends ready to be connected."

Operationalized:

1. `claude-fife --version` reports 2.1.302; `--help` and representative
   subcommands work from PowerShell and cmd.
2. A real prompt is answered by each backend (Anthropic after the user's
   fresh login; z.ai via reused credentials; Codex subscription via reused
   login, if the router gate approves that backend's mechanism), and
   `/model` switches backend in-session where the approved design promises
   it.
3. File-tree proof: after the above, `~/.claude` / `~/.claude.json` have not
   been recreated by fife activity (any recreation attributable to real
   `claude` must be distinguished), and fife state demonstrably lives under
   `C:\Users\barne\claude-fife\`.
4. Codex CLI still works after Codex-backend use (login not invalidated);
   OpenCode still works.
5. `claude-fife` runs in the same project as OpenCode without interference.
6. Only then: real `claude` is uninstalled and `claude` no longer resolves,
   while `claude-fife` still passes 1–4.

## Risks and open items for the plan

- **Versioned download availability**: Anthropic's installer serves the
  current release; a fresh v2.1.302 artifact may not be obtainable. Fallback:
  copy the installed v2.1.302 binary before uninstalling. Either way, the
  obtained binary is preserved in `C:\Users\barne\claude-fife-backup\` with
  its SHA-256 and signature status recorded in the repo, and the plan must
  document which source was used. Setup after real-claude removal restores
  from that backup.
- **Pin-forever security exposure**: upstream fixes never arrive. Accepted
  by the user; the setup docs must state how to deliberately re-pin.
- **Config-dir behavior**: the exact set of files the engine places under
  `CLAUDE_CONFIG_DIR` versus elsewhere (e.g. `~/.claude.json`, `%APPDATA%`)
  must be verified empirically; the tree layout adapts to findings.
  Isolation acceptance is judged on observed writes, not assumptions.
  Windows Credential Manager use is pre-approved (see Decisions); any other
  out-of-tree file write blocks acceptance pending a user decision.
- **Anthropic subscription through a router**: the engine's interactive
  subscription login may live in the engine's own credential store and not
  be reusable by a separate router process. The router gate must prove how
  Anthropic-as-default coexists with in-session switching under a
  subscription login, or escalate back to the user.
- **Router token-refresh contention** with Codex CLI (see gate).
- **Shim/PATH interactions**: `claude-fife` must resolve identically in
  PowerShell, cmd, and from OpenCode-launched shells.

## What's left to the builder

- Router selection (through the gate) and its exact config.
- Exact setup-script implementation, PATH mechanics, and subtree layout
  refinements after empirical config-dir verification.
- Model roster per backend exposed via `/model` (sensible defaults from each
  provider's current lineup; Anthropic default at launch is fixed).
- Verification scripts implementing the acceptance criteria.
