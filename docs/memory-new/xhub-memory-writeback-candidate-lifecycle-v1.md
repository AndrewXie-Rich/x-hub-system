# X-Hub Memory Writeback Candidate Lifecycle v1

- status: active-work-order
- updatedAt: 2026-05-25
- owner: Rust Hub Kernel / Swift Hub Shell / X-Terminal Runtime / Memory Governance / QA
- dependsOn:
  - `docs/memory-new/xhub-memory-runtime-authority-and-reality-map-v1.md`
  - `docs/memory-new/xhub-universal-memory-layer-work-orders-v1.md`
- purpose:
  - 固定 X-Hub Memory 写回候选的生命周期规则
  - 防止模型输出、XT 本地缓存、Node 兼容层绕过 Hub-first durable truth
  - 给后续 Swift candidate queue、TTL/stale handling、ops smoke、doctor evidence 提供可执行工单

## 1) Non-Negotiable Boundary

Memory writeback candidate 的核心规则：

`model/client/tool can propose -> Rust policy-gated candidate queue -> review/approval -> active memory`

不得出现：

- 模型输出直接写入 active durable Memory
- XT 本地 AXMemory 变成 durable writer
- Swift UI 直接改 durable truth
- Node compatibility path 新增 future Memory authority
- secret/private/cross-scope/permission/policy 类候选被自动批准

Candidate queue 是 Memory 的防污染层。它不是临时 UI 队列，也不是可被客户端本地替代的第二套 Memory authority。

## 2) Current Reality

已经实现的第一切片：

- Rust candidate queue 复用 `rust_hub_memory_objects.status='candidate'`。
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
- Deterministic AXMemory delta extractor:
  - maps goal / requirements / current state / decisions / next steps / open questions / risks / recommendations
  - writes only `status='candidate'`
  - supports dry-run
  - collapses duplicate stable project/kind/text IDs
  - rejects secret-like candidate text and audit refs fail-closed
- Transitions:
  - approve: `candidate -> active`
  - reject: `candidate -> rejected`
  - invalid transition returns conflict
  - approve of secret-like candidate is denied
  - each transition records a memory event
- XT caller:
  - `AXMemoryPipeline` sends model/fallback `AXMemoryDelta` into Rust extractor
  - evidence records `active_write=false`, `requires_approval=true`, `production_authority_change=false`

Still not complete yet:

- full supersession/conflict merge/compare UI; the first slice only enforces conflict metadata and requires an approval reason
- product-safe maintenance apply UI; Rust maintenance exists and is dry-run by default, but the shell does not yet expose a full apply/review workflow
- automatic approval gate; no class should auto-promote until a separate gate is designed and validated

Completed on 2026-05-25 in the Rust-refactored app tree:

- Swift shell candidate queue first slice under `x-hub-system/x-terminal`.
- `HubIPCClient` can list, approve, and reject Rust writeback candidates through:
  - `GET /memory/writeback/candidates`
  - `POST /memory/writeback/candidates/{memory_id}/approve`
  - `POST /memory/writeback/candidates/{memory_id}/reject`
- `ProjectSettingsView` shows a compact pending queue inside Hub memory governance for the selected project.
- The Swift shell only calls Rust endpoints and records bounded UI evidence; it does not mutate local active memory.
- Candidate content is previewed from title/summary/metadata by default; secret/private candidates are hidden by default.
- Rust TTL/stale maintenance first slice:
  - `POST /memory/writeback/candidates/maintenance`
  - CLI `xhubd memory candidate-maintenance`
  - dry-run by default, explicit `apply=1` required to mutate
  - low-risk stale `l3_working_set` / `l2_observations` candidates archive with memory events
  - high-value canonical candidates are marked `stale_review_required` and remain pending for explicit review
  - `/memory/readiness` now includes bounded candidate maintenance summary evidence
- Candidate lifecycle ops smoke:
  - `rust/xhubd/tools/memory_writeback_candidate_smoke.command`
  - runs an isolated temp `xhubd`/SQLite root
  - proves pending candidates do not retrieve as active memory, approve/reject transitions work, secret-like candidates fail closed, extract dry-run/apply stays candidate-only, and maintenance dry-run/apply preserves `production_authority_change=false`
