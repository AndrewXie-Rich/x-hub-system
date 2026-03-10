# XT Supervisor 节奏控制 + 用户可解释性实现包 v1

- version: `v1.2`
- updatedAt: `2026-03-03`
- owner: `XT-L2`（Primary） / `XT-L1` / `Hub-L5` / `QA` / `AI-COORD-PRIMARY`
- status: `active`
- scope: `XT-W2-27-D/F`（解阻路由 + 自托管关键路径）+ `XT-W2-28/XT-W2-28-F`（Jamless + 阻塞预测重排）+ `XT-W2-24-F`（会话滚动）补齐“用户可解释输出”
- parent:
  - `x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-28-jamless-anti-congestion-protocol-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`

## 0) 目标

- 目标 1：Supervisor 从“人工广播催单”升级为“事件驱动节奏控制（rhythm controller）”。
- 目标 2：每次状态变化都能给用户清楚解释“为什么、在等谁、下一步是什么、何时再更新”。
- 目标 3：在保证质量前提下压缩 token 消耗（定向消息 + 增量上下文 + 去重抑噪）。
- 目标 4：接入 Jamless 协议，防止“多泳道互等 + 无增量重试 + 重复 blocked 长报”导致的推进堵车。

硬约束：
- 任一关键 gate 非 `PASS` 时，必须 fail-closed，不得“为了顺畅”跳过门禁。
- 解释文本必须与 machine-readable 证据一致，不允许叙述与事实源漂移。

---

## 1) 节奏控制器（Rhythm Controller）契约

### 1.1 三层节奏环

1. **事件环（秒级）**  
   - 触发：`blocker_green_detected`, `lane_completed`, `verified_handoff_received`  
   - 行为：只通知被影响的 waiter lane（1:1 baton），不做全量广播。
2. **调度环（分钟级）**  
   - 触发：`blocked_age > threshold`、`checkpoint_missed`、`queue_starvation`  
   - 行为：重排优先级（`critical_path_mode` 下关键链优先）。
3. **治理环（小时级）**  
   - 触发：`gate_insufficient_evidence` 长时未收敛、重复阻塞  
   - 行为：升级 AI-COORD 或请求用户关键授权。

### 1.2 机读配置（建议落盘）

```json
{
  "schema_version": "xt.supervisor.rhythm_policy.v1",
  "critical_path_mode": true,
  "event_loop": {
    "enabled": true,
    "poll_interval_ms": 800,
    "unblock_dispatch_latency_target_p95_ms": 1200
  },
  "cadence_loop": {
    "enabled": true,
    "checkpoint_interval_ms": 7200000,
    "blocked_sla_ms": 7200000
  },
  "governance_loop": {
    "enabled": true,
    "escalate_after_missed_checkpoints": 1
  },
  "notification_policy": {
    "broadcast_enabled": false,
    "notify_only_impacted_lanes": true,
    "notify_on_lane_completed": false,
    "notify_on_dependency_green": true
  }
}
```

---

## 2) 用户可解释输出契约（User Explainability Contract）

每次用户可见更新必须包含 6 个字段（最小集）：

1. `what_changed`：发生了什么（例如“SKC-W2-05 转绿”）。
2. `why_now`：为什么现在触发（例如“依赖边 dual-green 成立”）。
3. `waiting_on`：如果仍阻塞，在等谁/等什么。
4. `next_action`：系统下一步会做什么（具体动作，不空泛）。
5. `next_update_eta`：下一次自动更新预估时间。
6. `evidence_ref`：对应证据路径（至少 1 条）。

### 2.1 用户消息模板（精简版）

```text
[Supervisor Update]
变化：<what_changed>
原因：<why_now>
当前阻塞：<waiting_on 或 none>
下一步：<next_action>
预计更新时间：<next_update_eta>
证据：<evidence_ref>
```

### 2.2 用户消息模板（关键阻塞版）

