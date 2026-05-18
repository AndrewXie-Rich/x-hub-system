# RHM-137 XT Hub Compatibility Guard

Date: 2026-05-15

## Scope

Every Rust Hub change that touches routing, grants, audit, memory, skills,
provider accounts, model inventory, pairing, or XT file IPC must preserve the
X-Terminal contract first.

Rust Hub remains authority for:

- grants and pending grant truth;
- audit references and policy decisions;
- durable memory truth and memory fail-closed gates;
- kill-switch and production authority switches;
- skill catalog, pins, grants, preflight, and execution authority;
- provider/model route authority when the production switches are enabled.

X-Terminal remains owner of:

- pairing and connection UX;
- route diagnostics and user-facing repair text;
- session runtime presentation;
- Supervisor display;
- tool execution UX and local tool safety presentation.

## XT Files Read For This Guard

The guard is based on the current XT source under:

`/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal`

Primary files:

- `Sources/Hub/HubPaths.swift`
- `Sources/Hub/HubConnector.swift`
- `Sources/Hub/HubAIClient.swift`
- `Sources/Hub/HubIPCClient.swift`
- `Sources/Hub/HubRouteStateMachine.swift`
- `Sources/Hub/HubPairingCoordinator.swift`
- `Sources/Hub/HubAccessKeysClient.swift`
- `Sources/Hub/HubProviderKeysClient.swift`
- `Sources/Hub/RustHubReadinessClient.swift`
- `Sources/Hub/RustHubModelRouteDiagnosticsClient.swift`
- `Sources/Hub/HubBridgeClient.swift`
- `Sources/Hub/HubBridgePaths.swift`
- `Sources/Hub/HubWebFetchClient.swift`
- `Sources/Hub/HubRemoteHostPolicy.swift`
- `Sources/Hub/XTHubConnectionStore.swift`
- `Sources/Hub/XTHubRouteHandoff.swift`
- `Sources/Hub/HubModels.swift`
- `Sources/Supervisor/SupervisorSkillPreflightGate.swift`
- `Sources/Supervisor/SupervisorSkillRegistrySnapshot.swift`
- `Sources/Tools/ToolExecutor.swift`

## Route Contract

Do not drift these semantics:

- `grpc`: remote-only and fail-closed. Missing profile is `hub_env_missing`.
  Business errors must surface and must not silently fall back to file IPC.
- `auto`: remote-first only when a pairing profile exists. File fallback is
  allowed only for route or transport errors, such as `hub_env_missing`,
  `grpc_route_unavailable`, `grpc_unavailable`, `14_unavailable`,
  connection refused, network unreachable, TLS/SSL errors, timeout, and HTML
  502/503/504 outage payloads.
- `file`: local file IPC only.

Explicit non-fallback business errors include:

- `model_not_found`
- `api_key_missing`
- paid model deny codes
- grant or policy deny codes

Any new Rust route error must be classified before shipping. If it is not
clearly route-unavailable or transport-unavailable, XT must treat it as a
business error and not fallback.

## Stable Fields And Tokens

Do not rename or remove existing XT-visible fields. Additive fields are allowed.

Fields that must remain stable:

- `schema_version`
- `reason_code`
- `deny_code`
- `fallback_reason_code`
- `raw_deny_code`
- `audit_ref`
- `grant_id`
- `grant_request_id`
- `execution_id`
- `package_sha256`
- `tool_request_id`
- `updated_at_ms`
- `created_at_ms`

Paid model deny and reason tokens that XT already understands:

- `device_paid_model_disabled`
- `device_paid_model_not_allowed`
- `device_paid_model_policy_missing`
- `device_daily_token_budget_exceeded`
- `device_single_request_token_exceeded`
- `legacy_grant_flow_required`
- `grant_required`
- `grant_pending`
- `grant_denied`
- `permission_denied`
- `forbidden`
- `denied`

Provider/runtime reason tokens that XT already maps:

- `missing_scope`
- `token_expired`
- `invalid_api_key`
- `auth_missing`
- `model_not_supported`
- `quota_exceeded`
- `rate_limited`
- `provider_timeout`
- `network_unreachable`
- `invalid_base_url`

## Pairing And Access-Key Contract

XT reads paired state from the user state dir:

- `pairing.env`
- `hub.env`

Required environment names include:

- `HUB_CLIENT_TOKEN`
- `HUB_HOST`
- `HUB_PORT`
- `HUB_PAIRING_PORT`
- `HUB_DEVICE_ID`
- `HUB_USER_ID`
- `HUB_APP_ID`
- `HUB_PROJECT_ID`
- `HUB_SESSION_ID`
- `AXHUB_PAIRING_PORT`
- `AXHUB_HUB_HOST`
- `AXHUB_INTERNET_HOST`

XT access-key management calls pairing HTTP, not the Rust `/ready` port:

- `GET /xt/clients/access-keys?auth_kind=hub_access_key`
- `GET /xt/clients/access-keys/:id`
- `POST /xt/clients/access-keys`
- `POST /xt/clients/access-keys/:id/rotate`
- `POST /xt/clients/access-keys/:id/revoke`

Responses must keep:

- `ok`
- `updated_at_ms`
- `access_keys`
- `access_key`
- `client_token`
- `idempotent`
- `error.code`
- `error.message`
- `error.retryable`

## Provider And Model Contract

XT still has a Node client-kit bridge for provider accounts:

- it reads `hub.env`;
- it expects `client_kit/hub_grpc_server`;
- it invokes gRPC service `HubProviderKeys`;
- it calls methods such as `ListProviderKeys`, `ListProviderKeyPools`,
  `GetProviderKeyRuntimeSnapshot`, `GetProviderKeyRouteDecision`,
  `AddProviderKey`, `ImportProviderKeys`, `ReportKeyUsage`,
  `ReportKeyError`, `GetKeyUsage`, and `ResetKeyErrorState`.

Rust HTTP provider endpoints are useful and currently present, but they do not
by themselves satisfy this XT path. If Rust takes provider account authority,
one of these must be true before cutover:

- Rust implements compatible `HubProviderKeys` gRPC service; or
- XT gets an explicit migration layer to call Rust HTTP while preserving all
  existing field names and reason codes.

Provider snapshots must keep:

- `accounts`
- `import_source_statuses`
- `updated_at_ms`
- `global_routing_strategy`
- `providers`
- account fields such as `account_key`, `provider`, `email`, `enabled`,
  `auth_type`, `tier`, `base_url`, `proxy_url`, `pool_id`,
  `provider_host`, `wire_api`, `models`, `quota`, `error_state`,
  `refresh_state`, `model_states`, `api_key_redacted`, `priority`
- route fields such as `requested_provider`, `requested_model_id`,
  `resolved_provider`, `strategy`, `selection_scope`,
  `selected_account_key`, `fallback_reason_code`, `available_count`,
  `total_count`, `candidates`

Current observed Rust Hub status on 2026-05-15:

- `/ready` is ok and ready.
- `model_route_authority_in_rust=true`.
- `provider_route_authority_in_rust=true`.
- `provider_key_runtime_snapshot_http=true`.
- `provider_key_pools_http=true`.
- `provider_key_import_http=true`.
- `provider_store_file_exists=false`.
- `/provider/runtime-snapshot` returned no accounts.
- `/provider/pools` returned no pools.
- `/model/inventory` returned no local or remote models.

Implication: XT can see Rust Hub as connected, but model/provider UI will have
no usable remote account inventory until provider account import/storage is
populated or bridged.

2026-05-17 provider import prep update:

- Rust now has `xhubd provider import` and `/provider/import` prep surfaces for
  Codex CLI `auth*.json` and Codex CLI `config.toml` sibling/explicit auth
  files.
- The import result keeps XT-compatible top-level `ok`, `imported`, and
  `errors` fields, and the runtime snapshot keeps `import_source_statuses`,
  `source_owners`, `source_type`, `source_ref`, `oauth_source_key`,
  `provider_host`, `wire_api`, `quota`, `error_state`, `refresh_state`, and
  redacted `api_key_redacted`.
- This does not by itself migrate XT's provider UI: XT currently still calls
  classic Node `HubProviderKeys` gRPC via `HubProviderKeysClient.swift`.
  Switching XT to Rust requires either compatible Rust gRPC or an explicit XT
  HTTP migration layer; until then, Node/XT and Rust runtime store locations
  must be kept aligned.
- No `reason_code`, `deny_code`, grant truth source, or `grpc/auto/file` route
  fallback semantics changed in this update.

2026-05-18 live provider import result:

- Domain Rust Hub advertises `provider_key_import_http=true` under both
  `runtime` and `capabilities`.