- Rust conflict/supersession metadata first slice:
  - candidate create scans active memory with same scope/source_kind/layer and records `conflict_with`
  - conflicting candidate approval requires explicit `conflict_resolution_reason`
  - newer pending candidates archive older same-key pending candidates with `superseded_by`
  - rejected candidates are not resurrected by supersession
- Rust candidate diagnostics first slice:
  - `GET /memory/writeback/candidates` returns top-level `candidate_diagnostics`
  - `/memory/readiness` exposes `object_store.writeback_candidates.diagnostics`
  - diagnostics schema is `xhub.memory.writeback_candidate_diagnostics.v1`
  - diagnostics include candidate/conflict/stale/stale-review/superseded/superseding counts, planned archive/review counts, `queue_pressure`, `noise_score`, bounded IDs, and `production_authority_change=false`
- Swift shell metadata and Doctor first slice:
  - `HubIPCClient` decodes candidate `policy`, `provenance`, and `candidate_diagnostics`
  - `XTMemoryWritebackCandidateQueueStore` exposes conflict, stale-review, supersedes, and superseded state without becoming authority
  - conflict approval is fail-closed unless Swift sends `conflict_resolution_reason`
  - `ProjectSettingsView` shows a visible conflict approval reason field and disables approve until it is filled
  - `XTUnifiedDoctor` consumes Rust `/memory/readiness` and emits bounded candidate queue detail-lines without showing secret/private content
  - `XTUnifiedDoctorSection.rustMemoryWritebackCandidateQueueProjection` now exports the same queue state as typed JSON, so ops/UI code does not need to parse strings

## 3) Candidate Object Contract

The first slice stores candidates as Rust Memory objects. The stable conceptual candidate contract is:

```json
{
  "schema_version": "xhub.memory.writeback_candidate.v1",
  "memory_id": "mc_ax_project_decisions_hash",
  "status": "candidate",
  "scope": "project",
  "owner_id": "project_123",
  "project_id": "project_123",
  "source_kind": "decision_track",
  "layer": "l1_canonical",
  "title": "Decision candidate",
  "text": "Decision: use Rust candidate queue for memory writeback.",
  "summary": "Decision: use Rust candidate queue...",
  "sensitivity": "internal",
  "visibility": "local_only",
  "ttl_ms": null,
  "provenance_json": {
    "source": "xt_axmemory_delta_candidate_extract",
    "audit_ref": "audit-...",
    "created_by": "rust_hub",
    "evidence_refs": [],
    "candidate_reason": "deterministic_axmemory_delta",
    "production_authority_change": false
  },
  "policy_json": {
    "write_gate": "rust_policy_gated_candidate_queue",
    "requires_approval": true,
    "remote_export": "local_only"
  }
}
```

Required semantics:

- `status='candidate'` means not durable active truth.
- Candidate retrieval may be shown in inspector/doctor, but must not be served as normal active memory unless a debug/review mode explicitly asks for candidates.
- `visibility='local_only'` remains default until export policy says otherwise.
- `ttl_ms` is candidate freshness/queue retention metadata; it is not permission to auto-promote.
- `provenance_json.production_authority_change` must remain false for candidate creation/extraction.

## 4) Lifecycle State Machine

Current implemented states:

| Status | Meaning | Can normal retrieval serve it? | Current support |
| --- | --- | --- | --- |
| `candidate` | Proposed memory awaiting review | No | implemented |
| `active` | Durable approved memory object | Yes, if policy allows | implemented |
| `rejected` | Reviewed and denied | No | implemented |
| `archived` | Retained for history but not active | No | schema-supported, lifecycle work pending |
| `deleted` | Removed from active store, history may remain | No | schema-supported, lifecycle work pending |

Target lifecycle:

```text
extract/create
  -> candidate
    -> approve -> active
    -> reject -> rejected
    -> expire/stale-prune -> archived
    -> superseded-by-newer-candidate -> archived
    -> delete by policy/admin -> deleted
```

