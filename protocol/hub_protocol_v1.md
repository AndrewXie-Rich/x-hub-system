# AX Hub Remote Protocol (Draft v1)

Status: draft (2026-02-08)

This document defines the network protocol contract for running **Hub as an independent always-on device**
(LAN or Internet) that provides:
- model capability center (local/offline + paid/online)
- network proxy (`web_fetch`, `remote_model_call`) with approval + auditing
- centralized permission control + monitoring + emergency kill-switch
- centralized memory (future phase; included as reserved API)

Terminal Apps (AX Coder / Windows / Mobile / etc) are treated as untrusted inputs:
- they do **not** hold paid model API keys
- they do **not** directly access the public Internet for AI/network tools inside the AX ecosystem
- all approvals, quotas, auditing, and memory live in Hub

---

## 0) Normative Language
- **MUST** / **SHOULD** / **MAY** are used as in RFC 2119.

## 0.1) Timestamp Convention
- All timestamps are Unix epoch **milliseconds**.
- JSON fields MUST use `*_ms` (integer) where timestamps appear.
- gRPC fields use `int64 *_ms` as in `protocol/hub_protocol_v1.proto`.

## 1) Core Requirements Recap (aligned)
- Hub is always connected to the Internet (device-level connectivity).
- **Local/offline models** are executed on Hub and MUST be forced offline at the execution boundary (network isolation).
- **Paid/online models** are executed via Hub as a proxy to 3rd party providers and MUST be permission-gated + audited.
- “No bypass” is defined only within the AX ecosystem (cannot stop users using other apps outside AX).
- Network capability is **A only**: Hub proxy (`web_fetch` / `remote_model_call`); no “grant client full Internet”.

---

## 2) Transports

Hub supports three transports; implementations MAY choose one data plane initially but MUST keep message schemas stable.

### 2.1 HTTP/JSON (Control plane + simple data plane)
- Base URL: `https://<hub-host>/api/v1`
- JSON encoding: UTF-8, `snake_case` keys preferred.
- Streaming (optional): SSE or JSONL over chunked HTTP.

### 2.2 gRPC (Recommended for streaming AI)
- gRPC endpoint: `https://<hub-host>:443` (TLS)
- Proto: `protocol/hub_protocol_v1.proto`

### 2.3 WebSocket (Push events + optional RPC)
- WebSocket URL: `wss://<hub-host>/api/v1/ws`
- Primary purpose: Hub -> client push (models list updates, approvals/revocations, quotas, kill-switch, request status).

### 2.4 HTTP conventions (recommended)
- Content type: `Content-Type: application/json`
- Idempotency: all POST requests SHOULD include `request_id` (UUID). Hub SHOULD de-dup by `(device_id, request_id)` for a retention window (e.g. 24h).
- Success response SHOULD include `request_id` when provided by the client.
- Error response (canonical JSON shape):
```json
{
  "ok": false,
  "error": { "code": "string", "message": "string", "retryable": false }
}
```
- Status codes (guidance):
  - `200/201/202`: ok / created / accepted
  - `400`: invalid request / schema mismatch
  - `401`: unauthenticated
  - `403`: authenticated but forbidden (e.g. `grant_required`)
  - `409`: kill-switch active or conflicting state
  - `429`: quota/rate limit exceeded
  - `500`: internal error (retryable depends on code)

---

## 3) Identity Model (Client / Actor / Context)

Every client call MUST carry an identity/context tuple:
- `device_id`: stable UUID per physical device (or per OS install)
- `user_id`: stable ID for family member / employee account (may be empty in early MVP)
- `app_id`: identifier of the Terminal App (e.g. `ax_coder_mac`, `ax_coder_ios`)
- `project_id`: optional; a stable project identifier in the Terminal App
- `session_id`: optional; current interactive session

Hub MUST use (`device_id`,`user_id`,`app_id`,`project_id`) for:
- policy evaluation
- auditing & aggregation
- grants & quotas

