# Acceptance Results — claude-fife

Date: 2026-10-18
Engine: Claude Code v2.1.302, provenance `fresh-download` from
downloads.claude.ai (manifest checksum verified), SHA-256 recorded in
`C:\Users\barne\claude-fife-backup\SHA256.txt`.
Router: CLIProxyAPI v8.0.33, localhost-only (verified listen socket
127.0.0.1:8317), request logging off.
Backends: Anthropic subscription (OAuth, default at launch), z.ai GLM
(provisioned key), ChatGPT/Codex subscription (OAuth) — all via the router.

Gauntlet: `fife\tools\Test-Acceptance.ps1`, 12 checks — **all PASS**
(two runs; the second after fixing a wrong test path that had made checks 3
and 5 vacuous in the first run):

| Check | Result |
|---|---|
| 1a `claude-fife --version` via PATH (PowerShell) | PASS |
| 1b `claude-fife --version` via cmd | PASS |
| 1c `--help` | PASS |
| 2a Anthropic backend prompt (`--model claude-sonnet-4-5-20250929`) | PASS |
| 2b z.ai backend prompt (`--model glm-5.3`) | PASS |
| 2c Codex backend prompt (`--model gpt-…` from live roster) | PASS |
| 2d default launch (no `--model`) served | PASS |
| 3 file-tree isolation (Test-Isolation) | PASS |
| 4a Codex CLI healthy after router use | PASS |
| 4b OpenCode healthy | PASS |
| 5 fife+OpenCode concurrency in shared project (Test-Concurrency) | PASS |
| 6 no secret leakage (repo, fife logs, router logs vs live z.ai key) | PASS |

Real logins performed by the user: router `-claude-login` and
`-codex-login` (auth files live in `C:\Users\barne\claude-fife\router\auth\`).

## Post-removal re-verification (Task 9, 2026-10-18)

After real `claude` was uninstalled (binary + `%LOCALAPPDATA%\claude`
removed): `claude` no longer resolves; `claude-fife --version` reports
2.1.302; default-Anthropic prompt answered; `tests\Test-Isolation.ps1` PASS.

Full gauntlet re-run **after** the review fix pass (router request-dump
logging disabled via `server.commercial-mode: true`, hardened whole-root
secret sweep, exit-code assertions made real, router hash pin, auth-dir ACL,
launcher no-config guard): **13/13 checks PASS** including a fresh
three-backend `Test-Backends` proof (claude-sonnet-4-5 / glm-5.3 / gpt
roster id) with `codex` CLI still healthy and isolation PASS.

Known non-blocking observations:
- The engine warns "doesn't recognize the model glm-5.3 … assumes 200k
  context" for non-Anthropic model ids. Cosmetic; behavior is correct.
- Interactive TUI `/model` switching across providers was proven
  mechanically (same gateway discovery, per-backend prompts); the user can
  watch it live any time by launching `claude-fife` and using `/model`.
