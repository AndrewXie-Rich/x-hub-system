# X-Hub Project Autonomy Tier + Supervisor Review Protocol v1

- version: v1.0
- updatedAt: 2026-04-09
- owner: X-Terminal / Supervisor / Hub Policy / Trusted Automation
- status: active
- scope: 为每个 project 冻结一套统一的自治档位、能力边界、review 节奏、干预语义和 safe-point 注入协议；覆盖 `A0..A4` 与 `Supervisor Review Policy`。
- machine-readable contract: `docs/memory-new/schema/xhub_project_autonomy_and_supervisor_review_contract.v1.json`
- normalization note: 本文档固定使用用户可见的 normalized protocol 命名（例如 `A4 Agent`、`a4_agent`、`trusted runtime surface`）；当前 schema/runtime 若仍存在旧兼容标识，只能按 compat alias 理解，不得继续作为产品命名。
- related:
  - `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
  - `docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
  - `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `x-terminal/Sources/Project/AXProjectAutonomyPolicy.swift`
  - `x-terminal/Sources/Project/AXProjectConfig.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRuntimePolicy.swift`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`

## 0) 目标与非目标

目标
- 让每个 project 顶部只有一个清晰的自治档位，但系统内部仍保持可治理、可审计、可 clamp 的策略包。
- 明确区分三件事：
  - `Heartbeat`: 看进度。
  - `Review`: 看方向、看方法、看偏航。
  - `Intervention`: 把建议或停止信号注入给执行中的 project AI。
- 让 `A4 Agent` 成为“高自治 + 旁路监督”的模式，而不是“没有 supervisor”。
- 把 `memory ceiling`、`capability bundle`、`execution budget`、`review cadence`、`safe-point injection` 固化为机读 contract。
- 保持 Hub-first governance：高风险动作、grant、kill-switch、TTL、audit、remote clamp 继续有效。

非目标
- 不把 `A4` 定义成“无限制 root 权限”。
- 不允许跨 project 原始记忆自由注入。
- 不允许绕过 trusted automation、tool policy、Hub grant、kill-switch 或 fail-closed。
- 不把现有 `AXProjectAutonomyMode` 和 `AutonomyLevel` 直接当成最终协议真相源；它们只作为兼容层与迁移输入。

## 1) 固定决策

1. `Project Autonomy Tier` 与 `Memory Serving Profile` 必须分离。
   - `Project Autonomy Tier` 决定“AI 能做什么、谁何时介入、预算多大”。
   - `Memory Serving Profile` 决定“AI 能看到多少上下文、看到多深”。

2. `Heartbeat != Review != Intervention`。
   - 进度心跳可以高频、轻量、便宜。
   - review 可以低频但更深。
   - intervention 必须有节制，默认在 safe point 注入。

3. `A4` 不等于“去掉 supervisor”。
   - `A4` 的真实定义是：project AI 可连续执行到交付收口，supervisor 在旁路做阶段复盘、方向纠偏、必要时暂停或重规划。

4. 用户只看一个档位，但系统内部必须展开成策略包。
   - `autonomy_tier`
   - `memory_profile_ceiling`
   - `capability_bundle`
   - `execution_budget`
   - `supervisor_review_policy`
   - `clamp / ttl / kill_switch`

5. 所有 review / guidance / clamp 都必须可审计。
   - 不能只靠自然语言聊天记录表达“提醒过、建议过、停过”。
   - 需要结构化 `Review Note` 与 `Guidance Injection` 对象。

6. 默认不即时打断。
   - 除非命中 `high_risk / kill_switch / clear_wrong_direction / policy_violation`。
   - 普通建议默认在 `safe point` 注入。

## 2) 协议主对象

### 2.1 `Project Autonomy Bundle`

单个 project 的自治总合同。它是用户顶部档位的展开结果。

最少包含：
- 当前 tier
- memory ceiling
- capability bundle
- execution budget
- review policy reference
- clamp / ttl / kill-switch

### 2.2 `Supervisor Review Policy`

定义 supervisor 何时 review、review 多深、默认如何干预。

最少包含：
- progress heartbeat 间隔
- pulse review 间隔
- event-driven review 是否开启
- strategic / rescue trigger 集合
- 默认 intervention mode
- safe point policy
- interrupt rate limit
- review memory ceiling

