# X-Hub Memory Runtime Authority And Reality Map v1

- status: active
- updatedAt: 2026-05-22
- owner: Rust Hub Kernel / Swift Hub Shell / X-Terminal Runtime / Memory Governance
- purpose:
  - 把 Memory 的 runtime authority、truth source、cache/projection 边界写清楚
  - 把 5-layer 设计和当前代码现实对齐，避免后续 AI 把协议目标误说成已经完全落地
  - 作为后续 `writeback candidate lifecycle`、`role-aware conversation contract`、`M0..M4 gateway cutover`、`Memory Inspector` 的前置入口

## 1) Fixed Product Boundary

固定产品口径：

`一个 Hub 产品 = Rust 内核 + Swift 壳`

- Rust 内核负责判断、状态、策略、接口、memory authority、检索、候选写回、readiness、evidence。
- Swift Hub 负责产品壳、设置、用户确认、展示、安装/启动体验。
- X-Terminal 负责交互、执行工作区、短期连续性、投影、fallback、调用 Hub。
- Node gRPC Hub 只保留兼容层、admin bridge、老 XT/GUI 接口迁移桥；不再新增 Memory authority。

这不是把 Swift Hub 和 Rust Hub 当两个产品维护，也不是把 UI 塞进 Rust。目标是把“判断、状态、策略、接口、Memory 主权”收进 Rust，把 Swift/XT 维持为产品壳和调用面。

## 2) Authority Matrix

| Surface | May own durable truth? | Allowed role | Forbidden role | Current reality |
| --- | --- | --- | --- | --- |
| Rust Hub `xhubd` | Yes, target authority | Memory object store, events/history, policy gate, retrieval, gateway prepare, candidate queue, readiness/evidence | Silent promotion without policy/evidence | Object store, project canonical sync, gateway prepare, object retrieval, candidate queue, readiness are implemented; model-call gateway authority is not fully cut over |
| Swift Hub app | No | Product shell, settings, local app container, user confirmation, launch/install/status UI | Durable Memory writer, independent policy engine, second source of truth | Still important product entry and local app container; should call Rust/Hub truth instead of owning Memory logic |
| X-Terminal | No | Client/caller, role-aware projection, hot continuity window, remote snapshot TTL cache, local fallback/edit buffer | Durable truth, canonical writer, private policy bypass, direct promotion | XT can submit canonical sync and writeback candidates to Rust; local stores remain cache/fallback/edit buffer |
| Node gRPC Hub | Compat only | Legacy compatibility, admin APIs, old clients, role-turn bridge during migration | New Memory authority, new durable schema as primary path | `turns`/`canonical_memory` still exist for legacy HubMemory; new durable Memory work should move to Rust |
| Local files under `.xterminal` / `.axcoder` | No | Crash recovery, hot window, pending retry, local projection, edit buffer | Durable truth, governance root, cross-device authority | Still used for speed and compatibility; must always be labelled cache/projection/fallback |
| Derived indexes | No | Rebuildable search acceleration, scoring, chunk refs, explain traces | Source of truth | Rust object retrieval has in-memory/derived lexical-BM25-like scoring; future FTS/vector indexes must be rebuildable from Rust objects |
| Remote snapshot cache | No | Short TTL read cache for smoother XT/Supervisor operation | Stale truth, permission bypass, export approval | XT doctor already exposes provenance/TTL; cache hit is not proof of durable truth |
| Skills / connectors / tools | No | Evidence producers and action surfaces under grants | Memory authority or policy bypass | Tool results and heartbeat can become evidence/candidates, but must not directly mutate active Memory |

## 3) Five-Layer Runtime Reality

The logical design remains:

1. Raw Vault
2. Observations
3. Longterm Memory
4. Canonical Memory
5. Working Set

X-Constitution is a pinned core above ordinary Memory slots. It must not be treated as a normal Longterm entry that retrieval can omit or overwrite.

### 3.1 X-Constitution Pinned Core

- Target: fixed kernel constraint, policy-first, not prompt-only.
- Current reality: protocol and injection contracts are documented and surfaced in doctor/evidence paths; enforcement still depends on a mix of Hub policy, XT assembly, route/export gates, and ongoing Rust migration.
- Boundary: no Memory feature may make it easier to bypass X-Constitution, grants, export gate, audit replay, or kill-switch.

