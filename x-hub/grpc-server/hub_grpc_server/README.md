# hub_grpc_server

This is the active Node-based gRPC service runtime for X-Hub.

It provides the service-side control surface behind pairing, grants, AI routing, web/runtime helpers, audit, memory, skills, and admin operations.

Current service families:
- gRPC services: Models / Grants / AI / Web / Events / Runtime / Audit / Memory / Skills / Admin
- storage: SQLite (via Node's built-in `node:sqlite`, synchronous + WAL)

Protocol contract:
- `protocol/hub_protocol_v1.md`
- `protocol/hub_protocol_v1.proto`

Repo path:
- `x-hub/grpc-server/hub_grpc_server/`

This README is implementation-facing. For repository entrypoints and product framing, start with:

- `README.md`
- `x-hub/README.md`
- `x-hub/grpc-server/README.md`

## Operator-Channel Boundary

Slack, Telegram, Feishu, WhatsApp Cloud, and similar adapters should be read as Hub ingress workers, not independent trust anchors.

That means:

- remote-channel events enter Hub governance first
- connector workers normalize ingress, enforce channel-side checks, and hand control to Hub-side authz, grants, audit, routing, and memory surfaces
- higher-trust confirmation or continuation can then be projected to paired surfaces such as X-Terminal voice rather than letting the remote channel own final grant authority

## Run (Hub machine)

1) Install deps (requires npm registry access):
```bash
npm install
```

2) Start server (recommended with tokens):
```bash
HUB_HOST=0.0.0.0 \
HUB_PORT=50051 \
HUB_CLIENT_TOKEN='replace-client-token' \
HUB_ADMIN_TOKEN='replace-admin-token' \
npm run start
```

Dedicated Slack operator ingress worker (local-only by default):
```bash
HUB_HOST=127.0.0.1 \
HUB_PORT=50051 \
HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN='replace-connector-token' \
HUB_SLACK_OPERATOR_ENABLE=1 \
HUB_SLACK_OPERATOR_SIGNING_SECRET='replace-slack-signing-secret' \
HUB_SLACK_OPERATOR_BOT_TOKEN='xoxb-...' \
npm run start-slack-operator
```

Dedicated Feishu operator ingress worker (local-only by default):
```bash
HUB_HOST=127.0.0.1 \
HUB_PORT=50051 \
HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN='replace-connector-token' \
HUB_FEISHU_OPERATOR_ENABLE=1 \
HUB_FEISHU_OPERATOR_VERIFICATION_TOKEN='replace-feishu-verification-token' \
HUB_FEISHU_OPERATOR_REPLY_ENABLE=1 \
HUB_FEISHU_OPERATOR_BOT_APP_ID='cli_xxx' \
HUB_FEISHU_OPERATOR_BOT_APP_SECRET='sec_xxx' \
npm run start-feishu-operator
```

Dedicated Telegram operator polling worker (outbound-only, no inbound webhook exposure):
```bash
HUB_HOST=127.0.0.1 \
HUB_PORT=50051 \
HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN='replace-connector-token' \
HUB_TELEGRAM_OPERATOR_ENABLE=1 \
HUB_TELEGRAM_OPERATOR_BOT_TOKEN='replace-telegram-bot-token' \
HUB_TELEGRAM_OPERATOR_ACCOUNT_ID='telegram_ops_bot' \
npm run start-telegram-operator
```

Dedicated WhatsApp Cloud operator ingress worker (local-only by default, intended behind a relay/domain rather than raw Hub IP exposure):
```bash
HUB_HOST=127.0.0.1 \
HUB_PORT=50051 \
HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN='replace-connector-token' \
HUB_WHATSAPP_CLOUD_OPERATOR_ENABLE=1 \
HUB_WHATSAPP_CLOUD_OPERATOR_VERIFY_TOKEN='replace-whatsapp-verify-token' \
HUB_WHATSAPP_CLOUD_OPERATOR_APP_SECRET='replace-whatsapp-app-secret' \
HUB_WHATSAPP_CLOUD_OPERATOR_REPLY_ENABLE=1 \
HUB_WHATSAPP_CLOUD_OPERATOR_ACCESS_TOKEN='replace-whatsapp-access-token' \
HUB_WHATSAPP_CLOUD_OPERATOR_PHONE_NUMBER_ID='replace-phone-number-id' \
HUB_WHATSAPP_CLOUD_OPERATOR_ACCOUNT_ID='ops_whatsapp_cloud' \
npm run start-whatsapp-cloud-operator
```

