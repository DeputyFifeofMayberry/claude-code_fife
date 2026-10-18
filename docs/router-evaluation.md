# Router Evaluation — claude-fife Task 2

Date: 2026-10-18. Requirement (from design): Claude Code speaks only the
Anthropic API; in-session `/model` switching across Anthropic (Claude
subscription, launch default), z.ai GLM, and ChatGPT/Codex subscription
requires a localhost translation router. This document scores the candidates
and records spike evidence. Decision is the user's (see router-decision.md).

## Criteria (from design)

ChatGPT-subscription OAuth support; refresh-token safety alongside Codex CLI;
Anthropic passthrough fidelity (streaming, tool use, prompt caching);
Anthropic subscription as launch default; z.ai support; `/model` naming via
gateway model discovery; Windows operability; localhost-only binding; no
prompt/response logging; maintenance burden.

## Comparison (researched 2026-10-18, official docs/repos)

| Criterion | claude-code-router (CCR) v3.1.3 | LiteLLM v1.106 | CLIProxyAPI v8.0.33 |
|---|---|---|---|
| Accepts Anthropic `/v1/messages` from Claude Code | Yes, core purpose, 127.0.0.1:3456 | Yes, native endpoint | Yes, Claude-compatible endpoint, 127.0.0.1:8317 |
| Codex subscription OAuth | **Reads `~/.codex/auth.json` directly** (access+refresh+account), re-syncs after Codex CLI refreshes (v3.0.19) | Own device-code OAuth, separate token store; **no** auth.json import | Own OAuth (`--codex-login` / device / sign-in-through-proxy); stores own auth files; stock auth.json import UNVERIFIED |
| Refresh contention with Codex CLI | Re-sync design suggests read-mostly, but write-back behavior undocumented — UNVERIFIED | None (separate grant), but requires a second login | Undocumented — UNVERIFIED; auto-refresh workers on its own grant |
| Anthropic subscription | Imports engine's `~/.claude/.credentials.json` token; refresh partial (open PR #1408) | Forwards the client's own subscription token per request; lifecycle stays with Claude Code `/login` | **First-class**: own PKCE login, auto-refresh, multi-account |
| z.ai | Built-in presets; open double-conversion bug #1317 on Anthropic-native endpoints | Native `zai/` provider (translates itself) | Config-only via Claude-compatible upstream `base-url: https://api.z.ai/api/anthropic` |
| `/model` discovery | Gateway model discovery supported (PR #1711) | Documented, needs `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1` | Documented, same env var; model aliases |
| Windows | Desktop app .exe | Python/pip | Windows zip releases |
| Localhost binding | 127.0.0.1 default | Configurable (docs default 0.0.0.0) | **Defaults to all interfaces** — must set `host: 127.0.0.1` |
| Logging controls | Request logs off by default | Callbacks/UI | request-log/debug/file toggles + payload redaction filters |
| Activity | Monthly-ish releases | Daily releases | Releases every 1–2 days |

## Spike evidence (this machine, 2026-10-18, no live credentials used)

CLIProxyAPI v8.0.33 windows_amd64 (23.8 MB zip) extracted to a throwaway dir,
run with `host: 127.0.0.1, port: 8317, request-log: false`:

- `GET /v1/models` with a placeholder API key → **200** `{"data":[],"object":"list"}`
  (empty because no provider logins configured — endpoint and auth gate work).
- `POST /v1/messages` (Anthropic shape, unknown model) → **400 BadRequest**,
  i.e. the Anthropic-compatible endpoint exists and validates, rather than 404.
- Listening socket check: `Get-NetTCPConnection -LocalPort 8317` →
  **127.0.0.1 only** with `host: 127.0.0.1` configured (default config binds
  all interfaces, so this setting is mandatory in our templates).

Live-credential proofs (z.ai answer, Codex answer + Codex CLI still healthy,
Anthropic subscription answer) were deliberately NOT run pre-gate: they spend
real OAuth grants and the Codex refresh-contention question is exactly what
the gate must decide how to test. They are Task 6 verification steps.

CCR and LiteLLM were not spiked: CCR's Anthropic-token refresh is an open PR
and its z.ai Anthropic-endpoint path has an open mangling bug; LiteLLM cannot
reuse the Codex login at all (violates the user's "reuse what exists"
decision) and adds a Python proxy dependency. Either remains a fallback if
the gate rejects CLIProxyAPI.

## Recommendation

**CLIProxyAPI**, configured localhost-only with request logging off, its own
Claude + Codex OAuth logins performed interactively by the user at Task 6,
z.ai wired as a Claude-compatible upstream. Accepted risks to state plainly:
(a) it runs its own OAuth grants rather than importing `~/.codex/auth.json`
(the user's reuse preference is satisfied in outcome — no API key, the same
ChatGPT subscription — but via a fresh sign-in through the proxy, and Codex
CLI keeps its separate login); (b) refresh contention is undocumented, so
Task 6 must verify `codex` still works after Codex-backend use, with
CCR (auth.json-reading) as the fallback if it breaks.

Alternatives if the user rejects this: CCR (best auth.json reuse, weakest
Anthropic refresh story), LiteLLM (most mature proxy, no credential reuse,
Python dependency), no-router (drop in-session switching or the Codex
backend — contradicts current design decisions).