### 2.3 `Supervisor Review Note`

每次 review 的结构化产物。

最少包含：
- trigger
- review level
- verdict
- confidence
- why
- recommended actions
- intervention mode
- 是否需要 coder ack

### 2.4 `Guidance Injection`

review 结果真正注入给 project AI 的对象，而不是一段散落文本。

最少包含：
- target role
- delivery mode
- intervention mode
- safe point policy
- ack status

### 2.5 `Safe Point`

允许 supervisor 把建议安全插入执行链的位置。

本协议冻结 4 类：
- `next_tool_boundary`
- `next_step_boundary`
- `checkpoint_boundary`
- `immediate`

## 3) 自治档位冻结（A0..A4）

注意：`A0..A4` 是新的 project-level 用户档位，不等于旧的 `AutonomyLevel 1..5`，也不等于旧 runtime surface preset 的 `manual/guided/trusted` 兼容层语义。

兼容规则：

- 本文档里的 tier key 使用 normalized protocol id，例如 `a4_agent`。
- 当前 schema/runtime 若仍返回旧兼容 id，应视为同一档位的 compat alias，而不是新的产品命名。

| Tier | 名称 | 默认 memory ceiling | 允许能力 | 默认 review policy | Supervisor 角色 |
| --- | --- | --- | --- | --- | --- |
| `a0_observe` | Observe | `m2_plan_review` | 只读记忆、项目状态、结构化建议 | `milestone_only` | 解释器 / 建议者 |
| `a1_plan` | Plan | `m2_plan_review` | `job/plan`、写 memory、梳理执行方案 | `periodic` | 计划监督者 |
| `a2_repo_auto` | Repo Auto | `m3_deep_dive` | repo 读写、build/test、patch、verify | `hybrid` | 执行纠偏者 |
| `a3_deliver_auto` | Deliver Auto | `m3_deep_dive` | 连续执行到交付、自动重试、收口汇总 | `hybrid` | 旁路 governor |
| `a4_agent` | Agent | `m4_full_scan` | device/browser/connector/extension 受治理执行 | `hybrid` 或 `aggressive` | 战略监督者 / 仲裁者 |

### 3.1 `A0 Observe`

- 不创建 job、不写 repo、不跑 side effect。
- 适合：
  - 项目刚创建
  - 高不确定性探索
  - 需要先理解全貌再行动

### 3.2 `A1 Plan`

- 允许：
  - 自动起 `job`
  - 自动写 `plan`
  - 自动回写项目记忆
  - 自动形成下一步执行方案
- 仍不允许：
  - repo side effect
  - device side effect

### 3.3 `A2 Repo Auto`

- 允许在 project root 内自主推进：
  - `write_file`
  - `git_apply`
  - `build/test`
  - governed verification
- 不要求 supervisor 每一步介入。
- 默认要求：
  - build/test evidence
  - 失败后 bounded retry
  - pre-done review

### 3.4 `A3 Deliver Auto`

- 在 `A2` 之上增加：
  - 连续执行多 step / 多轮
  - 阶段性收口
  - 交付前摘要
  - 完成后结果汇总通知用户
- supervisor 默认只在：
  - 周期 review
  - blocker
  - plan drift
  - pre-done
  时介入

### 3.5 `A4 Agent`

- 在 `A3` 之上允许受治理 device-level surface：
  - browser runtime
  - governed device tools
  - connector actions
  - extension surfaces
- `A4` 不是无限制放权。
- `A4` 必须继续受：
  - trusted automation binding
  - project-scoped device authority
  - tool runtime policy
  - Hub grant
  - TTL / clamp / kill-switch
  - supervisor review
  共同约束

冻结规则：
- 如果 `A4` 想用 `device / connector / extension`，必须满足 trusted runtime surface + trusted automation + device authority + project binding。
- 若不满足，必须 fail-closed 或被 clamp 回 `A3/A2/A1`，不能 silently 越界执行。

## 4) Review Policy 冻结

### 4.1 Review Policy Modes

- `off`
- `milestone_only`
- `periodic`
- `hybrid`
- `aggressive`

