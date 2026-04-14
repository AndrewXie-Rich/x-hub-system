# X-Hub Supervisor Adaptive Intervention And Work Order Depth Work Orders v1

- Status: Active
- Updated: 2026-03-15
- Owner: Product / Supervisor / XT-L2 / Hub-L5 / QA / Security
- Purpose: 把“`Supervisor` 看广、按需看深、必要时出详细工单”的能力，正式接到现有 `S0..S4` 介入档位中；让强 `Project AI` 获得更少日常干预，让弱或不稳定 `Project AI` 自动得到更高介入、更深 review 和更细工单。
- Depends on:
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-governed-autonomy-switchboard-productization-work-orders-v1.md`
  - `docs/memory-new/xhub-supervisor-event-loop-stability-work-orders-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-33-supervisor-decision-kernel-routing-and-memory-governance-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `x-terminal/Sources/Project/AXProjectSupervisorInterventionTier.swift`
  - `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`

## 0) 结论先冻结

### 0.1 `Supervisor` 不是“只看广不看深”

冻结语义：

- `Supervisor` 默认看广：
  - 看 portfolio
  - 看跨项目优先级
  - 看风险、阻塞、资源竞争、grant、incident
- `Supervisor` 必须具备按需看深能力：
  - 对需要纠偏、重规划、救火或立项的项目进入 deep-dive
  - deep-dive 后必须产出结构化结论，而不是只留自然语言聊天
- `Supervisor` 的深读目标不是长期代替 `Project AI` 执行，而是：
  - 修正方向
  - 产出工单
  - 调整约束
  - 决定是否升级介入

### 0.2 `Project AI` 强弱必须成为正式治理输入

现有 `S0..S4` 已定义 supervisor 介入强度，但还缺一层：

- 同一个 `S3`，面对强 `Project AI` 和弱 `Project AI`，行为不应相同。
- 同一个 `A3/A4`，如果 `Project AI` 实际能力不稳定，系统不能只因为用户配置了高自治就放任它持续跑。

因此本工单冻结一条新原则：

- `configured S-Tier` 是用户或产品配置值。
- `effective S-Tier` 是运行时真相值。
- `effective S-Tier` 必须可被以下因素自动抬高：
  - `Project AI` 过弱
  - 近期不稳定
  - 任务复杂度升高
  - 风险等级升高
  - 证据不足
- 默认不自动降低用户明确选定的更高介入档位。

### 0.3 强 `Project AI` 不等于去掉 `Supervisor`

冻结：

- 强 `Project AI` 代表可以减少 routine intervention。
- 不代表去掉：
  - 战略 review
  - 高风险 gate
  - pre-done review
  - incident / drift / blocker 纠偏

也就是说：

- 强 `Project AI` => 少打断、少微操、少重复工单
- 弱 `Project AI` => 多复核、多工单、多显式约束

## 1) 北极星行为

系统完成后必须满足下面这条主线：

1. 用户或默认 profile 先给出一个 `configured S-tier`
2. 系统持续评估当前 `Project AI` 强弱
3. resolver 计算：
   - `recommended S-Tier`
   - `effective S-Tier`
   - `recommended work order depth`
4. `Supervisor` 在事件触发时按 `effective S-Tier` 决定：
   - 看多深
   - review 多细
   - 是否产出工单
   - 工单要细到什么程度
5. 所有抬档、降档建议、工单产出都写入 memory 与 audit

目标结果：

- 强 `Project AI` 可以高速推进
- 弱 `Project AI` 不会在高自治外壳下长期跑偏
- `Supervisor` 从“抽象点评者”升级为“战略纠偏 + 派工内核”

## 2) 新增固定对象

### 2.1 `Project AI Strength Profile`

新增运行时对象：

- `xt.project_ai_strength_profile.v1`

最少字段：

```json
{
  "schema_version": "xt.project_ai_strength_profile.v1",
  "project_id": "proj_alpha",
  "strength_band": "capable",
  "confidence": 0.81,
  "declared_capability_band": "strong",
  "empirical_reliability_band": "developing",
  "task_complexity_band": "medium",
  "risk_band": "medium",
  "evidence_freshness_band": "fresh",
  "recommended_supervisor_floor": "s3_strategic_coach",
  "recommended_work_order_depth": "execution_ready",
  "reasons": [
    "model route is capable but recent failure streak remains elevated",
    "project is currently in repo-write + test-fix phase"
  ],
  "assessed_at_ms": 1773500000000,
  "audit_ref": "audit_strength_001"
}
```