WhatsApp Cloud require-real scaffolding for `XT-W3-24-N`:
```bash
node scripts/xt_w3_24_n_whatsapp_cloud_require_real_status.js
node scripts/prepare_xt_w3_24_n_whatsapp_cloud_require_real_sample.js
```

If the capture bundle is missing, the status command now auto-bootstraps it.

Finalize one real sample after capture:
```bash
node scripts/finalize_xt_w3_24_n_whatsapp_cloud_require_real_sample.js \
  --scaffold-dir build/reports/xt_w3_24_n_whatsapp_cloud_require_real/xt_w3_24_n_rr_03_deploy_plan_routes_project_first_to_preferred_xt
```

Low-level updater is still available when you need to override the default finalize flow:
```bash
node scripts/update_xt_w3_24_n_whatsapp_cloud_require_real_capture_bundle.js \
  --scaffold-dir build/reports/xt_w3_24_n_whatsapp_cloud_require_real/xt_w3_24_n_rr_03_deploy_plan_routes_project_first_to_preferred_xt \
  --status passed \
  --success true \
  --note real_runtime_capture
node scripts/generate_xt_w3_24_n_whatsapp_cloud_require_real_report.js
```

Supported Slack operator text commands:
```text
status
blockers
queue
deploy plan   # governed XT prepare path; returns prepared when XT replies in-window, else queued
grant approve <grant_request_id>
grant approve <grant_request_id> note approved after release review
grant reject <grant_request_id> reason outside approved change window
```

Telegram operator supports the same governed text command surface, plus inline `grant approve` / `grant reject` buttons when the compact callback payload fits within Telegram limits. When it does not fit, the worker falls back to text instructions rather than truncating approval context.

WhatsApp Cloud operator currently stays text-only on purpose: high-risk actions still go through explicit commands such as `grant approve <grant_request_id>` and `grant reject <grant_request_id> reason <why>`. `whatsapp_personal_qr` remains a separate trusted-runner path and is not shipped through the Hub connector worker.

Export operator-channel live-test evidence for `XT-W3-24-S` after the first real Slack / Telegram / Feishu / WhatsApp Cloud onboarding run:
```bash
HUB_ADMIN_TOKEN='replace-admin-token' \
npm run generate-operator-live-test-evidence -- \
  --provider slack \
  --ticket-id ticket_live_1 \
  --verdict passed \
  --summary "first live onboarding reply succeeded" \
  --performed-at 2026-03-15T11:00:00Z \
  --evidence-ref build/reports/slack-first-live-thread.png
```

Notes:
- This script stays on the local admin surface. It only reads `GET /admin/operator-channels/readiness`, `GET /admin/operator-channels/runtime-status`, and optionally `GET /admin/operator-channels/onboarding/tickets/:ticket_id`.
- Default base URL is `http://127.0.0.1:<HUB_PAIRING_PORT or HUB_PORT+1>` and the default output path is `x-terminal/build/reports/xt_w3_24_s_<provider>_live_test_evidence.v1.json`.
- `derived_status=pass` means command entry, delivery readiness, quarantine ticket, approval, first smoke, and onboarding outbox drainage all passed in the captured snapshot.
- `whatsapp_cloud_api` can use this report for onboarding evidence, but it still does not replace the separate `XT-W3-24-N` require-real bundle.

## Connect from another computer (LAN)

