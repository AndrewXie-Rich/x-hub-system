# XT-W2-27 依赖阻塞图与即时解阻编排实现子工单包（Implementation Pack v1）

- version: v1.2
- updatedAt: 2026-03-03
- owner: XT-L2（Primary）/ XT-L1 / Hub-L3 / Hub-L5 / QA / AI-COORD-PRIMARY
- status: active
- scope: `XT-W2-27`（阻塞依赖图 + 即时解阻）+ `XT-W2-27-A/B/C/D/E` + `XT-W2-27-G/H`（Dependency Edge Registry + Directed @ Inbox）
- parent:
  - `x-terminal/work-orders/xt-supervisor-multipool-adaptive-work-orders-v1.md`
  - `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-28-jamless-anti-congestion-protocol-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## 0) 目标与边界

- 目标：让 Supervisor 能实时维护“谁在等谁”的 `wait-for` 图，并在 blocker 转绿后自动触发等待泳道继续推进。
- 目标：解阻动作必须 machine-readable、可追溯、可回放，不依赖人工口头协调。
- 目标：等待泳道在被解阻后应收到“可执行下一步指导”，并按 Auto-Continue 规则续推。
- 目标：跨泳道协同从“广播催单”升级为 `Directed @`（waiter->blocker）+ SLA 约束，降低 token 噪音。
- 硬边界：
  - 任一依赖链路证据不足（`FAIL|INSUFFICIENT_EVIDENCE`）时，必须继续 `blocked`（fail-closed）。
  - 禁止跨泳道强制改写他人任务状态，只能通过 `unblock event + guidance` 驱动标准续推。
  - require-real 路径不得用 synthetic 证据冒绿。

## 1) 机读契约（统一语义）

### 1.1 阻塞边契约（wait edge）

```json
{
  "event_type": "supervisor.block.edge.registered",
  "project_id": "uuid",
  "waiter_task_id": "XT-W2-27-D",
  "waiter_lane": "XT-L1",
  "blocker_task_id": "XT-W2-27-B",
  "blocker_lane": "XT-L2",
  "block_reason_code": "dependency_not_green",
  "created_at_ms": 0,
  "edge_ttl_ms": 14400000,
  "audit_ref": "audit-xxxx"
}
```

### 1.2 双绿门控契约（dependency readiness）

```json
{
  "event_type": "supervisor.dependency.readiness.evaluated",
  "task_id": "XT-W2-27-B",
  "contract_green": true,
  "runtime_green": true,
  "gate_vector": "XT-MP-G3:PASS,XT-MP-G4:PASS",
  "decision": "green|not_green",
  "deny_code": "dependency_gate_not_green",
  "evaluated_at_ms": 0,
  "audit_ref": "audit-xxxx"
}
```

### 1.3 解阻分发契约（unblock dispatch）

```json
{
  "event_type": "supervisor.unblock.dispatch",
  "waiter_task_id": "XT-W2-27-D",
  "waiter_lane": "XT-L1",
  "trigger_blocker_task_id": "XT-W2-27-B",
  "dispatch_action": "notify_lane_and_allow_claim_next",
  "guidance_ref": "board://lane/xt-l1/guidance/20260302-001",
  "unblock_dispatch_latency_ms": 0,
  "audit_ref": "audit-xxxx"
}
```

### 1.4 依赖托管包契约（dependency escrow）

```json
{
  "escrow_id": "escrow-uuid",
  "waiter_task_id": "XT-W2-27-D",
  "resume_policy": "claim_backlog_next_if_dependency_green",
  "stable_core_ref": "hub://prompt-core/xt-lane-executor.v2",
  "task_delta_ref": "board://XT-W2-27-D",
  "context_refs": [
    "mem://project/<project_id>/<memory_id>"
  ],
  "rollback_ref": "board://rollback/xt-w2-27-d",
  "expires_at_ms": 0
}
```

## 2) 运行状态机（阻塞 -> 解阻 -> 续推）

`running -> blocked_detected -> edge_registered -> waiting_escrowed -> blocker_green_detected -> unblock_dispatched -> resumed`

异常分支：
- `blocked_detected -> missing_dependency_contract -> blocked_fail_closed`
- `blocker_green_detected -> dual_green_failed -> blocked_wait_dependency`
- `unblock_dispatched -> no_claim_progress_within_sla -> escalated_to_coord`

硬约束：
- 只有 `contract_green && runtime_green` 才允许触发 `unblock_dispatched`。
- 解阻事件不等于直接完成，等待泳道仍需按 `claim + gate + 7件套` 执行。
- 任一边 `edge_ttl` 到期未收敛，必须触发升级而非静默丢弃。

## 3) 实现子工单（可直接派发）

### 3.1 `XT-W2-27-A` Wait-For Graph Arbiter（阻塞图裁决器）

- owner: `XT-L2`（Primary）+ `Hub-L3`
- 目标：把 lane 的 `blocked_reason/unblock_owner/depends_on` 统一收敛为可机判 `wait-for DAG`。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorOrchestrator.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`（仅事件落盘扩展）
- DoR：
  - command board 的阻塞字段口径已冻结（`blocked_reason/unblock_owner/depends_on`）。
  - Auto-Continue completion 事件已可被读取（依赖 `XT-W2-26-A`）。
