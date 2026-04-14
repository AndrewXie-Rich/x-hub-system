# XT-W3-32 Supervisor Skill Orchestration + Governed Event Loop 实施包

- version: v1.0
- updatedAt: 2026-03-11
- owner: XT-L2（Primary）/ Hub-L5 / Security / QA / Product
- status: planned
- scope: `XT-W3-32`（把 Supervisor 从“只会看 portfolio 和分配模型”的高智商 PM，升级成“可调用 skills / 可维护 job-plan / 可消费事件回调 / 可写回记忆”的受治理控制平面）
- parent:
  - `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## 0) 为什么要单独开这份包

当前系统已经有两个很强的基础：

- `XT-W3-30` 正在补执行面，解决 browser runtime / external trigger / connector action / runtime-surface policy / extension bridge 的“手和脚”问题。
- `XT-W3-31` 已经把 Supervisor 的 portfolio / capsule / action feed 做成机读结构，解决“看见哪些项目、哪些阻塞、哪些需要授权”的问题。

但从真实 Supervisor 体验看，还存在一个单独的大缺口：

- Supervisor 现在能看、能想、能总结、能分配模型，
- 但还不能自然地下“结构化执行指令”，也不能把 skill 执行回调闭环成持续编排。

当前现实状态更接近：

- “高智商 PM / Tech Lead”

而不是：

- “受治理的 OpenClaw 式 workflow orchestrator”

根因不是模型不够强，而是控制平面仍然过窄：

1. Action Protocol 目前只支持：
   - `CREATE_PROJECT`
   - `ASSIGN_MODEL`
   - `ASSIGN_MODEL_ALL`
2. Supervisor 看得到 portfolio，但看不到 project-scoped skill registry 和可执行 side-effect 面。
3. Task / plan / step 还没有和 memory 的 canonical / observations / raw evidence 形成稳定写回闭环。
4. skill 执行完成/失败后，还没有稳定回调到 Supervisor 自动开下一轮推理。
5. 用户可调自治档位、Hub clamp、项目高风险授权，尚未形成一套专门面向 Supervisor 的 orchestration policy surface。

所以 `XT-W3-32` 的定位很明确：

- 它不是再造一个更聪明的 Supervisor。
- 它是把 Supervisor 接到 skills、job-plan 状态机、事件回路、策略门禁上。

换句话说：

- `XT-W3-30` 负责“可执行的手脚”
- `XT-W3-31` 负责“可见的全局视野”
- `XT-W3-32` 负责“神经通路和控制回路”

三者合起来，才是接近 OpenClaw 级别的真正主线。

## 1) 当前已验证基线

以下内容已经存在，可直接复用，不应重复造轮子：

### 1.1 Supervisor 的当前控制平面

- `SupervisorSystemPromptBuilder.swift` 已有 Action Protocol 段落，但仅暴露：
  - `[CREATE_PROJECT]`
  - `[ASSIGN_MODEL]`
  - `[ASSIGN_MODEL_ALL]`
- `SupervisorManager.swift` 已有 action tag 解析、冲突裁决、action ledger、结果回写。

这说明：

- “结构化 tag -> 本地执行 -> ledger/audit” 这条路已经有骨架。
- 缺的不是机制，而是动作种类和执行后端太少。

### 1.2 Supervisor 的当前视野与事件基础

- `SupervisorPortfolioSnapshot.swift`
- `SupervisorProjectCapsule.swift`
- `SupervisorProjectActionCanonicalSync.swift`
- `SupervisorPortfolioSnapshotCanonicalSync.swift`
- `xt-w3-31` 工单

已经冻结了这些事实：

- Supervisor 默认看 portfolio snapshot
- 项目动作变化以 delta feed 形式上送
- 默认摘要优先，不广播全文
- drill-down 必须 scope-safe

这意味着：

- `XT-W3-32` 无需重建 portfolio。
- 只需要在现有 portfolio/action feed 上叠加“可执行动作 + 执行结果回流”。

### 1.3 自动化 runtime 与调度骨架已经存在

- `XTAutomationRunCoordinator.swift`
- `XTAutomationRunExecutor.swift`
- `XTAutomationRuntimePolicy.swift`
- `TaskDecomposition/ExecutionMonitor.swift`
- `TaskDecomposer.swift`
- `TaskAssigner.swift`

这说明：

- 运行协调器、checkpoint、incident、heartbeat、retry、run lineage 都已有基础。
- `XT-W3-32` 应优先把 Supervisor actions 映射到这些已存在的 runtime，而不是再造第三套 orchestration runtime。

### 1.4 Skills 与 Hub 治理基础已经存在

- Hub skills store / manifest / resolved skills
- skills signing / distribution / runner 规范
- capability grant chain contract
- Hub-first memory + constitution + grants + kill-switch

这意味着：

- skill registry / capability metadata / risk metadata 的真相源应该继续在 Hub。
- Supervisor 只消费 scope-safe、policy-filtered、project-allowed 的 skill registry 视图。

## 2) 北极星目标

`XT-W3-32` 的目标不是“允许 Supervisor 任意 shell”。

目标是让它具备下面这条受治理闭环：

1. Supervisor 能看到当前项目可用的 skills / adapters / runtime 能力，而不是只能凭空建议。
2. Supervisor 能维护结构化 `job -> plan -> step`，而不是只输出自然语言“下一步建议”。
3. Supervisor 能发起受治理的 `CALL_SKILL` 或 `launch_run` 级动作。
4. skill 执行状态变化能回流成 machine-readable event delta，而不是只存在某个角落日志里。
5. 执行结果能写回 memory：
   - L1 Canonical：job / plan / current status
   - L2 Observations：skill_result / plan_transition / incident
   - L4 Raw Evidence：大输出 / 日志 / trace / tool result
6. 心跳、skill callback、incident、external trigger 都能触发 Supervisor 自动开下一轮，而不是只能靠用户输入“继续”。
7. 高风险动作继续遵守：
   - Hub grant
   - project governance bundle
   - A-Tier / runtime-surface clamp
   - constitution / injection defense
   - audit / kill-switch

## 3) 固定决策

### 3.1 真相源

- Hub 继续是：
  - skill registry 真相源
  - grant / policy / audit 真相源
  - canonical memory 真相源
- XT 允许本地短 TTL cache，但不得把本地 cache 冒充长期主权。

### 3.2 Action Protocol 只扩展，不推翻

- 现有：
  - `CREATE_PROJECT`
  - `ASSIGN_MODEL`
  - `ASSIGN_MODEL_ALL`
  必须保持兼容。
- 新动作必须增量加入，不允许一次性推翻当前 prompt / parser / tests。

### 3.3 Supervisor 不直接拿“裸 shell 主权”

- Supervisor 不新增“任意命令直跑”这类未治理通道。
- 所有执行动作都要落成：
  - skill call
  - governed lane launch
  - recipe run launch
  - plan/job mutation

也就是说：

- 把“自由 shell”变成“受治理 skill surface”
- 而不是绕过 Hub / grant / audit

### 3.4 记忆写回分层

- L0：继续固定注入 constitution / policy hard lines
- L1 Canonical：存 job / plan / current owner / authoritative status
- L2 Observations：存运行中的事件 delta、step state changes、skill result summary
- L3 Working Set：只保留当前关注的 job、pending approvals、recent hot events
- L4 Raw Evidence：存长日志、skill 原始输出、失败 trace、大型 artifacts refs

### 3.5 自动回合触发源

Supervisor 不再只在用户聊天时工作。

允许触发它的回合源至少包括：

- `user_turn`
- `heartbeat`
- `skill_callback`
- `incident`
- `external_trigger_ingress`
- `grant_resolution`

但所有自动回合必须：

- 带上 trigger source
- 带上 project scope
- 带上 policy verdict
- 失败时 fail-closed

### 3.6 与现有项目治理策略的关系

- `XT-W3-30-D` 的项目治理策略继续约束：
  - device
  - browser
  - connector
  - extension
- `XT-W3-32` 额外增加的是 Supervisor orchestration 层的策略，不取代项目治理策略。

二者关系：

- `project governance bundle` 决定“某类执行面能不能跑”
- `supervisor orchestration policy` 决定“Supervisor 能不能自动下这种动作”

## 4) 机读契约冻结

### 4.1 `xt.supervisor_action_protocol.v2`

在保留现有三个 tag 的同时，新增四个动作：

```text
[CREATE_JOB]{...json...}[/CREATE_JOB]
[UPSERT_PLAN]{...json...}[/UPSERT_PLAN]
[CALL_SKILL]{...json...}[/CALL_SKILL]
[CANCEL_SKILL]{...json...}[/CANCEL_SKILL]
```

约束：

- 旧 tag 继续用现有简洁格式，保持兼容。
- 新 tag 一律使用 JSON body，避免多级参数靠 `|` 分隔后无法表达嵌套 payload。
- tag body 必须是单对象 JSON；校验失败必须 fail-closed。
- 非明确执行意图或非允许的自动回合，不得发 action tags。

示例：

```json
{
  "schema_version": "xt.supervisor_action_protocol.v2",
  "supported_tags": [
    "CREATE_PROJECT",
    "ASSIGN_MODEL",
    "ASSIGN_MODEL_ALL",
    "CREATE_JOB",
    "UPSERT_PLAN",
    "CALL_SKILL",
    "CANCEL_SKILL"
  ],
  "json_body_tags": [
    "CREATE_JOB",
    "UPSERT_PLAN",
    "CALL_SKILL",
    "CANCEL_SKILL"
  ],
  "requires_explicit_execution_intent": true,
  "allows_non_user_round_actions": true,
  "non_user_round_sources": [
    "heartbeat",
    "skill_callback",
    "incident",
    "external_trigger_ingress",
    "grant_resolution"
  ]
}
```

### 4.2 `xt.supervisor_skill_registry_view.v1`

这是 Supervisor 能看到的 project-scoped skill registry 视图，不是全量 raw registry。

```json
{
  "schema_version": "xt.supervisor_skill_registry_view.v1",
  "project_id": "project_alpha",
  "updated_at_ms": 1760000000000,
  "memory_source": "hub_skill_registry",
  "items": [
    {
      "skill_id": "repo.git.status",
      "display_name": "Git Status",
      "description": "Read git working tree status for the active project.",
      "input_schema_ref": "schema://repo.git.status.input",
      "output_schema_ref": "schema://repo.git.status.output",
      "side_effect_class": "read_only",
      "risk_level": "low",
      "requires_grant": false,
      "policy_scope": "project",
      "timeout_ms": 30000,
      "max_retries": 1,
      "available": true
    }
  ],
  "audit_ref": "audit-xt-w3-32-skill-registry"
}
```

### 4.3 `xt.supervisor_job.v1`

```json
{
  "schema_version": "xt.supervisor_job.v1",
  "job_id": "job-20260311-001",
  "project_id": "project_alpha",
  "goal": "Repair failing browser runtime smoke and re-run evidence capture",
  "priority": "critical|high|normal|low",
  "status": "queued|planning|running|blocked|awaiting_authorization|completed|failed|canceled",
  "source": "user|supervisor|heartbeat|external_trigger|incident",
  "current_owner": "supervisor",
  "active_plan_id": "plan-20260311-001",
  "created_at_ms": 1760000000000,
  "updated_at_ms": 1760000005000,
  "audit_ref": "audit-xt-w3-32-job"
}
```

### 4.4 `xt.supervisor_plan_step.v1`

```json
{
  "schema_version": "xt.supervisor_plan_step.v1",
  "plan_id": "plan-20260311-001",
  "step_id": "step-003",
  "job_id": "job-20260311-001",
  "kind": "call_skill|launch_run|await_event|ask_user|write_memory|notify_user",
  "title": "Run browser runtime smoke",
  "status": "queued|running|blocked|awaiting_authorization|completed|failed|skipped|canceled",
  "depends_on": ["step-001", "step-002"],
  "attempt_count": 0,
  "max_attempts": 2,
  "payload_ref": "memory://project_alpha/jobs/job-20260311-001/steps/step-003/payload.json",
  "result_ref": "",
  "updated_at_ms": 1760000000000
}
```

### 4.5 `xt.supervisor_skill_call_record.v1`

```json
{
  "schema_version": "xt.supervisor_skill_call_record.v1",
  "request_id": "call-20260311-001",
  "project_id": "project_alpha",
  "job_id": "job-20260311-001",
  "step_id": "step-003",
  "skill_id": "browser.runtime.smoke",
  "dispatch_mode": "sync|async",
  "status": "queued|running|succeeded|failed|canceled|denied",
  "input_ref": "memory://project_alpha/skill_calls/call-20260311-001/input.json",
  "output_ref": "memory://project_alpha/skill_calls/call-20260311-001/output.json",
  "deny_code": "",
  "grant_id": "",
  "policy_ref": "policy://project_alpha/supervisor_orchestration",
  "audit_ref": "audit-xt-w3-32-call-001",
  "created_at_ms": 1760000000000,
  "updated_at_ms": 1760000003000
}
```

### 4.6 `xt.supervisor_event_delta.v1`

```json
{
  "schema_version": "xt.supervisor_event_delta.v1",
  "event_id": "evt-20260311-001",
  "project_id": "project_alpha",
  "job_id": "job-20260311-001",
  "step_id": "step-003",
  "event_type": "skill_result|job_state_changed|plan_state_changed|incident|grant_waiting|grant_resolved|memory_refreshed",
  "severity": "silent_log|badge_only|brief_card|interrupt_now|authorization_required",
  "summary": "browser.runtime.smoke failed with deny_code=bridge_disabled",
  "why_it_matters": "The active recovery job cannot progress until Hub route recovers.",
  "next_action": "replan or ask for reconnect approval",
  "refs": [
    "memory://project_alpha/skill_calls/call-20260311-001/output.json"
  ],
  "occurred_at_ms": 1760000004000,
  "audit_ref": "audit-xt-w3-32-event-001"
}
```

### 4.7 `xt.supervisor_orchestration_policy.v1`

```json
{
  "schema_version": "xt.supervisor_orchestration_policy.v1",
  "project_id": "project_alpha",
  "mode": "suggest_only|guided_auto|governed_auto",
  "memory_mode": "hub_preferred|hub_required|local_only",
  "allow_non_user_round_dispatch": true,
  "max_parallel_skill_calls": 2,
  "auto_dispatch_risk_ceiling": "medium",
  "require_user_confirmation_for": [
    "connector_actions.high",
    "repo_write.production",
    "device_tools.high"
  ],
  "blocked_skill_groups": [
    "unreviewed_plugins"
  ],
  "ttl_sec": 3600,
  "hub_override_mode": "none|clamp_guided|clamp_manual|kill_switch",
  "updated_at_ms": 1760000000000,
  "audit_ref": "audit-xt-w3-32-policy"
}
```

## 5) 分层推进

### 5.1 P0：先打通可执行控制平面

- `XT-W3-32-A` Action Protocol v2 + command processor
- `XT-W3-32-B` Project-scoped skill registry view
- `XT-W3-32-C` Job / Plan canonical state machine
- `XT-W3-32-D` Governed skill dispatch + callback event loop

### 5.2 P1：补齐策略、治理与外部 adapter 编排

- `XT-W3-32-E` Supervisor orchestration policy surface
- `XT-W3-32-F` External adapter orchestration graduation
- `XT-W3-32-G` Require-real orchestrator parity harness

## 6) Gate / KPI

### 6.1 Gate

- `XT-SO-G0`: `Action Protocol v2 + job/plan/event/policy` 契约冻结
- `XT-SO-G1`: Supervisor 能看到 project-scoped skill registry，且信息来自 Hub truth source
- `XT-SO-G2`: `CREATE_JOB / UPSERT_PLAN / CALL_SKILL / CANCEL_SKILL` parser + guard + ledger 全绿
- `XT-SO-G3`: skill dispatch 走受治理主链（policy -> grant -> execute -> audit -> callback）
- `XT-SO-G4`: job / plan / event 回写到 `L1/L2/L4`，无 orphan record
- `XT-SO-G5`: 心跳 / callback / incident 能自动触发 Supervisor 下一轮且不越权
- `XT-SO-G6`: require-real 样本证明“Supervisor 不只会建议，而是真的能闭环 orchestrate”

### 6.2 KPI

- `supervisor_action_parse_failure_rate <= 0.5%`
- `project_scoped_skill_registry_freshness_p95_sec <= 15`
- `orphan_skill_call_records = 0`
- `job_plan_memory_write_coverage = 100%`
- `callback_to_supervisor_round_p95_ms <= 2500`
- `unaudited_supervisor_skill_call = 0`
- `high_risk_supervisor_dispatch_without_authorization = 0`

## 7) 详细工单

### 7.1 `XT-W3-32` Supervisor Skill Orchestration + Governed Event Loop

- 目标：把 Supervisor 升级为受治理 workflow orchestrator，而不是停留在“看 portfolio + 给建议 + 分配模型”。
- 交付物：`build/reports/xt_w3_32_supervisor_orchestrator_evidence.v1.json`
- DoD:
  - `XT-W3-32-A..G` 的核心链路全部过 gate。
  - `XT-W3-30` 与 `XT-W3-31` 的 execution-plane / visibility-plane 可被 `XT-W3-32` 真实调用，不再只是平行存在。
  - 最终口径清晰：
    - `XT-W3-30 = hands/feet`
    - `XT-W3-31 = eyes/dashboard`
    - `XT-W3-32 = nerves/control loop`

### 7.2 `XT-W3-32-A` Action Protocol v2 + Command Processor

- 优先级：`P0`
- 目标：把 Supervisor 的动作标签从 3 个扩展到可实际驱动编排的最小集合。
- 推荐代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorSystemPromptBuilder.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Tests/SupervisorSystemPromptBuilderTests.swift`
  - `x-terminal/Tests/SupervisorCommandGuardTests.swift`