说明：
- `milestone_only`: 只在 phase 切换、pre-done、manual review 等节点触发。
- `periodic`: 只按间隔触发。
- `hybrid`: 周期触发 + 事件触发。
- `aggressive`: 高频 heartbeat + 周期 review + 关键事件强制 deep review。

### 4.2 Review Levels

#### `r1_pulse`

- 目标：快速看进度和轻量方向。
- 推荐 memory profile：`m2_plan_review`
- 常见触发：
  - 周期 pulse
  - 心跳窗口到达
  - milestone checkpoint

#### `r2_strategic`

- 目标：判断“方法对不对、有没有更好路径、是否该改 plan”。
- 推荐 memory profile：`m3_deep_dive`
- 常见触发：
  - failure streak
  - blocker
  - no progress window
  - plan drift

#### `r3_rescue`

- 目标：明显跑偏、高风险动作前、完成前最后复核。
- 推荐 memory profile：`m4_full_scan`
- 常见触发：
  - pre_high_risk_action
  - pre_done_summary
  - repeated_wrong_direction
  - manual forced review

### 4.3 Trigger Dictionary

冻结 `review_trigger`：
- `periodic_heartbeat`
- `periodic_pulse`
- `failure_streak`
- `no_progress_window`
- `blocker_detected`
- `plan_drift`
- `pre_high_risk_action`
- `pre_done_summary`
- `manual_request`
- `user_override`

### 4.4 Verdict Dictionary

冻结 `review_verdict`：
- `on_track`
- `watch`
- `better_path_found`
- `wrong_direction`
- `high_risk`

### 4.5 Mid-Project Review Input Ladder

Supervisor 做中途 review 时，不允许只看一句 heartbeat 就下指导。

冻结 review 最小输入护栏：

1. `L0/L1 anchor pack`，每次必看
   - `L0 constitution / policy hard lines`
   - 项目原始目标
   - 最新用户明确要求
   - `done / acceptance` 定义
   - 明确限制条件：
     - 时间
     - 风险
     - 不可做事项
     - 技术边界
   - 最新已批准 decision

2. `L2 progress pack`，每次必看
   - 当前阶段 / active plan summary
   - 当前 step 和 step owner
   - 最新 heartbeat / progress delta
   - blocker summary
   - 最新 review note 与未 ack guidance
   - 当前 grant / clamp / kill-switch 状态

3. `L3 working set`，默认应看
   - 最近热上下文摘要
   - 当前变更范围摘要
   - 当前验证状态摘要：
     - build
     - test
     - lint
     - verify
   - 近几轮关键执行结果摘要

4. `L4 raw evidence`，只在需要时展开
   - 失败日志
   - test failure 详情
   - diff / patch 证据
   - 外部动作回执
   - tool trace

默认规则：

- supervisor 必须先建立 `L0/L1 anchor`，但不要求后续所有层都按固定顺序读取。
- 在 `L2/L3/L4` 之间允许自由跳转，只要最终判断有足够证据支撑。
- `r1_pulse` 至少读完 `L0/L1 + L2 + L3 summary`。
- `r2_strategic` 若要给改路建议，必须额外展开相关 `L4 evidence` 或 decision/background drilldown，不能只凭感觉改 plan。
- `r3_rescue` 必须补足与风险点直接相关的 `L4 evidence`，不能只看摘要。

### 4.6 Mid-Project Review Frame

冻结 supervisor 中途 review 的最小判断框架，而不是固定推理顺序：

1. `re-anchor`
   - 用一句话重述：
     - 这个项目最初要达成什么
     - 当前 done 定义是什么
     - 当前哪些约束不能破

2. `progress-vs-goal check`
   - 判断当前推进是否真的缩短了到目标的距离。
   - 不能把“看起来忙”当成“在接近目标”。

3. `quality check`
   - 判断当前方案是否在质量上成立：
     - correctness
     - verification coverage
     - rollbackability
     - maintainability
     - side-effect safety

4. `drift check`
   - 判断当前方向是否偏离最初要求。
   - 重点检查：
     - 是否擅自扩大 scope
     - 是否绕开原始约束
     - 是否把手段当目标

