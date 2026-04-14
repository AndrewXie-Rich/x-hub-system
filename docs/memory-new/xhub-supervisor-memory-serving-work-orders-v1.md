# X-Hub Supervisor Memory Serving Work Orders v1

- version: v1.1
- updatedAt: 2026-03-21
- owner: XT-L2 / Hub-L5 / QA / Product / Security
- status: active-implementation
- scope: 把 `Supervisor` 记忆系统从“layer-aware prompt assembly”推进到“portfolio / focused project / delta / evidence 四通道 serving plane”。
- parent:
  - `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`
  - `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `x-terminal/work-orders/xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-35-supervisor-memory-retrieval-progressive-disclosure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`

## 0) Why This Plan Exists

当前实现已经有三块重要基础：

- `Supervisor` 的 `focused_project_execution_brief`
- `use_mode + serving_profile + progressive disclosure`
- `project digests / portfolio snapshot / retrieval block`

但它们还没有被编成一个明确的 serving plane，所以存在三个问题：

1. `Longterm` 不是一等供给对象
2. `portfolio / focused project / delta / evidence` 语义仍混在 `canonical / observations / working_set` 中
3. 压缩仍偏字符串裁剪，而不是语义槽位压缩

这份工单的目标不是增加更多 memory layer，而是把现有 truth-source 重新组织成更适合 `Supervisor` 和 `project AI` 的供给拓扑。

## 0.1) Current Progress Snapshot

截至 2026-03-14，已落地的关键切片：

- `SMS-W1` partial:
  - `MEMORY_V1` 顶层已稳定暴露 `PORTFOLIO_BRIEF / FOCUSED_PROJECT_ANCHOR_PACK / DELTA_FEED / LONGTERM_OUTLINE`
  - `SupervisorSystemPrompt` 已明确要求优先读取 serving objects，再决定是否下钻
- `SMS-W2` partial:
  - `LONGTERM_OUTLINE` 已成为一等供给对象
  - `focused_project_anchor_pack` 内已回挂 `longterm_outline`
- `SMS-W3` partial:
  - `DELTA_FEED` 已升级为结构化对象，带 `cursor_from / cursor_to / focus_project_id / project_state_hash_before / project_state_hash_after / portfolio_state_hash_before / portfolio_state_hash_after / material_change_flags / delta_items`
  - `SupervisorReviewNoteRecord` 已持久化 `memory_cursor / project_state_hash / portfolio_state_hash`
  - `latest_review_note` 已可稳定向后续 `Supervisor / coder` 暴露 review cursor 与状态哈希
  - 无 material change 时会显式给出 `no_material_change`，避免无意义重播项目全背景
- `SMS-W4` partial:
  - `CONFLICT_SET / CONTEXT_REFS / EVIDENCE_PACK` 已进入 `SupervisorManager -> HubIPCClient -> HubMemoryContextBuilder -> MEMORY_V1` 主链
  - `SupervisorSystemPrompt` 已明确三者的使用语义：冲突先显式化、refs 用于追证、evidence pack 不是全文回放
  - 已补定向测试覆盖 `Supervisor` 本地 memory、prompt 与 `HubMemoryContextBuilder`
- `SMS-W5` partial:
  - `HubMemoryContextBuilder` 已对 `PORTFOLIO_BRIEF / FOCUSED_PROJECT_ANCHOR_PACK / LONGTERM_OUTLINE / DELTA_FEED / CONFLICT_SET / CONTEXT_REFS / EVIDENCE_PACK` 落 object-aware compression，而不是只做裸字符串裁剪
  - 紧预算下会显式输出 `compression_reason / dropped_items / dropped_fields`
  - 已补 Hub 侧定向测试，验证 object-aware compression metadata 会进入 `MEMORY_V1`
- `SMS-W6` partial:
  - `review_level_hint` 已贯通 `SupervisorManager -> HubIPCClient -> RELFlowHubCore -> HubMemoryContextBuilder`
  - `Supervisor` 本地 fallback、Hub 侧 `MEMORY_V1` builder、remote snapshot fallback 已统一输出 `[SERVING_GOVERNOR]`
  - `SERVING_GOVERNOR` 已稳定暴露 `review_level_hint / profile_floor / minimum_pack / compression_policy`
  - 上述本地/远端 snapshot fallback 当前按 serving fallback 理解，不重新执行 memory model resolution；`SERVING_GOVERNOR` 应继续回显上游 `route_source / route_reason_code / fallback_applied / fallback_reason / model_id`
  - `r1_pulse / r2_strategic / r3_rescue` 已开始对 supervisor serving object budget floor 生效，避免战略 review 退化成薄摘要
  - 已补 X-Terminal 定向测试，验证本地 governor 文本与远程 request payload 传播

当前尚未完成的重点：

- `conflict_set / context_refs / evidence_pack` 已升格为标准 serving object，但 slot-level compression governor 还没补完
- object-level compression governor 仍未把 dropped counters、freshness policy 与 staged evidence expansion 完全统一到 `M0..M4 / r1..r3`
- `M0..M4 / r1..r3 / freshness policy` 仍需继续收束成一套完整且可量化的行为

## 0.2) Wave-0 参考借鉴在 Supervisor Serving 下的承接范围

来自 `docs/memory-new/xhub-memory-open-source-reference-wave0-execution-pack-v1.md` 的 `MRA-A2` 当前由本工单共同承接，范围限定为：

- Supervisor 必须消费统一的 expansion routing outcome
- Supervisor 不再私自发明一套与 Hub Retrieval 不一致的 deep recall 词典
- `answer_directly / expand_shallow / delegate_traversal` 的 explain 应可进入 serving governor / prompt explainability surface
- 最小 explain 字段固定为 `trigger_flags / budget_pressure / policy_floor / raw_evidence_allowed`

本轮不做：

- bounded expansion grant
- 新的 evidence grant contract
- 与 M2 主 PD contract 不一致的 recall API

## 0.3) Control-Plane Boundary

本工单固定是 `serving plane` 的执行父包，不是第二个 memory control plane。

它消费的上游 truth 来自：

- `memory_model_preferences`
- upstream mode profile（例如 `assistant_personal / project_code`）
- route diagnostics
  - `route_source`
  - `route_reason_code`
  - `fallback_applied`
  - `fallback_reason`
  - `model_id`
- `session_participation_class`
- `write_permission_scope`

本工单固定不做：

- 不本地重跑 `memory_model_router`
- 不替用户重选 memory maintenance model
- 不把 `serving_profile`、`review_level_hint`、`portfolio-first` 或 `delta-first` 语义扩写成新的模型选择面
- 不把 local fallback / remote snapshot fallback 当成第二次 memory route resolution

关系必须固定：

- 上游 control plane 决定“memory 维护链路按哪种 mode/profile bucket 执行”
- 本工单决定“Supervisor 看哪些对象、压到多深、什么时候 staged expansion”
- serving governor / prompt explainability 需要展示 route 信息时，必须直接回显上游 machine-readable truth，而不是在 Supervisor 侧派生第二套 route reason 词典

## 1) Finished State

完成后，系统至少要满足以下事实：

1. `Supervisor` 默认先看 `portfolio_brief`，再决定是否 drill down 到单项目。
2. 单项目 review 默认消费 `focused_project_anchor_pack`，而不是从混合的 `L1/L2/L3` 文本中猜语义。
3. `delta_feed` 成为一等对象，支持“自上次 review 后发生了什么”。
4. `Longterm` 成为一等供给层，至少能稳定提供 `longterm_outline`。
5. `conflict_set + context_refs + evidence_pack` 成为标准深挖链路。
6. 压缩从 prose clipping 升级为 slot-based + delta-based compression。

## 2) Workstreams

### 2.1 `SMS-W1` Freeze Supervisor Serving Objects And Prompt Envelope

- Goal:
  - 冻结 `portfolio_brief / focused_project_anchor_pack / delta_feed / conflict_set / context_refs / evidence_pack` 六个对象与 `MEMORY_V1` 顶层 envelope。
- Suggested touchpoints:
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorSystemPromptBuilder.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
- Depends on:
  - `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`
  - `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