Rules:

- Only `candidate -> active` and `candidate -> rejected` are implemented now.
- `candidate -> archived` should be the TTL/stale path, not a silent reject.
- `candidate -> deleted` should be reserved for explicit admin/policy cleanup.
- `active -> candidate` is forbidden.
- `rejected -> active` is forbidden; create a new candidate with new evidence instead.
- `archived -> active` is forbidden unless a future explicit restore flow creates a new candidate.

## 5) Candidate Sources And Default Handling

| Source | Default action | Notes |
| --- | --- | --- |
| deterministic AXMemory delta | create candidate | implemented |
| model-generated after-turn summary | create candidate only | no direct active write |
| runtime fallback delta | create candidate only | implemented via XT caller path |
| heartbeat status | candidate or observation draft | must preserve evidence refs |
| reviewer guidance | candidate unless already protocol-backed active state | should keep reviewer note ID |
| tool result | evidence first, candidate only for stable facts | never store secret output |
| connector/email/file content | raw evidence or candidate under policy | external content stays untrusted by default |
| user manual edit in Swift inspector | candidate or explicit approved edit depending UX | still goes through Rust policy/event |

## 6) Never Auto-Promote Classes

These candidate classes must never auto-promote:

- credentials, tokens, private keys, cookies, OAuth material
- user identity, payment, legal, medical, financial, or safety policy facts
- X-Constitution, grant, revoke, kill-switch, route authority, provider key state
- cross-user, cross-project, cross-device, or remote-channel imported facts
- personal memory visible to Project Coder
- any candidate created from untrusted connector content without review
- any candidate whose source/evidence scope is ambiguous
- any candidate with `sensitivity=secret`
- any candidate with `visibility` broader than `local_only`
- any candidate that would weaken export gate, audit, grant, or policy constraints

Low-risk auto-approval remains future-only. If added later, it needs a separate gate with allowlisted source kinds, confidence thresholds, duplicate/supersession checks, bounded scope, audit, and kill-switch compatibility.

## 7) Deduplication And Supersession

Current deterministic dedupe:

- `memory_id = mc_ax_<project>_<kind>_<stable_text_hash>`
- same-batch duplicates are skipped
- existing active/candidate/rejected/deleted IDs are skipped with `duplicate_<status>`

Target dedupe/supersession:

- exact duplicate: skip
- same source kind + same normalized text: skip
- same source kind + newer contradicts older candidate: mark older as `archived` with `superseded_by`
- active object conflict: keep candidate pending with `conflict_with_memory_id`
- high-risk conflict: block approval until reviewer/admin resolves

Required future metadata:

```json
{
  "duplicate_of": "memory_id",
  "supersedes": ["memory_id"],
  "superseded_by": "memory_id",
  "conflict_with": ["memory_id"],
  "conflict_reason": "contradicts_active_decision",
  "candidate_generation": 2
}
```

Do not implement fuzzy semantic duplicate collapse until semantic retrieval is policy-gated and explainable.

## 8) TTL And Stale Handling

TTL is a queue hygiene mechanism, not an authorization mechanism.

Target TTL defaults:

| Candidate type | Suggested TTL | Expiry action |
| --- | --- | --- |
| `l3_working_set` next step/current state | 7 days | archive stale |
| `l2_observations` risk/open question/recommendation | 14 days | archive stale unless referenced by active run |
| `l1_canonical` decision/requirement/goal | 30 days | mark stale, require explicit archive/review |
| reviewer guidance / governance note | 30 days | keep pending but mark stale |
| personal/cross-link candidate | 30 days, review-required | never auto-promote |
| secret-like or denied candidate | immediate deny, no candidate row | implemented for secret-like text/audit refs |

Future stale job behavior:

1. list candidates older than TTL
2. skip candidates with active review lock
3. archive expired low-risk candidates
4. mark high-value canonical candidates as `stale_review_required`
5. write memory event for every archive/stale mark
6. report counts in `/memory/readiness` and daemon ops gate

Target evidence:

```json
{
  "schema_version": "xhub.memory.writeback_candidate_maintenance.v1",
  "candidate_count": 12,
  "stale_count": 3,
  "archived_count": 2,
  "stale_review_required_count": 1,
  "production_authority_change": false
}
```

## 9) Approval And Rejection Rules

Approve must:

- require current status `candidate`
- reject immutable object
- reject secret-like title/summary/text
- rerun role/use-mode/scope/source/layer policy
- preserve before/after JSON in memory event
- set status `active`
- increment version
- set `production_authority_change=false` for this Rust candidate pipeline response

Reject must:

- require current status `candidate`
- rerun policy enough to prove actor/action is allowed
- set status `rejected`
- record event with reason/audit ref
- never delete evidence by default

Future Swift UI must require a visible reason for:

- reject
- approve of canonical decision/requirement/goal
- approve of candidate with conflicts
- archive of canonical candidate

## 10) Doctor / Readiness / Ops Evidence

Implemented evidence now includes:

- candidate queue ready state under `/memory/readiness`
- candidate create/list/extract/approve/reject availability through the Rust endpoint surface and lifecycle smoke
- `candidate_count`
- `conflict_candidate_count`
- `stale_candidate_count`
- `stale_review_required_count`
- `superseding_candidate_count`
- `superseded_candidate_count`
- `archived_superseded_count`
- `planned_archive_count`
- `planned_stale_review_required_count`
- `queue_pressure`
- `noise_score`
- `production_authority_change=false`

`XTUnifiedDoctor` currently surfaces these read-only Rust truth lines:

- `rust_memory_writeback_candidate_queue_schema`
- `rust_memory_writeback_candidate_queue_ready`
- `rust_memory_writeback_candidate_queue_authority`
- `rust_memory_writeback_candidate_queue_candidates`
- `rust_memory_writeback_candidate_queue_conflicts`
- `rust_memory_writeback_candidate_queue_stale_review_required`
- `rust_memory_writeback_candidate_queue_stale`
- `rust_memory_writeback_candidate_queue_superseded`
- `rust_memory_writeback_candidate_queue_pressure`
- `rust_memory_writeback_candidate_queue_noise_score`
- `rust_memory_writeback_candidate_queue_planned_archive`
- `rust_memory_writeback_candidate_queue_planned_stale_review_required`
- `rust_memory_writeback_candidate_queue_production_authority_change`

Remaining target evidence:

- counts by scope/layer/source_kind
- denied secret candidate count
- latest candidate event timestamp
- last maintenance report path

Doctor must make candidate state visible without showing secret/private candidate content.

Daemon ops gate should block only when:

- candidate API is required but unavailable
- candidate approval path can auto-activate without event
- secret candidate smoke does not fail closed
- stale maintenance report has errors when maintenance is required
- production authority change appears in candidate-only paths

## 11) Work Orders

### W9-C1 Candidate Lifecycle Contract Freeze

- status: this document
- write set:
  - `docs/memory-new/xhub-memory-writeback-candidate-lifecycle-v1.md`
  - `docs/memory-new/xhub-universal-memory-layer-work-orders-v1.md`
  - `docs/memory-new/xhub-memory-runtime-authority-and-reality-map-v1.md`
- acceptance:
  - doc distinguishes implemented states from target states
  - doc states XT/Swift/Node cannot become durable writer authority
  - doc lists never-auto-promote classes

### W9-C2 Rust TTL / Stale Candidate Maintenance

- status: first slice implemented on 2026-05-25
- owner: Rust Hub Kernel
- write set:
  - `rust/xhubd/crates/xhubd/src/memory_bridge.rs`
  - `rust/xhubd/crates/xhub-db/src/lib.rs` if new query helpers are needed
  - `rust/xhubd/tools/daemon_ops_gate.js` or equivalent ops tooling if gate rollup is needed
- implementation:
  1. Done: add candidate maintenance dry-run API:
     - `POST /memory/writeback/candidates/maintenance`
     - query/body flags: `apply`, `dry_run`, `max_age_ms`, `limit`, `project_id`
     - CLI alias: `xhubd memory candidate-maintenance`
  2. Done: dry-run reports stale/archive plans without content leakage.
  3. Done: apply mode archives low-risk stale candidates and writes memory events.
  4. Done: high-value canonical candidates become `stale_review_required` metadata, not silent archive.
  5. Done: `/memory/readiness` includes stale/maintenance summary.