On another computer (with this repo + deps), run:
```bash
HUB_HOST='<hub_lan_ip>' \
HUB_PORT=50051 \
HUB_CLIENT_TOKEN='replace-client-token' \
npm run list-models
```

If successful, Terminal prints `Hub connected: <ip>:50051` and model rows.

Skills search/import helper (client side):
```bash
HUB_HOST='<hub_lan_ip>' \
HUB_PORT=50051 \
HUB_CLIENT_TOKEN='replace-client-token' \
npm run skills -- search --query "find skills" --limit 20
```

Memory index rebuild (W3-04):
```bash
# Dry-run only (no write/swap)
npm run rebuild-index -- --db-path ./data/hub.sqlite3 --dry-run --json

# Full rebuild + atomic swap
npm run rebuild-index -- --db-path ./data/hub.sqlite3 --batch-size 500 --json
```

Memory reliability drills (W3-05):
```bash
# Restart / corruption / concurrent-write recovery drills
npm run drill-memory-index
```

## Paid AI queue stress test (6~10 projects)

One click (run from anywhere):
```bash
bash x-hub/grpc-server/hub_grpc_server/scripts/stress_paid_ai_queue.sh --projects 8
```

Local one-click (auto start Hub on `:50061` if not running, then run stress):
```bash
npm run stress-paid-local --prefix x-hub/grpc-server/hub_grpc_server -- --projects 8
```

Or run via npm in this folder:
```bash
npm run stress-paid -- --projects 8
```

Recommended 3-case benchmark matrix (baseline + 2 tuning cases):
```bash
npm run bench-paid-matrix --prefix x-hub/grpc-server/hub_grpc_server
```

If the last case reports `quota_exceeded`, increase `hub_quotas.json` (`devices.terminal_device.daily_token_cap`) or wait for the next UTC day.

The script will:
- auto-pick a paid model (or use `--model <model_id>`)
- auto-load a client token from `hub_grpc_clients.json` when `HUB_CLIENT_TOKEN` is not set (local Hub machine)
- fire concurrent `HubAI.Generate` requests across multiple `HUB_PROJECT_ID`s
- print queue statistics from `audit_events.ext_json.queue_wait_ms` (avg/p50/p90/max)

Extra report flags:
- `--json-out <path>`: persist full run result as JSON
- `--json`: print full run result as JSON to stdout
- `--label <name>`: mark scenario name in report JSON

Scheduler runtime snapshot (for dashboards/Supervisor):
- `<HUB_RUNTIME_BASE_DIR>/paid_ai_scheduler_status.json` (queue depth, in-flight by scope, oldest queued ms)
- `HubRuntime.GetSchedulerStatus` (remote-safe gRPC view for the same paid-AI scheduler state)

## TLS / mTLS (Phase 1)

The gRPC server now supports TLS and mutual TLS (mTLS).

Server env:
- `HUB_GRPC_TLS_MODE`: `insecure|tls|mtls` (default: `insecure`)
- `HUB_GRPC_TLS_SERVER_NAME`: stable DNS name used in the server cert CN/SAN (default: `axhub`)
- `HUB_GRPC_TLS_SERVER_SAN_IPS`: optional comma-separated IPs to include in the server cert SAN (e.g. `192.168.1.10,10.7.0.2`)
- `HUB_GRPC_TLS_DIR`: optional override for TLS material dir (default: `<runtime_base_dir>/hub_grpc_tls`)
- `HUB_GRPC_TLS_AUTO_GEN`: `1|0` (default: `1`) auto-generates CA + server cert on first run (requires `openssl`)
- `HUB_GRPC_MTLS_REQUIRE_CERT_PIN`: `1|0` (default: `1`) require `cert_sha256` pin for each token in mTLS mode

Client env (Node client kit):
- `HUB_GRPC_TLS_MODE`: `tls|mtls`
- `HUB_GRPC_TLS_SERVER_NAME`: should match the Hub server cert name (default: `axhub`)
- `HUB_GRPC_TLS_CA_CERT_PATH`: path to Hub CA cert PEM
- `HUB_GRPC_TLS_CLIENT_CERT_PATH` / `HUB_GRPC_TLS_CLIENT_KEY_PATH`: required for `mtls`

