# X-Hub Role-Aware Conversation Contract v1

- status: active-protocol-and-work-order
- updatedAt: 2026-05-22
- owner: Hub Protocol / Rust Hub Kernel / Node Compat Hub / X-Terminal Runtime / Supervisor / Coder / Reviewer / QA
- dependsOn:
  - `docs/memory-new/xhub-memory-runtime-authority-and-reality-map-v1.md`
  - `protocol/hub_protocol_v1.proto`
  - `protocol/hub_protocol_v1.md`
- purpose:
  - 把 XT 本地 `project_transcript_observation` 升级为 Hub 可理解、可保存、可查询、可回读的 role-aware conversation truth/projection
  - 让 Supervisor dispatch、Coder reply、Reviewer note、tool approval/result、heartbeat 能用 `dispatch_id` / `run_id` / `launch_run_id` 串起来
  - 明确这是一项 Hub-first protocol/runtime 升级，不是 XT 本地 Memory authority 补丁

## 1) Boundary

固定边界：

- Hub owns durable turns and role-aware projection truth.
- XT may send role metadata, display projection, maintain a short local fallback, and build prompts from Hub projection.
- XT must not create a second durable Memory authority.
- `dispatch_id`, `run_id`, `launch_run_id`, `tool_call_id`, and `reviewer_note_id` are correlation IDs only. They do not grant permissions, model route authority, tool authority, Memory authority, or export permission.
- Missing metadata must not break old clients.
- Invalid or cross-scope metadata must fail closed.

## 2) Current Reality

This contract already has a first implementation slice:

- Proto:
  - `RoleTurnMetadata` exists in `protocol/hub_protocol_v1.proto`
  - mirrored in `rust/xhubd/assets/proto/hub_protocol_v1.proto`
  - `ChatMessage.turn_metadata` is optional
  - `GetProjectRoleTranscriptProjection` exists in the canonical proto
- Protocol docs:
  - `protocol/hub_protocol_v1.md` documents the role metadata behavior under Memory section 12.1
- Node compatibility Hub:
  - `turns` table has role metadata columns
  - migration adds missing columns and indexes
  - `AppendTurns` accepts metadata, normalizes it, validates project scope, stores JSON + query columns, and writes audit evidence
  - `GetWorkingSet` returns metadata for stored turns
  - `GetProjectRoleTranscriptProjection` returns Hub-built role-aware projection
  - old `role/content` clients still pass
- Rust Hub:
  - read-only `/memory/project-role-transcript` projection path exists over Hub turn rows
  - it is projection/readback, not proof that Node should remain future Memory authority
- X-Terminal:
  - `XTProjectConversationMirrorMessage` carries optional `turnMetadata`
  - `XTProjectConversationMirror` can generate role-aware messages and stable fallback dispatch IDs
  - `XTProjectTranscriptProjection` can prefer `hub_role_turn_metadata_projection` and fall back to local sender/text inference
  - `HubPairingCoordinator` JS bridge can send `turn_metadata` and request `GetProjectRoleTranscriptProjection`
- Tests/smoke:
  - `role_turn_metadata.test.js`
  - `role_turn_metadata_live_smoke.js`
  - XT projection/mirror tests exist around this path

Not complete yet:

- Rust is not yet the durable turns authority for this contract.
- Role-aware heartbeat/tool approval/tool result coverage is present in metadata schema/tests, but not guaranteed from every runtime path.
- Every Supervisor launch path does not yet provide true `dispatch_id` / `run_id` / `launch_run_id`; XT still has fallback IDs.
- Swift/XT product surfaces do not yet expose a complete role transcript debugger.
- Ops gate does not yet require role-turn live smoke evidence by default.
- Role metadata is not yet tied into every Memory Gateway / Serving Profile decision as a first-class input.

## 3) Contract Schema

Canonical metadata schema:

```proto
message RoleTurnMetadata {
  string schema_version = 1; // "xhub.role_turn_metadata.v1"

  string client_message_id = 2;
  string source_role = 3;
  string target_role = 4;
  string sender_role = 5;

  string project_id = 6;
  string root_project_id = 7;
  string thread_key = 8;

  string dispatch_id = 9;
  string dispatch_kind = 10;
  string run_id = 11;
  string launch_run_id = 12;
  string tool_call_id = 13;
  string reviewer_note_id = 14;

  string status = 15;
  repeated string evidence_refs = 16;
  repeated string audit_refs = 17;
  repeated string tags = 18;

  int64 observed_at_ms = 19;
}
```

