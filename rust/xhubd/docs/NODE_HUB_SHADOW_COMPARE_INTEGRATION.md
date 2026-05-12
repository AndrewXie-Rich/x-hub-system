# Node Hub Shadow Compare Integration

This is the first opt-in connection from the existing Node Hub to Rust Hub
scheduler evidence. It does not make Rust Hub authoritative.

## Node Hub Hook

Files in the existing Node Hub:

- `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_scheduler_shadow_compare.js`
- `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_scheduler_shadow_compare.test.js`
- `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_scheduler_shadow_compare_service_hook.test.js`
- `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/services.js`

`HubRuntime.GetSchedulerStatus` still returns the Node scheduler snapshot first.
After the response is sent, the opt-in hook can spawn the Rust Hub Node caller:

```text
Node Hub GetSchedulerStatus
  -> buildPaidAISchedulerSnapshot()
  -> callback(null, { paid_ai })
  -> maybeCompare(paid_ai) when env enabled
  -> tools/node_scheduler_shadow_compare.js
  -> xhubd scheduler compare
  -> rust_hub_shadow_compare_reports
```

## Environment

Default: disabled.

Enable:

```bash
export XHUB_RUST_SCHEDULER_SHADOW_COMPARE=1
export XHUB_RUST_HUB_ROOT="rust/xhubd"
```

Optional overrides:

```bash
export XHUB_RUST_HUB_RUNNER="rust/xhubd/tools/run_rust_hub.command"
export XHUB_RUST_SCHEDULER_SHADOW_COMPARE_SCRIPT="rust/xhubd/tools/node_scheduler_shadow_compare.js"
export XHUB_RUST_SCHEDULER_SHADOW_COMPARE_THROTTLE_MS=5000
export XHUB_RUST_SCHEDULER_SHADOW_COMPARE_TIMEOUT_MS=5000
export XHUB_RUST_SCHEDULER_SHADOW_COMPARE_VERBOSE=1
```

## Status Read Bridge

The first compatibility bridge is read-only. It lets Node Hub answer
`HubRuntime.GetSchedulerStatus` from Rust scheduler status when explicitly
enabled, while the existing Node in-memory scheduler remains the fallback.

Default: disabled.

Enable:

```bash
export XHUB_RUST_SCHEDULER_STATUS_READ=1
export XHUB_RUST_HUB_ROOT="rust/xhubd"
```

Optional overrides:

```bash
export XHUB_RUST_HUB_RUNNER="rust/xhubd/tools/run_rust_hub.command"
export XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY=1
export XHUB_RUST_SCHEDULER_STATUS_TIMEOUT_MS=5000
export XHUB_RUST_SCHEDULER_STATUS_HTTP=1
export XHUB_RUST_SCHEDULER_STATUS_HTTP_BASE_URL=http://127.0.0.1:50151
export XHUB_RUST_SCHEDULER_STATUS_HTTP_TIMEOUT_MS=750
export XHUB_RUST_SCHEDULER_STATUS_HTTP_FALLBACK_TO_CLI=1
export XHUB_RUST_SCHEDULER_STATUS_CACHE_MS=250
export XHUB_RUST_SCHEDULER_STATUS_VERBOSE=1
export XHUB_RUST_SCHEDULER_STATUS_MIN_COMPARE_REPORTS=10
export XHUB_RUST_SCHEDULER_STATUS_MAX_MISMATCHES=0
export XHUB_RUST_SCHEDULER_STATUS_MIN_LEASE_SHADOW_RUNS=1
export XHUB_RUST_SCHEDULER_STATUS_MAX_STALE_ACTIVE=0
export XHUB_RUST_SCHEDULER_STATUS_MAX_ORPHANED_LEASES=0
```

Behavior:

- disabled by default, with no production behavior change
- reads `xhubd scheduler status`, or `GET /scheduler/status` when HTTP is
  enabled
- uses async process execution on the Node side, so Rust status reads do not
  block the Hub event loop
- when `XHUB_RUST_SCHEDULER_STATUS_HTTP=1`, tries warm daemon
  `/scheduler/cutover-readiness` and `/scheduler/status` before CLI, with CLI
  fallback enabled by default