5. `option scan`
   - 若命中 `r2_strategic` 或 `r3_rescue`，默认应做一次替代路径扫描：
     - 当前路径继续推进
     - 更保守路径
     - 更高收益但更高成本路径（可选）
   - 如果证据已经非常明确地支持继续当前路径，可只做轻量 option sanity check，不要求强行展开完整 brainstorm。

6. `decision`
   - 只有在下列条件之一成立时，才允许建议改 plan：
     - 当前路径明显错了
     - 当前路径质量风险过高
     - 存在显著更优路径
     - 当前路径已被 blocker 卡死

7. `guidance shaping`
   - guidance 默认应是最小必要改动：
     - 保持目标不变
     - 缩小改动面
     - 指明下一安全动作
   - 不要在弱证据下整包推翻 coder 当前计划。

补充规则：

- supervisor 可以自由决定先看质量、先看 drift、还是先看 blocker，只要最后覆盖到上述判断框架。
- 协议约束的是“必须回答哪些问题”，不是“脑内必须按什么顺序想”。

### 4.7 Brainstorm Rules

Supervisor 的 brainstorm 不是“每次 review 都强行想新点子”，而是受触发条件约束的高成本动作。

默认应 brainstorm 的情形：

- `plan_drift`
- `failure_streak`
- `blocker_detected`
- `no_progress_window`
- `pre_high_risk_action`
- `pre_done_summary` 但质量信心不足
- 同一路径已重复尝试仍无明显增益

可跳过 brainstorm 的情形：

- 当前路径进展稳定且验证在变绿
- 当前路径仍严格贴合原始要求
- 没有出现新证据表明当前方案不优

冻结 brainstorm 输出要求：

1. 默认应形成 `keep_current_path` 与 `proposed_better_path` 的比较。
2. 若证据非常明确地支持继续当前路径，可只输出：
   - 为什么继续当前路径
   - 当前路径的主要风险
   - 下一观察点
3. 若建议切换路径，必须说明：
   - 为什么更好
   - 成本是什么
   - 风险是什么
   - 对原始要求的影响是什么
4. 不允许只给“也许可以换一种做法”这种无落点建议。

### 4.8 Review Freedom Budget

为了保持 supervisor 的创造力与判断自由，协议明确保留以下自由度：

1. 可自由决定在 `L2/L3/L4` 中的阅读顺序与展开深度。
2. 可自由决定 review 文风与论证方式，不要求模板化语言。
3. 可自由提出未在既有 plan 中出现的新办法，但必须说明它与原始目标的关系。
4. 可在低风险、证据充分时只做轻量 guidance，不强制每次产出重规划建议。

协议不保留的自由：

1. 不能跳过 `goal / done / constraints` 的 re-anchor。
2. 不能在证据不足时大幅改路。
3. 不能把 brainstorm 变成无边界扩 scope。
4. 不能给不可执行、不可验证的建议。

### 4.9 High-Quality Review 的判断标准

一个高质量 supervisor review 至少应同时满足：

1. `goal aligned`
   - 明确引用最初目标和当前 done 定义，而不是只评论局部实现细节。

2. `evidence based`
   - 关键判断能对应到记忆、日志、验证结果或 decision track。

3. `quality oriented`
   - 会检查验证、回滚、风险和维护性，而不是只看速度。

4. `anti-drift`
   - 能主动识别 scope creep、错误抽象和“越做越偏”。

5. `low-churn`
   - 不在证据不足时频繁推翻 coder 计划。

6. `actionable`
   - 输出必须是清晰下一步，而不是泛泛评论。

## 5) Intervention + Safe Point 冻结

### 5.1 `intervention_mode`

- `observe_only`
- `suggest_next_safe_point`
- `replan_next_safe_point`
- `stop_immediately`

默认规则：
- 普通 review 结论默认 `suggest_next_safe_point`
- 发现更优路径但不致命时默认 `replan_next_safe_point`
- 高风险、越界或明显跑偏时允许 `stop_immediately`

### 5.2 `safe_point_policy`

- `next_tool_boundary`
- `next_step_boundary`
- `checkpoint_boundary`
- `immediate`

