# X-Hub Universal Memory Layer Work Orders v1

- version: v1.0
- updatedAt: 2026-06-03
- owner: Rust Hub Kernel / XT Runtime / Swift Shell / Supervisor / Coder / Security / QA
- status: in-progress-w0-w6-w9-w10-rust-and-xt-caller-doctor-grant-governance-slices-implemented
- purpose:
  - 把 mem0 / OpenMemory 这类开源模型通用记忆系统的可借鉴点，转成 X-Hub 可执行工单
  - 在不牺牲 X-Hub 现有安全边界的前提下，把 Memory 做成所有模型、所有 Agent、所有运行面统一调用的 Rust kernel capability
  - 让下一位 AI 或工程师一接手就知道先读什么、改哪里、怎么验收、哪些边界不能碰
- primary product boundary:
  - 一个 Hub 产品 = Rust 内核 + Swift 壳
  - Rust 内核负责判断、状态、策略、接口、memory authority、检索和审计
  - Swift 壳负责产品 UI、展示、用户确认、调用 Rust kernel
  - Node 只保留兼容层、admin bridge、老接口迁移桥，不再新增 memory authority

## Implementation Status 2026-06-03

First implementation slice landed in `rust/rust hub`:

- `UML-W0`: v1 contract captured in this work-order doc.
- Runtime authority and reality map captured in `docs/memory-new/xhub-memory-runtime-authority-and-reality-map-v1.md`.
  - It freezes the current authority boundary: Rust Hub is the target Memory authority, Swift/XT are shell/projection/cache/caller surfaces, Node is compatibility only.
  - It also records the current reality split between implemented Rust object/candidate/gateway slices and still-in-progress Observations/Longterm/semantic/cutover work.
- Writeback candidate lifecycle captured in `docs/memory-new/xhub-memory-writeback-candidate-lifecycle-v1.md`.
  - It freezes the candidate state machine, never-auto-promote classes, TTL/stale target behavior, Swift queue work orders, and ops evidence criteria.
- Role-aware conversation contract captured in `docs/memory-new/xhub-role-aware-conversation-contract-v1.md`.
  - It freezes Supervisor/Coder/Reviewer/tool/heartbeat turn metadata semantics, current Node/Rust/XT implementation reality, and remaining cutover work.
- Serving profile to Rust gateway alignment captured in `docs/memory-new/xhub-memory-serving-profile-gateway-alignment-v1.md`.
  - It maps M0..M4 onto current/future Rust `/memory/gateway/prepare`, records the current prepare-only reality, and freezes the SG-C1..SG-C5 code/evidence slices.
  - `SG-C2` first Rust slice is implemented: `/memory/gateway/prepare` accepts `serving_profile_id`, derives a default profile from `use_mode` for old callers, applies profile defaults before policy, downgrades deep remote-export profiles, and returns requested/effective profile evidence.
- `UML-W1`: SQLite `memory_objects` / `memory_events` store added through migration `0007_memory_objects.sql`.
- `UML-W2`: first CRUD surface implemented for create, get, list, and history.
  - HTTP:
    - `POST /memory/objects`
    - `GET /memory/objects`
    - `GET /memory/objects/{memory_id}`
    - `GET /memory/objects/{memory_id}/history`
  - CLI:
    - `xhubd memory object-create`
    - `xhubd memory object-list`
    - `xhubd memory object-get`
    - `xhubd memory object-history`
- `UML-W3`: minimal Rust policy matrix implemented with fail-closed behavior for unknown modes, Project Coder personal memory deny, lane handoff fulltext deny, remote raw evidence deny, Supervisor raw evidence deny, and high-risk tool-act fresh snapshot requirement.
- `UML-W4`: Rust-side first bridge and Swift/XT caller cutover implemented for existing XT `project_canonical_memory` payloads.
  - HTTP:
    - `POST /memory/project-canonical-sync`
    - default is dry-run
    - `?apply=1` writes deterministic Rust memory objects
  - CLI:
    - `xhubd memory project-canonical-sync --payload-json ...`
    - `--apply` writes deterministic Rust memory objects
  - Existing XT keys mapped:
    - `xterminal.project.memory.goal` -> `project` / `l1_canonical` / `project_goal`
    - `xterminal.project.memory.requirements` -> `project` / `l1_canonical` / `project_requirement`
    - `xterminal.project.memory.current_state` -> `project` / `l3_working_set` / `current_state`
    - `xterminal.project.memory.decisions` -> `project` / `l1_canonical` / `decision_track`
    - `xterminal.project.memory.next_steps` -> `project` / `l3_working_set` / `next_step`
    - `xterminal.project.memory.open_questions` -> `project` / `l2_observations` / `open_question`
    - `xterminal.project.memory.risks` -> `project` / `l2_observations` / `risk`
    - `xterminal.project.memory.recommendations` -> `project` / `l2_observations` / `recommendation`
  - Metadata keys such as `schema_version`, `project_name`, `project_root`, `updated_at`, and `summary_json` are skipped rather than duplicated as long-term facts.
  - Re-sync updates existing deterministic memory IDs and appends history events.
  - XT `HubIPCClient.syncProjectCanonicalMemory` now prefers Rust HTTP `POST /memory/project-canonical-sync?apply=1` in `.auto` / `.grpc` modes.
  - `.fileIPC` remains explicit local compatibility behavior.
  - If Rust HTTP is unavailable or rejects the write, `.auto` falls back to existing remote/local compatibility path so Coder prompt flow does not block.
  - If Rust HTTP is unavailable for project-backed AXMemory sync, XT writes a retryable pending snapshot at `.xterminal/memory_lifecycle/pending_project_canonical_rust_sync.json`.
  - A later Rust success clears the pending snapshot.
  - Project load schedules a pending Rust canonical sync retry through `HubIPCClient.retryPendingProjectCanonicalRustSync(ctx:)`.
  - XT memory-context assembly and `requestMemoryRetrieval` now check `canonical_memory_sync_status.json`; after a successful Rust project canonical sync, `.auto` / `.grpc` reads prefer active Rust `/memory/objects?scope=project&project_id=...&status=active` objects for L1/L2/L3 while keeping local projection, Hub remote snapshot, and local IPC as compatibility fallback.
  - `HubIPCClient.diagnoseProjectCanonicalRustImport(...)` compares the current AXMemory projection against active deterministic Rust project objects.
    - It skips metadata-only keys instead of requiring Rust long-term objects for them.
    - It refuses to fetch Rust objects until local sync status proves a successful Rust delivery.
    - It reports missing, stale, metadata-mismatched, and extra Rust objects with schema-versioned issue codes.
- `UML-W5`: first Rust Memory Gateway prepare surface implemented without model-call cutover.
  - HTTP:
    - `POST /memory/gateway/prepare`
    - alias `POST /memory/context`
  - CLI:
    - `xhubd memory gateway-prepare`
  - Behavior:
    - prepare-only, no model call, no production authority change.
    - Rust policy runs before object selection.
    - default context only includes `l1_canonical`, `l2_observations`, and `l3_working_set`.
    - `l4_raw_evidence` requires explicit request and policy allow.
    - remote export requests skip local-only / never-export objects.
    - response includes schema-versioned policy, selected slots, context text, and skip counters.
  - Swift/XT shadow compare added:
    - `HubIPCClient.compareMemoryContextWithRustGateway(...)`
    - product Memory V1 remains Swift/local/remote builder output.
    - Rust gateway output is compared by selected object text anchors and stable text hashes.
    - results write `memory_gateway_shadow_compare_status.json` when recorded.
    - results also append bounded safe metadata history to `memory_gateway_shadow_compare_history.json`.
    - automatic shadow compare is gated by `XHUB_RUST_MEMORY_CONTEXT_GATEWAY_SHADOW=1`.
  - Swift/XT guarded primary path added:
    - `XHUB_RUST_MEMORY_CONTEXT_GATEWAY=1` makes memory context assembly try Rust `/memory/gateway/prepare` first for non-`.fileIPC` routes.
    - Rust success returns product-compatible `MemoryContextResponsePayload` with `source=rust_memory_gateway_prepare` and `freshness=fresh_rust_gateway`.
    - Rust unavailable, denied, authority-unsafe, or empty-context responses fall back to existing Swift/local/remote builders unless the explicit require gate is enabled.
  - Swift/XT fail-closed require gate added:
    - `XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE=1` requires Rust `/memory/gateway/prepare` for non-`.fileIPC` memory context calls.
    - Require mode first checks local `memory_gateway_shadow_compare_status.json`.
    - Evidence must be fresh, same requester_role/use_mode/project_id, `ok=true`, `parity_ok=true`, `rust_source=rust_memory_gateway_prepare`, and `production_authority_change=false`.
    - `XHUB_RUST_MEMORY_CONTEXT_GATEWAY_PARITY_MAX_AGE_MS` controls evidence freshness; default is 10 minutes.
    - If evidence is missing/stale/mismatched or Rust fails, caller receives `source=rust_memory_gateway_cutover_gate` with fallback disabled instead of silently using Swift/local memory.
    - Coder and Supervisor memory builders now preserve that cutover-gate failure block instead of using local fallback.
  - Swift/XT live cutover readiness evidence added:
    - `HubIPCClient.rustMemoryGatewayCutoverReadinessEvidence(...)`
    - requires sustained fresh same-scope parity samples from `memory_gateway_shadow_compare_history.json`.
    - writes `memory_gateway_cutover_readiness.json` when requested.
    - report schema is `xt.rust_memory_gateway_cutover_readiness.v1`.
    - report contains only bounded metadata and hashes, not memory context text.
  - Doctor/evidence rollup added:
    - `HubIPCClient.rustMemoryGatewayShadowCompareStatus()` reads latest `memory_gateway_shadow_compare_status.json`.
    - Supervisor memory assembly diagnostics surface `memory_gateway_shadow_compare_drift` as warning.
    - Supervisor memory assembly diagnostics surface `memory_gateway_shadow_authority_violation` as blocking if shadow evidence reports `production_authority_change=true`.
    - Supervisor Doctor now consumes `memory_gateway_cutover_readiness.json` / generated readiness evidence.
    - Not-ready cutover evidence surfaces as `memory_gateway_cutover_readiness_not_ready`; it is a warning before require mode and blocking when `XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE=1`.
    - `daemon_ops_gate` / `daemon_ops_report` now include bounded `memory_gateway_cutover_readiness` evidence.
    - Ops gate does not block just because the report is absent; it blocks when `--require-memory-gateway-cutover-ready` is set, `XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE=1` is present, or the report contains a cutover authority violation.
  - Serving profile envelope added:
    - `serving_profile_id` / `servingProfileId` accepts M0..M4.
    - missing profile derives from `use_mode`.
    - profile defaults populate requested layers, source-kind hints, item/snippet budget, and read-limit multiplier when omitted.
    - remote export requests downgrade M2/M3/M4 to effective M1 instead of deep-exporting.
    - response now includes requested/effective profile evidence plus selected/omitted/denied/expanded/fallback fields.
  - XT profile caller slice added:
    - existing XT serving-profile resolver now feeds Rust `serving_profile_id`.
    - Rust gateway requests no longer force generic L1/L2/L3/default item budgets when profile defaults should apply.
    - shadow compare and history carry requested/selected/effective profile evidence.
    - require-mode cutover rejects wrong-profile parity evidence before contacting Rust.
  - Rust model-call plan-only wrapper and XT/Swift shadow preflight added:
    - Rust exposes `POST /memory/gateway/model-call-plan` / CLI `gateway-model-call-plan` as a non-executing admission wrapper over `/memory/gateway/prepare`.
    - `execute/apply/commit` fail closed; the wrapper reports `would_call_model=false` and `model_call_executed=false`.
    - `memory_gateway_cutover_smoke.js` writes bounded `model_call_plan_*` readiness fields, including content-free `omitted_reason_counts`, and ops gate blocks execution/text-leak/missing-denial failures.
    - XT/Swift `HubAIClient` now asks `HubIPCClient` to run a fire-and-forget model-call shadow preflight before local file-IPC enqueue and remote generation when `XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_PLAN_SHADOW=1` or the existing memory gateway shadow env is enabled.
    - XT evidence files are `memory_gateway_model_call_plan_status.json` and `memory_gateway_model_call_plan_history.json`; they contain counts/status/route/profile/omitted-reason metadata only, never prompt/context text.
    - Canonical Rust Hub `xhubd_daemon.js` ops-report/ops-gate now summarizes that XT evidence from the live/base dir. Missing shadow evidence is informational by default, `--require-memory-gateway-model-call-plan-shadow` makes it required, and execution/text-leak/authority-change evidence is always blocking when present.
    - This is not model execution authority cutover; product generation still follows the existing local/remote path.
- `UML-W11`: `/memory/readiness` now reports object store readiness summary and policy gate readiness.
- `MS-1`: first `memsearch-main` retrieval-engine lesson absorbed into Rust shadow file retrieval.
  - `.md` / `.txt` files are chunked by Markdown headings instead of treated as one monolithic document.
  - Stable section refs use line range + content hash style IDs.
  - Secret-bearing sections can be redacted/skipped without hiding unrelated public sections in the same file.
  - This remains shadow file-scan retrieval only; it does not introduce semantic embeddings, vector DB, or production authority change.
- `UML-W6`: first Rust object-store indexed retrieval slice started.
  - `/memory/search` and `POST /memory/retrieve` first try active Rust project memory objects when `project_id` is supplied.
  - Matching uses deterministic filters, in-memory lexical/FTS-like scoring, cheap property boosts, and optional result-level explain.
  - Returned source is `rust_memory_objects_hybrid_v1`; response includes `xhub.memory.hybrid_retrieval.v1` engine evidence.
  - Semantic retrieval and rerank remain disabled and explicitly reported as `false`.
  - No object match falls back to existing Rust shadow file-scan retrieval.
- `UML-W9`: governed writeback candidate slices implemented through the first Swift shell queue.
  - HTTP:
    - `POST /memory/writeback/candidates`
    - `GET /memory/writeback/candidates`
    - `POST /memory/writeback/candidates/extract`
    - `POST /memory/writeback/candidates/{memory_id}/approve`
    - `POST /memory/writeback/candidates/{memory_id}/reject`
    - aliases:
      - `POST /memory/objects/{memory_id}/approve`
      - `POST /memory/objects/{memory_id}/reject`
  - CLI:
    - `xhubd memory candidate-create`
    - `xhubd memory candidate-extract`
    - `xhubd memory candidate-list`
    - `xhubd memory candidate-approve`
    - `xhubd memory candidate-reject`
  - Behavior:
    - candidates reuse `rust_hub_memory_objects.status='candidate'`; no new DB schema needed for first slice.
    - candidate creation is policy gated and defaults to `tool/tool_plan`.
    - approval only transitions `candidate -> active` and records an `approve` memory event.
    - rejection only transitions `candidate -> rejected` and records a `reject` memory event.
    - deterministic AXMemory delta extraction maps goal/requirements/current state/decisions/next steps/open questions/risks/recommendations into candidate objects.
    - extractor supports dry-run, stable duplicate collapse, and candidate-only writes.
    - invalid transitions fail closed with conflict rather than silently mutating active memory.
    - secret-like candidate content/audit refs fail closed.
    - `/memory/readiness` reports `writeback_candidates` readiness and candidate count.
  - Swift/XT caller slice:
    - `HubIPCClient.extractMemoryWritebackCandidatesViaRust(...)` calls `POST /memory/writeback/candidates/extract?apply=1` with a short timeout and Rust access-key support.
    - `AXMemoryPipeline` emits decoded model deltas and runtime fallback deltas to the Rust extractor as `status='candidate'` writes only.
    - The emit path skips removal-only / empty deltas, preserves existing local AXMemory save/refine/vault behavior, and records bounded raw-log evidence with `active_write=false`, `requires_approval=true`, and `production_authority_change=false`.
  - Swift shell queue slice:
    - `HubIPCClient.listMemoryWritebackCandidatesViaRust(...)` lists pending Rust candidates.
    - `HubIPCClient.approveMemoryWritebackCandidateViaRust(...)` and `rejectMemoryWritebackCandidateViaRust(...)` call Rust transition endpoints.
    - `XTMemoryWritebackCandidateQueueStore` projects pending/stale/error state for the selected project.
    - `ProjectSettingsView` shows the compact queue under Hub memory governance in the Rust-refactored `x-terminal` app.
    - Swift records bounded review evidence with `production_authority_change=false` and never edits local active memory directly.
  - Candidate diagnostics and Doctor slice:
    - `GET /memory/writeback/candidates` now returns top-level `candidate_diagnostics`.
    - `/memory/readiness` exposes `object_store.writeback_candidates.diagnostics`.
    - Diagnostics schema is `xhub.memory.writeback_candidate_diagnostics.v1`.
    - Diagnostics include candidate/conflict/stale/stale-review/superseding/superseded counts, planned archive/review counts, queue pressure, noise score, bounded IDs, and `production_authority_change=false`.
    - Swift decodes candidate policy/provenance/diagnostics and exposes conflict/stale-review/supersession state without becoming authority.
    - Conflicting candidate approval requires `conflict_resolution_reason`; Swift fail-closes locally when the reason is blank.
    - `XTUnifiedDoctor` consumes Rust `/memory/readiness` and emits bounded `rust_memory_writeback_candidate_queue_*` detail-lines.
    - `session_runtime_readiness` now also carries typed `rustMemoryWritebackCandidateQueueProjection` JSON, so ops/UI code can consume candidate queue truth without parsing detail strings.