- coalesces concurrent reads and keeps a short TTL cache
  (`XHUB_RUST_SCHEDULER_STATUS_CACHE_MS`, default `250`) to avoid repeated Rust
  CLI process startup during rapid UI polling
- normalizes Rust JSON into the existing `PaidAISchedulerStatus` proto shape
- falls back to Node's in-memory scheduler status if Rust read fails
- when `XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY=1`, first requires
  `xhubd scheduler cutover-readiness` to return `ready=true`; readiness failure
  or `ready=false` falls back to the Node scheduler snapshot
- still sends the Node snapshot to shadow compare, so parity evidence remains
  Node-vs-Rust instead of Rust-vs-Rust

Validation:

```bash
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_scheduler_bridge.test.js
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_scheduler_shadow_compare_service_hook.test.js
bash "rust/xhubd/tools/scheduler_status_http_bridge_smoke.command"
```

## Provider Route Shadow Compare

Provider routing now has a read-only Rust shadow compare hook on
`HubProviderKeys.GetProviderKeyRouteDecision`. Node still builds and returns the
authoritative decision. After the response is sent, the hook can invoke:

```text
Node Hub GetProviderKeyRouteDecision
  -> buildProviderKeyRouteDecision()
  -> callback(null, { decision })
  -> maybeCompare(decision) when env enabled
  -> xhubd provider compare
  -> rust_hub_shadow_compare_reports component=provider_route
  -> log match/mismatch with report_id
```

Default: disabled.

Enable:

```bash
export XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE=1
export XHUB_RUST_HUB_ROOT="rust/xhubd"
```

Optional overrides:

```bash
export XHUB_RUST_HUB_RUNNER="rust/xhubd/tools/run_rust_hub.command"
export XHUB_RUST_PROVIDER_ROUTE_RUNNER="rust/xhubd/tools/run_rust_hub.command"
export XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_THROTTLE_MS=1000
export XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_TIMEOUT_MS=5000
export XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_MAX_IN_FLIGHT=2
export XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP=1
export XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP_BASE_URL=http://127.0.0.1:50151
export XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP_TIMEOUT_MS=750
export XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP_FALLBACK_TO_CLI=1
export XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_VERBOSE=1
```

Behavior:

- disabled by default, with no routing authority change
- runs after the gRPC response callback
- uses async HTTP or `execFile`, so Rust compare work does not block the Node
  event loop
- throttles per `(runtimeBaseDir, provider, modelId)` key
- compares normalized Node/Rust decision summaries
- writes append-only evidence through `xhubd provider compare`
- supports `xhubd provider reports` and `xhubd provider readiness`
- when `XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP=1`, posts
  `POST /provider/compare` to a warm `xhubd serve` daemon first and falls back
  to CLI by default
- does not expose API keys or move provider request payload construction into
  Rust yet

Validation:

```bash
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_provider_route_shadow_compare.test.js
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_provider_route_shadow_compare_service_hook.test.js
bash "rust/xhubd/tools/provider_route_smoke.command" --model-id gpt-4o
bash "rust/xhubd/tools/provider_route_http_shadow_compare_smoke.command"
bash "rust/xhubd/tools/provider_route_shadow_compare_smoke.command" --model-id gpt-4o
bash "rust/xhubd/tools/provider_route_shadow_compare_runner.command" --runs 10 --expect-ready --expect-zero-mismatch
```

The sustained runner verifies the read-only provider authority prep bridge once
readiness is true. This bridge is controlled by
`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP=1`, requires provider route readiness by
default, and returns only the selected `account_key` plus the Rust decision. It
does not fetch or pass provider secret material.

When authority prep is enabled, `HubProviderKeys.GetProviderKeyRouteDecision`
still returns the Node decision. After the gRPC response callback, the service
can asynchronously invoke the Rust authority prep bridge with the Node-selected
`account_key`. The bridge keeps
`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH=1` by default, so a
different Rust account returns fallback with
`rust_provider_route_authority_account_mismatch` instead of changing the Node
response. The service hook uses `prepRoute`, which is bounded by
`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_THROTTLE_MS` and
`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_MAX_IN_FLIGHT` so repeated
`GetProviderKeyRouteDecision` calls cannot fan out into unbounded Rust CLI
processes. When `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP=1` is enabled,
readiness and route checks try the warm `xhubd serve` HTTP endpoints first and
fall back to the CLI commands by default.