默认规则：
- `A2/A3/A4` 的软干预默认 `next_tool_boundary` 或 `next_step_boundary`
- `pre_high_risk_action` 命中的干预可升级到 `checkpoint_boundary`
- `kill_switch`、`policy_denied`、`wrong_direction + high_confidence` 才允许 `immediate`

### 5.3 `ack_status`

project AI 收到 guidance injection 后必须回写：
- `pending`
- `accepted`
- `deferred`
- `rejected`

`rejected` 必须附带理由，不能静默忽略。

### 5.4 `target_role` and `delivery_mode`

冻结 `target_role`：
- `coder`
- `supervisor`
- `project_chat`

冻结 `delivery_mode`：
- `context_append`
- `priority_insert`
- `replan_request`
- `stop_signal`

默认规则：
- 普通建议用 `context_append` 或 `priority_insert`
- 要求重规划时用 `replan_request`
- 强制暂停时用 `stop_signal`

## 6) Object Freeze

### 6.1 `xhub.project_autonomy_bundle.v1`

用途：
- 单个 project 的统一自治合同。

最小字段：
- `schema_version`
- `project_id`
- `autonomy_tier`
- `memory_profile_ceiling`
- `review_policy_mode`
- `capability_bundle`
- `execution_budget`
- `hub_override_mode`
- `ttl_seconds`
- `updated_at_ms`
- `audit_ref`

字段说明：
- `capability_bundle`
  - `allow_job_plan_auto`
  - `allow_repo_write`
  - `allow_repo_build`
  - `allow_repo_test`
  - `allow_git_apply`
  - `allow_browser_runtime`
  - `allow_device_tools`
  - `allow_connector_actions`
  - `allow_extensions`
  - `allow_auto_local_approval`
- `execution_budget`
  - `max_continuous_run_minutes`
  - `max_tool_calls_per_run`
  - `max_retry_depth`
  - `max_cost_usd_soft`
  - `pre_done_review_required`
  - `done_requires_evidence`

示例：

```json
{
  "schema_version": "xhub.project_autonomy_bundle.v1",
  "project_id": "proj-liang-001",
  "autonomy_tier": "a4_agent",
  "memory_profile_ceiling": "m4_full_scan",
  "review_policy_mode": "hybrid",
  "capability_bundle": {
    "allow_job_plan_auto": true,
    "allow_repo_write": true,
    "allow_repo_build": true,
    "allow_repo_test": true,
    "allow_git_apply": true,
    "allow_browser_runtime": true,
    "allow_device_tools": true,
    "allow_connector_actions": true,
    "allow_extensions": true,
    "allow_auto_local_approval": true
  },
  "execution_budget": {
    "max_continuous_run_minutes": 120,
    "max_tool_calls_per_run": 80,
    "max_retry_depth": 3,
    "max_cost_usd_soft": 25,
    "pre_done_review_required": true,
    "done_requires_evidence": true
  },
  "hub_override_mode": "none",
  "ttl_seconds": 7200,
  "updated_at_ms": 1773360000000,
  "audit_ref": "audit-project-autonomy-liang-v1"
}
```

### 6.2 `xhub.supervisor_review_policy.v1`

用途：
- 定义单个 project 的 heartbeat / review / intervention 节奏。

最小字段：
- `schema_version`
- `policy_id`
- `project_id`
- `mode`
- `progress_heartbeat_interval_sec`
- `pulse_review_interval_sec`
- `enable_event_driven_review`
- `strategic_review_triggers`
- `rescue_review_triggers`
- `default_review_level`
- `intervention_default`
- `safe_point_policy`
- `max_soft_interventions_per_hour`
- `mandatory_review_checkpoints`
- `review_memory_profile_ceiling`
- `audit_ref`

示例：