---

## 4) Auth & Pairing

### 4.1 Access model
- All authenticated requests use: `Authorization: Bearer <access_token>`
- Access tokens SHOULD be short-lived (e.g. 15m–2h).
- Refresh tokens (or device certs) SHOULD be used for long-lived sessions.

### 4.2 Pairing flows (two options)

#### Option A (Recommended): Admin-generated enrollment code
1) Admin generates an `enrollment_code` in Hub UI (out-of-band).
2) Terminal App calls `POST /pairing/enroll` with the code + device identity.
3) Hub issues device credentials (refresh token or device cert).

#### Option B: Device requests access, admin approves
1) Terminal App calls `POST /pairing/requests` with identity.
2) Hub records a pending pairing request.
3) Admin approves/denies in Hub UI.
4) Terminal App polls or receives WS event with approval and obtains credentials.

### 4.3 HTTP endpoints (Auth)

#### POST `/pairing/requests` (unauthenticated; rate-limited)
Request:
```json
{
  "device_id": "uuid",
  "user_id": "optional",
  "app_id": "ax_coder_mac",
  "device_info": { "os": "macOS", "os_version": "15.2", "app_version": "1.0" },
  "requested_scopes": ["models.read", "ai.generate", "web.fetch", "events.ws"],
  "created_at_ms": 1730000000000
}
```
Response:
```json
{
  "pairing_request_id": "uuid",
  "status": "pending",
  "created_at_ms": 1730000000000
}
```

#### POST `/pairing/enroll` (unauthenticated; enrollment code required)
Request:
```json
{
  "enrollment_code": "ABCD-EFGH",
  "device_id": "uuid",
  "user_id": "optional",
  "app_id": "ax_coder_mac",
  "device_info": { "os": "macOS", "os_version": "15.2", "app_version": "1.0" }
}
```
Response:
```json
{
  "device_id": "uuid",
  "access_token": "...",
  "expires_in_sec": 3600,
  "refresh_token": "...",
  "token_type": "bearer"
}
```

#### POST `/auth/refresh` (refresh -> access)
Request:
```json
{ "refresh_token": "..." }
```
Response:
```json
{ "access_token": "...", "expires_in_sec": 3600, "token_type": "bearer" }
```

### 4.4 Admin endpoints (Pairing)
- `GET /admin/pairing/requests?status=pending`
- `POST /admin/pairing/requests/{id}/approve`
- `POST /admin/pairing/requests/{id}/deny`
- `POST /admin/devices/{device_id}/revoke`

All admin endpoints MUST require an admin credential.

---

## 5) Models (Catalog + Visibility + Push)

Hub MUST maintain a global models catalog and push a per-client filtered view.

### 5.1 Model fields (minimum)
- `model_id`, `name`
- `kind`: `local_offline` | `paid_online`
- `backend`: `mlx` | `openai` | `anthropic` | `gemini` | `openai_compatible` | ...
- `context_length`
- `visibility`: `available` | `requestable` | `denied` (as seen by this client)
- `requires_grant`: boolean (true for paid models unless policy says otherwise)

### 5.2 HTTP endpoints

#### GET `/models`
Response:
```json
{
  "updated_at_ms": 1730000000000,
  "models": [
    {
      "model_id": "mlx/qwen2.5-7b-instruct",
      "name": "Qwen2.5 7B (Local)",
      "kind": "local_offline",
      "backend": "mlx",
      "context_length": 8192,
      "visibility": "available",
      "requires_grant": false
    },
    {
      "model_id": "openai/gpt-4.1",
      "name": "GPT-4.1",
      "kind": "paid_online",
      "backend": "openai",
      "context_length": 128000,
      "visibility": "requestable",
      "requires_grant": true
    }
  ]
}
```

### 5.3 WebSocket push
Hub SHOULD push `models.updated` when:
- catalog changes (add/remove/enable/disable)
- policy changes affecting visibility