- tests:
  - Done: stale working-set candidate archives
  - Done: canonical candidate gets stale review marker
  - Done: active/rejected candidates are ignored
  - Done: maintenance dry-run does not mutate
  - Done: maintenance apply writes events
- verification:
  - `cargo test -p xhubd memory_writeback_candidate_maintenance`

### W9-C3 Swift Shell Candidate Queue

- status: first slice implemented on 2026-05-25
- owner: Swift Shell / XT Runtime
- write set:
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Project/XTMemoryWritebackCandidateQueueStore.swift`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - tests under `x-terminal/Tests/`
- implementation:
  1. Done: add `HubIPCClient.listMemoryWritebackCandidatesViaRust(...)`.
  2. Done: add `HubIPCClient.approveMemoryWritebackCandidateViaRust(...)`.
  3. Done: add `HubIPCClient.rejectMemoryWritebackCandidateViaRust(...)`.
  4. Done first slice: queue projection for selected project with layer/source_kind/sensitivity/visibility/staleness metadata.
  5. Done first slice: show title/summary/metadata only by default; secret/private content is hidden.
  6. Done: approve/reject calls Rust endpoints; Swift does not edit local active memory directly.
  7. Done: record UI evidence in project raw log with `production_authority_change=false`.
- tests:
  - Done: list candidates parses Rust response.
  - Done: approve/reject calls Rust decision path and preserves audit ref.
  - Done: UI projection labels candidate as pending, not active truth.
  - Done: secret/private candidate content is not displayed by default.
- verification:
  - `swift test --filter MemoryWritebackCandidateQueueTests`
    - passed on 2026-05-25 with 6 Swift Testing tests after diagnostics/conflict-reason coverage.

### W9-C4 Conflict And Supersession Metadata

- status: first slice implemented on 2026-05-25
- owner: Rust Hub Kernel / Memory Governance
- implementation:
  1. Done: add conflict detection against active objects by same scope/source_kind/layer.
  2. Done: add explicit conflict metadata in candidate policy/provenance JSON.
  3. Done: prevent approval of conflicting candidate unless reviewer supplies `conflict_resolution_reason`.
  4. Done: add superseded-by archive transition for candidate-only conflicts.
- tests:
  - Done: conflicting candidate requires resolution
  - Done: superseded pending candidate archives with event
  - Done: rejected candidate is not silently resurrected
- verification:
  - `cargo test -p xhubd memory_writeback_candidate`

### W9-C5 Candidate Ops Smoke

- status: first slice implemented on 2026-05-25
- owner: QA / Rust Hub Kernel
- implementation:
  1. Done: add smoke that creates candidate in temp DB.
  2. Done: prove active retrieval does not return candidate.
  3. Done: approve candidate.
  4. Done: prove active retrieval returns approved memory.
  5. Done: reject another candidate.
  6. Done: prove rejected candidate is not retrieved.
  7. Done: prove secret-like candidate fails closed.
  8. Done: prove extract dry-run/apply remains candidate-only.
  9. Done: prove maintenance dry-run/apply archives low-risk stale candidates and marks canonical stale review.
  10. Done: emit bounded report.
- acceptance:
  - report has no memory content beyond safe preview/hash
  - report includes `production_authority_change=false`
  - daemon ops gate can consume report
- verification:
  - `bash rust/xhubd/tools/memory_writeback_candidate_smoke.command`

### W9-C6 Candidate Diagnostics And Noise Metrics

- status: first slice implemented on 2026-05-25
- owner: Rust Hub Kernel / Memory Governance
- implementation:
  1. Done: add `xhub.memory.writeback_candidate_diagnostics.v1`.
  2. Done: make `GET /memory/writeback/candidates` return top-level `candidate_diagnostics`.
  3. Done: make `/memory/readiness` expose `object_store.writeback_candidates.diagnostics`.
  4. Done: compute conflict, stale, stale-review, supersession, planned archive, planned review, queue pressure, and noise score from Rust objects.
  5. Done: keep diagnostics bounded and content-free.
  6. Done: keep `production_authority_change=false`.
- tests:
  - Done: diagnostics report active conflicts and high queue pressure.
  - Done: diagnostics report superseding/superseded state.
  - Done: diagnostics report stale-review state from maintenance.
- verification:
  - `cargo test -p xhubd memory_writeback_candidate`
  - `bash rust/xhubd/tools/memory_writeback_candidate_smoke.command`

### W9-C7 Swift Conflict Approval Reason And Doctor Surfacing

- status: first slice implemented on 2026-05-25
- owner: Swift Shell / XT Runtime / Doctor
- implementation:
  1. Done: decode candidate `policy`, `provenance`, and `candidate_diagnostics`.
  2. Done: expose conflict/stale-review/supersession state in `XTMemoryWritebackCandidateQueueStore`.
  3. Done: require `conflict_resolution_reason` before approving a conflicting candidate.
  4. Done: show a visible conflict approval reason field in `ProjectSettingsView`.
  5. Done: disable approve until a conflict reason is present.
  6. Done: fetch Rust `/memory/readiness` into AppModel and pass it into `XTUnifiedDoctor`.
  7. Done: emit bounded `rust_memory_writeback_candidate_queue_*` Doctor detail-lines.
- tests:
  - Done: list response decodes candidate diagnostics.
  - Done: store fails closed on blank conflict approval reason.
  - Done: valid conflict approval reason is forwarded to Rust.
  - Done: Doctor report includes Rust candidate diagnostics detail-lines.
  - Done: Rust readiness presentation decodes writeback candidate diagnostics.
- verification:
  - `swift test --filter MemoryWritebackCandidateQueueTests`
  - `swift test --filter XTUnifiedDoctorReportTests/sessionRuntimeSectionIncludesRustMemoryWritebackCandidateQueueDiagnostics`
  - `swift test --filter RustHubReadinessPresentationTests/memoryReadinessDecodesWritebackCandidateDiagnostics`

### W9-C8 Typed Doctor Export Projection

- status: first slice implemented on 2026-05-25
- owner: Swift Shell / Doctor / Ops
- write set:
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-terminal/Tests/XTUnifiedDoctorReportTests.swift`
- implementation:
  1. Done: add `XTUnifiedDoctorRustMemoryWritebackCandidateQueueProjection`.
  2. Done: attach `rustMemoryWritebackCandidateQueueProjection` to the `session_runtime_readiness` section.
  3. Done: export snake-case typed fields for schema, ready, authority, source, candidate/conflict/stale/stale-review/supersession/planned-maintenance counts, queue pressure, noise score, and production-authority state.
  4. Done: keep the projection content-free; no candidate text, candidate IDs, or secret/private previews are exported.
  5. Done: keep the existing detail-lines for backward compatibility.
