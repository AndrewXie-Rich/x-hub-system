# X-Hub Role-Aware Memory Serving And Tier Coupling v1

- version: v1.0
- updatedAt: 2026-04-09
- owner: Hub Memory / X-Terminal Supervisor / Project Runtime / Governance / Product / QA
- status: active
- scope: 冻结 `Supervisor` 与 `Project AI` 的角色化记忆装配、`A-Tier / S-Tier` 对记忆深度的 ceiling 关系、独立记忆拨盘、`configured / recommended / effective` 三值、每轮 effective resolver、doctor explainability 与 handoff 规则。
- related:
  - `X_MEMORY.md`
  - `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
  - `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
  - `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-compatibility-guardrails-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `docs/memory-new/xhub-a-tier-execution-graduation-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`

## 0) Why This Patch Exists

当前系统已经分别冻结了下面几件正确的事情：

- `Supervisor` 是单一身份，但内部是 `assistant plane + project plane + cross_link plane + continuity lane`
- `Project AI` 需要自己的 `Recent Project Dialogue + Project Context Depth`
- `A0..A4` 与 `S0..S4` 已经从单一 autonomy 语义里拆开
- `5-layer memory + serving plane + X-Constitution` 仍是内核，不应被替换

但还缺一块非常关键的中间合同：

`A-Tier / S-Tier 与实际记忆装配到底怎么耦合。`

如果这层不冻结，后续实现很容易走向两个坏方向之一：

1. 重新把高档位理解成“直接塞更多上下文”
2. 反过来把记忆滑块和治理档位绑死，失去弹性与 explainability

因此本补丁冻结的不是新的 memory 内核，而是：

`在保留 5-layer memory、serving plane、scope 边界与治理边界的前提下，明确 Supervisor 与 Project AI 各自怎么吃记忆、A/S 档位怎样提供 memory ceiling、每轮 effective memory assembly 怎样计算。`

## 1) One-Line Decision

冻结决策：

`Supervisor` 与 `Project AI` 必须继续使用不同的记忆装配模型；`A-Tier` 只为 `Project AI` 提供 project-memory ceiling，`S-Tier` 只为 `Supervisor` 提供 review-memory ceiling 与 intervention depth；每轮实际喂什么由 role-aware effective resolver 计算，而不是由 A/S 档位直接等于 prompt 大小。`

## 2) Goals And Non-Goals

目标

- 让 `Supervisor` 真正具备比 `Project AI` 更深、更全、更跨域的战略记忆视角。
- 让 `Project AI` 继续保持执行效率，不因“更懂全局”而被 prompt 污染。
- 让 `A-Tier / S-Tier` 与记忆深度形成稳定、可解释、可调节的耦合，而不是偶然实现。
- 让用户继续拥有独立的记忆拨盘，而不是只有一个“大自治就大上下文”的隐式开关。
- 让下一位 AI 协作者不需要回看长聊天记录，就能知道这套耦合该怎么实现。

非目标

- 不替换 `5-layer memory` 真相源。
- 不新增第二套 Supervisor 私有长期真相源。
- 不把 `A-Tier` 或 `S-Tier` 重新变成“唯一上下文大小滑块”。
- 不默认给 `Project AI` 完整 personal memory。
- 不允许因为大上下文模型出现就退回 `full dump`。

## 3) Frozen Decisions

### 3.1 Role First, Tier Second

先冻结角色差异，再谈档位：

- `Supervisor` 是战略治理体
- `Project AI` 是持续执行体

因此：

- `Supervisor` 默认看得更广、更深、更跨域
- `Project AI` 默认看得更窄、更当前、更执行导向

角色差异优先级高于档位差异。

### 3.2 `A-Tier` 只提供 `Project AI` 的 memory ceiling

冻结：

- `A-Tier` 决定 `Project AI` 最多能用到多厚的 project memory
- `A-Tier` 不直接等于这轮 `Project AI` 实际喂多少内容
- `A-Tier` 不替代 `Recent Project Dialogue`
- `A-Tier` 不替代 `Project Context Depth`

换句话说：

- `A-Tier` 是 ceiling
- `Project Context Depth` 是用户或系统给出的当前偏好
- `effective project assembly` 才是这轮实际结果