### 2.2 `Supervisor Adaptation Policy`

新增每项目治理策略：

- `xt.supervisor_adaptation_policy.v1`

最少字段：

```json
{
  "schema_version": "xt.supervisor_adaptation_policy.v1",
  "project_id": "proj_alpha",
  "adaptation_mode": "raise_only",
  "configured_supervisor_tier": "s3_strategic_coach",
  "allow_auto_relax": false,
  "stability_window_min": 180,
  "failure_streak_raise_threshold": 3,
  "insufficient_evidence_raise_threshold": 2,
  "incident_raise_enabled": true,
  "audit_ref": "audit_adapt_001"
}
```

冻结模式：

- `manual_only`
  - 只给建议，不自动抬档
- `raise_only`
  - 可以自动抬高 `effective S-Tier`
  - 不自动放松
- `bidirectional`
  - 可自动抬高，也可在稳定窗口后自动建议放松
  - 默认仍建议“提示用户或显式记录原因”

默认值：

- `raise_only`

### 2.3 `Work Order Depth`

新增正式派工深度对象：

- `xt.supervisor_work_order_depth.v1`

冻结枚举：

- `none`
- `brief`
- `milestone_contract`
- `execution_ready`
- `step_locked_rescue`

语义：

- `none`
  - 只审计或观察，不出工单
- `brief`
  - 目标、范围、验收、风险提醒
- `milestone_contract`
  - 当前阶段目标、边界、关键里程碑、上抛条件
- `execution_ready`
  - 明确输入、步骤建议、可用 skill、约束、验收、回退
- `step_locked_rescue`
  - 用于弱 AI、事故恢复、反复失败或高风险场景
  - 要求逐步执行、强 ack、更紧 safe point

## 3) `Project AI` 强弱分档冻结

### 3.1 Strength Bands

| Band | 名称 | 语义 |
| --- | --- | --- |
| `unknown` | Unknown | 新项目、新模型或证据不足，不能假定其强 |
| `weak` | Weak | 需要频繁纠偏，容易误解工单或无法稳定收口 |
| `developing` | Developing | 可推进局部任务，但复杂任务上仍不稳定 |
| `capable` | Capable | 可在项目内持续推进，偶发纠偏即可 |
| `strong` | Strong | 可在既定目标和边界下稳定推进多阶段任务 |

冻结：

- 首版不引入比 `strong` 更高的“无限自治”等级。
- 就算是 `strong`，高风险动作也不绕过治理。

### 3.2 强弱来源必须是“声明能力 + 实证表现”的合成

`Project AI Strength Profile` 不能只看模型名，也不能只看最近一次成功。

至少由五类信号合成：

1. `declared capability`
   - 当前项目实际模型路由
   - 可用 tools / skills
   - trusted automation readiness
   - device authority / grant posture 是否到位

2. `empirical reliability`
   - 最近成功收口率
   - failure streak
   - retry 后恢复率
   - review 退化率
   - 用户或 Supervisor 否决率

3. `task complexity`
   - 是否跨 repo / browser / connector / device
   - 是否多阶段、多依赖、多子任务
   - 是否需要大量外部上下文

4. `risk band`
   - 是否涉及高风险 side effect
   - 是否涉及删除、外发、权限升级、联网、支付

5. `evidence quality`
   - 是否有最新 tests / logs / UI review / skill evidence
   - 是否长期处于 `insufficient_evidence`

## 4) `S0..S4` 与强弱分档的结合规则

### 4.1 `S-tier` 仍是主语义，强弱只是运行时放大器

冻结：

- `S-tier` 决定 Supervisor 的基础角色。
- `strength band` 决定在该基础角色下：
  - 是否要更频繁 deep-dive
  - 是否要更详细出工单
  - 是否要更强 ack / hold / review

### 4.2 分档行为表

