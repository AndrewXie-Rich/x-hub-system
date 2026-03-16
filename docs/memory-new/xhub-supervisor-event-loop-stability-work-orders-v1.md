# X-Hub Supervisor Event Loop Stability Work Orders v1

- Status: Active
- Updated: 2026-03-14
- Owner: XT-L2（Primary）/ Supervisor / Hub-L5 / QA / Security / Product
- Purpose: 把 `skill callback / grant resolution / heartbeat / incident` 驱动的 Supervisor 自动续跑闭环，从“已有骨架”升级为“稳定、可恢复、可审计、可回写 memory”的正式主线，确保每次事件都能在受治理前提下自动起下一轮，并持续写回 memory 与审计链。
- Depends on:
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/memory-new/xhub-skills-capability-grant-chain-contract-v1.md`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorProjectJobStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorProjectSkillCallStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorReviewScheduleStore.swift`

## 0) 当前状态判断

### 0.1 已经有的能力

截至 2026-03-14，代码里已经能看到这些事件驱动部件：

- `skill_callback`
- `grant_resolution`
- `approval_resolution`
- `heartbeat`
- `incident`
- `guidance_ack`
- `automation_safe_point`

也已经存在：

- 事件监听
- follow-up message 组装
- dedupe key
- 部分 memory refresh
- 部分 job / skill call / incident / review schedule 存储

所以这份工单不是从零搭一个事件回路，而是把当前散落在 `SupervisorManager` 和相关 store 里的能力，升级成“稳定闭环”。

### 0.2 当前真正缺的不是“有无触发器”，而是“稳定性合同”

当前还缺或仍然不够明确的地方：

1. 触发是否 durable persisted，再执行。
2. XT 重启或 crash 后，未完成事件如何恢复。
3. 同一事件被重复投递时，如何稳定去重。
4. 同一 project 上多种事件同时到达时，如何排序与合并。
5. 一次自动回合完成后，如何保证：
   - memory 写回完成
   - audit 链完成
   - round status 可追踪
6. 哪些异常必须 fail-closed 并进入 quarantine，而不是静默丢事件。

本工单要解决的就是这几个稳定性问题。

## 1) 北极星闭环

Supervisor 事件回路的目标状态必须是：

1. 任一合法触发源到达后，事件先进入 durable inbox。
2. 事件通过去重、范围校验、策略校验后，进入 project-scoped dispatcher。
3. Dispatcher 自动拉起下一轮 Supervisor 回合。
4. 回合结束后，统一写回：
   - L1 canonical
   - L2 observations
   - L4 raw evidence / refs
   - audit ledger
5. 若 XT 在任意中间环节崩溃，重启后能恢复未完成事件。
6. 若事件内容无效、过期、越权或缺关键上下文，系统要 fail-closed，并留下可审计记录。

## 2) 必须保证的四个主触发源

本工单强制稳定以下四类主触发：

1. `skill_callback`
2. `grant_resolution`
3. `heartbeat`
4. `incident`

同时建议保持同一基础设施兼容以下附加触发：

- `approval_resolution`
- `guidance_ack`
- `automation_safe_point`
- `external_trigger_ingress`

规则：

- 主触发必须进入正式 durability 与 replay 合同
- 附加触发应尽量复用同一套机制，而不是继续走散点特判

## 3) 固定事件合同

### 3.1 `Supervisor Event Envelope`

新增统一事件包络，最少包含：

- `event_id`
- `source`
- `project_id`
- `job_id`（可空）
- `plan_id`（可空）
- `request_id` / `grant_request_id` / `incident_id`（按 source 取其一）
- `dedupe_key`
- `created_at_ms`
- `eligible_at_ms`
- `priority`
- `payload`
- `policy_verdict`
- `status`

### 3.2 事件状态机

冻结：

- `received`
- `persisted`
- `eligible`
- `dispatched`
- `processing`
- `writeback_pending`
- `completed`
- `failed_closed`
- `superseded`
- `quarantined`

禁止：

- 只在内存里“看起来处理过”，但没有持久状态
- 直接从 `received` 跳成“完成”而无中间记录

### 3.3 去重键冻结

去重键必须稳定、可恢复、跨重启可重算。

最少规则：

- `skill_callback`: `project_id + request_id + final_status`
- `grant_resolution`: `project_id + request_id + resolution`
- `heartbeat`: `project_id + review_window + trigger_kind`
- `incident`: `project_id + incident_id + handled_state`

要求：

- 去重 ledger 必须持久化
- 不能只靠进程内字典去重

## 4) 调度规则冻结

### 4.1 单 project 单飞行

同一 project 任意时刻只允许一个 event-loop round 处于 `processing`。

若新事件到达：

- 高优先级可插队但必须留下 supersede 记录
- 普通优先级进入 pending queue
- heartbeat 可被 coalesce

### 4.2 优先级顺序

冻结默认优先级：

1. `incident`
2. `grant_resolution`
3. `skill_callback`
4. `approval_resolution`
5. `guidance_ack`
6. `automation_safe_point`
7. `heartbeat`

解释：

- `incident` 关乎安全与阻塞解除，优先级最高
- `heartbeat` 最容易风暴化，必须最低且允许合并

### 4.3 心跳合并

同一 project 在一个 review window 内，heartbeat 事件必须可合并。

禁止：

- 心跳每来一次就拉起一次新回合
- 心跳风暴把 `incident` 和 `grant_resolution` 饿死

### 4.4 失效事件处理

以下情况必须 fail-closed 或 quarantine：

- `grant_resolution` 找不到对应 request
- `skill_callback` 指向未知 request 或已取消 request
- `incident` 缺 project scope 或 audit ref
- `heartbeat` 发生在 project 已被 kill-switch / clamp 到不可自动执行时
- event payload 校验失败