Allowlist (`hub_grpc_clients.json`) supports an extra optional field:
```json
{
  "device_id": "dev_abc123",
  "token": "axhub_client_...",
  "cert_sha256": "hex_sha256_of_client_cert_der",
  "enabled": true
}
```

Notes:
- Clients typically connect by IP, so the Node client kit uses `grpc.ssl_target_name_override` with `HUB_GRPC_TLS_SERVER_NAME` to satisfy hostname verification.
- The pairing control plane can be used to approve devices and issue mTLS client certs (Terminal generates a CSR; Hub signs it).

Full end-to-end smoke test from another computer:
```bash
HUB_HOST='<hub_lan_ip>' \
HUB_PORT=50051 \
HUB_CLIENT_TOKEN='replace-client-token' \
npm run smoke
```

## Environment variables

- `HUB_PORT` (default: `50051`)
- `HUB_HOST` (default: `0.0.0.0`)
- `HUB_DB_PATH` (default: `./data/hub.sqlite3`)
- `HUB_CLIENT_TOKEN` (legacy fallback; if set, clients must send `authorization: Bearer <token>`)
- `HUB_ADMIN_TOKEN` (if set, admin RPCs require `authorization: Bearer <token>`)
- `HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN` (required for operator-channel governance RPCs under `HubRuntime`; do not reuse `HUB_ADMIN_TOKEN`)
- `HUB_SLACK_OPERATOR_ENABLE` (default: `0`; starts the dedicated Slack operator ingress worker only when set to `1`)
- `HUB_SLACK_OPERATOR_HOST` (default: `127.0.0.1`; must remain loopback unless `HUB_SLACK_OPERATOR_ALLOW_REMOTE=1`)
- `HUB_SLACK_OPERATOR_PORT` (default: `50161`)
- `HUB_SLACK_OPERATOR_EVENT_PATH` (default: `/slack/events`)
- `HUB_SLACK_OPERATOR_HEALTH_PATH` (default: `/health`)
- `HUB_SLACK_OPERATOR_BODY_MAX_BYTES` (default: `262144`; bounded to `1024..1048576`)
- `HUB_SLACK_OPERATOR_SIGNING_SECRET` (required when `HUB_SLACK_OPERATOR_ENABLE=1`)
- `HUB_SLACK_OPERATOR_BOT_TOKEN` (optional for ingress-only mode; required when Slack reply delivery should post summaries/denials/routing receipts back into the thread)
- `HUB_SLACK_OPERATOR_REPLY_ENABLE` (default: `1`; when `0`, the worker still accepts ingress but does not attempt Slack reply delivery even if a bot token exists)
- `HUB_SLACK_OPERATOR_APP_ID` (default: `slack_operator_adapter`; connector principal app id for HubRuntime governance RPCs)
- `HUB_SLACK_OPERATOR_ALLOW_REMOTE` (default: `0`; set to `1` only when the worker is placed behind an explicit relay/tunnel boundary and raw Hub exposure is still avoided)
- `HUB_FEISHU_OPERATOR_ENABLE` (default: `0`; starts the dedicated Feishu operator ingress worker only when set to `1`)
- `HUB_FEISHU_OPERATOR_HOST` (default: `127.0.0.1`; must remain loopback unless `HUB_FEISHU_OPERATOR_ALLOW_REMOTE=1`)
- `HUB_FEISHU_OPERATOR_PORT` (default: `50162`)
- `HUB_FEISHU_OPERATOR_EVENT_PATH` (default: `/feishu/events`)
- `HUB_FEISHU_OPERATOR_HEALTH_PATH` (default: `/health`)
- `HUB_FEISHU_OPERATOR_BODY_MAX_BYTES` (default: `262144`; bounded to `1024..1048576`)
- `HUB_FEISHU_OPERATOR_VERIFICATION_TOKEN` (required when `HUB_FEISHU_OPERATOR_ENABLE=1`)
- `HUB_FEISHU_OPERATOR_REPLY_ENABLE` (default: `0`; when `1`, Feishu reply delivery requires bot credentials and posts governed summaries back to the originating thread anchor)
- `HUB_FEISHU_OPERATOR_BOT_APP_ID` / `HUB_FEISHU_OPERATOR_BOT_APP_SECRET` (required when `HUB_FEISHU_OPERATOR_REPLY_ENABLE=1`)
- `HUB_FEISHU_OPERATOR_APP_ID` (default: `feishu_operator_adapter`; connector principal app id for HubRuntime governance RPCs)
- `HUB_FEISHU_OPERATOR_API_BASE_URL` (default: `https://open.feishu.cn/open-apis`)
- `HUB_FEISHU_OPERATOR_ALLOW_REMOTE` (default: `0`; set to `1` only when the worker is placed behind an explicit relay/tunnel boundary and raw Hub exposure is still avoided)
- `HUB_TELEGRAM_OPERATOR_ENABLE` (default: `0`; starts the dedicated Telegram polling worker only when set to `1`)
- `HUB_TELEGRAM_OPERATOR_BOT_TOKEN` (required when `HUB_TELEGRAM_OPERATOR_ENABLE=1`)
- `HUB_TELEGRAM_OPERATOR_REPLY_ENABLE` (default: `1`; when `0`, the worker still polls and executes governed commands but does not send Telegram replies)
- `HUB_TELEGRAM_OPERATOR_POLL_ENABLE` (default: `1`; leave enabled for the outbound-only polling model)
- `HUB_TELEGRAM_OPERATOR_POLL_TIMEOUT_SEC` (default: `15`; bounded to `0..50`)
- `HUB_TELEGRAM_OPERATOR_POLL_IDLE_MS` (default: `400`; bounded to `100..30000`; also used as backoff when Telegram returns immediately or errors)
- `HUB_TELEGRAM_OPERATOR_ACCOUNT_ID` (default: `telegram_operator`; tenant/account id stamped into channel bindings and audit actor metadata)
- `HUB_TELEGRAM_OPERATOR_APP_ID` (default: `telegram_operator_adapter`; connector principal app id for HubRuntime governance RPCs)
- `HUB_TELEGRAM_OPERATOR_API_BASE_URL` (default: `https://api.telegram.org`)
- `HUB_WHATSAPP_CLOUD_OPERATOR_ENABLE` (default: `0`; starts the dedicated WhatsApp Cloud operator ingress worker only when set to `1`)
- `HUB_WHATSAPP_CLOUD_OPERATOR_HOST` (default: `127.0.0.1`; must remain loopback unless `HUB_WHATSAPP_CLOUD_OPERATOR_ALLOW_REMOTE=1`)
- `HUB_WHATSAPP_CLOUD_OPERATOR_PORT` (default: `50163`)
- `HUB_WHATSAPP_CLOUD_OPERATOR_EVENT_PATH` (default: `/whatsapp/events`)
- `HUB_WHATSAPP_CLOUD_OPERATOR_HEALTH_PATH` (default: `/health`)
- `HUB_WHATSAPP_CLOUD_OPERATOR_BODY_MAX_BYTES` (default: `262144`; bounded to `1024..1048576`)
- `HUB_WHATSAPP_CLOUD_OPERATOR_VERIFY_TOKEN` (required when `HUB_WHATSAPP_CLOUD_OPERATOR_ENABLE=1`; used for Meta webhook verification challenge)
- `HUB_WHATSAPP_CLOUD_OPERATOR_APP_SECRET` (required when `HUB_WHATSAPP_CLOUD_OPERATOR_ENABLE=1`; used to verify `X-Hub-Signature-256` on incoming webhooks)
- `HUB_WHATSAPP_CLOUD_OPERATOR_REPLY_ENABLE` (default: `0`; when `1`, outbound governed summaries/pending approvals require Cloud API credentials)
- `HUB_WHATSAPP_CLOUD_OPERATOR_ACCESS_TOKEN` / `HUB_WHATSAPP_CLOUD_OPERATOR_PHONE_NUMBER_ID` (required when `HUB_WHATSAPP_CLOUD_OPERATOR_REPLY_ENABLE=1`)
- `HUB_WHATSAPP_CLOUD_OPERATOR_ACCOUNT_ID` (default: `HUB_WHATSAPP_CLOUD_OPERATOR_PHONE_NUMBER_ID` or `whatsapp_cloud_operator`; account id stamped into channel bindings and audit actor metadata)
- `HUB_WHATSAPP_CLOUD_OPERATOR_APP_ID` (default: `whatsapp_cloud_operator_adapter`; connector principal app id for HubRuntime governance RPCs)
- `HUB_WHATSAPP_CLOUD_OPERATOR_API_BASE_URL` (default: `https://graph.facebook.com`)
- `HUB_WHATSAPP_CLOUD_OPERATOR_API_VERSION` (default: `v23.0`)
- `HUB_WHATSAPP_CLOUD_OPERATOR_ALLOW_REMOTE` (default: `0`; set to `1` only when the worker is placed behind an explicit relay/tunnel boundary and raw Hub exposure is still avoided)
- `HUB_ALLOWED_CIDRS` (optional; comma-separated allowlist like `private,127.0.0.1,192.168.1.0/24`)
- `HUB_ADMIN_ALLOW_REMOTE` (default: `0`; set to `1` to allow admin RPCs from non-loopback peers)
- `HUB_ADMIN_ALLOWED_CIDRS` (optional; comma-separated allowlist for admin RPCs when `HUB_ADMIN_ALLOW_REMOTE=0`)
- `HUB_OPERATOR_CHANNEL_CONNECTOR_ALLOW_REMOTE` (default: `0`; set to `1` only when the connector is behind an explicit relay/tunnel boundary)
- `HUB_OPERATOR_CHANNEL_CONNECTOR_ALLOWED_CIDRS` (optional; comma-separated allowlist for operator-channel connector RPCs when remote access must be enabled narrowly)
- `HUB_AUTO_APPROVE_TTL_SEC` (default: `1800`)
- `HUB_AUTO_APPROVE_TOKEN_CAP` (default: `5000`)
- `HUB_RUNTIME_BASE_DIR` (optional override for runtime/bridge shared base dir)
- `HUB_AI_AUTO_LOAD` (default: `1`; auto-load local models in the MLX runtime)
- `HUB_MLX_RESPONSE_TIMEOUT_MS` (default: `180000`; wait for runtime response when runtime is alive)
- `HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS` (default: `8000`; fail fast when runtime seems down)
- `HUB_GRPC_TLS_MODE` (default: `insecure`; set to `tls` or `mtls` for encrypted transport)
- `HUB_GRPC_TLS_DIR` (optional; defaults to `<runtime_base_dir>/hub_grpc_tls`)
- `HUB_GRPC_TLS_AUTO_GEN` (default: `1`; auto-generate CA/server certs with `openssl`)
- `HUB_GRPC_TLS_SERVER_NAME` (default: `axhub`)
- `HUB_GRPC_TLS_SERVER_SAN_IPS` (optional; comma-separated)
- `HUB_GRPC_MTLS_REQUIRE_CERT_PIN` (default: `1`; require `cert_sha256` pin per device token)
- `HUB_GRPC_MAX_MESSAGE_MB` (default: `32`; gRPC max request/response size, applies to server + Node client kit)
- `HUB_SKILLS_MAX_PACKAGE_MB` (default: same as `HUB_GRPC_MAX_MESSAGE_MB`; max upload size for `UploadSkillPackage`)
- `HUB_SKILLS_DOWNLOAD_CHUNK_BYTES` (default: `262144`; streaming chunk size for `DownloadSkillPackage`)
- `HUB_SKILLS_DEVELOPER_MODE` (default: `0`; only low-risk unsigned/untrusted skills can bypass signer trust when set to `1`; high-risk skills stay fail-closed)
- `HUB_REQUIRE_SKILLS_CAP` (default: `0`; when `1`, clients must explicitly include `skills` in `capabilities`)

