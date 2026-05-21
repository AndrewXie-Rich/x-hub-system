# X-Hub Universal Memory Layer Work Orders v1

- version: v1.0
- updatedAt: 2026-05-19
- owner: Rust Hub Kernel / XT Runtime / Swift Shell / Supervisor / Coder / Security / QA
- status: in-progress-w0-w5-gateway-prep-implemented
- purpose:
  - 把 mem0 / OpenMemory 这类开源模型通用记忆系统的可借鉴点，转成 X-Hub 可执行工单
  - 在不牺牲 X-Hub 现有安全边界的前提下，把 Memory 做成所有模型、所有 Agent、所有运行面统一调用的 Rust kernel capability
  - 让下一位 AI 或工程师一接手就知道先读什么、改哪里、怎么验收、哪些边界不能碰
- primary product boundary:
  - 一个 Hub 产品 = Rust 内核 + Swift 壳
  - Rust 内核负责判断、状态、策略、接口、memory authority、检索和审计
  - Swift 壳负责产品 UI、展示、用户确认、调用 Rust kernel
  - Node 只保留兼容层、admin bridge、老接口迁移桥，不再新增 memory authority

## Implementation Status 2026-05-19

First implementation slice landed in `rust/rust hub`:

- `UML-W0`: v1 contract captured in this work-order doc.
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
- `cargo test -p xhubd`
  - validates the full xhubd unit suite after gateway endpoint/readiness changes.
- `cargo test -p xhub-memory`
  - validates memsearch-inspired heading chunking, stable section refs, get-ref compatibility, and secret section isolation for Rust shadow file retrieval.
- `cargo test -p xhubd memory_object_hybrid_retrieval`
  - validates Rust object-store indexed retrieval finds decision memory with explain and supports layer filtering plus object `get_ref`.
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
- No Swift Memory Inspector.
- No Node memory authority.
- No public delete/pin/archive candidate mutation surface beyond first-slice stubs.
- No full AXMemory pipeline authority flip yet; XT caller now prefers Rust for canonical sync, context/retrieval reads can prefer active Rust project objects, and import diagnostics can prove projection drift, but local AXMemory files remain fallback/projection until Rust memory gateway cutover lands.
- No model-call execution in Rust Memory Gateway yet; the gateway is prepare-only. Swift shadow compare is available behind an explicit env gate, Rust primary context is opt-in with compatibility fallback, fail-closed require mode is available but still must be explicitly enabled with fresh parity evidence, and readiness evidence is now visible in Supervisor Doctor plus daemon ops gate/report.
- Existing file scanner retrieval remains untouched until hybrid retrieval and migration tests land.

## 0) How To Use This File

如果你是新接手的 AI，固定按这个顺序进入：

1. 读本文件 `docs/memory-new/xhub-universal-memory-layer-work-orders-v1.md`
2. 读 `description/MEMORY_SYSTEM.md`
3. 读 `description/SUPERVISOR_AND_CODER.md`
4. 读 `docs/memory-new/xhub-memory-v3-execution-plan.md`
5. 读 `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
6. 读 `docs/memory-new/xhub-memory-support-for-governed-agentic-coding-work-orders-v1.md`
7. 读 `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md`
8. 读 `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
9. 再开始改代码

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
| Heading-aware chunking with paragraph fallback | First Rust file-scan slice implemented | Rust shadow file retrieval now chunks `.md`/`.txt` by headings with stable section refs; object-store indexing still needs the same rule in W6. |
| Content-addressed dedup / stable chunk IDs | Partially absorbed | File-scan refs now include stable section line/hash IDs. W6 must use deterministic object chunk IDs across reindex. |
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

- status: first Rust shadow file-scan slice implemented; object-store index adoption still pending in W6.
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
  - Next: W6 object-store retrieval must use the same chunk identity concept for Rust objects and future FTS/vector chunks.
- acceptance:
  - Query for one heading does not return unrelated headings from the same file.
  - Re-running retrieval on unchanged memory returns the same ref.
  - Secret section does not leak and does not poison public sections.
- verification:
  - `cargo test -p xhub-memory markdown`

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
  - Coder, Supervisor, coarse/refine, skills can use one memory gateway.
  - Memory V1 text remains backward compatible.
  - Existing prompt sections still appear.
  - Still needed: live operational enablement of the fail-closed gate after fresh live readiness evidence is collected.
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
- guardrails:
  - Keep feature flag:
    - `XHUB_RUST_MEMORY_CONTEXT_GATEWAY`
  - Start in shadow compare mode:
    - Swift build and Rust build both run
    - product uses Swift until diff stable
  - Cut over only when doctor reports parity.

### UML-W6 Hybrid Retrieval v1 With Deterministic And FTS Index