- `UML-W10`: Rust memory object mutation gate, Swift caller/evidence wrapper, Project Memory Inspector controls, and Assistant/User reveal grant gate implemented without moving authority out of Rust.
  - HTTP:
    - `POST /memory/objects/{memory_id}/archive`
    - `POST /memory/objects/{memory_id}/delete`
    - `POST /memory/objects/{memory_id}/pin`
    - `POST /memory/objects/{memory_id}/unpin`
    - `POST /memory/user-reveal-grant/issue`
    - `POST /memory/user-reveal-grant/evaluate`
    - `POST /memory/user-reveal-grant/revoke`
  - CLI:
    - `xhubd memory object-archive`
    - `xhubd memory object-delete`
    - `xhubd memory object-pin`
    - `xhubd memory object-unpin`
  - Behavior:
    - archive/delete require explicit confirmation (`confirm=true`, action-specific confirm field, or matching `confirmation` token).
    - archive clears `pinned` so archived objects cannot remain pinned but un-unpinnable.
    - delete is tombstone-only (`status='deleted'`), not physical row removal.
    - immutable objects fail closed for every object mutation action.
    - pin/unpin only apply to active/candidate objects; archived/deleted states fail closed.
    - every successful mutation increments object version and writes `rust_hub_memory_events`.
    - `/memory/readiness` exposes `object_store.mutation_gate` with confirmation/delete-mode/authority evidence.
    - XT Doctor decodes that cached readiness payload and emits content-free `rust_memory_object_mutation_gate_*` detail-lines plus typed `rustMemoryObjectMutationGateProjection`; generic `xhub doctor` mirrors it as `rust_memory_object_mutation_gate_snapshot`.
  - Swift caller/evidence slice:
    - `HubIPCClient.mutateMemoryObjectViaRust(...)` calls only the Rust `archive/delete/pin/unpin` endpoints with Rust access-key support.
    - `XTMemoryInspectorStore.mutateProjectObject(...)` fail-closes on project-scope mismatch before calling Rust.
    - bounded raw-log evidence uses `xt.memory_inspector_object_mutation.v1` with action/status/version/event-present/confirmation/authority fields only; it omits memory IDs, event IDs, prompt/context text, and object content.
  - Project Memory Inspector controls now render only legal Rust-owned actions, require confirmation for archive/delete, disable duplicate in-flight actions, and refresh from Rust after success.
  - Assistant/User Memory Inspector grant slice:
    - Rust issues, evaluates, and revokes a short-TTL `xhub.memory.user_reveal_grant.v1` envelope for `scope=user` and `surface=assistant_user_memory_inspector`.
    - The grant envelope is content-free: `content_included=false`, `memory_ids_included=false`, `model_context_authority=false`, `memory_serving_authority_change=false`, and `production_authority_change=false`.
    - Rust denies Project Coder / project use-mode requests fail-closed (`project_coder_allowed=false`).
    - `/memory/readiness.object_store.user_reveal_grant` exposes readiness/default TTL/max TTL/authority evidence without scanning or exporting objects.
    - Swift `HubIPCClient.requestMemoryUserRevealGrantViaRust(...)` is the only Assistant/User reveal caller; `SupervisorPersonalMemoryCenterView` uses it for request/evaluate/revoke and `XTMemoryInspectorStore.refreshAssistantUser(...)` lists `/memory/objects?scope=user` only after Rust object-store readiness plus an active unexpired Rust grant.
    - The Supervisor Personal Memory Center now renders a gated Assistant/User object shell after the active Rust grant: list rows show only scope-safe metadata, detail/history are loaded on demand through Rust get/history endpoints, cross-scope objects/events are dropped, and title/text/summary/provenance/policy are stripped from Assistant/User shell objects.
    - XT Doctor decodes the same cached readiness payload and emits content-free `rust_memory_user_reveal_grant_*` detail-lines plus typed `rustMemoryUserRevealGrantProjection`; generic `xhub doctor` mirrors it as `rust_memory_user_reveal_grant_snapshot`.

Validation completed:

- `cargo fmt`
- `cargo test -p xhub-db`
- `cargo test -p xhubd`
- `cargo build -p xhubd`
- Temporary HTTP smoke on `127.0.0.1:50251` for create/get/list/history/policy/readiness.
- CLI smoke on a temporary DB for create/list/get/history/policy.
- CLI smoke on a temporary DB for project canonical sync dry-run/apply/update/history.
- Temporary HTTP smoke on `127.0.0.1:50251` for `POST /memory/project-canonical-sync?apply=1` followed by object listing.
- `cargo test -p xhubd memory_gateway_prepare`
  - validates prepare-only gateway returns policy-gated project memory slots from Rust objects.
  - validates default prepare excludes raw evidence.
  - validates remote export skips local-only objects.
  - validates Supervisor raw evidence request fails closed before model route.
  - validates M0/M1/M2 profile defaults, M4 remote-export downgrade, and profile evidence fields.
- `cargo test -p xhubd`
  - validates the full xhubd unit suite after gateway endpoint/readiness changes.
- `cargo test -p xhub-memory`
  - validates memsearch-inspired heading chunking, stable section refs, get-ref compatibility, and secret section isolation for Rust shadow file retrieval.
- `cargo test -p xhubd memory_object_hybrid_retrieval`
  - validates Rust object-store indexed retrieval finds decision memory with explain and supports layer filtering plus object `get_ref`.
- `cargo test -p xhubd memory_object_http_mutation_gate_archives_deletes_and_pins`
  - validates Rust-owned archive/delete/pin/unpin HTTP mutation gate, explicit confirmation, tombstone delete, event history, and readiness evidence.
- `cargo test -p xhubd memory_object_http_mutation_gate_blocks_immutable_objects`
  - validates immutable objects fail closed for mutation.
- `cargo test -p xhubd memory_object_cli_pin_and_archive_use_rust_mutation_gate`
  - validates CLI object mutation aliases use the same Rust gate.
- `cargo test -p xhubd memory_writeback_candidate`
  - validates candidate create/list/approve, readiness candidate count, approve event history, active retrieval after approval, reject via object alias, invalid transition conflict, and secret-like candidate deny.
- `swift test --filter AXMemoryPipelineTests`
  - validates XT AXMemory delta payload encoding for Rust candidate extraction.
  - validates Swift caller delivery records candidate-only evidence with `active_write=false` and `production_authority_change=false`.
  - validates removal-only deltas do not call the candidate extractor.
- `swift test --filter MemoryWritebackCandidateQueueTests`
  - validates Rust candidate list decoding.
  - validates queue projection marks rows as pending, not active truth.
  - validates approve/reject Rust decision calls preserve audit refs.
  - validates secret candidate content is hidden by default.
  - validates candidate diagnostics decoding.
  - validates conflicting approve is blocked locally until `conflict_resolution_reason` is provided.
- `swift test --filter XTUnifiedDoctorReportTests/sessionRuntimeSectionIncludesRustMemoryWritebackCandidateQueueDiagnostics`
  - validates Unified Doctor detail-lines and typed JSON projection expose Rust writeback candidate diagnostics without memory content.
- `swift test --filter RustHubReadinessPresentationTests/memoryReadinessDecodesWritebackCandidateDiagnostics`
  - validates Rust `/memory/readiness` candidate diagnostics decoding.
- `swift test --filter HubIPCClientProjectCanonicalMemorySyncTests`
  - validates Rust preferred dispatch writes no local `xterminal_project_memory_` file.
  - validates Rust unavailable fallback still queues one local file IPC compatibility event.
  - validates retryable pending snapshot write/clear behavior.
  - validates pending retry success clears the snapshot and pending retry unavailable keeps it.
  - validates memory-context read preference for Rust canonical objects after successful Rust sync status.
  - validates no Rust object read is attempted before successful Rust sync status exists.
  - validates Rust import diagnostics detect missing, stale, metadata-mismatched, and extra deterministic project objects.
  - validates Rust import diagnostics do not fetch Rust objects before successful Rust sync status exists.
  - validates Swift Rust Memory Gateway shadow compare matches product context and records status.
  - validates Swift Rust Memory Gateway shadow compare reports missing Rust anchors as drift.
- `swift test --filter HubIPCClientProjectCanonicalMemorySyncTests/rustMemoryGatewayModelCallPlanShadowRecordsBoundedStatusWhenEnabled`
  - validates XT bounded model-call shadow preflight evidence and no prompt-text persistence.
- `swift test --filter HubAIClientLocalRuntimeRecoveryTests`
  - validates local file-IPC enqueue remains compatible after the non-blocking model-call preflight hook.
- `node --check rust/xhubd/tools/xhubd_daemon.js`
  - validates canonical Rust Hub ops parser syntax after XT model-call shadow evidence rollup.
- temporary `ops-report --memory-gateway-model-call-plan-base-dir <tmp>` smoke
  - validates canonical Rust Hub ops-report reads `memory_gateway_model_call_plan_status.json` / history and emits bounded safety metadata only.
- `swift test --filter HubIPCClientMemoryRetrievalContractTests`
  - validates project-chat retrieval returns `rust_memory_objects` snippets before remote/local retrieval after successful Rust sync status.
- `swift build --target XTerminal`
  - validates Swift shell/client compile after Rust gateway primary gate and doctor rollup changes.
- `swift test --skip-build --filter requestMemoryContextUsesRustGatewayWhenPrimaryGateIsEnabled`
  - validates explicit Rust memory context primary gate uses the Rust gateway response and does not include Swift fallback text.
- `swift test --skip-build --filter requestMemoryContextRequireGate`
  - validates required Rust gateway cutover blocks before contacting Rust when fresh parity evidence is missing.
  - validates required Rust gateway cutover uses Rust output and disables fallback once fresh same-scope parity evidence exists.
- `swift test --filter rustMemoryGatewayCutoverReadiness`
  - validates shadow compare writes bounded history.
  - validates require-readiness needs sustained fresh same-scope parity samples.
  - validates `memory_gateway_cutover_readiness.json` generation.
- `swift test --skip-build --filter SupervisorDoctorTests`
  - validates doctor keeps existing memory assembly findings and now reports Rust gateway shadow drift / authority violation evidence.
- `node --check tools/xhubd_daemon.js`
  - validates daemon ops gate/report syntax after adding bounded memory gateway cutover readiness evidence.

Still intentionally not done:

- No semantic embeddings.
- No full Swift Memory Inspector yet; read-only project list/detail/history exists, but selected/omitted evidence, personal/supervisor surfaces, and Rust-gated mutations remain future work.
- Candidate merge review has a first read-only Rust object comparison slice, but product-grade history/diff inspection remains future work.
- No Node memory authority.
- No public delete/pin/archive candidate mutation surface beyond first-slice stubs; approve/reject candidate flow now exists.
- No full AXMemory writeback authority flip yet; XT caller now prefers Rust for canonical sync, context/retrieval reads can prefer active Rust project objects, and import diagnostics can prove projection drift, but local AXMemory files remain fallback/projection/edit-buffer surfaces rather than durable authority.
- No model execution inside Rust Memory Gateway yet; the gateway is prepare-only for memory context assembly. The launchd-owned live Hub now has fail-closed require mode enabled for memory context gateway calls after fresh profile-suite evidence, while model execution/provider routing remain separate Rust-controlled surfaces.
- Existing file scanner retrieval remains untouched until hybrid retrieval and migration tests land.

## 0) How To Use This File

如果你是新接手的 AI，固定按这个顺序进入：

1. 读本文件 `docs/memory-new/xhub-universal-memory-layer-work-orders-v1.md`
2. 读 `docs/memory-new/xhub-memory-runtime-authority-and-reality-map-v1.md`
3. 读 `docs/memory-new/xhub-memory-writeback-candidate-lifecycle-v1.md`
4. 读 `docs/memory-new/xhub-role-aware-conversation-contract-v1.md`
5. 读 `docs/memory-new/xhub-memory-serving-profile-gateway-alignment-v1.md`
6. 读 `description/MEMORY_SYSTEM.md`
7. 读 `description/SUPERVISOR_AND_CODER.md`
8. 读 `docs/memory-new/xhub-memory-v3-execution-plan.md`
9. 读 `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
10. 读 `docs/memory-new/xhub-memory-support-for-governed-agentic-coding-work-orders-v1.md`
11. 读 `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md`
12. 读 `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
13. 再开始改代码

固定规则：

- 不要把本文件理解成“把 mem0 复制进 X-Hub”。
- 不要为了模型通用性牺牲 X-Hub 的 role/use-mode/scope/sensitivity 安全边界。
- 不要把 personal memory 默认开放给 Coder 或 Supervisor。
- 不要把 remote / cloud memory 变成默认。
- 不要把 Swift UI 改成 memory authority。
- 不要在 Node 兼容层新增 durable memory truth。
- 任何新增 memory behavior 都必须能在 Rust readiness / doctor / evidence report 里解释。

## 1) External Reference Summary

本工单包借鉴的开源系统主要是 mem0 / OpenMemory。参考资料：

- mem0 OpenMemory: `https://mem0.ai/openmemory`
- mem0 open-source overview: `https://docs.mem0.ai/open-source/overview`
- mem0 LLM providers: `https://docs.mem0.ai/components/llms/overview`
- mem0 memory types: `https://docs.mem0.ai/core-concepts/memory-types`
- mem0 search operation: `https://docs.mem0.ai/core-concepts/memory-operations/search`
- mem0 async memory: `https://docs.mem0.ai/open-source/features/async-memory`
- mem0 GitHub: `https://github.com/mem0ai/mem0`
- memsearch local reference: `/Users/andrew.xie/Documents/AX/source/memsearch-main`
  - `README.md`
  - `docs/architecture.md`
  - `docs/design-philosophy.md`
  - `docs/home/comparison.md`
  - `docs/home/embedding-evaluation.md`
  - `src/memsearch/chunker.py`
  - `src/memsearch/store.py`
  - `src/memsearch/reranker.py`
  - `plugins/codex/hooks/`

### 1.1 What mem0 / OpenMemory Does Well

mem0 的优势不是它比 X-Hub 更安全，而是它把 memory 抽成模型外部的通用层：

- Model-agnostic memory:
  - 同一套 memory 可以服务 OpenAI、Anthropic、Ollama、Gemini、Mistral、Bedrock、LM Studio、DeepSeek 等模型入口。
  - 记忆不是塞在某个模型内部，也不是绑定某个 UI。
- Simple scope model:
  - `user_id`
  - `agent_id`
  - `run_id`
  - 容易让任意 agent / app 复用。
- Unified operations:
  - add
  - search
  - update
  - delete
  - history
  - list / get
- Semantic search:
  - embedding / vector search
  - filters
  - top_k
  - threshold
  - optional rerank
- Integration ergonomics:
  - library
  - server
  - MCP
  - OpenAI-compatible flow
  - IDE / coding agent 统一接入
- User-visible memory management:
  - 让用户看到记住了什么
  - 允许编辑、删除、管理
  - 不是完全黑盒

### 1.2 What X-Hub Already Does Better

X-Hub 不是普通 memory SDK。X-Hub 已经有更强的治理边界：

- Rust Hub 作为 product kernel。
- Supervisor 和 Coder 分离。
- Role-aware memory policy 已存在。
- Memory V1 五层合约已存在：
  - `L0_CONSTITUTION`
  - `L1_CANONICAL`
  - `L2_OBSERVATIONS`
  - `L3_WORKING_SET`
  - `L4_RAW_EVIDENCE`
- 高风险 tool act 和 remote prompt bundle 要求 fresh remote snapshot。
- XT remote memory snapshot cache 有 TTL 和 invalidation reason。
- Rust memory 检索和写入有 secret fail-closed。
- Project Coder 默认 project scoped。
- Supervisor 默认治理面更宽，但 personal memory 仍必须受控。
- Lane handoff 支持 refs-only。

所以目标不是“更像 mem0”，而是：

`吸收 mem0 的模型通用 memory layer 优势，同时保留 X-Hub 的 local-first、policy-first、role-aware、fail-closed 安全模型。`

### 1.3 What memsearch-main Adds That X-Hub Should Absorb

`memsearch-main` 的优势更偏 coding-agent memory retrieval engine。它不是 authority model 的参考；X-Hub 不能照搬它的 plugin writes 或 Markdown-as-truth 模型，因为 Hub truth 必须在 Rust object store / Writer + Gate 内。但它有一组值得吸收的 retrieval/index 工程点：

| memsearch advantage | X-Hub absorption status | X-Hub target |
| --- | --- | --- |
| Cross-platform one memory | Partially absorbed | Hub truth + role-aware projection lets XT/Supervisor/Coder consume one truth. Other clients should consume Hub APIs, not local Markdown plugins. |
| Markdown human-readable truth | Not adopted as authority | X-Hub canonical truth remains Rust memory objects/events. Markdown/file outputs may be projection/export only. |
| Rebuildable shadow index | Planned | Any FTS/vector index must be derived from Rust objects or sanctioned projections and droppable/rebuildable. |
| Heading-aware chunking with paragraph fallback | Absorbed for file-scan and first object-store retrieval identity slice | Rust shadow file retrieval chunks `.md`/`.txt` by headings with stable section refs; Rust object retrieval now emits deterministic single-object chunk identity fields for current object/index rows. |
| Content-addressed dedup / stable chunk IDs | Absorbed for current Rust object retrieval/index slices | File-scan refs include stable section line/hash IDs, and object retrieval now emits stable `chunk_id` / `chunk_ref` values from line count + content hash. The derived object index is now chunk-granular; future vector/FTS acceleration must reuse the same identity shape. |
| Hybrid dense + BM25 + RRF | Planned, not implemented | W6 starts with FTS/deterministic boosts; W7 adds local semantic; W8 adds profile-gated fusion/rerank. |
| ONNX bge-m3 int8 local default | Planned, not implemented | Best candidate default for local bilingual embeddings once local runtime supports embedding tasks. Remote embeddings remain off by default. |
| Optional cross-encoder rerank | Planned, not implemented | Profile-gated only for plan/review/deep-dive, never heartbeat/hot execute path by default. |
| Progressive disclosure search -> expand -> transcript | Partially absorbed | X-Hub has L1/L2/L3/L4 policy layers and role transcript projection. Need explicit retrieve/expand/transcript APIs and selected/omitted trace. |
| Watch/debounce live sync | Partially absorbed | X-Hub has sync/retry/gateway shadow compare; canonical watch should be Rust-supervised, not per-client plugin authority. |
| Compact loop into daily memory | Planned as governed candidate path | X-Hub should create write candidates / rollups, not directly mutate durable memory without approval gate. |
| Plugin hook ergonomics | Partially absorbed | XT/Swift should show memory availability and selected/omitted evidence, but hooks must call Hub truth instead of writing local memory authority. |

Current answer to "have we absorbed all useful memsearch advantages?": no. We have absorbed the architecture lessons into the plan and one low-risk Rust retrieval slice, but hybrid semantic retrieval, local ONNX embedding default, RRF/rerank, explicit expand/transcript API, and governed compact/candidate loop are still work items.

### 1.4 Detailed memsearch-main Absorption Work Orders

这些工单只吸收 `memsearch-main` 的 retrieval/index/product ergonomics 优点，不改变 X-Hub authority 边界。所有 durable truth 仍在 Rust memory objects/events；所有模型调用仍必须经过 Rust policy/gateway；Swift/XT 只做 shell、projection、hot cache 和调用。

#### MS-W1 Heading-Aware Chunking And Stable Section Refs

- status: Rust shadow file-scan slice implemented; object-store retrieval chunk identity and chunk-granular derived index implemented in W6.
- source reference:
  - `source/memsearch-main/src/memsearch/chunker.py`
  - `source/memsearch-main/docs/architecture.md`
- value to absorb:
  - Markdown heading sections are natural retrieval units.
  - Oversized sections should split at paragraph/line boundaries with small overlap.
  - Chunk refs should be deterministic from source + line range + content hash.
