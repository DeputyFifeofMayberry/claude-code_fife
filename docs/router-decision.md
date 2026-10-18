# Router Decision — claude-fife Task 2 Gate

Date: 2026-10-18
User decision (verbatim choice at gate): **CLIProxyAPI (Recommended)**
Evidence: `docs/router-evaluation.md` (researched + spiked on this machine).

## Router Contract (consumed by Tasks 4–6)

- **Router**: CLIProxyAPI **v8.0.33** windows_amd64 (`cli-proxy-api.exe`,
  pinned alongside the engine pin; re-pin only with the engine re-pin
  procedure).
- **Location**: exe at `C:\Users\barne\claude-fife\router\cli-proxy-api.exe`,
  config at `C:\Users\barne\claude-fife\router\config.yaml`, OAuth auth files
  in `C:\Users\barne\claude-fife\router\auth\` (fife tree only; never in git).
- **Listen**: `host: 127.0.0.1`, `port: 8317` — mandatory; the upstream
  default binds all interfaces and must never ship in our config.
- **Logging**: `request-log: false`, `debug: false`; no prompt/response
  content in any log.
- **Engine wiring** (set by the launcher, process-scope only):
  `ANTHROPIC_BASE_URL=http://127.0.0.1:8317`,
  `ANTHROPIC_AUTH_TOKEN` = router-local API key generated at setup and stored
  only in the fife tree, `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1`.
- **Model naming**: client-visible model IDs served by the router's
  `/v1/models` (gateway discovery), with `oauth.model-alias` used where a
  friendlier roster name is needed. Exact roster (Anthropic default, GLM,
  Codex entries) is fixed in Task 6 from the live `/v1/models` output after
  logins exist.
- **Lifecycle**: the `claude-fife` launcher health-checks
  `GET http://127.0.0.1:8317/v1/models` with the router-local key; if
  unhealthy it starts the exe with `--config <fife router config>` hidden and
  waits for health. The launcher does not kill the router on exit (shared
  across fife sessions); stopping is a documented manual action.
- **Auth strategy**: CLIProxyAPI's own OAuth logins, performed interactively
  by the user in Task 6 (`--claude-login` for the Claude subscription,
  Codex sign-in for the ChatGPT subscription). No API keys for Anthropic or
  OpenAI. z.ai uses the API key provisioned from the OpenCode config,
  wired as a Claude-compatible upstream
  (`base-url: https://api.z.ai/api/anthropic`).
- **Contention rule**: after Codex-backend use, Task 6 verifies the `codex`
  CLI still works. If the router's refresh behavior breaks Codex CLI, stop
  and return to the user with CCR (auth.json-reading) as the fallback —
  do not silently re-login or rotate the user's Codex grant.