- priority: P1
- owner: Rust Hub Kernel / Memory Retrieval
- status: in-progress-persistent-derived-index-slice
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
  10. Still needed: optional SQLite FTS5 virtual table or equivalent BM25 scorer over the derived index.
  11. Still needed: sustained/large fixture retrieval quality bench.
  12. Keep old file scan retrieval as compatibility import.
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
  - Still needed: `memory_hybrid_retrieval_filters_scope`
  - `memory_hybrid_retrieval_omits_deleted`
  - Done W6 slice: `memory_hybrid_retrieval_explain`
  - Done W6 slice: `memory_hybrid_reindex_recovers`
- verification commands:
  - `cargo test -p xhubd memory_object_hybrid_retrieval`
  - `cargo test -p xhubd memory_object_reindex_command_recovers_derived_index`
  - `bash tools/memory_hybrid_quality_bench.command`
- risks:
  - Index drift.
  - Search quality regressions hidden by old lexical fallback.
- guardrails:
  - Add route-sensitive bench before production cutover.
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
  1. Add candidate table or candidate status in memory object table.
  2. Add candidate creation API.
  3. Add candidate approval/reject API.
  4. Add deterministic candidate extractor for AXMemory deltas.
  5. Add optional model-assisted candidate extractor later.
  6. Add duplicate detection.
  7. Add user-visible candidate queue for Swift W10.
  8. Add candidate TTL.
- acceptance:
  - Candidate creation does not alter active canonical memory.
  - Approval creates active memory object and event.
  - Rejection records event.
  - Secret candidates are denied or redacted.
  - Duplicate candidates collapse.
- tests:
  - candidate create/approve/reject
  - candidate secret deny
  - duplicate collapse
  - TTL prune
- verification commands:
  - `cargo test -p xhub-memory memory_candidate`
  - `cargo test -p xhubd memory_candidate`
- risks:
  - Too many candidates can become noise.
  - Auto-approval can corrupt durable truth.
- guardrails:
  - Default candidate, not direct write, for model-extracted memories.
  - Auto-approve only deterministic low-risk project facts after separate gate.

### UML-W10 Swift Memory Inspector

- priority: P1
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
  1. Add `HubMemoryClient` methods in `HubIPCClient`.
  2. Add presentation models.
  3. Add list and detail views.
  4. Add candidate queue.
  5. Add selected/omitted evidence view for Coder and Supervisor.
  6. Add tests for redaction presentation.
- acceptance:
  - User can see what memory exists.
  - User can see what was used in a turn.
  - User can approve/reject candidates.
  - UI never displays secret payloads.
  - Rust remains source of truth.
- tests:
  - memory list presentation
  - secret redaction presentation
  - candidate action calls correct endpoint
  - project view excludes user personal by default
- verification commands:
  - `swift test --filter Memory`
  - `swift test --filter HubIPCClient`
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
3. `UML-W2` only for create/get/list/history, not delete/update yet
4. `UML-W3` minimal policy matrix
5. `UML-W11` readiness for those pieces

As of 2026-05-20, this first slice is implemented and validated at the Rust package / temporary HTTP / CLI smoke level. `UML-W4` has also landed the Swift/XT caller cutover: existing XT `project_canonical_memory` payloads can dry-run/apply into Rust memory objects, and `HubIPCClient.syncProjectCanonicalMemory` prefers Rust HTTP with local compatibility fallback. Retryable Rust-unavailable failures now leave a pending snapshot under project memory lifecycle, project load schedules a retry, successful Rust sync status lets context/retrieval reads prefer active Rust project objects, and import diagnostics can prove deterministic AXMemory-to-Rust drift. `UML-W5` now has a prepare-only Rust gateway surface for policy-gated context assembly, Swift shadow compare behind an explicit env gate, Supervisor doctor/evidence rollup for shadow drift, an opt-in Rust primary context gate with compatibility fallback, model usage audit fields for Rust gateway context results (`memory_gateway_source`, `memory_gateway_mode`, `memory_gateway_production_authority_change`, object count, and effective layers), an explicit fail-closed require gate guarded by fresh same-scope parity evidence, sustained parity readiness evidence (`memory_gateway_shadow_compare_history.json` plus `memory_gateway_cutover_readiness.json`), Supervisor Doctor visibility for readiness not-ready / authority-violation states, and daemon ops gate/report inclusion for the same readiness evidence. The current next slice is live evidence collection, then explicit require-gate enablement only when readiness is green, with no Swift UI inspector and no semantic embeddings yet.

Do not start semantic embeddings or UI inspector until create/get/list/history and policy matrix are stable.

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

Then continue UML-W5 by collecting fresh live `memory_gateway_cutover_readiness.json` evidence and running daemon ops gate with `--require-memory-gateway-cutover-ready`. Supervisor Doctor visibility, daemon ops gate/report inclusion, model usage audit, the explicit fail-closed require gate, and sustained live parity readiness report already exist. Keep existing Swift builders as compatibility fallback unless require mode is explicitly enabled with fresh same-scope parity evidence.

Do not implement semantic embeddings.
Do not modify Swift UI yet.
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
- rollback/projection state
- import diagnostics
- retrieval preference for Rust canonical project memory
- Rust policy enforcement on every sync write
- tests and daemon ops evidence
```
