# XT-W3-36 Project Autonomy Tier + Supervisor Intervention Implementation Pack v1

- owner: XT-L2（Primary）/ Supervisor / Hub-L5 / Security / QA / Product
- status: planned
- last_updated: 2026-03-13
- purpose: 把当前混合在单一 `autonomy` 语义里的“执行权限、supervisor 介入强度、progress heartbeat”三件事拆开，正式落成 `A0..A4` 执行档位、`S0..S4` 介入档位和独立 review/heartbeat 调度，使 project coder 与 supervisor 都能在更清晰、更可审计、更可迁移的治理框架下推进项目。
- depends_on:
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/schema/xhub_project_autonomy_and_supervisor_review_contract.v1.json`
  - `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-33-supervisor-decision-kernel-routing-and-memory-governance-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-35-supervisor-memory-retrieval-progressive-disclosure-implementation-pack-v1.md`
  - `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## 0) 为什么要单开这份包

当前系统里已经同时存在三类看起来相近、但本质不同的控制面：

- project 能不能自主做事
- supervisor 该不该主动 review / brainstorm / 纠偏
- heartbeat 多久回报一次进度

问题在于，这三件事目前没有被显式拆开：

1. `manual/guided/trusted_openclaw_mode` 更像 execution surface preset，不足以表达“执行能力强，但 supervisor 仍需周期 review”。
2. heartbeat 只能说明“多久看一次进度”，不能说明“多久做一次深入 review”或“什么时候插入方向建议”。
3. `AutonomyLevel(1..5)` 与 `AXProjectAutonomyMode` 同时存在，但二者都不是正式 project governance contract。
4. Supervisor 已经有 portfolio、project capsule、memory drilldown 和 job/plan action 能力，但还缺一套正式的“何时介入、如何介入、何时要求 ack”的运行合同。
5. A4 / OpenClaw 类项目如果没有单独的介入强度定义，容易在两个极端之间摇摆：
   - 要么 supervisor 过度介入，反而拖慢执行
   - 要么 supervisor 基本失联，项目跑偏后很晚才发现

所以 `XT-W3-36` 不是再发明一个新 slider，而是把系统中已经存在、但仍混在一起的控制面拆成三根独立拨盘，并冻结为可执行主链。

## 1) 北极星模型

### 1.1 三个独立控制面

每个 project 以后都按三组设置解析：

1. `Execution Tier`
   - 决定 project AI 能做什么。
   - 只讨论执行权限和执行面。

2. `Supervisor Intervention Tier`
   - 决定 supervisor 多频繁 review、多主动 brainstorm、多深地介入方向。
   - 只讨论 review / guidance / replan / interrupt 的强度。

3. `Progress Heartbeat + Review Schedule`
   - 决定多久汇报进度、多久做 pulse review、多久做 strategic brainstorm review。
   - 是时序调度，不是权限。

冻结规则：

- `A-tier` 只管 execution rights，不再混入 supervisor 行为。
- `S-tier` 只管 intervention strength，不再暗含 device/repo 权限。
- `heartbeat` 与 `review` 保持独立，不再用“心跳时间”替代 review policy。

### 1.2 对用户和运行时的呈现

用户可见层：

- project 顶部显示一个 `A?` 和一个 `S?`
- 点击后可看：
  - 当前 capability bundle
  - 当前 memory ceiling
  - 当前 heartbeat / review cadence
  - 当前 Hub clamp / TTL / kill-switch 状态

运行时真相源：

- 以 machine-readable `Project Governance Bundle` 为准
- UI 只是一层编辑器和解释层

### 1.3 和记忆系统的关系

本包同时冻结一条很关键的解释链：

- `A-tier` 决定 project coder 的默认背景信息 ceiling
- `S-tier` 决定 supervisor review 时可使用的默认 review memory ceiling
- `XT-W3-35` 的渐进检索能力为这两个 ceiling 提供“按需展开”通道

也就是说：

