# Rust Hub Model Management Execution Plan

Status: active-proposed
Updated: 2026-05-18
Target root: `/Users/andrew.xie/Documents/AX/rust/rust hub`
Source plan: `/Users/andrew.xie/Documents/AX/x-hub-system/docs/memory-new/xhub-remote-paid-and-local-model-management-execution-plan-v1.md`

## 0. Purpose

This document maps the X-Hub remote-paid-model and local-model management plan
onto the Rust Hub rewrite. It is intentionally Rust-specific: the canonical
product plan remains in `x-hub-system/docs/memory-new`, while this file defines
which Rust crates, CLIs, bridges, and readiness gates must absorb that plan.

Rust Hub must not become a second product truth. It should become the typed,
fast, shadow-comparable authority for:

- remote provider route decisions
- provider account pool availability
- route decision explainability
- local model artifact inventory
- local runtime preflight
- unified model inventory snapshots
- cutover readiness evidence

Node Hub and RELFlowHub remain production authority until each Rust slice has
shadow evidence, readiness gates, and an explicit opt-in bridge.

## 1. Non-Negotiable Boundaries

1. Rust Hub does not store provider email/password credentials.
2. Rust Hub does not automate provider website password login, CAPTCHA, or
   anti-abuse bypasses.
3. Rust Hub must not log provider API keys, OAuth access tokens, refresh tokens,
   or downloaded auth file contents.
4. Rust provider routing returns selected account identity and explainability,
   not request payload secrets.
5. XT reads Hub/Rust snapshots and route decisions; XT does not reimplement
   provider quota, OAuth scope, or local runtime availability logic.
6. Any scope, quota, auth, model unsupported, or local runtime failure must fail
   closed with a machine-readable reason code.
7. All Rust cutovers must stay default-off until readiness gates pass.

## 2. Current Rust Hub Starting Point

Already present in this Rust workspace:

- `crates/xhub-provider`
  - reads the Node provider key store shape
  - infers provider from model ID
  - supports shared OpenAI/Codex pools
  - skips disabled, missing-auth, expired, cooldown, blocked, stale, and quota
    exhausted accounts
  - plans and applies secret-safe Codex OAuth refresh without exposing token
    material in CLI/HTTP output
  - emits candidate decisions without provider secrets
- `crates/xhubd/src/provider_bridge.rs`
  - exposes `xhubd provider route`
  - exposes `provider compare`, `provider reports`, and `provider readiness`
  - exposes `provider plan-codex-oauth-refresh` and
    `provider refresh-codex-oauth`
  - persists append-only `provider_route` shadow evidence
- Node Hub opt-in hooks
  - provider route shadow compare
  - provider authority observe for `HubAI.Generate`
  - candidate audit event for paid-model generate path
- packaging
  - `tools/package_rust_hub.command` already copies `docs/*.md`, so this file
    ships with future Rust Hub packages automatically.

## 3. Desired Rust Surface

The Rust side should expose four typed surfaces before any provider cutover:

### 3.1 Provider Route Decision

Command:

```bash
xhubd provider route --model-id gpt-5.5 --provider openai
```

Output must include:

- normalized requested model
- resolved provider
- selected account key
- pool ID
- routing strategy
- available/total counts
- candidate list
- skipped candidate reasons
- next retry time
- fallback reason when no account can be selected

### 3.2 Model Inventory Snapshot

Proposed command:

```bash
xhubd model inventory --runtime-base-dir <runtime-dir>
```

Output must include both:

- remote rows derived from provider key pools and remote model catalog
- local rows derived from local model artifacts and runtime preflight

### 3.3 Local Runtime Preflight

Proposed command:

```bash
xhubd model local-preflight --model-id <local-model-id>
```

Output must answer:

- is the artifact present
- is the format supported
- is the provider runtime installed
- can the model dry-run load
- is memory risky
- which capabilities are available

### 3.4 Unified Route Decision

Proposed command:

```bash
xhubd model route --task-type coder --required-capability code.assist --model-id auto
```

Output must decide between:

- remote paid primary
- remote account pool fallback
- local privacy/cost primary
- local offline fallback
- blocked missing capability
- blocked auth/quota/runtime

## 4. Rust Work Orders

### RHM-001 Mirror Model Management Contract

Priority: P0
Owner: xhub-contract / xhubd
Source: RLM-W0-01
Files:

- `assets/proto/hub_protocol_v1.proto`
- `crates/xhub-contract`
- `crates/xhubd/src/grpc_runtime.rs`
- `docs/MODEL_MANAGEMENT_EXECUTION_PLAN.md`

Tasks:

1. Mirror additive proto fields for model inventory and route decisions after
   they land in `x-hub-system/protocol/hub_protocol_v1.proto`.
2. Add Rust structs only after proto source is mirrored.
3. Keep existing gRPC methods fail-closed until the new surface is explicitly
   implemented.
4. Add decode/serialization tests for additive fields.

Done:

- Rust compiles with mirrored proto.
- Old clients still get current fail-closed responses.
- No field names diverge from Node/Swift contract.

