# XT-W3-26 Supervisor 一次性接案 + 自适应泳池规划实现子工单包

- version: v1.0
- updatedAt: 2026-03-07
- owner: XT-L2（Primary）/ Hub-L5 / QA / AI-COORD-PRIMARY
- status: active
- scope: `XT-W3-26`（Supervisor One-Shot Intake + Adaptive Pool Planner）+ `XT-W3-26-A/B/C/D/E/F/G/H`
- parent:
  - `x-terminal/work-orders/xt-supervisor-multipool-adaptive-work-orders-v1.md`
  - `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-supervisor-rhythm-user-explainability-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## 0) 为什么要有这份包

当前 X-Terminal 已经具备 Supervisor 拆分、泳道执行、heartbeat 托管、grant 恢复、lane mergeback 等核心引擎，但还没有完成“用户只输入一个大任务，Supervisor 自动判断复杂度、自动决定 pool/lane、自动启动、自动跟踪阻塞、最后自动收口交付”的产品化闭环。

当前已存在但仍偏工程半成品的能力锚点：

- `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - 已有生成 split proposal 的入口。
  - 已有确认并启动 proposal 的入口。
  - 问题：入口仍偏手工操作，用户需要理解内部状态与按钮顺序。
- `x-terminal/Sources/Supervisor/SupervisorOrchestrator.swift`
  - 已有 proposal 生成、确认、执行的编排能力。
  - 问题：还缺 one-shot 状态机、自动确认策略、交付冻结闭环。
- `x-terminal/Sources/Supervisor/TaskDecomposition/TaskDecomposer.swift`
  - 已有任务拆解能力。
  - 问题：还未把拆解直接收敛到自适应 pool/lane 规划与 seat 预算。
- `x-terminal/Sources/Supervisor/IntakeAcceptanceContracts.swift`
  - 已有 intake manifest 与 pool 规划基础字段。
  - 问题：当前 pool 规划仍偏静态，主要还是 `supervisor-main` / `isolated-side-effects` 两池思维。
- `x-terminal/Sources/Supervisor/PoolIntegrationOrchestrator.swift`
  - 已有跨 pool 集成编排基础。
  - 问题：缺自动池数决策、池边界解释、阻塞再路由闭环。