- tests:
  - Done: Doctor report carries the typed projection.
  - Done: JSON export contains snake-case count/status fields.
  - Done: JSON export does not include candidate IDs/content.
- verification:
  - `swift test --filter XTUnifiedDoctorReportTests/sessionRuntimeSectionIncludesRustMemoryWritebackCandidateQueueDiagnostics`

### W9-C9 Daemon Ops Candidate Rollup

- status: first slice implemented on 2026-05-25
- owner: Rust Hub Kernel / Ops Gate
- write set:
  - `rust/xhubd/tools/xhubd_daemon.js`
- implementation:
  1. Done: add a bounded `/memory/readiness` probe for `ops-report` and `ops-gate`.
  2. Done: roll `object_store.writeback_candidates.diagnostics` into `memory_writeback_candidate_ops_rollup`.
  3. Done: expose top-level queue ready/pressure/noise/conflict/stale-review/production-authority fields.
  4. Done: keep ops output content-free; candidate IDs, text, refs, previews, and private content are not copied into ops reports.
  5. Done: block ops-gate on production authority change or diagnostics schema mismatch when present.
  6. Done: leave missing diagnostics as explicit unavailable evidence instead of making old/live binaries a new memory authority.
- verification:
  - `node --check rust/xhubd/tools/xhubd_daemon.js`
  - `git diff --check -- rust/xhubd/tools/xhubd_daemon.js`
  - `bash rust/xhubd/tools/daemon_ops_gate.command --max-slow-requests 0` exercised the new fields; that strict run failed only on pre-existing slow-request / authority-allow gates, not on candidate rollup production-authority evidence.
  - `bash rust/xhubd/tools/daemon_ops_gate.command --max-slow-requests 1 --allow-memory-skills-production` passed with `issues=[]` and exported `memory_writeback_candidate_ops_rollup`.