### RHM-002 Normalize Model IDs In Rust Provider Routing

Priority: P0
Owner: xhub-provider
Source: RLM-W1-01
Files:

- `crates/xhub-provider/src/lib.rs`
- `docs/PROVIDER_ROUTE_CLI.md`

Tasks:

1. Add one Rust model ID normalizer used by provider inference and model-state
   lookup.
2. Normalize common OpenAI aliases:
   - `GPT5.5`
   - `gpt5.5`
   - `openai/gpt5.5`
   - `openai/GPT5.5`
3. Emit the canonical requested model in route decisions so downstream routing
   and provider calls do not keep propagating alias typos.
4. Compare Rust normalizer output against Node/Swift fixture expectations.

Done:

- `xhubd provider route --model-id openai/gpt5.5` resolves to the same model
  family and account candidates as `gpt-5.5`.
- Unit tests cover alias casing, compact/hyphenated OpenAI GPT spellings,
  provider prefixes, model-state aliases, and unknown model IDs.
- `xhubd provider compare` normalizes `requested_model_id`, `selection_scope`,
  and `model_state_key` with the same canonicalizer before recording
  Node-vs-Rust parity reports.

### RHM-003 Extend Provider Candidate Trace

Priority: P0
Owner: xhub-provider / xhubd
Source: RLM-W1-02
Files:

- `crates/xhub-provider/src/lib.rs`
- `crates/xhubd/src/provider_bridge.rs`
- `docs/PROVIDER_ROUTE_CLI.md`

Tasks:

1. Ensure every candidate row carries:
   - `account_key`
   - `provider`
   - `pool_id`
   - `state`
   - `selected`
   - `reason_code`
   - `status_message`
   - `retry_at_source`
   - `next_retry_at_ms`
   - `models`
2. Include route-level `pool_id`, `routing_strategy`, and `selection_scope`.
3. Keep secrets out of all JSON.
4. Keep compare normalization stable so Node/Rust reports can ignore harmless
   presentation-only differences.

Done:

- A blocked/cooling account is visible in trace and is not selected.
- A selected account has `reason_code=selected_by_scheduler`.
- Route decisions expose additive `pool_id` and `routing_strategy` trace
  fields.
- Candidate rows expose additive `next_retry_at_ms` beside the existing
  `retry_at_ms` field.
- Serialized route decisions are covered by a secret-free regression test that
  rejects provider API keys and refresh tokens in trace output.
- Shadow compare reports still persist successfully.

### RHM-004 Align Quota And Retry Semantics

Priority: P0
Owner: xhub-provider
Source: RLM-W1-03
Files:

- `crates/xhub-provider/src/lib.rs`
- `docs/PROVIDER_ROUTE_CLI.md`

Tasks:

1. Treat both `quota.cooldown_until_ms` and `quota.next_recover_at_ms` as route
   cooldown inputs.
2. Treat model-state retry windows as model-specific cooldown inputs.
3. Preserve `retry_at_source`.
4. Classify provider errors using stable reason codes:
   - `missing_scope`
   - `token_expired`
   - `invalid_api_key`
   - `auth_missing`
   - `quota_exceeded`
   - `rate_limited`
   - `model_not_found`
   - `model_not_supported`
   - `invalid_base_url`
   - `provider_timeout`
   - `network_unreachable`
5. Add all-candidates fallback reason:
   - `all_keys_rate_limited`
   - `all_keys_auth_blocked`
   - `all_keys_stale`
   - `no_keys_for_provider`

Done:

- Accounts cooling only by `next_recover_at_ms` are not selected.
- The earliest retry time is visible in route output.
- Readiness gates fail when Rust and Node disagree on selected account or
  fallback reason.
- Unit tests cover `next_recover_at_ms` without requiring an
  `error_state.next_retry_at_ms` mirror.

### RHM-005 Add Model Inventory CLI

Priority: P0
Owner: xhub-provider / xhub-runtime / xhubd
Source: RLM-W0-01, RLM-W3-01
Files:

- `crates/xhubd/src/model_bridge.rs` (new)
- `crates/xhub-provider/src/lib.rs`
- `crates/xhub-runtime/src/lib.rs`
- `docs/MODEL_MANAGEMENT_EXECUTION_PLAN.md`

Tasks:

1. Add `xhubd model inventory`.
2. Include remote inventory rows from provider key store.
3. Include local inventory rows from local model metadata when available.
4. Return stable schema version `xhub.model_inventory.v1`.
5. Emit unknown/empty rows rather than crashing when source files are absent.

Remote row minimum fields:

- `model_id`
- `provider`
- `provider_host`
- `family_key`
- `pool_id`
- `availability_state`
- `available_account_count`
- `total_account_count`
- `blocking_reason_code`
- `next_retry_at_ms`

Local row minimum fields:

- `model_id`
- `artifact_path`
- `format`
- `runtime_provider`
- `availability_state`
- `blocking_reason_code`
- `capabilities`
- `memory_risk`

Done:

- CLI works against an empty runtime dir.
- CLI works against provider key fixtures.
- CLI output contains no secrets.
- Remote inventory rows are derived from provider route decisions and include
  canonical model IDs, provider host, family key, pool ID, availability counts,
  blocking reason, and next retry timestamp.
- Local inventory rows read `models_state.json` when present, skip paid-online
  runtime references, infer basic artifact format, and mark missing artifacts
  as `stale_artifact`.

### RHM-006 Add Local Artifact Inventory Reader

Priority: P0
Owner: xhub-runtime
Source: RLM-W2-01
Files:

- `crates/xhub-runtime/src/lib.rs`
- `crates/xhubd/src/model_bridge.rs`

Tasks:

1. Read local model artifact metadata from the current Hub local model store
   shape once that shape is identified.
2. Support missing file, moved file, duplicate artifact, and unknown format.
3. Identify GGUF, MLX, CoreML, Transformers, and unknown formats.
4. Record artifact path, display name, family, size, optional checksum, and
   quantization when present.

Done:

- Missing local artifact returns `availability_state=stale_artifact`.
- Unknown format returns `blocking_reason_code=unsupported_format`.
- Duplicate artifact fixtures do not produce duplicate stable IDs.
- Moved artifact fixtures can publish a resolved/current/moved-to path and
  inventory uses the existing path.
- Rows include additive artifact metadata: `display_name`, `family_key`,
  `artifact_size_bytes`, `checksum`, `quantization`, and
  `duplicate_artifact_of`.

### RHM-007 Add Local Runtime Preflight

Priority: P0
Owner: xhub-runtime / xhubd
Source: RLM-W2-02, RLM-W2-03
Files:

- `crates/xhub-runtime/src/lib.rs`
- `crates/xhubd/src/model_bridge.rs`

Tasks:

1. Add provider runtime readiness structs.
2. Detect missing runtime executable/package.
3. Detect unsupported format.
4. Detect memory risk using conservative host memory checks.
5. Add optional dry-run load hook later; initial implementation may return
   `unknown_stale` when no safe dry-run is available.
6. Emit capability tags:
   - `text.generate`
   - `text.summarize`
   - `code.assist`
   - `code.review`
   - `embedding.generate`
   - `vision.describe`
   - `vision.ocr`
   - `audio.transcribe`
   - `audio.tts`
   - `tool.calling`

Done:

- Local model is not marked ready without a runtime provider match.
- Capability mismatch is visible as a route blocking reason.
- Preflight is side-effect-free by default.
- Runtime preflight reads `ai_runtime_status.json` only; it does not start or
  load model runtimes.
- Runtime provider missing, runtime status missing, unsupported format, high
  memory risk, and capability mismatch are emitted as stable blocker codes.
- Capability tags are normalized to dotted names such as `text.generate`,
  `vision.ocr`, and `tool.calling`.

### RHM-008 Add Unified Model Route Decision

Priority: P0
Owner: xhub-provider / xhub-runtime / xhub-policy / xhubd
Source: RLM-W3-01
Files:

- `crates/xhubd/src/model_bridge.rs`
- `crates/xhub-provider/src/lib.rs`
- `crates/xhub-runtime/src/lib.rs`
- `crates/xhub-policy/src/lib.rs`

Tasks:

1. Add `xhubd model route`.
2. Accept task type, preferred model, required capabilities, privacy mode, and
   cost preference.
3. Try remote route decision first when policy allows.
4. Try local fallback only when capability and risk policy allow.
5. Block high-risk tasks instead of silently falling to weak local models.
6. Return selected route plus skipped candidates.

Done:

- Coder/reviewer high-risk tasks do not silently use local weak fallback.
- Summarization can use local fallback when remote quota is cooling.
- Every block has a machine-readable reason code.
- `xhubd model route` emits `xhub.model_route_decision.v1` and returns
  selected route, remote candidates, local candidates, and blocker reason.
- `privacy_mode=local-only` skips remote candidates and can select local.
- Empty runtime dirs fail closed with `no_model_route_available`.

### RHM-009 Add Node/Rust Shadow Compare For Model Inventory

Priority: P0
Owner: tools / Node bridge
Source: RLM-W4-01
Files:

- `tools/model_inventory_shadow_compare_smoke.js` (new)
- `tools/model_inventory_shadow_compare_smoke.command` (new)
- `tools/model_inventory_shadow_compare_runner.command` (new)
- Node Hub opt-in bridge files in `x-hub-system` after Rust CLI stabilizes

Tasks:

1. Compare Node/Swift-derived model inventory with Rust `model inventory`.
2. Normalize presentation-only differences.
3. Persist compare reports under component `model_inventory`.
4. Add readiness command or extend existing provider readiness.

Done:

- Done 2026-05-05: `xhubd model compare` normalizes Node/Swift presentation
  differences, including camelCase keys, provider/model casing, model aliases,
  capability spellings, and row ordering.
- Done 2026-05-05: compare reports persist under component `model_inventory`;
  `xhubd model reports` and `xhubd model readiness` expose the evidence gate.