| S-tier | 强 `Project AI` | 弱/未知 `Project AI` |
| --- | --- | --- |
| `S0 Silent Audit` | 仅保留观察与审计；不建议用于高自治执行面 | 禁止搭配 `A2+` 持续执行；必须抬档 |
| `S1 Milestone Review` | 只在 phase / pre-done / manual request 出 `brief` 或 `milestone_contract` | 对弱 AI 视为不足；推荐至少抬到 `S2` |
| `S2 Periodic Review` | 周期巡检，必要时出 `milestone_contract` | 周期巡检 + blocker deep-dive；默认出 `execution_ready` |
| `S3 Strategic Coach` | 以战略 review 为主；新阶段 / blocker / drift 时出高质量工单 | 默认进入“战略 review + 明细派工”模式；弱 AI 下工单深度提升到 `execution_ready` 或更高 |
| `S4 Tight Supervision` | 用于高风险、关键交付或人工明确要求紧盯 | 弱 AI 默认档；可要求 `step_locked_rescue`、pre-step hold、强 ack |

### 4.3 强弱对工单深度的默认映射

| Strength Band | 默认工单深度 |
| --- | --- |
| `unknown` | `execution_ready` |
| `weak` | `step_locked_rescue` |
| `developing` | `execution_ready` |
| `capable` | `milestone_contract` 或 `execution_ready` |
| `strong` | `brief` 或 `milestone_contract` |

## 5) `configured` / `recommended` / `effective` 三值冻结

### 5.1 三个值必须分开

每个项目至少同时保留：

- `configured_supervisor_tier`
- `recommended_supervisor_tier`
- `effective_supervisor_tier`

解释：

- `configured`
  - 用户或 profile 显式配置
- `recommended`
  - 系统根据强弱、复杂度、风险给出的建议
- `effective`
  - 真正生效的 runtime 档位

### 5.2 `effective` 计算规则

冻结公式：

```text
effective_supervisor_tier =
  max(
    configured_supervisor_tier,
    execution_tier_min_floor,
    risk_floor,
    weakness_floor,
    instability_raise,
    incident_raise
  )
```

其中：

- `execution_tier_min_floor`
  - 继续沿用 `A-tier` 对 `S-tier` 的最小约束
- `risk_floor`
  - 高风险动作前的临时抬档
- `weakness_floor`
  - 弱或未知 `Project AI` 的最小监督要求
- `instability_raise`
  - 连续失败、证据不足、UI review 退化、测试退化触发的抬档
- `incident_raise`
  - incident / blocker / repeated drift 时的强制抬档

冻结：

- 默认只允许“自动抬高”，不允许“静默自动降低用户配置”。
- 若要自动放松，只能在 `bidirectional` 模式下进行，并留下显式 audit。

## 6) Supervisor 工单规则冻结

### 6.1 哪些场景必须由 `Supervisor` 出工单

以下场景强制要求 `Supervisor` 生成结构化工单，而不是只给一句建议：

- 新项目立项
- 新阶段切换
- 连续失败达到阈值
- blocker 超过时间窗
- plan drift
- incident 恢复
- pre-done 总结前
- 高风险动作前
- 引入新 skill / 新 publisher / 新外部能力前

### 6.2 工单必须具备的字段

冻结最少字段：

- `goal`
- `why_now`
- `scope`
- `non_goals`
- `inputs_and_refs`
- `constraints`
- `allowed_skills_and_tools`
- `acceptance`
- `rollback_or_abort_conditions`
- `escalate_back_to_supervisor_when`

### 6.3 工单不是把 `Project AI` 变成脚本执行器

冻结：

- `Supervisor` 产出的是“作战命令”和“约束合同”
- `Project AI` 仍保留项目内局部自主权

也就是：

- `Supervisor` 定方向、边界、验收、升级条件
- `Project AI` 决定项目内具体执行路径

只有在 `step_locked_rescue` 模式下，才允许更接近逐步执行。

## 7) 触发和升级规则冻结

### 7.1 弱化介入的前提

只有同时满足下面条件，才能建议较少 routine intervention：

- `strength_band >= capable`
- 近期 failure streak 低
- 近期 review 不显示明显 drift
- 近期 evidence 充分
- 当前阶段不属于高风险

### 7.2 强化介入的条件

命中任一条件都可抬高 `effective S-Tier` 或提高工单深度：

- `strength_band = unknown`
- `strength_band = weak`
- `failure_streak >= threshold`
- `insufficient_evidence` 连续命中
- `ui_review` 或 tests 出现回归
- grant / approval 频繁被拦
- project 长时间无有效进展
- 触发 incident / blocker / repeated drift

## 8) UI / 产品化落点

