# X-Hub Memory Serving Profile To Rust Gateway Alignment v1

- status: active
- updatedAt: 2026-05-23
- owner: Rust Hub Kernel / X-Terminal Runtime / Supervisor / Memory Governance
- purpose:
  - 把 `M0..M4 Memory Serving Profiles` 和当前 Rust `/memory/gateway/prepare` 现实对齐
  - 冻结下一步把 serving profile 变成 Rust gateway 一等输入/输出证据的工单
  - 避免后续 AI 把 `use_mode`、`serving_profile`、`permission/grant`、`model route` 混成同一件事
- parents:
  - `docs/memory-new/xhub-memory-runtime-authority-and-reality-map-v1.md`
  - `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
  - `docs/memory-new/xhub-universal-memory-layer-work-orders-v1.md`
  - `docs/xhub-memory-remote-export-and-prompt-gate-v1.md`
  - `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`

## 1) Fixed Boundary

Serving Profile 是 context serving 档位，不是 truth source、permission grant、model router，也不是 autonomy tier。

固定边界：

- Truth 仍在 Hub/Rust Memory objects/events/canonical/projections 里。
- Serving Plane 只做选择、裁剪、打包、扩容、降级和 evidence。
- `M0..M4` 决定“给多少、给多深、按什么包装方式给模型”。
- `use_mode` 决定当前任务语义和默认 profile 候选。
- `A-Tier / S-Tier / grant / policy` 决定 ceiling、权限、review、kill-switch，不由 profile 自己授予。
- `remote_export_requested=true` 仍必须走 remote export gate；profile 不能绕过 DLP、secret deny、local-only/never-export 过滤。
- Rust `/memory/gateway/prepare` 是目标 Memory serving authority；XT/Swift 只能调用、展示、缓存、比较、诊断。

一句话口径：

`M0..M4 是 Rust Memory Gateway 的 serving contract，不是 XT 本地 prompt 模板。`

## 2) Current Reality

当前 Rust 已有 prepare-only gateway：

- HTTP:
  - `POST /memory/gateway/prepare`
  - alias `POST /memory/context`
- CLI:
  - `xhubd memory gateway-prepare`
- response schema:
  - `xhub.memory.gateway_prepare.v1`
- current source:
  - `rust/xhubd/crates/xhubd/src/memory_bridge.rs`

当前已实现：

- policy 先于对象选择执行
- default project context 包含 `l1_canonical`、`l2_observations`、`l3_working_set`
- `l4_raw_evidence` 默认不进 gateway
- raw evidence 必须显式请求，并且必须被 Rust policy 允许
- remote export 请求会跳过非 `sanitized_remote_ok` 对象
- secret-like `latest_user/query` 会 fail closed
- project scope 必须有 `project_id`
- response 有 `requested_layers`、`effective_layers`、`slots`、`context_text`、skip counters
- response 固定 `production_authority_change=false`
- request 已接受一等 `serving_profile_id`
- missing profile 会从 `use_mode` 推导 M0/M1 default
- response 已返回 `selected_profile/effective_profile/expanded/expansion_reason`
- M0..M4 已由 Rust 解算默认 layers、source-kind hints、max items、snippet budget
- XT 已有 shadow compare、opt-in primary gateway、fail-closed require gate、cutover readiness evidence
- XT caller first slice 已发送 `serving_profile_id`，shadow/history/readiness 已按 profile 记录和比对
- daemon ops gate/report 已读取 profile-scoped readiness，包含 per-profile sample counts、downgrade/deny counters
- daemon ops gate/report 已读取 model-call plan-only smoke evidence，包含 wrapper readiness、execution-denial、no-text-leak / no-execution guards
- XT/Swift 已有真实生成前的 model-call shadow preflight：
  - local file-IPC enqueue 和 remote generate 执行前会在 env gate 打开时 fire-and-forget 调用 Rust `/memory/gateway/model-call-plan`
  - gate：`XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_PLAN_SHADOW=1`，并兼容 `XHUB_RUST_MEMORY_CONTEXT_GATEWAY_SHADOW=1`
  - 证据：`memory_gateway_model_call_plan_status.json` 与 `memory_gateway_model_call_plan_history.json`
  - 落盘只保存 schema/status/source/mode/authority、provider/model/task、profile/project/session、prompt/context/message/ref 计数和 guard flags；不保存 prompt/context 原文
  - 该 preflight 不等待、不阻塞、不改变现有 Swift/Node/remote/local 生成路径
  - 新 Rust Hub ops-report / ops-gate 已读取该证据；缺失默认不阻塞，显式 `--require-memory-gateway-model-call-plan-shadow` 才要求存在且 ok；一旦证据显示模型执行、prompt/context 泄露或 authority change，会进入 blocking issues
- Rust 已有非执行 model-call plan wrapper：
  - HTTP：`POST /memory/gateway/model-call-plan`
  - aliases：`POST /memory/gateway/generate-plan`、`POST /memory/model-call-plan`
  - CLI：`xhubd memory gateway-model-call-plan`
  - schema：`xhub.memory.gateway_model_call_plan.v1`
  - 行为：复用 Rust `/memory/gateway/prepare` 的 policy/profile/context 选择，只返回 admission/route/evidence plan；不调用模型、不调用 local ML bridge、不回显 prompt/context 原文；`execute/apply/commit` 请求 fail closed。
- Rust 已有 model-call execution admission gate：
  - HTTP：`POST /memory/gateway/model-call-execution-gate`
  - aliases：`POST /memory/gateway/generate-execution-gate`、`POST /memory/model-call-execution-gate`
  - CLI：`xhubd memory gateway-model-call-execution-gate`
  - schema：`xhub.memory.gateway_model_call_execution_gate.v1`
  - 默认行为：继续 fail-closed，不调用模型、不调用 local ML bridge、不回显 prompt/context 原文。
  - 显式 `XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTION_ADMISSION=1` 且 provider/model route authority 已在 Rust 时，gate 可返回 `ready_for_execution=true`，表示 Rust 已接管执行准入；这仍不等于真实 model-call execution 已迁入 Rust。
- Rust 已有 guarded model-call execute endpoint：
  - HTTP：`POST /memory/gateway/model-call-execute`
  - aliases：`POST /memory/gateway/generate`、`POST /memory/model-call-execute`
  - CLI：`xhubd memory gateway-model-call-execute`
  - schema：`xhub.memory.gateway_model_call_execute.v1`
  - 默认行为：`execute_guard_no_model_call`，不会调用模型。
  - 只有 admission ready、provider/model route authority 已在 Rust、`XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_LOCAL_EXECUTOR=1`、`XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_APPLY=1`、local-ML readiness ready、且 route 是 local provider 时，才会委托 Rust local-ML bridge。
  - ops/smoke 只记录 status/mode/authority/blocker/latency 这类 content-free 字段，不记录 prompt/context/result text。
- Rust 已有独立 guarded execute smoke / rollback evidence：
  - tool：`rust/xhubd/tools/memory_gateway_model_call_execute_smoke.js`
  - wrapper：`rust/xhubd/tools/memory_gateway_model_call_execute_smoke.command`
  - evidence：`memory_gateway_model_call_execute_smoke_status.json` 与 `memory_gateway_model_call_execute_smoke_history.json`
  - 默认 live probe 使用非 local provider，必须证明 `/memory/gateway/model-call-execute` 返回 blocked，且 `would_call_model/model_call_invoked/model_call_executed/local_ml_execute_http_invoked` 全为 false。
  - rollback plan 只记录需要 unset 的 env key；smoke 不设置 env、不重启 daemon、不修改 launchd、不切 authority。
  - `xhubd_daemon.js ops-report/ops-gate` 已能读取该 evidence；缺失默认不阻塞，显式 `--require-memory-gateway-model-call-execute-smoke` 才要求 present/blocked/content-free。

当前还没有完成：

- XT caller 还没有把所有 context-depth / review-depth / use-mode 入口全面映射成 profile request
- doctor UI/export 还需要更明确展示 per-profile readiness rollup
- model-call execution 还没有完全收进 Rust gateway；当前新增的是 plan-only wrapper + Rust execution admission gate + guarded local execute connector + 独立 execute smoke/rollback evidence，不是 live product execution cutover

因此本文件不宣称 Rust gateway 已经完整接管所有 Memory serving profile；当前完成的是 Rust prepare envelope、XT first caller slice、profile-scoped parity evidence、ops profile/model-call-plan rollup、model-call plan-only admission wrapper、Rust execution admission gate、guarded local execute connector、独立 execute smoke/rollback evidence，以及 XT/Swift 真实生成前的非阻塞 shadow preflight。下一步是把新版 Rust daemon 部署到 live base dir 后，先跑 `memory_gateway_model_call_execute_smoke` 并让 ops-gate 以 `--require-memory-gateway-model-call-execute-smoke` 验证 present/blocked/content-free；只有这条证据通过后，才能讨论让 XT 真实生成路径 opt-in 调用 `/memory/gateway/model-call-execute`。

## 3) Profile Semantics

### M0_Heartbeat

用途：

- heartbeat
- lane handoff
- user digest beat
- remote prompt bundle 的最薄上下文
- low-latency status/resume refs

Gateway target behavior：

- default layers:
  - `l1_canonical`
  - `l3_working_set`
- optional layers:
  - selected `l2_observations` only when they are current-status/anomaly/blocker refs
- raw:
  - denied by default
- budget:
  - very low `max_items`
  - short `max_snippet_chars`
- packaging:
  - refs/digest/handoff first
  - content optional
- remote export:
  - allowed only after export gate and visibility filtering

M0 不能变成“把最近原文都发出去”。它是 continuity/status handoff，不是 full context。

### M1_Execute

用途：

- project chat default
- coder normal execution
- tool plan
- session resume
- supervisor normal orchestration

Gateway target behavior：

- default layers:
  - `l1_canonical`
  - `l2_observations`
  - `l3_working_set`
- raw:
  - denied by default
- budget:
  - bounded default, optimized for low latency
- packaging:
  - focused canonical
  - recent/high-signal working set
  - current blockers/next steps
  - selected observations with refs

M1 是生产默认，不是浅层临时模式。它要快，但必须可解释。

### M2_PlanReview

用途：

- normal review
- planning
- conflict resolution
- failed retry after M1
- high-risk tool preflight needing more context

Gateway target behavior：

- default layers:
  - `l1_canonical`
  - `l2_observations`
  - `l3_working_set`
- expanded source kinds:
  - decisions
  - open questions
  - risks
  - recommendations
  - latest review/guidance
  - heartbeat anomaly summaries
- raw:
  - raw refs may appear as evidence refs
  - raw content stays denied unless explicit policy grants selected evidence
- budget:
  - more objects than M1, still not full scan
- packaging:
  - plan/review pack
  - conflict set
  - evidence refs

M2 的核心不是更大，而是能解释“为什么现在该这样计划/纠偏”。

### M3_DeepDive

用途：

- strategic review
- drift analysis
- rescue preparation
- long blocker diagnosis
- post-failure investigation

Gateway target behavior：

- layers:
  - `l1_canonical`
  - `l2_observations`
  - `l3_working_set`
  - selected longterm/outline-like objects when available
- raw:
  - selected raw evidence only under explicit policy allow
  - never default
- budget:
  - expanded, but still capped
- packaging:
  - lineage
  - conflict history
  - selected evidence chunks
  - expansion trace

M3 不能用“大窗口”绕过 policy。它只是允许更厚的 governed evidence pack。

### M4_FullScan

用途：

- portfolio review
- release readiness
- repo-wide memory audit
- critical pre-done review
- major rescue/postmortem

Gateway target behavior：

- layers:
  - profile may request all governed layers, but Rust policy decides effective layers
- raw:
  - selected/staged raw evidence only
  - never unbounded full dump
- budget:
  - highest allowed budget, still capped by role/scope/export/policy
- packaging:
  - staged scan
  - outline first
  - selected expansions
  - omitted/denied counters must be explicit

M4 不是“无条件全量注入”。即使长上下文可用，也必须分阶段、可回放、可审计。

## 4) Use Mode Mapping

Target Rust default mapping:

| use_mode | default profile | allowed escalation | hard constraints |
| --- | --- | --- | --- |
| `project_chat` | `M1_Execute` | M2 when user asks for plan/review/global context | project scope only unless explicit bridge |
| `session_resume` | `M1_Execute` | M2 for multiple unresolved threads | continuity floor is not durable promotion |
| `supervisor_orchestration` | `M1_Execute` | M2 for review, M3/M4 for portfolio/rescue | S-Tier is ceiling, not permission grant |
| `tool_plan` | `M1_Execute` | M2 for multi-module/high uncertainty | no action authority from memory profile |
| `tool_act_low_risk` | `M1_Execute` | M2 on conflict | policy/grant still separate |
| `tool_act_high_risk` | `M1_Execute` | M2/M3 only with fresh recheck | stale memory must deny/degrade |
| `lane_handoff` | `M0_Heartbeat` | M1 if handoff fails | refs/digest first |
| `remote_prompt_bundle` | `M0_Heartbeat` or `M1_Execute` | no automatic M3/M4 | remote export gate mandatory |

## 5) Target Gateway Request

Add a first-class profile envelope while keeping old clients compatible.

Target request fields:

```json
{
  "schema_version": "xhub.memory.gateway_prepare_request.v1",
  "serving_profile_id": "M1_Execute",
  "use_mode": "project_chat",
  "requester_role": "tool",
  "scope": "project",
  "project_id": "project-id",
  "agent_id": "optional-agent-id",
  "thread_key": "optional-thread-key",
  "remote_export_requested": false,
  "requested_layers": ["l1_canonical", "l2_observations", "l3_working_set"],
  "requested_source_kinds": ["project_goal", "decision_track", "next_step"],
  "latest_user": "optional query",
  "max_items": 12,
  "max_snippet_chars": 420,
  "read_limit": 48,
  "include_content": true,
  "freshness_policy": "fresh_if_high_risk",
  "profile_reason": "default_project_chat_execute"
}
```

Compatibility rules:

- If `serving_profile_id` is absent, Rust derives it from `use_mode/requester_role/scope/remote_export_requested`.
- If `requested_layers` is absent, Rust uses the profile default.
- If `requested_layers` is present, Rust treats it as a request, not an entitlement.
- If requested profile exceeds role/scope/remote-export ceiling, Rust returns the allowed effective profile/layers or denies fail-closed when there is no safe downgrade.
- Old clients with only `role/content` or old memory context calls must still work.

## 6) Target Gateway Response Evidence

The response must explain selection, expansion, denial, and fallback state without exposing sensitive content in diagnostics.

Target response additions:

```json
{
  "schema_version": "xhub.memory.gateway_prepare.v1",
  "serving_profile_id": "M2_PlanReview",
  "selected_profile": "M2_PlanReview",
  "effective_profile": "M1_Execute",
  "profile_reason": "requested_m2_but_remote_export_downgraded",
  "effective_layers": ["l1_canonical", "l2_observations", "l3_working_set"],
  "selected_count": 8,
  "omitted_count": 11,
  "denied_count": 2,
  "expanded": false,
  "expansion_reason": "remote_export_no_auto_deep_expand",
  "raw_evidence_allowed": false,
  "remote_export_filtered_count": 3,
  "fallback_disabled": false,
  "fallback_reason": "",
  "production_authority_change": false
}
```

Required evidence semantics:

- `serving_profile_id`: requested or derived profile.
- `selected_profile`: profile Rust attempted after request normalization.
- `effective_profile`: profile actually served after ceiling/policy/export constraints.
- `effective_layers`: only layers Rust policy allowed.
- `selected_count`: objects returned in slots/context.
- `omitted_count`: safe omissions due to budget/filter/relevance.
- `denied_count`: policy/security denied items or layer requests.
- `expanded`: whether profile escalated beyond initial/default pack.
- `expansion_reason`: machine-readable reason for expansion or non-expansion.
- `raw_evidence_allowed`: explicit boolean; absence should be treated as false.
- `remote_export_filtered_count`: count of local-only/never-export objects skipped.
- `fallback_disabled`: true when require mode blocks Swift/XT fallback.
- `production_authority_change`: must stay false for prepare-only gateway.

## 7) XT/Swift Caller Alignment

XT/Swift must become profile callers, not profile authorities.

Target caller behavior:

- Project Coder:
  - `project_chat`, `tool_plan`, normal Coder execution -> `M1_Execute`
  - plan/review/failure retry -> request `M2_PlanReview`
  - rescue/debug deep review -> request `M3_DeepDive`
- Supervisor:
  - normal orchestration -> `M1_Execute`
  - review/guidance -> `M2_PlanReview`
  - strategic/drift/rescue -> `M3_DeepDive`
  - portfolio/release review -> `M4_FullScan`, still under S-Tier ceiling
- Heartbeat/lane/user digest:
  - default `M0_Heartbeat`
- Remote prompt bundle:
  - `M0_Heartbeat` or `M1_Execute`
  - no automatic M3/M4
  - always `remote_export_requested=true`

XT must continue to record:

- Rust gateway source
- requested/effective profile
- requested/effective layers
- selected object count
- fallback used/disabled
- parity/drift evidence
- production_authority_change

XT must not:

- create a local durable Memory profile authority
- auto-promote local cache because a profile requested deeper context
- bypass Hub/Rust policy when Rust returns denied/downgraded
- treat A-Tier/S-Tier as profile output without resolver evidence

## 8) Work Orders

### SG-C1 Docs Freeze

- status: this document
- owner: Memory Governance
- write set:
  - `docs/memory-new/xhub-memory-serving-profile-gateway-alignment-v1.md`
  - `docs/memory-new/xhub-memory-runtime-authority-and-reality-map-v1.md`
  - `docs/memory-new/xhub-memory-doc-authority-map-v1.md`
  - `docs/WORKING_INDEX.md`
  - `X_MEMORY.md`
  - `docs/memory-new/xhub-universal-memory-layer-work-orders-v1.md`
- acceptance:
  - M0..M4 are mapped to Rust gateway target behavior
  - current gateway reality is stated without overclaiming
  - next code slices are clear enough for another AI to implement

### SG-C2 Rust Gateway Profile Envelope

- status: implemented-first-rust-slice
- owner: Rust Hub Kernel
- write set:
  - `rust/xhubd/crates/xhubd/src/memory_bridge.rs`
  - Rust gateway tests in the same crate
- implementation:
  1. Parse `serving_profile_id` / `servingProfileId`.
  2. Normalize allowed values:
     - `M0_Heartbeat`
     - `M1_Execute`
     - `M2_PlanReview`
     - `M3_DeepDive`
     - `M4_FullScan`
  3. Derive default profile from `use_mode` when absent.
  4. Convert profile to default `requested_layers`, `max_items`, `max_snippet_chars`, and source-kind hints only when caller omitted them.
  5. Apply existing Rust policy after derivation.
  6. Emit `serving_profile_id`, `selected_profile`, `effective_profile`, `profile_reason`, `selected_count`, `omitted_count`, `denied_count`, `expanded`, `expansion_reason`, `raw_evidence_allowed`, `remote_export_filtered_count`, `fallback_disabled`.
- acceptance:
  - old request with no `serving_profile_id` still passes
  - M0 defaults are smaller than M1 and exclude raw
  - M1 defaults remain current L1/L2/L3 behavior
  - M2 increases budget/source breadth without raw content by default
  - M3/M4 raw content requests fail closed unless policy allows
  - remote export with M3/M4 downgrades or denies instead of leaking local-only/raw
- tests:
  - done: `cargo test -p xhubd memory_gateway_prepare`
  - add cases for each profile default and remote-export downgrade

Implemented first slice:

- Rust parses `serving_profile_id` / `servingProfileId`.
- Missing profile derives from `use_mode`:
  - `lane_handoff` / `remote_prompt_bundle` -> `M0_Heartbeat`
  - other current modes -> `M1_Execute`
- Rust normalizes:
  - `M0_Heartbeat`
  - `M1_Execute`
  - `M2_PlanReview`
  - `M3_DeepDive`
  - `M4_FullScan`
- Invalid profile fails closed with `memory_gateway_serving_profile_invalid`.
- Profile defaults now set requested layers, source-kind hints, `max_items`, `max_snippet_chars`, and read-limit multiplier when the caller omits those fields.
- `remote_export_requested=true` downgrades M2/M3/M4 to effective `M1_Execute` instead of deep-exporting.
- Response now includes:
  - `serving_profile_id`
  - `selected_profile`
  - `effective_profile`
  - `profile_reason`
  - `selected_count`
  - `omitted_count`
  - `denied_count`
  - `expanded`
  - `expansion_reason`
  - `raw_evidence_allowed`
  - `remote_export_filtered_count`
  - `fallback_disabled`
  - `fallback_reason`
- Policy-denied responses include requested/effective profile evidence.
- Tests prove:
  - old caller without profile still derives M1 and passes
  - M0 uses a thinner L1/L3 profile and excludes L2 risk text
  - M2 expands budget/source breadth without raw content by default
  - remote M4 is downgraded to M1 and skips local-only objects
  - supervisor M3 raw request fails closed

### SG-C3 XT Profile Caller Mapping

- status: implemented-first-swift-caller-slice
- owner: X-Terminal Runtime
- write set:
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Project/XTContextAssemblyProfiles.swift`
  - `x-terminal/Sources/Project/XTRoleAwareMemoryPolicy.swift`
  - `x-terminal/Sources/Supervisor/SupervisorMemoryAssemblySnapshot.swift`
  - `x-terminal/Sources/Supervisor/SupervisorMemoryAssemblyDiagnostics.swift`