Payload MAY be either full list or `updated_at_ms` + `etag` (client refetches via HTTP).

---

## 6) Permission & Grants (Paid models / Web fetch)

### 6.1 Concepts
- **Grant request**: client asks to use a capability (paid model / web fetch) with proposed limits.
- **Grant**: Hub-issued temporary authorization with TTL + quota caps; revocable.

Local/offline models default to `allow` for authenticated clients (no manual approval),
but all calls MUST still be routed through Hub for monitoring, quotas, and kill-switch.

### 6.2 Capabilities
- `ai.generate.local` (default allow; still audited)
- `ai.generate.paid` (requires grant unless policy auto-approves)
- `web.fetch` (requires grant unless policy auto-approves)

### 6.3 HTTP endpoints (client)

#### POST `/grant_requests`
Request:
```json
{
  "request_id": "uuid (client generated for idempotency)",
  "device_id": "uuid",
  "user_id": "optional",
  "app_id": "ax_coder_mac",
  "project_id": "optional",
  "capability": "ai.generate.paid",
  "model_id": "openai/gpt-4.1",
  "reason": "Need latest API docs for a work task",
  "requested_ttl_sec": 1800,
  "requested_token_cap": 20000,
  "created_at_ms": 1730000000000
}
```
Response (decision is immediate when auto-approved; otherwise queued):
```json
{
  "grant_request_id": "uuid",
  "decision": "queued|approved|denied",
  "grant": {
    "grant_id": "uuid",
    "capability": "ai.generate.paid",
    "model_id": "openai/gpt-4.1",
    "token_cap": 20000,
    "token_used": 0,
    "expires_at_ms": 1730001800000
  },
  "deny_reason": "string (only when denied)"
}
```

#### GET `/grants?device_id=...&status=active`
Response:
```json
{
  "updated_at_ms": 1730000000000,
  "grants": [
    {
      "grant_id": "uuid",
      "capability": "web.fetch",
      "token_cap": 0,
      "token_used": 0,
      "expires_at_ms": 1730001800000,
      "status": "active"
    }
  ]
}
```

### 6.4 HTTP endpoints (admin)
- `GET /admin/grant_requests?status=pending`
- `POST /admin/grant_requests/{id}/approve` (admin MAY downscope TTL/quota)
- `POST /admin/grant_requests/{id}/deny`
- `POST /admin/grants/{id}/revoke`

### 6.5 WebSocket push
Hub MUST push grant decisions to the requesting device:
- `grant.approved`
- `grant.denied`
- `grant.revoked`

### 6.6 Kill Switch (Emergency)
Hub MUST support an emergency kill-switch that overrides grants/quotas:
- `models_disabled=true` MUST reject all `ai.generate.*` (local + paid).
- `network_disabled=true` MUST reject `web.fetch` and paid/online model calls.

Scope (string):
- `device:<device_id>` (recommended)
- `user:<user_id>`
- `project:<project_id>`
- `global:*`

gRPC (draft v1):
- `HubAdmin.SetKillSwitch` / `HubAdmin.GetKillSwitch` (see proto).
- `HubRuntime.GetSchedulerStatus` (paid AI queue/in-flight snapshot for Supervisor dashboards).
- `HubRuntime.GetConnectorIngressReceipts` (recent connector/webhook ingress receipts for XT-side governed automation binding).

Push:
- Hub SHOULD push `kill_switch_updated` over WebSocket/gRPC events so clients can update UI immediately.

---

## 7) AI Generate (Hub as the only model provider)

### 7.1 Request fields (minimum)
- `request_id` (client-generated, idempotency + correlation)
- identity: `device_id`,`user_id`,`app_id`,`project_id`
- `model_id`
- `messages` (OpenAI-style): `[{role, content}]`
- sampling: `max_tokens`, `temperature`, `top_p`
- optional (recommended for token efficiency): `thread_id` (+ `working_set_limit`) to let Hub assemble context from Hub Memory
- optional: `fail_closed_on_downgrade=true` to force deny instead of local downgrade when remote export/policy blocks a paid route