- DoD:
  - `MEMORY_V1` 顶层 section 冻结
  - `SupervisorSystemPrompt` 明确先读 serving objects
  - `focused_project_execution_brief` 不再只是藏在 `L1/L3` 里
- Gate:
  - `SMS-G1`
- KPI:
  - `prompt_section_semantic_drift = 0`

### 2.2 `SMS-W2` Promote Longterm To First-Class Supervisor Input

- Goal:
  - 把 `Longterm` 从 metadata 升级为可稳定注入的 `longterm_outline / selected longterm sections`。
- Suggested touchpoints:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- Depends on:
  - `docs/xhub-memory-system-spec-v2.md`
  - `docs/xhub-memory-fusion-v1.md`
  - `x-terminal/work-orders/xt-w3-35-supervisor-memory-retrieval-progressive-disclosure-implementation-pack-v1.md`
- DoD:
  - `M2` 默认带 `longterm_outline`
  - `M3+` 可带 `selected longterm sections`
  - `Longterm` 引用可以回挂到 refs
- Gate:
  - `SMS-G2`
- KPI:
  - `focused_review_without_longterm_outline = 0`

### 2.3 `SMS-W3` Build Portfolio Lane And Project Action Delta Feed

- Goal:
  - 让 Supervisor 真正具备 `portfolio-first` 视角和 `delta-first` 巡检能力。