### W9-C10 Swift Maintenance Review Controls

- status: first slice implemented on 2026-05-25
- owner: Swift Shell / Rust Hub Memory Governance
- write set:
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Project/XTMemoryWritebackCandidateQueueStore.swift`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Tests/MemoryWritebackCandidateQueueTests.swift`
- implementation:
  1. Done: add Swift models and HTTP caller for Rust `POST /memory/writeback/candidates/maintenance`.
  2. Done: add store-level dry-run preview and apply maintenance actions.
  3. Done: require a successful dry-run with planned work before the Swift shell enables/apply-calls maintenance.
  4. Done: add Project Settings buttons for refresh, maintenance preview, and maintenance apply without making Swift a memory writer.
  5. Done: write bounded `xt.memory_writeback_candidate_maintenance.v1` raw-log evidence with counts/status only.
  6. Done: keep maintenance output content-free; candidate text/private previews are not logged by Swift.
- tests:
  - Done: decode Rust maintenance response and plan items.
  - Done: apply is denied until preview exists.
  - Done: preview/apply call Rust maintenance path and write bounded evidence.
- verification:
  - `swift test --filter MemoryWritebackCandidateQueueTests`

### W9-C11 Candidate Merge Review Detail Comparison

- status: first slice implemented on 2026-05-25
- owner: Swift Shell / Rust Hub Memory Governance
- write set:
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Project/XTMemoryWritebackCandidateQueueStore.swift`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Tests/MemoryWritebackCandidateQueueTests.swift`
- implementation:
  1. Done: add a Swift caller for Rust `GET /memory/objects/{memory_id}` so review UI can fetch referenced active/candidate objects from Hub truth.
  2. Done: add candidate-row `conflict_with`, `supersedes`, and `superseded_by` reference expansion for read-only comparison.
  3. Done: render loaded referenced objects in Project Settings with Rust-provided status/layer/source/sensitivity metadata and bounded body preview.
  4. Done: record content-free `xt.memory_writeback_candidate_merge_review.v1` local evidence with reference/object/missing counts only.
  5. Done: keep Swift as review shell only; merge comparison does not create, mutate, approve, reject, archive, or supersede memory.
- tests:
  - Done: Rust memory object response decodes referenced object metadata.
  - Done: merge review loads conflict/supersedes objects through the Rust caller.
  - Done: merge review evidence omits referenced object content.
- verification:
  - `swift test --filter MemoryWritebackCandidateQueueTests`

## 12) Acceptance For Closing UML-W9

UML-W9 can be considered closed only when:

1. Candidate create/list/extract/approve/reject are implemented and tested.
2. Candidate creation never creates active memory.
3. Candidate approval requires valid `candidate -> active` transition and writes event.
4. Rejection writes event and blocks future direct activation.
5. Secret-like candidate content/audit refs fail closed.
6. Duplicate collapse is deterministic and explainable.
7. TTL/stale candidate handling exists or is explicitly deferred with a report.
8. Swift shell can show candidates and call Rust approve/reject without becoming authority.
9. Doctor/readiness/ops evidence can explain candidate count, conflict count, stale count, stale-review count, queue pressure, noise score, planned maintenance, production-authority state, and fail-closed behavior.
10. Swift shell can fetch Rust-owned conflict/supersession references for reviewer comparison without logging memory content.
11. XT/Swift/Node have not gained durable Memory writer authority.
