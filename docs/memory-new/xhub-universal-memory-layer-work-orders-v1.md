# X-Hub Universal Memory Layer Work Orders v1

- version: v1.0
- updatedAt: 2026-05-19
- owner: Rust Hub Kernel / XT Runtime / Swift Shell / Supervisor / Coder / Security / QA
- status: draft-ready-for-execution
- purpose:
  - 把 mem0 / OpenMemory 这类开源模型通用记忆系统的可借鉴点，转成 X-Hub 可执行工单
  - 在不牺牲 X-Hub 现有安全边界的前提下，把 Memory 做成所有模型、所有 Agent、所有运行面统一调用的 Rust kernel capability
  - 让下一位 AI 或工程师一接手就知道先读什么、改哪里、怎么验收、哪些边界不能碰
- primary product boundary:
  - 一个 Hub 产品 = Rust 内核 + Swift 壳
  - Rust 内核负责判断、状态、策略、接口、memory authority、检索和审计
  - Swift 壳负责产品 UI、展示、用户确认、调用 Rust kernel
  - Node 只保留兼容层、admin bridge、老接口迁移桥，不再新增 memory authority

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
- source kind 主要由路径启发式推断。

当前短板：

- 还没有统一的 `memory_id` object lifecycle。
- Rust memory write 更偏 append file record，缺少 update/delete/history/list/get。
- Rust 还没有统一 Memory Gateway 拦在所有 model request 前。
- AXMemory project memory 仍有大量 truth 在 XT local project store。
- 没有统一 hybrid retrieval index。
- 没有 optional semantic index / embedding abstraction。
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
  1. Add `AXMemoryRustSyncPayload`.
  2. Add `HubIPCClient.syncProjectMemoryToRust(...)`.
  3. After `AXMemoryPipeline.updateMemory` succeeds, enqueue sync.
  4. If Rust unavailable, record pending sync under `.xterminal/memory_lifecycle/`.
  5. On project open, retry pending sync.
  6. Add idempotency key:
     - project_id
     - AXMemory updatedAt
     - normalized section hash
  7. Avoid duplicate records.
  8. Add Rust import endpoint if needed:
     - `POST /memory/import/ax-project`
- acceptance:
  - Updating project memory creates or updates Rust memory objects.
  - Re-running sync is idempotent.
  - Rust unavailable does not break Coder prompt.
  - Pending sync is visible in diagnostics.
  - Rust object history points back to AXMemory lifecycle audit.
- tests:
  - AXMemory sync payload encoding.
  - Idempotent retry.
  - Rust object creation from AXMemory sections.
  - Offline fallback.
- verification commands:
  - `swift test --filter AXMemory`
  - `swift test --filter HubIPCClient`
  - `cargo test -p xhubd ax_project_memory`
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
  1. Add Rust memory context builder that can assemble Memory V1 from object store + request payload.
  2. Keep existing Swift builders as fallback/compatibility only.
  3. Change Coder Memory V1 build to prefer Rust `/memory/context`.
  4. Change Supervisor Memory V1 build to prefer Rust `/memory/context`.
  5. Change AXMemory coarse/refine model calls to request memory through gateway where relevant.
  6. Change skill execution memory needs to call gateway.
  7. Add gateway result into model usage audit.
  8. Add no-memory fallback only where policy allows.
- acceptance:
  - Coder, Supervisor, coarse/refine, skills can use one memory gateway.
  - Memory V1 text remains backward compatible.
  - Existing prompt sections still appear.
  - Gateway records selected/omitted memory ids.
  - Gateway enforces policy before model route.
- tests:
  - Coder prompt still includes Memory V1.
  - Supervisor prompt still includes selected sections.
  - High-risk tool act requires fresh memory.
  - Remote prompt bundle sanitized only.
  - Gateway denied result does not call model.
- verification commands:
  - `cargo test -p xhubd memory_gateway`
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
  1. Build FTS table or equivalent local full-text index.
  2. Index only policy-eligible active memory objects.
  3. Add property extraction on create/update.
  4. Add reindex command.
  5. Add stale-index detection.
  6. Add explain output:
     - score
     - lexical_score
     - property_boost
     - policy_filter
     - omitted reason
  7. Keep old file scan retrieval as compatibility import.
- acceptance:
  - Retrieval quality improves for project decision/blocker/next-step queries.
  - Policy gate runs before index search.
  - Deleted records are not returned.
  - Secret records are not indexed.
  - Explain output can justify selected snippets.
- tests:
  - `memory_hybrid_retrieval_finds_decision`
  - `memory_hybrid_retrieval_filters_scope`
  - `memory_hybrid_retrieval_omits_deleted`
  - `memory_hybrid_retrieval_explain`
  - `memory_hybrid_reindex_recovers`
- verification commands:
  - `cargo test -p xhub-memory hybrid_retrieval`
  - `cargo test -p xhubd memory_reindex`
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
  - X-Hub should use rerank selectively, not always-on.
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

The safest next implementation slice is:

1. `UML-W0`
2. `UML-W1`
3. `UML-W2` only for create/get/list/history, not delete/update yet
4. `UML-W3` minimal policy matrix
5. `UML-W11` readiness for those pieces

Do not start semantic embeddings or UI inspector until create/get/list/history and policy matrix are stable.

## 12) Handoff Prompt For Next AI

Use this exact prompt for a new implementation agent:

```text
You are continuing X-Hub Universal Memory Layer v1.

Read:
- docs/memory-new/xhub-universal-memory-layer-work-orders-v1.md
- description/MEMORY_SYSTEM.md
- docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md

Start with UML-W0 through UML-W3 only.

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
- x-terminal/Sources/Hub/XTMemoryUsePolicy.swift

Deliver:
- Rust memory object structs
- SQLite object/event store
- create/get/list/history endpoints or internal APIs
- minimal policy matrix
- readiness fields
- tests and daemon ops evidence
```