- 高档位 project coder 确实可以拿到更完整的 project 背景
- 高介入 supervisor 也可以在 review 时拿到更完整的项目上下文
- 但两者都仍受 `memory profile`、scope、audit 和 fail-closed 约束

## 2) 固定决策

### 2.1 `A0..A4` 只表示执行权限

冻结：

- `A0 Observe`
- `A1 Plan`
- `A2 Repo Auto`
- `A3 Deliver Auto`
- `A4 OpenClaw`

`A-tier` 不能再直接表达：

- review 频率
- review 是否 brainstorm
- supervisor 是否旁路纠偏

这些语义全部移到 `S-tier`。

### 2.2 `S0..S4` 只表示 supervisor 介入强度

冻结：

- `S0 Silent Audit`
- `S1 Milestone Review`
- `S2 Periodic Review`
- `S3 Strategic Coach`
- `S4 Tight Supervision`

`S-tier` 不能再直接放权给 repo / device / connector / extension。

### 2.3 Heartbeat 单独保留

冻结：

- `progress_heartbeat_sec`
- `review_pulse_sec`
- `brainstorm_review_sec`
- `event_driven_review_enabled`
- `event_review_triggers`

### 2.4 A4 仍然有 supervisor，只是 supervisor 换到旁路治理位

`A4` 的目标不是去掉 supervisor，而是把 supervisor 从“每一步审批者”改成：

- 旁路观察者
- 战略复盘者
- 方向纠偏者
- 高风险动作前的仲裁者

### 2.5 Guidance 必须结构化

supervisor 的 review 结果不能只靠自然语言漂在聊天里。

必须落成：

- `Review Note`
- `Guidance Queue Item`
- `Ack Status`

并且继续遵守协议里已冻结的枚举：

- `target_role`: `coder | supervisor | project_chat`
- `delivery_mode`: `context_append | priority_insert | replan_request | stop_signal`
- `ack_status`: `pending | accepted | deferred | rejected`

### 2.6 默认 soft intervention 走 safe point

除以下情况外，不允许立即打断：

- `kill_switch`
- `policy_denied`
- `pre_high_risk_action`
- `wrong_direction` 且高置信

其它建议默认走：

- `next_tool_boundary`
- `next_step_boundary`
- `checkpoint_boundary`

## 3) 档位冻结

### 3.1 Execution Tier

| Tier | 名称 | 默认 project memory ceiling | 核心能力 | 不允许 |
| --- | --- | --- | --- | --- |
| `a0_observe` | Observe | `m2_plan_review` | 读记忆、读项目状态、给建议 | 创建 job、改 repo、跑 side effect |
| `a1_plan` | Plan | `m2_plan_review` | 自动建 `job/plan`、写 project memory、产出执行方案 | repo side effect、device side effect |
| `a2_repo_auto` | Repo Auto | `m3_deep_dive` | project root 内改文件、跑 build/test、做 patch、更新计划 | device/browser/connector 高风险执行 |
| `a3_deliver_auto` | Deliver Auto | `m3_deep_dive` | 多 step 连续推进到交付完成、自动收口、汇总通知 | 未授权 device-level side effect |
| `a4_openclaw` | OpenClaw | `m4_full_scan` | 在受治理前提下使用 browser/device/connector/extension 完整执行面 | 绕过 trusted automation、Hub grant、kill-switch |

### 3.2 Supervisor Intervention Tier

| Tier | 名称 | 默认 review memory ceiling | 触发语义 | 默认注入动作 |
| --- | --- | --- | --- | --- |
| `s0_silent_audit` | Silent Audit | `m2_plan_review` | 只看、不主动插入 guidance；仅保留 incident / kill-switch 审计 | `observe_only` |
| `s1_milestone_review` | Milestone Review | `m2_plan_review` | milestone / pre-done / manual request review | `suggest_next_safe_point` |
| `s2_periodic_review` | Periodic Review | `m3_deep_dive` | 周期 pulse + blocker / pre-done review | `suggest_next_safe_point` |
| `s3_strategic_coach` | Strategic Coach | `m4_full_scan` | 周期 pulse + strategic brainstorm + drift / blocker / rescue review | `replan_next_safe_point` |
| `s4_tight_supervision` | Tight Supervision | `m4_full_scan` | 高频 review + 高风险前 gate + 必要时 pre-step hold | `replan_next_safe_point` 或 `stop_immediately` |

