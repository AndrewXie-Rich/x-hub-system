# XT-W2-23/XT-W2-26 自动推进与用户介入等级实现子工单（Implementation Pack v1）

- version: v1.1
- updatedAt: 2026-03-03
- owner: XT-L2（Primary）/ XT-L1 / Hub-L3 / Hub-L5 / QA / AI-COORD-PRIMARY
- status: active
- scope: `XT-W2-23`, `XT-W2-26`（含 completion 接线 + auto-continue + 介入等级 + 创新分档 + 建议治理）
- parent:
  - `x-terminal/work-orders/xt-supervisor-multipool-adaptive-work-orders-v1.md`
  - `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## 0) 目标与边界

- 目标：让 Supervisor 能基于 heartbeat + 实时执行信号，自动判断 lane 完成并自动续推下一任务。
- 同时支持三档用户介入等级：
  - `zero_touch`（完全不介入）
  - `critical_touch`（仅关键点介入）
  - `guided_touch`（频繁介入）
- 同时支持创新分档（`L0..L4`）与建议治理模式（`supervisor_only|hybrid|lane_open`）：
  - `L0` 执行优先（不头脑风暴）
  - `L1` 微反思（默认）
  - `L2` 优化模式（堵塞/重复失败触发）
  - `L3` 战略创新（里程碑级）
  - `L4` 突破冲刺（实验周）
- 硬边界：高风险授权、不可逆动作、跨泳道契约变更必须可阻断，不得静默自动越权。

## 1) 介入等级定义（v2，含向后兼容）

### 1.1 模式定义

- `zero_touch`（推荐在稳定期使用）
  - 用户默认不被打断。
  - 仅以下事件触达：`high_risk_authorization_required`、`irreversible_action_required`、`policy_conflict_blocked`。
- `critical_touch`（默认）
  - 关键节点触达：提案确认（可选）、高风险授权、重规划裁决、发布前最终确认。
- `guided_touch`
  - 关键节点 + 高频进度通知（阶段完成、重试耗尽、跨池合并前后）。

### 1.2 向后兼容映射

- `hands_off -> zero_touch`
- `critical_only -> critical_touch`
- `interactive -> guided_touch`

解析规则：
- 配置传入旧值时自动映射到新值并写审计字段 `autonomy_mode_migrated_from`。
- 未识别值 fail-closed 到 `critical_touch`，并记录 `deny_code=invalid_autonomy_mode`。

### 1.3 创新分档（Innovation Level）

- `L0_execute_only`
  - 不执行头脑风暴，仅按工单推进与证据回填。
- `L1_micro_reflect`（默认）
  - 每关键步骤做一次 3 问自检（安全/效率/质量），仅允许 1 条微建议。
- `L2_optimize`
  - 阻塞或重复失败时，允许提交 1 个替代方案 + 量化收益预估。
- `L3_strategic`
  - 里程碑阶段执行竞品差异与优势强化评估，输出 adopt/reject 建议。
- `L4_breakthrough`
  - 创新冲刺档，允许 2~3 条候选路径并行验证，必须带收敛门与回滚点。

硬约束：
- 发布冻结窗自动降档到 `L0/L1`。
- `high_risk_without_grant=true` 时禁止提升到 `L3/L4`。

### 1.4 建议治理模式（Suggestion Governance）

- `supervisor_only`
  - 泳道不提建议，仅 Supervisor 输出建议；最低 token，创新密度最低。
- `hybrid`（默认）
  - 泳道触发式提交“微建议卡”，Supervisor 统一 triage 与对用户提案。
- `lane_open`
  - 泳道可主动提建议，Supervisor 仅做收敛；仅用于创新冲刺期。

触发式建议（hybrid/lane_open）：
- 同类失败连续 >=2 次；
- 阻塞链 >20 分钟；
- 预计 token 节省 >=15%；
- 预计质量提升 >=10%；
- 命中安全红线风险。

## 2) 实现契约（machine-readable）

### 2.1 Runtime 配置契约

```json
{
  "autonomy_mode": "critical_touch",
  "innovation_level": "L1_micro_reflect",
  "suggestion_governance_mode": "hybrid",
  "auto_continue_enabled": true,
  "touch_policy": {
    "notify_on_lane_completed": false,
    "notify_on_pool_completed": true,
    "notify_on_global_merge_ready": true,
    "max_noncritical_notifications_per_hour": 6
  },
  "safety_policy": {
    "high_risk_without_grant": "block",
    "irreversible_without_ack": "block",
    "contract_change_without_coord_decision": "block"
  },
  "innovation_policy": {
    "allow_brainstorm": true,
    "brainstorm_trigger_mode": "event_driven_only",
    "max_suggestion_cards_per_lane_per_4h": 2,
    "require_quantified_impact": true
  }
}
```

### 2.2 Completion 信号契约

```json
{
  "event_type": "supervisor.lane.completion.detected",
  "lane_id": "lane-auth-01",
  "task_id": "uuid",
  "project_id": "uuid",
  "completion_source": "runtime_status|tool_result|mergeback_gate",
  "detected_at_ms": 0,
  "confidence": 1.0
}
```

### 2.3 Auto-Continue 决策契约

```json
{
  "event_type": "supervisor.autocontinue.decision",
  "lane_id": "lane-auth-01",
  "task_id": "uuid",
  "decision": "continue_current|claim_next|blocked_wait_dependency|notify_user",
  "reason_code": "dependency_not_ready",
  "next_task_id": "XT-W2-24",
  "autonomy_mode": "critical_touch",
  "audit_ref": "audit-xxxx"
}
```

### 2.4 建议卡契约（Lane Insight Card）

```json
{
  "insight_id": "INS-XT-L1-20260303-001",
  "from_lane": "XT-L1",
  "task_context": "SKC-W2-05",
  "category": "security|efficiency|quality|token|reliability",
  "problem_statement": "...",
  "proposal": "...",
  "expected_impact": {
    "metric": "token_per_notification_p95_delta",
    "target_delta": -0.18
  },
  "risk_level": "low|medium|high",
  "adoption_scope": "lane_local|cross_lane|global_policy",
  "requires_user_decision": false,
  "status": "proposed|triaged|adopted|rejected|parked"
}
```

## 3) 状态机（实现级）

`running -> completion_detected -> lane_completed -> evaluate_autocontinue -> (claim_next | blocked_wait_dependency | notify_user)`

补充分支：
- `running -> blocked`（grant/dependency/runtime）
- `blocked -> recovering -> running`（自动恢复或人工解锁）
- `lane_completed -> mergeback_gate_failed -> blocked_wait_fix`

硬约束：
- `high_risk && grant_missing` 时，禁止进入 `claim_next`。
- `gate=FAIL|INSUFFICIENT_EVIDENCE` 时，禁止写 `closed`。

## 4) 实现子工单拆分（可直接派发）

### 4.1 `XT-W2-23-A` 介入等级策略引擎 v2

- owner: `XT-L1`（Primary）+ `XT-L2`
- 目标：把三档介入策略变成统一判定器，并提供旧值兼容。
- 代码落点：
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/Task.swift`（必要时扩展 metadata 字段）
- 步骤：
  1. 新增 `AutonomyMode` 枚举与兼容解析器。
  2. 新增 `TouchpointPolicyEvaluator`（输入事件类型，输出是否触达用户）。
  3. 加入 fail-closed 默认值（无效模式强制 `critical_touch`）。
  4. 输出机读报告：`build/reports/xt_w2_23_a_autonomy_policy_evidence.v1.json`。