- Suggested touchpoints:
  - `x-terminal/work-orders/xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/MemoryUXAdapter.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- Depends on:
  - `SMS-W1`
  - `xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md`
- DoD:
  - `portfolio_brief` 默认成为 Supervisor 首视图
  - 引入 `last_seen_cursor / project_state_hash / material_change_flags`
  - 无 material change 时默认不重播完整背景
- Gate:
  - `SMS-G3`
- KPI:
  - `delta_replay_avoidance_rate >= 0.8`
  - `portfolio_stale_snapshot_false_positive = 0`

### 2.4 `SMS-W4` Surface Conflict Sets And Provenance Refs

- Goal:
  - 让 `Supervisor` 的战略纠偏有“冲突显式化 + 可追证”基础。
- Suggested touchpoints:
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorReviewNoteStore.swift`
- Depends on:
  - `SMS-W1`
  - `xt-w3-35-supervisor-memory-retrieval-progressive-disclosure-implementation-pack-v1.md`
- DoD:
  - `conflict_set` 顶层对象可生成
  - 每个关键结论至少能挂到 `context_refs`
  - `evidence_pack` 输出 `why_included`
- Gate:
  - `SMS-G4`
- KPI:
  - `answer_without_grounding_ref_rate <= 0.05`
  - `conflict_hidden_incidents = 0`

### 2.5 `SMS-W5` Replace String Clipping With Slot-Based Compression Governor

- Goal:
  - 把当前 token 裁剪升级为按对象、按字段优先级、按 delta 的压缩治理。
- Suggested touchpoints:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
  - `x-terminal/Sources/Hub/XTMemoryUsePolicy.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
- Depends on:
  - `SMS-W1`
  - `SMS-W2`
  - `SMS-W3`
- DoD:
  - 先压 `evidence_pack`，不先压 `done_definition`
  - 先删低优先级项目，不先删聚焦项目 anchor
  - 去除跨对象全文重复
  - 引入 `compression reason / dropped field counters`
- Gate:
  - `SMS-G5`
- KPI:
  - `compression_loss_rate <= 0.08`
  - `context_waste_ratio <= 0.2`

### 2.6 `SMS-W6` Align Supervisor Profiles, Review Ladder, And Safety Guards

- Goal:
  - 把 `M0..M4`、review level、风险治理、freshness policy 收成一致行为。
- Suggested touchpoints:
  - `x-terminal/Sources/Hub/XTMemoryUsePolicy.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorSystemPromptBuilder.swift`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
- Depends on:
  - `SMS-W1..W5`
  - `xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