- Done 2026-05-05: CI can run fixture-backed inventory compare without
  network through `tools/model_inventory_shadow_compare_smoke.command`.
- Done 2026-05-05: packaged Rust Hub includes the smoke and runner wrappers.
- Done 2026-05-05: mismatch reports identify field-level differences.

### RHM-010 XT Parity Gate

Priority: P0
Owner: XT / xhubd
Source: RLM-W3-02, RLM-W3-03
Files:

- `x-terminal/Sources/UI/XTVisibleHubModelInventory.swift`
- `x-terminal/Sources/UI/XTModelInventoryTruthPresentation.swift`
- `x-terminal/Tests/XTRustModelInventoryProjectionTests.swift`
- `x-terminal/Tests/Fixtures/RustModelInventory/*.json`
- `rust hub/docs/RHM_010_XT_MODEL_INVENTORY_FIELDS.md`
- Rust Hub docs and fixtures

Tasks:

1. Define the exact inventory fields XT consumes.
2. Add fixture JSON from Rust `model inventory`.
3. Add XT presentation tests for remote quota, missing scope, local runtime
   missing, and capability mismatch.
4. Do not let XT read token files or provider secrets.

Done:

- Done 2026-05-05: exact XT-consumed Rust inventory fields are documented in
  `docs/RHM_010_XT_MODEL_INVENTORY_FIELDS.md`.
- Done 2026-05-05: XT can project Rust `xhub.model_inventory.v1` into
  `ModelStateSnapshot` without reading token/auth/provider secret files.
- Done 2026-05-05: XT presentation tests cover remote quota, missing scope,
  local runtime missing, and capability mismatch fixtures.
- Done 2026-05-05: XT output carries Rust blocking reason codes instead of
  guessing quota, scope, runtime, or capability state.

### RHM-011 Default-Off Live XT/Rust Inventory Bridge

Priority: P0
Owner: XT / xhubd
Source: RHM-009, RHM-010
Files:

- `crates/xhubd/src/main.rs`
- `tools/model_inventory_http_bridge_smoke.js`
- `tools/model_inventory_http_bridge_smoke.command`
- `x-terminal/Sources/Hub/XTRustModelInventoryLiveBridge.swift`
- `x-terminal/Sources/LLM/HubModelManager.swift`
- `x-terminal/Tests/XTRustModelInventoryLiveBridgeTests.swift`
- `x-terminal/Tests/HubModelManagerFetchTests.swift`

Tasks:

1. Expose Rust `model inventory`, `compare`, `reports`, and `readiness` through
   shadow HTTP endpoints for warm-daemon consumption.
2. Add a local HTTP smoke that proves inventory output is secret-free and that
   model inventory readiness can be gated by compare evidence.
3. Add an XT live bridge that is default-off and only activates with explicit
   opt-in through `XHUB_RUST_MODEL_INVENTORY_BRIDGE=1` or the matching XT
   defaults key.
4. Let XT consume either a configured Rust inventory snapshot file or
   `GET /model/inventory` from a configured Rust HTTP base URL.
5. Preserve fail-closed behavior: invalid schema, HTTP errors, unavailable
   bridge source, or detected secret material must not mark Rust inventory as
   ready.
6. Keep production routing authority unchanged; this bridge only feeds visible
   model inventory and truth presentation while the Rust cutover remains
   default-off.

Done:

- Done 2026-05-05: Rust `xhubd serve` exposes `/model/inventory`,
  `/model/compare`, `/model/reports`, and `/model/readiness`.
- Done 2026-05-05: XT has a default-off live bridge that consumes
  `xhub.model_inventory.v1` from a configured snapshot file or Rust HTTP base
  URL without reading token/auth/provider secret files.
- Done 2026-05-05: `HubModelManager.fetchModels()` can use the bridge only when
  explicitly enabled, and model settings truth cards preserve Rust blocker
  states from the projection.
- Done 2026-05-05: bridge tests cover default-off config, snapshot ingestion,
  secret-material rejection, and HubModelManager integration.

### RHM-012 Sustained Node/XT Inventory Shadow Evidence

Priority: P0
Owner: tools / xhubd
Source: RHM-009, RHM-011
Files:

- `tools/model_inventory_shadow_compare_runner.js`
- `tools/model_inventory_shadow_compare_runner.command`
- `tools/xhubd_daemon.js`
- `docs/RHM_012_MODEL_INVENTORY_SHADOW_EVIDENCE.md`
- `tools/package_rust_hub.command`

Tasks:

1. Replace the placeholder runner wrapper with a sustained HTTP-first evidence
   runner.
2. Start an isolated warm Rust daemon and collect multiple model inventory
   compare reports.
3. Use Node Hub helper views for local runtime models and provider pool
   summaries without serializing account secrets.
4. Feed Node/XT-shaped camelCase inventory into Rust `/model/compare`.
5. Gate final output on `/model/readiness` and zero newly added mismatches.
6. Keep the path default-off and authority-neutral.

Done:

- Done 2026-05-05: `tools/model_inventory_shadow_compare_runner.js` starts an
  isolated `xhubd serve`, writes fixture provider/runtime/model state, and
  runs repeated HTTP inventory compare iterations.
- Done 2026-05-05: the runner imports Node Hub `runtimeModelsSnapshot`,
  `listProviderKeyPools`, and `providerKeyStoreSummary` as secret-free evidence
  inputs.
- Done 2026-05-05: secret leakage checks cover Rust inventory, Node helper
  evidence, Node/XT-shaped inventory, and compare responses.
- Done 2026-05-05: `tools/xhubd_daemon.js env` prints XT model inventory bridge
  variables for warm-daemon testing.
- Done 2026-05-05: packaged Rust Hub includes the sustained runner.

### RHM-013 Real Runtime Model Inventory Evidence

Priority: P0
Owner: tools / xhubd
Source: RHM-012
Files:

- `tools/model_inventory_shadow_compare_runner.js`
- `docs/RHM_013_REAL_RUNTIME_MODEL_INVENTORY_EVIDENCE.md`

Tasks:

1. Add `--use-existing-runtime` so the runner can read a supplied runtime dir
   without writing fixture files into it.
2. Add `--runtime-base-dir`, `--db-path`, and `--now-ms` controls for
   real-machine evidence collection.
3. Add `--no-start --http-base-url` so the runner can target an already warm
   `xhubd serve` daemon.
4. Keep the existing fixture mode as the default regression path.
5. Allow empty/missing Node local runtime snapshots when Rust also sees no
   local models, but fail closed when Rust has local rows that Node cannot see.
6. Preserve the secret boundary by using only Rust inventory/compare endpoints
   and Node secret-free summary helpers.

Done:

- Done 2026-05-06: the sustained runner supports existing runtime and warm
  daemon modes while defaulting to the isolated fixture mode.
- Done 2026-05-06: `--use-existing-runtime` short evidence passed against the
  existing MLX real-run report runtime with 2 matched reports, 0 mismatches, and
  readiness `ready`.
- Done 2026-05-06: self-test and dry-run cover the new real-runtime argument
  parsing.

### RHM-014 Model Route HTTP Prep

Priority: P0
Owner: xhubd / tools
Source: RHM-008, RHM-013
Files:

- `crates/xhubd/src/main.rs`
- `tools/model_route_http_smoke.js`
- `tools/model_route_http_smoke.command`
- `docs/RHM_014_MODEL_ROUTE_HTTP_PREP.md`

Tasks:

1. Expose `xhubd model route` through warm-daemon HTTP as `/model/route`.
2. Support query-string and JSON body request shapes for Node/XT bridge usage.
3. Preserve the existing `xhub.model_route_decision.v1` response schema.
4. Add a local smoke that proves both remote and local-only route decisions.
5. Keep production model routing authority unchanged.

Done:

- Done 2026-05-06: `/model/route` supports GET and POST requests with
  snake_case and camelCase field aliases.
- Done 2026-05-06: `tools/model_route_http_smoke.command` validates remote and
  local-only decisions against an isolated fixture runtime.
- Done 2026-05-06: the smoke verifies provider secrets are not serialized and
  records `authority_changed=false`.

### RHM-015 UI Compatibility Preservation Contract

Priority: P0
Owner: XT / xhubd
Source: RHM-010, RHM-011, RHM-014
Files:

- `docs/RHM_015_UI_COMPATIBILITY_PRESERVATION.md`
- `x-terminal/Sources/UI/ModelSettingsView.swift`
- `x-terminal/Sources/UI/ModelSelectorView.swift`
- `x-terminal/Sources/UI/ProjectSettingsView.swift`
- `x-terminal/Sources/UI/SupervisorSettingsView.swift`
- `x-terminal/Sources/UI/MessageTimeline/DockInputView.swift`
- `x-terminal/Sources/UI/TerminalChatView.swift`
- `x-terminal/Sources/UI/HubSetupWizardView.swift`
- `x-terminal/Sources/LLM/HubModelManager.swift`
- `x-terminal/Sources/Hub/XTRustModelInventoryLiveBridge.swift`

Tasks:

1. Document that Rust Hub is a backend rewrite and not a replacement product UI.
2. Enumerate XT product surfaces that must keep layout, navigation, and
   workflow stable.
3. Define allowed Rust data replacements and disallowed bundled UI changes.
4. Define fail-closed UI behavior when Rust daemon, schema, readiness, or
   secret checks fail.
5. Define per-bridge implementation checklists and focused test gates.
6. Require this contract before model route authority prep can change any
   selected model authority.

Done:

- Done 2026-05-06: UI compatibility preservation contract created with
  surface-by-surface preservation requirements, allowed Rust data source
  matrix, failure behavior, bridge checklist, and test gates.
- Done 2026-05-06: packageable
  `tools/ui_compatibility_no_product_ui_change_gate.command` added to verify
  Rust Hub remains backend/diagnostics only, does not embed SwiftUI product UI
  files, and keeps authority changes default-off.

### RHM-016 Model Route Authority Prep Bridge