- X-Hub implementation:
  - Done: `.md` / `.txt` shadow file retrieval now chunks by Markdown headings and returns stable section refs.
  - Done: secret-like section content can be skipped/redacted without hiding unrelated public sections in the same file.
  - Done W6 slice: Rust object-store retrieval keeps the legacy object-level `ref` for old clients while adding stable `chunk_id`, `chunk_ref`, `chunk_identity_schema=xhub.memory.object_chunk_identity.v1`, and line-range evidence.
  - Done W6 slice: derived index migration `0009_memory_object_index_chunks.sql` rebuilds `rust_hub_memory_object_index` as chunk-granular `(memory_id, chunk_id)` rows, still derived/droppable/rebuildable from Rust memory objects.
  - Done W6 slice: `retrieval_kind=get_ref` accepts object refs with or without `#chunk_id`; a chunk ref expands to the governed matching chunk only.
  - Remaining: future vector/FTS acceleration must reuse this identity shape instead of inventing a second ref scheme.
- acceptance:
  - Query for one heading does not return unrelated headings from the same file.
  - Re-running retrieval on unchanged memory returns the same ref.
  - Secret section does not leak and does not poison public sections.
- verification:
  - `cargo test -p xhub-memory markdown`
  - `cargo test -p xhubd memory_object_hybrid_retrieval`
  - `cargo test -p xhub-db memory_object_index`

#### MS-W2 Rebuildable Derived Index

- status: planned in W6.
- source reference:
  - `source/memsearch-main/docs/design-philosophy.md`
  - `source/memsearch-main/src/memsearch/core.py`
- value to absorb:
  - Index is disposable and rebuildable from canonical source.
  - Stale chunks for deleted/changed sources are removed.
- X-Hub adaptation:
  - Canonical source is not Markdown; it is Rust `rust_hub_memory_objects` plus governed projections.
  - Add a derived retrieval index table or in-memory indexed read surface that can be regenerated from active objects.
  - Readiness must report index generation, stale count, and rebuild availability.
- implementation steps:
  1. Define `xhub.memory.hybrid_retrieval.v1` evidence fields.
  2. Add object-store indexed retrieval over active project objects.
  3. Add deterministic chunk IDs for object chunks.
  4. Add reindex/report command once persistent FTS table lands.
  5. Add stale-index detection once persistent index exists.
- acceptance:
  - Deleted/archived objects are not returned.
  - Rebuild from objects produces equivalent refs/scores for unchanged data.
  - Readiness can explain index state without exposing memory text.

#### MS-W3 Hybrid BM25/FTS + Deterministic Boosts

- status: W6 first slice started.
- source reference:
  - `source/memsearch-main/src/memsearch/store.py`
  - `source/memsearch-main/docs/architecture.md`
- value to absorb:
  - Exact terms, identifiers, error codes, and config names need keyword retrieval.
  - Semantic retrieval alone is not enough for coding memory.
- X-Hub adaptation:
  - Start with policy-gated active object filtering, lexical/FTS-like scoring, and deterministic property boosts.
  - Move to SQLite FTS table after first in-memory object retrieval slice is stable.
  - Keep old shadow file scan as fallback until W6 parity is proven.
- first slice shipped in this update:
  - `/memory/search` and `POST /memory/retrieve` can return `source=rust_memory_objects_hybrid_v1` when active project objects match.
  - Response includes `retrieval_engine.schema_version=xhub.memory.hybrid_retrieval.v1`.
  - `semantic_used=false` and `rerank_used=false` are explicit.
  - Result-level explain is available with `explain=true`.
- acceptance:
  - Decision/risk/next-step objects can be found by query.
  - `requested_layers`, `requested_kinds`, `visibility`, `sensitivity_max`, `created_after_ms`, `updated_after_ms` filters work.
  - No active object match falls back to file-scan compatibility.

#### MS-W4 Local ONNX bge-m3 Embedding Default

- status: planned in W7; not implemented.
- source reference:
  - `source/memsearch-main/docs/home/embedding-evaluation.md`
  - `source/memsearch-main/src/memsearch/embeddings/onnx.py`
- value to absorb:
  - `gpahal/bge-m3-onnx-int8` is a strong local bilingual default candidate.
  - CPU-only, no API key, lower dependency footprint than PyTorch, good Chinese/English recall.
- X-Hub adaptation:
  - Implement through Hub Local Provider Runtime as `embedding` task kind.
  - Default remote embeddings off.
  - Embed sanitized local text only; secret/private handling must be policy gated.
  - Readiness must report provider, model, pending/failed counts, local-only status.
- acceptance:
  - Local embedding smoke passes without external API key.
  - Remote embedding attempts are denied unless explicit remote gate permits.
  - Search response says whether semantic retrieval was used.

#### MS-W5 RRF Fusion And Optional Cross-Encoder Rerank

- status: planned in W8; not implemented.
- source reference:
  - `source/memsearch-main/src/memsearch/reranker.py`
  - `source/memsearch-main/docs/architecture.md`
- value to absorb:
  - Dense + keyword result lists should be fused.
  - Cross-encoder rerank improves deep recall but is too expensive for hot paths.
- X-Hub adaptation:
  - Add profile-gated fusion/rerank:
    - heartbeat/hot execute: no semantic, no rerank
    - plan/review: semantic optional, rerank only above candidate threshold
    - deep dive/full scan: semantic + rerank allowed if ready
  - Explain must show why rerank was or was not used.
- acceptance:
  - Hot execute remains under latency budget.
  - Deep dive improves recall fixtures.
  - Remote bundles cannot rerank/expand into raw evidence.

#### MS-W6 Progressive Disclosure Search -> Expand -> Transcript

- status: partially absorbed; explicit APIs still pending.
- source reference:
  - `source/memsearch-main/docs/design-philosophy.md`
  - `source/memsearch-main/plugins/codex/skills/memory-recall/SKILL.md`
- value to absorb:
  - Start cheap with snippets, expand only selected sections, drill into raw transcript only when needed.
- X-Hub adaptation:
  - Map to X-Hub layers:
    - L1/L2 snippets from memory objects
    - L3 working set / role transcript projection
    - L4 raw evidence only with explicit policy allow
  - Add `Get/HTTP expand` that returns full object/section by ref with policy checks.
  - Add selected/omitted trace so UI can show what was used and why.
- acceptance:
  - Search response includes refs enough for expand.
  - Expand enforces same role/use-mode/scope policy.
  - Transcript/raw evidence requests fail closed unless explicitly allowed.

#### MS-W7 Watch/Debounce Live Sync

- status: partially absorbed through sync/retry/gateway shadow compare; canonical Rust watcher still pending.
- source reference:
  - `source/memsearch-main/src/memsearch/watcher.py`
  - `source/memsearch-main/plugins/codex/hooks/session-start.sh`
- value to absorb:
  - Debounced reindex avoids stutter and redundant work.
  - Watcher failures should not crash the session.
- X-Hub adaptation:
  - Watch/sync must be Rust-supervised and evidence-backed, not per-client authority.
  - Apply to sanctioned projection imports and derived index rebuilds.
  - Keep live UI responsive with short TTL caches and route metrics.
- acceptance:
  - Repeated project memory edits coalesce.
  - Index drift is detected and repaired.
  - Watcher errors appear in readiness/doctor without blocking `/health`.

#### MS-W8 Governed Compact/Rollup Candidate Loop

- status: planned; not implemented.
- source reference:
  - `source/memsearch-main/src/memsearch/compact.py`
  - `source/memsearch-main/plugins/codex/hooks/stop.sh`
- value to absorb:
  - Long transcripts need compact summaries.
  - Capture can run asynchronously after a turn.
- X-Hub adaptation:
  - Model-generated compaction must create memory candidates or rollup objects behind approval/policy gates.
  - No direct durable mutation from model summary without Writer + Gate.
  - Store source refs/audit refs, not raw secret text.
- acceptance:
  - Compact candidate creation does not alter active canonical memory.
  - Approval creates active memory object and event.
  - Rejection records event.
  - Secret-like candidates are denied or redacted.

#### MS-W9 Plugin Ergonomics Without Local Authority

- status: partially absorbed; product surface pending.
- source reference:
  - `source/memsearch-main/plugins/codex/skills/memory-recall/SKILL.md`
  - `source/memsearch-main/docs/platforms/codex/how-it-works.md`
- value to absorb:
  - Users need clear "memory available" and recall affordances.
  - Agent should know when memory recall is useful.
- X-Hub adaptation:
  - XT/Swift should show Hub memory availability, selected/omitted evidence, and recall/expand controls.
  - Any hooks or bridge calls must consume Hub truth/projection, not write a second local authority.
- acceptance:
  - UI/XT can show memory status and evidence refs.
  - Coder/Supervisor prompts can cite selected Hub memory refs.
  - No new XT-local durable memory writer is introduced.

## 2) Current Local Architecture Baseline

当前代码路径：

- Rust memory crate:
  - `rust/rust hub/crates/xhub-memory/src/lib.rs`
- Rust daemon endpoints:
  - `rust/rust hub/crates/xhubd/src/main.rs`
  - `rust/rust hub/crates/xhubd/src/memory_bridge.rs`
- XT Hub memory client:
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
- XT memory role/use-mode policy:
  - `x-terminal/Sources/Hub/XTMemoryUsePolicy.swift`
- XT remote snapshot cache:
  - `x-terminal/Sources/Hub/HubRemoteMemorySnapshotCache.swift`
- Supervisor memory assembly:
  - `x-terminal/Sources/Supervisor/SupervisorTurnContextAssembler.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorMemoryAssemblySnapshot.swift`
- Project / Coder memory:
  - `x-terminal/Sources/Project/AXMemory.swift`
  - `x-terminal/Sources/Project/AXMemoryPipeline.swift`
  - `x-terminal/Sources/Project/AXProjectContext.swift`
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
- Swift local IPC compatibility:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/FileIPC.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/UnixSocketServer.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryRetrievalBuilder.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RustLiveFileIPCBridge.swift`
- Node compatibility memory retrieval:
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js`

当前 Rust memory 的特点：

- 支持 `/memory/search`
- 支持 `/memory/retrieve`
- 支持 `/memory/write` / `/memory/append`
- 支持 `/memory/readiness`
- `project_code` mode 默认包含 dialogue window + project capsule，不包含 personal capsule。
- `assistant_personal` mode 才包含 personal capsule。
- Rust writer authority 由以下环境变量共同 gate：
  - `XHUB_RUST_MEMORY_WRITER_AUTHORITY`
  - `XHUB_RUST_MEMORY_WRITE_AUTHORITY`
  - `XHUB_RUST_MEMORY_PRODUCTION_AUTHORITY`
- 目前检索主要是文件扫描 + lexical score。
- 支持 `.json`、`.jsonl`、`.md`、`.txt`。
- `.md` / `.txt` file-scan retrieval now has memsearch-inspired heading-aware chunking with stable section refs, so one large Markdown file no longer returns as a single monolithic chunk.
- source kind 主要由路径启发式推断。

当前短板：

- 还没有统一的 `memory_id` object lifecycle。
- Rust memory write 更偏 append file record，缺少 update/delete/history/list/get。
- Rust 还没有统一 Memory Gateway 拦在所有 model request 前。
- AXMemory project memory 仍有大量 truth 在 XT local project store。
- 没有统一 hybrid retrieval index。
- 没有 optional semantic index / embedding abstraction。
- 没有 local ONNX bge-m3 embedding default、BM25+dense+RRF、cross-encoder rerank，只有 shadow file-scan chunking 的第一步。
- 没有 memory inspector 产品面。
- Node / Swift compatibility path 仍会让下一位 AI 误以为 memory authority 分散。

## 3) Target Architecture

目标形态：

`All model calls -> Rust Memory Gateway -> role/use-mode/scope/sensitivity policy -> memory context/retrieval -> provider/model route -> response -> memory write candidate -> governed writeback`

### 3.1 Memory Authority Target

Rust Hub must own:

- memory object schema
- durable memory store
- memory CRUD
- memory history
- memory index
- memory search/retrieve
- memory role/scope policy
- memory write candidates
- memory approval gate
- memory audit events
- memory readiness / doctor evidence

Swift shell must own:

- memory inspector UI
- edit forms
- confirmation prompts
- revoke/delete/pin UX
- display of selected/omitted memory evidence
- calling Rust endpoints

XT must own:

- Coder and Supervisor prompt assembly invocation
- local hot window for continuity
- project-local fallback while Rust unavailable
- visible routing and diagnostics presentation

Node compatibility must own only:

- legacy bridge
- old clients
- compatibility report
- migration smoke

### 3.2 Universal Scope Model

Adopt a mem0-like scope vocabulary, but map it into X-Hub governance:

| Universal scope | X-Hub mapping | Default access | Notes |
| --- | --- | --- | --- |
| `user` | personal capsule / assistant personal | denied for Coder, explicit grant for assistant surfaces | Must never leak into project code by default |
| `project` | project capsule / AXMemory / project code | allowed for Project Coder, selected for Supervisor | Main coding memory scope |
| `session` | run / chat / active workflow / recent context | allowed within current session | TTL and freshness matter |
| `agent` | Supervisor / Coder / skill-specific memory | role-gated | Useful for model-agnostic agent memory |
| `org` | portfolio brief / shared policy / project registry | Supervisor-oriented | Coder gets selected refs only unless allowed |
| `device` | device canonical memory / runtime config | shell/kernel only | Strong sensitivity gate |

### 3.3 Memory Object Schema v1

Minimum durable object:

```json
{
  "schema_version": "xhub.memory.object.v1",
  "memory_id": "mem_...",
  "scope": "project",
  "owner_id": "project_or_user_or_agent_id",
  "run_id": "optional_run_id",
  "project_id": "optional_project_id",
  "agent_id": "optional_agent_id",
  "source_kind": "project_capsule",
  "layer": "l1_canonical",
  "title": "short title",
  "text": "memory content",
  "summary": "bounded summary",
  "tags": ["optional"],
  "sensitivity": "internal",
  "visibility": "local_only",
  "status": "active",
  "pinned": false,
  "immutable": false,
  "ttl_ms": null,
  "created_at_ms": 0,
  "updated_at_ms": 0,
  "last_accessed_at_ms": 0,
  "version": 1,
  "provenance": {
    "source": "xt_project_memory_sync",
    "audit_ref": "audit-...",
    "created_by": "rust_hub",
    "evidence_refs": []
  },
  "policy": {
    "write_gate": "canonical_writer",
    "allowed_roles": ["chat", "supervisor"],
    "denied_roles": [],
    "remote_export": "local_only"
  }
}
```

Allowed enum baseline:

- `scope`
  - `user`
  - `project`
  - `session`
  - `agent`
  - `org`
  - `device`
- `layer`
  - `l0_constitution`
  - `l1_canonical`
  - `l2_observations`
  - `l3_working_set`
  - `l4_raw_evidence`
- `sensitivity`
  - `public`
  - `internal`
  - `private`
  - `secret`
- `visibility`
  - `local_only`
  - `sanitized_remote_ok`
  - `refs_only`
  - `never_export`
- `status`
  - `active`
  - `candidate`
  - `archived`
  - `deleted`
  - `rejected`

### 3.4 Memory Event Schema v1

Every write-like operation must append an event:

```json
{
  "schema_version": "xhub.memory.event.v1",
  "event_id": "mev_...",
  "memory_id": "mem_...",
  "operation": "create",
  "actor": "rust_hub",
  "reason": "project_memory_sync",
  "before_version": null,
  "after_version": 1,
  "policy_decision": "allow",
  "deny_code": "",
  "audit_ref": "audit-...",
  "created_at_ms": 0
}
```

Operations:

- `create`
- `update`
- `delete`
- `archive`
- `restore`
- `pin`
- `unpin`
- `candidate_create`
- `candidate_approve`
- `candidate_reject`
- `reindex`
- `redact`
- `access`

## 4) Global Safety Constraints

All work orders must obey:

- Local-first by default.
- Policy before prompt.
- X-Constitution remains pinned L0 and cannot be overwritten by memory CRUD.
- Personal memory remains default denied for Project Coder.
- Supervisor only receives personal memory under explicit contract and privacy mode.
- Raw evidence does not cross remote export gate unless sanitized and explicitly allowed.
- Secret-looking content must fail closed before indexing, search result rendering, writeback, export, or UI display.
- Embeddings must not index secret/private content unless local-only and policy-approved.
- Deleting memory must not leave retrievable stale index entries.
- Updating memory must preserve history.
- Swift UI must not become authority.
- Node compatibility must not become authority.

## 5) Execution Order

Critical path:

1. `UML-W0` contract freeze and baseline evidence
2. `UML-W1` Rust memory object store schema
3. `UML-W2` Rust CRUD/history/list/get API
4. `UML-W3` role/use-mode/scope/sensitivity policy gate
5. `UML-W4` AXMemory -> Rust canonical sync
6. `UML-W5` Memory Gateway for model calls
7. `UML-W6` hybrid retrieval v1 with deterministic/FTS index
8. `UML-W7` optional semantic index
9. `UML-W8` rerank / adaptive expansion profiles
10. `UML-W9` write candidate pipeline
11. `UML-W10` Swift Memory Inspector
12. `UML-W11` doctor/evidence/ops gates
13. `UML-W12` migration, dual-run, rollback
14. `UML-W13` release gates and docs

Parallel lanes:

- `UML-W6` and `UML-W10` can start after `UML-W2` schema stubs exist.
- `UML-W7` can run behind a feature flag after `UML-W6`.
- `UML-W11` should run throughout, not only at the end.
- `UML-W13` can be updated incrementally as each work order closes.

## 6) Work Orders

### UML-W0 Contract Freeze And Baseline Evidence

- priority: P0
- owner: Rust Hub / XT Runtime / Security
- goal:
  - Freeze the Universal Memory Layer v1 contract before code changes.
  - Capture current runtime behavior so later AI can detect regressions.
- borrowed from open source:
  - mem0 makes memory integration simple because its external contract is clear.
  - X-Hub needs the same clarity, but with stronger governance fields.
- write set:
  - `docs/memory-new/xhub-universal-memory-layer-work-orders-v1.md`
  - optional: `docs/memory-new/schema/xhub-memory-object-v1.schema.json`
  - optional: `docs/memory-new/schema/xhub-memory-event-v1.schema.json`
- implementation steps:
  1. Extract current Rust memory endpoint behavior:
     - `/memory/readiness`
     - `/memory/search`
     - `/memory/retrieve`
     - `/memory/write`
  2. Extract current XT memory role/use-mode matrix from `XTMemoryUsePolicy.swift`.
  3. Extract current Supervisor memory assembly contract.
  4. Extract current Project Coder Memory V1 sections.
  5. Freeze the object schema and event schema.
  6. Freeze mapping from universal scopes to X-Hub scopes.
  7. Add a baseline report under `rust/rust hub/reports/` or `x-hub-system/build/reports/`.
