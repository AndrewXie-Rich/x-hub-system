# Rust Hub Execution Plan

Status: active
Target root: `/Users/andrew.xie/Documents/AX/rust/rust hub`
Source system: `/Users/andrew.xie/Documents/AX/x-hub-system`
Contract source: `x-hub-system/protocol/hub_protocol_v1.proto`

## 0. Operating Rules

This plan is executable by file, command, and done criteria. The Rust Hub must
start as a side-by-side shadow daemon and must not weaken the current X-Terminal
fallback semantics.

Hard rules:

- All Rust Hub files live under `rust/rust hub`.
- The existing Node Hub remains the production authority until explicit cutover.
- Proto and JSON contracts are shared truth. Rust must not invent incompatible
  field names, error codes, or fallback behavior.
- `grpc` mode remains fail-closed from X-Terminal's point of view.
- `auto` mode may fall back only through the already-defined route state machine.
- Hub remains authority for grant, audit, kill-switch, skills, provider routing,
  and durable memory truth.
- Python remains the local ML runtime for embeddings, rerankers, vision, audio,
  and experimental scoring.
- Third-party skill code is not executed in Hub Core.

## 1. Target Workspace Layout

Create and maintain this layout:

```text
rust/rust hub/
  Cargo.toml
  README.md
  config/default.toml
  assets/proto/hub_protocol_v1.proto
  docs/RUST_HUB_EXECUTION_PLAN.md
  migrations/
  tools/
    build_rust_hub.command
    run_rust_hub.command
    package_rust_hub.command
  crates/
    xhubd/
    xhub-core/
    xhub-contract/
    xhub-db/
    xhub-scheduler/
    xhub-policy/
    xhub-memory/
    xhub-skills/
    xhub-provider/
    xhub-runtime/
```

## 2. Phase 0: Workspace And Shadow Daemon

Goal: create a Rust workspace that can be built and run independently.

Tasks:

- RH-0001: Create workspace files.
  - Files: `Cargo.toml`, crate `Cargo.toml` files.
  - Done: `cargo metadata` works after Rust toolchain is installed.
- RH-0002: Mirror the proto contract.
  - Files: `assets/proto/hub_protocol_v1.proto`.
  - Done: doctor reports service/message/rpc counts from the mirrored proto.
- RH-0003: Add command wrappers.
  - Files: `tools/build_rust_hub.command`, `tools/run_rust_hub.command`,
    `tools/package_rust_hub.command`.
  - Done: wrappers fail with a clear `cargo not found` message if Rust is absent.
- RH-0004: Add `xhubd doctor`.
  - Files: `crates/xhubd/src/main.rs`, `crates/xhub-core`, `crates/xhub-contract`.
  - Done: prints target root, toolchain status, proto status, config defaults.
- RH-0005: Add `xhubd serve`.
  - Files: `crates/xhubd/src/main.rs`.
  - Done: starts a shadow HTTP server with `/health`,
    `/runtime/scheduler_status`, and `/contract/proto_summary`.