Allowed role values for v1:

- `source_role`: `user`, `supervisor`, `coder`, `reviewer`, `tool`, `hub`, `system`
- `target_role`: `user`, `supervisor`, `coder`, `reviewer`, `all`, `none`

Current `dispatch_kind` values:

- `supervisor_to_coder`
- `coder_reply`
- `reviewer_note`
- `user_request`
- `tool_approval`
- `tool_approval_decision`
- `tool_result`
- `heartbeat`

Current `status` values:

- `dispatched`
- `running`
- `awaiting_authorization`
- `failed`
- `completed`
- `observed`

The enum lists are intentionally string contracts for compatibility, but Hub must normalize and cap values instead of trusting arbitrary input.

## 4) Conversation Patterns

### 4.1 Supervisor Dispatch To Coder

```json
{
  "role": "user",
  "content": "Supervisor dispatches coder to wire the role-aware contract.",
  "turn_metadata": {
    "schema_version": "xhub.role_turn_metadata.v1",
    "client_message_id": "msg-supervisor-1",
    "source_role": "supervisor",
    "target_role": "coder",
    "project_id": "project_123",
    "thread_key": "xterminal_project_project_123",
    "dispatch_id": "dispatch_123",
    "dispatch_kind": "supervisor_to_coder",
    "run_id": "run_123",
    "launch_run_id": "launch_123",
    "status": "dispatched",
    "evidence_refs": ["evidence://..."],
    "audit_refs": ["audit://..."],
    "observed_at_ms": 1778000000000
  }
}
```

Required:

- `dispatch_id` should come from Supervisor launch/runtime when available.
- XT fallback is allowed only until real launch/run IDs are consistently exposed.
- `project_id` must match authenticated scope.

### 4.2 Coder Reply

```json
{
  "role": "assistant",
  "content": "Coder reply keeps the same dispatch id.",
  "turn_metadata": {
    "schema_version": "xhub.role_turn_metadata.v1",
    "client_message_id": "msg-coder-1",
    "source_role": "coder",
    "target_role": "supervisor",
    "project_id": "project_123",
    "thread_key": "xterminal_project_project_123",
    "dispatch_id": "dispatch_123",
    "dispatch_kind": "coder_reply",
    "run_id": "run_123",
    "launch_run_id": "launch_123",
    "status": "completed",
    "observed_at_ms": 1778000000001
  }
}
```

Required:

- Coder reply should carry the same `dispatch_id`.
- A missing dispatch ID may use XT fallback, but projection must label this as fallback/local inference.

### 4.3 Reviewer Note

```json
{
  "role": "user",
  "content": "Reviewer note asks Coder to add one smoke test.",
  "turn_metadata": {
    "schema_version": "xhub.role_turn_metadata.v1",
    "client_message_id": "msg-reviewer-1",
    "source_role": "reviewer",
    "target_role": "coder",
    "project_id": "project_123",
    "thread_key": "xterminal_project_project_123",
    "dispatch_id": "dispatch_123",
    "dispatch_kind": "reviewer_note",
    "reviewer_note_id": "review_note_1",
    "status": "observed",
    "observed_at_ms": 1778000000002
  }
}
```

Required:

- Reviewer note must be read back through Hub projection.
- Reviewer note cannot directly mutate durable Memory; durable writeback still uses candidate/write gate.

### 4.4 Tool Approval / Decision / Result

Tool approval path uses the same `dispatch_id` plus `tool_call_id`:

- request awaiting permission:
  - `source_role=tool`
  - `target_role=supervisor`
  - `dispatch_kind=tool_approval`
  - `status=awaiting_authorization`
- approval decision:
  - `source_role=user` or `supervisor`
  - `target_role=coder`
  - `dispatch_kind=tool_approval_decision`
  - `status=completed` or `failed`
- result:
  - `source_role=tool`
  - `target_role=coder`
  - `dispatch_kind=tool_result`
  - `status=completed` or `failed`

Required:

- Tool metadata is evidence/projection. It does not replace grant chain, signed intent, risk classification, or audit.

### 4.5 Heartbeat

Heartbeat lines should use:

- `source_role=hub` or `tool`
- `target_role=supervisor` or `all`
- `dispatch_kind=heartbeat`
- `status=running|blocked|failed|completed|observed` where mapped by runtime

Required:

- Heartbeat is state/evidence/projection. It does not directly become durable Canonical Memory without writeback classification.

## 5) Hub Storage And Readback

Required Hub behavior:

1. `AppendTurns` accepts legacy role/content-only messages.
2. If metadata has no signal, Hub stores a legacy turn.
3. If metadata has signal, Hub normalizes it.
4. If metadata `project_id` mismatches authenticated project scope, Hub fails closed with `role_metadata_project_mismatch`.
5. Hub stores full bounded metadata JSON plus query columns:
   - `role_metadata_json`
   - `client_message_id`
   - `source_role`
   - `target_role`
   - `dispatch_id`
   - `dispatch_kind`
   - `run_id`
   - `launch_run_id`
   - `reviewer_note_id`
   - `status`
6. Hub indexes:
   - `(thread_id, dispatch_id, created_at_ms)`
   - `(thread_id, source_role, created_at_ms)`
   - `(run_id, launch_run_id, created_at_ms)`
7. `GetWorkingSet` returns `turn_metadata` for stored metadata turns.
8. `GetProjectRoleTranscriptProjection` returns:
   - `schema_version=xhub.project_role_transcript_projection.v1`
   - `source=hub_memory_turns`
   - latest supervisor dispatch
   - latest coder reply
   - latest reviewer note
   - recent role lines
   - optional content redaction through `include_content=false`

## 6) Projection Semantics

XT prompt projection may include:

```text
[project_transcript_observation]
source=hub_role_turn_metadata_projection
truth_boundary=Hub role-turn metadata projection; XT local sender/text inference is fallback only.
latest_dispatch_id=...
latest_supervisor_dispatch=...
latest_coder_reply=...
latest_reviewer_note=...
[/project_transcript_observation]
```

Rules:

- Prefer Hub projection when available.
- If Hub projection is unavailable, use XT local projection as fallback only.
- Fallback prompt block must explicitly say it is local projection and Hub remains authority.
- Projection is not durable Memory writeback.
- Projection does not grant skill/model/tool/memory/export authority.

## 7) Security Rules

Role metadata must obey:

- no private content in metadata fields
- content redaction applies to `content`, not metadata
- metadata strings must be capped and normalized
- unknown role values must normalize to blank/unknown or fail by policy; never trust arbitrary role strings
- project mismatch fails closed
- correlation IDs do not authorize
- role metadata cannot lower risk tier
- role metadata cannot bypass grant/approval chain
- role metadata cannot make remote export allowed
- role metadata cannot promote Memory candidates

## 8) Current Evidence

Known evidence/tests:

- `x-hub/grpc-server/hub_grpc_server/src/role_turn_metadata.test.js`
  - stores columns
  - verifies GetWorkingSet echoes metadata
  - verifies role transcript projection
  - verifies old clients without metadata still pass
  - verifies project mismatch fail-closed
- `x-hub/grpc-server/hub_grpc_server/src/role_turn_metadata_live_smoke.js`
  - live-style smoke for append/readback/projection/audit evidence
- `rust/xhubd/crates/xhubd/src/memory_role_projection.rs`
  - Rust read-only role transcript projection helper
- `x-terminal/Sources/Project/XTProjectConversationMirror.swift`
  - role metadata builder and fallback dispatch ID
- `x-terminal/Sources/Project/XTProjectTranscriptProjection.swift`
  - Hub projection first, local inference fallback
