# XT-W2-28 无拥塞推进协议（Jamless Protocol v1）实现子工单包

- version: v1.1
- updatedAt: 2026-03-03
- owner: XT-L2（Primary）/ XT-L1 / Hub-L3 / Hub-L5 / QA / AI-COORD-PRIMARY
- status: active
- scope: `XT-W2-28`（防堵车规则总装）+ `XT-W2-28-A/B/C/D/E/F`
- parent:
  - `x-terminal/work-orders/xt-supervisor-multipool-adaptive-work-orders-v1.md`
  - `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-supervisor-rhythm-user-explainability-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`

## 0) 目标与边界

- 目标：把“多泳道互等 + 高频重复汇报 + 无增量重试”收敛为可机判的无拥塞执行协议。
- 目标：在不降低质量与安全门禁的前提下，显著降低 token 消耗并提升 unblock 吞吐。
- 目标：把解阻从“广播催单”升级为“blocker -> waiter 定向接力（baton）”。

硬边界：
- 任何 `FAIL|INSUFFICIENT_EVIDENCE` 不得进入 `closed`。
- `require_real=true` 路径禁止 synthetic 证据冒绿。
- 规则只能约束调度与通知，不得绕过既有 Gate/授权/审计链路。

## 1) Jamless v1 规则集（R1..R10）

1. `R1 单一阻塞主责`：同一 blocker 同时仅允许 1 个 owner lane 推进，其他泳道转 `standby_wait`。
2. `R2 双层门禁`：区分 `execution_green` 与 `release_green`；除 Hub-L5 外默认只追 execution_green。
3. `R3 定向接力`：只允许 blocker->waiter 定向通知，禁止全泳道广播。
4. `R4 死锁解环`：wait-for 图每 5 分钟做 SCC 检测；发现环后仅保留 1 条 breaker lane。
5. `R5 WIP 限流`：7 泳道模式同时 active 数上限 3（建议 Hub-L1、XT-L2、Hub-L5）。
6. `R6 汇报去重`：同 `blocked_reason_hash` 4 小时内禁止重复 full 7 件套。
7. `R7 证据增量阈值`：无 `evidence_delta_hash` 变化时，禁止重跑 release 级门禁。
8. `R8 Claim 护栏`：续租 claim 必须附增量证据 hash；无增量只允许降级为 delta 心跳。
9. `R9 重试冷却`：同一 gate 无增量重试最小间隔 90 分钟。
10. `R10 Token 预算守门`：active lane 报告 <= 400 tokens，standby lane <= 120 tokens。

## 2) 机读契约（新增字段）

### 2.1 Lane 调度快照

```json
{
  "schema_version": "xt.jamless.lane_state.v1",
  "task_id": "XT-W2-28-B",
  "lane_id": "XT-L1",
  "lane_mode": "active|standby|frozen",
  "blocker_id": "SKC-W2-06",
  "blocked_reason_hash": "sha256:...",
  "unblock_condition_expr": "contract_green && runtime_green && gate_vector_has_no_fail",
  "evidence_delta_hash": "sha256:...",
  "retry_after_utc": "2026-03-02T00:00:00Z",
  "report_mode": "delta_3line|full_7piece"
}
```

### 2.2 定向接力事件

```json
{
  "schema_version": "xt.jamless.baton_dispatch.v1",
  "event_type": "supervisor.unblock.baton.dispatched",
  "blocker_id": "SKC-W2-06",
  "waiter_task_id": "SKC-W2-07",
  "waiter_lane": "Hub-L4",
  "baton_seq": 12,
  "next_step": "claim_backlog_next_and_run_precheck",
  "evidence_ref": "build/reports/skc_w2_06_xt_l2_verified_handoff.v1.json",
  "dedupe_window_ms": 14400000,
  "sent_at_ms": 0
}
```

### 2.3 Gate 重试记录

```json
{
  "schema_version": "xt.jamless.gate_retry.v1",
  "gate_id": "SKC-G5",
  "task_id": "SKC-W3-08",
  "last_attempt_at_ms": 0,
  "retry_after_ms": 5400000,
  "evidence_delta_hash": "sha256:...",
  "attempt_policy": "blocked_if_no_delta"
}
```

## 3) 7 泳道运行档（默认）

- `Active-3`（主推）：`Hub-L1 + XT-L2 + Hub-L5`
- `Standby-4`（低频）：`XT-L1 + Hub-L4 + Hub-L2 + Hub-L3`
- 触发升档：收到定向 baton 且 unblock 条件满足。
- 回落条件：连续 2 个窗口无增量证据。

## 4) 实施子工单（可直接派发）

### 4.1 `XT-W2-28-A` Critical Path Admission + WIP Governor