- acceptance:
  - A new AI can read the frozen schema and implement APIs without asking what fields mean.
  - Scope mapping table is explicit.
  - Personal memory default deny for Coder is explicitly documented.
  - Remote export behavior is explicitly documented.
- verification commands:
  - `rg -n "memory_writer_authority|MemoryMode|RetrievalPlan" "rust/rust hub/crates/xhub-memory/src/lib.rs"`
  - `rg -n "XTMemoryUseMode|XTMemoryRequesterRole|XTMemoryLayer" x-terminal/Sources/Hub/XTMemoryUsePolicy.swift`
  - `rg -n "MEMORY_V1|L0_CONSTITUTION|L1_CANONICAL|L4_RAW_EVIDENCE" x-terminal/Sources/Chat/ChatSessionModel.swift`
- risks:
  - If the schema is too broad, implementation will drift.
  - If the schema is too narrow, migration from AXMemory will lose useful facts.
- guardrails:
  - Freeze v1 minimal schema first.
  - Add new optional fields only after W1/W2 tests pass.

### UML-W1 Rust Memory Object Store Schema

- priority: P0
- owner: Rust Hub Kernel
- goal:
  - Add a durable Rust-owned memory object store.
  - Stop treating memory write as only file append.
- write set:
  - `rust/rust hub/crates/xhub-memory/src/lib.rs`
  - `rust/rust hub/crates/xhubd/src/memory_bridge.rs`
  - `rust/rust hub/crates/xhubd/src/main.rs`
  - any existing SQLite/storage helper under `rust/rust hub/crates/*`
  - tests under the relevant Rust crates
- design:
  - Use SQLite as durable canonical store.
  - Keep file scanner as compatibility/import source.
  - Store memory objects and memory events separately.
  - Enforce unique `memory_id`.
  - Keep tombstones for deletes.
- minimum tables:
  - `memory_objects`
  - `memory_events`
  - `memory_index_state`
  - optional `memory_object_tags`
- minimum `memory_objects` columns:
  - `memory_id TEXT PRIMARY KEY`
  - `schema_version TEXT NOT NULL`
  - `scope TEXT NOT NULL`
  - `owner_id TEXT NOT NULL`
  - `run_id TEXT`
  - `project_id TEXT`
  - `agent_id TEXT`
  - `source_kind TEXT NOT NULL`
  - `layer TEXT NOT NULL`
  - `title TEXT NOT NULL`
  - `text TEXT NOT NULL`
  - `summary TEXT NOT NULL`
  - `tags_json TEXT NOT NULL`
  - `sensitivity TEXT NOT NULL`
  - `visibility TEXT NOT NULL`
  - `status TEXT NOT NULL`
  - `pinned INTEGER NOT NULL`
  - `immutable INTEGER NOT NULL`
  - `ttl_ms INTEGER`
  - `created_at_ms INTEGER NOT NULL`
  - `updated_at_ms INTEGER NOT NULL`
  - `last_accessed_at_ms INTEGER NOT NULL`
  - `version INTEGER NOT NULL`
  - `provenance_json TEXT NOT NULL`
  - `policy_json TEXT NOT NULL`
- minimum `memory_events` columns:
  - `event_id TEXT PRIMARY KEY`
  - `memory_id TEXT NOT NULL`
  - `operation TEXT NOT NULL`
  - `actor TEXT NOT NULL`
  - `reason TEXT NOT NULL`
  - `before_version INTEGER`
  - `after_version INTEGER`
  - `before_json TEXT`
  - `after_json TEXT`
  - `policy_decision TEXT NOT NULL`
  - `deny_code TEXT NOT NULL`
  - `audit_ref TEXT NOT NULL`
  - `created_at_ms INTEGER NOT NULL`
- implementation steps:
  1. Add Rust structs:
     - `MemoryObject`
     - `MemoryObjectProvenance`
     - `MemoryObjectPolicy`
     - `MemoryEvent`
     - `MemoryObjectStatus`
     - `MemoryScope`
     - `MemoryLayer`
     - `MemorySensitivity`
     - `MemoryVisibility`
  2. Add sanitizers for every public field.
  3. Add ID generator:
     - `mem_` prefix for objects
     - `mev_` prefix for events
  4. Add database migration or lazy table creation.
  5. Add `create_memory_object` internal function.
  6. Add `append_memory_event` internal function.
  7. Ensure secret-looking text is denied before insert.
  8. Ensure deleted/archived records do not appear in default retrieval.
- acceptance:
  - Memory object can be created in SQLite with event.
  - Invalid scope/layer/sensitivity/status is rejected.
  - Secret-looking text is rejected before database insert.
  - Delete tombstone is representable.
  - Existing `/memory/readiness` reports object store readiness.
- tests:
  - `memory_object_create_roundtrip`
  - `memory_object_rejects_secret_text`
  - `memory_object_rejects_invalid_scope`
  - `memory_event_appended_on_create`
  - `memory_deleted_object_not_retrieved`
- verification commands:
  - `cargo test -p xhub-memory memory_object`
  - `cargo test -p xhubd memory_object`
- risks:
  - Schema migration may diverge from existing file-based runtime.
  - Object store may accidentally become parallel truth before sync rules exist.
- guardrails:
  - Initially expose object store behind read/write feature flag.
  - Keep existing file scan retrieval untouched until W6 migration tests pass.

### UML-W2 Rust Universal Memory CRUD API

- priority: P0
- owner: Rust Hub Kernel / API Contracts
- goal:
  - Provide mem0-like universal operations while preserving X-Hub policy.
- endpoints:
  - `POST /memory/objects`
  - `GET /memory/objects/{memory_id}`
  - `GET /memory/objects`
  - `PATCH /memory/objects/{memory_id}`
  - `DELETE /memory/objects/{memory_id}`
  - `POST /memory/objects/{memory_id}/archive`
  - `POST /memory/objects/{memory_id}/restore`
  - `POST /memory/objects/{memory_id}/pin`
  - `POST /memory/objects/{memory_id}/unpin`
  - `GET /memory/objects/{memory_id}/history`
  - `POST /memory/candidates`
  - `POST /memory/candidates/{candidate_id}/approve`
  - `POST /memory/candidates/{candidate_id}/reject`
- write set:
  - `rust/rust hub/crates/xhubd/src/main.rs`
  - `rust/rust hub/crates/xhubd/src/memory_bridge.rs`
  - `rust/rust hub/crates/xhub-memory/src/lib.rs`
  - command wrappers under `rust/rust hub/tools/` if existing style supports it
- API request examples:

```json
{
  "scope": "project",
  "owner_id": "project_123",
  "project_id": "project_123",
  "source_kind": "project_capsule",
  "layer": "l1_canonical",
  "title": "Routing authority decision",
  "text": "Provider/model route authority now lives in Rust.",
  "tags": ["route", "authority"],
  "sensitivity": "internal",
  "visibility": "local_only",
  "audit_ref": "audit-..."
}
```

- API response baseline:

```json
{
  "schema_version": "xhub.memory.object_result.v1",
  "ok": true,
  "status": "created",
  "memory_id": "mem_...",
  "version": 1,
  "event_id": "mev_...",
  "deny_code": "",
  "audit_ref": "audit-..."
}
```

- implementation steps:
  1. Add route dispatch.
  2. Add JSON parsing with camelCase and snake_case compatibility.
  3. Add list filters:
     - `scope`
     - `owner_id`
     - `project_id`
     - `agent_id`
     - `source_kind`
     - `layer`
     - `status`
     - `sensitivity`
     - `visibility`
     - `tag`
     - `limit`
     - `cursor`
  4. Add optimistic update:
     - `expected_version`
  5. Add immutable/pinned guard.
  6. Add event append for every mutation.
  7. Add HTTP status mapping:
     - policy deny -> `403`
     - validation error -> `400`
     - conflict -> `409`
     - missing -> `404`
  8. Add CLI/tool command parity if this repo uses tool wrappers for Rust Hub operations.
- acceptance:
  - CRUD operations work against local Rust Hub.
  - History returns ordered events.
  - Update conflict fails closed.
  - Delete keeps tombstone and removes from default search.
  - Pin prevents accidental delete unless force path is explicitly implemented and gated.
- tests:
  - `memory_object_http_create_get_list`
  - `memory_object_http_update_conflict`
  - `memory_object_http_delete_tombstone`
  - `memory_object_history_ordered`
  - `memory_object_pin_blocks_delete`
- verification commands:
  - `cargo test -p xhubd memory_object_http`
  - `curl -fsS http://127.0.0.1:50151/memory/readiness`
  - `bash tools/daemon_ops_gate.command --max-slow-requests 0`
- risks:
  - Exposing CRUD before policy gate could allow unsafe writes.
- guardrails:
  - W2 must call W3 gate stubs even if W3 rules are conservative.
  - Deny by default for unknown scope/role/source.

### UML-W3 Role / Use-Mode / Scope / Sensitivity Policy Gate

- priority: P0
- owner: Rust Hub Kernel / Security / XT Runtime
- goal:
  - Move core memory access decisions into Rust so all models share the same safety contract.
- write set:
  - `rust/rust hub/crates/xhub-memory/src/lib.rs`
  - `rust/rust hub/crates/xhubd/src/memory_bridge.rs`
  - `rust/rust hub/crates/xhubd/src/xt_contract.rs`
  - `x-terminal/Sources/Hub/XTMemoryUsePolicy.swift`
  - tests in Rust and Swift
- policy input:

```json
{
  "requester_role": "chat",
  "use_mode": "project_chat",
  "scope": "project",
  "owner_id": "project_123",
  "project_id": "project_123",
  "agent_id": "coder",
  "requested_layers": ["l1_canonical", "l3_working_set"],
  "requested_source_kinds": ["project_capsule"],
  "remote_export_requested": false,
  "freshness_required": false,
  "audit_ref": "audit-..."
}
```

- policy output:

```json
{
  "ok": true,
  "decision": "allow",
  "deny_code": "",
  "downgrade_code": "",
  "allowed_layers": ["l1_canonical", "l3_working_set"],
  "allowed_source_kinds": ["project_capsule"],
  "visibility_floor": "local_only",
  "raw_evidence_allowed": false,
  "personal_memory_allowed": false,
  "requires_fresh_snapshot": false
}
```

- minimum rules:
  - `project_chat + chat`
    - allow project/session/agent scoped memory for current project
    - deny user personal by default
    - allow L0-L4 only if local and role policy allows
  - `supervisor_orchestration + supervisor`
    - allow org/project/session selected memory
    - deny user personal unless explicit assistant personal mode and grant
    - default raw evidence false
  - `tool_act_high_risk + tool`
    - require fresh snapshot
    - deny stale TTL cache
    - deny L4 raw evidence by default
  - `lane_handoff + lane`
    - refs-only
    - deny fulltext
  - `remote_prompt_bundle + remoteExport`
    - require fresh snapshot
    - sanitized only
    - deny raw evidence
  - unknown role/use_mode/scope:
    - deny
- implementation steps:
  1. Port the stable semantics from `XTMemoryUsePolicy.swift` into Rust policy structs.
  2. Keep Swift policy as client-side preflight and UI explanation, not authority.
  3. Add `/memory/policy/evaluate`.
  4. Ensure every CRUD/search/retrieve/write endpoint evaluates policy.
  5. Add policy evidence into all responses.
  6. Add deny/downgrade codes aligned with XT existing codes:
     - `memory_layer_not_allowed_for_mode`
     - `user_memory_grant_required`
     - `cross_scope_memory_denied`
     - `longterm_fulltext_pd_required`
     - `raw_evidence_remote_export_denied`
     - `memory_snapshot_stale_for_high_risk_act`
     - `lane_handoff_fulltext_denied`
     - `memory_mode_contract_missing`
     - `memory_route_policy_mismatch`
- acceptance:
  - Rust policy results match Swift policy for existing modes.
  - Unknown mode fails closed.
  - Coder cannot read personal memory by default.
  - Supervisor cannot receive raw evidence by default.
  - Remote prompt bundle cannot receive raw evidence.
  - Lane handoff is refs-only.
- tests:
  - Rust policy golden matrix.
  - Swift/Rust parity fixture if feasible.
  - Adversarial secret/private/cross-project tests.
- verification commands:
  - `cargo test -p xhub-memory memory_policy`
  - `cargo test -p xhubd memory_policy`
  - `swift test --filter XTMemory`
- risks:
  - Two policy implementations can drift.
- guardrails:
  - Rust is source of authority.
  - Swift surfaces policy result and can preflight, but cannot override Rust allow/deny.

### UML-W4 AXMemory To Rust Canonical Sync

- priority: P0
- owner: XT Runtime / Rust Hub Kernel
- goal:
  - Move project durable memory toward Rust canonical records while preserving XT local fallback.
- write set:
  - `x-terminal/Sources/Project/AXMemory.swift`
  - `x-terminal/Sources/Project/AXMemoryPipeline.swift`
  - `x-terminal/Sources/Project/AXProjectStore.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `rust/rust hub/crates/xhub-memory/src/lib.rs`
  - `rust/rust hub/crates/xhubd/src/memory_bridge.rs`
- current source:
  - `.xterminal/ax_memory.json`
  - `.xterminal/AX_MEMORY.md`
  - `.xterminal/raw_log.jsonl`
  - `.xterminal/memory_lifecycle/latest_after_turn.json`
- target:
  - AXMemory remains local fallback and import/export projection.
  - Rust object store becomes canonical project memory source.
  - Every successful AXMemory update emits a Rust memory sync candidate or direct write under writer authority.
- mapping:
  - `AXMemory.goal` -> `project` / `l1_canonical` / `project_goal`
  - `requirements` -> `project` / `l1_canonical` / `project_requirement`
  - `currentState` -> `project` / `l2_observations` or `l3_working_set`
  - `decisions` -> `project` / `l1_canonical` / `decision_track`
  - `nextSteps` -> `project` / `l3_working_set` / `next_step`
  - `openQuestions` -> `project` / `l2_observations`
  - `risks` -> `project` / `l2_observations`
  - `recommendations` -> `project` / `l2_observations`
- implementation steps:
  1. Done: Rust accepts existing `ProjectCanonicalMemoryIPCRequest` payloads at `POST /memory/project-canonical-sync`.
  2. Done: `HubIPCClient.syncProjectCanonicalMemory` prefers Rust HTTP in `.auto` / `.grpc` and preserves `.fileIPC` local compatibility.
  3. Done: existing `AXMemoryPipeline.updateMemory` callers continue through `syncProjectCanonicalMemory`, so successful AXMemory updates now enter the Rust-preferred path.
  4. Done: if Rust HTTP is unavailable, record pending sync under `.xterminal/memory_lifecycle/pending_project_canonical_rust_sync.json`.
  5. Done: on project load, retry pending sync in the background.
  6. Done: after successful Rust project canonical sync status, XT memory-context assembly reads active Rust project objects and prefers them over local projection / Hub remote snapshot for L1 canonical, L2 observations, and L3 working set.
  7. Done: after successful Rust project canonical sync status, `requestMemoryRetrieval` can return `rust_memory_objects` snippets from active Rust project objects before remote/local retrieval.
  8. Done: add Swift import diagnostics that compare current AXMemory-derived expected deterministic Rust objects against active Rust objects, fail closed until successful Rust sync status exists, and report missing/stale/metadata-mismatched/extra records.
  9. Add idempotency key:
     - project_id
     - AXMemory updatedAt
     - normalized section hash
  10. Avoid duplicate records.
  11. Add Rust import endpoint if needed:
     - `POST /memory/import/ax-project`
- acceptance:
  - Done at bridge/caller level: updating project memory can create or update Rust memory objects through deterministic project canonical sync.
  - Done at bridge level: re-running sync updates deterministic Rust memory IDs and appends history.
  - Done at caller level: Rust unavailable does not break Coder prompt and falls back to local file IPC in `.auto`.
  - Done at local diagnostics level: pending sync is visible in `.xterminal/memory_lifecycle/pending_project_canonical_rust_sync.json`.
  - Done at read-preference level: when `canonical_memory_sync_status.json` says the project was delivered to Rust, Coder/Supervisor memory-context assembly can hydrate L1/L2/L3 from Rust active project objects first, and project memory retrieval can return Rust object snippets first.
  - Done at import diagnostics level: XT can detect AXMemory-to-Rust drift for deterministic project canonical objects without touching Rust before successful sync status.
  - Still needed: Rust object history points back to AXMemory lifecycle audit.
- tests:
  - Done: AXMemory / project canonical payload encoding through existing `ProjectCanonicalMemoryIPCRequest`.
  - Done: Rust object creation/update/history from project canonical sections.
  - Done: Swift Rust-preferred dispatch and offline fallback.
  - Done: pending retry success clears the snapshot and retry unavailable preserves it.
  - Done: Swift memory-context read preference uses Rust canonical project objects only after successful Rust sync status.
  - Done: Swift memory-context read preference does not touch Rust object store before successful Rust sync status.
  - Done: Swift project-chat memory retrieval prefers Rust canonical project objects after successful Rust sync status.
  - Done: Swift import diagnostics detect missing, stale, metadata-mismatched, and extra deterministic Rust project objects.
  - Done: Swift import diagnostics do not fetch Rust objects before successful Rust sync status.
  - Still needed: AXMemory lifecycle audit ref assertions.
- verification commands:
  - `swift test --filter HubIPCClientProjectCanonicalMemorySyncTests`
  - `cargo test -p xhub-db`
  - `cargo test -p xhubd`
- risks:
  - Duplicate memory records could pollute retrieval.
  - Local fallback and Rust canonical could diverge.
- guardrails:
  - Sync must write provenance and section hash.
  - Retrieval should prefer active Rust object over stale local projection once synced.

### UML-W5 Universal Memory Gateway For Model Calls

- priority: P0
- owner: Rust Hub Kernel / XT Runtime / Model Routing
- goal:
  - Make memory model-agnostic by routing all model calls through a common Rust Memory Gateway.
- borrowed from open source:
  - mem0 advantage is that any model can use the same memory layer.
  - X-Hub should do this at kernel level, not per UI prompt.
- write set:
  - `rust/rust hub/crates/xhubd/src/main.rs`
  - `rust/rust hub/crates/xhubd/src/model_bridge.rs`
  - `rust/rust hub/crates/xhubd/src/memory_bridge.rs`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Project/AXMemoryPipeline.swift`