- 实施步骤：
  1. 冻结 `xt.supervisor_action_protocol.v2`
  2. 新增 JSON-body tag parser：
     - `CREATE_JOB`
     - `UPSERT_PLAN`
     - `CALL_SKILL`
     - `CANCEL_SKILL`
  3. 将 action guard 从“只看用户显式创建项目/分配模型”扩展为：
     - 显式用户执行意图
     - 明确允许的非用户自动回合
  4. 统一写入 action ledger，并在每个动作上记录：
     - `trigger_source`
     - `project_scope`
     - `policy_verdict`
     - `verified_at`
- 验收指标：
  - 新旧 tags 兼容通过率 `= 100%`
  - 非法 JSON body 解析失败必须 fail-closed
- 回归样例：
  - 普通聊天输出 `[CALL_SKILL]` -> 必须被 guard 去掉
  - callback round 合法发出 `CALL_SKILL` -> 允许执行
  - 同一回合冲突 tag -> 必须有 deterministic 裁决和 ledger 记录

### 7.3 `XT-W3-32-B` Project-Scoped Skill Registry View

- 优先级：`P0`
- 目标：让 Supervisor 真正知道“这个项目当前能用什么 skill”，而不是只会建议别人去做。
- 推荐代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Supervisor/MemoryUXAdapter.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- 实施步骤：
  1. Hub 导出 Supervisor 可消费的 project-scoped registry view
  2. 按 project policy / user policy / hub clamp 过滤不可见或不可用技能
  3. 向 Supervisor memory 注入：
     - available skills
     - risk level
     - requires_grant
     - timeout / retry hints
  4. UI 补充“Supervisor 可用技能”摘要视图