### 3.3 Heartbeat / Review Schedule

冻结为独立调度对象，不再塞进 `A-tier` 或 `S-tier`：

- `progress_heartbeat_sec`
- `review_pulse_sec`
- `brainstorm_review_sec`
- `event_driven_review_enabled`
- `event_review_triggers`
- `interrupt_rate_limit_per_hour`

## 4) 组合规则

### 4.1 推荐默认组合

| Execution | Supervisor | 说明 |
| --- | --- | --- |
| `A0` | `S0` | 观察为主，不自动推进 |
| `A1` | `S1` | 自动梳理计划，但不直接动 repo |
| `A2` | `S2` | repo 内自主推进，supervisor 周期 review |
| `A3` | `S3` | 持续推进到交付，supervisor 做战略纠偏 |
| `A4` | `S3` | 高自治执行面 + 旁路战略 review，是推荐主档 |

### 4.2 合法但更严格的组合

- `A1 + S2`
- `A2 + S3`
- `A3 + S4`
- `A4 + S4`

这些组合用于：

- 高风险仓库
- 复杂长期项目
- 明确希望 supervisor 更强势跟进的场景

### 4.3 无效组合

以下组合必须 fail-closed：

- `A2 + S0`
- `A3 + S0`
- `A4 + S0`
- `A4 + S1`

原因：

- repo 及以上自主执行不能在“几乎无 review”下持续运行
- device-level / OpenClaw 面不能只靠 milestone review

### 4.4 警告组合

以下组合允许保存，但 UI 与运行时都要给出风险提示：

- `A2 + S1`
- `A3 + S1`
- `A3 + S2`
- `A4 + S2`

这些组合不是错误，但意味着：

- supervisor 介入强度低于推荐值
- drift / rescue 发现窗口会变大

## 5) 机读契约冻结

### 5.1 `xt.project_execution_tier.v1`

```json
{
  "schema_version": "xt.project_execution_tier.v1",
  "project_id": "proj_alpha",
  "tier": "a3_deliver_auto",
  "project_memory_ceiling": "m3_deep_dive",
  "surface_preset": "guided",
  "allowed_capabilities": [
    "job.create",
    "plan.upsert",
    "repo.read",
    "repo.write",
    "repo.build",
    "repo.test"
  ],
  "ttl_sec": 3600,
  "audit_ref": "audit_exec_001"
}
```

### 5.2 `xt.supervisor_intervention_tier.v1`

```json
{
  "schema_version": "xt.supervisor_intervention_tier.v1",
  "project_id": "proj_alpha",
  "tier": "s3_strategic_coach",
  "review_memory_ceiling": "m4_full_scan",
  "default_intervention_mode": "replan_next_safe_point",
  "safe_point_policy": "next_step_boundary",
  "coder_ack_required": true,
  "audit_ref": "audit_sup_001"
}
```

### 5.3 `xt.project_governance_combo.v1`

```json
{
  "schema_version": "xt.project_governance_combo.v1",
  "project_id": "proj_alpha",
  "execution_tier": "a4_openclaw",
  "supervisor_intervention_tier": "s3_strategic_coach",
  "surface_preset": "trusted_openclaw_mode",
  "progress_heartbeat_sec": 600,
  "review_pulse_sec": 1200,
  "brainstorm_review_sec": 2400,
  "event_driven_review_enabled": true,
  "event_review_triggers": [
    "blocker_detected",
    "plan_drift",
    "pre_high_risk_action",
    "pre_done_summary"
  ],
  "clamp_state": "none",
  "compat_source": "explicit_dual_dial",
  "audit_ref": "audit_combo_001"
}
```

### 5.4 `xt.supervisor_review_note.v1`

