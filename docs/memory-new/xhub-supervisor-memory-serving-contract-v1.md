# X-Hub Supervisor Memory Serving Contract v1

- version: v1.0
- updatedAt: 2026-03-13
- owner: Hub Memory / X-Terminal Supervisor / Hub Policy / QA
- status: proposed-active
- scope: 冻结 `Supervisor` 的记忆供给拓扑、压缩规则、预算档位与治理边界；用于支撑 `project AI` 自主推进、`Supervisor` 战略纠偏、portfolio awareness 与多 surface brief 投影。
- related:
  - `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/xhub-memory-system-spec-v2.md`
  - `docs/xhub-memory-fusion-v1.md`
  - `x-terminal/work-orders/xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-35-supervisor-memory-retrieval-progressive-disclosure-implementation-pack-v1.md`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Hub/XTMemoryUsePolicy.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`

## 0) Why This Contract Exists

当前系统已经有：

- `5-layer memory` 作为真相源
- `use_mode + serving_profile` 作为供给路由
- `focused_project_execution_brief` 作为 Supervisor 深看单项目的强基线

但在真正要支持下面三种能力时，还缺一个明确的供给合同：

1. `project AI` 长时间自主推进项目，不反复丢掉背景和战略边界
2. `Supervisor` 随时看 portfolio 全局，再一键 drill down 到单项目纠偏
3. voice / channels / XT UI / future companion 都消费同一份可治理 brief，而不是各自拼摘要

因此本合同冻结的不是新的 truth-source，而是：

`Supervisor 应该如何从 5-layer truth + workflow/runtime state 中取材、压缩、打包、扩容给模型。`

## 1) One-Line Decision

冻结决策：

`Supervisor 不直接消费“原始 L0..L4 文本拼接”，而是消费由 5-layer memory 编译出来的 serving objects。`

这些 serving objects 至少包含：

- `portfolio_brief`
- `focused_project_anchor_pack`
- `delta_feed`
- `conflict_set`
- `context_refs`
- `evidence_pack`

`L0..L4` 继续作为 truth/storage plane；上述对象属于 serving plane。

## 2) Fixed Decisions

1. `5-layer memory` 继续是唯一真相源，不新增第二套 Supervisor 长期事实源。
2. `short action carry` 与 `long background memory` 明确分离。
   - 例如 `grant / guidance` 的短时承接窗口可以很短，但不影响 Supervisor 对项目长期背景的理解。
3. `Supervisor` 默认是 `portfolio-first`，不是 `full-project-first`。
   - 默认先看全局盘面，再看单个聚焦项目。
4. `Longterm` 必须成为一等供给对象，而不是只留一段 metadata。
5. `delta since last review` 必须是一等对象，不能总靠重播全文背景。
6. `conflict + provenance` 必须 first-class。
   - 不允许只有 prose 摘要，没有证据引用。
7. 不允许 `full dump` 成为默认策略。
   - 即使模型支持长窗口，默认仍然是 staged expansion。

## 3) Planes And Topology

### 3.1 Storage Plane

保持不变：

- `L0 Constitution`
- `Raw Vault`
- `Observations`
- `Longterm`
- `Canonical`
- `Working Set`

### 3.2 Serving Plane

新增并冻结以下 Supervisor 专用 serving topology：

1. `Portfolio Brief`
   - 作用：让 Supervisor 先掌握全局态势
   - 典型 surface：heartbeat、voice brief、channel digest、Supervisor 首屏
2. `Focused Project Anchor Pack`
   - 作用：让 Supervisor 在单项目上快速建立稳定锚点
   - 典型 surface：战略 review、blocker review、plan correction
3. `Delta Feed`
   - 作用：回答“从我上次看之后发生了什么变化”
4. `Conflict Set`
   - 作用：显式暴露冲突，而不是静默揉平
5. `Context Refs`
   - 作用：把摘要回挂到 `canonical / observation / longterm / raw evidence` refs
6. `Evidence Pack`
   - 作用：只在需要时提供选段证据，而不是整桶倒

## 4) Canonical Serving Objects

### 4.1 `portfolio_brief`

默认是 Supervisor 每次进入会话、心跳播报、外部通道 digest 的第一输入对象。

最少字段：

- `portfolio_summary`
- `active_projects_top_n`
- `blocked_projects_top_n`
- `awaiting_grants_top_n`
- `queue_pressure_or_scheduler_state`
- `recommended_priority_order`
- `focus_candidate_project_id`
- `last_global_change_cursor`

单项目摘要最少字段：

- `project_id`
- `display_name`
- `goal_digest`
- `runtime_state`
- `next_step`
- `top_blocker`
- `waiting_on`
- `risk_level`
- `last_material_delta`

### 4.2 `focused_project_anchor_pack`

默认是 Supervisor 对单项目做继续推进、审查、纠偏时的最小稳定锚点。

最少字段：

- `project_id`
- `goal`
- `done_definition`
- `constraints_hard_lines`
- `approved_decisions`
- `longterm_outline`
- `background_hints`
- `current_state`
- `next_step`
- `top_blocker`
- `active_job_summary`
- `active_plan_summary`
- `latest_review_note`
- `latest_guidance`
- `pending_ack_guidance`
- `grant_clamp_killswitch_state`

固定要求：

- `done_definition` 不能被最近执行噪声挤掉
- `approved_decisions` 不能退化成“只有最近一次建议”
- `longterm_outline` 不能只剩一个布尔 metadata

### 4.3 `delta_feed`

默认回答：

- 上次 Supervisor 看过之后，哪些项目状态变了
- 当前聚焦项目有哪些 material changes
- 哪些 blocker、grant、guidance ack、计划状态发生了变化

最少字段：

- `cursor_from`
- `cursor_to`
- `material_change_flags`
- `project_state_hash_before`
- `project_state_hash_after`
- `delta_items`

`delta_items` 类型最少支持：

- `progress_delta`
- `blocker_delta`
- `decision_delta`
- `guidance_delta`
- `grant_delta`
- `verification_delta`
- `risk_delta`

### 4.4 `conflict_set`

当出现新旧结论不一致、跨层不一致、来源不一致时，必须显式输出。

最少字段：

- `conflict_id`
- `conflict_kind`
- `summary`
- `side_a`
- `side_b`
- `resolution_status`
- `refs`

`conflict_kind` 最少支持：

- `canonical_vs_observation`
- `longterm_vs_recent_execution`
- `decision_vs_guidance`
- `runtime_vs_memory`
- `cross_project_dependency`

### 4.5 `context_refs`

所有关键结论都必须能回挂。

最少字段：

- `ref_id`
- `ref_kind`
- `title`
- `source_scope`
- `token_cost_hint`
- `freshness_hint`

`ref_kind` 最少支持：

- `canonical_ref`
- `observation_ref`
- `longterm_ref`
- `raw_evidence_ref`
- `workflow_ref`

### 4.6 `evidence_pack`

只在 `M2+` 需要时展开，且默认是 `selected_chunks`，不是原文倾倒。

最少字段：

- `evidence_goal`
- `selected_items`
- `truncated_items`
- `redacted_items`
- `audit_ref`

每条 `selected_item` 最少字段：

- `ref_id`
- `source_kind`
- `why_included`
- `snippet`

## 5) Source Mapping

| Serving Object | Primary Truth Inputs | Secondary Runtime Inputs | Notes |
| --- | --- | --- | --- |
| `portfolio_brief` | `canonical`, `observations`, `working_set` | scheduler snapshot, pending grants, action feed | 默认不吃 raw evidence |
| `focused_project_anchor_pack` | `canonical`, `longterm`, `observations` | workflow state, review note, guidance injection, grant/clamp state | 单项目纠偏主对象 |
| `delta_feed` | `observations`, `working_set` | action ledger, state hash, last_seen cursor | 只保留 material changes |
| `conflict_set` | `canonical`, `longterm`, `observations` | runtime verification state | 冲突显式化，不做 prose 融平 |
| `context_refs` | all | retrieval/index metadata | 用于可逆摘要 |
| `evidence_pack` | `raw vault`, `observations`, `longterm sections` | retrieval results, tool traces | 必须选段、必须带 why |

固定接线意见：

- 当前 `focused_project_execution_brief` 直接升级为 `focused_project_anchor_pack` 的实现基线。
- 当前 `projectDigests + portfolio snapshot + project action feed` 直接升级为 `portfolio_brief` 的实现基线。
- 当前 Supervisor retrieval block 直接升级为 `context_refs + evidence_pack` 的实现基线。

## 6) Backward-Compatible Prompt Envelope

短期不推翻现有 `MEMORY_V1`，但冻结以下顶层 section：

```text
[MEMORY_V1]
[SERVING_PROFILE]
profile_id: m2_plan_review
scope: focused_project
[/SERVING_PROFILE]