`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE=1` enables a separate observe-only
hook in the paid-model `HubAI.Generate` path. Node still resolves the provider
key and constructs the Bridge payload; the hook fire-and-forgets `xhubd provider
route`, compares the selected Node/Rust `account_key`, and logs match/mismatch
without throwing or blocking generation. This is hot-path telemetry only, not a
provider routing cutover. The observe path is guarded by
`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE_THROTTLE_MS` and
`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE_MAX_IN_FLIGHT` so busy Generate
traffic cannot start unbounded Rust CLI work.

Authority prep defaults to a Node/Rust account match gate via
`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH=1`. When a caller passes
the Node-selected `account_key`, Rust must select the same account or return
fallback with `rust_provider_route_authority_account_mismatch`. The observe-only
path explicitly skips this gate so it can still report mismatches as telemetry.

`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE=1` enables a separate candidate
audit event for the paid-model `HubAI.Generate` path. It is also default-off and
does not change provider routing. After Node selects its provider key, the hook
asks Rust for the candidate route asynchronously with the Node match gate
disabled, then appends audit event `ai.generate.provider_route_candidate` with
ext schema `xhub.rust_provider_route_candidate.audit.v1`. The event captures
Node/Rust selected account match state, Rust fallback/error reason codes,
provider/model scope, and decision counts. It intentionally does not include API
keys or Bridge provider secret payloads. Generate continues normally if the
candidate call or audit write fails.
If candidate audit is enabled, the Generate hook skips the separate observe
route call for that request. Candidate audit carries the same selected-account
match signal, so this avoids starting two Rust CLI processes for one Generate
request. The candidate bridge additionally supports a short TTL cache and
single-flight coalescing with
`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS` and
`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MAX_ENTRIES`; this reduces
duplicate Rust route work during bursts while preserving one audit event per
Generate request. Evidence runners set the candidate cache to `0` when they need
fresh route samples for readiness gates.

Authority prep environment:

```bash
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP=1
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE=1
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE=1
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH=1
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE_THROTTLE_MS=1000
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE_MAX_IN_FLIGHT=2
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP=1
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL=http://127.0.0.1:50151
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_TIMEOUT_MS=750
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI=1
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS=250
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MAX_ENTRIES=128
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY=1
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS=10
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MAX_MISMATCHES=0
```

Validation:

```bash
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_provider_route_authority_bridge.test.js
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_provider_route_authority_generate_hook.test.js
bash "rust/xhubd/tools/provider_route_generate_observe_runner.command" --runs 5 --concurrency 1 --max-generate-ms 3000
bash "rust/xhubd/tools/provider_route_generate_observe_runner.command" --runs 3 --concurrency 1 --enable-candidate-audit --expect-candidate-ready --min-candidate-audits 3 --observe-throttle-ms 0 --observe-max-in-flight 2 --max-generate-ms 3000
```

The candidate-audit runner emits `candidate_readiness` with schema
`xhub.provider_route_candidate_audit_readiness.v1`. `--expect-candidate-ready`
turns that report into a non-zero gate. Current checks require audit coverage,
stable ext schema, `ok` audit rows, known Node/Rust account match, no fallback,
no suspected provider secret leakage, and Generate latency under
`--max-generate-ms`.

Combined provider route cutover readiness:

```bash
bash "rust/xhubd/tools/provider_route_cutover_readiness_runner.command" --shadow-runs 3 --candidate-runs 3 --expect-ready
```

This emits `xhub.provider_route_cutover_readiness.v1` and combines provider
shadow compare readiness, authority prep same-account selection, fail-closed
account mismatch probing, the `GetProviderKeyRouteDecision` service-boundary
prep hook, candidate audit readiness, and Generate latency. It is still
evidence-only; it does not enable provider routing authority in the Node Hub.