```json
{
  "schema_version": "xt.supervisor_review_note.v1",
  "review_id": "review_001",
  "project_id": "proj_alpha",
  "trigger": "plan_drift",
  "review_level": "r2_strategic",
  "verdict": "replan_recommended",
  "confidence": 0.89,
  "recommended_actions": [
    "shrink active scope",
    "switch to safer integration order"
  ],
  "intervention_mode": "replan_next_safe_point",
  "target_role": "coder",
  "delivery_mode": "replan_request",
  "ack_required": true,
  "audit_ref": "audit_review_001"
}
```

### 5.5 `xt.supervisor_guidance_queue_item.v1`

```json
{
  "schema_version": "xt.supervisor_guidance_queue_item.v1",
  "guidance_id": "guide_001",
  "project_id": "proj_alpha",
  "review_id": "review_001",
  "target_role": "coder",
  "delivery_mode": "priority_insert",
  "safe_point_policy": "next_step_boundary",
  "intervention_mode": "replan_next_safe_point",
  "ack_status": "pending",
  "expires_at_ms": 1760000000000,
  "audit_ref": "audit_guide_001"
}
```

## 6) 代码落点

### 6.1 Project Config / Compatibility

- `x-terminal/Sources/Project/AXProjectConfig.swift`
- `x-terminal/Sources/Project/AXProjectAutonomyPolicy.swift`
- `x-terminal/Sources/Project/ProjectModel.swift`
- `x-terminal/Sources/Project/AXProjectRegistry.swift`
- 新增：
  - `x-terminal/Sources/Project/AXProjectExecutionTier.swift`
  - `x-terminal/Sources/Project/AXProjectSupervisorInterventionTier.swift`
  - `x-terminal/Sources/Project/AXProjectGovernanceBundle.swift`
  - `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`

### 6.2 UI

- `x-terminal/Sources/UI/ProjectSettingsView.swift`
- `x-terminal/Sources/UI/Projects/CreateProjectSheet.swift`
- `x-terminal/Sources/UI/Projects/ProjectDetailView.swift`
- `x-terminal/Sources/UI/GlobalHomeView.swift`
- 需要时新增：
  - `x-terminal/Sources/UI/ProjectGovernanceBadge.swift`
  - `x-terminal/Sources/UI/ProjectGovernanceInspector.swift`

### 6.3 Supervisor Runtime / Review Loop

- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- `x-terminal/Sources/Supervisor/XTAutomationRuntimePolicy.swift`
- `x-terminal/Sources/Supervisor/XTAutomationRunCoordinator.swift`
- `x-terminal/Sources/Supervisor/SupervisorPortfolioSnapshot.swift`
- 新增：
  - `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
  - `x-terminal/Sources/Supervisor/SupervisorReviewScheduleStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorReviewNoteStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorGuidanceInjectionStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorSafePointCoordinator.swift`

### 6.4 Tool / Capability Gate

- `x-terminal/Sources/Tools/XTToolRuntimePolicy.swift`
- `x-terminal/Sources/Tools/ToolExecutor.swift`
- `x-terminal/Sources/Hub/HubIPCClient.swift`

## 7) 迁移策略

### 7.1 schema 升级

- `AXProjectConfig.currentSchemaVersion` 升到下一版
- 新增字段：
  - `executionTier`
  - `supervisorInterventionTier`
  - `progressHeartbeatSeconds`
  - `reviewPulseSeconds`
  - `brainstormReviewSeconds`
  - `eventDrivenReviewEnabled`
  - `eventReviewTriggers`

### 7.2 旧字段定位

旧字段继续保留，但只作为 compatibility input：

- `AXProjectAutonomyMode`
  - 只表示 `surface preset`
- `AutonomyLevel`
  - 只表示 legacy execution intent

二者都不再是最终运行时真相源。

### 7.3 迁移优先级

第一次解析 project governance 时按以下优先级：

1. 若已存在新双拨盘字段，直接使用
2. 否则若存在 `AutonomyLevel`，按 `1..5 -> A0..A4` 映射
3. 否则按 `AXProjectAutonomyMode` 保守推断：
   - `manual -> A0`
   - `guided -> A1`
   - `trusted_openclaw_mode -> A4`
4. 若仍无法确定，则默认 `A0 + S0`
5. `S-tier` 默认取推荐配对值

### 7.4 旧 surface preset 的兼容

迁移后仍保留：

- `manual`
- `guided`
- `trusted_openclaw_mode`

但它们只负责决定：

- browser / device / connector / extension surface preset
- Hub clamp 对这些 surface 的压制方式

真正是否执行，继续由：

- `executionTier`
- `supervisorInterventionTier`
- trusted automation readiness
- tool runtime policy
- Hub grant / clamp / kill-switch

共同决策。

### 7.5 clamp 与 kill-switch 对齐

冻结：

- `kill_switch` 总是最高优先级
- `clamp_manual` 与 `clamp_guided` 继续压制 surface preset
- 当 `effective governance` 低于最小安全组合时，必须：
  - fail-closed
  - 或把 `effective supervisor tier` 自动抬到最小值

本包推荐第一版实现为：

- UI 阻止保存无效组合
- 运行时对旧项目或远端脏配置继续 fail-closed

## 8) 可执行粒度工单

### 8.1 `XT-W3-36-A` Dual-Dial Contract + Config Schema

- priority: `P0`
- 目标：把双拨盘治理写成正式的 config / contract / resolver，而不是散落在 UI 和 prompt 文本里。
- 推荐落点：
  - `x-terminal/Sources/Project/AXProjectConfig.swift`
  - `x-terminal/Sources/Project/AXProjectAutonomyPolicy.swift`
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/AppModel+MultiProject.swift`
  - 新增 `AXProjectExecutionTier.swift`
  - 新增 `AXProjectSupervisorInterventionTier.swift`
  - 新增 `AXProjectGovernanceResolver.swift`
- 实施步骤：
  1. 冻结 `A-tier`、`S-tier`、schedule 字段和无效组合规则。
  2. 新增 `effective governance resolution`：
     - configured combo
     - legacy compat source
     - hub clamp
     - ttl
     - trusted automation readiness
  3. 输出统一的 `AXProjectResolvedGovernanceState`。
  4. 为 resolver 补 machine-readable debug snapshot。
- DoD：
  - 不再需要在 UI、tool gate、supervisor runtime 三处各自重复推断 governance。
  - 旧项目可无 crash 地被解析成保守双拨盘状态。

### 8.2 `XT-W3-36-B` Project Top Bar + Settings UI

- priority: `P0`
- 目标：把 project 顶部与设置页升级为双拨盘治理面。
- 推荐落点：
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Sources/UI/Projects/CreateProjectSheet.swift`
  - `x-terminal/Sources/UI/Projects/ProjectDetailView.swift`
  - `x-terminal/Sources/UI/GlobalHomeView.swift`
- 实施步骤：
  1. 顶部显示 `A? / S? / clamp / ttl / heartbeat / review` 摘要。
  2. 设置页新增：
     - Execution Tier picker
     - Supervisor Intervention picker
     - Progress Heartbeat 输入
     - Review Pulse 输入
     - Brainstorm Review 输入
  3. `ProjectDetailView` 与 project header 共用同一份治理 badge / inspector，不再继续展示旧 `AutonomyLevel` 星级语义。
  4. 对无效组合给出即时错误说明。
  5. 对警告组合给出风险说明。
  6. 展示“当前 effective 值”与“被 clamp 后的值”。
- DoD：
  - 用户能一眼区分“权限档位”和“supervisor 盯得多紧”。
  - 不再把 review 配置误解成 heartbeat 配置。

### 8.3 `XT-W3-36-C` Execution Capability Resolver

- priority: `P0`
- 目标：让 repo/device/browser/connector/extension 等执行面只从统一 governance resolver 取最终 verdict。
- 推荐落点：
  - `x-terminal/Sources/Project/AXProjectAutonomyPolicy.swift`
  - `x-terminal/Sources/Tools/XTToolRuntimePolicy.swift`
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
- 实施步骤：
  1. 把 `A-tier` 映射到 capability bundle。
  2. 把旧 `surface preset` 保留为 surface clamp，而不是主权来源。
  3. 接入 trusted automation / Hub grant / clamp / TTL 复核。
  4. 为 deny path 统一 reason code。
- DoD：
  - `A2/A3/A4` 的区别能在运行时真实体现，而不是只停留在 UI 文案。
  - device-level surface 继续只有 `A4 + trusted automation + grant` 才会放行。

### 8.4 `XT-W3-36-D` Supervisor Intervention Resolver + Review Scheduler

- priority: `P0`
- 目标：让 supervisor 的 review 与 brainstorm 调度从“零散 heartbeat”升级为正式 intervention engine。
- 推荐落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRunCoordinator.swift`
  - 新增 `SupervisorReviewPolicyEngine.swift`
  - 新增 `SupervisorReviewScheduleStore.swift`
