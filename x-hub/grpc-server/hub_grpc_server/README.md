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
- `HUB_ALLOWED_CIDRS` (optional; comma-separated allowlist like `private,127.0.0.1,192.168.1.0/24`)
- `HUB_ADMIN_ALLOW_REMOTE` (default: `0`; set to `1` to allow admin RPCs from non-loopback peers)
- `HUB_ADMIN_ALLOWED_CIDRS` (optional; comma-separated allowlist for admin RPCs when `HUB_ADMIN_ALLOW_REMOTE=0`)
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

When `HUB_RUNTIME_BASE_DIR` is not set, server now auto-detects the most active base directory among:
- `~/Library/Containers/com.rel.flowhub/Data/RELFlowHub`
- `/private/tmp/RELFlowHub`
- `~/Library/Group Containers/group.rel.flowhub`
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
- `web_fetch` is executed via **RELFlowHubBridge** file IPC (`bridge_requests/` -> `bridge_responses/`) so the core Hub process stays offline.
- All decisions and executions emit `audit.v1` events into SQLite.

## Pairing (MVP)

This repo now includes a minimal HTTP pairing control plane (Option B in `protocol/hub_protocol_v1.md`):

- Terminal device "knocks" (unauthenticated) -> Hub records a pending request.
- Hub operator approves/denies locally (Hub UI or local admin call).
- Terminal device polls -> receives a per-device `HUB_CLIENT_TOKEN` once approved.

Defaults:
- Pairing server listens on `HUB_PAIRING_PORT` (default: `HUB_PORT + 1`, e.g. `50052`).
- Pairing server only accepts `private,loopback` source IPs by default (override with `HUB_PAIRING_ALLOWED_CIDRS`).
- Admin endpoints are local-only by default and require `HUB_ADMIN_TOKEN`.

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