- Secret-free fixture import through `/provider/import` returned
  `ok=true imported=1`; the runtime snapshot redacted token material.
- Real Codex import from `/Users/andrew.xie/.codex` and
  `/Users/andrew.xie/.codex/config.toml` returned `ok=true imported=7`.
- Live `/provider/runtime-snapshot` contains three enabled Codex OAuth accounts,
  and `/provider/pools` groups them under `openai:api.openai.com:chat_completions`.
- All imported live accounts are expired (`reason_code=token_expired`,
  expiry on 2026-04-30), so `/model/inventory` reports
  `blocking_reason_code=all_keys_auth_blocked`. XT-facing presentation must keep
  this distinct from quota exhaustion.
- Remaining XT/Hub compatibility work is OAuth re-login or fail-closed refresh
  support, then rerun `/provider/runtime-snapshot`, `/provider/pools`,
  `/model/inventory`, and the XT provider/model smoke paths.

2026-05-18 OAuth refresh state-writer prep:

- Additive Rust Hub surfaces were added:
  `/provider/oauth-refresh/apply`, `/provider/oauth-refresh/failure`,
  `xhubd provider apply-oauth-refresh`, and
  `xhubd provider record-oauth-refresh-failure`.
- `/ready` now advertises `provider_oauth_refresh_apply_http=true` and
  `provider_oauth_refresh_failure_http=true` under both `runtime` and
  `capabilities`.
- XT-visible provider fields are preserved: `account_key`, `provider`,
  `email`, `enabled`, `auth_type`, `account_id`, `source_ref`,
  `oauth_source_key`, `provider_host`, `wire_api`, `models`, `quota`,
  `error_state`, `refresh_state`, `reason_code`, `retry_at_source`, and
  `api_key_redacted`.
- Reason-code behavior is additive/stabilizing: terminal OAuth failures keep
  `invalid_grant` or `refresh_token_reused` with no retry, retryable failures
  keep `refresh_timeout`/`refresh_request_failed` with cooldown, and successful
  refresh clears auth-managed blockers such as `token_expired`.
- No `deny_code`, pending grant truth source, or `grpc`/`auto`/`file` route
  fallback semantics changed. No raw access tokens or refresh tokens are
  returned by the new JSON envelopes, runtime snapshots, or tests.
- XT files considered: `Sources/Hub/HubProviderKeysClient.swift`,
  `Sources/UI/ProviderKeySelectionPresentationSupport.swift`, and
  `Sources/Hub/ProviderKeyRuntimeFeedbackSupport.swift`. Targeted Rust checks
  run: `cargo test -p xhub-provider`, `cargo test -p xhubd provider_bridge`,
  and `cargo check -p xhubd`.
- Remaining work: implement the live Codex OAuth token endpoint caller or
  re-login UX, then rerun `/provider/runtime-snapshot`, `/provider/pools`,
  `/model/inventory`, and the XT provider/model smoke paths.

2026-05-18 Codex OAuth token endpoint bridge:

- Additive Rust Hub surfaces were added:
  `/provider/oauth-refresh/codex` and
  `xhubd provider refresh-codex-oauth`.
- `/ready` now advertises `provider_oauth_refresh_codex_http=true`.
- The bridge reads the refresh token from Hub's provider store, sends it to the
  token endpoint via stdin-backed `curl`, and then delegates all store mutation
  to the existing OAuth apply/failure writers.
- The refresh token is not placed in the command line, URL, logs, or JSON
  response. The response also omits new access/refresh tokens.
- XT-facing fields and semantics remain additive: successful refresh clears
  auth-managed blockers; terminal provider failures keep stable
  `invalid_grant`/`refresh_token_reused`; retryable transport failures keep
  `refresh_timeout`/`refresh_request_failed` and cooldown.
- No `deny_code`, pending grant truth source, high-risk grant chain, or
  `grpc`/`auto`/`file` route fallback semantics changed.
- Targeted Rust checks run: `cargo test -p xhubd provider_bridge` and
  `cargo check -p xhubd`.

2026-05-18 Codex OAuth refresh planner:

- Additive Rust Hub surfaces were added:
  `/provider/oauth-refresh/codex/plan`,
  `/provider/oauth/codex-refresh/plan`,
  `/provider/codex-oauth-refresh/plan`, and
  `xhubd provider plan-codex-oauth-refresh`.