### 8.1 Project Settings

必须新增或清晰暴露：

- `Project AI Strength`
  - 当前评估值
  - 置信度
  - 为什么这么判断
- `Supervisor Adaptation Mode`
  - `manual_only`
  - `raise_only`
  - `bidirectional`
- `Configured / Effective S-tier`
  - 如果不同，要解释原因
- `Work Order Depth`
  - 当前默认派工深度

### 8.2 Project Detail

项目详情至少要能看到：

- 当前 `Project AI` 强弱
- 最近一次抬档原因
- 最近一次 `Supervisor` 工单
- 当前 `effective S-Tier`

### 8.3 Supervisor View

`Supervisor` 侧最近活动需要统一呈现：

- 当前项目是否因为“AI 过弱/不稳定”而进入更高介入档
- 最近工单深度
- 抬档原因
- 是否处于紧监督窗口

## 9) 实现分包

### 9.1 `SAI-W1` Freeze contract and resolver semantics

- Goal:
  - 冻结 `Project AI Strength Profile`、`Supervisor Adaptation Policy`、`Work Order Depth`
  - 把 `configured / recommended / effective` 三值接入治理 resolver
- Suggested touchpoints:
  - `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`
  - `x-terminal/Sources/Project/AXProjectGovernanceBundle.swift`
  - `x-terminal/Sources/Project/AXProjectSupervisorInterventionTier.swift`
- DoD:
  - 可导出三值快照
  - 自动抬档规则可机读
  - 现有 `A-tier` floor 继续生效

### 9.2 `SAI-W2` Build strength assessor

- Goal:
  - 基于模型、工具、skills、任务复杂度、历史结果构建 `Project AI Strength Profile`
- Suggested touchpoints:
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Tools/XTToolRuntimePolicy.swift`
  - `x-terminal/Sources/Project/`
  - `x-terminal/Sources/Hub/`
- DoD:
  - 至少能输出 `unknown/weak/developing/capable/strong`
  - 可写回审计和 memory

### 9.3 `SAI-W3` Connect adaptive review and work-order generation

- Goal:
  - 让 `Supervisor` 在 review 时按当前强弱选择工单深度
- Suggested touchpoints:
  - `x-terminal/work-orders/xt-w3-33-supervisor-decision-kernel-routing-and-memory-governance-implementation-pack-v1.md`
  - `x-terminal/Sources/Supervisor/SupervisorReviewNoteStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorGuidanceInjectionStore.swift`
- DoD:
  - review note 可挂工单深度
  - guidance 可显式带 `work_order_ref`
  - weak AI 场景不再只产出抽象建议

### 9.4 `SAI-W4` Productize in settings and supervisor surfaces

- Goal:
  - 在项目设置页、项目详情页、Supervisor 活动页统一展示：
    - 强弱评估
    - effective S-tier
    - 最近工单
    - 抬档原因
- Suggested touchpoints:
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Sources/UI/Projects/ProjectDetailView.swift`
  - `x-terminal/Sources/Supervisor/SupervisorView.swift`
- DoD:
  - 用户能看懂为什么项目当前被盯得更紧或更松
  - 不需要读日志才能理解有效治理状态

### 9.5 `SAI-W5` Tests, gates, and regression metrics

- Goal:
  - 给自动抬档、工单深度和解释链补齐回归
- Must cover:
  - 弱 AI 自动抬档
  - 强 AI 不被静默降档
  - incident / blocker 触发 `S4`
  - work order depth 跟随强弱与风险变化
  - UI 正确展示 configured / effective 差异
- KPI:
  - `weak_ai_under_supervised = 0`
  - `strong_ai_silently_overconstrained <= agreed_threshold`
  - `review_without_structured_work_order_when_required = 0`

## 10) 最终产品判断标准

完成后，系统应达到下面这条体验：

- 用户能明确知道：
  - 当前项目的 `Project AI` 强不强
  - 为什么强或弱
  - `Supervisor` 为什么在这个项目上盯得更紧或更松
  - 当前到底只是 review，还是已经进入“详细派工”
- 强 `Project AI` 项目可以少打断、高速推进
- 弱 `Project AI` 项目会被自动收紧治理，并得到更详细的 `Supervisor` 工单
- `Supervisor` 既不会沦为闲置旁观者，也不会退化成所有项目的微操瓶颈