- DoD:
  - `r1_pulse / r2_strategic / r3_rescue` 对应的最小输入梯子落实
  - 高风险动作优先 `freshness over size`
  - `remote_prompt_bundle` 仍 fail-closed
  - `M0..M4` / review ladder 只消费上游 mode/profile/route truth，不形成第二套 chooser
  - local / remote snapshot fallback 下 `SERVING_GOVERNOR` 仍可回放同一组上游 `route_source / route_reason_code / fallback_* / model_id`
- Gate:
  - `SMS-G6`
- KPI:
  - `high_risk_stale_context_usage = 0`
  - `review_without_min_input_pack = 0`

### 2.7 `SMS-W7` Tests, Metrics, And Require-Real Proof

- Goal:
  - 给这条链路补齐可回归的证据和门禁。
- Suggested touchpoints:
  - `x-terminal/Tests/`
  - `x-hub/grpc-server/hub_grpc_server/src/*.test.js`
  - `x-terminal/scripts/ci/xt_release_gate.sh`
  - `.github/workflows/`
- Depends on:
  - `SMS-W1..W6`
- DoD:
  - 覆盖 profile 升级、delta 优先、longterm 注入、冲突显式化、cross-scope fail-closed
  - 关键路径有 machine-readable evidence
  - `SERVING_GOVERNOR` / doctor / export 对同一请求复用同一份上游 route truth，不自行派生第二套 route 解释
  - 当 full diagnostics surface 可得时，直接复用 `Diagnostic-First Route Surface` 六组字段：
    - `request_snapshot`
    - `resolution_chain`
    - `winning_profile`
    - `winning_binding`
    - `route_result`
    - `constraint_snapshot`
  - Supervisor 本地追加的 `review_level_hint / profile_floor / minimum_pack / compression_policy / selected serving objects` 必须与上游 route truth 分开表达
  - 指标接入 CI 或 release gate
- Gate:
  - `SMS-G7`
- KPI:
  - `require_real_memory_serving_pass_rate = 1.0`
  - `serving_route_truth_surface_drift = 0`

## 3) Recommended Sequence

1. `SMS-W1`
   - 先冻结 serving objects，否则后面做的检索、压缩、prompt 调整都会反复返工。
2. `SMS-W2`
   - 先把 `Longterm` 提成一等对象，再谈战略纠偏。
3. `SMS-W3`
   - 把 `portfolio lane + delta feed` 建起来，让 Supervisor 真正先看盘面。
4. `SMS-W4`
   - 再补冲突和 provenance，让纠偏不靠感觉。
5. `SMS-W5`
   - 在对象语义稳定后再做压缩治理，避免“压缩优化”压在错误拓扑上。
6. `SMS-W6`
   - 最后统一 review ladder、profile ceiling 和安全边界。
7. `SMS-W7`
   - 用 tests / metrics / require-real 证据收口。

## 4) Immediate Next Slice

最值得先做的下一个 vertical slice：

1. 在 `HubMemoryContextBuilder` 中把 `string clipping` 进一步替换成 `slot/object-aware compression`
2. 为 `CONFLICT_SET / CONTEXT_REFS / EVIDENCE_PACK` 增加 `compression reason / dropped field counters`
3. 让 `M0..M4` 对这三类对象采用更清晰的 profile ceiling
4. 给 `r1_pulse / r2_strategic / r3_rescue` 建立最小输入包约束，优先保住 longterm anchor 与 active conflict

这样可以把当前已经完成的可追证 memory plane，推进到真正“长记忆不易丢、压缩不伤关键锚点、不同 review 深度行为一致”的生产级形态。