- 步骤：
  1. 实现 `WaitGraphBuilder`，增量维护 `waiter -> blocker` 边。
  2. 为每条边生成 `edge_id + edge_ttl + created_at`，支持去重与续租。
  3. 增加环检测：`wait_graph_cycle_detected` 命中即 fail-closed。
  4. 输出机读报告：`build/reports/xt_w2_27_a_wait_graph_evidence.v1.json`。
- DoD：
  - `wait_graph_edge_freshness_p95_ms <= 2000`。
  - 同一阻塞边不会重复膨胀（重复边增长率接近 0）。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G4`
  - KPI: `wait_graph_cycle_incidents = 0`, `stale_wait_edge_ratio <= 0.05`
- 回归：
  - blocker 已完成但边未清理 -> 失败。
  - 依赖环 A->B->A 未阻断 -> 失败。

### 3.2 `XT-W2-27-B` Dual-Green Dependency Gate（双绿依赖门控）

- owner: `XT-L2`（Primary）+ `Hub-L5` + `QA`
- 目标：把“依赖已完成”的判定从单信号升级到 `contract_green + runtime_green` 双绿。
- 代码落点：
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `scripts/m3_check_xt_ready_gate.js`（只加证据钩子，不改已冻结语义）
- DoR：
  - `XT-W2-27-A` 已能稳定产出 wait edges。
  - Gate vector 字段与 `PASS/FAIL/INSUFFICIENT_EVIDENCE` 语义已冻结。
- 步骤：
  1. 实现 `DependencyDualGreenEvaluator`。
  2. 将 `delivered-but-gate-fail` 归类为 `not_green`。
  3. 输出 `supervisor.dependency.readiness.evaluated` 审计事件。
  4. 输出机读报告：`build/reports/xt_w2_27_b_dual_green_evidence.v1.json`。
- DoD：
  - 无单绿放行（只要任一侧不绿就阻断）。
  - 判定结果可追溯到 gate_vector 与运行态证据。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G4`
  - KPI: `false_unblock_due_to_single_green = 0`, `dual_green_eval_p95_ms <= 800`
- 回归：
  - `contract_green=true` 但 `runtime_green=false` 仍触发解阻 -> 失败。
  - `runtime_green=true` 但 `gate=INSUFFICIENT_EVIDENCE` 仍触发解阻 -> 失败。

### 3.3 `XT-W2-27-C` Dependency Escrow Package（等待态托管包）

- owner: `XT-L1`（Primary）+ `XT-L2`
- 目标：等待泳道在 blocked 期间预生成“可恢复执行包”，解阻后无需人工重新组织上下文。
- 代码落点：
  - `x-terminal/Sources/Supervisor/PromptFactory.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/Task.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- DoR：
  - 三段式提示词合同已启用（依赖 `XT-W2-24-A`）。
  - Auto-Continue claim 语义已启用（依赖 `XT-W2-26-B`）。
- 步骤：
  1. 实现 `DependencyEscrowBuilder`（固化 stable core + delta + refs）。
  2. 为等待任务写入 `escrow_id/resume_policy/rollback_ref`。
  3. 解阻后优先复用 escrow 包，减少重新拼 prompt token。
  4. 输出机读报告：`build/reports/xt_w2_27_c_dependency_escrow_evidence.v1.json`。
- DoD：
  - `escrow_coverage_for_blocked_tasks = 100%`。
  - 解阻后恢复步骤可解释且可回滚。
- Gate/KPI：
  - Gate: `XT-MP-G2`, `XT-MP-G3`
  - KPI: `unblock_to_resume_ready_p95_ms <= 2000`, `escrow_rebuild_miss_rate <= 0.05`
- 回归：
  - blocked 任务无 escrow 包 -> 失败。
  - escrow 缺 rollback_ref 仍放行 -> 失败。

### 3.4 `XT-W2-27-D` Unblock Router & Guidance（解阻路由与续推指导）

- owner: `XT-L1`（Primary）+ `XT-L2` + `Hub-L3`
- 目标：blocker 转绿后，等待泳道秒级收到“继续执行”指导与 claim 建议。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - `x-terminal/Sources/Supervisor/PromptFactory.swift`
- DoR：
  - `XT-W2-27-B` 双绿判定可用。
  - `XT-W2-27-C` escrow 包已可读取。
- 步骤：
  1. 实现 `UnblockEventRouter`（按 waiter_lane 定向分发）。
  2. 生成 `GuidanceDelta`（只传 next_step 与必要 refs，不贴全文）。
  3. 与 `zero_touch|critical_touch|guided_touch` 路由策略对齐。
  4. 输出机读报告：`build/reports/xt_w2_27_d_unblock_router_evidence.v1.json`。
- DoD：
  - blocker 转绿后能自动通知等待泳道并给出下一步。
  - 无误通知、无漏通知、无重复通知风暴。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G5`
  - KPI: `unblock_notify_latency_p95_ms <= 1200`, `missed_unblock_notifications = 0`, `duplicate_unblock_notifications_rate <= 0.02`