When `HUB_RUNTIME_BASE_DIR` is not set, the server now auto-detects the most active base directory across the current compatibility runtime locations:
- `~/Library/Containers/com.rel.flowhub/Data/XHub`
- `~/Library/Containers/com.rel.flowhub/Data/RELFlowHub`
- `/private/tmp/XHub`
- `/private/tmp/RELFlowHub`
- `~/Library/Group Containers/group.rel.flowhub`
- `~/XHub`
- `~/RELFlowHub`

## Auth (v1: per-device client allowlist)

Create `hub_grpc_clients.json` under the runtime base dir (same dir that contains `models_state.json`):
```json
{
  "schema_version": "hub_grpc_clients.v1",
  "clients": [
    {
      "device_id": "terminal_device",
      "user_id": "user_123",
      "name": "My Laptop",
      "token": "axhub_client_...",
      "enabled": true,
      "capabilities": ["models", "events", "memory", "skills", "ai.generate.local", "ai.generate.paid", "web.fetch"],
      "allowed_cidrs": ["private", "127.0.0.1"]
    }
  ]
}
```

Notes:
- When this file contains at least one client, **only** those tokens are accepted.
- The `device_id` from this file becomes the *authenticated* identity used for quotas/audit/policy.
- Client-provided `ClientIdentity.device_id` is treated as untrusted input and is overridden.
- `capabilities` is optional. If present and non-empty, Hub denies RPCs outside this allowlist.
- `allowed_cidrs` is optional. If present and non-empty, Hub rejects connections whose peer IP is outside the allowlist.
- `cert_sha256` is optional. In `mtls` mode, when `HUB_GRPC_MTLS_REQUIRE_CERT_PIN=1`, Hub requires the presented client cert sha256 to match this value.