### 3.2 Raw Vault

- Target: append-only raw evidence layer for turns, tool outputs, heartbeats, original payloads, audit references.
- Current reality: Node `turns`, XT raw/local logs, runtime artifacts, audit events, and Rust file-scan retrieval cover parts of this; a single Rust Raw Vault substrate is not complete.
- What is real now:
  - raw evidence can be referenced by audit/evidence refs
  - Rust file-scan retrieval supports `.json`, `.jsonl`, `.md`, `.txt`
  - `.md` / `.txt` shadow retrieval has heading-aware chunking and secret section isolation
- Not complete:
  - unified encrypted Rust Raw Vault for all surfaces
  - full raw event lineage across turns/tools/heartbeat/review
  - raw evidence serving profiles across every role

### 3.3 Observations

- Target: structured facts/preferences/constraints/decisions/lessons/anomalies extracted from raw material.
- Current reality: Rust `l2_observations` objects exist, AXMemory delta extraction can create candidate observations, heartbeat/review projections expose observation-like signals, but generalized extraction and promotion are not complete.
- What is real now:
  - project canonical sync maps risks/recommendations/open questions into `l2_observations`
  - writeback candidate extraction can produce reviewable observations from AXMemory deltas
  - doctor surfaces memory/heartbeat/review evidence
- Not complete:
  - universal observation extractor for all turns/tools/connectors
  - stable observation taxonomy across personal/project/cross-link scopes
  - observation lifecycle with TTL, supersession, conflict, and decay

### 3.4 Longterm Memory

- Target: topic/document/lineage memory built from observations, with outline-first progressive disclosure.
- Current reality: longterm design is protocol-frozen, but the runtime is not as mature as Canonical/Working Set. Some long-lived project facts live in canonical-like Rust objects or legacy stores.
- What is real now:
  - `l1_canonical`, `l2_observations`, `l3_working_set` objects are retrievable from Rust
  - docs and project facts can be served by file-scan / object retrieval paths
- Not complete:
  - semantic longterm retrieval
  - timeline/theme retrieval
  - outline -> expand -> evidence progressive disclosure across all roles
  - durable longterm promotion policy with conflict lineage

### 3.5 Canonical Memory

- Target: compact, high-confidence, injection-friendly stable facts by scope.
- Current reality: this is the strongest Rust migration path so far.
- What is real now:
  - `POST /memory/project-canonical-sync` writes deterministic Rust memory objects
  - XT `syncProjectCanonicalMemory` prefers Rust in `.auto` / `.grpc` modes
  - successful Rust sync can make XT reads prefer active Rust project objects
  - Rust import diagnostics can detect missing/stale/metadata-mismatched/extra deterministic project objects
- Not complete:
  - all legacy canonical paths removed
  - every personal/project/cross-link canonical writer moved into Rust
  - full live authority cutover with fallback disabled

### 3.6 Working Set

- Target: recent high-signal task context, dialogue continuity, current blocker, next step, latest review/guidance.
- Current reality: mature in XT/Supervisor/Product assembly, partly moved behind Rust gateway prepare.
- What is real now:
  - Supervisor and Project AI have role-aware assembly/resolver/doctor evidence
  - recent raw/project dialogue continuity floor exists on XT side
  - Rust `/memory/gateway/prepare` can assemble policy-gated context from Rust objects
  - Rust gateway default includes `l1_canonical`, `l2_observations`, `l3_working_set`
- Not complete:
  - all model calls forced through Rust Memory Gateway
  - M0..M4 fully mapped to Rust gateway behavior
  - no-fallback require mode as default production authority

## 4) Current Implemented Memory Runtime Slices

These are real or preview-working in the current codebase:

- Rust object store:
  - `rust_hub_memory_objects`
  - `rust_hub_memory_events`
  - CRUD/list/get/history surfaces
- Rust project canonical sync:
  - `POST /memory/project-canonical-sync`
  - CLI `xhubd memory project-canonical-sync`
- Rust Memory Gateway prepare:
  - `POST /memory/gateway/prepare`
  - alias `POST /memory/context`
  - prepare-only; no model call execution authority yet
