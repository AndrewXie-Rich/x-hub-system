# XT-CBL 防堵塞拆分 + 上下文滚动治理实现子工单包（Implementation Pack v1）

- version: v1.0
- updatedAt: 2026-03-03
- owner: XT-L2（Primary）/ XT-L1 / Hub-L3 / Hub-L5 / QA / AI-COORD-PRIMARY
- status: active
- scope: `XT-W2-20-B`, `XT-W2-24-F`, `XT-W2-25-B`, `XT-W2-28-F`
- parent:
  - `x-terminal/work-orders/xt-supervisor-multipool-adaptive-work-orders-v1.md`
  - `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-28-jamless-anti-congestion-protocol-implementation-pack-v1.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`

## 0) 目标与边界

- 目标：在多泳池/多泳道并行中，把“高并发”切换为“低阻塞高吞吐”，降低等待链年龄与 token 膨胀。
- 目标：建立 CBL（Contract-Block-Context Loop）闭环：先冻结契约、再压低阻塞、最后滚动压缩上下文。
- 目标：确保 Supervisor 在复杂案子中可持续自治推进，不因上下文拉长和广播噪音导致效率塌陷。

硬边界：
- 任一 `FAIL/INSUFFICIENT_EVIDENCE` 不得宣告完成。
- `require_real=true` 路径禁止 synthetic 证据冒绿。
- 仅允许定向 baton，不允许全泳道广播催单。
- 任何优化不得绕过授权、审计、回滚链路。

## 1) CBL 契约（机判字段）

### 1.1 新增调度字段

```json
{
  "schema_version": "xt.cbl.scheduler.v1",
  "task_id": "XT-W2-25-B",
  "block_risk_score": 0.0,
  "contract_freeze_state": "pending|green|drifted",
  "critical_path_rank": 0,
  "lane_mode": "active|standby|frozen",
  "wip_slot": "A1|A2|A3|S1|S2|S3|S4",
  "unblock_baton_target": "Hub-L4",
  "evidence_delta_hash": "sha256:...",
  "next_replan_at_utc": "2026-03-03T00:00:00Z"
}
```

### 1.2 新增上下文字段

```json
{
  "schema_version": "xt.cbl.context.v1",
  "lane_id": "XT-L2",
  "session_rollover_id": "rollover-uuid",
  "turn_count_since_rollover": 0,
  "state_transition_count_since_rollover": 0,
  "context_capsule_hash": "sha256:...",
  "report_mode": "delta_3line|full_7piece",
  "token_budget_lane": 450,
  "context_refs_count": 3
}
```

## 2) 可执行子工单（可直接派发）

### 2.1 `XT-W2-20-B` 防堵塞拆分器（Block-aware Pool/Lane Splitter）

- owner: `XT-L2`（Primary）+ `Hub-L3` + `QA`
- 目标：在 `pool->lane` 拆分阶段直接降低阻塞概率，不再只追求 lane 数。
- 代码落点：
  - `x-terminal/Sources/Supervisor/TaskDecomposition/TaskDecomposer.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/SplitAnalyzer.swift`
- DoR：
  - `XT-W2-20` 可输出稳定 pool plan。
  - `XT-W2-21` 可输出 lane DAG。
- 实施子步骤：
  1. 增加 `block_risk_score` 计算（依赖密度/跨池边/接口不确定性/风险等级）。
  2. 增加拆分约束：`depends_on<=2`、`fan_in<=2`、`fan_out<=3`。
  3. 增加 wave 机制：先 `contract_freeze_wave`，后 `feature_wave`。
  4. `cross_pool_cycle=true` 一律 fail-closed 阻断。
  5. 产出机读证据：`build/reports/xt_w2_20_b_block_aware_split_evidence.v1.json`。
- DoD：
  - 新生成 lane 计划满足依赖约束上限。
  - contract wave 通过前，feature wave 不启动。
- Gate/KPI：
  - Gate: `XT-MP-G0`, `XT-MP-G1`, `XT-MP-G3`
  - KPI: `cross_pool_dependency_density <= 0.25`, `avg_lane_depends_on <= 2.0`, `split_plan_block_risk_p90 <= 0.55`
- 回归样例：
  - 高风险模块仍被拆成高耦合链 -> 失败。
  - 存在跨池环依赖却进入执行 -> 失败。

### 2.2 `XT-W2-24-F` 会话滚动与上下文胶囊治理器（Session Rollover + Context Compactor）