- DoD：
  - 新旧模式值均可被稳定解析。
  - 三档触达差异可测试验证。
- Gate/KPI：
  - Gate: `XT-MP-G3`
  - KPI: `autonomy_mode_parse_success_rate = 100%`
- 回归：
  - 传入非法模式值 -> 自动降到 `critical_touch` + 审计。
  - `zero_touch` 下非关键事件误通知 -> 失败。

### 4.2 `XT-W2-26-A` Completion Signal Adapter（完成信号接线）

- owner: `XT-L2`（Primary）+ `Hub-L3`
- 目标：把“AI 已完成输入/执行完成”转为可机判 completion 事件。
- 代码落点：
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `x-terminal/Sources/Event/AXEventBus.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- 步骤：
  1. 新增 completion 检测器（runtime 状态、task status、mergeback gate 结果三源合并）。
  2. 统一发布 `supervisor.lane.completion.detected` 事件。
  3. 事件去重（lane_id + task_id + completion_epoch）防重复推进。
  4. 输出机读报告：`build/reports/xt_w2_26_a_completion_adapter_evidence.v1.json`。
- DoD：
  - 完成事件可在 <=2s 内被检测并落盘。
  - 重复事件不会触发重复 claim。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G4`
  - KPI: `completion_detect_latency_p95_ms <= 2000`, `duplicate_completion_actions = 0`