- 实施步骤：
  1. 把 `S-tier` 映射到：
     - review depth
     - review triggers
     - default intervention mode
     - ack requirement
  2. 引入三类调度：
     - progress heartbeat
     - pulse review
     - brainstorm review
  3. 事件触发 review 至少覆盖：
     - `blocker_detected`
     - `plan_drift`
     - `failure_streak`
     - `pre_high_risk_action`
     - `pre_done_summary`
  4. 为每次 review 组装统一 `review input ladder`：
     - `L0/L1 anchor pack`
     - `L2 progress pack`
     - `L3 working set`
     - 按需展开 `L4 raw evidence`
  5. 为每次 review 生成结构化 `Review Note`。
  6. `r2_strategic / r3_rescue` 默认应支持 option scan，但保留 supervisor 自由度：
     - 默认比较 `keep_current_path` 与 `proposed_better_path`
     - 必要时再展开 `higher_cost_higher_upside_path`
     - 若证据非常明确支持继续当前路径，可只做轻量 option sanity check
  7. 若建议改 plan，必须同时写明：
     - 更好在哪里
     - 切换成本
     - 风险
     - 对原始目标/约束的影响
  8. policy engine 只校验：
     - 是否完成 re-anchor
     - 是否引用足够证据
     - 是否输出可执行 guidance
     不校验固定推理顺序或固定文风
- DoD：
  - `继续` 这种人工 nudging 不再是 supervisor 复盘的唯一入口。
  - `A4` 项目可以定时被 review，但不必每一步被卡住。
  - review 不是只看 heartbeat 文本，而是按最小记忆梯度和证据梯度做判断。
  - brainstorm 只在触发条件满足时运行，不制造无谓 churn。
  - 实现出来的是“有护栏的自由 review”，不是僵硬 checklist agent。

### 8.5 `XT-W3-36-E` Review Note + Guidance Injection + Ack Loop