### 7.2 HTTP (non-streaming)
#### POST `/ai/generate`
Request:
```json
{
  "request_id": "uuid",
  "device_id": "uuid",
  "user_id": "optional",
  "app_id": "ax_coder_mac",
  "project_id": "optional",
  "thread_id": "optional (Hub memory thread)",
  "fail_closed_on_downgrade": true,
  "model_id": "mlx/qwen2.5-7b-instruct",
  "messages": [
    {"role":"system","content":"..."},
    {"role":"user","content":"Write a function that ..."}
  ],
  "max_tokens": 768,
  "temperature": 0.2,
  "top_p": 0.95
}
```
Response:
```json
{
  "request_id": "uuid",
  "ok": true,
  "model_id": "mlx/qwen2.5-7b-instruct",
  "text": "final text",
  "usage": { "prompt_tokens": 123, "completion_tokens": 456, "total_tokens": 579 },
  "created_at_ms": 1730000000000,
  "finished_at_ms": 1730000001200
}
```

Errors:
- `403 grant_required` (paid model without active grant)
- `429 quota_exceeded`
- `409 kill_switch_active`

### 7.3 gRPC (streaming; recommended)
See `HubAI.Generate` in `protocol/hub_protocol_v1.proto`.

---

## 8) Web Fetch (Hub proxy only)

### 8.1 Constraints (recommended defaults)
- Hub SHOULD only allow HTTPS by default.
- Hub SHOULD cap response bytes (e.g. 1–5 MB) and timeouts.
- Hub SHOULD record destination host and status code in audit logs.

### 8.2 HTTP (non-streaming)
#### POST `/web/fetch`
Request:
```json
{
  "request_id": "uuid",
  "device_id": "uuid",
  "app_id": "ax_coder_mac",
  "project_id": "optional",
  "url": "https://example.com/docs",
  "method": "GET",
  "timeout_sec": 12,
  "max_bytes": 1000000
}
```
Response:
```json
{
  "request_id": "uuid",
  "ok": true,
  "status": 200,
  "final_url": "https://example.com/docs",
  "content_type": "text/html; charset=utf-8",
  "truncated": false,
  "bytes": 34567,
  "text": "<html>...</html>",
  "finished_at_ms": 1730000001200
}
```

### 8.3 gRPC (streaming; optional)
See `HubWeb.Fetch` in `protocol/hub_protocol_v1.proto`.

---

## 9) Emergency Control (Kill-switch + Quotas)

Hub MUST allow an admin to immediately:
- disable all model use for a device/user/project
- disable all network proxy for a device/user/project
- set token budgets (daily/weekly) and rate limits
- terminate in-flight requests

### 9.1 Admin HTTP endpoints
- `POST /admin/killswitch/set`
- `POST /admin/quotas/set`
- `POST /admin/requests/{request_id}/terminate`

### 9.2 WebSocket push
Clients MUST receive:
- `killswitch.updated`
- `quota.updated`
- `request.terminated`

Clients MUST stop in-flight work on receiving these events.

---

## 10) WebSocket Event Contract (Push)

### 10.1 Connection
- URL: `wss://<hub-host>/api/v1/ws`
- Auth: bearer token (preferred via header; query param is discouraged)

### 10.2 Message envelope
All messages are JSON objects:
```json
{
  "type": "client_hello|server_hello|event|heartbeat|error",
  "id": "uuid (optional)",
  "created_at_ms": 1730000000000,
  "payload": {}
}
```

Client hello:
```json
{
  "type": "client_hello",
  "created_at_ms": 1730000000000,
  "payload": {
    "device_id": "uuid",
    "user_id": "optional",
    "app_id": "ax_coder_mac",
    "scopes": ["models", "grants", "quota", "killswitch", "requests"],
    "last_event_id": "optional (resume)"
  }
}
```