```text
[Supervisor Blocked]
任务：<task_id> / 泳道：<lane_id>
阻塞原因：<blocked_reason>
依赖方：<unblock_owner>
系统动作：<auto_action 或 fail-closed>
需要你：<是否需要用户介入；若不需要写“无需介入”>
预计下次更新：<eta>
证据：<evidence_ref>
```

---

## 3) Token 优化（必须落地）

### 3.1 消息路由优化

- 默认关闭全泳道广播，启用 `notify_only_impacted_lanes=true`。
- 只在 `blocker -> waiter` 依赖边命中时发定向 baton。
- 无状态变化不发消息；仅更新本地计时器与健康快照。

### 3.2 提示词体积优化

- 强制三段式：`Stable Core + Task Delta + Context Refs`。
- Context 只传引用 ID，不传全文。
- delta 消息预算：`<= 320 tokens`；超预算自动压缩为 `ID + hash + next_step`。

### 3.3 去重与抑噪

- 同一 `blocked_reason` 不重复通知（直到状态变化）。
- 同一 `unblock_dispatch` 事件仅允许一次主通知 + 一次重试通知。
- 通知去重窗口：`10 min`。

---

## 4) 实施子工单（执行级）

### 4.1 `RHY-W1` 节奏策略执行器

- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
- 交付物：
  - `RhythmPolicyResolver`
  - `CriticalPathTickScheduler`
  - 机读证据：`build/reports/rhy_w1_rhythm_policy_evidence.v1.json`
- DoD：
  - `critical_path_mode` 启用时，非关键任务不会抢占关键链资源。

### 4.2 `RHY-W2` 定向解阻通知器（Baton）

- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
- 交付物：
  - `UnblockBatonNotifier`（按 waiter lane 定向）
  - 机读证据：`build/reports/rhy_w2_unblock_baton_evidence.v1.json`
- DoD：
  - `missed_unblock_notifications = 0`
  - `duplicate_unblock_notifications_rate <= 0.02`

### 4.3 `RHY-W3` 用户解释生成器

- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorView.swift`
- 交付物：
  - `UserExplainabilityRenderer`
  - 机读证据：`build/reports/rhy_w3_user_explainability_evidence.v1.json`
- DoD：
  - 用户可见消息覆盖 6 字段最小集，覆盖率 `=100%`。

### 4.4 `RHY-W4` Token 守门器

- 代码落点：
  - `x-terminal/Sources/Supervisor/PromptFactory.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- 交付物：
  - `NotificationTokenBudgetGuard`
  - 机读证据：`build/reports/rhy_w4_token_guard_evidence.v1.json`
- DoD：
  - 定向消息 p95 token 降低 >= 40%（对比全量广播基线）。

---

## 5) Gate / KPI / 回归

### 5.1 Gate

- `XT-MP-G3`：节奏控制正确性（无错唤醒/漏唤醒）
- `XT-MP-G4`：可靠性与 fail-closed（长阻塞升级、无静默失败）
- `XT-MP-G5`：用户可解释性与交付可用性

### 5.2 KPI

- `unblock_notify_latency_p95_ms <= 1200`
- `missed_unblock_notifications = 0`
- `duplicate_unblock_notifications_rate <= 0.02`
- `user_explainability_field_coverage = 1.0`
- `token_per_notification_p95_delta <= -40%`（对比广播基线）

### 5.3 回归样例（必须）

1. blocker 转绿后 waiter 未收到定向 baton -> 失败  
2. 同一阻塞重复刷屏（无状态变化）-> 失败  
3. 用户消息缺少 `waiting_on` 或 `next_action` -> 失败  
4. gate 非 PASS 仍宣告“已自动恢复”-> 失败  
5. token 超预算未压缩 -> 失败

---

## 6) 对用户的说明文案（系统内固定文本）

> 我会按依赖关系自动推进：当某条依赖泳道转绿时，我只通知受影响的泳道继续执行，不做全量广播。  
> 如果任务卡住，我会明确告诉你：卡在什么、在等谁、我下一步做什么、预计何时再更新。  
> 在不影响质量和安全门禁的前提下，我会尽量用最少上下文（增量信息）来降低 token 消耗。