- owner: `XT-L2`（Primary）+ `Hub-L5`
- 目标：执行 R1/R2/R5，把 active 并发限制为关键链优先。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
- 交付物：`build/reports/xt_w2_28_a_wip_governor_evidence.v1.json`
- DoD：
  - `active_lane_count <= 3`（7 泳道模式）
  - 非关键泳道不会抢占 release blocker 资源
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G4`
  - KPI: `critical_path_preempt_success_rate >= 0.99`

### 4.2 `XT-W2-28-B` Directed Baton Router（No Broadcast）

- owner: `XT-L1`（Primary）+ `XT-L2` + `Hub-L3`
- 目标：执行 R3，仅向受影响 waiter lane 发消息。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/PromptFactory.swift`
- 交付物：`build/reports/xt_w2_28_b_directed_baton_evidence.v1.json`
- DoD：
  - `broadcast_dispatch_count = 0`
  - `missed_unblock_notifications = 0`
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G5`
  - KPI: `baton_dispatch_latency_p95_ms <= 1200`

### 4.3 `XT-W2-28-C` Blocked Dedupe + Delta Reporter

- owner: `XT-L1`（Primary）+ `QA`
- 目标：执行 R6/R10，阻断重复长报并强制 delta-only 心跳。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - `x-terminal/Sources/Supervisor/PromptFactory.swift`
- 交付物：`build/reports/xt_w2_28_c_dedupe_delta_evidence.v1.json`
- DoD：
  - 无状态变化时仅输出 3 行 delta
  - 4 小时内同 hash 不重复 full 7 件套
- Gate/KPI：
  - Gate: `XT-MP-G4`, `XT-MP-G5`
  - KPI: `duplicate_blocked_report_count = 0`, `token_per_notification_p95_delta <= -35%`

### 4.4 `XT-W2-28-D` Deadlock SCC Breaker

- owner: `Hub-L3`（Primary）+ `XT-L2`
- 目标：执行 R4，自动检测 wait-for 环并只保留 breaker lane。
- 代码落点：
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `x-terminal/Sources/Supervisor/SupervisorOrchestrator.swift`
- 交付物：`build/reports/xt_w2_28_d_deadlock_breaker_evidence.v1.json`
- DoD：
  - `wait_graph_cycle_incidents` 被检测并自动处置
  - 解环后 1 个调度窗口内恢复可推进状态
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G4`
  - KPI: `deadlock_break_time_p95_ms <= 60000`

### 4.5 `XT-W2-28-E` Gate Retry Cooldown + Evidence Delta Guard

- owner: `Hub-L5`（Primary）+ `QA` + `XT-L2`
- 目标：执行 R7/R8/R9，阻断无增量重跑 release gate。
- 代码落点：
  - `scripts/m3_run_hub_l5_skc_g5_gate.sh`
  - `scripts/m3_check_internal_pass_lines.js`
  - `docs/memory-new/xhub-lane-command-board-v2.md`（机读字段引用）
- 交付物：`build/reports/xt_w2_28_e_gate_cooldown_evidence.v1.json`
- DoD：
  - 无 `evidence_delta_hash` 变化时 gate 重试被阻断
  - 冷却时间命中后才允许下一次重试
- Gate/KPI：
  - Gate: `XT-MP-G4`, `XT-MP-G5`
  - KPI: `invalid_gate_retry_count = 0`

### 4.6 `XT-W2-28-F` Block Risk Predictor + Replan Guard

- owner: `XT-L2`（Primary）+ `Hub-L5` + `QA` + `AI-COORD-PRIMARY`
- 目标：在堵塞链变成全局停滞前，自动触发重排/降档，保证关键路径可推进。
- 代码落点：
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorOrchestrator.swift`
- 交付物：`build/reports/xt_w2_28_f_block_predict_replan_guard_evidence.v1.json`
- DoD：
  - 支持 `20/40/60` 分钟触发器：
    - `20min` 无增量 -> checkpoint
    - `40min` 无增量 -> 自动换 breaker
    - `60min` 无增量 -> 自动发起 CR 重排
  - 收益不足时自动降档：`aggressive -> balanced`
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G4`, `XT-MP-G5`
  - KPI: `blocked_chain_age_p95_ms <= 7200000`, `deadlock_break_time_p95_ms <= 60000`, `replan_latency_p95_ms <= 3000`

## 5) 最小回归集（必须全绿）

1. blocker 转绿只通知 waiter，不触发全泳道广播。
2. 同 blocker 原因连续 3 次心跳，仅第 1 次 full 7 件套，其余 delta-only。
3. wait-for 环 A->B->C->A 出现后 1 分钟内自动解环。
4. 无证据增量时尝试重跑 SKC-G5 被 fail-closed 拒绝。
5. 7 泳道模式下 active lane 数超过 3 时自动降档并审计。
6. 连续 60 分钟无增量时必须触发自动重排或升级裁决。

## 6) 回滚点与开关

- feature flags:
  - `XT_JAMLESS_ACTIVE3_WIP_V1`
  - `XT_JAMLESS_DIRECTED_BATON_V1`
  - `XT_JAMLESS_BLOCKED_DEDUPE_V1`
  - `XT_JAMLESS_SCC_BREAKER_V1`
  - `XT_JAMLESS_GATE_COOLDOWN_V1`
  - `XT_JAMLESS_BLOCK_PREDICTOR_V1`
- rollback:
  - 发现误阻断时先关闭 `XT_JAMLESS_GATE_COOLDOWN_V1`（保留审计）。
  - 发现漏通知时关闭 `XT_JAMLESS_DIRECTED_BATON_V1` 并回退到 `XT-W2-27-D` 基线。
  - 发现误解环时关闭 `XT_JAMLESS_SCC_BREAKER_V1` 并保留 wait edge 只读告警。