## Quotas (MVP: per-device daily tokens)

Create `hub_quotas.json` under the runtime base dir (same dir that contains `models_state.json`), for example:
```json
{
  "default_daily_token_cap": 0,
  "devices": {
    "terminal_device": { "daily_token_cap": 50000 }
  }
}
```

Notes:
- Scope is currently `device_id`. With `hub_grpc_clients.json` enabled, this becomes the authenticated device id.
- Quotas are enforced on `HubAI.Generate` and stored in SQLite (`quota_usage_daily`).

## Notes

- HubAI.Generate is backed by the existing MLX runtime file IPC (`python_service/relflowhub_mlx_runtime.py`).
- `web_fetch` is executed via the Hub's embedded bridge file IPC (`bridge_requests/` -> `bridge_responses/`). Historical internal naming may still use `RELFlowHubBridge` in some implementation surfaces.
- All decisions and executions emit `audit.v1` events into SQLite.
- The Slack operator worker is a separate process and stays loopback-only by default; it should sit behind a relay/tunnel instead of exposing the raw Hub IP directly.
- Without `HUB_SLACK_OPERATOR_BOT_TOKEN`, the Slack operator worker still processes governed ingress but only returns HTTP webhook acknowledgements; thread replies stay disabled.
- The Feishu operator worker follows the same Hub-first, loopback-only ingress model as Slack; keep it behind a relay/tunnel rather than exposing raw Hub endpoints.
- The Telegram operator worker is polling-only by design. It does not open an inbound HTTP listener and should be run on the Hub machine or another outbound-only connector host that can reach Hub over the local connector channel.
- The WhatsApp Cloud operator worker verifies the Meta webhook challenge token and `X-Hub-Signature-256` before any command normalization. Keep it behind a domain/relay boundary and do not treat it as approval to expose the raw Hub IP.
- `build/reports/xt_w3_24_n_action_grant_whatsapp_evidence.v1.json` is the fail-closed `XT-W3-24-N` require-real report for WhatsApp Cloud. It stays `NO_GO` until the capture bundle is backed by real Meta/Hub/XT samples.
- `whatsapp_cloud_api` remains `p1 / release_blocked` in the channel runtime snapshot until require-real evidence is collected. `whatsapp_personal_qr` stays a separate trusted-automation track and is not part of this Hub connector worker.
- `HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN` is intentionally narrower than `HUB_ADMIN_TOKEN`; do not reuse the admin token for Slack / Feishu / Telegram operator workers.