- `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - 已有 heartbeat 与 auto-recovery。
  - 问题：还缺 blocker resolved 后的 directed continue baton。
- `x-terminal/Sources/Supervisor/CriticalPathSeatAllocator.swift`
  - 已有 Max-3 active lane 关键路径席位治理。
  - 问题：还未与 `conservative|balanced|aggressive` 和真实 pool/lane DAG 联动。
- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 当前更像聊天/命令入口。
  - 问题：还未打通成 one-shot intake 主链。

本包的目标不是重复已有拆分机制，而是把这些零散能力产品化成一个可默认启用的主路径。

## 1) 目标与硬边界

### 1.1 目标

- 用户在 Supervisor 主入口输入一个复杂任务后，系统自动完成：
  - 请求标准化
  - 复杂度评估
  - `pool -> lane` 自适应规划
  - 参与等级与分档决策
  - 安全可控的 auto-confirm / auto-launch
  - blocker 定向续推
  - 交付冻结与范围声明
- 支持 `zero_touch | critical_touch | guided_touch` 与 `L0..L4` 创新档协同决策。
- 支持 `conservative | balanced | aggressive` 拆分档位，但受安全与经济性预算硬约束。
- 让 Supervisor 对用户清楚解释“为什么这样拆、为什么现在推进或暂停、下一步由谁执行”。

### 1.2 硬边界

- 不允许在无 grant / 无 policy / 无 audit 的情况下自动启动高风险副作用。
- 不允许为了“自动化体验”而绕过 `fail-closed` 与 `validated-mainline-only` 口径。
- 不允许激进拆分造成 lane 爆炸且无 seat/budget 治理。
- 不允许 blocker resolved 后靠全局广播继续推进，必须优先 directed baton。
- 不允许交付收口时扩大 scope 或追加未验证对外表述。

## 2) 机读契约冻结

### 2.1 `xt.supervisor_one_shot_intake_request.v1`

```json
{
  "schema_version": "xt.supervisor_one_shot_intake_request.v1",
  "project_id": "uuid",
  "request_id": "uuid",
  "user_goal": "string",
  "context_refs": ["memory://project/123", "file://docs/spec.md"],
  "preferred_split_profile": "auto|conservative|balanced|aggressive",
  "participation_mode": "zero_touch|critical_touch|guided_touch",
  "innovation_level": "L0|L1|L2|L3|L4",
  "token_budget_class": "tight|standard|priority_delivery",
  "delivery_mode": "spec_first|implementation_first|release_first",
  "allow_auto_launch": true,
  "requires_human_authorization_types": ["payment", "external_side_effect"],
  "audit_ref": "audit-xxxx"
}
```

### 2.2 `xt.adaptive_pool_plan_decision.v1`

```json
{
  "schema_version": "xt.adaptive_pool_plan_decision.v1",
  "project_id": "uuid",
  "request_id": "uuid",
  "complexity_score": 0.78,
  "risk_surface": "low|medium|high|critical",
  "selected_profile": "conservative|balanced|aggressive",
  "selected_participation_mode": "zero_touch",
  "selected_innovation_level": "L2",
  "pool_count": 2,
  "lane_count": 6,
  "pool_plan": [
    {
      "pool_id": "xt-main",
      "purpose": "mainline_delivery",
      "lane_ids": ["L1", "L2", "L3"],
      "requires_isolation": false
    }
  ],
  "seat_cap": 3,
  "block_risk_score": 0.24,
  "estimated_merge_cost": 0.18,
  "decision_explain": [
    "dependency_density_high",
    "sensitive_side_effect_detected",
    "requires_parallel_contract_and_ui_tracks"
  ],
  "decision": "allow|downgrade|deny",
  "deny_code": "none",
  "audit_ref": "audit-xxxx"
}
```

### 2.3 `xt.one_shot_autonomy_policy.v1`

```json
{
  "schema_version": "xt.one_shot_autonomy_policy.v1",
  "project_id": "uuid",
  "auto_confirm_policy": "none|safe_only|safe_plus_low_risk",
  "auto_launch_policy": "manual|directed_safe_only|mainline_only",
  "grant_gate_mode": "fail_closed",
  "allowed_auto_actions": [
    "plan_generation",
    "lane_claim_assignment",
    "directed_continue",
    "summary_delivery"
  ],
  "human_touchpoints": [
    "payment_auth",
    "external_secret_binding",
    "scope_expansion"
  ],
  "explainability_required": true,
  "audit_ref": "audit-xxxx"
}
```

### 2.4 `xt.one_shot_run_state.v1`

```json
{
  "schema_version": "xt.one_shot_run_state.v1",
  "project_id": "uuid",
  "request_id": "uuid",
  "run_id": "uuid",
  "state": "intake_normalized|planning|awaiting_grant|launching|running|blocked|resuming|mergeback|delivery_freeze|completed|failed_closed",
  "current_owner": "Supervisor|XT-L2|Hub-L5|QA",
  "active_pools": ["xt-main"],
  "active_lanes": ["XT-W3-26-B", "XT-W3-26-E"],
  "top_blocker": "grant_required",
  "next_directed_target": "XT-L2",
  "user_visible_summary": "string",
  "evidence_refs": ["build/reports/xt_w3_26_run_state.v1.json"],
  "audit_ref": "audit-xxxx"
}
```

### 2.5 `xt.unblock_baton.v1`

```json
{
  "schema_version": "xt.unblock_baton.v1",
  "project_id": "uuid",
  "edge_id": "EDGE-123",
  "blocked_lane": "XT-W3-26-F",
  "resolved_by": "Hub-L5",
  "resolved_fact": "grant_chain_ready",
  "resume_scope": "continue_current_task_only",
  "deadline_hint_utc": "2026-03-07T12:00:00Z",
  "must_not_do": ["scope_expand", "parallel_claim_new_lane"],
  "evidence_refs": ["build/reports/xt_w3_26_unblock_baton.v1.json"]
}
```

### 2.6 `xt.delivery_scope_freeze.v1`

```json
{
  "schema_version": "xt.delivery_scope_freeze.v1",
  "project_id": "uuid",
  "run_id": "uuid",
  "validated_scope": ["XT-W3-23", "XT-W3-24", "XT-W3-25"],
  "release_statement_allowlist": [
    "validated_mainline_only",
    "no_scope_expansion",
    "no_unverified_claims"
  ],
  "pending_non_release_items": ["future_ui_productization", "future_one_shot_full_autonomy"],
  "decision": "go|hold|no_go",
  "audit_ref": "audit-xxxx"
}
```

## 3) 专项 Gate / KPI

### 3.1 Gate

- `XT-OS-G0`：one-shot intake / pool plan / autonomy / run state / unblock baton / delivery freeze 六类契约冻结完成。
- `XT-OS-G1`：Supervisor 单次输入可生成 `normalized request + adaptive pool plan + explain`，且同输入可复现。
- `XT-OS-G2`：自适应 pool/lane 规划通过经济性与安全性门禁，`lane explosion`、`cross_pool_cycle`、`unsafe_auto_launch` 全为零。
- `XT-OS-G3`：safe auto-confirm / auto-launch / grant gate / fail-closed 主链通过。
- `XT-OS-G4`：blocker resolved 后能在定向目标泳道内触发 continue baton，且无需全局广播。
- `XT-OS-G5`：交付冻结、用户可解释输出、release scope 控制、回滚点与机读证据全部齐备。

### 3.2 KPI

- `one_shot_intake_to_plan_p95_ms <= 8000`
- `same_input_plan_determinism = 100%`
- `unsafe_auto_launch = 0`
- `cross_pool_cycle_allowed = 0`
- `blocked_to_directed_resume_p95_ms <= 3000`
- `lane_cap_violations = 0`
- `user_interrupt_rate(zero_touch) <= 0.15`
- `delivery_scope_expansion_without_replan = 0`
- `orchestration_explainability_missing = 0`

## 4) 子工单分解

### 4.1 `XT-W3-26-A` One-Shot Intake Entry + Normalized Request

- 目标：把 Supervisor 现有聊天入口与 split proposal 入口合并成一个用户可理解的接案入口。
- 交付物：`build/reports/xt_w3_26_a_one_shot_intake_evidence.v1.json`

### 4.2 `XT-W3-26-B` Adaptive Pool Planner

- 目标：根据复杂度、模块边界、风险面、档位、参与等级自动决定 `pool_count + lane_count + seat_cap + explain`。
- 交付物：`build/reports/xt_w3_26_b_adaptive_pool_plan_evidence.v1.json`

### 4.3 `XT-W3-26-C` Lane Cap / Seat / Concurrency Governor

- 目标：把 `CriticalPathSeatAllocator` 与分档、block risk、token/class 预算联动，避免 lane 爆炸。
- 交付物：`build/reports/xt_w3_26_c_concurrency_governor_evidence.v1.json`

### 4.4 `XT-W3-26-D` One-Shot Run State Machine

- 目标：把 one-shot 主路径显式状态化，避免 UI/编排逻辑散落在多个按钮与临时状态里。
- 交付物：`build/reports/xt_w3_26_d_run_state_machine_evidence.v1.json`

### 4.5 `XT-W3-26-E` Safe Auto-Confirm + Launch Policy

- 目标：支持在低风险、已授权、边界清晰时自动确认与启动；高风险场景保持 fail-closed。
- 交付物：`build/reports/xt_w3_26_e_safe_auto_launch_evidence.v1.json`

### 4.6 `XT-W3-26-F` Directed Unblock + Continue Baton

- 目标：当 blocker 转绿时，由 Supervisor 向具体等待泳道发单播继续指令，而不是依赖广播。
- 交付物：`build/reports/xt_w3_26_f_directed_unblock_evidence.v1.json`

### 4.7 `XT-W3-26-G` Delivery Handoff + Scope Freeze

- 目标：把最终交付收口为 `validated scope + allowed public statements + next actions` 的冻结包。
- 交付物：`build/reports/xt_w3_26_g_delivery_scope_freeze_evidence.v1.json`

### 4.8 `XT-W3-26-H` Replay / Evidence / Regression Harness

- 目标：建立 one-shot 运行回放与回归包，确保未来让 Supervisor 自推进自身项目时可机判。
- 交付物：`build/reports/xt_w3_26_h_replay_regression_evidence.v1.json`

## 5) 任务级执行包

### 5.1 `XT-W3-26` 总任务

- 目标：把 X-Terminal Supervisor 从“有拆分功能的工程控制面板”提升到“用户输入一个大任务后可安全自动推进的主入口”。

#### DoR

- `XT-W3-21/XT-W3-22` 的 intake manifest / acceptance pack 已存在。
- `XT-W2-20..XT-W2-28` 的分档、参与等级、反阻塞、jamless、context capsule 已有工单与部分实现。
- `docs/memory-new/xhub-lane-command-board-v2.md` 已是 directed-only / 7件套 / claim TTL 的协作基础。
- `Hub-first` 安全边界、grant 主链、release scope freeze 原则已经冻结。

#### 实施子步骤

1. 在 Supervisor 主入口新增 `one-shot intake` 模式，接管大任务输入、上下文引用、默认档位、介入等级与预算类。
2. 将现有 `TaskDecomposer + IntakeAcceptanceContracts + PoolIntegrationOrchestrator` 串成统一的 `AdaptivePoolPlanner` 决策链。
3. 把 `CriticalPathSeatAllocator` 升级成 `profile-aware + risk-aware + budget-aware` 并发治理器。
4. 将 proposal 生成、确认、执行、阻塞、续推、mergeback、delivery freeze 串成显式 `one-shot run state` 状态机。
5. 落地 `safe auto-confirm + auto-launch` 策略层，明确哪些动作可自动、哪些必须等待用户授权。
6. 将 blocker -> resolved 的续推动作改为 `directed unblock baton`，禁止依赖全量广播自发现。
7. 产出 `delivery scope freeze` 与 machine-readable 交付摘要，约束 validated scope 与对外口径。
8. 补齐 replay harness、回归矩阵、回滚点、证据报告与 release gate。

#### DoD

- 用户从单次输入开始，不再需要手工依次点击“生成 proposal / 确认 / 启动 / 人工追 blocker”。
- Supervisor 可自动给出 `为什么拆成这些池与泳道` 的解释，且同输入可复现。
- 低风险主链可自动推进，高风险链路仍保留 `grant_required / permission_denied / awaiting_user_auth` 的 fail-closed 行为。
- blocker 一旦 resolved，等待泳道能收到定向继续指令并只推进被允许的最小范围。
- 交付时可自动输出冻结范围、已验证能力、未覆盖能力与下一步建议。

#### Gate

- `XT-OS-G0/G1/G2/G3/G4/G5`
- `XT-MP-G0/G1/G3/G4/G5`
- `XT-READY-G0..G5`

#### KPI

- `one_shot_intake_to_plan_p95_ms <= 8000`
- `blocked_to_directed_resume_p95_ms <= 3000`
- `same_input_plan_determinism = 100%`
- `unsafe_auto_launch = 0`
- `delivery_scope_expansion_without_replan = 0`

## 6) 实现热点

- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 把当前聊天入口提升为 one-shot intake 主链入口。
- `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - 替换当前分散的 proposal/confirm/launch 手工入口，增加主状态视图与 explain 面板。
- `x-terminal/Sources/Supervisor/SupervisorOrchestrator.swift`
  - 统一 `generate -> confirm -> execute -> resume -> mergeback -> freeze` 主链。