## 5) memory 写回合同

### 5.1 一次事件回合最少写回三层

只要事件被正式处理，必须写回：

- `L1_CANONICAL`
  - 当前 job / plan / step authoritative state
- `L2_OBSERVATIONS`
  - 这次事件的标准化摘要
- `L4_RAW_EVIDENCE`
  - 长日志、大输出、trace ref 或 raw payload ref

### 5.2 不能只刷新预览，不写 authoritative state

冻结：

- `refreshSupervisorMemorySnapshot()` 不等于 authoritative writeback
- 只有把 canonical / observation / raw evidence 的结构化结果写回 Hub/XT store，才算本次回合完成

### 5.3 写回顺序

每次 round 至少遵守：

1. 记录事件 envelope
2. 记录 round start audit
3. 执行 Supervisor 回合
4. 写回 L1/L2/L4
5. 记录 round completion audit
6. 标记 event `completed`

若第 4 步失败：

- event 状态必须停在 `writeback_pending` 或 `failed_closed`
- 不允许把事件标成完成

## 6) 审计合同

### 6.1 每次自动回合都要有 correlation id

至少关联：

- `event_id`
- `dedupe_key`
- `project_id`
- `trigger_source`
- `job_id/plan_id/request_id`
- `memory_writeback_ref`
- `audit_ref`

### 6.2 审计链必须回答四个问题

1. 是什么事件触发了这次回合
2. 为什么它被允许或被阻止
3. 它写回了哪些 memory 层
4. 它最终完成、失败还是被隔离

### 6.3 UI 必须可见最近事件回路活动

至少在 Supervisor 侧提供：

- 最近事件列表
- 事件 source
- 当前状态
- 触发时间
- 去重结果
- writeback 结果
- audit ref

## 7) 稳定性工单拆分

### 7.1 Pack A: Durable Event Inbox

Owner:

- XT-L2 / Supervisor

交付：

- 新增 `SupervisorEventEnvelopeStore`
- 所有主触发先落 durable inbox，再入 dispatcher
- 支持 retention / ttl / replay cursor

验收：

- XT 重启后，未完成事件还能恢复
- 重复投递同一事件不会重复执行

### 7.2 Pack B: Dispatcher 与单飞行调度

Owner:

- XT-L2 / QA

交付：

- per-project single-flight dispatcher
- 事件优先级队列
- heartbeat coalescing
- supersede / pending / quarantine 机制

验收：

- 同一 project 上同时到达 `incident + heartbeat` 时，先处理 incident
- 同一 heartbeat 窗口不会产生多次重复 round

### 7.3 Pack C: 四类主触发适配器收口

Owner:

- XT-L2 / Supervisor / Hub-L5

交付：

- 把 `skill callback / grant resolution / heartbeat / incident` 接成统一 envelope
- 所有 source 统一走同一套 dedupe / dispatch / audit / writeback

验收：

- 这四类事件都能从一条标准路径进入下一轮
- 任一 source 不再依赖“临时字符串拼接+内存去重”作为最终保障

### 7.4 Pack D: Memory Writeback Barrier

Owner:

- Hub-L5 / XT-L2

交付：

- 新增 `round writeback barrier`
- 没有 L1/L2/L4 写回成功时，不允许 round 标 completed
- 写回失败自动进入 retry 或 quarantine

验收：

- 人工制造 writeback failure 时，系统不会错误宣称“已处理”

### 7.5 Pack E: 审计与可观测性

Owner:

- XT-L2 / Product / QA

交付：

- Supervisor Recent Event Loop Activity 面板
- queue depth / processing lag / duplicate suppression / quarantine count 指标
- 关键故障转 incident

验收：

- 运营或开发者能从 UI / 导出里看清每个事件回合的命运

### 7.6 Pack F: 崩溃恢复与回放

Owner:

- XT-L2 / QA / Security

交付：

- 启动恢复扫描
- 对 `persisted / eligible / dispatched / processing / writeback_pending` 的事件做 replay 判定
- 过期和脏事件进入 quarantine

验收：

- 模拟处理过程中 crash，重启后能继续或明确 fail-closed

## 8) fail-closed 规则

以下情况默认 fail-closed：

- project 已被 Hub kill-switch
- scope 不匹配
- 事件缺主键
- 回调指向不存在的 request
- 事件超过 freshness 窗口且无法证明仍有效
- audit 或 writeback 链缺关键字段

禁止：

- 静默吞掉事件
- 悄悄继续执行但没有 audit / memory 记录

## 9) 测试计划

### 9.1 合同测试

- `skill_callback` 重复回调
- `grant_resolution` 乱序到达
- `incident` 与 `heartbeat` 竞争
- `heartbeat` 风暴合并
- 事件内容缺失时 fail-closed

### 9.2 崩溃恢复测试

- `persisted -> restart -> replay`
- `processing -> crash -> restart -> recover`
- `writeback_pending -> restart -> retry / quarantine`

### 9.3 审计完整性测试

- 每个事件 round 都有 correlation id
- 每个 completed event 都有 memory writeback ref
- 每个 failed/quarantined event 都能解释原因

## 10) 完成定义

满足以下条件，才算这条主线真正完成：

1. `skill callback / grant resolution / heartbeat / incident` 都能自动拉起下一轮 Supervisor 回合。
2. 这些回合都走 durable inbox + dispatcher + dedupe + writeback + audit 的统一主线。
3. XT 崩溃或重启后，未完成事件可恢复或明确隔离。
4. memory 写回不再只是“刷新快照”，而是 authoritative 写回。
5. 重复事件、乱序事件、过期事件都能稳定处理。
6. UI 和导出都能展示最近事件回路的真实状态。