```json
{
  "schema_version": "xhub.supervisor_review_policy.v1",
  "policy_id": "review-liang-hybrid-v1",
  "project_id": "proj-liang-001",
  "mode": "hybrid",
  "progress_heartbeat_interval_sec": 900,
  "pulse_review_interval_sec": 1800,
  "enable_event_driven_review": true,
  "strategic_review_triggers": [
    "failure_streak",
    "no_progress_window",
    "blocker_detected",
    "plan_drift"
  ],
  "rescue_review_triggers": [
    "pre_high_risk_action",
    "pre_done_summary"
  ],
  "default_review_level": "r1_pulse",
  "intervention_default": "suggest_next_safe_point",
  "safe_point_policy": "next_step_boundary",
  "max_soft_interventions_per_hour": 3,
  "mandatory_review_checkpoints": [
    "blocker_detected",
    "pre_high_risk_action",
    "pre_done_summary"
  ],
  "review_memory_profile_ceiling": "m4_full_scan",
  "audit_ref": "audit-review-policy-liang-v1"
}
```

### 6.3 `xhub.supervisor_review_note.v1`

用途：
- 结构化记录一次 review 结论。

最小字段：
- `schema_version`
- `review_id`
- `policy_id`
- `project_id`
- `trigger`
- `review_level`
- `verdict`
- `confidence`
- `why`
- `recommended_actions`
- `intervention_mode`
- `safe_point_policy`
- `requires_ack`
- `review_memory_profile`
- `created_at_ms`
- `audit_ref`

示例：

```json
{
  "schema_version": "xhub.supervisor_review_note.v1",
  "review_id": "review-liang-20260313-001",
  "policy_id": "review-liang-hybrid-v1",
  "project_id": "proj-liang-001",
  "job_id": "job-20260313-001",
  "plan_id": "plan-liang-refactor-v2",
  "trigger": "plan_drift",
  "review_level": "r2_strategic",
  "verdict": "better_path_found",
  "confidence": 0.87,
  "why": "当前计划先做大范围重排，成本高且回滚面大；先切模块边界更稳。",
  "recommended_actions": [
    "先输出模块边界图和依赖方向",
    "把大规模重排拆成两阶段 patch"
  ],
  "intervention_mode": "replan_next_safe_point",
  "safe_point_policy": "next_step_boundary",
  "requires_ack": true,
  "review_memory_profile": "m3_deep_dive",
  "created_at_ms": 1773360030000,
  "audit_ref": "audit-review-note-liang-001"
}
```

### 6.4 `xhub.supervisor_guidance_injection.v1`

用途：
- 把 review note 变成可追踪的执行插入事件。

最小字段：
- `schema_version`
- `injection_id`
- `review_id`
- `project_id`
- `target_role`
- `delivery_mode`
- `intervention_mode`
- `safe_point_policy`
- `guidance_text`
- `ack_status`
- `injected_at_ms`
- `audit_ref`

冻结规则：
- `ack_status=pending` 时，不得把本次 guidance 视为已执行。
- `ack_status=rejected` 时必须附带 `ack_note`。
- `observe_only` guidance 可以不要求 ack，但仍需 audit。

## 7) Recommended Defaults by Tier

| Tier | Heartbeat | Pulse Review | Mode | Default Intervention | Mandatory Checkpoints |
| --- | --- | --- | --- | --- | --- |
| `A0` | 1800s | disabled | `milestone_only` | `observe_only` | `manual_request` |
| `A1` | 1200s | 3600s | `periodic` | `suggest_next_safe_point` | `pre_done_summary` |
| `A2` | 900s | 1800s | `hybrid` | `suggest_next_safe_point` | `blocker_detected`, `pre_done_summary` |
| `A3` | 600s | 1200s | `hybrid` | `replan_next_safe_point` | `blocker_detected`, `plan_drift`, `pre_done_summary` |
| `A4` | 600s | 1200s | `hybrid` or `aggressive` | `suggest_next_safe_point` | `blocker_detected`, `pre_high_risk_action`, `pre_done_summary` |

说明：
- `A4` 默认不是最高频打断，而是最高等级的旁路复盘能力。
- `A4` 的关键价值不是“更多打断”，而是“更强纠偏 + 更强边界控制 + 更完整记忆”。
- `A/S` 的组合 guidance 是产品治理建议，不是物理不可能矩阵。
- 用户可以显式选择更低监督强度的组合；系统应显著提示风险，但不应仅因 `A/S` 搭配本身直接 fail-closed。
- 真正的 fail-closed 继续只来自 trusted automation、tool policy、Hub grant、TTL、kill-switch、runtime readiness、scope / binding 等执行边界。

### 7.1 Operator Overview