- `/ready` now advertises `provider_oauth_refresh_codex_plan_http=true`.
- The planner is read-only and secret-free. It emits due account keys,
  `reason_code`, `expires_at_ms`, `refresh_due_at_ms`, `next_refresh_at_ms`,
  and retry metadata, but never emits access tokens or refresh tokens.
- Due selection is fail-closed and additive: disabled accounts, in-flight
  accounts, missing refresh tokens, unsupported OAuth schemas, and terminal
  refresh failures are skipped; retryable failures are selected only after
  their `refresh_state.next_refresh_at_ms`.
- Expiry refresh lead defaults to a long proactive window but is capped by the
  observed token TTL, so short-lived access tokens are not refreshed on every
  request.
- No XT-visible provider field was renamed or removed. No `deny_code`, pending
  grant truth source, high-risk grant chain, or `grpc`/`auto`/`file` route
  fallback semantics changed.
- Targeted Rust checks run:
  `cargo test -p xhub-provider oauth_refresh`,
  `cargo test -p xhubd provider_bridge`, and
  `bash tools/provider_codex_oauth_refresh_smoke.command`.

## XT File IPC Contract

XT writes generate requests to:

- `ai_requests/req_<req_id>.json`

XT tails responses from:

- `ai_responses/resp_<req_id>.jsonl`

XT writes cancel requests to:

- `ai_cancels/cancel_<req_id>.json`

Request fields Rust must keep reading:

- `type`
- `req_id`
- `app_id`
- `task_type`
- `preferred_model_id`
- `model_id`
- `prompt`
- `max_tokens`
- `temperature`
- `top_p`
- `created_at`
- `auto_load`
- `provider_key`

Response events must keep:

- `type`
- `req_id`
- `ok`
- `reason`
- `text`
- `seq`
- `model_id`
- token fields
- metadata fields such as `requested_model_id`, `preferred_model_id`,
  `actual_model_id`, `runtime_provider`, `execution_path`,
  `fallback_reason_code`, `audit_ref`, `deny_code`,
  `provider_key_account_key`, `provider_key_provider`,
  `provider_key_tokens_used`, `provider_key_cost_usd`,
  `provider_key_error_code`

## Pending Grants Contract

Pending grants must come from Hub snapshots, not XT log inference.

Local fallback file shape:

- `pending_grant_requests_status.json`
- top level: `schema_version`, `updated_at_ms`, `items`
- item: `grant_request_id`, `request_id`, `client`, `capability`, `model_id`,
  `reason`, `requested_ttl_sec`, `requested_token_cap`, `status`, `decision`,
  `created_at_ms`, `decided_at_ms`

Auto mode may annotate a fallback source only when the remote snapshot failed
with route-unavailable semantics:

`transport=auto|remote_snapshot_unavailable=1|fallback_used=1|fallback_reason=<reason>`

gRPC mode must fail closed and must not fallback to the file snapshot.

## Memory Contract

Memory request schema:

- `xt.memory_retrieval_request.v1`

Memory response fields XT consumes:

- `schema_version`
- `request_id`
- `status`
- `resolved_scope`
- `source`
- `scope`
- `audit_ref`
- `reason_code`
- `detail`
- `deny_code`
- `results`
- `snippets`
- `truncated`
- `budget_used_chars`
- `truncated_items`
- `redacted_items`

High-risk memory use must preserve fresh Hub memory truth and fail closed when
the snapshot is stale or denied.

## Skills Contract

Skill catalog entries XT consumes include:

- `skill_id`
- `display_name`
- `description`
- `intent_families`
- `capability_families`
- `capability_profiles`
- `grant_floor`
- `approval_floor`
- `package_sha256`
- `publisher_id`
- `source_id`
- `official_package`
- `capabilities_required`
- `governed_dispatch`
- `governed_dispatch_variants`
- `input_schema_ref`
- `output_schema_ref`
- `side_effect_class`
- `risk_level`
- `requires_grant`
- `policy_scope`
- `timeout_ms`
- `max_retries`
- `available`

Skill runner gate result fields XT consumes:

- `ok`
- `source`
- `skill_id`
- `package_sha256`
- `tool_name`
- `decision`
- `tool_request_id`
- `grant_id`
- `execution_id`
- `deny_code`
- `result_json`
- `executed_at_ms`

`grant_required` remains the canonical preflight deny for skills that need a
grant. Quarantine and policy denies must stay explicit, for example
`preflight_quarantined` or a stable Hub deny code.