### 3.3 `S-Tier` 只提供 `Supervisor` 的 review-memory ceiling

冻结：

- `S-Tier` 决定 `Supervisor` 介入多深、纠偏多积极
- `S-Tier` 同时决定 `Supervisor` review 时可用的记忆 ceiling
- `S-Tier` 不直接等于这轮 Supervisor 实际喂满多少
- `S-Tier` 不替代 `Recent Raw Context`
- `S-Tier` 不替代 `Review Memory Depth`

换句话说：

- `S-Tier` 是监督强度和 review 深度 ceiling
- `Review Memory Depth` 是当前 review 偏好
- `effective supervisor review assembly` 才是这轮实际结果

### 3.4 Continuity Floors Continue To Be Hard Contracts

冻结：

- `Supervisor` recent raw dialogue floor 继续独立存在
- `Project AI` recent project dialogue floor 继续独立存在
- 这两条 floor 不能被任何 serving profile、A-tier、S-tier、budget governor 二次压掉

默认底线仍然是：

- `Supervisor`: 至少 `8 pairs`
- `Project AI`: 至少 `8 pairs`

### 3.5 Cross-Link Remains First-Class

冻结：

- `cross_link_plane` / `cross_link_scope` 继续是一等对象
- Supervisor 默认可以读 selected 或 full cross-link
- Project AI 只允许读 project-relevant selected cross-link hints

禁止回退到：

- 靠模型自己猜“谁在等哪个项目”
- 靠 prose 摘要隐式混入 personal/project 关联

### 3.6 `configured / recommended / effective` 三值必须进入记忆控制面

当前治理协议已经对 `S-Tier` 冻结了三值：

- `configured`
- `recommended`
- `effective`

本补丁把这条扩展到记忆控制面。

冻结：

每个 project 至少保留下面两组三值。

对于 `Supervisor`：

- `configured_supervisor_recent_raw_context_profile`
- `recommended_supervisor_recent_raw_context_profile`
- `effective_supervisor_recent_raw_context_profile`
- `configured_review_memory_depth`
- `recommended_review_memory_depth`
- `effective_review_memory_depth`

对于 `Project AI`：

- `configured_recent_project_dialogue_profile`
- `recommended_recent_project_dialogue_profile`
- `effective_recent_project_dialogue_profile`
- `configured_project_context_depth`
- `recommended_project_context_depth`
- `effective_project_context_depth`

解释：

- `configured`
  - 用户或项目 profile 显式设置
- `recommended`
  - 系统根据风险、任务类型、模型窗口、AI 强弱、治理档位给出的建议
- `effective`
  - 真正进入这轮 prompt assembly 的值

### 3.7 Effective Resolver Is The Real Runtime Authority

冻结一条总公式：

```text
effective_memory_assembly =
  role
  + turn_mode
  + trigger
  + configured_depth
  + recommended_depth
  + A/S tier ceiling
  + model_window
  + latency_budget
  + risk_level
  + runtime_readiness
  + current evidence availability
```

固定原则：

- `role` 先决定 topology
- `turn_mode` 再决定主域
- `trigger` 再决定是否临时升深
- `A/S ceiling` 最后做上限裁剪
- 不允许 “A4 == full dump”
- 不允许 “S4 == 每轮都 full scan”

### 3.8 No New Truth Source

本补丁再次冻结：

- `5-layer memory` 继续是唯一 truth source
- `serving plane` 继续只做 selection / packaging / expansion / explainability
- `XT local cache` 只能是交互缓存或 fallback，不是新的 canonical truth
- `Hub-first durable thread` 必须继续承担 continuity carrier

## 4) Control Surfaces

### 4.1 Supervisor Memory Controls

用户面和 runtime 至少区分两条轴：

1. `Recent Raw Context`
   - 解决“最近原始对话保留多少”
   - 推荐档位：
     - `Floor`
     - `Standard`
     - `Deep`
     - `Extended`
     - `Auto Max`

2. `Review Memory Depth`
   - 解决“做 review 时看多深、多厚、多证据”
   - 推荐用户面档位：
     - `Compact`
     - `Plan Review`
     - `Deep Dive`
     - `Full Scan`
     - `Auto`