- priority: `P0`
- 目标：把 review 产物变成可追踪的 guidance 队列，而不是散落消息。
- 推荐落点：
  - 新增 `SupervisorReviewNoteStore.swift`
  - 新增 `SupervisorGuidanceInjectionStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- 实施步骤：
  1. Review 完成后写 `Review Note`。
  2. 根据 verdict 生成 `Guidance Queue Item`。
  3. 支持协议中已冻结的：
     - `target_role`
     - `delivery_mode`
     - `ack_status`
  4. `coder` 接到 guidance 后必须回写：
     - `accepted`
     - `deferred`
     - `rejected`
  5. `rejected` 必须附带原因。
- DoD：
  - supervisor 说过什么、project AI 是否接收、是否执行过，都能 audit。
  - `ack_status=pending` 的 guidance 不能被误当成已执行。

### 8.6 `XT-W3-36-F` Safe Point Coordinator

- priority: `P1`
- 目标：把 guidance 注入切到安全边界，避免粗暴打断执行链。
- 推荐落点：
  - 新增 `SupervisorSafePointCoordinator.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRunCoordinator.swift`
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
- 实施步骤：
  1. 冻结四类 safe point：
     - `next_tool_boundary`
     - `next_step_boundary`
     - `checkpoint_boundary`
     - `immediate`
  2. soft guidance 默认排队到下一个 safe point。
  3. `kill_switch / policy_denied / pre_high_risk_action` 允许升级到更强注入策略。
  4. 对被延期的 guidance 保留过期与重试策略。
- DoD：
  - project AI 不会因为轻量建议被频繁打断。
  - supervisor 又能在真正高风险时立即止损。

### 8.7 `XT-W3-36-G` Migration + Clamp + Kill-Switch Alignment

- priority: `P1`
- 目标：让新治理模型可以平滑吃掉旧项目、旧 slider、旧 autonomy mode，而不制造错误放权。
- 推荐落点：
  - `x-terminal/Sources/Project/AXProjectConfig.swift`
  - `x-terminal/Sources/Project/ProjectModel.swift`
  - `x-terminal/Sources/Project/AXProjectRegistry.swift`
  - `x-terminal/Sources/Project/AXProjectAutonomyPolicy.swift`
- 实施步骤：
  1. 保守迁移 legacy project。
  2. 统一 `AutonomyLevel` 与 `AXProjectAutonomyMode` 的 compat path。
  3. Hub clamp 与 local override 写入统一 effective snapshot。
  4. 为 kill-switch / clamp / expired TTL 给出可解释文案和 reason code。
- DoD：
  - 没有 project 因 schema 升级被静默放到更高自治档。
  - 所有 clamp 都能在 UI 和 runtime 上看到同一解释。

### 8.8 `XT-W3-36-H` Require-Real Regression + Metrics

- priority: `P1`
- 目标：把这套治理包做成可回归、可度量、可发布判断的主链。
- 推荐落点：
  - `x-terminal/Tests/`
  - `x-terminal/scripts/ci/`
  - `build/reports/`
- 需要补的测试族：
  - `ProjectGovernanceResolverTests`
  - `SupervisorInterventionPolicyEngineTests`
  - `SupervisorGuidanceInjectionStoreTests`
  - `SupervisorSafePointCoordinatorTests`
  - `XTToolRuntimePolicyGovernanceClampTests`
  - `ProjectSettingsGovernanceUITests`
- 关键指标：
  - `invalid_governance_combo_execution_count = 0`
  - `guidance_without_ack_tracking = 0`
  - `device_action_under_subminimum_supervision = 0`
  - `legacy_project_overgrant_after_migration = 0`
- 交付物：
  - `build/reports/xt_w3_36_project_governance_evidence.v1.json`

## 9) 实施顺序

推荐推进顺序：

1. `XT-W3-36-A`
2. `XT-W3-36-B`
3. `XT-W3-36-C`
4. `XT-W3-36-D`
5. `XT-W3-36-E`
6. `XT-W3-36-F`
7. `XT-W3-36-G`
8. `XT-W3-36-H`

原因：

- 先冻结 contract 和 resolver，后面的 UI / runtime / guidance 才不会各写一套解释
- guidance / safe point 必须建立在 review scheduler 之后
- migration 与 require-real regression 放在后半段，避免前面 contract 仍在变化时反复改 fixture

## 10) 完成标准

本包完成后，系统应能稳定回答下面这些过去经常说不清的问题：

1. 这个 project 到底能自主做到哪一步，是 `A1` 还是 `A4`？
2. supervisor 是只观察，还是会定期 brainstorm 和纠偏？
3. heartbeat 只是看进度，还是也会触发正式 review？
4. project coder 和 supervisor 各自能拿到多深的背景信息？
5. guidance 是不是已经注入、是否被接受、为什么被拒绝？
6. 旧项目迁移后有没有被错误放权？

如果这 6 个问题都能由统一的 governance resolver、UI 解释层和审计对象给出一致答案，`XT-W3-36` 才算真正完成。