- 验收指标：
  - Supervisor 命中不存在 skill 的 hallucination rate 显著下降
  - registry freshness `p95 <= 15s`
- 回归样例：
  - revoked skill 不得继续出现在可用列表
  - high-risk skill 必须显示 `requires_grant=true`
  - 跨 project skill 泄漏必须 fail-closed

### 7.4 `XT-W3-32-C` Job / Plan Canonical State Machine

- 优先级：`P0`
- 目标：把“下一步建议”升级成结构化 `job -> plan -> step`，并写回 Hub memory。
- 推荐代码落点：
  - `x-terminal/Sources/Supervisor/TaskDecomposition/`
  - `x-terminal/Sources/Supervisor/XTAutomationRunCoordinator.swift`
  - `x-terminal/Sources/Supervisor/SupervisorProjectActionCanonicalSync.swift`
  - `x-terminal/Sources/Supervisor/SupervisorPortfolioSnapshotCanonicalSync.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- 实施步骤：
  1. 冻结 `xt.supervisor_job.v1` / `xt.supervisor_plan_step.v1`
  2. 为 active project 建立 authoritative current job
  3. 将 plan step 与现有：
     - task decomposition
     - automation run
     - incident / heartbeat
     做映射
  4. 回写 memory：
     - L1：job / active plan / step status
     - L2：状态转移事件
     - L4：payload / output / trace refs
- 验收指标：
  - `job_plan_memory_write_coverage = 100%`
  - `orphan_step_records = 0`
- 回归样例：
  - skill result 成功后 step 未转 completed -> fail
  - canceled run 仍保持 running -> fail
  - project 切换后把别的项目 job 写进当前 scope -> fail

### 7.5 `XT-W3-32-D` Governed Skill Dispatch + Callback Event Loop

- 优先级：`P0`
- 目标：让 Supervisor 发出的动作真正调用 runtime，并在结果回来后自动继续下一轮。
- 推荐代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRunExecutor.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
- 实施步骤：
  1. 将 `CALL_SKILL` 路由到：
     - Hub skill runner
     - XT governed runtime
     - automation run launcher
  2. 每次 dispatch 产出 `xt.supervisor_skill_call_record.v1`
  3. 执行完成/失败/deny 后产出 `xt.supervisor_event_delta.v1`
  4. callback event 满足策略时，自动触发 Supervisor 新回合
  5. 保持 fail-closed：
     - missing grant
     - stale memory when high risk
     - policy deny
     - unknown skill
- 验收指标：
  - `callback_to_supervisor_round_p95_ms <= 2500`
  - `unaudited_supervisor_skill_call = 0`
- 回归样例：
  - skill fail 后 Supervisor 自动 replan
  - grant pending 后 Supervisor 转 `awaiting_authorization`
  - callback 回到错误 project scope -> 必须 deny

### 7.6 `XT-W3-32-E` Supervisor Orchestration Policy Surface

- 优先级：`P1`
- 目标：给用户和 Hub 一套专门限制 Supervisor 自动编排的可视化策略面。
- 推荐代码落点：
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/UI/SupervisorSettingsView.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRuntimePolicy.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- 实施步骤：
  1. 冻结 `xt.supervisor_orchestration_policy.v1`
  2. XT 侧提供用户滑块 / picker：
     - `suggest_only`
     - `guided_auto`
     - `governed_auto`
  3. Hub 侧保留 clamp / kill-switch / policy override
  4. 高风险 skill 组支持：
     - always confirm
     - project allowlist
     - repo path / branch / environment allowlist
- 验收指标：
  - policy drift `= 0`
  - high-risk auto dispatch without confirmation `= 0`
- 回归样例：
  - user 设 `suggest_only` 后 callback round 不得自动 dispatch
  - Hub kill-switch 开启后 Supervisor 所有 auto dispatch 必须 fail-closed
  - project A 放开策略不得泄漏到 project B

### 7.7 `XT-W3-32-F` External Adapter Orchestration Graduation

- 优先级：`P1`
- 目标：把 GitHub / CI / Issue / Email / Browser 这类外部系统统一收敛成 skill adapters，而不是一堆特例。
- 实施步骤：
  1. 统一 adapter manifest / skill metadata
  2. 每类外部 side effect 映射到 capability + grant + audit
  3. 先接入最有价值的三类：
     - repo / git workflow
     - CI status / rerun
     - issue create / comment / state update
  4. 邮件 / browser / connector 继续复用 `XT-W3-30` 执行面成果
- 验收指标：
  - external adapter actions 全部走 audited skill calls
  - 不再出现单点 hardcoded orchestrator branch
- 回归样例：
  - GitHub comment without grant -> deny
  - CI rerun result -> event delta -> Supervisor replan
  - Issue tracker unavailable -> fail-closed + fallback summary

### 7.8 `XT-W3-32-G` Require-Real Orchestrator Parity Harness

- 优先级：`P1`
- 目标：证明 Supervisor 已从“只会建议”升级到“能真实 orchestrate”。
- 建议样本：
  - `RR01` user_turn -> create_job -> upsert_plan -> call_skill(read-only) -> event callback -> complete
  - `RR02` heartbeat -> blocked project auto replan -> launch_run
  - `RR03` skill callback fail -> Supervisor 自动转 awaiting_authorization
  - `RR04` external trigger ingress -> governed auto dispatch -> delivery event
  - `RR05` multi-project burst -> scope-safe event loop
- 交付物：
  - `build/reports/xt_w3_32_require_real_capture_bundle.v1.json`
  - `build/reports/xt_w3_32_require_real_evidence.v1.json`
- 验收指标：
  - 5 个样本全部不是口头描述
  - 全部带：
    - action tags
    - call records
    - event deltas
    - memory writeback refs

## 8) 推荐代码落点总表

- Prompt / action protocol:
  - `x-terminal/Sources/Supervisor/SupervisorSystemPromptBuilder.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- Portfolio / memory bus:
  - `x-terminal/Sources/Supervisor/SupervisorPortfolioSnapshot.swift`
  - `x-terminal/Sources/Supervisor/MemoryUXAdapter.swift`
  - `x-terminal/Sources/Supervisor/SupervisorProjectActionCanonicalSync.swift`