Server hello:
```json
{
  "type": "server_hello",
  "created_at_ms": 1730000000100,
  "payload": {
    "hub_id": "uuid",
    "protocol": "hub.ws.v1",
    "server_time_ms": 1730000000100,
    "heartbeat_interval_sec": 20
  }
}
```

### 10.3 Event types (minimum)
- `models.updated`
- `grant.approved` / `grant.denied` / `grant.revoked`
- `quota.updated`
- `killswitch.updated`
- `request.status` (running/done/failed/canceled/terminated)

Example event:
```json
{
  "type": "event",
  "id": "evt_...",
  "created_at_ms": 1730000001000,
  "payload": {
    "event_type": "grant.approved",
    "device_id": "uuid",
    "grant": { "grant_id":"...", "capability":"ai.generate.paid", "expires_at_ms": 1730001800000 }
  }
}
```

---

## 11) Audit Events (schema + storage)

Hub MUST write an append-only audit log for every permission decision and every model/network execution.

- Canonical JSON Schema: `protocol/audit_event_v1.schema.json`
- Recommended storage (MVP): SQLite (indexed) or JSONL (`audit_events_YYYYMMDD.jsonl`) + periodic aggregates.

Example audit event:
```json
{
  "schema_version": "audit.v1",
  "event_id": "uuid",
  "event_type": "ai.generate.completed",
  "created_at_ms": 1730000001200,
  "actor": {
    "device_id": "uuid",
    "user_id": "dad",
    "app_id": "ax_coder_mac",
    "project_id": "proj_123"
  },
  "request": {
    "request_id": "req_...",
    "capability": "ai.generate.local",
    "model_id": "mlx/qwen2.5-7b-instruct"
  },
  "usage": { "prompt_tokens": 123, "completion_tokens": 456, "total_tokens": 579 },
  "network": { "allowed": false },
  "outcome": { "ok": true, "duration_ms": 850 }
}
```

---

## 12) Memory (Threads + Working Set + Canonical) (Phase-2, but schema is reserved now)

Goal: Hub owns durable memory. Clients keep only a short local context window and sync each turn to Hub.
Hub then assembles a token-efficient prompt via:
1) Canonical Memory (small + pinned)
2) Working Set (recent N turns)
3) Retrieval hits (observations index; reserved)

### 12.1 gRPC
See `service HubMemory` in `protocol/hub_protocol_v1.proto`:
- `GetOrCreateThread` (device/app/project scoped thread)
- `AppendTurns` (sync turns; supports dropping/redacting `<private>...</private>`)
- `GetWorkingSet` (fetch last N turns)
- `UpsertCanonicalMemory` / `ListCanonicalMemory` (small, pinned memory)
- `UpsertProjectLineage` / `GetProjectLineageTree` (parent-child lineage source-of-truth + lineage tree query)
- `AttachDispatchContext` (bind per-project dispatch context: agent profile / lane / budget / priority / expected artifacts)
- `RegisterAgentCapsule` / `VerifyAgentCapsule` / `ActivateAgentCapsule`
  - 状态机：`registered -> verified -> active`，非法迁移 fail-closed 为 `state_corrupt`
  - 验证项：`sha256`、`signature`、`sbom_hash`、`allowed_egress[]`（machine-readable deny）
  - 推荐 machine-readable `deny_code`：`invalid_request` / `permission_denied` / `capsule_not_found` / `capsule_conflict` / `hash_mismatch` / `signature_invalid` / `sbom_invalid` / `egress_policy_violation` / `state_corrupt` / `runtime_error`
  - 审计事件：`agent.capsule.registered`、`agent.capsule.verified`、`agent.capsule.denied`、`agent.capsule.activated`