- `x-terminal/Sources/Supervisor/TaskDecomposition/TaskDecomposer.swift`
  - 暴露规范化 task graph 给 adaptive planner 使用。
- `x-terminal/Sources/Supervisor/IntakeAcceptanceContracts.swift`
  - 增补 one-shot intake request / pool plan decision / delivery freeze 字段。
- `x-terminal/Sources/Supervisor/PoolIntegrationOrchestrator.swift`
  - 接入多池规划、池间边界解释、mergeback 约束与 cross-pool cycle gate。
- `x-terminal/Sources/Supervisor/CriticalPathSeatAllocator.swift`
  - 接入 profile/risk/budget 决策，形成席位与 lane cap 守门。
- `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - 接入 blocker resolved 事件监听与 continue baton 下发。

建议新增文件：

- `x-terminal/Sources/Supervisor/OneShotIntakeCoordinator.swift`
- `x-terminal/Sources/Supervisor/AdaptivePoolPlanner.swift`
- `x-terminal/Sources/Supervisor/OneShotRunStateStore.swift`
- `x-terminal/Sources/Supervisor/DirectedUnblockRouter.swift`

## 7) 回归样例

- `small_single_pool`
  - 输入低复杂度任务时，不应误拆成多池多泳道。
- `medium_dual_pool_with_side_effects`
  - 含副作用边界的任务应拆出隔离池，但主线仍可自动推进。
- `grant_required_fail_closed`
  - 高风险动作缺授权时必须停在 `awaiting_grant`，不能偷跑。
- `aggressive_profile_lane_explosion`
  - 激进档输入若会导致 lane 爆炸，必须自动降档或限流。
- `blocker_resolved_directed_resume`
  - blocker 解除后，仅被阻塞泳道收到继续 baton，不发全局广播。
- `user_changes_plan_mid_run`
  - 用户中途改需求时，必须触发 replan 与 scope freeze 失效重算，而不是在旧计划上硬推。
- `delivery_scope_freeze`
  - 发布摘要必须只覆盖已验证 mainline，不可扩写为“平台全部可用”。

## 8) 回滚点

- UI 入口回滚：`x-terminal/Sources/Supervisor/SupervisorView.swift`
- 编排主链回滚：`x-terminal/Sources/Supervisor/SupervisorOrchestrator.swift`
- 规划决策回滚：`x-terminal/Sources/Supervisor/IntakeAcceptanceContracts.swift`
- 运行状态机回滚：`x-terminal/Sources/Supervisor/OneShotRunStateStore.swift`
- 定向续推回滚：`x-terminal/Sources/Supervisor/DirectedUnblockRouter.swift`

## 9) 发布判定

只有同时满足以下条件，才允许宣告“Supervisor 已支持一次性接案 + 自适应泳池规划主路径”：

- `XT-OS-G0..G5` 全绿。
- 真实样本证明 one-shot 流程可从单次输入进入已验证主链交付。
- `grant_required / permission_denied / runtime_error / scope_expansion` 四类失败注入全部 fail-closed。
- 用户可解释输出完整，且不依赖人工旁白补充“系统刚才做了什么”。