- Runtime / orchestration:
  - `x-terminal/Sources/Supervisor/XTAutomationRunCoordinator.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRunExecutor.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
- Hub / skills:
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
- Policy / UI:
  - `x-terminal/Sources/UI/SupervisorSettingsView.swift`
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRuntimePolicy.swift`

## 9) 风险与防守线

### 9.1 最大风险

- 把“更会执行”误实现成“绕过治理”

这是硬禁止的。

### 9.2 典型错误实现

- 直接给 Supervisor 一个任意 `run_command`
- 不做 project-scoped skill filtering
- skill callback 回来后不校验 scope 就喂给 Supervisor
- 高风险 auto dispatch 不经过 Hub grant / memory recheck
- 把 raw evidence 全文广播给 portfolio

### 9.3 正确实现口径

- 所有能力都走 skill / runtime manifest
- 所有 side effect 都有 policy / grant / audit
- 所有 callback 都回写 `job / plan / event / evidence`
- 所有自动回合都带 trigger source + policy verdict
- 所有高风险动作都默认 fail-closed

## 10) 一句话推进顺序

如果按最短路径推进，顺序应固定为：

1. 先做 `XT-W3-32-A`
2. 再做 `XT-W3-32-B`
3. 立即接 `XT-W3-32-C`
4. 然后打通 `XT-W3-32-D`
5. 最后补 `XT-W3-32-E/F/G`

原因：

- 没有 action protocol，就没有动作入口。
- 没有 skill registry，就不知道 Supervisor 能调什么。
- 没有 job/plan，就无法把编排状态写进 memory。
- 没有 callback event loop，就仍然只能靠用户手动“继续”。
- policy / adapters / require-real 应在主链可跑后再收口，不应先把边角做满。