内部映射建议：

- `Compact` -> `M1_Execute`
- `Plan Review` -> `M2_PlanReview`
- `Deep Dive` -> `M3_DeepDive`
- `Full Scan` -> `M4_FullScan`
- `Auto` -> runtime resolver 根据 trigger 与 budget 计算

### 4.2 Project AI Memory Controls

用户面和 runtime 至少区分两条轴：

1. `Recent Project Dialogue`
   - 解决“当前项目最近几轮对话 continuity”
   - 推荐档位：
     - `Floor`
     - `Standard`
     - `Deep`
     - `Extended`
     - `Auto Max`

2. `Project Context Depth`
   - 解决“当前项目背景喂多厚”
   - 推荐档位：
     - `Lean`
     - `Balanced`
     - `Deep`
     - `Full`
     - `Auto`

### 4.3 These Dials Must Stay Independent

冻结：

- `Recent Raw Context` 不等于 `Review Memory Depth`
- `Recent Project Dialogue` 不等于 `Project Context Depth`
- `A-Tier` 不替代 Project AI 的两条拨盘
- `S-Tier` 不替代 Supervisor 的两条拨盘

允许：

- 档位给拨盘一个默认值和最大 ceiling
- 但不允许偷偷绑死成单一档位

## 5) Role-Aware Serving Topology

### 5.1 Supervisor Assembly

Supervisor 默认继续走 serving objects，不直接消费“原始 L0..L4 文本拼接”。

默认对象：

- `recent raw dialogue window`
- `portfolio_brief`
- `focused_project_anchor_pack`
- `delta_feed`
- `conflict_set`
- `context_refs`
- `evidence_pack`
- `assistant_plane`
- `project_plane`
- `cross_link_plane`

默认装配顺序：

1. `recent raw dialogue window`
2. `focus pointers`
3. `dominant plane`
4. `supporting plane`
5. `cross_link_plane`
6. `portfolio_brief / delta_feed`
7. `conflict_set`
8. `context_refs`
9. `evidence_pack`

固定原则：

- 先 continuity
- 再当前主域
- 再 cross-link
- 最后再上更厚的 evidence

### 5.2 Project AI Assembly

Project AI 默认继续走“project execution first”装配链。

默认对象：

- `recent_project_dialogue_window`
- `focused_project_anchor_pack`
- `active workflow / active plan / pending steps`
- `latest execution evidence`
- `latest review note`
- `latest guidance / pending ack`
- `selected longterm outline`
- `selected evidence refs`
- `selected cross_link_hints`

默认装配顺序：

1. `recent_project_dialogue_window`
2. `focused_project_anchor_pack`
3. `active workflow / pending steps`
4. `latest execution evidence`
5. `latest review note / guidance / pending ack`
6. `selected decision lineage / longterm outline`
7. `selected evidence refs`
8. `selected cross_link_hints`

固定原则：

- 先 continuity
- 再 anchor
- 再 execution truth
- 再 guidance
- 最后才是更厚背景

### 5.3 Personal Memory Boundary For Project AI Stays Tight

默认允许透传到 coder 的 only-if-relevant hints：

- `the user wants a minimal shippable version first`
- `the user prefers concise status updates`
- `someone is waiting on this deliverable`
- `today's priority is to unblock this project first`

默认不允许：

- 完整 `assistant_plane`
- 完整 follow-up queue
- personal review state
- relationship history
- 与项目无关的 personal memory

## 6) A-Tier To Project Memory Coupling

### 6.1 Frozen Rule

冻结：