- 回归：
  - 同一 lane 重复完成事件 -> 只处理一次。
  - completion 误判（实际未完成）-> 必须被回滚并审计。

### 4.3 `XT-W2-26-B` Auto-Continue 执行器（自动领下一单）

- owner: `XT-L2`（Primary）+ `AI-COORD-PRIMARY`
- 目标：完成当前任务后自动判断依赖并推进 backlog_next。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorOrchestrator.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `docs/memory-new/xhub-lane-command-board-v2.md`（仅机读导出/同步字段，不改跨泳道内容规则）
- 步骤：
  1. 实现 `AutoContinueExecutor.evaluateAndAct(...)`。
  2. 决策分支：`continue_current|claim_next|blocked_wait_dependency|notify_user`。
  3. 自动写入 claim 元信息（`claim_id + claim_ttl_until`）。
  4. 绑定依赖检查与 Gate 检查（不满足则 fail-closed blocked）。
  5. 输出机读报告：`build/reports/xt_w2_26_b_autocontinue_evidence.v1.json`。
- DoD：
  - completion 后可自动推进下一任务（依赖满足时）。
  - 依赖未满足必写 blocked 信息（含 unblock_owner）。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G4`
  - KPI: `autocontinue_success_rate >= 90%`, `wrong_autoclaim_incidents = 0`
- 回归：
  - 依赖未满足仍 claim_next -> 失败。
  - claim TTL 缺失 -> 失败。

### 4.4 `XT-W2-26-C` 自适应指导与通知路由器

- owner: `XT-L1`（Primary）+ `XT-L2` + `QA`
- 目标：像“总控指导语”那样自动生成下一步指导，并按介入等级路由给用户或仅落盘。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - `x-terminal/Sources/Supervisor/PromptFactory.swift`
- 步骤：
  1. 实现 `GuidanceComposer`（读取 incident + gate + backlog 输出指导语）。
  2. 路由规则接入三档介入等级（zero/critical/guided）。
  3. 接入通知去重与频率限制（避免 guided_touch 通知风暴）。
  4. 输出机读报告：`build/reports/xt_w2_26_c_guidance_router_evidence.v1.json`。
- DoD：
  - 同一事件不重复刷屏。
  - zero_touch 不输出非关键通知；guided_touch 能持续引导。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G5`
  - KPI: `critical_notify_latency_p95_ms <= 1500`, `notification_dedup_hit_rate >= 95%`
- 回归：
  - zero_touch 下普通进度通知出现 -> 失败。
  - guided_touch 下关键失败未通知 -> 失败。

### 4.5 `XT-W2-23-B` 创新分档引擎 + UI 选择器

- owner: `XT-L1`（Primary）+ `XT-L2` + `QA`
- 目标：在 UI 中提供 `L0..L4` 可选档位，并把档位规则接入 Supervisor 执行策略。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
- 步骤：
  1. 新增 `InnovationLevel` 枚举（L0/L1/L2/L3/L4）与默认值 `L1_micro_reflect`。
  2. 在 UI 增加档位选择组件与说明文案（包含冻结窗降档提示）。
  3. 将档位映射到执行策略（是否允许建议、建议频率、是否允许实验分支）。
  4. 事件审计：`supervisor.innovation_level.changed`。
  5. 输出机读报告：`build/reports/xt_w2_23_b_innovation_level_ui_evidence.v1.json`。
- DoD：
  - UI 可切换五档且状态持久化。
  - 冻结窗进入时自动降档生效并有审计记录。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G5`
  - KPI: `innovation_level_apply_success_rate = 100%`, `freeze_window_forced_downgrade_miss = 0`
- 回归：
  - UI 选择无效值仍放行 -> 失败。
  - 冻结窗未自动降档 -> 失败。

### 4.6 `XT-W2-23-C` 建议治理路由器（Supervisor-only/Hybrid/Lane-open）

- owner: `XT-L2`（Primary）+ `AI-COORD-PRIMARY` + `Hub-L5`
- 目标：把“谁提建议、何时提、谁裁决”变成可机判策略，避免 token 噪音。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorOrchestrator.swift`
  - `docs/memory-new/xhub-lane-command-board-v2.md`（Insight Outbox/Inbox 字段对齐）