## Pairing (MVP)

This repo now includes a minimal HTTP pairing control plane (Option B in `protocol/hub_protocol_v1.md`):

- Terminal device "knocks" (unauthenticated) -> Hub records a pending request.
- Hub operator approves/denies locally (Hub UI or local admin call).
- Terminal device polls -> receives a per-device `HUB_CLIENT_TOKEN` once approved.

Defaults:
- Pairing server listens on `HUB_PAIRING_PORT` (default: `HUB_PORT + 1`, e.g. `50052`).
- Pairing server only accepts `private,loopback` source IPs by default (override with `HUB_PAIRING_ALLOWED_CIDRS`).
- Admin endpoints are local-only by default and require `HUB_ADMIN_TOKEN`.
- Operator-channel governance RPCs are also local-only by default, but require a separate `HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN` instead of the admin token.

Bootstrap install (new machine, LAN):
```bash
HUB_HOST='<hub_lan_ip>'
PAIRING_PORT=50052

# Download axhubctl (single-file shell tool) from the Hub pairing server.
curl -fsSL "http://${HUB_HOST}:${PAIRING_PORT}/install/axhubctl" -o /tmp/axhubctl
curl -fsSL "http://${HUB_HOST}:${PAIRING_PORT}/install/axhubctl.sha256" -o /tmp/axhubctl.sha256
# Verify sha256 (note the file name in the .sha256 manifest is "axhubctl").
AXHUBCTL_SHA256="$(awk '{print $1}' /tmp/axhubctl.sha256)"
echo "${AXHUBCTL_SHA256}  /tmp/axhubctl" | shasum -a 256 -c -
chmod +x /tmp/axhubctl

# (Optional) Install to ~/.local/bin (no sudo):
mkdir -p ~/.local/bin
mv /tmp/axhubctl ~/.local/bin/axhubctl
chmod +x ~/.local/bin/axhubctl
```