- target API:
  - `POST /memory/context`
  - `POST /model/generate-with-memory`
  - or an internal preflight:
    - `POST /memory/gateway/prepare`
    - model call remains in existing route
- gateway input:
  - requester role
  - use mode
  - project id
  - agent id
  - model route intent
  - latest user text
  - current local sections
  - risk tier
  - remote export requested
  - budget/profile
- gateway output:
  - memory context text
  - selected memory ids
  - omitted memory ids
  - deny/downgrade codes
  - token usage
  - freshness
  - cache hit
  - remote export posture
  - audit ref
- implementation steps:
  1. Done: add Rust memory context builder that can assemble prepare-only Memory V1 context slots from object store + request payload.
     - `POST /memory/gateway/prepare`
     - `POST /memory/context`
     - `xhubd memory gateway-prepare`
     - returns schema `xhub.memory.gateway_prepare.v1`
     - default layers are L1/L2/L3; L4 raw evidence is never default.
     - response includes selected slots, `context_text`, Rust policy result, and skip counters.
  2. Done: add Swift shadow compare while keeping existing Swift builders as product output.
     - `HubIPCClient.compareMemoryContextWithRustGateway(...)`
     - automatic background compare only when `XHUB_RUST_MEMORY_CONTEXT_GATEWAY_SHADOW=1`
     - records latest compare to `memory_gateway_shadow_compare_status.json`
     - product output is unchanged; this is not a cutover.
  3. Done: add doctor/evidence rollup for latest `memory_gateway_shadow_compare_status.json`.
     - parity drift becomes `memory_gateway_shadow_compare_drift`.
     - unexpected shadow authority change becomes blocking `memory_gateway_shadow_authority_violation`.
  4. Done: add opt-in caller integration gate while keeping existing Swift builders as product fallback.
     - `XHUB_RUST_MEMORY_CONTEXT_GATEWAY=1`
     - non-`.fileIPC` routes try Rust `/memory/gateway/prepare` before existing builders.
     - Rust success returns product-compatible `MemoryContextResponsePayload`.
     - Rust unavailable/denied/unsafe/empty responses fall back; this is not fail-closed production cutover.
  5. Done: add explicit fail-closed require gate for Coder/Supervisor context callers.
     - `XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE=1`
     - requires fresh same-scope `memory_gateway_shadow_compare_status.json` parity evidence.
     - missing/stale/mismatched evidence returns `rust_memory_gateway_cutover_gate` and disables local fallback.
     - successful required Rust response records `memory_gateway_safety_mode=fail_closed_required_after_shadow_parity`.
  6. Done: add sustained live parity evidence report.
     - `memory_gateway_shadow_compare_history.json`
     - `memory_gateway_cutover_readiness.json`
     - requires N fresh same-scope parity samples before reporting `ready_for_require=true`.
  7. Done for Supervisor Doctor: include cutover readiness report in memory assembly diagnostics and Doctor findings.
  8. Done: include cutover readiness report in daemon ops gate / ops report without adding hot-path runtime work.
  7. Change AXMemory coarse/refine model calls to request memory through gateway where relevant.
  8. Change skill execution memory needs to call gateway.
  9. Done: add gateway result into model usage audit and doctor detail lines.
  10. Add no-memory fallback only where policy allows.
  11. Done SG-C2 first Rust slice: add first-class `serving_profile_id` parsing and requested/effective profile evidence, using `docs/memory-new/xhub-memory-serving-profile-gateway-alignment-v1.md` as the contract.
  12. Done SG-C3 first Swift caller slice: make XT callers send profile IDs from existing context-depth/review-depth/use-mode resolvers, record profile evidence in shadow compare/history, and fail closed on wrong-profile require evidence.
  13. Done SG-C3 verification: `swift test --filter rustMemoryGateway` passes.
  14. Done SG-C5 first ops rollup slice: `xhubd_daemon.js` now forwards scoped profile fields, counts per-profile readiness samples from shadow history, and reports profile downgrade/Rust deny counters without prompt text.
  15. Done SG-C5 first Swift Doctor display slice: memory gateway shadow/readiness findings now include `serving_profile_id`, `selected_profile`, and `effective_profile`.
  16. Done SG-C5 Swift report/export rollup slice: Swift-generated `memory_gateway_cutover_readiness.json` now carries `profile_readiness[]`, `profile_readiness_sample_count`, `profile_downgrade_count`, and `rust_deny_count`; Doctor detail includes a compact per-profile readiness sample.
  17. Done SG-C3 caller coverage test: public `requestMemoryContextDetailed(...)` sends canonical Rust profile IDs for session resume, project review, supervisor deep dive, high-risk tool clamp, remote prompt M0/M1, and explicit M4.
  18. Done SG-C6 live profile-suite evidence: launchd-owned local runner collected sustained M0/M1/M2/M3/M4 evidence in the live base dir.
  19. Done SG-C7 live fail-closed require rollout: current user launchd session and `com.ax.xhubd.local.plist` now enable `XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE=1` with parity max age `600000`.
- acceptance:
  - Done at prepare surface level: Rust can assemble policy-gated context text from active memory objects.
  - Done at prepare surface level: Gateway records selected slots and skip counters.
  - Done at prepare surface level: Gateway enforces Rust policy before model route.
  - Done at prepare surface level: Remote export requests exclude local-only objects.
  - Done at Swift shadow level: product Memory V1 remains unchanged while Rust gateway compare can detect parity or drift.
  - Done at Swift shadow level: latest compare status is schema-versioned and stored locally for doctor/evidence consumption.
  - Done at doctor/evidence level: shadow drift and authority-safety violations are visible in Supervisor memory assembly readiness and doctor findings.
  - Done at opt-in caller level: `XHUB_RUST_MEMORY_CONTEXT_GATEWAY=1` can make Coder/Supervisor memory context assembly prefer Rust gateway output while preserving compatibility fallback.
  - Done at gated cutover level: `XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE=1` blocks fallback until fresh same-scope shadow parity evidence exists, then uses Rust gateway output with fail-closed safety metadata.
  - Done at live evidence level: sustained same-scope shadow parity is summarized in `memory_gateway_cutover_readiness.json`.
  - Done at Rust profile envelope level: old callers derive M1/M0, explicit M0/M2/M4 requests return profile evidence, and remote deep profile requests downgrade before export.
  - Done at XT caller level: Rust gateway requests carry `serving_profile_id`, profile evidence is stored in shadow compare/history, and require-mode evidence must match profile.
  - Done at XT caller coverage level: session/project/supervisor/tool/remote prompt paths are covered by targeted Swift tests for expected Rust profile IDs.
  - Done at ops/doctor evidence level: ops and Swift-generated readiness reports include bounded per-profile readiness counts, downgrade counts, and deny counts.
  - Done at live profile-suite level: sustained live profile-scoped parity and cutover readiness exist for M0/M1/M2/M3/M4.
  - Coder, Supervisor, coarse/refine, skills can use one memory gateway.
  - Memory V1 text remains backward compatible.
  - Existing prompt sections still appear.
  - Done at live operational level: fail-closed require mode is enabled in the current launchd session and persisted in the LaunchAgent plist.
- tests:
  - Done: Rust gateway prepare returns policy-gated project slots.
  - Done: Rust gateway prepare defaults exclude raw evidence.
  - Done: Rust gateway prepare denies Supervisor raw evidence request.
  - Done: Rust gateway prepare remote export skips local-only objects.
  - Done: Swift shadow compare matches product context and records status.
  - Done: Swift shadow compare reports missing Rust anchors as drift.
  - Done: Swift doctor reports shadow drift and shadow authority violation.
  - Done: Swift caller uses Rust gateway output when `XHUB_RUST_MEMORY_CONTEXT_GATEWAY=1`.
  - Done: Swift require gate fails closed without fresh parity evidence and uses Rust with `fail_closed_required_after_shadow_parity` when evidence is fresh.
  - Done: Swift readiness evidence report requires sustained fresh parity history before `ready_for_require=true`.
  - Coder prompt still includes Memory V1.
  - Supervisor prompt still includes selected sections.
  - High-risk tool act requires fresh memory.
  - Remote prompt bundle sanitized only.
  - Gateway denied result does not call model.
- verification commands:
  - `cargo test -p xhubd memory_gateway`
  - `swift build --target XTerminal`
  - `swift test --skip-build --filter requestMemoryContextUsesRustGatewayWhenPrimaryGateIsEnabled`
  - `swift test --skip-build --filter SupervisorDoctorTests`
  - `swift test --filter ChatSessionModel`
  - `swift test --filter Supervisor`
- risks:
  - Moving assembly too fast could break prompt quality.
  - Treating M0..M4 as authority tiers could accidentally bypass policy/grant/export gates.
- guardrails:
  - Keep feature flag:
    - `XHUB_RUST_MEMORY_CONTEXT_GATEWAY`
  - Start in shadow compare mode:
    - Swift build and Rust build both run
    - product uses Swift until diff stable
  - Cut over only when doctor reports parity.
  - Profile requests are not entitlements; Rust policy decides effective profile/layers.

### UML-W6 Hybrid Retrieval v1 With Deterministic And FTS Index

- priority: P1
- owner: Rust Hub Kernel / Memory Retrieval
- status: implemented-ci-gated-slice
- goal:
  - Improve retrieval beyond lexical file scan without jumping directly to always-on embeddings.
- write set:
  - `rust/rust hub/crates/xhub-memory/src/lib.rs`
  - Rust storage/index helper modules
  - `rust/rust hub/crates/xhubd/src/memory_bridge.rs`
  - tests
- design:
  - Stage 1: policy gate
  - Stage 2: deterministic filters
  - Stage 3: SQLite FTS or lexical scorer
  - Stage 4: cheap properties boost
  - Stage 5: optional semantic search in W7
  - Stage 6: optional rerank in W8
- deterministic properties:
  - `has_code`
  - `has_todo`
  - `has_error`
  - `has_decision`
  - `has_approval`
  - `has_blocker`
  - `has_link`
  - `title_like`
- retrieval request additions:
  - `filters`
  - `layers`
  - `source_kinds`
  - `sensitivity_max`
  - `visibility`
  - `created_after_ms`
  - `updated_after_ms`
  - `top_k`
  - `threshold`
  - `explain`
- implementation steps:
  1. Done first slice: equivalent in-memory full-text over active Rust memory objects for `/memory/search` / `POST /memory/retrieve`, with file-scan fallback when no object match exists.
  2. Done first slice: index only project-scoped active non-secret memory objects when `project_id` is supplied.
  3. Done first slice: deterministic property extraction at retrieval time:
     - `has_code`
     - `has_todo`
     - `has_error`
     - `has_decision`
     - `has_approval`
     - `has_blocker`
     - `has_link`
     - title-like lexical overlap
  4. Done W6 slice: add `memory object-index-rebuild` / `memory reindex` CLI command.
  5. Done W6 slice: add stale-index detection and readiness evidence:
     - `memory_index_ready`
     - `memory_index_row_count`
     - `memory_index_stale_count`
     - `memory_index_generation.latest_indexed_at_ms`
  6. Done first slice: add explain output when `explain=true`:
     - score
     - lexical_score
     - property_boost
     - policy_filter
     - omitted reason
  7. Done W6 slice: persistent rebuildable derived index table `rust_hub_memory_object_index`; `/memory/retrieve` prefers this table and can rebuild it on demand before falling back to live object scan.
  8. Done W6 slice: selected/omitted trace ledger for `explain=true` retrieval:
     - `retrieval_trace.selected`
     - `retrieval_trace.omitted`
     - stable `reason_code` values for layer/source/visibility/sensitivity/no-match/inactive/secret filters
     - content-redacted omission evidence for UI/debug surfaces
  9. Done W6 slice: route-sensitive HTTP quality bench:
     - `tools/memory_hybrid_quality_bench.command`
     - covers project chat, supervisor next-step layer filter, remote sanitized visibility, raw-evidence opt-in, and private sensitivity filter
     - asserts derived index source, trace schema, top hit, and no production authority change
  10. Done W6 slice: Rust BM25-style scorer over the derived index:
      - policy/filter gate runs before BM25 corpus statistics
      - `retrieval_engine.fts=derived_index_bm25_rust`
      - `retrieval_engine.bm25_used=true`
      - `explain.bm25_score` and trace selected rows expose BM25 contribution
      - SQLite FTS5 remains optional future acceleration, not a portability dependency
  11. Done W6 slice: sustained/large fixture retrieval quality bench:
      - `tools/memory_hybrid_quality_bench.command --profile large`
      - deterministic 80+ object fixture with route/domain/reviewer/noise records
      - quality metrics:
        - `precision_at_1`
        - `recall_at_k`
        - `filter_pass_rate`
        - `trace_coverage`
      - default `quick` profile remains lightweight for daily validation
  12. Done W6 slice: quick bench CI/source gate:
      - `scripts/ci/rust_memory_hybrid_quality_gate.sh`
      - `.github/workflows/rust-memory-hybrid-quality-gate.yml`
      - runs syntax check plus quick route-sensitive quality bench
      - writes `build/reports/rust_memory_hybrid_quality_gate_summary.v1.json`
      - keeps large profile manual/nightly to avoid slowing normal validation
  13. Done W6 slice: stable object chunk identity evidence:
      - retrieval results keep legacy `ref=memory://rust/object/{memory_id}` for old clients
      - retrieval results and selected/omitted trace rows add `chunk_ref=memory://rust/object/{memory_id}#object-1-{line_count}-{content_hash}`
      - `chunk_id`, `chunk_identity_schema`, `chunk_start_line`, and `chunk_end_line` are machine-readable
      - `get_ref` continues to accept object refs with or without `#chunk_id`
      - live-scan fallback uses the same content hash as the derived index, so unchanged objects produce equivalent chunk refs across rebuild
  14. Done W6 slice: chunk-granular derived object index:
      - migration `0009_memory_object_index_chunks.sql` replaces the derived index with `(memory_id, chunk_id)` primary key rows
      - rebuild splits long object text into bounded chunks with small line overlap
      - short objects remain one chunk
      - `retrieval_engine.index_granularity=object_chunk`
      - `retrieval_engine.chunk_expand_via_get_ref=true`
      - exact chunk refs expand through the existing governed `retrieval_kind=get_ref` path, without adding Swift/local authority
  15. Done W6 slice: gateway/model-call-plan chunk evidence alignment:
      - `/memory/gateway/prepare` now prefers the chunk-granular derived index and falls back to active object reads only when the index is unavailable
      - `slots.objects[]`, `selected_refs[]`, and `omitted_refs[]` carry `chunk_ref`, `chunk_id`, line range, and `chunk_identity_schema`
      - omitted refs are content-free and capped through the existing trace cap
      - `index_granularity=object_chunk`, `chunk_expand_via_get_ref=true`, `index_source`, and rebuild evidence are machine-readable
      - `/memory/gateway/model-call-plan` mirrors the chunk selected/omitted evidence in `memory_context` while keeping `context_text_included=false`
  16. Done W6 Swift projection slice:
      - `HubIPCClient` decodes cached model-call-plan selected/omitted chunk refs, selected chunk count, omitted ref count, index source/granularity, chunk schema, and `chunk_expand_via_get_ref` while preserving old cache compatibility
      - Project Memory Inspector selection evidence shows only content-free chunk shape/counts and logs no memory IDs, chunk refs, prompt/context text, project IDs, or object content
      - `XTUnifiedDoctor` and generic Doctor export project chunk counts/schema/line-range samples without exporting full refs or IDs
  17. Done W6 ops rollup slice:
      - `memory_gateway_cutover_smoke.js` carries content-free model-call-plan chunk rollups into `memory_gateway_cutover_readiness.json`
      - `xhubd_daemon.js` ops-report/ops-gate reads XT model-call-plan shadow cache and cutover readiness chunk rollups without exporting `selected_refs[]`, `omitted_refs[]`, memory IDs, chunk refs, prompt/context text, or object content
      - `production_live_stability_gate.js` and `production_live_stability_session.js` propagate the same chunk count/schema/index fields through live stability summaries without changing blocking gate semantics
  18. Keep old file scan retrieval as compatibility import.
- acceptance:
  - Retrieval quality improves for project decision/blocker/next-step queries.
  - Policy gate runs before index search.
  - Deleted records are not returned.
  - Secret records are not indexed.
  - Explain output can justify selected snippets.
- tests:
  - Done first slice: `memory_object_hybrid_retrieval_finds_decision_with_explain`
  - Done first slice: `memory_object_hybrid_retrieval_filters_layer_and_supports_get_ref`
  - Done W6 slice: `memory_object_reindex_command_recovers_derived_index`
  - Done W6 slice: `tools/memory_hybrid_quality_bench.command`
  - Done W6 slice: `tools/memory_hybrid_quality_bench.command --profile large`
  - Done W6 slice: `memory_hybrid_retrieval_filters_scope`
  - Done W6 slice: `memory_hybrid_retrieval_omits_deleted`
  - Done W6 slice: `memory_hybrid_retrieval_explain`
  - Done W6 slice: `memory_hybrid_reindex_recovers`
  - Done W6 slice: `memory_object_hybrid_retrieval_finds_decision_with_explain` asserts `chunk_ref` / `chunk_id` / `chunk_identity_schema`
  - Done W6 slice: `memory_object_hybrid_retrieval_filters_layer_and_supports_get_ref` asserts `get_ref` accepts a chunk-ref-shaped object ref
  - Done W6 slice: `memory_object_hybrid_retrieval_returns_long_object_chunk_ref`
  - Done W6 slice: xhub-db `memory_object_index_rebuilds_long_objects_as_stable_chunks`
  - Done W6 slice: xhub-db `migrations_are_idempotent_and_create_scheduler_tables` updated for migration `0009`
  - Done W6 slice: `memory_gateway_prepare_returns_policy_gated_project_slots` asserts selected/omitted chunk refs
  - Done W6 slice: `memory_gateway_model_call_plan_wraps_prepare_without_execution` asserts model-call-plan mirrors chunk refs content-free
  - Done W6 Swift projection slice: `MemoryInspectorTests.selectionEvidenceCacheDecodesChunkRefsWithoutContent`, `MemoryInspectorTests.selectionEvidenceRefreshReadsCachedRustStatusWithoutLoggingRefs`, `HubIPCClientProjectCanonicalMemorySyncTests/rustMemoryGatewayModelCallPlanShadowRecordsBoundedStatusWhenEnabled`, and `XTUnifiedDoctorReportTests/sessionRuntimeSectionIncludesRustMemorySelectionEvidenceProjection`
  - Done W6 ops rollup slice: JS syntax checks for `xhubd_daemon.js`, `memory_gateway_cutover_smoke.js`, `production_live_stability_gate.js`, `production_live_stability_session.js`; `memory_gateway_cutover_smoke.js --self-test`; temp status-cache `ops-report` smoke validates chunk rollup without ref leakage