Priority: P0
Owner: Node Hub / xhubd
Source: RHM-014, RHM-015
Files:

- `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_model_route_authority_bridge.js`
- `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/services.js`
- `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_model_route_authority_bridge.test.js`
- `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_provider_route_authority_generate_hook.test.js`
- `docs/RHM_016_MODEL_ROUTE_AUTHORITY_PREP_BRIDGE.md`

Tasks:

1. Add a default-off Node bridge for Rust `model route` decisions.
2. Support HTTP-first `/model/route` plus CLI fallback.
3. Require Rust `/model/readiness` by default before candidate use.
4. Compare Rust selected model and route kind against Node selected execution
   route.
5. Reject Rust responses containing secret-shaped keys or values.
6. Wire `HubAI.Generate` to record candidate audit evidence without changing
   selected model, Bridge payload, local runtime dispatch, or XT UI behavior.

Done:

- Done 2026-05-06: Node bridge implemented with
  `XHUB_RUST_MODEL_ROUTE_AUTHORITY_*` flags.
- Done 2026-05-06: `HubAI.Generate` writes
  `ai.generate.model_route_candidate` in candidate mode.
- Done 2026-05-06: tests cover default-off behavior, readiness fail-closed,
  HTTP route, mismatch reporting, secret rejection, and paid Generate audit
  preservation.

### RHM-017 Model Route Candidate Evidence Runner

Priority: P0
Owner: Node Hub / tools
Source: RHM-016
Files:

- `tools/model_route_generate_candidate_runner.js`
- `tools/model_route_generate_candidate_runner.command`
- `docs/RHM_017_MODEL_ROUTE_CANDIDATE_EVIDENCE_RUNNER.md`
- `tools/package_rust_hub.command`

Tasks:

1. Start an isolated Rust HTTP daemon for model route decisions.
2. Drive Node `HubAI.Generate` in-process against an isolated paid remote
   fixture and fake Bridge.
3. Enable `XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE=1` with HTTP-first
   `/model/route`.
4. Require `ai.generate.model_route_candidate` audits for every request.
5. Gate readiness on zero selected-model mismatches, zero route-kind
   mismatches, zero fallbacks, zero missing audits, and zero secret leakage.
6. Keep Bridge payload and Node selected execution model unchanged.

Done:

- Done 2026-05-06: runner self-test and dry-run implemented.
- Done 2026-05-06: isolated E2E readiness run passed with 2 Generate requests,
  2 candidate audits, zero mismatches, zero fallbacks, and zero secret leakage.

### RHM-018 Local Model Route Candidate Coverage

Priority: P0
Owner: Node Hub / tools
Source: RHM-016, RHM-017
Files:

- `tools/model_route_local_candidate_runner.js`
- `tools/model_route_local_candidate_runner.command`
- `docs/RHM_018_LOCAL_MODEL_ROUTE_CANDIDATE_COVERAGE.md`
- `tools/package_rust_hub.command`

Tasks:

1. Start an isolated Rust HTTP daemon for local model route decisions.
2. Drive Node `HubAI.Generate` in-process against an isolated local
   `local.summary` fixture.
3. Simulate local runtime JSONL response files.
4. Enable `XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE=1` with HTTP-first
   `/model/route`.
5. Require `ai.generate.model_route_candidate` audits for every local Generate
   request.
6. Gate readiness on zero selected-model mismatches, zero route-kind
   mismatches, zero fallbacks, zero missing audits, and zero secret leakage.
7. Verify runtime IPC request and Generate `done` metadata remain Node-selected
   `local.summary` with `execution_path=local_runtime`.

Done:

- Done 2026-05-06: runner self-test and dry-run implemented.
- Done 2026-05-06: isolated E2E readiness run passed with 2 local Generate
  requests, 2 candidate audits, zero mismatches, zero fallbacks, zero secret
  leakage, and local runtime execution preserved.

### RHM-020 Model Route Combined Candidate Evidence Report

Priority: P0
Owner: Node Hub / tools
Source: RHM-017, RHM-018
Files:

- `tools/model_route_candidate_evidence_runner.js`
- `tools/model_route_candidate_evidence_runner.command`
- `docs/RHM_020_MODEL_ROUTE_COMBINED_CANDIDATE_EVIDENCE_REPORT.md`
- `tools/package_rust_hub.command`

Tasks:

1. Run the paid remote model-route candidate runner.
2. Run the local runtime model-route candidate runner.
3. Persist a combined `xhub.model_route_candidate_evidence_report.v1`
   artifact.
4. Gate readiness on remote and local candidate readiness.
5. Require zero selected-model mismatches, zero route-kind mismatches, zero
   fallbacks, and zero secret leakage by default.
6. Record `production_authority_change=false` and
   `authority_mode=candidate_audit_only`.

Done:

- Done 2026-05-06: runner self-test and dry-run implemented.
- Done 2026-05-06: isolated combined E2E readiness run passed with 1 remote
  candidate audit, 1 local candidate audit, zero mismatches, zero fallbacks,
  zero secret leakage, and a persisted report artifact.