One-shot bootstrap (discover + pair + wait + download client kit):
```bash
axhubctl bootstrap --hub auto --pairing-port "$PAIRING_PORT" \
  --device-name "Frank-Mac" \
  --requested-scopes "models,events,memory,ai.generate.local,web.fetch"
```

Discovery only (saves host hint to `~/.axhub/pairing.env`):
```bash
axhubctl discover --pairing-port "$PAIRING_PORT"
```

Download client kit only (after approval):
```bash
axhubctl install-client --hub "$HUB_HOST" --pairing-port "$PAIRING_PORT"
axhubctl list-models
```

Auto reconnect loop (with exponential backoff):
```bash
axhubctl connect --hub auto --auto-reconnect --max-backoff-sec 30
```

Example (Terminal device, LAN):
```bash
PAIRING_SECRET="$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')"

curl -sS -X POST "http://<hub_lan_ip>:50052/pairing/requests" \
  -H 'Content-Type: application/json' \
  -d "{\"app_id\":\"ax_terminal\",\"device_name\":\"Frank-Mac\",\"pairing_secret\":\"$PAIRING_SECRET\"}" | jq

# Poll for approval:
curl -sS "http://<hub_lan_ip>:50052/pairing/requests/<pairing_request_id>" \
  -H "X-Pairing-Secret: $PAIRING_SECRET" | jq
```