- 回归：
  - blocker 转绿后等待泳道未收到指导 -> 失败。
  - 同一解阻事件反复刷屏 -> 失败。

### 3.5 `XT-W2-27-E` Block SLA Escalator（阻塞 SLA 与升级治理）

- owner: `QA`（Primary）+ `XT-L2` + `Hub-L5`
- 目标：把“长期 blocked”变成可度量、可升级、可追责的治理闭环。
- 代码落点：
  - `scripts/m3_check_internal_pass_lines.js`
  - `scripts/m3_check_xt_ready_gate.js`
  - `docs/memory-new/xhub-lane-command-board-v2.md`（仅证据引用区）
- DoR：
  - `XT-W2-27-A/B/D` 已产出机读事件。
  - release 证据矩阵已接入 Command Board。
- 步骤：
  1. 定义阻塞 SLA：`P0<=15min`, `P1<=60min`, `P2<=240min`。
  2. 实现 `BlockSLAWatcher`（超时自动升级到 `AI-COORD-PRIMARY`）。
  3. 输出 `blocked_age_distribution` 与 `mean_time_to_unblock` 报告。
  4. 样本不足输出 `INSUFFICIENT_EVIDENCE`，禁止冒绿。
  5. 输出机读报告：`build/reports/xt_w2_27_e_block_sla_evidence.v1.json`。
- DoD：
  - 每次 blocked 都有年龄与升级轨迹。
  - 超 SLA 事件不会静默堆积。
- Gate/KPI：
  - Gate: `XT-MP-G4`, `XT-MP-G5`
  - KPI: `mean_time_to_unblock_p0_p95_ms <= 900000`, `unresolved_block_over_sla_rate <= 0.05`, `stuck_block_silent_drop = 0`
- 回归：
  - 超 SLA 未升级 -> 失败。
  - 样本不足仍输出 GO -> 失败。

### 3.6 `XT-W2-27-G` Dependency Edge Registry（依赖边台账）

- owner: `XT-L2`（Primary）+ `Hub-L3` + `AI-COORD-PRIMARY`
- 目标：把“谁等谁”统一落到 Command Board `I. Dependency Edge Registry`，支持优先级计算与去重。
- 代码/文档落点：
  - `docs/memory-new/xhub-lane-command-board-v2.md`（`I` 分区）
  - `x-terminal/Sources/Supervisor/SupervisorOrchestrator.swift`（edge export hook）
- DoR：
  - `XT-W2-27-A` wait edge 已可稳定生成 `edge_id`。
  - `blocked_reason/unblock_condition_expr/evidence_refs` 字段已冻结。
- 步骤：
  1. 将运行态 wait edge 映射到 `I` 分区机读字段（`state/priority_score/mention_open_count`）。
  2. 增加 4h 去重：同 `edge_id` 只允许 1 条 open mention。
  3. 增加状态校验：`unblock_condition_expr` 为空时 fail-closed。
  4. 输出机读报告：`build/reports/xt_w2_27_g_edge_registry_evidence.v1.json`。