### RHM-023 Model Route Selected-Model Authority Plan

Priority: P0
Owner: Node Hub / tools
Source: RHM-020
Files:

- `tools/model_route_authority_plan_runner.js`
- `tools/model_route_authority_plan_runner.command`
- `docs/RHM_023_MODEL_ROUTE_SELECTED_MODEL_AUTHORITY_PLAN.md`
- `tools/package_rust_hub.command`

Tasks:

1. Run the combined remote/local candidate evidence runner.
2. Require the persisted candidate evidence report to exist.
3. Write a persisted
   `xhub.model_route_selected_model_authority_dry_run_plan.v1` plan artifact.
4. Record manual prep-trial environment variables and rollback variables.
5. Keep `production_authority_change=false`.
6. Keep Node as remote Bridge payload and local runtime IPC model authority.
7. Block production selected-model authority until a future explicit cutover
   task.

Done:

- Done 2026-05-06: runner self-test and dry-run implemented.
- Done 2026-05-06: isolated E2E plan passed with combined remote/local
  candidate evidence ready, persisted plan and evidence artifacts, zero
  mismatches, zero fallbacks, zero secret leakage, and production authority
  unchanged.

### RHM-026 Model Route Prep Trial Smoke

Priority: P0
Owner: Node Hub / tools
Source: RHM-023
Files:

- `tools/model_route_generate_candidate_runner.js`
- `tools/model_route_local_candidate_runner.js`
- `tools/model_route_prep_trial_runner.js`
- `tools/model_route_prep_trial_runner.command`
- `docs/RHM_026_MODEL_ROUTE_PREP_TRIAL_SMOKE.md`
- `tools/package_rust_hub.command`

Tasks:

1. Add explicit `--prep-trial` mode to the remote Generate runner.
2. Add explicit `--prep-trial` mode to the local runtime Generate runner.
3. Enable `XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP=1` and disable candidate audit
   mode so Node services reach `prepRoute`.
4. Require remote and local Rust/Node `prep match` logs.
5. Verify remote Bridge payload model/provider remains Node-selected.
6. Verify local runtime IPC model remains Node-selected.
7. Persist a combined `xhub.model_route_prep_trial_report.v1` artifact.
8. Keep `production_authority_change=false` and
   `selected_model_authority_enabled=false`.

Done:

- Done 2026-05-06: remote and local prep-trial runner modes passed isolated
  E2E.
- Done 2026-05-06: combined prep-trial report passed with 1 remote prep match,
  1 local prep match, zero warnings, Node authority preserved, and production
  authority unchanged.

### RHM-028 Model Route Prep Sustained Evidence

Priority: P0
Owner: Node Hub / tools
Source: RHM-026
Files:

- `tools/model_route_prep_sustained_runner.js`
- `tools/model_route_prep_sustained_runner.command`
- `docs/RHM_028_MODEL_ROUTE_PREP_SUSTAINED_EVIDENCE.md`
- `tools/package_rust_hub.command`

Tasks:

1. Repeat the combined RHM-026 prep trial across multiple cycles.
2. Persist each child RHM-026 report for auditability.
3. Persist a sustained `xhub.model_route_prep_sustained_report.v1` artifact.
4. Require total remote and local prep matches to meet thresholds.
5. Require zero prep warnings by default.
6. Require every child report to preserve Node-selected remote and local
   execution authority.
7. Keep `production_authority_change=false` and
   `selected_model_authority_enabled=false`.

Done:

- Done 2026-05-06: sustained prep evidence runner added with self-test,
  dry-run, per-cycle report persistence, and production-neutral report schema.

### RHM-031 Model Route Report Diagnostics

Priority: P0
Owner: xhubd / XT diagnostics
Source: RHM-028
Files:

- `crates/xhubd/src/model_bridge.rs`
- `crates/xhubd/src/main.rs`
- `docs/RHM_031_MODEL_ROUTE_REPORT_DIAGNOSTICS.md`

Tasks:

1. Add `model diagnostics` CLI command.
2. Add `GET /model/diagnostics` and `GET /model/route-diagnostics`.
3. Summarize latest authority-plan, prep-trial, sustained-prep, and
   candidate-evidence reports without returning raw stderr or env blocks.
4. Add `model_route_diagnostics_http=true` to `/ready`.
5. Add a browser status page link to `/model/diagnostics`.
6. Keep diagnostics read-only and production-neutral.

Done:

- Done 2026-05-06: read-only diagnostics returned latest report summaries with
  `ready=true`, zero observed authority changes, and zero Node authority
  failures.

## 5. Recommended Implementation Order

1. Done 2026-04-30: finish `RHM-002` and `RHM-004` inside `xhub-provider`.
2. Done 2026-04-30: add `RHM-003` trace fields while preserving compare
   normalization.
3. Done 2026-04-30: add `RHM-005` as a read-only `model inventory` CLI with
   remote rows and local `models_state.json` rows.
4. Done 2026-05-05: add `RHM-006` and `RHM-007` for deeper local model
   artifact/runtime readiness.