- Rust object retrieval:
  - `GET /memory/search`
  - `POST /memory/retrieve`
  - first active-object lexical/BM25-like hybrid slice returns `source=rust_memory_objects_hybrid_v1`
  - semantic and rerank are explicitly not enabled yet
- Rust writeback candidates:
  - `POST /memory/writeback/candidates`
  - `GET /memory/writeback/candidates`
  - `POST /memory/writeback/candidates/extract`
  - `POST /memory/writeback/candidates/{memory_id}/approve`
  - `POST /memory/writeback/candidates/{memory_id}/reject`
  - candidate status is `candidate`; approval transitions only `candidate -> active`
- Rust memory readiness:
  - `GET /memory/readiness`
  - object store, policy gate, candidate queue readiness
- Role-aware transcript projection:
  - Rust has a read-only role-aware project transcript projection path over Hub turns when role metadata exists
  - Node compatibility path has role-turn metadata tests
  - This is projection/readback, not a reason to keep Node as future Memory authority
- XT caller/projection:
  - XT sends canonical sync and writeback candidate extraction to Rust where available
  - XT local memory stores remain cache/fallback/edit buffer
  - Doctor/export surfaces local cache provenance, remote snapshot provenance, and memory route truth as evidence

## 5) Not Yet Done

Do not claim these as complete:

- no full Rust Memory Gateway authority for every model call
- no semantic embeddings / vector index as a production retrieval path
- no local ONNX bge-m3 default embedding provider
- no RRF fusion / cross-encoder rerank
- no fully unified Observations/Longterm substrate
- no full encrypted Rust Raw Vault for every memory/event type
- no public Swift Memory Inspector for candidate review and lineage browsing
- no full removal of Node/XT legacy memory compatibility paths
- no default require-mode cutover with fallback disabled across all model requests

## 6) Write Authority Rules

All future Memory write work must obey:

1. Model output can propose memory; it cannot directly promote durable truth.
2. XT can submit candidates; XT cannot become durable writer authority.
3. Swift can display and collect confirmation; Swift cannot become durable writer authority.
4. Node can bridge old clients; Node cannot receive new Memory authority.
5. Secret-like content fails closed before candidate creation or promotion.
6. Project Coder cannot read personal memory by default.
7. Cross-scope retrieval must deny by default unless policy explicitly permits a governed bridge.
8. Remote export gate is separate from local model context assembly.
9. Derived indexes are rebuildable; losing an index must not lose truth.
10. Every write/promotion/deny path needs machine-readable evidence.

## 7) Serving Authority Rules

All future Memory serving work must obey:

- Serving plane selects from truth; it is not a second truth store.
- M0/M1 hot paths must prefer low-latency, bounded context.
- M2/M3/M4 can expand, but only under role/scope/sensitivity/budget policy.
- Raw evidence requires explicit policy permission.
- `remote_export=true` must skip `local_only` and `never_export` content.
- Fresh Hub truth is required for high-risk tool acts and remote prompt bundles.
- Recent raw continuity is a floor, not a durable promotion signal.

## 8) Next Design Updates To Do

### RT-A Candidate Lifecycle Spec

Primary spec: `docs/memory-new/xhub-memory-writeback-candidate-lifecycle-v1.md`.

The lifecycle spec now covers:

- extract
- dedupe
- candidate
- review
- approve/reject
- active/rejected/archive
- TTL / stale candidate handling
- supersession
- conflict handling
- audit/evidence
- which candidate classes can never auto-promote

Primary files:

- `docs/memory-new/xhub-universal-memory-layer-work-orders-v1.md`
- `docs/memory-new/xhub-memory-writeback-candidate-lifecycle-v1.md`
- Rust implementation: `rust/xhubd/crates/xhubd/src/memory_bridge.rs`
- XT caller: `x-terminal/Sources/Hub/HubIPCClient.swift`
- XT pipeline: `x-terminal/Sources/Project/AXMemoryPipeline.swift`

### RT-B Role-Aware Conversation Contract

Primary spec: `docs/memory-new/xhub-role-aware-conversation-contract-v1.md`.

The role-aware contract now covers:

- supervisor -> coder dispatch
- coder -> supervisor reply
- reviewer -> coder/supervisor note
- tool approval / tool result
- heartbeat
- `dispatch_id`, `run_id`, `launch_run_id`, `reviewer_note_id`, `status`

This must stay a Hub protocol upgrade. XT may cache/project, but must not create a second Memory authority.

Primary files:

- `docs/memory-new/xhub-role-aware-conversation-contract-v1.md`
- `protocol/hub_protocol_v1.proto`
- `rust/xhubd/assets/proto/hub_protocol_v1.proto`
- `protocol/hub_protocol_v1.md`
- `x-terminal/Sources/Project/XTProjectConversationMirror.swift`
- `x-terminal/Sources/Project/XTProjectTranscriptProjection.swift`
- `x-terminal/Sources/Hub/HubIPCClient.swift`
- `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
- `x-hub/grpc-server/hub_grpc_server/src/services.js`
- `x-hub/grpc-server/hub_grpc_server/src/db.js`

### RT-C Serving Profile To Rust Gateway Alignment

Primary spec: `docs/memory-new/xhub-memory-serving-profile-gateway-alignment-v1.md`.

The alignment spec now maps M0..M4 onto Rust `/memory/gateway/prepare`:

- M0 heartbeat / handoff refs
- M1 execute
- M2 plan/review
- M3 deep dive
- M4 full scan with policy/budget caps

It also freezes the next code slices:

- add `serving_profile_id` to Rust gateway request parsing
- derive a default profile from `use_mode` for old callers
- return requested/effective profile evidence
- scope shadow compare and cutover readiness by profile
- surface profile readiness in doctor/ops evidence

Current implementation state:

- SG-C1 docs freeze is complete.
- SG-C2 first Rust slice is complete in `rust/xhubd/crates/xhubd/src/memory_bridge.rs`.
- SG-C3 first Swift caller slice is complete in `x-terminal/Sources/Hub/HubIPCClient.swift`:
  - gateway requests carry `serving_profile_id`
  - shadow compare/history carry requested/selected/effective profile evidence
  - require-mode cutover rejects wrong-profile parity evidence
  - public caller coverage proves session/project/supervisor/tool/remote prompt paths send the expected canonical Rust profile IDs
- SG-C3 targeted Swift verification is complete with `swift test --filter rustMemoryGateway`.
- SG-C5 ops rollup first slice is complete in `rust/xhubd/tools/xhubd_daemon.js`:
  - ops gate/report forward scoped profile fields from `memory_gateway_cutover_readiness.json`
  - ops rollup counts fresh/passing samples per serving profile from shadow history
  - ops rollup reports profile downgrade and Rust deny counters without prompt/context text
- SG-C5 Swift Doctor profile identity slice is complete in `SupervisorMemoryAssemblyDiagnostics`:
  - shadow drift/authority findings show `serving_profile_id/selected_profile/effective_profile`
  - cutover readiness findings show the same profile identity next to sample counts
- SG-C5 Swift readiness report/export slice is complete in `HubIPCClient`:
  - Swift-generated `memory_gateway_cutover_readiness.json` includes `profile_readiness[]`
  - Swift reports `profile_readiness_sample_count`, `profile_downgrade_count`, and `rust_deny_count`
  - Doctor readiness findings include a compact per-profile sample line
- SG-C4/SG-C5/SG-C6 profile readiness path is now implemented:
  - Rust gateway emits selected/effective profile evidence.
  - Swift/Doctor/Ops carry bounded per-profile readiness.
  - `memory_gateway_cutover_smoke.js --profile-suite` collects M0/M1/M2/M3/M4 sustained samples.
  - 2026-05-24 local daemon validation produced `memory_gateway_cutover_ready=true` under ops-gate with `--require-memory-gateway-cutover-ready`.
- 2026-05-24 live base-dir validation is complete against the launchd-owned packaged runner:
  - LaunchAgent `com.ax.xhubd.local` is enabled/loaded/running.
  - live DB path is `~/Library/Application Support/AX/rust-hub/local/data/hub.sqlite3`.
  - live profile-suite smoke produced fresh M0/M1/M2/M3/M4 readiness.
  - ops-gate passed with memory-gateway require-ready, memory writer authority required, skills execution authority required, and `--max-slow-requests 0`.
- 2026-05-25 live fail-closed require rollout is complete:
  - `memory_gateway_cutover_session.js --apply --require` set the current user launchd session to `active_mode=require`.
  - `~/Library/LaunchAgents/com.ax.xhubd.local.plist` now persists `XHUB_RUST_MEMORY_CONTEXT_GATEWAY=1`, `XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE=1`, and `XHUB_RUST_MEMORY_CONTEXT_GATEWAY_PARITY_MAX_AGE_MS=600000`.
  - `launchctl kickstart -k gui/501/com.ax.xhubd.local` relaunched the live daemon; `launchd-status` reported pid `39382` from `launchctl_print`.
  - Post-relaunch profile-suite smoke refreshed live evidence with 15 fresh passing samples across M0/M1/M2/M3/M4, `profile_downgrade_count=0`, and `rust_deny_count=0`.
  - Final ops gate passed with `memory_gateway_cutover_ready=true`, `memory_gateway_cutover_readiness_ok=true`, `memory_writer_authority_in_rust=true`, `skills_execution_authority_in_rust=true`, `node_remains_authority=false`, `slow_requests=0`, and `issues=[]`.
  - final report: `rust/xhubd/reports/daemon_ops_gate_20260525T004409Z.json`.

Acceptance must prove selected, omitted, denied, expanded, downgraded, and fallback-disabled reasons are machine-readable.

### RT-D Live Cutover Plan

Define exact cutover gates:

- shadow compare sample count and age
- parity fields
- require-mode env flags
- fallback disable condition
- rollback condition
- daemon ops gate evidence
- doctor evidence
- no production authority change unless explicitly requested

## 9) Code Reference Map

Rust:

- `rust/xhubd/crates/xhubd/src/memory_bridge.rs`
- `rust/xhubd/crates/xhubd/src/memory_role_projection.rs`
- `rust/xhubd/crates/xhubd/src/main.rs`
- `rust/xhubd/assets/proto/hub_protocol_v1.proto`

Swift / XT:

- `x-terminal/Sources/Hub/HubIPCClient.swift`
- `x-terminal/Sources/Project/AXMemoryPipeline.swift`
- `x-terminal/Sources/Project/XTProjectConversationMirror.swift`
- `x-terminal/Sources/Project/XTProjectTranscriptProjection.swift`
- `x-terminal/Sources/Project/XTRoleAwareMemoryPolicy.swift`
- `x-terminal/Sources/Project/AXProjectContextAssemblyDiagnostics.swift`
- `x-terminal/Sources/Supervisor/SupervisorMemoryAssemblyDiagnostics.swift`
- `x-terminal/Sources/UI/XTUnifiedDoctor.swift`

Node compatibility:

- `x-hub/grpc-server/hub_grpc_server/src/services.js`
- `x-hub/grpc-server/hub_grpc_server/src/db.js`
- `x-hub/grpc-server/hub_grpc_server/src/role_turn_metadata.test.js`

Protocols / design:

- `protocol/hub_protocol_v1.md`
- `protocol/hub_protocol_v1.proto`
- `docs/memory-new/xhub-universal-memory-layer-work-orders-v1.md`
- `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
- `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
- `docs/memory-new/xhub-memory-serving-profile-gateway-alignment-v1.md`
- `docs/xhub-memory-remote-export-and-prompt-gate-v1.md`
- `docs/memory-new/xhub-constitution-memory-integration-v2.md`

## 10) Acceptance For Future Memory Work

Before closing any future Memory work item, show:

1. Which surface owned the durable decision.
2. Whether XT/Swift/Node only acted as shell/projection/compat.
3. Whether local cache was labelled cache/fallback/edit buffer.
4. Whether role/scope/sensitivity policy ran.
5. Whether remote export was separately gated when relevant.
6. Whether candidate promotion required explicit allowed transition.
7. Whether readiness/doctor/evidence can explain selected, omitted, denied, degraded, and fallback behavior.
8. Whether old clients without new metadata still work.
9. Whether no new Node/Swift/XT durable Memory authority was introduced.
10. Which tests or smoke commands prove the claim.