- implementation:
  1. Add Swift enum/strings for `M0_Heartbeat` through `M4_FullScan`.
  2. Map Project Context Depth and Review Memory Depth to requested profile.
  3. Preserve existing configured/recommended/effective resolver semantics.
  4. Send `serving_profile_id` to Rust gateway when available.
  5. Record requested/effective profile in shadow compare and cutover readiness evidence.
  6. Keep `.fileIPC` and old compatibility paths from becoming authority.
- acceptance:
  - normal project chat requests M1
  - heartbeat/lane handoff requests M0
  - supervisor plan/review requests M2
  - deep review requests M3 only when resolver allows
  - profile evidence appears in doctor/export snapshots

Implemented first slice:

- `HubIPCClient` maps the existing `XTMemoryRoleScopedRouter` result to Rust `serving_profile_id`.
- Caller-mode test coverage now proves the public `requestMemoryContextDetailed(...)` path sends canonical Rust profile IDs for:
  - `session_resume -> M1_Execute`
  - `project_chat` review signal -> `M2_PlanReview`
  - `supervisor_orchestration` full-scan signal -> `M3_DeepDive`
  - `tool_act_high_risk` explicit deep profile clamped -> `M2_PlanReview`
  - `remote_prompt_bundle` handoff -> `M0_Heartbeat`
  - `remote_prompt_bundle` review signal -> `M1_Execute`
  - explicit project `m4_full_scan -> M4_FullScan`