`A-Tier` 只为 `Project AI` 提供 project memory ceiling，不直接替代 `Project Context Depth`。`

### 6.2 Recommended Coupling Table

| A-Tier | Project Memory Ceiling | Recommended Default `Project Context Depth` | Recommended Temporary Escalation Ceiling | Notes |
| --- | --- | --- | --- | --- |
| `A0 Observe` | `m2_plan_review` | `Lean` | `Balanced` | 以理解项目为主，不建议自动升到厚 evidence |
| `A1 Plan` | `m2_plan_review` | `Balanced` | `Deep` | 规划和工单生成可临时升深，但不应默认 Full |
| `A2 Repo Auto` | `m3_deep_dive` | `Balanced` | `Deep` 或受预算门控的 `Full` | blocker / repeated failure / verify gap 时允许临时升深 |
| `A3 Deliver Auto` | `m3_deep_dive` | `Deep` | `Full` | pre-done / delivery close / drift 时常需更厚上下文 |
| `A4 Agent` | `m4_full_scan` | `Deep` | `Full` 或 `Auto` | 多执行面、高风险动作、跨 surface 恢复时允许更全背景 |

### 6.3 Trigger-Based Elevation For Project AI

Project AI 的上下文升深不应由 A-tier 单独触发，而应由事件触发。

推荐触发：

- `failure_streak`
- `persistent_blocker`
- `verification_gap`
- `plan_drift`
- `pre_done_summary`
- `cross_surface_handoff`
- `resume_from_checkpoint`

推荐规则：

- 正常执行不轻易从 `Balanced` 跳到 `Full`
- 只有在 blocker、verify gap、resume、pre-done 等高价值时段，才临时升深
- 升深结束后允许回落，避免 coder 长时间背重 prompt

## 7) S-Tier To Supervisor Memory Coupling

### 7.1 Frozen Rule

冻结：

`S-Tier` 只为 `Supervisor` 提供 review-memory ceiling 与 intervention depth，不直接替代 `Review Memory Depth`。`

### 7.2 Recommended Coupling Table

| S-Tier | Review Memory Ceiling | Recommended Default Review Profile | Typical Escalation Profiles | Notes |
| --- | --- | --- | --- | --- |
| `S0 Silent Audit` | `m2_plan_review` | `M0_Heartbeat` 或轻量 `M1_Execute` | `M2_PlanReview` 仅 incident / manual request | 以观察和审计为主，不主动 deep-dive |
| `S1 Milestone Review` | `m2_plan_review` | `M1_Execute` | `M2_PlanReview` 于 milestone / pre-done | 关键节点看，不适合高自治项目长期主档 |
| `S2 Periodic Review` | `m3_deep_dive` | `M1_Execute` 或 `M2_PlanReview` | `M3_DeepDive` 于 blocker / pre-done | 正常巡检档 |
| `S3 Strategic Coach` | `m4_full_scan` | `M2_PlanReview` | `M3_DeepDive` 于 drift / blocker，`M4_FullScan` 于 portfolio reprioritize / rescue | 推荐主档 |
| `S4 Tight Supervision` | `m4_full_scan` | `M3_DeepDive` | `M4_FullScan` 于 pre-high-risk / rescue / critical pre-done | 高风险、关键交付、强监督档 |

### 7.3 Trigger-Based Elevation For Supervisor

推荐升深触发：

- `periodic_pulse`
- `blocker_detected`
- `plan_drift`
- `pre_high_risk_action`
- `pre_done_summary`
- `grant_resolution`
- `skill_callback`
- `manual_request`
- `portfolio_reprioritize`

推荐映射：

- `r1_pulse`:
  - 至少读 `portfolio_brief + focused_project_anchor_pack summary + delta_feed`
- `r2_strategic`:
  - 必须补 `conflict_set + context_refs`
- `r3_rescue`:
  - 必须补 `selected evidence_pack`

### 7.4 S-Tier Does Not Mean Permanent Full Scan

冻结：

- `S4` 不等于“每轮都 full scan”
- `S3` 不等于“每次 review 都拿 portfolio 全量”
- `S-Tier` 决定的是可用 ceiling 与默认干预强度
- 实际是否扩到 `M3/M4`，仍取决于 trigger、budget、risk、model window

## 8) Effective Resolver Contracts

### 8.1 `effective_project_memory_assembly`

建议冻结一个机读结果对象：

- `role = project_ai`
- `project_id`
- `trigger`
- `configured_recent_project_dialogue_profile`
- `recommended_recent_project_dialogue_profile`
- `effective_recent_project_dialogue_profile`
- `configured_project_context_depth`
- `recommended_project_context_depth`
- `effective_project_context_depth`
- `a_tier_memory_ceiling`
- `ceiling_hit`
- `selected_slots`
- `selected_cross_link_hints`
- `excluded_personal_memory_reason`
- `budget_summary`
- `audit_ref`