- `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - JS bridge for metadata send/readback projection

## 9) Work Orders

### RB-C1 Contract Freeze And Docs Truth

- status: this document
- write set:
  - `docs/memory-new/xhub-role-aware-conversation-contract-v1.md`
  - `docs/memory-new/xhub-memory-runtime-authority-and-reality-map-v1.md`
  - `protocol/hub_protocol_v1.md`
- acceptance:
  - states current implemented slice vs unfinished authority migration
  - states correlation IDs do not grant permission
  - states XT local projection is fallback only

### RB-C2 Rust Durable Projection Cutover Plan

- status: next Rust design/implementation slice
- owner: Rust Hub Kernel / Node Compat Hub
- goal:
  - move role-aware transcript projection authority toward Rust without breaking old Node HubMemory clients
- implementation:
  1. Identify current turn storage source used by Rust `/memory/project-role-transcript`.
  2. Add parity smoke comparing Node `GetProjectRoleTranscriptProjection` and Rust HTTP projection for the same test rows.
  3. Add readiness evidence:
     - `role_turn_projection_http=true`
     - `role_turn_projection_source`
     - `role_turn_projection_parity_ok`
     - `role_turn_projection_authority`
  4. Keep Node as compatibility until parity evidence is green.
- tests:
  - Rust projection returns supervisor/coder/reviewer lines with same dispatch ID.
  - `include_content=false` equivalent path does not leak content.
  - mismatch project denies.

### RB-C3 Real Supervisor Launch IDs

- status: next XT/Supervisor runtime slice
- owner: X-Terminal Runtime / Supervisor
- goal:
  - replace fallback `xt_dispatch_<project>_<createdAtMs>` IDs with true Supervisor launch/run IDs wherever possible
- implementation:
  1. Audit every call to `XTProjectConversationMirror.roleAwareMessages(...)`.
  2. Ensure Supervisor dispatch path provides `dispatch_id`, `run_id`, `launch_run_id`.
  3. Ensure Coder reply inherits same IDs.
  4. Ensure reviewer note can carry `reviewer_note_id`.
  5. Add fallback evidence when true IDs are unavailable.
- tests:
  - Supervisor dispatch and Coder reply share dispatch ID.
  - Reviewer note carries reviewer note ID.
  - Fallback dispatch ID is stable and labelled fallback.

### RB-C4 Tool / Heartbeat Runtime Coverage

- status: next runtime coverage slice
- owner: XT Runtime / Rust Hub Kernel / Node Compat Hub
- goal:
  - make tool approval, tool result, and heartbeat consistently visible in role transcript projection
- implementation:
  1. Wire tool approval request metadata.
  2. Wire tool approval decision metadata.
  3. Wire tool result metadata.
  4. Wire heartbeat metadata for project execution heartbeat.
  5. Add projection status mapping for pending/failed/completed.
- tests:
  - pending tool approval sets transcript status `awaiting_authorization`.
  - tool result clears pending status.
  - failed tool result surfaces `failed`.
  - heartbeat does not override active dispatch/coder reply status incorrectly.

### RB-C5 Ops Smoke And Gate Evidence

- status: after RB-C2/RB-C4
- owner: QA / Rust Hub Kernel / Node Compat Hub
- goal:
  - make role-aware conversation contract verifiable in release/ops gates
- implementation:
  1. Promote `role_turn_metadata_live_smoke.js` into an ops/report command if not already wired.
  2. Report:
     - append metadata count
     - dispatch IDs
     - source roles
     - GetWorkingSet readback ok
     - projection readback ok
     - legacy no-metadata ok
     - mismatch fail-closed ok
     - secret/private metadata policy ok
  3. Add bounded report with no long content.
  4. Add daemon ops gate optional require flag.
- acceptance:
  - report proves Supervisor dispatch, Coder reply, Reviewer note share `dispatch_id`
  - report proves old clients still pass
  - report proves project mismatch denies

## 10) Acceptance For Closing RT-B

RT-B is complete only when:

1. Proto and mirrored Rust proto remain identical for role metadata messages.
2. Node compatibility path can append, store, audit, and read back role metadata.
3. Rust projection path has parity evidence or is clearly labelled read-only compatibility projection.
4. XT sends role-aware metadata for supervisor dispatch, coder reply, reviewer note, tool approval/result, and heartbeat where available.
5. XT projection prefers Hub metadata and labels local inference as fallback.
6. Real Supervisor launch/run IDs are used where available; fallback IDs are stable and labelled.
7. Old clients with only role/content still work.
8. Project mismatch fails closed.
9. No role metadata field grants permissions or bypasses policy/export/audit/kill-switch.
10. Ops smoke/report can prove the contract without leaking private content.