## Web Fetch And High-Risk Tool Contract

XT `web_fetch` uses the bridge paths:

- `bridge_requests/req_<req_id>.json`
- `bridge_responses/resp_<req_id>.json`

Request fields:

- `type: "fetch"`
- `req_id`
- `url`
- `method: "GET"`
- `created_at`
- `timeout_sec`
- `max_bytes`

Response fields:

- `ok`
- `status`
- `final_url`
- `content_type`
- `truncated`
- `bytes`
- `text`
- `error`

High-risk `web_fetch` must keep grant checks and deny codes:

- `high_risk_grant_missing`
- `high_risk_grant_invalid`
- `high_risk_grant_expired`
- `high_risk_bridge_disabled`

## Pre-Change Checklist

Before changing Rust Hub behavior that can affect XT:

1. Name the XT consumer files and exact fields affected.
2. Confirm whether the change is additive or breaking.
3. Preserve old field names or add a migration layer.
4. Classify every new `reason_code` and `deny_code`.
5. Confirm `grpc`, `auto`, and `file` route semantics stay unchanged.
6. Confirm pending grants remain Hub-snapshot truth.
7. Confirm high-risk capabilities keep grant, policy, and audit links.
8. Confirm provider account authority still satisfies the XT gRPC client-kit
   path or an explicit XT migration.
9. Confirm `/ready` does not claim a production authority unless the matching
   XT-visible surface is actually usable.
10. Confirm no raw provider secrets, access keys, refresh tokens, or custom
    headers are emitted in diagnostics, JSONL, reports, or UI payloads.

## Verification Matrix

Run Rust-side checks when the touched surface changes:

- `cargo test -p xhubd xt_file_ipc`
- `cargo test -p xhubd xt_compat`
- `cargo test -p xhubd provider_bridge`
- `cargo test -p xhubd model_bridge`
- `cargo test -p xhubd memory_bridge`
- `cargo test -p xhubd skills_bridge`
- `bash tools/daemon_ops_gate.command --allow-memory-skills-production --require-memory-skills-production`
- `bash tools/provider_route_http_smoke.command`
- `bash tools/model_route_http_smoke.command`
- `bash tools/memory_retrieval_http_smoke.command`
- `bash tools/skills_catalog_http_smoke.command`
- `bash tools/xt_file_ipc_live_heartbeat_soak.command`

Run targeted XT tests when Hub contracts change:

- `swift test --filter HubStatusLivenessTests`
- `swift test --filter HubBaseDirConvergenceTests`
- `swift test --filter HubRouteStateMachineTests`
- `swift test --filter HubAIClientReconnectPolicyTests`
- `swift test --filter HubAIClientErrorPresentationTests`
- `swift test --filter HubAIClientRemoteConnectOptionsTests`
- `swift test --filter HubAIPaidModelAccessExplainabilityTests`
- `swift test --filter HubIPCClientLocalTaskTests`
- `swift test --filter HubIPCClientMemoryRetrievalContractTests`
- `swift test --filter HubIPCClientRequestFailureDiagnosticsTests`
- `swift test --filter HubModelRoutingTruthBuilderTests`
- `swift test --filter RustHubReadinessPresentationTests`
- `swift test --filter RustHubModelRouteDiagnosticsPresentationTests`
- `swift test --filter SupervisorPendingHubGrantPresentationTests`
- `swift test --filter SupervisorPendingSkillApprovalPresentationTests`
- `swift test --filter SupervisorSkillRegistrySnapshotTests`
- `swift test --filter SupervisorSkillRoutingCompatibilityHintTests`
- `swift test --filter ToolExecutorWebSearchGrantGateTests`
- `swift test --filter XTHubConnectionStoreTests`
- `swift test --filter XTUnifiedDoctorHubReachabilityTests`
- `swift test --filter HubAccessKeysClientTests`
- `swift test --filter HubPairingCoordinatorTests`
- `swift test --filter HubBridgeClientTests`

## Release Note Requirement

Every Hub change that crosses this boundary must report:

- exact XT files or tests considered;
- changed endpoints or JSON fields;
- new, removed, or reclassified `reason_code` / `deny_code`;
- whether `grpc`, `auto`, or `file` route semantics changed;
- whether pending grant truth source changed;
- whether provider account import/list/route compatibility changed;
- smoke and test commands run, including skipped commands and why.