5. Done 2026-05-05: add `RHM-008` unified route decision.
6. Done 2026-05-05: add `RHM-009` model inventory shadow compare evidence.
7. Done 2026-05-05: wire `RHM-010` fixture/presentation parity into XT.
8. Done 2026-05-05: add the default-off live XT/Rust model inventory bridge.
9. Done 2026-05-05: add sustained Node/XT model inventory shadow evidence
   before any production authority switch.
10. Done 2026-05-06: add real-runtime and warm-daemon model inventory evidence
   mode.
11. Done 2026-05-06: expose read-only warm-daemon model route decisions.
12. Done 2026-05-06: add UI compatibility preservation contract before more
   Rust bridge cutovers.
13. Done 2026-05-06: add default-off Node model route authority prep bridge
   with Generate candidate audit and no execution/UI authority change.
14. Done 2026-05-06: add sustained model route candidate evidence runner before
   any selected-model authority switch.
15. Done 2026-05-06: add local runtime route candidate coverage.
16. Done 2026-05-06: add persisted combined remote/local candidate evidence
   reports before authority switch planning.
17. Done 2026-05-06: draft default-off selected-model authority planning from
   the persisted report, with rollback gates and no production authority
   change.
18. Done 2026-05-06: add a manual prep-trial smoke that enables
   `XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP=1` while proving Node-selected remote
   and local execution models remain authoritative.
19. Done 2026-05-06: repeat model-route prep evidence with a sustained report
   and per-cycle child reports.
20. Done 2026-05-06: expose latest plan/prep/sustained diagnostics without
   changing XT execution behavior.
21. Next: wire XT to consume the diagnostics as display-only status.

## 6. Validation Commands

Existing commands:

```bash
cargo test --workspace
bash "tools/provider_route_smoke.command" --model-id gpt-4o
bash "tools/provider_route_shadow_compare_runner.command" --runs 10 --expect-ready --expect-zero-mismatch
bash "tools/provider_route_generate_observe_runner.command" --runs 1 --concurrency 1 --enable-candidate-audit --max-generate-ms 3000
cargo run --bin xhubd -- model inventory --runtime-base-dir /tmp/xhub-empty-model-inventory --now-ms 1000
bash "tools/model_inventory_shadow_compare_smoke.command"
bash "tools/model_inventory_http_bridge_smoke.command"
bash "tools/model_inventory_shadow_compare_runner.command" --runs 3 --min-compare-reports 3 --expect-ready --expect-zero-mismatch
bash "tools/model_inventory_shadow_compare_runner.command" --use-existing-runtime --runtime-base-dir /path/to/runtime_base_dir --runs 10 --min-compare-reports 10 --expect-ready --expect-zero-mismatch
bash "tools/model_route_http_smoke.command" --timeout-ms 30000
bash "tools/model_route_generate_candidate_runner.command" --runs 2 --concurrency 1 --expect-ready --min-candidate-audits 2 --timeout-ms 45000
bash "tools/model_route_local_candidate_runner.command" --runs 2 --concurrency 1 --expect-ready --min-candidate-audits 2 --timeout-ms 45000
bash "tools/model_route_candidate_evidence_runner.command" --remote-runs 1 --local-runs 1 --concurrency 1 --expect-ready --timeout-ms 45000
bash "tools/model_route_authority_plan_runner.command" --remote-runs 1 --local-runs 1 --concurrency 1 --expect-ready --timeout-ms 45000
bash "tools/model_route_prep_trial_runner.command" --remote-runs 1 --local-runs 1 --concurrency 1 --expect-ready --timeout-ms 45000
bash "tools/model_route_prep_sustained_runner.command" --cycles 2 --remote-runs 1 --local-runs 1 --concurrency 1 --expect-ready --timeout-ms 45000
cargo run --bin xhubd -- model diagnostics --limit 1
curl -fsS "http://127.0.0.1:50151/model/diagnostics?limit=1"
cargo run --bin xhubd -- model readiness --min-compare-reports 0 --max-mismatches 0
node ../../x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_model_route_authority_bridge.test.js
node ../../x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_provider_route_authority_generate_hook.test.js
swift test --filter 'XTModelInventoryTruthPresentationTests|XTVisibleHubModelInventoryTests|XTRustModelInventoryProjectionTests|XTRustModelInventoryLiveBridgeTests|HubModelManagerFetchTests'
```

Planned commands:

```bash
cargo run --bin xhubd -- model inventory --runtime-base-dir /tmp/xhub-runtime
cargo run --bin xhubd -- model route --task-type summarize --required-capability text.summarize --model-id auto
```

## 7. Done Criteria For This Plan

This Rust plan is considered implemented when:

1. Rust provider routing matches Node/Swift on alias, quota, scope, and selected
   account decisions.
2. Rust can produce a remote + local model inventory snapshot without secrets.
3. Rust can produce a local runtime preflight result that fails closed.
4. Rust can produce a unified route decision for task/capability inputs.
5. Node/XT shadow compare evidence exists for route and inventory parity.
6. Package output contains this document and all related CLIs/runners.