Validation commands:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/build_rust_hub.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" doctor
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" serve
```

Current environment:

- `rustc`, `cargo`, and `protoc` are installed through Homebrew.
- Phase 0 validation is complete.

## 3. Phase 1: Contract-Compatible gRPC Shadow

Goal: expose a Rust gRPC server that can answer a narrow compatible surface while
Node Hub remains the production implementation.

Tasks:

- RH-0101: Add `tonic/prost` proto generation.
  - Files: `crates/xhub-contract/build.rs`, `crates/xhub-contract/src/lib.rs`.
  - Done: generated Rust types compile from `assets/proto/hub_protocol_v1.proto`.
- RH-0102: Implement health and reflection-free service registration scaffold.
  - Files: `crates/xhubd/src/grpc_server.rs`.
  - Done: server binds to `XHUB_RUST_HUB_GRPC_PORT`, separate from Node `HUB_PORT`.
- RH-0103: Implement `HubRuntime.GetSchedulerStatus` shadow response.
  - Files: `crates/xhub-scheduler`, `crates/xhubd`.
  - Done: response matches proto field names and uses empty/fail-closed defaults.
- RH-0104: Implement `HubAudit.ListAuditEvents` read-only shadow response.
  - Files: `crates/xhub-db`, `crates/xhubd`.
  - Done: reads existing `audit_events` only when configured with a real DB path.
- RH-0105: Add compatibility tests.
  - Files: `crates/xhubd/tests/`.
  - Done: tests assert stable enum/error/source strings used by XT.

Validation commands:

```bash
cargo test --workspace
cargo run -p xhubd -- doctor
cargo run -p xhubd -- serve --grpc
```

## 4. Phase 2: Scheduler Truth Migration

Goal: move high-churn scheduler state into Rust while keeping Node as a fallback
facade.

Tasks:

- RH-0201: Add scheduler schema.
  - Files: `migrations/0002_scheduler_truth.sql`, `crates/xhub-db`.
  - Tables: `run_queue`, `run_leases`, `scheduler_events`,
    `scheduler_scope_counters`.
  - Done: migrations are idempotent and forward-only.
- RH-0202: Implement paid AI fair queue in Rust.
  - Files: `crates/xhub-scheduler`.
  - Done: supports global concurrency, per-scope concurrency, queue limit,
    timeout, cancel, and snapshot.
  - Current status: first DB-backed implementation complete inside the Rust
    scheduler crate; `xhubd scheduler-smoke` validates enqueue/acquire/release;
    no production cutover yet. `xhubd scheduler claim` now provides an atomic
    enqueue-and-fair-lease primitive for the future authority switch, avoiding
    multiple Node-composed bridge calls on the hot path.
- RH-0203: Add `HubRuntime.GetSchedulerStatus` authoritative path.
  - Files: `crates/xhubd`, `crates/xhub-scheduler`.
  - Done: XT scheduler panel can read Rust snapshot without polling six files.
  - Current status: compatible DB-backed read path complete for Rust scheduler
    rows; mutating runtime RPCs remain shadow/fail-closed.
- RH-0206: Add scheduler bridge and shadow-compare evidence.
  - Files: `crates/xhubd/src/scheduler_bridge.rs`,
    `migrations/0003_shadow_compare_reports.sql`,
    `docs/SCHEDULER_BRIDGE_CLI.md`,
    `docs/NODE_HUB_SHADOW_COMPARE_INTEGRATION.md`,
    `tools/node_scheduler_shadow_compare.js`,
    `tools/node_hub_shadow_compare_smoke.js`,
    `tools/node_hub_shadow_compare_runner.js`,
    Node Hub opt-in hook in `x-hub-system/x-hub/grpc-server/hub_grpc_server/src`.
  - Done: Node can invoke JSON bridge commands for enqueue/acquire/release and
    persist scheduler parity reports before cutover.
  - Current status: existing Node Hub can opt in with
    `XHUB_RUST_SCHEDULER_SHADOW_COMPARE=1`; default remains off. Evidence can
    be inspected with `xhubd scheduler reports`.
- RH-0204: Add aggregate runtime snapshot.
  - Proto change required before implementation.
  - Proposed RPC: `HubRuntime.GetRuntimeSnapshot`.
  - Snapshot includes scheduler, pending grants, review queue, connector ingress,
    operator commands, and command results.
- RH-0205: Add Node compatibility bridge.
  - Files in Node repo only after Rust side is stable.
  - Done: Node can call Rust scheduler locally and expose old RPCs unchanged.
  - Current status: first read-only bridge complete for
    `HubRuntime.GetSchedulerStatus`, behind
    `XHUB_RUST_SCHEDULER_STATUS_READ=1`. The Node bridge uses async process
    execution so status polling does not block the Hub event loop while Rust CLI
    reads are in flight; it also coalesces concurrent reads and uses a short TTL
    cache to reduce rapid UI polling overhead. The read bridge can additionally
    require `xhubd scheduler cutover-readiness` to return `ready=true` before
    using Rust status when `XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY=1`;
    readiness failure or `ready=false` falls back to Node status. First opt-in
    scheduler authority bridge is complete behind
    `XHUB_RUST_SCHEDULER_AUTHORITY=1`; it uses readiness-gated
    `scheduler claim` for paid AI slot ownership and falls back to Node when
    Rust is disabled, missing, or not ready. First write-side shadow mirror is
    complete behind
    `XHUB_RUST_SCHEDULER_LEASE_SHADOW=1`; it mirrors Node paid AI
    enqueue/acquire/release/cancel into Rust but does not make Rust
    authoritative. Rust evidence summary is available through
    `xhubd scheduler lease-shadow-report`; a fail-closed readiness gate is
    available through `xhubd scheduler cutover-readiness`. Automated compare
    and lease evidence collection is available through
    `tools/scheduler_cutover_readiness_runner.js`. Full Node paid AI Generate
    authority-path smoke is available through
    `tools/scheduler_authority_runner.js`, which uses temporary DBs and fake
    Bridge IPC to verify Rust claim/release without network calls. The authority
    runner also supports concurrent same-scope requests to verify Rust queueing
    and release cleanup under pressure.

Do not migrate yet:

- Full `HubAI.Generate` provider execution.
- Provider key OAuth.
- Pairing HTTP install flow.

## 5. Phase 3: Policy, Grant, Audit, Kill-Switch

Goal: move fail-closed security-critical decisions into typed Rust modules.

Tasks:

- RH-0301: Model capability and kill-switch aliases.
  - Files: `crates/xhub-policy`.
  - Done: preserves aliases such as local TTS capability mapping.
- RH-0302: Add grant request evaluator.
  - Files: `crates/xhub-policy`, `crates/xhub-db`.
  - Done: returns stable decisions: `approved`, `queued`, `denied`, `failed`.
- RH-0303: Add audit writer.
  - Files: `crates/xhub-db`, `crates/xhub-policy`.
  - Done: metadata-only redaction by default; full-content requires explicit
    config.
- RH-0304: Implement pending grants read/action RPCs.
  - Files: `crates/xhubd`.
  - Done: XT pending grant view does not need file fallback in Rust mode.

DoD:

- `grpc` mode never falls back silently after Rust policy denial.
- Audit write failure fails closed for gated actions.

## 6. Phase 4: Memory Retrieval And Assembly

Goal: move high-frequency memory read path to Rust before moving writer truth.

Tasks:

- RH-0401: Add mode profiles.
  - Files: `crates/xhub-memory/src/mode.rs`.
  - Modes: `assistant_personal`, `project_code`.
  - Done: retrieval receives mode and applies mode-specific budgets.
- RH-0402: Add retrieval document builder.
  - Files: `crates/xhub-memory`.
  - Sources: canonical rows, turns, governed runtime docs, future observations.
- RH-0403: Add local index path.
  - First step: SQLite FTS-compatible read path.
  - Later step: Tantivy index for larger data.
- RH-0404: Preserve prompt gate.
  - Files: `crates/xhub-policy`, `crates/xhub-memory`.
  - Done: secret/private/untrusted remote export rules are enforced before
    provider routing.
- RH-0405: Add `HubMemory.RetrieveMemory`.
  - Files: `crates/xhubd`.
  - Done: response matches current `MemoryRetrievalResponse` and source kinds.

DoD:

- Project coder cannot receive full personal memory by default.
- Supervisor assembly remains slot-based and explainable.
- Durable writeback still goes through Writer + Gate, not retrieval.

## 7. Phase 5: Memory Scheduler, Worker, Writer Gate

Goal: implement the memory control plane described by the memory scheduler spec.

Tasks:

- RH-0501: Add `thread_runs`.
- RH-0502: Add `vault_items`.
- RH-0503: Add `memory_jobs`.
- RH-0504: Add `observations`.
- RH-0505: Add `canonical_candidates`.
- RH-0506: Add job leasing and retry.
- RH-0507: Add Python worker bridge.
- RH-0508: Add Writer + Gate.

Hard boundary:

- Models and skills can submit candidates only.
- Only Writer + Gate writes `canonical_memory`, `observations`, and
  `longterm_docs`.

## 8. Phase 6: Skills And Provider Routing

Goal: move governance to Rust while keeping execution and ML where they belong.

Tasks:

- RH-0601: Skill manifest parser and vetter.
- RH-0602: Signature/trust/pin/revoke model.
- RH-0603: Skill resolution API.
- RH-0604: Provider key pool reader/writer.
- RH-0605: Provider route decision engine.
- RH-0606: Quota, retry budget, cooldown, error state.
- RH-0607: Remote/local model inventory contract.
  - Files: `docs/MODEL_MANAGEMENT_EXECUTION_PLAN.md`,
    `crates/xhub-provider`, `crates/xhub-runtime`, `crates/xhubd`.
  - Done: Rust can emit a secret-free model inventory snapshot with remote
    provider pool rows and local runtime readiness rows.
- RH-0608: Model ID alias parity.
  - Files: `crates/xhub-provider`.
  - Done: Rust normalizes common provider-prefixed and typo model IDs the same
    way Hub/RELFlowHub does, including `GPT5.5`, `gpt5.5`, and
    `openai/gpt5.5`.
- RH-0609: Route decision trace parity.
  - Files: `crates/xhub-provider`, `crates/xhubd/src/provider_bridge.rs`.
  - Done: every provider candidate explains selected/skipped state, reason
    code, pool identity, retry source, and next retry time without exposing
    provider secrets.
- RH-0610: Local model artifact and runtime preflight.
  - Files: `crates/xhub-runtime`, future `crates/xhubd/src/model_bridge.rs`.
  - Done: local models are not marked ready until artifact, runtime provider,
    capability, and conservative memory checks pass.
- RH-0611: Unified model route decision.
  - Files: `crates/xhub-provider`, `crates/xhub-runtime`, `crates/xhub-policy`,
    future `crates/xhubd/src/model_bridge.rs`.
  - Done: task/capability requests can choose remote paid routes, remote pool
    fallback, local privacy/cost routes, or fail closed with explicit reason
    codes.
- RH-0612: Model inventory shadow compare and XT parity gate.
  - Files: `tools/`, Node Hub opt-in bridge files, XT projection fixtures.
  - Done: Rust CLI model inventory mismatches are persisted under
    `model_inventory`, and fixture smoke covers report/readiness evidence before
    XT or production routing consumes Rust as authority.
  - Remaining: Node Hub opt-in bridge files and XT projection fixtures.

Boundary:

- Hub Core never executes third-party code.
- XT executes only resolved and allowed skill surfaces.
- Provider OAuth UI can stay Swift/Node until stable.
- Rust Hub must not store provider email/password credentials or log provider
  API keys, OAuth access tokens, refresh tokens, or downloaded auth file
  contents.
- Local runtime preflight may call safe probes, but it must not execute
  untrusted third-party skill code.

## 9. Phase 7: Cutover And Rollback

Goal: replace Node Hub core without removing a rollback path.

Tasks:

- RH-0701: Add `XHUB_HUB_IMPL=node|rust|shadow_compare`.
- RH-0702: Run shadow compare on real requests.
- RH-0703: Capture mismatch reports.
- RH-0704: Switch scheduler to Rust.
- RH-0705: Switch memory retrieval to Rust.
- RH-0706: Switch policy/grant/audit to Rust.
- RH-0707: Retire Node core endpoints only after evidence.

Rollback:

- Keep Node server runnable from existing commands.
- Keep SQLite migrations forward-compatible.
- Keep old file IPC fallback until XT release proves stable with Rust gRPC.

## 10. First Implementation Slice

Start now with:

- RH-0001 workspace
- RH-0002 proto mirror
- RH-0003 command wrappers
- RH-0004 doctor
- RH-0005 shadow HTTP serve

Stop condition for this slice:

- Files exist under the target root.
- Command wrappers are executable.
- Doctor reports missing Rust toolchain clearly in this environment.
- No changes are required in existing `x-hub-system` runtime files.