Provider authority dry-run plan:

```bash
bash "rust/xhubd/tools/provider_route_authority_plan_runner.command" --shadow-runs 3 --candidate-runs 3 --expect-ready
```

This emits `xhub.provider_route_authority_dry_run_plan.v1`. It lists the env
vars for a prep-only manual trial, rollback env vars to unset, and actions
blocked until a future explicit cutover. The plan always keeps Node as provider
routing authority.

## Validation

```bash
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_scheduler_bridge.test.js
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_scheduler_shadow_compare.test.js
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_scheduler_shadow_compare_service_hook.test.js
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_provider_route_shadow_compare.test.js
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_provider_route_shadow_compare_service_hook.test.js
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_provider_route_authority_generate_hook.test.js
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_provider_route_authority_bridge.test.js
bash "rust/xhubd/tools/provider_route_generate_observe_runner.command" --runs 5 --concurrency 1 --max-generate-ms 3000
bash "rust/xhubd/tools/provider_route_generate_observe_runner.command" --runs 3 --concurrency 1 --enable-candidate-audit --expect-candidate-ready --min-candidate-audits 3 --observe-throttle-ms 0 --observe-max-in-flight 2 --max-generate-ms 3000
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/supervisor_control_plane_service_api.test.js
```

Rust Hub validation:

```bash
node "rust/xhubd/tools/node_scheduler_shadow_compare.js" --self-test
bash "rust/xhubd/tools/run_rust_hub.command" scheduler compare \
  --node-in-flight-total 0 \
  --node-queue-depth 0 \
  --node-oldest-queued-ms 0
bash "rust/xhubd/tools/run_rust_hub.command" scheduler reports --limit 20
```

One-shot smoke using the real Node Hub service handler:

```bash
node "rust/xhubd/tools/node_hub_shadow_compare_smoke.js" --timeout-ms 15000
```

The smoke creates a temporary Node Hub DB/runtime dir, enables
`XHUB_RUST_SCHEDULER_SHADOW_COMPARE=1`, invokes `HubRuntime.GetSchedulerStatus`,
waits for the Rust report count to increase, and prints the before/after report
summary.

Continuous evidence collection:

```bash
node "rust/xhubd/tools/node_hub_shadow_compare_smoke.js" \
  --runs 50 \
  --interval-ms 1000 \
  --timeout-ms 15000 \
  --expect-zero-mismatch
```

The smoke waits for one new Rust report after each Node
`GetSchedulerStatus` call. The final JSON includes `reports_added` with total,
matched, and mismatched counts.

## Live Runner

Use the runner when you want Node Hub to run normally with the opt-in Rust
shadow compare hook enabled, while Rust Hub reports are printed periodically:

```bash
node "rust/xhubd/tools/node_hub_shadow_compare_runner.js" \
  --duration-ms 60000 \
  --report-interval-ms 5000 \
  --hub-host 127.0.0.1 \
  --hub-port 55051 \
  --hub-db-path /tmp/xhub-runner.sqlite3 \
  --runtime-base-dir /tmp/xhub-runner-runtime \
  --pairing-enable 0 \
  --expect-zero-mismatch
```

The runner starts `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/server.js`
unless `--no-start` is passed. It does not generate traffic by itself; new
compare reports appear when real or smoke traffic calls
`HubRuntime.GetSchedulerStatus`.

Monitor only, without starting Node Hub:

```bash
node "rust/xhubd/tools/node_hub_shadow_compare_runner.js" \
  --no-start \
  --duration-ms 1000 \
  --report-interval-ms 500 \
  --expect-zero-mismatch
```

If the runner started Node Hub and the process exits unexpectedly during the
monitor window, the runner exits non-zero even when compare reports have no
mismatch. This keeps CI and packaging checks from accepting a dead Node Hub
process as a clean run.

## Lease Shadow Bridge

The first write-side bridge is still non-authoritative. It mirrors Node paid AI
slot lifecycle events into Rust scheduler tables so status compare can be tested
against real traffic. Node remains the execution authority.

Default: disabled.

Enable:

```bash
export XHUB_RUST_SCHEDULER_LEASE_SHADOW=1
export XHUB_RUST_HUB_ROOT="rust/xhubd"
```

Optional overrides:

```bash
export XHUB_RUST_HUB_RUNNER="rust/xhubd/tools/run_rust_hub.command"
export XHUB_RUST_SCHEDULER_LEASE_SHADOW_TIMEOUT_MS=5000
export XHUB_RUST_SCHEDULER_LEASE_SHADOW_OWNER=node-hub-paid-ai-shadow
export XHUB_RUST_SCHEDULER_LEASE_SHADOW_DURATION_MS=300000
export XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP=0
export XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_BASE_URL=http://127.0.0.1:50151
export XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_TIMEOUT_MS=750
export XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_FALLBACK_TO_CLI=1
export XHUB_RUST_SCHEDULER_LEASE_SHADOW_VERBOSE=1
```

Mirrored lifecycle:

- immediate Node slot: `scheduler enqueue` -> `scheduler acquire-run`
- queued Node request: `scheduler enqueue`
- Node queue drain: `scheduler acquire-run`
- Node slot release: `scheduler release --outcome completed`
- Node cancel/queue timeout before slot: `scheduler cancel`

The bridge serializes its Rust mirror calls and never blocks Node's scheduler
decision. By default it uses the Rust CLI. When
`XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP=1`, it prefers a warm `xhubd serve`
daemon and posts to `/scheduler/enqueue`, `/scheduler/acquire-run`,
`/scheduler/release`, and `/scheduler/cancel`; CLI fallback is enabled by
default through `XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_FALLBACK_TO_CLI=1`.
If Rust mirroring fails, Node continues on its existing path and logs a warning.

Validation:

```bash
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_scheduler_lease_shadow_bridge.test.js
bash "rust/xhubd/tools/scheduler_lease_shadow_http_bridge_smoke.command"
bash "rust/xhubd/tools/run_rust_hub.command" scheduler lease-shadow-report --limit 20
```

Healthy output has `stale_active=0`, `orphaned_leases=0`, and terminal mirrored
runs in `completed`, `failed`, or `canceled` rather than long-lived `queued` or
`leased`.

Cutover readiness gate:

```bash
bash "rust/xhubd/tools/run_rust_hub.command" scheduler cutover-readiness
```

The readiness gate combines scheduler compare evidence and lease shadow
evidence. It is intentionally conservative: the JSON can have `ok=true` and
`ready=false` at the same time. Only `ready=true` should be treated as a cutover
permission signal.

Automated evidence collection:

```bash
node "rust/xhubd/tools/scheduler_cutover_readiness_runner.js" \
  --runs 3 \
  --expect-ready \
  --expect-zero-mismatch
```

The runner calls the real Node Hub `GetSchedulerStatus` service handler to add
shadow compare reports, mirrors one paid AI lease shadow lifecycle per
iteration, and reads `scheduler cutover-readiness` after each round. It stops
early when `ready=true` unless `--continue-after-ready` is set.

## Cutover Rule

Do not switch authority based on a single clean compare. Collect sustained
`match_result=match` evidence under realistic traffic and inspect mismatch rows
before enabling any Rust scheduler write authority from Node.

Report inspection:

```bash
bash "rust/xhubd/tools/run_rust_hub.command" scheduler reports --limit 50
```

## Authority Bridge

The authority bridge is the first opt-in path where Node can ask Rust to own a
paid AI slot lifecycle. It is still guarded and reversible: default is disabled,
readiness is required by default, and Node falls back to its existing in-memory
queue when Rust is not ready or unavailable.

Enable:

```bash
export XHUB_RUST_SCHEDULER_AUTHORITY=1
export XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY=1
export XHUB_RUST_SCHEDULER_STATUS_READ=1
export XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY=1
export XHUB_RUST_HUB_ROOT="rust/xhubd"
```

Optional overrides:

```bash
export XHUB_RUST_SCHEDULER_AUTHORITY_OWNER=node-hub-paid-ai-authority
export XHUB_RUST_SCHEDULER_AUTHORITY_LEASE_DURATION_MS=300000
export XHUB_RUST_SCHEDULER_AUTHORITY_TIMEOUT_MS=5000
export XHUB_RUST_SCHEDULER_AUTHORITY_HTTP=1
export XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL=http://127.0.0.1:50151
export XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_TIMEOUT_MS=750
export XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_FALLBACK_TO_CLI=1
export XHUB_RUST_SCHEDULER_AUTHORITY_POLL_MS=100
export XHUB_RUST_SCHEDULER_AUTHORITY_READINESS_CACHE_MS=1000
export XHUB_RUST_SCHEDULER_AUTHORITY_FALLBACK_ON_ERROR=1
export XHUB_RUST_SCHEDULER_AUTHORITY_ALLOW_ACTIVE_RUNS=1
```

Behavior:

- calls `xhubd scheduler cutover-readiness` before authority use when
  `XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY=1`
- when `XHUB_RUST_SCHEDULER_AUTHORITY_HTTP=1`, tries warm daemon
  `/scheduler/cutover-readiness`, `/scheduler/claim`, `/scheduler/release`,
  and `/scheduler/cancel` before CLI, with CLI fallback enabled by default
- passes `--allow-active-runs` to the runtime readiness check by default, so
  normal in-flight Rust authority leases do not force concurrent requests back
  to Node's in-memory queue
- calls `xhubd scheduler claim` to perform idempotent enqueue and fair lease
  attempt in one Rust transaction
- polls `claim` with the same idempotency key while waiting for capacity
- calls `scheduler release` when the remote AI slot completes
- calls `scheduler cancel` on cancel or queue timeout
- falls back to the existing Node queue when Rust is disabled, missing, or not
  ready

Validation:

```bash
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_scheduler_authority_bridge.test.js
bash "rust/xhubd/tools/scheduler_authority_http_bridge_smoke.command"
bash "rust/xhubd/tools/scheduler_authority_runner.command" --runs 1 --timeout-ms 45000
bash "rust/xhubd/tools/scheduler_authority_runner.command" --runs 1 --concurrency 3 --bridge-response-delay-ms 3000 --timeout-ms 70000 --expect-queued
bash "rust/xhubd/tools/scheduler_authority_runner.command" --scenario queued-cancel --bridge-response-delay-ms 3000 --timeout-ms 70000
bash "rust/xhubd/tools/scheduler_authority_runner.command" --scenario queued-timeout --timeout-ms 70000
bash "rust/xhubd/tools/node_hub_authority_live_runner.command" --runs 1 --timeout-ms 45000
bash "rust/xhubd/tools/node_hub_authority_live_runner.command" --runs 3 --concurrency 3 --bridge-response-delay-ms 2500 --timeout-ms 90000 --expect-queued
bash "rust/xhubd/tools/node_hub_authority_live_runner.command" --scenario queued-cancel --timeout-ms 70000
bash "rust/xhubd/tools/node_hub_authority_live_runner.command" --scenario queued-timeout --timeout-ms 70000
```

The authority runner creates temporary Node and Rust databases, writes a fake
Bridge status/response pair through the same filesystem IPC used by production
Bridge, and invokes the real Node `HubAI.Generate` service handler. It verifies
that the paid model request completes, Rust records the authority run as
`completed`, and `scheduler status` returns a clean empty queue after release.
With `--concurrency 3 --expect-queued`, it also verifies Rust per-scope queueing
under pressure. With `--scenario queued-cancel` and
`--scenario queued-timeout`, it verifies queued requests terminate through the
Rust `cancel` path and leave no leaked in-flight or queued state.

For a process-level smoke, `node_hub_authority_live_runner.command` starts the
real Node Hub gRPC server, uses a shared SQLite DB for Node and Rust scheduler
state, writes a temporary trusted client profile, and sends gRPC
`HubAI.Generate` requests. With `--concurrency 3 --expect-queued`, it verifies
the production gRPC boundary still observes Rust per-scope queueing and drains
cleanly. With `--scenario queued-cancel` and `--scenario queued-timeout`, it
also verifies queued terminal paths through real gRPC stream cancellation and
queue timeout.
