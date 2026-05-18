# Provider Route CLI

`xhubd provider route` is the Rust shadow implementation for provider/account
routing. `xhubd provider compare` persists Node-vs-Rust route evidence for
readiness checks. Both read the existing Node Hub provider key store shape from
`$HUB_RUNTIME_BASE_DIR/hub_provider_keys.json` or from `--runtime-base-dir`.

This command is default-off for production routing. It only returns a JSON
decision so Node, CI, or packaged smoke tools can compare Rust routing against
the existing Node provider router before any cutover.

## Commands

```bash
bash "tools/provider_route_smoke.command"
bash "tools/provider_route_http_smoke.command"
bash "tools/provider_route_http_bridge_smoke.command"
bash "tools/provider_route_http_shadow_compare_smoke.command"
bash "tools/provider_route_smoke.command" --model-id gpt-4o
bash "tools/provider_route_smoke.command" --model-id claude-3.5-sonnet --provider claude
bash "tools/provider_route_smoke.command" --request-json '{"model_id":"gpt-4o","provider":"openai","now_ms":1000}'
bash "tools/provider_route_shadow_compare_smoke.command" --model-id gpt-4o
bash "tools/provider_route_shadow_compare_runner.command" --runs 10 --expect-ready --expect-zero-mismatch
bash "tools/provider_route_generate_observe_runner.command" --runs 5 --concurrency 1 --max-generate-ms 3000
bash "tools/provider_route_generate_observe_runner.command" --runs 3 --concurrency 1 --enable-candidate-audit --expect-candidate-ready --min-candidate-audits 3 --observe-throttle-ms 0 --observe-max-in-flight 2 --max-generate-ms 3000
bash "tools/provider_route_cutover_readiness_runner.command" --shadow-runs 3 --candidate-runs 3 --expect-ready
bash "tools/provider_route_authority_plan_runner.command" --shadow-runs 3 --candidate-runs 3 --expect-ready
bash "tools/provider_codex_oauth_refresh_smoke.command"
bash "tools/provider_route_smoke.command" --model-id openai/gpt5.5
```

Direct form:

```bash
cargo run --bin xhubd -- provider route --model-id gpt-4o
cargo run --bin xhubd -- provider route --model-id gpt-4o --runtime-base-dir /path/to/runtime
cargo run --bin xhubd -- provider compare --node-decision-json '{"requested_provider":"openai","requested_model_id":"gpt-4o","selected_account_key":"","fallback_reason_code":"no_keys_for_provider","available_count":0,"total_count":0,"candidates":[]}'
cargo run --bin xhubd -- provider reports --limit 20
cargo run --bin xhubd -- provider readiness --min-compare-reports 10 --max-mismatches 0
cargo run --bin xhubd -- provider plan-codex-oauth-refresh --runtime-base-dir /path/to/runtime --include-skipped
cargo run --bin xhubd -- provider refresh-codex-oauth --runtime-base-dir /path/to/runtime --account-key codex:example
```

Daemon HTTP form:

```bash
XHUB_RUST_HUB_HTTP_PORT=50151 HUB_RUNTIME_BASE_DIR=/path/to/runtime cargo run --bin xhubd -- serve
curl -fsS "http://127.0.0.1:50151/provider/route?model_id=gpt-4o&provider=openai"
curl -fsS -X POST "http://127.0.0.1:50151/provider/compare" -H "content-type: application/json" --data '{"model_id":"gpt-4o","provider":"openai","node_decision":{"requested_provider":"openai","requested_model_id":"gpt-4o","selected_account_key":"","fallback_reason_code":"no_keys_for_provider","available_count":0,"total_count":0,"candidates":[]}}'
curl -fsS "http://127.0.0.1:50151/provider/reports?limit=20"
curl -fsS "http://127.0.0.1:50151/provider/readiness?min_compare_reports=10&max_mismatches=0&limit=20"
curl -fsS -X POST "http://127.0.0.1:50151/provider/oauth-refresh/codex/plan" -H "content-type: application/json" --data '{"runtime_base_dir":"/path/to/runtime","include_skipped":true}'
curl -fsS -X POST "http://127.0.0.1:50151/provider/oauth-refresh/codex" -H "content-type: application/json" --data '{"runtime_base_dir":"/path/to/runtime","account_key":"codex:example"}'
```

`GET /provider/route`, `POST /provider/compare`, `GET /provider/reports`, and
`GET /provider/readiness` return the same `xhub.provider_bridge.v1` envelopes as
their CLI equivalents. `POST /provider/compare` accepts `node_decision` or
`node_decision_json`, plus optional `runtime_base_dir`, `model_id`, `provider`,
and `now_ms`. They are still shadow/evidence only; they let Node bridge hooks
reuse a warm `xhubd` daemon instead of spawning one Rust CLI process for each
route/readiness/compare check.