- verification commands:
  - `cargo test -p xhubd memory_object_hybrid_retrieval`
  - `cargo test -p xhubd memory_hybrid_retrieval`
  - `cargo test -p xhubd memory_object_reindex_command_recovers_derived_index`
  - `cargo test -p xhubd memory_object_hybrid_retrieval_returns_long_object_chunk_ref`
  - `cargo test -p xhub-db memory_object_index`
  - `cargo test -p xhub-db migrations_are_idempotent`
  - `cargo test -p xhubd memory_gateway_prepare`
  - `cargo test -p xhubd memory_gateway_model_call`
  - `bash tools/memory_hybrid_quality_bench.command`
  - `bash tools/memory_hybrid_quality_bench.command --profile large`
  - `bash ../../scripts/ci/rust_memory_hybrid_quality_gate.sh`
- risks:
  - Index drift.
  - Search quality regressions hidden by old lexical fallback.
- guardrails:
  - Keep route-sensitive quick and large bench green before production cutover.
  - Report index generation and stale count in readiness.

### UML-W7 Optional Semantic Index And Embedding Provider Abstraction

- priority: P1
- owner: Rust Hub Kernel / Local ML Runtime / Security
- goal:
  - Add semantic retrieval while preserving local-first safety and cost control.
- borrowed from open source:
  - mem0 search benefits from vector/semantic matching.
  - memsearch's `gpahal/bge-m3-onnx-int8` evaluation is the best current local default candidate for bilingual coding memory: CPU-only, no API key, small enough for managed download, and better Chinese recall than common API/default alternatives.
  - X-Hub should support this as optional profile-based capability.
- write set:
  - `rust/rust hub/crates/xhub-memory/src/lib.rs`
  - Rust local ML bridge modules
  - `rust/rust hub/crates/xhubd/src/main.rs`
  - `rust/rust hub/crates/xhubd/src/memory_bridge.rs`
  - readiness/report tools
- design:
  - Embedding provider is pluggable.
  - Default disabled until local model readiness passes.
  - Secret/private records are not embedded unless explicitly local-only and policy-approved.
  - Embeddings stored in local runtime root.
  - Embedding index is rebuildable from canonical objects.
- provider options:
  - local embedding model
  - LM Studio compatible local endpoint
  - future provider route, but remote embedding must be explicitly allowed
- implementation steps:
  1. Add `MemoryEmbeddingProvider` trait.
  2. Add `none` provider.
  3. Add local provider integration behind feature flag.
  4. Add embedding job queue:
     - pending
     - complete
     - failed
     - skipped_policy
  5. Add vector storage:
     - SQLite blob or local vector index
     - exact format should be simple and recoverable in v1
  6. Add semantic search stage after FTS candidates or standalone if configured.
  7. Add readiness fields:
     - `semantic_index_enabled`
     - `embedding_provider`
     - `embedding_pending_count`
     - `embedding_failed_count`
     - `remote_embedding_allowed`
- acceptance:
  - Semantic index disabled by default.
  - Enabling semantic index does not index secrets.
  - Local provider failure falls back to hybrid lexical/FTS.
  - Search response says whether semantic was used.
  - Rebuild regenerates embeddings.
- tests:
  - provider none path
  - secret skip path
  - local provider mock path
  - fallback path
  - rebuild path
- verification commands:
  - `cargo test -p xhub-memory semantic`
  - `cargo test -p xhubd embedding`
  - `bash tools/local_ml_execution_smoke.command`
- risks:
  - Latency and cost.
  - Remote embedding privacy leak.
- guardrails:
  - Default off.
  - Remote embedding denied by default.
  - Per-scope allowlist required.

### UML-W8 Rerank And Adaptive Expansion Profiles

- priority: P1
- owner: Rust Hub Kernel / Supervisor / Coder Runtime
- goal:
  - Use rerank and expansion only when the mode/profile warrants it.
- borrowed from open source:
  - mem0 supports reranker search.
  - memsearch adds BM25+dense RRF plus optional cross-encoder rerank.
  - X-Hub should use fusion/rerank selectively, not always-on.
- write set:
  - `rust/rust hub/crates/xhub-memory/src/lib.rs`
  - `rust/rust hub/crates/xhubd/src/memory_bridge.rs`
  - `x-terminal/Sources/Hub/XTMemoryUsePolicy.swift`
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- profiles:
  - `m0_heartbeat`
    - no semantic/rerank
    - tiny budget
  - `m1_execute`
    - FTS/hybrid only
  - `m2_plan_review`
    - allow semantic if ready
    - no expensive rerank unless candidate count high
  - `m3_deep_dive`
    - allow semantic + rerank
  - `m4_full_scan`
    - allow broader expansion but still policy-gated
- expansion outcomes:
  - `answer_directly`
  - `expand_shallow`
  - `delegate_traversal`
- implementation steps:
  1. Add expansion decision function.
  2. Inputs:
     - candidate_count
     - requested_depth
     - token_risk_ratio
     - broad_time_range_indicator
     - multi_hop_indicator
     - needs_raw_chunk
  3. Add profile caps.
  4. Add rerank abstraction.
  5. Add explain output:
     - trigger_flags
     - budget_pressure
     - policy_floor
     - raw_evidence_allowed
  6. Add regression fixtures for over-expand and under-expand.
- acceptance:
  - Execute mode stays fast.
  - Deep dive improves recall.
  - High-risk tool act remains conservative.
  - Remote bundle cannot expand into raw evidence.
  - Explain shows why expansion happened.
- tests:
  - expansion profile matrix
  - deep dive recall fixture
  - high-risk clamp fixture
  - remote export no raw evidence
- verification commands:
  - `cargo test -p xhub-memory expansion`
  - `swift test --filter XTMemory`
- risks:
  - Rerank can add latency and unstable results.
- guardrails:
  - Add latency budget per profile.
  - Add ops gate for p95/p99.

### UML-W9 Governed Memory Write Candidate Pipeline

- priority: P1
- owner: Rust Hub Kernel / XT Runtime / Security
- status: in-progress-rust-extractor-xt-caller-swift-queue-diagnostics-doctor-slices
- lifecycle spec:
  - `docs/memory-new/xhub-memory-writeback-candidate-lifecycle-v1.md`
- goal:
  - Add mem0-like automatic memory capture without "remember everything" behavior.
- target:
  - Model responses and user turns can produce memory candidates.
  - Candidates require policy gate before becoming canonical.
  - Sensitive/personal/project boundaries stay intact.
- write set:
  - `rust/rust hub/crates/xhub-memory/src/lib.rs`
  - `rust/rust hub/crates/xhubd/src/memory_bridge.rs`
  - `x-terminal/Sources/Project/AXMemoryPipeline.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- candidate schema:

```json
{
  "schema_version": "xhub.memory.candidate.v1",
  "candidate_id": "mc_...",
  "scope": "project",
  "owner_id": "project_123",
  "source_kind": "decision_track",
  "layer": "l1_canonical",
  "title": "Decision",
  "text": "Use Rust as provider route authority.",
  "confidence": 0.82,
  "reason": "durable_project_decision",
  "requires_approval": true,
  "policy_decision": "pending",
  "audit_ref": "audit-..."
}
```

- implementation steps:
  1. Done first slice: use candidate status in memory object table (`status='candidate'`).
  2. Done first slice: add candidate creation/list API:
     - `POST /memory/writeback/candidates`
     - `GET /memory/writeback/candidates`
     - CLI `candidate-create` / `candidate-list`
  3. Done first slice: add candidate approval/reject API:
     - `POST /memory/writeback/candidates/{memory_id}/approve`
     - `POST /memory/writeback/candidates/{memory_id}/reject`
     - object aliases under `/memory/objects/{memory_id}/approve|reject`
     - CLI `candidate-approve` / `candidate-reject`
  4. Done Rust slice: add deterministic candidate extractor for AXMemory deltas:
     - `POST /memory/writeback/candidates/extract`
     - CLI `candidate-extract --payload-json ...`
     - accepts `delta` / `ax_memory_delta` envelopes with AXMemoryDelta camelCase or snake_case fields
     - maps goal/requirements/current state/decisions/next steps/open questions/risks/recommendations into policy-gated `status='candidate'` memory objects
     - supports `dry_run=1` and CLI `--dry-run`
     - secret-like candidate text/audit refs fail closed before any batch write
  5. Add optional model-assisted candidate extractor later.
  6. Done Rust slice: deterministic duplicate detection:
     - candidate memory IDs include a stable project/kind/text hash
     - same-batch duplicates are skipped
     - existing active/candidate/rejected/deleted IDs are skipped with duplicate reason codes
  7. Done XT caller slice: wire `AXMemoryPipeline` / `HubIPCClient` into Rust deterministic candidate extraction:
     - model-generated AXMemory deltas call `POST /memory/writeback/candidates/extract?apply=1`
     - runtime fallback deltas call the same Rust extractor
     - removal-only / empty deltas are skipped to avoid candidate noise
     - existing local AXMemory files remain compatibility fallback/projection, not authority escalation
     - raw-log evidence records `active_write=false`, `requires_approval=true`, and `production_authority_change=false`
  8. Done Swift shell queue slice:
     - detailed work order: `W9-C3` in `docs/memory-new/xhub-memory-writeback-candidate-lifecycle-v1.md`
     - `HubIPCClient` lists/approves/rejects Rust writeback candidates.
     - `ProjectSettingsView` shows a compact selected-project pending queue in the Rust-refactored `x-hub-system/x-terminal` app.
     - Swift shell records bounded review evidence and does not edit local active memory.
  9. Done Rust TTL/stale maintenance slice:
     - detailed work order: `W9-C2` in `docs/memory-new/xhub-memory-writeback-candidate-lifecycle-v1.md`
     - `POST /memory/writeback/candidates/maintenance` and CLI `candidate-maintenance`
     - dry-run by default; explicit apply archives low-risk stale candidates and marks canonical candidates `stale_review_required`
     - readiness includes bounded maintenance summary evidence
  10. Done conflict/supersession metadata:
      - detailed work order: `W9-C4` in `docs/memory-new/xhub-memory-writeback-candidate-lifecycle-v1.md`
      - candidate create records same scope/source_kind/layer active conflicts in policy/provenance metadata.
      - conflicting candidate approval requires explicit `conflict_resolution_reason`.
      - newer pending candidates archive older same-key pending candidates with `superseded_by`.
      - rejected candidates are not resurrected by supersession.
  11. Done candidate lifecycle ops smoke:
      - detailed work order: `W9-C5` in `docs/memory-new/xhub-memory-writeback-candidate-lifecycle-v1.md`
      - `rust/xhubd/tools/memory_writeback_candidate_smoke.command`
      - isolated temp daemon proves pending/rejected candidates stay out of active retrieval, approved candidates retrieve, secret-like candidates fail closed, extractor stays candidate-only, and stale maintenance remains bounded.
  12. Done candidate diagnostics and noise metrics:
      - detailed work order: `W9-C6` in `docs/memory-new/xhub-memory-writeback-candidate-lifecycle-v1.md`
      - `GET /memory/writeback/candidates` returns top-level `candidate_diagnostics`.
      - `/memory/readiness` exposes `object_store.writeback_candidates.diagnostics`.
      - diagnostics include conflict/stale/stale-review/supersession counts, planned archive/review counts, `queue_pressure`, `noise_score`, bounded IDs, and `production_authority_change=false`.
  13. Done Swift conflict approval reason and Doctor surfacing:
      - detailed work order: `W9-C7` in `docs/memory-new/xhub-memory-writeback-candidate-lifecycle-v1.md`
      - Swift decodes Rust candidate diagnostics/policy/provenance.
      - conflicting approve requires `conflict_resolution_reason`; blank reasons fail closed before the Rust call.
      - `ProjectSettingsView` shows a conflict approval reason field and disables approve until filled.
      - `XTUnifiedDoctor` consumes Rust `/memory/readiness` and emits bounded `rust_memory_writeback_candidate_queue_*` detail-lines.
      - `XTUnifiedDoctorSection.rustMemoryWritebackCandidateQueueProjection` exports typed JSON fields for candidate queue diagnostics.
  14. Done Swift merge review detail comparison:
      - detailed work order: `W9-C11` in `docs/memory-new/xhub-memory-writeback-candidate-lifecycle-v1.md`
      - `HubIPCClient` fetches Rust-owned memory object details through `GET /memory/objects/{memory_id}`.
      - `ProjectSettingsView` can expand a candidate and compare referenced `conflict_with`, `supersedes`, and `superseded_by` objects.
      - local evidence records only reference/object/missing counts and never logs referenced memory content.
      - Swift remains read-only for merge review; approval/reject/maintenance authority stays in Rust endpoints.
- acceptance:
  - Candidate creation does not alter active canonical memory.
  - Approval creates active memory object and event.
  - Rejection records event.
  - Secret candidates are denied or redacted.
  - Duplicate candidates collapse.
  - Conflict approvals require a reviewer reason.
  - Candidate merge review can compare Rust-owned conflict/supersession references without becoming a local memory writer.
  - Doctor/readiness can explain queue pressure and candidate noise without showing candidate content.
- tests:
  - Done first slice: `memory_writeback_candidate_create_list_approve_roundtrip`
  - Done first slice: `memory_writeback_candidate_rejects_and_blocks_invalid_transitions`
  - Done first slice: `memory_writeback_candidate_secret_like_content_fails_closed`
  - Done Rust slice: `memory_writeback_candidate_extracts_axmemory_delta_and_dedupes`
  - Done Rust slice: `memory_writeback_candidate_extract_dry_run_and_secret_fail_closed`
  - Done XT caller slice: `AXMemoryPipelineTests.memoryWritebackCandidatePayloadEncodesAXMemoryDeltaForRustExtractor`
  - Done XT caller slice: `AXMemoryPipelineTests.emitMemoryWritebackCandidatesCallsRustExtractorAndLogsCandidateOnlyResult`
  - Done XT caller slice: `AXMemoryPipelineTests.memoryDeltaHasCandidateContentIgnoresRemovalOnlyDelta`
  - Done Swift shell queue slice: `MemoryWritebackCandidateQueueTests.rustCandidateListResponseDecodesPendingObject`
  - Done Swift shell queue slice: `MemoryWritebackCandidateQueueTests.queueStoreRefreshProjectsPendingNotActiveTruth`
  - Done Swift shell queue slice: `MemoryWritebackCandidateQueueTests.approveAndRejectCallRustDecisionPathAndWriteEvidence`
  - Done Swift shell queue slice: `MemoryWritebackCandidateQueueTests.secretCandidatePreviewIsHiddenByDefault`
  - Done Rust TTL/stale maintenance: `memory_writeback_candidate_maintenance_dry_run_does_not_mutate`
  - Done Rust TTL/stale maintenance: `memory_writeback_candidate_maintenance_archives_stale_working_set`
  - Done Rust TTL/stale maintenance: `memory_writeback_candidate_maintenance_marks_canonical_stale_review_required`
  - Done Rust TTL/stale maintenance: `memory_writeback_candidate_maintenance_ignores_active_and_rejected`
  - Done Rust diagnostics: `memory_writeback_candidate` tests cover candidate diagnostics, conflict pressure, supersession, and stale-review counts.
  - Done Swift diagnostics: `MemoryWritebackCandidateQueueTests` covers diagnostics decode and conflict reason fail-closed behavior.
  - Done Doctor diagnostics: `XTUnifiedDoctorReportTests/sessionRuntimeSectionIncludesRustMemoryWritebackCandidateQueueDiagnostics` covers detail-lines plus typed JSON projection export.
  - Done readiness decode: `RustHubReadinessPresentationTests/memoryReadinessDecodesWritebackCandidateDiagnostics`
  - Done merge review detail comparison: `MemoryWritebackCandidateQueueTests` covers Rust object detail decode, conflict/supersedes fetch, and content-free evidence.
- verification commands:
  - `cargo test -p xhubd memory_writeback_candidate`
  - `swift test --filter AXMemoryPipelineTests`
  - `swift test --filter MemoryWritebackCandidateQueueTests`
  - `swift test --filter XTUnifiedDoctorReportTests/sessionRuntimeSectionIncludesRustMemoryWritebackCandidateQueueDiagnostics`
  - `swift test --filter RustHubReadinessPresentationTests/memoryReadinessDecodesWritebackCandidateDiagnostics`
- risks:
  - Too many candidates can become noise.
  - Auto-approval can corrupt durable truth.
- guardrails:
  - Default candidate, not direct write, for model-extracted memories.
  - No class auto-promotes until a separate auto-approval gate is designed and validated.
  - Never auto-promote credentials, identity/payment/legal/medical/financial/safety facts, X-Constitution/grant/revoke/kill-switch/route authority state, cross-scope imports, personal memory visible to Project Coder, untrusted connector content, ambiguous-source facts, `sensitivity=secret`, broader-than-local visibility, or anything that weakens export/audit/grant/policy.

### UML-W10 Swift Memory Inspector

- priority: P1
- status: Project Memory Inspector read/detail/history/selection-evidence plus Rust-owned archive/delete/pin/unpin controls implemented through 2026-05-30; Assistant/User Memory Inspector now has a separate fail-closed readiness/Rust reveal-grant gate, gated list/detail/history shell, and Rust-owned governance actions through 2026-06-03
- owner: Swift Shell / Product UI / Security
- goal:
  - Make memory visible and manageable without moving authority out of Rust.
- borrowed from open source:
  - OpenMemory's product advantage is user-visible shared memory management.
- write set:
  - `x-terminal/Sources/UI/SettingsView.swift`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Sources/UI/SupervisorSettingsView.swift`
  - new Swift files under `x-terminal/Sources/UI/Memory/`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - optional X-Hub app settings surfaces
- UI surfaces:
  - Project Memory Inspector
  - Assistant/User Memory Inspector
  - Supervisor Memory Evidence View
  - Candidate Queue
  - Per-turn selected/omitted memory panel
- required views:
  - list memory objects
  - filter by scope/layer/source_kind/status/sensitivity
  - inspect object detail
  - history timeline
  - selected in current turn
  - omitted with reason
  - approve/reject candidates
  - archive/delete
  - pin/unpin
- UI safety:
  - Do not render secret text.
  - Private memory requires explicit reveal gate.
  - Delete/archive must show confirmation.
  - Personal memory must not appear inside project view unless explicitly granted and labeled.