[PORTFOLIO_BRIEF]
...
[/PORTFOLIO_BRIEF]

[FOCUSED_PROJECT_ANCHOR_PACK]
...
[/FOCUSED_PROJECT_ANCHOR_PACK]

[DELTA_FEED]
...
[/DELTA_FEED]

[CONFLICT_SET]
...
[/CONFLICT_SET]

[CONTEXT_REFS]
...
[/CONTEXT_REFS]

[EVIDENCE_PACK]
...
[/EVIDENCE_PACK]
[/MEMORY_V1]
```

兼容规则：

- `L0..L4` 可继续保留在内部构建链路中
- 但 Supervisor-facing prompt 应优先读这些 serving objects，而不是直接在 `L1/L2/L3` 中找语义
- `SupervisorSystemPrompt` 必须提示模型先读：
  - `PORTFOLIO_BRIEF`
  - `FOCUSED_PROJECT_ANCHOR_PACK`
  - `DELTA_FEED`
  - `CONFLICT_SET`

## 7) Serving Profiles For Supervisor

`Supervisor` 继续复用 `M0..M4`，但冻结其语义如下：

| Profile | Default Scope | Primary Objects | Token Target | Recommended Use |
| --- | --- | --- | --- | --- |
| `M0_Heartbeat` | `portfolio` | `portfolio_brief` | `400-800` | voice brief、通知、轻量巡检 |
| `M1_Execute` | `focused_project` | `portfolio_brief + focused_project_anchor_pack + short delta_feed` | `1500-3000` | 单项目继续推进、普通问答 |
| `M2_PlanReview` | `focused_project` | `M1 + longterm outline + conflict_set + context_refs` | `3000-6000` | review、重构建议、战略纠偏 |
| `M3_DeepDive` | `focused_project` | `M2 + expanded delta + selected evidence_pack` | `6000-12000` | incident、persistent blocker、根因分析 |
| `M4_FullScan` | `portfolio` | `portfolio_brief + cross-project deltas + staged evidence expansion` | `12000-24000` | portfolio audit、repo-wide review |

固定策略：

- `M0` 默认不带 `evidence_pack`
- `M1` 默认不展开 raw evidence，只带 refs
- `M2` 起默认带 `longterm_outline`
- `M3/M4` 允许 `selected_chunks`
- `M4` 仍然禁止一次性无差别全文注入

## 8) Compression Contract

### 8.1 Compression Is Slot-Based, Not Prose-Only

压缩必须优先按字段槽位进行，而不是先写一大段 prose 再截断。

推荐优先级：

1. `anchor slots`
   - `goal`
   - `done_definition`
   - `constraints_hard_lines`
   - `approved_decisions`
   - `grant_clamp_killswitch_state`
2. `execution slots`
   - `current_state`
   - `next_step`
   - `top_blocker`
   - `active_plan_summary`
3. `delta slots`
   - `material_change_flags`
   - `top deltas`
4. `refs slots`
   - `context_refs`
5. `evidence slots`
   - `selected evidence`

### 8.2 Overflow Rules

溢出时的固定策略：

1. 先删低优先级项目，不删 anchor fields
2. 先缩短 `evidence_pack`，不先删 `done_definition`
3. 先把 `delta_items` 聚类，不先删 `approved_decisions`
4. 先把 `recent messages / traces` 摘成 structured digest，不直接 tail clip 顶层对象

### 8.3 Delta Compression

`delta_feed` 必须支持：

- `last_seen_cursor`
- `project_state_hash`
- `material_change_flags`
- `evidence_delta_hash`

如果状态 hash 不变，默认不重播完整背景，只回放：

- `no_material_change`
- `keep_current_strategy`
- `pending_items`

### 8.4 Dedupe Rules

以下内容不得在多个对象里全文重复：

- `goal`
- `done_definition`
- `approved_decisions`
- `latest_guidance`

允许保留：

- 在 `portfolio_brief` 中保留极短摘要
- 在 `focused_project_anchor_pack` 中保留完整结构化字段

### 8.5 Must-Never-Drop Fields

无论 budget 多紧，以下字段不能被压缩掉：

- 项目原始目标
- `done_definition / acceptance`
- 硬约束和禁止项
- 最新已批准 decision
- 当前 blocker
- 当前 active step
- 最新 guidance 与 ack 状态
- 当前 grant / clamp / kill-switch 状态

## 9) Safety And Governance

1. `Supervisor` 的长记忆默认不能变成跨项目原文注入。
   - cross-project 默认只允许 digest、delta、dependency refs
2. `remote_prompt_bundle` 不允许自动带 `evidence_pack` 原文。
3. 高风险动作仍然遵守 `freshness over size`。
   - 小而新的上下文优先于大而旧的上下文
4. voice / channel / mobile surface 默认只消费 projection，不直接消费 raw layers
5. `Longterm` 可见不等于 `Longterm fulltext` 默认可注入
6. 任何关键结论如无 refs，应视为降级模式，而不是正常模式

## 10) Review Input Ladder Alignment

本合同与 `Supervisor Review Protocol` 对齐如下：

- `L0/L1 anchor pack`
  - 由 `focused_project_anchor_pack` 承担
- `L2 progress pack`
  - 由 `delta_feed + active_plan_summary + blocker` 承担
- `L3 working set`
  - 由 `focused_project_anchor_pack` 内的热执行态与少量 recent digest 承担
- `L4 raw evidence`
  - 由 `evidence_pack` 按需展开承担

固定要求：

- `r1_pulse` 至少读 `portfolio_brief + focused_project_anchor_pack summary + delta_feed`
- `r2_strategic` 若要改路，必须读 `conflict_set` 与相关 `context_refs`
- `r3_rescue` 必须补足 `evidence_pack`

## 11) Recommended Implementation Touchpoints

### 11.1 Hub

- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
  - 从 `L0..L4 clipper` 升级为 `serving objects compiler`
  - `Longterm` 从 metadata 升级为真实 `longterm_outline`

### 11.2 XT Memory Route

- `x-terminal/Sources/Hub/XTMemoryUsePolicy.swift`
  - 继续保留 `use_mode` 和 profile gate
  - 为 Supervisor 增加 object-level packaging contract，而不只是 layer allowlist

### 11.3 Supervisor

- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 将当前 `focused_project_execution_brief` 提升为 `focused_project_anchor_pack`
  - 将当前 `projectDigests + action feed` 提升为 `portfolio_brief`
  - 将 retrieval block 拆成 `context_refs + evidence_pack`

### 11.4 Prompt Layer

- `x-terminal/Sources/Supervisor/SupervisorSystemPromptBuilder.swift`
  - 增加“先看 serving objects，再判断是否需要 drilldown”的固定提示

## 12) Acceptance Metrics

建议新增以下指标：

- `portfolio_awareness_stale_rate`
- `focused_anchor_missing_rate`
- `compression_loss_rate`
- `context_waste_ratio`
- `conflict_exposure_rate`
- `answer_grounding_rate`
- `profile_upgrade_rate`
- `delta_replay_avoidance_rate`

验收门禁建议：

- `SMS-G1`: serving object contract freeze
- `SMS-G2`: longterm first-class visibility
- `SMS-G3`: delta-first packaging correctness
- `SMS-G4`: conflict/provenance surfacing correctness
- `SMS-G5`: token/latency regression
- `SMS-G6`: cross-scope / remote export fail-closed

## 13) Final Judgment

`Supervisor` 需要的不是“更大的单段记忆”，而是：

- 无限留存的 truth plane
- 稳定锚点的 focused serving objects
- delta-first 的高频巡检路径
- evidence-on-demand 的低频深挖路径

后续实现应优先替代“单一静态摘要 + 字符串截断”的供给方式，而不是优先继续堆大 token。