- DoD：
  - `edge_registry_completeness = 100%`（所有 blocked 边均可追溯）。
  - `duplicate_open_mentions_per_edge = 0`（4h 窗口）。
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G4`
  - KPI: `edge_registry_sync_p95_ms <= 1500`, `stale_edge_without_sla_tracking = 0`
- 回归：
  - 缺 `unblock_condition_expr` 仍进入 ready_to_verify -> 失败。
  - 同 edge 生成多条 open mention -> 失败。

### 3.7 `XT-W2-27-H` Directed @ Inbox（定向 @ 协同收件箱）

- owner: `XT-L1`（Primary）+ `XT-L2` + `AI-COORD-PRIMARY` + `QA`
- 目标：统一 waiter->blocker 的 @ 协同协议（ACK/accept/first-evidence SLA），替代全泳道广播。
- 代码/文档落点：
  - `docs/memory-new/xhub-lane-command-board-v2.md`（`J` 分区）
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`（mention route hook）
- DoR：
  - `I` 分区 edge 可读，含 `priority_score_snapshot`。
  - Directed baton 路由已可用（依赖 `XT-W2-27-D`）。
- 步骤：
  1. 落地 `MentionTicket` 契约：`mention_id/edge_id/from/to/status/ack_by_utc`。
  2. 执行 SLA：`ACK<=10m`、`accept/reject<=20m`、`first_evidence_delta<=40m`。
  3. 强制 `directed-only`，禁用广播 mention。
  4. 输出机读报告：`build/reports/xt_w2_27_h_directed_inbox_evidence.v1.json`。
- DoD：
  - `mention_ack_sla_breach_rate <= 0.05`
  - `broadcast_like_mentions = 0`
- Gate/KPI：
  - Gate: `XT-MP-G3`, `XT-MP-G5`
  - KPI: `mention_to_ack_p95_ms <= 600000`, `first_evidence_delta_p95_ms <= 2400000`
- 回归：
  - 未 ACK 超时未升级 -> 失败。
  - 使用广播催单仍被放行 -> 失败。

## 4) 测试计划（实现级）

### 4.1 单测

- `swift test --filter WaitGraphArbiterTests`
- `swift test --filter DependencyDualGreenTests`
- `swift test --filter DependencyEscrowTests`
- `swift test --filter UnblockRouterTests`
- `swift test --filter DependencyEdgeRegistryTests`
- `swift test --filter DirectedMentionInboxTests`

### 4.2 集成

- `swift test --filter AutoContinueExecutorTests`
- `swift test --filter SupervisorIncidentExportTests`
- `swift test --filter SupervisorDoctorTests`

### 4.3 最小回归集（必须全绿）

1. 多泳道等待链：A 等 B、B 等 C，C 转绿后 A/B 按序解阻。
2. 单绿误放行防护：只有 `contract_green` 或只有 `runtime_green` 时不得解阻。
3. 解阻通知准确性：解阻事件仅通知对应 waiter lane，且去重有效。
4. 阻塞超时升级：P0 blocked 超过 15 分钟必须升级并写审计。
5. fail-closed：缺证据或 gate 不绿时，必须保持 blocked。

## 5) 发布条件（防“假解阻、假转绿”）

- `false_unblock_due_to_single_green = 0`
- `missed_unblock_notifications = 0`
- `unresolved_block_over_sla_rate <= 0.05`
- `stuck_block_silent_drop = 0`
- `mean_time_to_unblock_p0_p95_ms <= 900000`

## 6) 回滚点与开关

- feature flags:
  - `XT_WAIT_GRAPH_ARBITER_V1`
  - `XT_DUAL_GREEN_GATE_V1`
  - `XT_DEPENDENCY_ESCROW_V1`
  - `XT_UNBLOCK_ROUTER_V1`
  - `XT_BLOCK_SLA_ESCALATOR_V1`
- rollback：
  - 发现误解阻或漏通知时，立即关闭 `XT_UNBLOCK_ROUTER_V1`，回退到仅写 blocked + 人工确认。
  - 发现双绿误判时，关闭 `XT_DUAL_GREEN_GATE_V1` 并强制全量回落 `dependency_not_green`。
  - 发现等待边异常膨胀时，关闭 `XT_WAIT_GRAPH_ARBITER_V1`，回退旧版静态依赖检查。

## 7) 泳道 AI 派发模板（可直接复制）

```text
任务：<XT-W2-27-A | XT-W2-27-B | XT-W2-27-C | XT-W2-27-D | XT-W2-27-E>
读序：
1) docs/memory-new/xhub-lane-command-board-v2.md
2) x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md
3) x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md

执行规则：
- 先 claim_id + claim_ttl_until（4h）
- 依赖未满足时 fail-closed，写 blocked_reason + unblock_owner
- 解阻只通过事件路由，不跨泳道直接改状态
- delivered 必交 7件套（含 Gate 证据路径 + KPI 报告路径）
```