- 步骤：
  1. 实现 `SuggestionGovernanceEvaluator`（三模式判定）。
  2. 接入触发器（重复失败/长阻塞/token收益/质量收益/安全风险）。
  3. 限流策略：每 lane 每 4h 建议卡上限；超额自动 parked。
  4. 统一 triage 输出到 Supervisor Insight Inbox（adopt/reject/park + reason）。
  5. 输出机读报告：`build/reports/xt_w2_23_c_suggestion_governance_evidence.v1.json`。
- DoD：
  - `hybrid` 模式下，泳道建议只在触发条件命中时产生。
  - 需要用户决策的建议自动标记并升级。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G5`
  - KPI: `suggestion_noise_ratio <= 0.20`, `high_value_suggestion_adoption_rate >= 0.60`, `suggestion_token_overhead_ratio <= 0.08`
- 回归：
  - supervisor_only 下泳道仍写建议 -> 失败。
  - hybrid 下无触发条件却大量建议 -> 失败。
  - requires_user_decision=true 未升级用户 -> 失败。

## 5) 测试计划（实现级）

### 5.1 单测

- `swift test --filter AutonomyModePolicyTests`
- `swift test --filter CompletionSignalAdapterTests`
- `swift test --filter AutoContinueExecutorTests`
- `swift test --filter GuidanceRouterTests`
- `swift test --filter InnovationLevelSelectorTests`
- `swift test --filter SuggestionGovernanceRouterTests`

### 5.2 集成

- `swift test --filter SupervisorIncidentExportTests`
- `swift test --filter HighRiskGrantGateTests`
- `swift test --filter SupervisorDoctorTests`

### 5.3 回归场景（最小必跑）

1. completion 实时触发：
   - lane 完成后 2 秒内生成 `completion.detected` + `autocontinue.decision`。
2. 依赖阻塞：
   - completion 后依赖未满足，必须写 `blocked_wait_dependency`，不得 claim_next。
3. 高风险授权：
   - 无 grant 的 high-risk lane，任何模式都不得自动推进。
4. 三档介入差异：
   - zero_touch 无非关键通知；
   - critical_touch 关键点通知完整；
   - guided_touch 通知频率受限且不漏关键失败。

## 6) Gate / KPI / 发布条件

- 通过 Gate：
  - `XT-MP-G3`（自治安全）
  - `XT-MP-G4`（集成可回滚）
  - `XT-MP-G5`（交付通知质量）
- 关键 KPI：
  - `completion_detect_latency_p95_ms <= 2000`
- `autocontinue_success_rate >= 90%`
- `high_risk_lane_without_grant = 0`
- `wrong_autoclaim_incidents = 0`
- `user_interrupt_rate(zero_touch) <= 0.10`
- `suggestion_noise_ratio <= 0.20`
- `suggestion_token_overhead_ratio <= 0.08`

## 7) 回滚点与开关

- feature flags：
  - `XT_AUTOCONTINUE_EXECUTOR_V1`
  - `XT_AUTONOMY_MODE_V2`
  - `XT_GUIDANCE_ROUTER_V1`
  - `XT_INNOVATION_LEVEL_SELECTOR_V1`
  - `XT_SUGGESTION_GOVERNANCE_ROUTER_V1`
- rollback：
  - 若出现错领任务或越权通知，立即关闭 `XT_AUTOCONTINUE_EXECUTOR_V1` 并回退到仅提示模式。
  - 若出现模式解析异常，强制回退 `critical_touch`（fail-closed）。

## 8) 泳道 AI 派发模板（可直接复制）

```text
任务：<XT-W2-23-A | XT-W2-26-A | XT-W2-26-B | XT-W2-26-C>
读序：
1) docs/memory-new/xhub-lane-command-board-v2.md
2) x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md
3) x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md

执行规则：
- 先 claim_id + claim_ttl_until（4h）
- 只改本泳道分区
- delivered 必交 7件套（含 Gate 证据路径 + KPI 报告路径）
- 依赖不满足时 fail-closed 落盘 blocked_reason + unblock_owner
```