Node bridge opt-in for the warm daemon path:

```bash
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP=1
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL=http://127.0.0.1:50151
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_TIMEOUT_MS=750
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI=1
```

The bridge still requires the existing prep/observe/candidate flags. HTTP only
changes how Rust route and readiness evidence is fetched; it does not make Rust
production provider authority.

Node shadow compare can also use the warm daemon instead of CLI process starts:

```bash
export XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE=1
export XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP=1
export XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP_BASE_URL=http://127.0.0.1:50151
export XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP_TIMEOUT_MS=750
export XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP_FALLBACK_TO_CLI=1
```

This path is default-off. With fallback disabled, the comparer can still run
without a CLI runner as long as `xhubd serve` is healthy.

## Output

The CLI writes one JSON object:

```json
{
  "schema_version": "xhub.provider_bridge.v1",
  "ok": true,
  "command": "route",
  "decision_schema_version": "xhub.provider_route_decision.v1",
  "decision": {
    "requested_provider": "openai",
    "requested_model_id": "gpt-4o",
    "resolved_provider": "openai",
    "pool_id": "",
    "strategy": "fill-first",
    "routing_strategy": "fill-first",
    "selection_scope": "openai::gpt-4o",
    "selected_account_key": "",
    "fallback_reason_code": "no_keys_for_provider",
    "available_count": 0,
    "total_count": 0,
    "candidates": [],
    "updated_at_ms": 1000
  }
}
```

`provider compare` writes append-only evidence into
`rust_hub_shadow_compare_reports` with component `provider_route`. `provider
reports` summarizes that evidence, and `provider readiness` returns
`ready=true` only when the evidence count and mismatch thresholds pass.

## Current Routing Semantics

- Infer provider from model ID using the Node Hub provider/model map.
- Canonicalize common OpenAI GPT aliases for routing and comparison:
  `GPT5.5`, `gpt5.5`, and `openai/gpt5.5` resolve to `gpt-5.5`.
- Support shared OpenAI/Codex pools.
- Prefer model-restricted accounts that match the requested model.
- Match account `models` and per-model `model_states` by canonical and compact
  aliases, including `models/...` and provider-prefixed IDs.
- Skip disabled, missing-auth, expired, cooldown, blocked, stale, and
  quota-exhausted accounts.
- Treat `quota.next_recover_at_ms` as a cooldown source alongside
  `quota.cooldown_until_ms`, `error_state.next_retry_at_ms`, and
  `refresh_state.next_refresh_at_ms`.
- Expose route-level trace fields `pool_id`, `strategy`, `routing_strategy`,
  and `selection_scope`.
- Expose candidate trace fields including `pool_id`, `provider_host`,
  `wire_api`, `status_message`, `retry_at_ms`, `next_retry_at_ms`,
  `retry_at_source`, `models`, `source_owners`, and
  `required_refresh_metadata`.
- Score `fill-first`, `priority`, and `quota-aware` strategies.
- Use deterministic tie-break by score then `account_key`.
- Normalize `requested_model_id`, `selection_scope`, and `model_state_key`
  during Node-vs-Rust compare so harmless alias presentation differences do
  not count as parity failures.
- Fail closed with explicit `fallback_reason_code` when no provider or account
  can be selected.

The command intentionally does not return secret key material. Production
request payload construction remains in Node until provider authority cutover is
explicitly gated.

## Codex OAuth Refresh

`provider plan-codex-oauth-refresh` and
`POST /provider/oauth-refresh/codex/plan` are read-only planner surfaces for
Codex/OpenAI OAuth accounts in `hub_provider_keys.json`. They return due
account keys and reason codes such as `token_expired`, `expires_soon`,
`retry_due`, `auth_missing`, and `not_due`; they do not return access tokens,
refresh tokens, or provider request payloads.

`provider refresh-codex-oauth` and `POST /provider/oauth-refresh/codex` perform
one account refresh through the OpenAI/Codex token endpoint and then delegate
all store mutation to the OAuth apply/failure writers. Terminal provider
failures such as `invalid_grant` and `refresh_token_reused` fail closed with no
retry, while retryable transport failures keep `retry_at_source=refresh` and a
cooldown. The mock smoke for this flow is:

```bash
bash "tools/provider_codex_oauth_refresh_smoke.command"
```

## Generate Hot-Path Evidence