- implementation steps:
  1. Done first read-only slice: add `HubIPCClient.listMemoryObjectsViaRust` for Rust `GET /memory/objects` with project/status/layer/source_kind/sensitivity filters.
  2. Done first read-only slice: add `XTMemoryInspectorStore` and `XTMemoryInspectorPresentation` models under the Rust-refactored `x-terminal` app.
  3. Done first read-only slice: add Project Settings `Project Memory Inspector` list/detail rows for current-project Rust memory objects.
  4. Done first read-only slice: fail closed in the Swift shell projection by dropping cross-scope/personal objects from the project inspector even if Rust returns them.
  5. Done first read-only slice: write bounded `xt.memory_inspector_refresh.v1` evidence with counts/filter presence only and no memory IDs/content.
  6. Done via `UML-W9`: candidate queue approve/reject/maintenance/merge-review surfaces are already implemented as Rust-owned flows.
  7. Done second read-only slice: add Rust `GET /memory/objects/{memory_id}/history` caller and test override.
  8. Done second read-only slice: add per-object history expansion in Project Settings showing operation/actor/version/policy/audit metadata only.
  9. Done second read-only slice: write bounded `xt.memory_inspector_history.v1` evidence with event counts/operation summary only and no memory IDs/content.
  10. Done third read-only slice: decode Rust model-call-plan `prepare`, `selected_refs`, selected/omitted/denied counts, effective layers, and skipped reason buckets into Swift evidence models while remaining backward-compatible with older cache files.
  11. Done third read-only slice: add a Project Settings `Project Memory Inspector` selection-evidence panel that reads only cached `memory_gateway_model_call_plan_status.json` / bounded history, filters to current-project samples, drops cross-scope refs from the project view, and does not recompute memory selection on the chat path.
  12. Done third read-only slice: write bounded `xt.memory_selection_evidence_view.v1` raw-log evidence with counts/reason buckets only and no memory IDs, prompt text, context text, or object content.
  13. Done fourth read-only slice: extend the same cached selected/omitted evidence projection into `XTUnifiedDoctor` session runtime diagnostics and the generic XT doctor export as typed `rustMemorySelectionEvidenceProjection` / `rust_memory_selection_evidence_snapshot` JSON.
  14. Done fourth read-only slice: keep Doctor selection evidence content-free by dropping memory IDs, project IDs, prompt/context text, and object content; expose only source/status, counts, reason buckets, selected layer/source/sensitivity/visibility aggregates, bounded ref metadata samples, and execution/text safety booleans.
  15. Done fifth read-only slice: wire fuller Rust `retrieval_trace.omitted.reason_code` buckets into prepare/model-call-plan `omitted_reason_counts`, cached Swift selection evidence, Project Memory Inspector, `XTUnifiedDoctor`, generic XT Doctor export, `memory_gateway_cutover_smoke.js`, and `xhubd_daemon.js` ops-report/ops-gate. This stays content-free and does not recompute memory selection on Doctor/Inspector paths.
  16. Done sixth slice: add Rust-owned `archive/delete/pin/unpin` object mutation gate with HTTP/CLI entrypoints, explicit archive/delete confirmation, archive-clears-pin behavior, tombstone delete, immutable fail-closed behavior, memory event history, `/memory/readiness` `object_store.mutation_gate` evidence, and no Swift authority transfer.
  17. Done seventh slice: add Swift `HubIPCClient.mutateMemoryObjectViaRust(...)` caller, mutation payload/result decoding, test override hooks, and `XTMemoryInspectorStore.mutateProjectObject(...)` bounded `xt.memory_inspector_object_mutation.v1` evidence without rendering controls or creating local authority.
  18. Done eighth slice: render Project Memory Inspector archive/delete/pin/unpin icon controls from Rust gate state, require confirmation UI for archive/delete, disable duplicate in-flight actions, avoid optimistic destructive UI, refresh from Rust after success, and keep all mutation writes Rust-owned.
  19. Done ninth slice: add a separate Assistant/User Memory Inspector gate/snapshot model in the Rust-refactored `x-terminal` app. It evaluates cached Rust `/memory/readiness` object-store readiness plus an explicit user-scope grant, labels the surface as `scope=user · authority=rust_memory_object_store · Swift shell only`, and defaults fail-closed.
  20. Done ninth slice: add `refreshAssistantUser(...)` as a gated shell path that does not call Rust `GET /memory/objects?scope=user` until readiness and grant are both satisfied, filters returned objects back to user scope, drops cross-scope/project returns, and keeps Project Inspector behavior unchanged.
  21. Done tenth slice: wire the Assistant/User gate into `SupervisorPersonalMemoryCenterView` as a compact Rust gate shell. It fetches bounded `/memory/readiness`, labels Rust authority, strips title/text/summary/provenance/policy from the shell snapshot, and renders only gate status/object counts/drop counts with `content=hidden`.
  22. Done eleventh slice: replace the local reveal placeholder with Rust-owned `POST /memory/user-reveal-grant/issue|evaluate|revoke`. The grant is a short-TTL `xhub.memory.user_reveal_grant.v1` envelope, file-backed under the Rust runtime root, content-free, deny-by-default for Project Coder/project use-modes, and never grants model-serving authority.
  23. Done eleventh slice: add Swift `HubIPCClient.requestMemoryUserRevealGrantViaRust(...)` with decode/test override support, make `XTMemoryInspectorStore.refreshAssistantUser(...)` accept/evaluate the Rust grant envelope, and make `SupervisorPersonalMemoryCenterView` request/evaluate/revoke through Rust before listing user-scope shell objects.
  24. Done twelfth slice: project `/memory/readiness.object_store.user_reveal_grant` into XT Unified Doctor and the generic XHub Doctor export as content-free readiness-only evidence (`rustMemoryUserRevealGrantProjection` / `rust_memory_user_reveal_grant_snapshot`) without object scans, memory IDs, project IDs, prompt/context text, or user memory content.
  25. Done thirteenth slice: add the gated Assistant/User object list/detail/history shell in `SupervisorPersonalMemoryCenterView`. It renders only user-scope metadata after Rust readiness plus an active Rust reveal grant, fetches detail/history on demand, strips title/text/summary/provenance/policy from shell objects, drops cross-scope objects/events, and never appears in Project Settings or Project Coder context by default.
  26. Done fourteenth slice: add Rust-owned Assistant/User object governance actions. User-scope `archive/delete/pin/unpin` now require an active Rust reveal grant id at the Rust mutation gate, allow only the Assistant/User inspector use-mode with Supervisor role, keep Project Coder/model-context access denied, and return content-free mutation denial envelopes when the grant is missing, expired, mismatched, or authority-unsafe.
  27. Done fourteenth slice: add Swift shell Assistant/User mutation controls in `SupervisorPersonalMemoryCenterView`. Pin/unpin call the same Rust mutation wrapper, archive/delete require confirmation, payloads carry `requester_role=supervisor`, `use_mode=assistant_user_memory_inspector`, and the active reveal grant id, and `XTMemoryInspectorStore.mutateAssistantUserObject(...)` keeps returned objects shell-sanitized with title/text/summary/provenance/policy stripped.
  28. Done fifteenth slice: update the Rust-refactored XT shell to read chunk-level cached model-call-plan evidence from Rust. `HubIPCClient`, Project Memory Inspector, and `XTUnifiedDoctor` now understand selected/omitted chunk refs, line ranges, chunk schema, index granularity, selected chunk count, omitted ref count, and get-ref expansion evidence, while UI/raw-log/Doctor export remain content-free and do not expose full refs or IDs.
  28. Done fifteenth slice: add Assistant/User mutation history refresh UX without turning history into a background scan. `XTMemoryInspectorStore.mutateAssistantUserObject(...)` refreshes bounded Rust history only when the user had already opened that object's history, otherwise records a content-free skipped state (`history_not_open_on_demand`). The Supervisor Personal Memory Center shows mutation and history-refresh status at the list level so archive/delete results remain visible after the object leaves the current filter, while all history/status text stays content-hidden and avoids memory IDs/event IDs.
  29. Done sixteenth slice: add Assistant/User per-action governance disable/reason hints. `XTMemoryInspectorPresentation.assistantUserMutationActionStates(...)` derives archive/delete/pin/unpin enabled state from Rust readiness, active reveal grant, mutation in-flight state, object mutability, status, and pinned state. `SupervisorPersonalMemoryCenterView` renders all actions with disabled help text and a content-free aggregate reason line, while user-scope memory remains absent from Project Settings, Project Coder, and model-serving paths.
- acceptance:
  - User can see what memory exists.
  - User can see what was used in a turn.
  - User can approve/reject candidates.
  - UI never displays secret payloads.
  - Rust remains source of truth.
- tests:
  - Done: `MemoryInspectorTests.rustMemoryObjectListResultDecodesActiveObjects`
  - Done: `MemoryInspectorTests.rustMemoryObjectHistoryResultDecodesEvents`
  - Done: `MemoryInspectorTests.projectInspectorRefreshUsesRustProjectScopeAndDropsCrossScopeObjects`
  - Done: `MemoryInspectorTests.projectInspectorHistoryLoadsGovernanceEventsWithoutLoggingContent`
  - Done: `MemoryInspectorTests.oldSelectionEvidenceCacheDecodesWithoutSelectedRefs`
  - Done: `MemoryInspectorTests.selectionEvidenceCacheDecodesChunkRefsWithoutContent`
  - Done: `MemoryInspectorTests.selectionEvidenceRefreshReadsCachedRustStatusWithoutLoggingRefs`
  - Done: `HubIPCClientProjectCanonicalMemorySyncTests/rustMemoryGatewayModelCallPlanShadowRecordsBoundedStatusWhenEnabled`
  - Done: `XTUnifiedDoctorReportTests/sessionRuntimeSectionIncludesRustMemorySelectionEvidenceProjection`
  - Done: `MemoryInspectorTests.selectionEvidenceRefreshIsUnavailableWhenNoCacheExists`
  - Done: `MemoryInspectorTests.secretInspectorPreviewIsHiddenByDefault`
  - Done: `MemoryInspectorTests.rustMemoryObjectMutationResultDecodesGovernedEnvelope`
  - Done: `MemoryInspectorTests.projectInspectorMutationUsesRustGateAndLogsBoundedEvidenceOnly`
  - Done: `MemoryInspectorTests.mutationActionsMatchRustGateStateRules`
  - Done: `MemoryInspectorTests.assistantUserInspectorGateDeniesByDefaultAndDoesNotListRustObjects`
  - Done: `MemoryInspectorTests.assistantUserInspectorUsesUserScopeOnlyAfterReadinessAndGrant`
  - Done: `MemoryInspectorTests.rustUserRevealGrantResultDecodesContentFreeEnvelope`
  - Done: `MemoryInspectorTests.assistantUserInspectorExpiredRustGrantDoesNotListObjects`
  - Done: Rust `memory_user_reveal_grant_issue_evaluate_revoke_roundtrip`
  - Done: Rust `memory_user_reveal_grant_expired_evaluate_denies`
  - Done: Rust `memory_user_reveal_grant_denies_project_coder`
  - Done: `RustHubReadinessPresentationTests.memoryReadinessDecodesUserRevealGrantGate`
  - Done: `XTUnifiedDoctorReportTests.sessionRuntimeSectionIncludesRustMemoryUserRevealGrantProjection`
  - Done: `XHubDoctorOutputTests.projectsRustMemoryUserRevealGrantSnapshotFromStructuredSessionReadinessProjection`
  - Done: `MemoryInspectorTests.assistantUserInspectorLoadsGatedDetailAndHistoryWithoutContent`
  - Done: `MemoryInspectorTests.assistantUserInspectorDetailAndHistoryRequireActiveRustGrant`
  - Done: `MemoryInspectorTests.assistantUserInspectorMutationRequiresActiveRustGrant`
  - Done: `MemoryInspectorTests.assistantUserInspectorMutationRejectsProjectScopeObject`
  - Done: `MemoryInspectorTests.assistantUserInspectorMutationUsesRustGateAndKeepsShellContentHidden`
  - Done: `MemoryInspectorTests.assistantUserInspectorMutationDoesNotRefreshHistoryUnlessAlreadyLoaded`
  - Done: `MemoryInspectorTests.assistantUserInspectorMutationRefreshesLoadedHistoryContentFree`
  - Done: `MemoryInspectorTests.assistantUserMutationActionStatesExplainDisabledRustGateRules`
  - Done: Rust `memory_object_user_scope_mutation_requires_active_reveal_grant`
  - Done: `HubIPCClientProjectCanonicalMemorySyncTests.rustMemoryGatewayModelCallPlanShadowRecordsBoundedStatusWhenEnabled`
  - Done via `UML-W9`: candidate action calls correct Rust endpoint
- verification commands:
  - `swift test --filter MemoryInspectorTests`
  - `swift test --filter RustHubReadinessPresentationTests/memoryReadinessDecodesUserRevealGrantGate`
  - `swift test --filter XTUnifiedDoctorReportTests/sessionRuntimeSectionIncludesRustMemoryUserRevealGrantProjection`
  - `swift test --filter XHubDoctorOutputTests/projectsRustMemoryUserRevealGrantSnapshotFromStructuredSessionReadinessProjection`
  - `swift test --filter MemoryInspectorTests/assistantUserInspectorLoadsGatedDetailAndHistoryWithoutContent`
  - `swift test --filter MemoryInspectorTests/assistantUserInspectorDetailAndHistoryRequireActiveRustGrant`
  - `swift test --filter MemoryInspectorTests/assistantUserInspectorMutationRequiresActiveRustGrant`
  - `swift test --filter MemoryInspectorTests/assistantUserInspectorMutationRejectsProjectScopeObject`
  - `swift test --filter MemoryInspectorTests/assistantUserInspectorMutationUsesRustGateAndKeepsShellContentHidden`
  - `swift test --filter MemoryInspectorTests/assistantUserInspectorMutationDoesNotRefreshHistoryUnlessAlreadyLoaded`
  - `swift test --filter MemoryInspectorTests/assistantUserInspectorMutationRefreshesLoadedHistoryContentFree`
  - `swift test --filter MemoryInspectorTests/assistantUserMutationActionStatesExplainDisabledRustGateRules`
  - `cargo test -p xhubd memory_user_reveal_grant`
  - `cargo test -p xhubd memory_object_user_scope_mutation_requires_active_reveal_grant`
  - `cargo test -p xhubd memory_object_http_mutation_gate_archives_deletes_and_pins`
  - `cargo test -p xhubd memory_object_http_mutation_gate_blocks_immutable_objects`
  - `cargo test -p xhubd memory_object_cli_pin_and_archive_use_rust_mutation_gate`
  - `swift test --filter MemoryWritebackCandidateQueueTests`
  - broader sweep later: `swift test --filter Memory`
- risks:
  - UI may expose sensitive text.
  - UI may imply deletion happened before Rust confirms.
- guardrails:
  - Optimistic UI disabled for destructive actions.
  - Always display Rust result status.

### UML-W11 Doctor, Readiness, Evidence Ledger, Ops Gates

- priority: P0
- owner: Rust Hub Kernel / QA / Ops
- goal:
  - Make Universal Memory Layer observable and releasable.