- Rust gateway requests now send canonical Rust profile IDs:
  - `M0_Heartbeat`
  - `M1_Execute`
  - `M2_PlanReview`
  - `M3_DeepDive`
  - `M4_FullScan`
- Swift no longer forces generic L1/L2/L3 layer and fixed item/snippet budgets on Rust gateway calls when profile defaults should apply.
- Rust gateway shadow compare records:
  - `serving_profile_id`
  - `selected_profile`
  - `effective_profile`
- Shadow compare history de-dupes by profile as well as role/use/project/hash.
- Require-mode cutover now rejects stale parity evidence for the wrong profile with `memory_gateway_cutover_evidence_profile_mismatch`.
- Cutover readiness can be scoped by `serving_profile_id` and reports profile fields when scoped.
- Rust gateway primary responses map Rust requested/effective profiles back to XT `requestedProfile` / `resolvedProfile`.
- Supervisor Doctor passes the current memory assembly resolved profile into generated cutover readiness evidence.

Verification status:

- Passed:
  - `swift test --filter rustMemoryGateway`

### SG-C4 Shadow Compare Profile Parity

- status: partially-covered-by-sg-c3
- owner: XT Runtime / QA
- write set:
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Tests/*MemoryGateway*`
  - doctor/evidence surfaces that already read gateway shadow compare history
- implementation:
  1. Add requested/effective profile to `memory_gateway_shadow_compare_status.json`.
  2. Add requested/effective profile to `memory_gateway_shadow_compare_history.json`.
  3. Update cutover readiness to require same profile, same scope, same project, fresh parity.
  4. Make profile mismatch a drift reason, not silent parity.
- acceptance:
  - M1 parity cannot authorize M3/M4 require-mode cutover
  - stale profile evidence blocks require mode
  - fallback-disabled response states which profile lacked parity evidence

### SG-C5 Ops Gate / Doctor Evidence

- status: ops-rollup-and-swift-report-profile-readiness-implemented
- owner: Rust Hub Kernel / XT Runtime / Ops
- write set:
  - `rust/xhubd/tools/xhubd_daemon.js`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Supervisor/SupervisorMemoryAssemblyDiagnostics.swift`
  - `x-terminal/Tests/HubIPCClientProjectCanonicalMemorySyncTests.swift`
  - `x-terminal/Tests/SupervisorDoctorTests.swift`
  - Rust/Node ops report plumbing if needed
  - XT doctor/export structures
- implementation:
  1. Surface latest gateway profile readiness summary.
  2. Count fresh parity samples per profile.
  3. Report profile downgrade/deny counters.
  4. Block only when require mode is enabled or `--require-memory-gateway-cutover-ready` is set.
  5. Keep bounded metadata only; no prompt content in ops reports.
- acceptance:
  - ops report can say which profile is ready/not ready
  - missing profile evidence is warning before require mode, blocking in require mode
  - `production_authority_change=true` remains a blocking violation

Implemented ops slice:

- `collectMemoryGatewayCutoverReadiness(...)` now forwards:
  - `serving_profile_id`
  - `selected_profile`
  - `effective_profile`
  - `max_age_ms`
  - `total_sample_count`
  - `latest_recorded_at_ms`
  - `oldest_considered_at_ms`
- It reads adjacent `memory_gateway_shadow_compare_history.json` / `memory_gateway_shadow_compare_status.json` when available and emits bounded per-profile rollup:
  - `profile_readiness_source`
  - `profile_readiness_sample_count`
  - `profile_downgrade_count`
  - `rust_deny_count`
  - `profile_readiness[]`
- `profile_readiness[]` includes only metadata counts, no prompt/context text:
  - `serving_profile_id`
  - `total_sample_count`
  - `fresh_sample_count`
  - `passing_sample_count`
  - `authority_violation_count`
  - `fresh_authority_violation_count`
  - `parity_failure_count`
  - `fresh_parity_failure_count`
  - `rust_source_mismatch_count`
  - `fresh_rust_source_mismatch_count`
  - `downgrade_count`
  - `deny_count`
  - `latest_recorded_at_ms`
  - `ready_for_require`
- Blocking behavior is unchanged:
  - missing readiness is non-blocking unless require mode is enabled
  - schema mismatch blocks only when explicit/required
  - authority violation remains blocking
  - not-ready blocks only when require mode is enabled
- Swift Doctor memory assembly findings now include profile identity in detail:
  - shadow compare findings include `serving_profile_id`, `selected_profile`, `effective_profile`
  - cutover readiness findings include `serving_profile_id`, `selected_profile`, `effective_profile`
- Swift-generated `memory_gateway_cutover_readiness.json` now includes the same bounded per-profile rollup:
  - `profile_readiness_source`
  - `profile_readiness_sample_count`
  - `profile_downgrade_count`
  - `rust_deny_count`
  - `profile_readiness[]`
- Swift Doctor readiness findings now include a compact `profile_readiness_sample` line so M0/M1/M2/M3/M4 readiness can be inspected without opening raw JSON.

Verification:

- `node --check rust/xhubd/tools/xhubd_daemon.js`
- fixture run of `xhubd_daemon.js ops-gate` with synthetic readiness/history proves:
  - `serving_profile_id=M3_DeepDive` is forwarded
  - `profile_downgrade_count=1`
  - `rust_deny_count=1`
  - per-profile `ready_for_require` is computed from fresh passing samples
- `swift test --filter rustMemoryGateway`
  - verifies generated Swift readiness carries profile rollup counts
  - verifies Doctor findings include compact profile readiness samples

### SG-C6 Live Profile-Suite Smoke Evidence

Status: implemented.

Files:

- `rust/xhubd/tools/memory_gateway_cutover_smoke.js`

The cutover smoke can now collect profile-aware sustained evidence without enabling require mode:

- `--serving-profile <M0_Heartbeat|M1_Execute|M2_PlanReview|M3_DeepDive|M4_FullScan>` records and checks one profile.
- `--profile-suite` / `--all-profiles` records and checks all canonical profiles.
- `--self-test` validates the in-memory readiness reducer, including fail-closed behavior when a required profile is missing.

The smoke now:

1. Sends `serving_profile_id` to Rust `/memory/gateway/prepare` for profile runs.
2. Lets Rust profile defaults choose layers, source kinds, item limits, and snippet budgets for profile runs.
3. Records profile identity and bounded counters in shadow evidence:
   - `serving_profile_id`
   - `selected_profile`
   - `effective_profile`
   - `profile_reason`
   - `expanded`
   - `expansion_reason`
   - selected/omitted/denied counters
   - remote export filtered count
   - fallback-disabled state
4. Deduplicates shadow history by role/use/project/profile/hash so M0..M4 evidence can coexist.
5. Builds `memory_gateway_cutover_readiness.json` with per-profile readiness:
   - each required profile must have `required_sample_count` fresh passing samples
   - missing profile evidence emits `memory_gateway_cutover_profile_missing`
   - stale or insufficient profile evidence remains blocking for require-mode preflight
6. Runs plan-only model-call wrapper smoke by default:
   - `POST /memory/gateway/model-call-plan` must return `xhub.memory.gateway_model_call_plan.v1` with `status=planned`
   - the plan must report `would_call_model=false` and `model_call_executed=false`
   - `execute:true` must fail closed with `memory_gateway_model_call_execute_not_enabled`
   - `POST /memory/gateway/model-call-execution-gate` must return content-free gate status
   - `POST /memory/gateway/model-call-execute` smoke uses a non-local provider to prove the endpoint blocks without invoking local-ML
   - readiness records bounded `model_call_plan_*` fields only, with no prompt/context text
7. Keeps the output bounded to metadata, counts, hashes, and short parity anchors.

Validation run on 2026-05-24 against the local `rust/xhubd` daemon:

- `node --check rust/xhubd/tools/memory_gateway_cutover_smoke.js`
- `node rust/xhubd/tools/memory_gateway_cutover_smoke.js --self-test`
- `node rust/xhubd/tools/memory_gateway_cutover_smoke.js --profile-suite`
  - generated `rust/xhubd/memory_gateway_cutover_readiness.json`
  - M0/M1/M2/M3/M4 each had at least 3 fresh passing samples
  - `profile_downgrade_count=0`
  - `rust_deny_count=0`
  - `production_authority_change=false`
- `node rust/xhubd/tools/xhubd_daemon.js ops-gate --memory-gateway-cutover-readiness-path rust/xhubd/memory_gateway_cutover_readiness.json --require-memory-gateway-cutover-ready --max-slow-requests 999999`
  - `memory_gateway_cutover_ready=true`
  - `memory_gateway_cutover_readiness_ok=true`
  - `blocking_issues=[]`

The local validation above is prepare/shadow/readiness evidence only. It does not by itself enable `XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE`.


Follow-on validation on 2026-05-25 against a temporary `xhubd` daemon on `127.0.0.1:50261`:

- `node --check rust/xhubd/tools/memory_gateway_cutover_smoke.js`
- `node --check rust/xhubd/tools/xhubd_daemon.js`
- `node rust/xhubd/tools/memory_gateway_cutover_smoke.js --self-test`
- `node rust/xhubd/tools/memory_gateway_cutover_smoke.js --http-base-url http://127.0.0.1:50261 --hub-base-dir /tmp/xhub-model-plan-smoke-Pj9hVf --samples 1 --required-samples 1 --serving-profile M1_Execute`
  - `model_call_plan_smoke_enabled=true`
  - `model_call_plan_ready=true`
  - `model_call_plan_execution_blocked=true`
  - `model_call_plan_issue_codes=[]`
- `node rust/xhubd/tools/xhubd_daemon.js ops-gate ... --memory-gateway-cutover-readiness-path /tmp/xhub-model-plan-smoke-Pj9hVf/memory_gateway_cutover_readiness.json --require-memory-gateway-cutover-ready --no-require-ready`
  - `memory_gateway_model_call_plan_smoke_enabled=true`
  - `memory_gateway_model_call_plan_ready=true`
  - `memory_gateway_model_call_plan_execution_blocked=true`
  - `issues=[]`

The `--no-require-ready` ops-gate mode was used only because the temporary daemon did not include the full live proto/assets tree; the model-call plan rollup itself was read and gated successfully.

Follow-on XT/Swift + Rust Hub ops validation on 2026-05-25:

- `swift test --filter HubIPCClientProjectCanonicalMemorySyncTests/rustMemoryGatewayModelCallPlanShadowRecordsBoundedStatusWhenEnabled`
  - validates bounded `memory_gateway_model_call_plan_status.json` / history evidence for Rust model-call shadow preflight
  - validates prompt text is not persisted in XT evidence
- `swift test --filter HubAIClientLocalRuntimeRecoveryTests`
  - validates the local file-IPC enqueue path still writes the existing request shape after the non-blocking shadow hook
- `node --check rust/xhubd/tools/xhubd_daemon.js`
  - validates new Rust Hub ops-report / ops-gate parser syntax
- temporary `ops-report --memory-gateway-model-call-plan-base-dir <tmp>` smoke
  - validates `memory_gateway_model_call_plan_status.json` and history are summarized by the canonical Rust Hub tool
  - validates the report carries only bounded route/count/safety fields, not prompt/context text

Live base-dir validation on 2026-05-24:

- The previously installed live runner under `~/Library/Application Support/AX/rust-hub/local/bin/xhubd` was missing the new Memory Gateway endpoint surface and returned `404` for `/memory/project-canonical-sync`.
- Built the current `xhubd` release binary and installed it to the live runner path.
  - Previous binary was backed up at `~/Library/Application Support/AX/rust-hub/local/bin/xhubd.backup.20260524T1330`.
- Re-enabled and bootstrapped the existing LaunchAgent:
  - label: `com.ax.xhubd.local`
  - runner: `~/Library/Application Support/AX/rust-hub/local/bin/xhubd`
  - live base dir: `~/Library/Application Support/AX/rust-hub/local`
- `launchd-status` now reports:
  - `loaded=true`
  - `running=true`
  - `pid_source=launchctl_print`
  - `pid_alive=true`
  - live DB path: `~/Library/Application Support/AX/rust-hub/local/data/hub.sqlite3`
- Live readiness confirms:
  - `memory_writer_authority_in_rust=true`
  - `skills_execution_authority_in_rust=true`
  - `ml_execution_authority_in_rust=true`
  - `provider_route_authority_in_rust=true`
  - `model_route_authority_in_rust=true`
  - `scheduler_authority_in_rust=true`
  - `xt_file_ipc_production_authority_in_rust=true`
  - `cross_network_ready=true`
  - `domain_public_endpoint_ready=true`
- Final launchd-owned live profile-suite smoke:
  - `node rust/xhubd/tools/memory_gateway_cutover_smoke.js --profile-suite --hub-base-dir ~/Library/Application\ Support/AX/rust-hub/local`
  - M0/M1/M2/M3/M4 each had 3 fresh passing samples.
  - `profile_downgrade_count=0`
  - `rust_deny_count=0`
  - `issues=[]`
- Final ops gate:
  - `--require-memory-gateway-cutover-ready`
  - `--allow-memory-skills-production`
  - `--require-memory-skills-production`
  - `--max-slow-requests 0`
  - result: `ok=true`, `memory_gateway_cutover_ready=true`, `memory_writer_authority_in_rust=true`, `skills_execution_authority_in_rust=true`, `issues=[]`.

Additional ops tooling fix:

- `xhubd_daemon.js launchd-status` now parses the full `launchctl print` stdout internally so long LaunchAgent environments do not truncate away the real `pid = ...` line.
- JSON output remains bounded; only internal pid parsing uses the untruncated stdout.

### SG-C7 Live Fail-Closed Require Cutover

Status: completed on 2026-05-25 against the launchd-owned live base dir.

Live cutover state:

- live base dir: `~/Library/Application Support/AX/rust-hub/local`
- LaunchAgent: `~/Library/LaunchAgents/com.ax.xhubd.local.plist`
- service label: `com.ax.xhubd.local`
- post-relaunch pid source: `launchctl_print`
- post-relaunch pid: `39382`
- persisted environment:
  - `XHUB_RUST_HUB_ROOT=~/Library/Application Support/AX/rust-hub/local`
  - `XHUB_RUST_MEMORY_CONTEXT_GATEWAY=1`
  - `XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE=1`
  - `XHUB_RUST_MEMORY_CONTEXT_GATEWAY_PARITY_MAX_AGE_MS=600000`

Cutover sequence:

1. Refreshed live M0/M1/M2/M3/M4 profile-suite evidence with `memory_gateway_cutover_smoke.js --profile-suite --hub-base-dir ~/Library/Application\ Support/AX/rust-hub/local`.
2. Ran `memory_gateway_cutover_session.js --apply --require` against the live readiness report.
3. Persisted the require-mode keys into the LaunchAgent plist.
4. Linted the plist.
5. Restarted the launchd service with `launchctl kickstart -k gui/501/com.ax.xhubd.local`.
6. Re-ran profile-suite smoke after relaunch so evidence timestamps matched the current system clock.
7. Ran final ops gate with:
   - `--require-memory-gateway-cutover-ready`
   - `--allow-memory-skills-production`
   - `--require-memory-skills-production`
   - `--max-slow-requests 0`

Final live evidence:

- `memory_gateway_cutover_session.js --status --require`:
  - `active_mode=require`
  - `primary_enabled=true`
  - `require_enabled=true`
  - `mismatch_keys=[]`
  - `memory_gateway_cutover_readiness.ok=true`
- live profile-suite smoke:
  - M0/M1/M2/M3/M4 each had 3 fresh passing samples.
  - `passing_sample_count=15`
  - `profile_downgrade_count=0`
  - `rust_deny_count=0`
  - `issue_codes=[]`
- final ops gate:
  - `ok=true`
  - `healthy=true`
  - `ready=true`
  - `slow_requests=0`
  - `max_observed_http_elapsed_ms=61`
  - `memory_gateway_cutover_ready=true`
  - `memory_gateway_cutover_readiness_ok=true`
  - `memory_writer_authority_in_rust=true`
  - `skills_execution_authority_in_rust=true`
  - `node_remains_authority=false`
  - `rust_product_kernel=true`
  - `swift_product_shell=true`
  - `issues=[]`
  - report: `rust/xhubd/reports/daemon_ops_gate_20260525T004409Z.json`

Operational note:

- `XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE=1` is now the live default for the launchd-owned local Hub.
- Swift/XT remain shell, projection, cache, and compatibility surfaces. They must not create a second durable Memory authority.
- The smoke command still reports `production_authority_change=false` because smoke only records evidence; the authority flip is the explicit session/plist cutover recorded above.

## 9) Acceptance For RT-C

RT-C is complete when:

1. Rust gateway accepts `serving_profile_id` while old callers still work.
2. Rust derives profile defaults from `use_mode` when profile is absent.
3. M0/M1/M2/M3/M4 each have tests proving default layers/budget/raw/export behavior.
4. Gateway response explains requested vs effective profile.
5. XT sends profile IDs from existing context-depth/review-depth/use-mode resolvers.
6. Shadow compare and cutover readiness are profile-scoped.
7. Doctor/ops evidence can explain selected, omitted, denied, expanded, downgraded, and fallback-disabled states.
8. Remote export remains separately gated.
9. No Swift/XT/Node durable Memory authority is introduced.
10. Smoke/evidence commands keep `production_authority_change=false`; live authority changes must be explicit session/plist cutovers with rollback state and ops evidence.

## 10) Code Reference Map

Rust:

- `rust/xhubd/crates/xhubd/src/memory_bridge.rs`
- `rust/xhubd/crates/xhubd/src/main.rs`

Swift / XT:

- `x-terminal/Sources/Hub/HubIPCClient.swift`
- `x-terminal/Sources/Project/XTContextAssemblyProfiles.swift`
- `x-terminal/Sources/Project/XTRoleAwareMemoryPolicy.swift`
- `x-terminal/Sources/Supervisor/SupervisorMemoryAssemblySnapshot.swift`
- `x-terminal/Sources/Supervisor/SupervisorMemoryAssemblyDiagnostics.swift`
- `x-terminal/Sources/UI/XTUnifiedDoctor.swift`

Ops:

- `tools/daemon_ops_gate.command`
- `tools/daemon_ops_report.command`

Docs:

- `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
- `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
- `docs/xhub-memory-remote-export-and-prompt-gate-v1.md`
- `docs/memory-new/xhub-memory-runtime-authority-and-reality-map-v1.md`
- `docs/memory-new/xhub-universal-memory-layer-work-orders-v1.md`