The Node Hub integration has two paid-model `HubAI.Generate` evidence hooks.
Both are disabled by default and leave Node as the production provider-routing
authority.

`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE=1` fire-and-forgets a Rust route
check after Node selects its provider key. It compares only selected
`account_key` truth, logs match/mismatch, and is bounded by
`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE_THROTTLE_MS` and
`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE_MAX_IN_FLIGHT`.

`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE=1` appends audit event
`ai.generate.provider_route_candidate` with ext schema
`xhub.rust_provider_route_candidate.audit.v1`. The event records Node/Rust
selected account match state, fallback/error reason codes, provider/model
scope, and decision counts. It does not include provider API keys or Bridge
secret payloads. The candidate call is asynchronous and ignored on failure, so
it cannot block or change the Generate response.
When candidate audit is enabled, the Generate hook skips the separate observe
call for that request. Candidate audit already records the Node/Rust selected
account match, and avoiding the duplicate observe call halves Rust CLI process
starts on the candidate-readiness hot path. The candidate bridge also has a
short TTL cache plus single-flight coalescing controlled by
`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS` and
`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MAX_ENTRIES`. This can
merge concurrent identical route checks and briefly reuse recent audit-only
decisions; the readiness runner disables that cache to keep its gate based on
fresh Rust route samples.

The `provider_route_generate_observe_runner.command --enable-candidate-audit`
smoke uses a temporary isolated DB and `HUB_AUDIT_LEVEL=full_content` only so
the runner can verify the audit schema and scan the ext JSON for accidental
secret leakage.

With `--expect-candidate-ready`, the runner also gates the final
`candidate_readiness` report:

```json
{
  "schema_version": "xhub.provider_route_candidate_audit_readiness.v1",
  "component": "provider_route",
  "decision": "ready",
  "ready": true,
  "audit": {
    "expected": 3,
    "total": 3,
    "account_mismatch": 0,
    "fallback": 0,
    "secret_leak": 0
  }
}
```

The readiness report checks event coverage, ext schema, audit `ok`, known
Node/Rust selected account match, fallback count, suspected secret leakage, and
Generate latency under `--max-generate-ms`.

## Combined Cutover Readiness

`provider_route_cutover_readiness_runner.command` combines the two provider
evidence planes into one report. It runs:

- provider shadow compare/readiness
- readiness-gated authority prep and account mismatch probe
- `GetProviderKeyRouteDecision` service-boundary authority prep hook
- paid Generate candidate audit/readiness

The final report uses schema `xhub.provider_route_cutover_readiness.v1`:

```json
{
  "schema_version": "xhub.provider_route_cutover_readiness.v1",
  "component": "provider_route",
  "decision": "ready",
  "ready": true,
  "provider_shadow": {
    "reports_added": { "total": 3, "matched": 3, "mismatched": 0 },
    "readiness_ready": true,
    "authority_prep_selected": true,
    "mismatch_gate_ok": true,
    "service_hook_ok": true
  },
  "candidate_audit": {
    "readiness_ready": true,
    "total": 3,
    "account_mismatch": 0,
    "fallback": 0,
    "secret_leak": 0
  }
}
```

This runner is a cutover gate only. It does not enable provider route authority
in production and does not change the Node Bridge payload.

`GetProviderKeyRouteDecision` also has an opt-in service-boundary prep hook.
With `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP=1`, the service returns the Node
decision first, then asynchronously asks Rust for a readiness-gated prep route
using the Node-selected `account_key`. A Rust account mismatch falls back through
`rust_provider_route_authority_account_mismatch`; it does not alter the gRPC
response. The hook is non-blocking and bounded by
`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_THROTTLE_MS` plus
`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_MAX_IN_FLIGHT` to keep frequent route
decision checks from creating unbounded Rust CLI work.
The sustained shadow runner records this as `authority_prep.service_hook`, and
the combined cutover readiness report requires `provider_shadow.service_hook_ok`
to be true.

## Authority Dry-Run Plan

`provider_route_authority_plan_runner.command` runs the combined cutover
readiness gate and emits a default-off prep-only plan. The plan uses schema
`xhub.provider_route_authority_dry_run_plan.v1` and includes:

- `production_authority_change=false`
- `node_remains_provider_authority=true`
- environment variables for a manual authority-prep trial
- rollback variables to unset
- actions blocked until a later explicit cutover

Example:

```bash
bash "tools/provider_route_authority_plan_runner.command" --shadow-runs 3 --candidate-runs 3 --expect-ready
```

This command is intentionally not a switch. It only tells operators whether the
prep-only path is ready to test and what guardrails must stay enabled.