- `AgentSessionOpen` / `AgentToolRequest` / `AgentToolGrantDecision` / `AgentToolExecute`
  - ACP grant 主链：`ingress -> risk classify -> policy -> grant -> execute -> audit`
  - risk classify 采用风险下限保护：`final_risk_tier = max(caller_hint, hub_inferred_by_tool_scope)`，禁止通过低风险 hint 旁路 grant
  - skills 能力映射冻结：`capabilities_required -> required_grant_scope` 以 `docs/memory-new/schema/xhub_skills_capability_grant_chain_contract.v1.json` 为准；scope/risk floor 漂移按 `request_tampered` fail-closed
  - high-risk execute 必须携带有效 `grant_id`，缺失/过期/篡改一律 deny（fail-closed）
  - execute 幂等重放采用严格一致性：同一 `request_id` 若 `tool_request_id/tool_name/tool_args_hash/exec_argv/exec_cwd/grant_id` 漂移，统一 `deny_code=request_tampered`（不回放旧成功结果）
  - 审批绑定硬化：`exec_argv` 精确匹配（仅接受字符串参数）+ `exec_cwd` 绝对路径 canonical realpath（含 symlink 防护）+ identity hash 绑定 canonical session project scope + 执行前二次 identity hash 校验（不匹配即 deny）
  - incident 语义冻结：`grant_pending` / `awaiting_instruction` / `runtime_error` 的 `deny_code + event_type` 模板受 `docs/memory-new/xhub-skills-capability-grant-chain-contract-v1.md` 约束，供 XT-Ready 机判联动
  - 推荐 machine-readable `deny_code`：`invalid_request` / `session_not_found` / `tool_request_not_found` / `grant_pending` / `grant_missing` / `grant_expired` / `request_tampered` / `gateway_fail_closed` / `policy_denied` / `downgrade_to_local` / `approval_binding_invalid` / `approval_binding_missing` / `approval_binding_corrupt` / `approval_argv_mismatch` / `approval_cwd_invalid` / `approval_cwd_mismatch` / `approval_identity_mismatch` / `runtime_error`
- `CreatePaymentIntent` / `AttachPaymentEvidence` / `IssuePaymentChallenge` / `ConfirmPaymentIntent` / `AbortPaymentIntent`
  - 状态机：`prepared -> evidence_verified -> pending_user_auth -> authorized -> committed | aborted | expired`
  - anti-replay + timeout fail-closed：nonce/challenge 过期与重放拦截，超时自动转 `expired`（后台 sweep + RPC 入口双保险）
  - evidence 签名验真：默认 `sha256(payload)`；配置 `HUB_PAYMENT_EVIDENCE_SIGNING_SECRET` 后切换 `hmac-sha256(payload)`（fail-closed）
  - 回执/补偿：`committed` 后进入 receipt 通道，支持 undo 窗口（`HUB_PAYMENT_RECEIPT_UNDO_WINDOW_MS`）与补偿 worker（`HUB_PAYMENT_RECEIPT_COMPENSATION_DELAY_MS`）
  - `AbortPaymentIntent` 在 `committed` 阶段为“异步补偿请求”：响应返回 `aborted=true` 且 `compensation_pending=true`，intent 先进入 `receipt_delivery_state=undo_pending`，后续由补偿 worker 收口为 `status=aborted, receipt_delivery_state=compensated`
  - confirm 幂等绑定：`committed` 后仅接受同 `confirm_nonce` 且 challenge/mobile 绑定一致的重试请求；不一致 fail-closed
  - 审计事件：`payment.intent.created`、`payment.evidence.verified`、`payment.challenge.issued`、`payment.confirmed`、`payment.aborted`、`payment.expired`