推荐计算式：

```text
effective_project_context_depth =
  clamp(
    planner(
      configured_project_context_depth,
      recommended_project_context_depth,
      trigger,
      blocker_state,
      verification_state,
      resume_state,
      model_window,
      latency_budget
    ),
    floor = recent_project_dialogue_floor,
    ceiling = a_tier_memory_ceiling
  )
```

### 8.2 `effective_supervisor_memory_assembly`

建议冻结一个机读结果对象：

- `role = supervisor`
- `project_id?`
- `dominant_mode`
- `trigger`
- `configured_supervisor_recent_raw_context_profile`
- `recommended_supervisor_recent_raw_context_profile`
- `effective_supervisor_recent_raw_context_profile`
- `configured_review_memory_depth`
- `recommended_review_memory_depth`
- `effective_review_memory_depth`
- `s_tier_review_memory_ceiling`
- `ceiling_hit`
- `selected_planes`
- `selected_serving_objects`
- `selected_cross_link_level`
- `evidence_pack_level`
- `budget_summary`
- `audit_ref`

推荐计算式：

```text
effective_review_memory_depth =
  clamp(
    planner(
      dominant_mode,
      trigger,
      configured_review_memory_depth,
      recommended_review_memory_depth,
      current_s_tier,
      project_risk_level,
      project_ai_strength_band,
      model_window,
      latency_budget
    ),
    floor = recent_raw_context_floor,
    ceiling = s_tier_review_memory_ceiling
  )
```

### 8.3 `dominant_mode` Still Matters

Supervisor effective resolver 继续必须先算 `dominant_mode`：

- `personal_first`
- `project_first`
- `hybrid`
- `portfolio_review`

固定规则：

- `dominant_mode` 决定主域
- `S-Tier` 决定这轮 review 能看多深
- 两者都参与 effective assembly
- 两者都不等于 memory model chooser

## 9) Recommended Defaults

### 9.1 Supervisor Defaults

- `Recent Raw Context`
  - 默认 `Standard`
  - hard floor `Floor`
- `Review Memory Depth`
  - 默认 `Auto`
  - 推荐由 `S-Tier + trigger` 共同驱动

推荐解释：

- `S0/S1` 默认不应常驻 deep review
- `S2` 从正常巡检开始
- `S3` 默认进入战略 review
- `S4` 只在高风险或关键交付下常驻更深视图

### 9.2 Project AI Defaults

- `Recent Project Dialogue`
  - 默认 `Standard`
  - hard floor `Floor`
- `Project Context Depth`
  - 默认 `Auto`
  - 推荐由 `A-Tier + trigger + evidence availability` 共同驱动

推荐解释：

- `A0/A1` 不应默认喂太厚
- `A2/A3` 应优先 execution evidence，而不是泛泛 longterm
- `A4` 可以允许更厚，但仍应 staged expansion，不做 full dump

## 10) Explainability And Doctor

### 10.1 Must Expose For Supervisor

Doctor 或 diagnostics 至少要能回答：

- 这轮 `dominant_mode` 是什么
- 这轮 `S-Tier` 给的 review ceiling 是多少
- 这轮 `configured / recommended / effective review depth` 分别是什么
- 这轮选了多少 `recent raw pairs`
- `assistant_plane / project_plane / cross_link_plane` 分别进了多少
- 有没有补 `conflict_set`
- 有没有补 `evidence_pack`
- 哪些块被排除，为什么

### 10.2 Must Expose For Project AI

Doctor 或 diagnostics 至少要能回答：

- 这轮 `A-Tier` 给的 project memory ceiling 是多少
- 这轮 `configured / recommended / effective project context depth` 分别是什么
- 这轮选了多少 `recent project dialogue pairs`
- `workflow_present / execution_evidence_present / review_guidance_present`
- 哪些 cross-link hints 被选中
- 哪些 personal memory 被排除，为什么
- 是否命中了 `ceiling_hit` 或 `floor_only_fallback`

### 10.3 Suggested Machine-Readable Fields

建议至少新增或稳定这些字段：