- write set:
  - `rust/rust hub/crates/xhubd/src/main.rs`
  - `rust/rust hub/tools/daemon_ops_gate.command`
  - relevant Rust report tools
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-terminal/Sources/UI/RustHubReadinessPresentation.swift`
- readiness additions:
  - `memory_object_store_ready`
  - `memory_object_count`
  - `memory_candidate_count`
  - `memory_deleted_tombstone_count`
  - `memory_event_count`
  - `memory_index_ready`
  - `memory_index_generation`
  - `memory_index_stale_count`
  - `memory_policy_gate_ready`
  - `memory_gateway_ready`
  - `memory_writeback_candidate_diagnostics_schema`
  - `memory_writeback_candidate_conflict_count`
  - `memory_writeback_candidate_stale_review_required_count`
  - `memory_writeback_candidate_superseded_count`
  - `memory_writeback_candidate_planned_archive_count`
  - `memory_writeback_candidate_queue_pressure`
  - `memory_writeback_candidate_noise_score`
  - `semantic_index_enabled`
  - `semantic_index_ready`
  - `embedding_pending_count`
  - `embedding_failed_count`
  - `selected_memory_trace_enabled`
- doctor checks:
  - object store table exists
  - writer authority gate state
  - policy gate denies unknown mode
  - Coder personal memory deny
  - Supervisor raw evidence default deny
  - delete tombstone not searchable
  - candidate approval path
  - candidate conflict approval reason gate
  - candidate diagnostics/readiness present without candidate text
  - index stale count under threshold
  - semantic disabled/default or ready if enabled
- reports:
  - memory object store report
  - policy matrix report
  - retrieval quality report
  - selected/omitted trace report
  - migration parity report
- acceptance:
  - `daemon_ops_gate` includes Universal Memory Layer evidence.
  - Doctor can explain memory readiness without reading secrets.
  - A failing policy matrix blocks production cutover.
  - Slow request budget tracks memory endpoints.
- tests:
  - readiness JSON schema
  - doctor presentation
  - ops gate failure cases
- verification commands:
  - `cargo test -p xhubd readiness`
  - `swift test --filter RustHubReadinessPresentation`
  - `bash tools/daemon_ops_gate.command --max-slow-requests 0`
- risks:
  - Evidence reports may accidentally include memory text.
- guardrails:
  - Reports include counts, refs, policy decisions, snippets only when sanitized.

### UML-W12 Migration, Dual-Read, Dual-Write, Rollback

- priority: P0
- owner: Rust Hub Kernel / XT Runtime / Release
- goal:
  - Move from current mixed memory system to Rust universal memory without breaking existing workflows.
- stages:
  - Stage A: shadow object store
  - Stage B: dual-write AXMemory -> Rust object store
  - Stage C: dual-read compare, product still uses old path
  - Stage D: Rust read primary, old path fallback
  - Stage E: Rust write primary, old path projection
  - Stage F: old path compatibility only
- write set:
  - Rust memory object store
  - XT AXMemory pipeline
  - HubIPCClient
  - Supervisor/Coder prompt builders
  - build/release tools
- implementation steps:
  1. Add feature flags:
     - `XHUB_RUST_UNIVERSAL_MEMORY_OBJECT_STORE`
     - `XHUB_RUST_UNIVERSAL_MEMORY_DUAL_WRITE`
     - `XHUB_RUST_UNIVERSAL_MEMORY_READ_PRIMARY`
     - `XHUB_RUST_UNIVERSAL_MEMORY_WRITE_PRIMARY`
     - `XHUB_RUST_UNIVERSAL_MEMORY_SEMANTIC_INDEX`
  2. Add snapshot before migration.
  3. Add import command:
     - AXMemory files
     - current memory_dir files
     - project registry / portfolio brief
  4. Add parity compare:
     - selected section count
     - retrieval result overlap
     - selected/omitted reasons
     - token budget
     - policy denies
  5. Add rollback command.
  6. Add migration reports under `reports/`.
- acceptance:
  - Migration can run dry-run.
  - Dry-run reports planned object count and denied/skipped count.
  - Apply writes objects and events.
  - Rollback disables new primary path without deleting legacy data.
  - No production authority change without explicit apply.
- tests:
  - dry-run import
  - apply import
  - rollback
  - dual-read parity
  - stale index recovery
- verification commands:
  - `cargo test -p xhubd universal_memory_migration`
  - `bash tools/daemon_ops_gate.command --max-slow-requests 0`
- risks:
  - Silent migration corruption.
  - Duplicate memories.
  - Broken fallback after cutover.
- guardrails:
  - Dry-run first.
  - Write-before snapshot.
  - Explicit cutover gate.

### UML-W13 Release Gates, Benchmarks, Docs

- priority: P0
- owner: QA / Release / Docs
- goal:
  - Ensure Universal Memory Layer is safe, fast, and handoff-ready.
- write set:
  - `docs/memory-new/`
  - `scripts/`
  - Rust tests
  - Swift tests
  - CI workflows if present
- benchmark dimensions:
  - retrieval recall for project decisions
  - blocker/retry recovery recall
  - Supervisor governance review selection
  - false positive personal memory exposure
  - secret leakage
  - p95/p99 memory endpoint latency
  - candidate noise rate
  - migration parity
- release gates:
  - correctness gate
  - policy gate
  - security gate
  - performance gate
  - migration rollback gate
  - UI redaction gate
  - ops evidence gate
- acceptance:
  - All P0 work orders have automated tests.
  - All security gates pass.
  - No secret appears in report artifacts.
  - p95 latency budget is documented and met.
  - Handoff docs are updated.
- verification commands:
  - `cargo test`
  - `swift test`
  - `bash tools/daemon_ops_gate.command --max-slow-requests 0`
  - project-specific CI scripts if configured
- risks:
  - Docs can drift from implementation.
- guardrails:
  - Each endpoint response includes schema_version.
  - Each doc references owning files and test commands.

## 7) API Surface Checklist

Minimum Rust endpoints before product cutover:

- `/memory/readiness`
- `/memory/search`
- `/memory/retrieve`
- `/memory/write`
- `/memory/objects`
- `/memory/objects/{memory_id}`
- `/memory/objects/{memory_id}/history`
- `/memory/candidates`
- `/memory/candidates/{candidate_id}/approve`
- `/memory/candidates/{candidate_id}/reject`
- `/memory/policy/evaluate`
- `/memory/context`
- `/memory/index/status`
- `/memory/index/rebuild`
- `/memory/migration/plan`
- `/memory/migration/apply`
- `/memory/migration/rollback`

Backward-compatible aliases can exist, but new product code should use the Universal Memory endpoints.

## 8) Security Test Matrix

Required adversarial cases:

| Case | Expected |
| --- | --- |
| Coder requests user personal memory | denied |
| Supervisor requests raw evidence by default | denied or omitted |
| Lane handoff requests fulltext | denied |
| Remote prompt bundle requests L4 raw evidence | denied |
| Query contains `api key` / `password` / secret-like term | denied |
| Memory text contains secret-like token | denied or redacted before insert |
| Deleted memory appears in search | fail test |
| Archived memory appears in default search | fail test |
| Stale index returns deleted memory | fail test |
| Cross-project query without explicit scope/grant | denied |
| UI renders secret text | fail test |
| Migration imports secret file | skipped/denied with report |
| Semantic embedding attempts remote export of private content | denied |

## 9) Performance Budgets

Initial local budgets:

- `/memory/readiness`
  - p95 under 50 ms
- `/memory/policy/evaluate`
  - p95 under 25 ms
- `/memory/context` m1 execute
  - p95 under 250 ms without semantic
- `/memory/retrieve` hybrid FTS
  - p95 under 200 ms for normal local project
- `/memory/retrieve` semantic + rerank
  - p95 under 900 ms under m3/m4 only
- Memory Inspector list
  - initial page under 300 ms
- Migration dry-run
  - may be slower, but must report progress and not block daemon health

Any endpoint crossing budget must record route metrics and slow request evidence.

## 10) Done Definition

Universal Memory Layer v1 is done only when:

1. Rust object store is live.
2. CRUD/history/list/get work with schema_versioned JSON.
3. Rust policy gate is source of authority.
4. Coder and Supervisor use Rust memory context gateway in production mode.
5. AXMemory syncs to Rust canonical objects or has a documented projection state.
6. Hybrid retrieval is enabled and tested.
7. Semantic retrieval is either disabled by default with readiness evidence or enabled behind passing local readiness.
8. Candidate writeback exists and does not auto-write unsafe memory.
9. Swift Memory Inspector can show memory objects, history, candidates, and selected/omitted traces without leaking secrets.
10. Doctor and daemon ops gate cover object store, policy, index, candidates, migration, and selected/omitted evidence.
11. Migration has dry-run, apply, and rollback reports.
12. Security matrix passes.
13. Performance budgets pass.
14. Documentation is updated.

## 11) First Slice Recommendation

First slice target:

1. `UML-W0`
2. `UML-W1`
3. `UML-W2` create/get/list/history plus Rust-gated archive/delete/pin/unpin mutation transitions
4. `UML-W3` minimal policy matrix
5. `UML-W11` readiness for those pieces

As of 2026-05-30, this first slice is implemented and validated at the Rust package / temporary HTTP / CLI smoke level. `UML-W4` has also landed the Swift/XT caller cutover: existing XT `project_canonical_memory` payloads can dry-run/apply into Rust memory objects, and `HubIPCClient.syncProjectCanonicalMemory` prefers Rust HTTP with local compatibility fallback. Retryable Rust-unavailable failures now leave a pending snapshot under project memory lifecycle, project load schedules a retry, successful Rust sync status lets context/retrieval reads prefer active Rust project objects, and import diagnostics can prove deterministic AXMemory-to-Rust drift. `UML-W5` now has a prepare-only Rust gateway surface for policy-gated context assembly, Swift shadow compare behind an explicit env gate, Supervisor doctor/evidence rollup for shadow drift, an opt-in Rust primary context gate with compatibility fallback, model usage audit fields for Rust gateway context results (`memory_gateway_source`, `memory_gateway_mode`, `memory_gateway_production_authority_change`, object count, and effective layers), an explicit fail-closed require gate guarded by fresh same-scope parity evidence, sustained parity readiness evidence (`memory_gateway_shadow_compare_history.json` plus `memory_gateway_cutover_readiness.json`), Supervisor Doctor visibility for readiness not-ready / authority-violation states, and daemon ops gate/report inclusion for the same readiness evidence. `UML-W5/RT-C` now also has profile-suite live smoke evidence: `memory_gateway_cutover_smoke.js --profile-suite` records M0/M1/M2/M3/M4 samples, writes per-profile readiness, and ops-gate can require that report. On 2026-05-25 the launchd-owned live runner under `~/Library/Application Support/AX/rust-hub/local` was cut to fail-closed `XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE=1`, persisted in `com.ax.xhubd.local.plist`, relaunched with pid `39382`, and passed final ops gate with memory writer authority, skills execution authority, require-ready evidence, `slow_requests=0`, and `issues=[]`. `UML-W6` has a rebuildable Rust derived index, BM25-style scorer, selected/omitted trace evidence, and quick/large quality bench. `UML-W9` now has the Rust governed candidate queue plus deterministic AXMemory-delta extractor, XT caller path, Swift shell pending queue, TTL/stale maintenance, isolated lifecycle ops smoke, conflict/supersession metadata, Rust candidate diagnostics/noise metrics, conflict approval reason gating, Unified Doctor surfacing, daemon ops gate/report rollup, Swift maintenance review controls, and Swift merge review detail comparison: create/list/extract plus approve/reject/maintenance transitions with memory events, duplicate collapse, dry-run, secret fail-closed behavior, readiness evidence, queue pressure/noise score evidence, ops-safe candidate diagnostics, UI-triggered maintenance dry-run/apply evidence, Rust-owned conflict/supersession object comparison, and `AXMemoryPipeline` delivery of model/fallback deltas into Rust candidate-only writeback. `UML-W10` now has the first read-only Project Memory Inspector foundation plus object history/detail and cached selection-evidence inspection in the Rust-refactored Swift shell: it lists current-project Rust memory objects through `/memory/objects`, supports basic filters, drops cross-scope returns, hides private/secret previews, expands per-object Rust history through `/memory/objects/{memory_id}/history`, reads cached Rust model-call-plan selected/omitted/denied/skipped evidence without recomputing memory selection on the chat path, filters selected refs to the current project, writes content-free inspector/selection evidence, exports the same content-free selected/omitted projection through `XTUnifiedDoctor` / generic XT doctor JSON, carries richer Rust `omitted_reason_counts` from retrieval traces through Inspector/Doctor/ops evidence, and now has Rust-owned object mutation gates plus Swift caller/evidence wrappers and Project Memory Inspector controls for archive/delete/pin/unpin with confirmation, archive-clears-pin behavior, tombstone delete, immutable fail-closed behavior, memory event history, readiness evidence, and bounded mutation raw-log evidence. No semantic embeddings have been started.

2026-05-25 follow-on: `UML-W5/RT-C` also has a Rust model-call plan-only wrapper (`POST /memory/gateway/model-call-plan`, CLI `gateway-model-call-plan`). It reuses gateway prepare admission/profile/context selection and returns model-call route evidence without executing a model call, without invoking local ML, and without echoing prompt/context text. `execute/apply/commit` requests fail closed until a separate execution cutover gate lands.

2026-05-25 follow-on: `memory_gateway_cutover_smoke.js` now runs that plan-only wrapper smoke by default and writes bounded `model_call_plan_*` fields into `memory_gateway_cutover_readiness.json`. `xhubd_daemon.js ops-report/ops-gate` now rolls those fields up and blocks if enabled evidence reports execution, text leakage, missing execute-denial, or plan smoke failure. This is evidence/doctor hardening only; real model-call execution remains behind a future explicit gate.

2026-06-09 follow-on: Rust now has a separate model-call execution admission gate (`POST /memory/gateway/model-call-execution-gate`, CLI `gateway-model-call-execution-gate`). Defaults remain fail-closed and no model call is executed. When `XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTION_ADMISSION=1` is set and provider/model route authority are already in Rust, the gate can return `ready_for_execution=true` with `mode=execution_admission_no_model_call`; this means Rust owns execution admission only, not actual model/provider/local-ML execution. The cutover smoke and daemon ops rollup now summarize this gate with content-free status/blocker counts and block only on execution, text leak, or authority mutation evidence.

2026-06-09 follow-on: Rust now also exposes guarded model-call execute (`POST /memory/gateway/model-call-execute`, CLI `gateway-model-call-execute`). It first requires the execution admission gate, then requires `XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_LOCAL_EXECUTOR=1`, `XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_APPLY=1`, local-ML readiness, and a local provider route before it delegates to `/local-ml/execute`. Defaults remain `execute_guard_no_model_call`; the smoke path deliberately uses a non-local provider so ops can prove the endpoint blocks without invoking local-ML. Ops/readiness evidence is content-free and blocks on unexpected invocation, execution, text leakage, or authority mutation.

2026-06-09 follow-on: Rust now has an independent guarded execute smoke and rollback evidence gate. `rust/xhubd/tools/memory_gateway_model_call_execute_smoke.js` probes live `/ready`, `/memory/gateway/model-call-execution-gate`, and `/memory/gateway/model-call-execute`, writes `memory_gateway_model_call_execute_smoke_status.json` plus bounded history, and records only content-free status/mode/authority/blocker/admission fields. It also emits a rollback plan listing the env keys to unset for a future explicit executor cutover, but the smoke itself does not set env, relaunch daemon, or switch authority. `xhubd_daemon.js ops-report/ops-gate` now reads that evidence; missing evidence is informational by default, while `--require-memory-gateway-model-call-execute-smoke` requires present/ok/blocked/content-free evidence and blocks if any model/local-ML invocation, text leakage, or authority mutation is reported. This is a live cutover precondition, not the live product execution cutover.

2026-05-25 follow-on: XT/Swift now has the first real caller shadow hook before generation. `HubAIClient` schedules a non-blocking Rust model-call preflight before local file-IPC enqueue and remote generation; `HubIPCClient` records `memory_gateway_model_call_plan_status.json` / bounded history with route/profile/count/guard metadata only. The hook is gated by `XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_PLAN_SHADOW=1` or existing gateway shadow env and does not alter product output.

2026-05-25 follow-on: the canonical Rust Hub package path now includes XT model-call shadow evidence in `xhubd_daemon.js` ops-report/ops-gate. New fields include `memory_gateway_model_call_plan_shadow`, `*_found`, `*_evidence_ok`, `*_execution_safe`, and `*_text_safe`; missing evidence is non-blocking unless `--require-memory-gateway-model-call-plan-shadow` is used, while execution/text leak/authority violation evidence blocks ops-gate when present.

Do not start semantic embeddings. Project Memory Inspector mutation controls now consume the Rust archive/delete/pin/unpin gates; do not add new mutation surfaces unless they call the same Rust wrapper, keep scope-specific labeling, and refresh from Rust after success.

## 12) Handoff Prompt For Next AI

Use this exact prompt for a new implementation agent:

```text
You are continuing X-Hub Universal Memory Layer v1.

Read:
- docs/memory-new/xhub-universal-memory-layer-work-orders-v1.md
- description/MEMORY_SYSTEM.md
- docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md

UML-W0 through UML-W3 first slice already exists. Verify it with:
- cargo test -p xhub-db
- cargo test -p xhubd

Then continue UML-W10 only if the next slice adds Rust-owned Assistant/User governance actions behind explicit gates. Do not reuse the project inspector for personal memory without explicit scope labels and grant/readiness gates. Rust now exposes and tests `POST /memory/objects/{memory_id}/archive|delete|pin|unpin`, `xhubd memory object-archive|object-delete|object-pin|object-unpin`, confirmation-required archive/delete, archive-clears-pin behavior, tombstone delete, immutable fail-closed behavior, memory event history, and `/memory/readiness.object_store.mutation_gate`. Rust also owns content-free `POST /memory/user-reveal-grant/issue|evaluate|revoke` for Assistant/User inspection, with TTL, revoke, Project Coder/project-use-mode deny, `/memory/readiness.object_store.user_reveal_grant`, and no model-serving authority change. Swift now has `HubIPCClient.mutateMemoryObjectViaRust(...)`, `HubIPCClient.requestMemoryUserRevealGrantViaRust(...)`, mutation/grant result decoding, test overrides, `XTMemoryInspectorStore.mutateProjectObject(...)`, Assistant/User grant evaluation/detail/history shell support, and bounded inspector evidence without becoming durable authority. Project Settings icon controls call the Rust mutation wrapper, disable optimistic destructive UI, and refresh from Rust after success; `SupervisorPersonalMemoryCenterView` requests/evaluates/revokes the Rust reveal grant before it can list user-scope shell objects, renders a gated user-scope metadata list, fetches per-object detail/history on demand, strips title/text/summary/provenance/policy, and still renders `content=hidden`. XT Doctor mutation-gate and user-reveal grant readiness projections come from the cached `/memory/readiness` payload (`rustMemoryObjectMutationGateProjection` / `rust_memory_object_mutation_gate_snapshot` and `rustMemoryUserRevealGrantProjection` / `rust_memory_user_reveal_grant_snapshot`) without scanning objects. The Swift shell candidate queue is already in the Rust-refactored `x-hub-system/x-terminal` app: it lists pending Rust candidates, calls Rust approve/reject endpoints, hides secret/private content by default, requires `conflict_resolution_reason` for conflicting approvals, can preview/apply Rust-owned maintenance, can expand conflict/supersession references by fetching Rust-owned object details for read-only comparison, and records bounded raw-log evidence without becoming durable authority. The Project Memory Inspector lists current-project Rust objects through `/memory/objects`, supports status/layer/source_kind/sensitivity filters, drops cross-scope returns from the project surface, hides private/secret previews, expands per-object Rust history through `/memory/objects/{memory_id}/history`, reads cached `memory_gateway_model_call_plan_status/history` selected/omitted/denied/skipped/omitted-reason-count evidence without recomputing memory selection, filters selected refs to the current project, records content-free refresh/history/selection/mutation evidence only, and `XTUnifiedDoctor` / generic XT doctor JSON now mirror content-free `rustMemorySelectionEvidenceProjection` / `rust_memory_selection_evidence_snapshot`, `rustMemoryObjectMutationGateProjection` / `rust_memory_object_mutation_gate_snapshot`, and `rustMemoryUserRevealGrantProjection` / `rust_memory_user_reveal_grant_snapshot` evidence. Rust TTL/stale maintenance is in place through `/memory/writeback/candidates/maintenance`, conflict/supersession metadata is enforced in Rust, `/memory/readiness` exposes `object_store.writeback_candidates.diagnostics`, `GET /memory/writeback/candidates` returns `candidate_diagnostics`, `XTUnifiedDoctor` surfaces bounded `rust_memory_writeback_candidate_queue_*` detail-lines plus typed `rustMemoryWritebackCandidateQueueProjection`, `xhubd_daemon.js` ops-report/ops-gate exposes content-free `memory_writeback_candidate_ops_rollup`, model-call-plan omitted reason counts, and shadow omitted reason counts, and `memory_writeback_candidate_smoke.command` covers the isolated lifecycle smoke. Keep model-generated memories as candidates, not active writes. The launchd-owned live Hub has memory gateway require mode enabled; local dev/test profiles may still run compatibility fallback unless their env explicitly enables the same require gate.

Do not implement semantic embeddings.
Do not make Swift UI a memory authority.
Do not make Node a new authority.
Rust is the memory authority.
Swift is the shell.
Personal memory is denied to Project Coder by default.
All endpoints must return schema_versioned JSON and fail closed on secrets.

Before editing, inspect:
- rust/rust hub/crates/xhub-memory/src/lib.rs
- rust/rust hub/crates/xhubd/src/memory_bridge.rs
- rust/rust hub/crates/xhubd/src/main.rs
- rust/rust hub/crates/xhub-db/src/lib.rs
- rust/rust hub/migrations/0007_memory_objects.sql
- x-terminal/Sources/Hub/XTMemoryUsePolicy.swift
- x-terminal/Sources/Project/AXMemory.swift
- x-terminal/Sources/Project/AXMemoryPipeline.swift

Deliver:
- tests and daemon ops evidence proving candidates remain approval-gated and do not auto-activate
```