1. `A0..A4` 只回答一件事：project AI 最多能动到哪里。
2. `S0..S4` 只回答一件事：Supervisor 会盯多深、会不会主动纠偏。
3. `Heartbeat / Pulse / Brainstorm / Event-driven` 只回答一件事：多久看一次，以及什么事件会起 review。
4. 推荐组合是默认起步点，不是强制矩阵；用户可以往更弱监督或更强监督方向偏移。
5. 真正决定动作会不会被放行的，仍是 grant、权限就绪、runtime surface、TTL、kill-switch 和 Hub clamp。

## 8) 与现有实现的兼容映射

### 8.1 `AXProjectAutonomyMode`

现有：
- `manual`
- `guided`
- legacy trusted runtime-surface compat value

协议定位：
- 它是 `surface clamp / execution surface preset`，不是完整自治 tier。
- 兼容层的具体旧字面值由 schema/runtime 维护；本文档不再把旧字面值当成对外术语。

冻结映射：
- `A0/A1` 默认可落在 `manual`
- `A2/A3` 可继续使用 `manual/guided`，是否开 browser 由 capability bundle 决定
- `A4` 若启用 device/connector/extension，必须进入 trusted runtime surface

### 8.2 `AXProjectConfig`

现有字段映射：
- `autonomyMode` -> `surface preset`
- `autonomyAllowDeviceTools` -> `capability_bundle.allow_device_tools`
- `autonomyAllowBrowserRuntime` -> `capability_bundle.allow_browser_runtime`
- `autonomyAllowConnectorActions` -> `capability_bundle.allow_connector_actions`
- `autonomyAllowExtensions` -> `capability_bundle.allow_extensions`
- `governedAutoApproveLocalToolCalls` -> `capability_bundle.allow_auto_local_approval`
- `automationSelfIterateEnabled` / `automationMaxAutoRetryDepth` -> `execution_budget.max_retry_depth`
- `autonomyTTLSeconds` / `autonomyHubOverrideMode` -> `clamp / ttl`

### 8.3 `AutonomyLevel` 旧滑杆

旧的 `AutonomyLevel(1..5)` 只保留迁移价值，推荐兼容映射：
- `1 -> A0`
- `2 -> A1`
- `3 -> A2`
- `4 -> A3`
- `5 -> A4`

但冻结规则是：
- 迁移后，运行时以 `Project Autonomy Bundle` 为准，不再以 legacy slider 为准。

### 8.4 `Memory Serving Profile`

保持正交：
- `A0/A1` 推荐 ceiling `m2_plan_review`
- `A2/A3` 推荐 ceiling `m3_deep_dive`
- `A4` 推荐 ceiling `m4_full_scan`

### 8.5 `Supervisor` 当前 heartbeat 页面

当前页面若已有“项目心跳时间”设置，建议扩展为两组设置：
- `Progress Heartbeat`
- `Review Policy`

而不是把 review 时机硬塞进 heartbeat。

## 9) 实施建议（协议到实现）

Phase-1
- 为 project config 新增 `Project Autonomy Bundle` 和 `Supervisor Review Policy` 存储位。
- 顶部 UI 改成一个自治档位 + 一个 review policy 入口。

Phase-2
- 新增 `SupervisorReviewNoteStore` 与 `GuidanceInjectionStore`。
- 建立 `review -> note -> injection -> ack` 闭环。

Phase-3
- 为 `A2/A3/A4` 增加 `safe point` 检测与注入队列。
- `Supervisor` 只在 `safe point` 或 `stop_immediately` 时干预。

Phase-4
- 让 `A4` 在 `pre_high_risk_action` 与 `pre_done_summary` 前强制触发 deep review。
- 汇总最终交付并通知用户。

## 10) 结论

本协议冻结的核心不是“让 AI 权限更大”，而是：

- 每个 project 用一个清晰档位描述自治程度。
- supervisor 不再每一步同步审批，但始终拥有旁路 review 与纠偏能力。
- `A4` 不是无监督自动化，而是“高自治执行 + 高治理监督”。

只要这 3 点保持不变，系统就能同时做到：
- 自主推进
- 可纠偏
- 可审计
- 可随时 clamp / kill