- owner: `XT-L1`（Primary）+ `XT-L2` + `Hub-L3`
- 目标：阻断“长会话历史膨胀”，用 checkpoint + 引用恢复语义连续性。
- 代码落点：
  - `x-terminal/Sources/Supervisor/PromptFactory.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- DoR：
  - `XT-W2-24-A/B/C/D` 已可生成三段式提示词。
  - Command Board 支持 `delta_3line` 与 `context_refs`。
- 实施子步骤：
  1. 实现 `SessionRolloverPolicy`（`turn_count>=8` 或 `state_transition_count>=2` 强制换会话）。
  2. 落地 `ContextCompactor`：旧会话压缩为 machine-readable checkpoint（JSON）。
  3. 新会话只加载 `Stable Core + Task Delta + Context Refs<=3`。
  4. 增加 token 档位：`active<=450`, `standby<=120`。
  5. 产出机读证据：`build/reports/xt_w2_24_f_session_rollover_evidence.v1.json`。
- DoD：
  - 复杂案子中会话可滚动切换，语义不丢失。
  - 无增量时禁止发送 full 7 件套。
- Gate/KPI：
  - Gate: `XT-MP-G2`, `XT-MP-G3`, `XT-MP-G5`
  - KPI: `prompt_token_waste_ratio <= 0.12`, `full_history_prompt_usage = 0`, `rollover_recovery_success_rate >= 0.99`
- 回归样例：
  - 超过阈值不 rollover -> 失败。
  - rollover 后丢失 DoD/Gate 钩子 -> 失败。
  - standby lane 输出超过 120 tokens -> 失败。

### 2.3 `XT-W2-25-B` 关键路径动态席位调度器（Critical Path Active-3 Seat Governor）

- owner: `XT-L2`（Primary）+ `Hub-L5` + `QA`
- 目标：把 `Active-3` 从固定泳道升级为关键路径动态席位，避免关键任务被挤压。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorOrchestrator.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
- DoR：
  - `XT-W2-25` 基础调度器已可运行。
  - `XT-W2-27` wait-for 图可读。
- 实施子步骤：
  1. 实现 `CriticalPathSeatAllocator`（按 `critical_path_rank + block_risk_score` 选 active）。
  2. 实现 seat 抢占保护：非关键 lane 不得占用 active 资源。
  3. 无增量超过 2 个窗口自动降为 standby。
  4. 每轮输出席位审计：`seat_before/seat_after/preempt_reason`。
  5. 产出机读证据：`build/reports/xt_w2_25_b_active3_dynamic_seat_evidence.v1.json`。
- DoD：
  - 任何时刻 active lane 数不超过 3。
  - 关键路径任务获得优先推进且无长期饥饿。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G4`
  - KPI: `active_lane_count_violations = 0`, `critical_path_preempt_success_rate >= 0.98`, `queue_starvation_incidents = 0`
- 回归样例：
  - 非关键 lane 长占 active 席位 -> 失败。
  - active 超过 3 未回收 -> 失败。

### 2.4 `XT-W2-28-F` 阻塞预测 + 自动重排守门（Block Risk Predictor + Replan Guard）

- owner: `XT-L2`（Primary）+ `Hub-L5` + `QA` + `AI-COORD-PRIMARY`
- 目标：在真正堵死前触发重排与降档，把“相互等待”转成可控事件。
- 代码落点：
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `docs/memory-new/xhub-lane-command-board-v2.md`（CR/CD 引用）
- DoR：
  - `XT-W2-28` Jamless v1 基础规则已启用。
  - Command Board `CR Inbox` 可机判接入重排动作（`accepted|queued|rejected`）。
- 实施子步骤：
  1. 实现 `BlockRiskPredictor`（未来 30 分钟堵塞概率评分）。
  2. 实现阈值触发器：`20min 无增量 -> checkpoint`、`40min -> 自动换 breaker`、`60min -> CR 重排`。
  3. 实现 `aggressive_to_balanced` 自动回落守门（收益不达标即降档）。
  4. 输出 replan 决策审计：`trigger_reason/old_plan/new_plan/rollback_point`。
  5. 产出机读证据：`build/reports/xt_w2_28_f_block_predict_replan_guard_evidence.v1.json`。
- DoD：
  - 长阻塞链可被提前识别并自动触发处置。
  - 重排过程可回放、可回滚、可解释。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G4`, `XT-MP-G5`
  - KPI: `blocked_chain_age_p95_ms <= 7200000`, `deadlock_break_time_p95_ms <= 60000`, `replan_latency_p95_ms <= 3000`
- 回归样例：
  - 60 分钟无增量仍无重排 -> 失败。
  - 自动重排冲掉 release blocker -> 失败。
  - 收益不足仍停留 aggressive -> 失败。

## 3) 最小回归集（必须全绿）

1. 高耦合输入项目：拆分后 `cross_pool_dependency_density` 不得超阈值。
2. 长会话场景：达到 rollover 阈值后必须切换新会话且保留 DoD/Gate 钩子。
3. 关键路径抢占：非关键 lane 无法挤占 active-3 席位。
4. 长阻塞链：40/60 分钟触发器必须产生日志与重排行为。
5. 无增量场景：仍发送 full 7 件套判失败。

## 4) 上线顺序（7 泳道）

1. `XT-L2+Hub-L3+QA`：先落地 `XT-W2-20-B`（拆分前防堵塞）。
2. `XT-L1+XT-L2+Hub-L3`：落地 `XT-W2-24-F`（会话滚动与上下文压缩）。
3. `XT-L2+Hub-L5+QA`：落地 `XT-W2-25-B`（关键路径动态席位）。
4. `XT-L2+Hub-L5+QA+AI-COORD-PRIMARY`：落地 `XT-W2-28-F`（预测 + 重排守门）。
5. Hub-L1/Hub-L2/Hub-L4：保持 SKC 主链证据与定向 baton 协同，不抢占 active 资源。

## 5) 回滚点与开关

- feature flags:
  - `XT_CBL_BLOCK_AWARE_SPLIT_V1`
  - `XT_CBL_SESSION_ROLLOVER_V1`
  - `XT_CBL_ACTIVE3_DYNAMIC_SEAT_V1`
  - `XT_CBL_BLOCK_PREDICT_REPLAN_V1`
- rollback:
  - 误重排：关闭 `XT_CBL_BLOCK_PREDICT_REPLAN_V1`，回退上个 `plan_snapshot_ref`。
  - 误降档：关闭 `XT_CBL_ACTIVE3_DYNAMIC_SEAT_V1`，回退 `XT-W2-25` 基线调度。
  - 语义丢失：关闭 `XT_CBL_SESSION_ROLLOVER_V1`，暂退回 `XT-W2-24-D` 增量重试模式。