- `ProjectHeartbeat` (persist project heartbeat with TTL; stale/expired heartbeat is fail-closed)
- `GetDispatchPlan` (oldest-first fair scheduling + anti-starvation + prewarm targets; missing heartbeat falls back to conservative mode)
- `GetRiskTuningProfile` / `EvaluateRiskTuningProfile` / `PromoteRiskTuningProfile` (risk tuning profile evaluate/promote/auto-rollback with holdout gate; fail-closed on constraint violation)
- `IssueVoiceGrantChallenge` / `VerifyVoiceGrantResponse` (Supervisor voice authorization challenge/verify; default dual-channel `voice + mobile`, high-risk voice-only denied)
- M3-W1-03 deny_code dictionary + boundary freeze: `docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`
- M3-W1-03 contract test checklist (deny_code grouped): `docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md`
- `LongtermMarkdownExport` (Longterm Markdown projection export; DB remains source-of-truth)
- `LongtermMarkdownBeginEdit` / `LongtermMarkdownApplyPatch` (edit session + optimistic-lock patch draft; no direct canonical write)
- `LongtermMarkdownReview` / `LongtermMarkdownWriteback` (review/approve/writeback gate; write only to Longterm candidate queue)
- `LongtermMarkdownRollback` (rollback by `pending_change_id`; idempotent and fail-closed on cross-scope mismatch)

### 12.2 HTTP (reserved)
- `POST /memory/threads/get_or_create`
- `POST /memory/turns/append`
- `GET /memory/threads/{thread_id}/working_set?limit=...`
- `POST /memory/canonical/upsert`
- `GET /memory/canonical?scope=...&thread_id=...`
- `POST /memory/projects/lineage/upsert`
- `GET /memory/projects/lineage/tree?root_project_id=...&project_id=...&max_depth=...`
- `POST /memory/projects/dispatch/attach`
- `POST /memory/agent/capsule/register`
- `POST /memory/agent/capsule/verify`
- `POST /memory/agent/capsule/activate`
- `POST /memory/agent/session/open`
- `POST /memory/agent/tool/request`
- `POST /memory/agent/tool/grant_decision`
- `POST /memory/agent/tool/execute`
- `POST /memory/payment/intents/create`
- `POST /memory/payment/intents/attach_evidence`
- `POST /memory/payment/intents/issue_challenge`
- `POST /memory/payment/intents/confirm`
- `POST /memory/payment/intents/abort`
- `POST /memory/projects/heartbeat`
- `POST /memory/projects/dispatch/plan`
- `GET /memory/risk_tuning/profile?profile_id=...`
- `POST /memory/risk_tuning/evaluate`
- `POST /memory/risk_tuning/promote`
- `POST /memory/supervisor/voice/challenge/issue`
- `POST /memory/supervisor/voice/challenge/verify`
- `POST /memory/longterm/markdown/export`
- `POST /memory/longterm/markdown/begin_edit`
- `POST /memory/longterm/markdown/apply_patch`
- `POST /memory/longterm/markdown/review`
- `POST /memory/longterm/markdown/writeback`
- `POST /memory/longterm/markdown/rollback`

---

## 13) Skills (Discovery + Import v1)

Goal: preserve a portable “search + install skill” UX while keeping Hub as the single control plane:
- Hub stores/pins/audits skills; Hub does **not** execute third-party skill code.
- v1 import is **Client Pull + Upload** (Terminal downloads, Hub verifies/stores).

### 13.1 gRPC
See `service HubSkills` in `protocol/hub_protocol_v1.proto`:
- `SearchSkills` (built-in catalog search; also used by `skills.search` tool)
- `UploadSkillPackage` (upload tgz/zip bytes + `skill.json` manifest)
- `SetSkillPin` (scope `global|project`, identity bound by pairing; global pins are keyed by `user_id`)
- `ListResolvedSkills` (Memory-Core > Global > Project precedence, returns effective list for a `(user_id, project_id)` context)
- `GetSkillManifest` / `DownloadSkillPackage` (runner fetch)

Audit event types (minimum set):
- `skills.search.performed`
- `skills.package.imported`
- `skills.pin.updated`
- `skills.revoked` (reserved; revocation chain is a separate milestone)