- `role_aware_memory_mode`
- `dominant_mode`
- `configured_depth`
- `recommended_depth`
- `effective_depth`
- `ceiling_from_tier`
- `ceiling_hit`
- `recent_dialogue_pairs_selected`
- `selected_planes`
- `selected_serving_objects`
- `selected_cross_link_level`
- `excluded_blocks`
- `exclusion_reasons`
- `budget_summary`

## 11) Forbidden Regressions

明确禁止：

1. 把 `A-Tier` 直接绑定成 `Project Context Depth`
2. 把 `S-Tier` 直接绑定成 `Review Memory Depth`
3. 让 `Project AI` 默认吃完整 `assistant_plane`
4. 用 summary 代替 recent raw continuity
5. 用 full dump 代替 role-aware assembly
6. 让 XT 本地缓存重新成为唯一 continuity truth
7. 为了“更懂用户”而放松 personal/project scope 隔离

## 12) Implementation Guidance

### 12.1 Config Surfaces To Add Or Stabilize

建议在 project / supervisor runtime config 中稳定以下对象：

1. `xhub.project_memory_policy.v1`
   - `configured_recent_project_dialogue_profile`
   - `configured_project_context_depth`
   - `recommended_recent_project_dialogue_profile`
   - `recommended_project_context_depth`
   - `effective_recent_project_dialogue_profile`
   - `effective_project_context_depth`
   - `a_tier_memory_ceiling`
   - `audit_ref`

2. `xhub.supervisor_memory_policy.v1`
   - `configured_supervisor_recent_raw_context_profile`
   - `configured_review_memory_depth`
   - `recommended_supervisor_recent_raw_context_profile`
   - `recommended_review_memory_depth`
   - `effective_supervisor_recent_raw_context_profile`
   - `effective_review_memory_depth`
   - `s_tier_review_memory_ceiling`
   - `audit_ref`

3. `xhub.memory_assembly_resolution.v1`
   - `role`
   - `dominant_mode`
   - `trigger`
   - `configured_*`
   - `recommended_*`
   - `effective_*`
   - `ceiling_*`
   - `selected_slots`
   - `selected_planes`
   - `budget_summary`
   - `audit_ref`

### 12.2 Runtime Sequence

推荐实现顺序：

1. 先接 `configured / recommended / effective` 三值
2. 再实现 role-aware effective resolver
3. 再把 doctor / diagnostics 暴露出来
4. 再补 UI 控件和 explainability
5. 最后再做 trigger-based auto-escalation 精修

### 12.3 Read Order For The Next AI

如果下一位 AI 要继续这条线，固定按这个顺序进入：

1. 本文件
2. `docs/memory-new/xhub-supervisor-memory-compatibility-guardrails-v1.md`
3. `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
4. `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
5. `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
6. `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
7. `docs/memory-new/xhub-a-tier-execution-graduation-work-orders-v1.md`
8. `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`
9. `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`

### 12.4 Suggested Next Implementation Slices

推荐下一个 AI 直接从这几件事开始：

1. 把 `configured / recommended / effective` 三值接入 `Supervisor` 与 `Project AI` 的 memory policy resolver
2. 把 `A-tier memory ceiling` 和 `S-tier review ceiling` 机器可读化，并接入 doctor
3. 给 `Supervisor` 新增独立 `Review Memory Depth` explainability
4. 给 `Project AI` 新增独立 `Project Context Depth` explainability
5. 在 runtime diagnostics 里暴露 `selected_planes / selected_serving_objects / excluded_blocks`

## 13) Final Summary

本补丁冻结的核心不是“让高档位吃更多上下文”，而是：

1. `Supervisor` 和 `Project AI` 必须继续吃不同形态的记忆
2. `A-Tier` 只提供 project-memory ceiling
3. `S-Tier` 只提供 review-memory ceiling
4. recent continuity 继续是硬底线
5. 真正这轮喂什么，由 role-aware effective resolver 计算

这样系统才能同时保住：

- `Supervisor` 的战略纠偏能力
- `Project AI` 的执行效率
- `5-layer memory` 的治理优势
- `A0..A4 + S0..S4 + independent heartbeat/review` 的架构清晰度
