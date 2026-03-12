# XT-W3-31 Supervisor Portfolio Awareness + Project Action Feed 详细实施包

- version: v1.0
- updatedAt: 2026-03-11
- owner: XT-L2（Primary）/ Hub-L5 / QA / AI-COORD-PRIMARY
- status: active
- scope: `XT-W3-31`（Supervisor 跨项目总览 + 项目动作事件流 + Hub 记忆摘要可见 + 定向通知）
- parent:
  - `x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-supervisor-rhythm-user-explainability-implementation-pack-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`

## 0) 为什么要单独补这份包

当前系统已经具备：

- Hub 作为记忆与治理控制面
- Supervisor 作为项目编排入口
- 多项目基础结构与部分项目 digest 展示
- delivery notification / heartbeat / blocked / authorization 等局部通知能力

但还缺一个产品级闭环：

- Supervisor 还不能自然看到“我当前管辖的全部项目”
- 项目当前动作还没有统一上报成结构化事件流
- 项目进度、项目记忆摘要、项目 blocker、当前动作仍分散在不同局部状态里
- 缺少“默认只看摘要与事件、需要时再 drill-down”的 token 最优机制
- 缺少“所有项目动作都会通知到 Supervisor，但按严重度分级，不刷屏”的统一规则

这会导致三个问题：

1. Supervisor 不能稳定掌握全局节奏。
2. 用户问“现在所有项目到哪了”时，系统需要临时扫项目、扫聊天、扫 memory，成本高且容易漏。
3. 项目 AI 的动作变化无法稳定沉淀为“可追踪、可回放、可通知”的控制面事实。

本包的目标，是把 Supervisor 从“单项目会话控制台”升级为“受辖项目 portfolio 控制台”：

- Supervisor 默认可见自己管辖项目的进度与记忆摘要
- 每个项目的当前动作必须上报
- 事件默认以 delta 形式推给 Supervisor，而不是靠轮询或全文广播
- 需要深看某一项目时，再按 scope-safe drill-down 读取更深层记忆

## 1) 固定决策

### 1.1 真相源

- 项目组合视图（portfolio truth）继续以 Hub 为真相源。
- X-Terminal 负责展示、局部缓存、会话内交互，不私自演化第二套跨项目长期真相源。

### 1.2 Supervisor 默认可见什么

Supervisor 默认只能看到其 jurisdiction 内项目的：

- project capsule 摘要
- 当前动作
- blocker / next step
- 状态机位置
- 最近事件
- 记忆新鲜度

Supervisor 默认不直接看：

- 单项目 raw evidence 全文
- 单项目完整聊天全文
- 跨项目混杂的长期全文记忆

### 1.3 默认同步模式

- 项目侧不广播全文。
- 项目侧必须持续产出：
  - `project_capsule`
  - `project_action_event`
- Supervisor 只消费：
  - `portfolio_snapshot`
  - `event_delta`
  - `scope-safe refs`

### 1.4 通知模型

所有项目的当前动作变化都必须通知到 Supervisor，但必须分级：

- `silent_log`
- `badge_only`
- `brief_card`
- `interrupt_now`
- `authorization_required`

禁止把所有事件都做成弹窗或长文广播。

### 1.5 Token 原则

- 默认只推增量，不推全文。
- 默认只推摘要，不推原文。
- 默认先给“哪个项目、发生了什么、为什么重要、下一步是什么”，而不是把项目上下文整包塞给 Supervisor。
- 需要 drill-down 时，先给 refs，再按需取详情。

### 1.6 安全边界

- Supervisor portfolio 不得跨 jurisdiction 读项目。
- lane / project / supervisor 之间不得相互广播 raw memory。
- 高风险 act 仍按原有 Hub grant / authorization / fail-closed 规则执行。
- portfolio feed 只是可见性与调度层，不是越权通道。

## 2) 产品目标

### 2.1 用户视角目标

用户打开 Supervisor 时，应自然看到：

- 我现在有多少项目
- 哪些在进行中 / 阻塞 / 等授权 / 已完成
- 每个项目当前正在做什么
- 哪个项目最值得我现在关注
- 哪个项目需要我授权或确认

### 2.2 Supervisor 视角目标

Supervisor 应能自然回答：

- “我正在管哪些项目？”
- “每个项目现在处于哪一步？”
- “最近 5 分钟有什么关键变化？”
- “哪些项目在等待我？”
- “如果我要接手某项目，现在最少需要读什么？”

### 2.3 工程目标

- 项目状态与项目动作沉淀为机读 contract
- Supervisor portfolio 支持 event-driven 更新
- 允许短 TTL cache，但不能把 stale project capsule 冒充 fresh truth
- 允许多项目并行，但必须保持 scope-safe

## 3) 机读契约冻结

### 3.1 `xt.supervisor_jurisdiction_registry.v1`

```json
{
  "schema_version": "xt.supervisor_jurisdiction_registry.v1",
  "supervisor_id": "supervisor-main",
  "projects": [
    {
      "project_id": "proj_alpha",
      "project_name": "Alpha",
      "jurisdiction_mode": "owner|observer|triage_only",
      "visibility_scope": "summary_only|portfolio_plus_drilldown",
      "memory_scope": "project_only",
      "last_bound_at_ms": 0
    }
  ],
  "audit_ref": "audit-xxxx"
}
```

### 3.2 `xt.supervisor_project_capsule.v1`

```json
{
  "schema_version": "xt.supervisor_project_capsule.v1",
  "project_id": "proj_alpha",
  "project_name": "Alpha",
  "project_state": "idle|active|blocked|awaiting_authorization|completed|archived",
  "goal": "Deliver feature X",
  "current_phase": "implementation",
  "current_action": "Implement runtime policy resolution",
  "top_blocker": "Need paid-model require-real sample",
  "next_step": "Run RR02 on paired XT device",
  "memory_freshness": "fresh|ttl_cached|stale",
  "updated_at_ms": 0,
  "status_digest": "RR02 pending; XT runtime fixed; QA waiting real sample",
  "evidence_refs": [
    "build/reports/example.json"
  ],
  "audit_ref": "audit-xxxx"
}
```

### 3.3 `xt.supervisor_project_action_event.v1`

```json
{
  "schema_version": "xt.supervisor_project_action_event.v1",
  "event_id": "evt-xxxx",
  "project_id": "proj_alpha",
  "project_name": "Alpha",
  "event_type": "started|progressed|blocked|unblocked|awaiting_authorization|completed|archived|memory_refreshed",
  "severity": "silent_log|badge_only|brief_card|interrupt_now|authorization_required",
  "actor": "project_ai|lane_ai|supervisor|user|hub",
  "action_title": "RR02 first paid-model success started",
  "action_summary": "XT switched to all_paid_models and is executing first real sample",
  "why_it_matters": "This is the last blocker for XT-TP-G5",
  "next_action": "Wait result or escalate if deny_code appears",
  "refs": [
    "build/reports/example.json"
  ],
  "occurred_at_ms": 0,
  "audit_ref": "audit-xxxx"
}
```

### 3.4 `xt.supervisor_portfolio_snapshot.v1`

```json
{
  "schema_version": "xt.supervisor_portfolio_snapshot.v1",
  "supervisor_id": "supervisor-main",
  "updated_at_ms": 0,
  "project_counts": {
    "active": 4,
    "blocked": 1,
    "awaiting_authorization": 1,
    "completed": 2
  },
  "critical_queue": [
    {
      "project_id": "proj_alpha",
      "reason": "authorization_required"
    }
  ],
  "projects": [
    {
      "project_id": "proj_alpha",
      "project_state": "awaiting_authorization",
      "current_action": "Paid-model grant challenge pending",
      "top_blocker": "Need user approval"
    }
  ],
  "audit_ref": "audit-xxxx"
}
```

### 3.5 `xt.supervisor_notification_policy.v1`

```json
{
  "schema_version": "xt.supervisor_notification_policy.v1",
  "dedupe_window_sec": 30,
  "portfolio_refresh_ttl_sec": 15,
  "interrupt_rules": [
    "authorization_required",
    "critical_path_changed",
    "blocker_resolved_on_waiting_project"
  ],
  "must_not_interrupt_rules": [
    "duplicate_progress",
    "noncritical_status_churn"
  ],
  "token_budget": {
    "max_brief_tokens": 120,
    "max_interrupt_tokens": 180
  },
  "audit_ref": "audit-xxxx"
}
```

### 3.6 `xt.supervisor_project_drilldown_request.v1`

```json
{
  "schema_version": "xt.supervisor_project_drilldown_request.v1",
  "supervisor_id": "supervisor-main",
  "project_id": "proj_alpha",
  "reason": "manual_open|critical_event|authorization_context|blocked_triage",
  "requested_depth": "capsule_only|capsule_plus_recent|capsule_plus_refs",
  "allow_raw_evidence": false,
  "audit_ref": "audit-xxxx"
}
```

## 4) 门禁与 KPI

### 4.1 Gate

- `SPF-G0`：六份 contract 冻结并机读落盘。
- `SPF-G1`：Supervisor 能看到 jurisdiction 内全部项目的 `state + current_action + blocker + next_step + freshness`。
- `SPF-G2`：项目动作变更可在 SLA 内推送到 Supervisor，且 severity 正确分级。
- `SPF-G3`：Supervisor 默认只消费 delta/capsule，不发生全文广播或跨项目记忆污染。
- `SPF-G4`：drill-down 与通知 dedupe 正确；stale capsule 不冒充 fresh；jurisdiction 外项目不可见。
- `SPF-G5`：require-real 样本验证通过，确认多项目真实运行时下：
  - 没有 missed critical event
  - 没有 duplicate interrupt flood
  - 没有 cross-project memory leak

### 4.2 KPI

- `portfolio_visibility_completeness = 100%`
- `project_action_event_delivery_rate >= 0.99`
- `critical_event_notify_latency_p95_ms <= 1500`
- `portfolio_snapshot_refresh_p95_ms <= 2000`
- `duplicate_interrupt_notification_rate <= 0.02`
- `missed_critical_event_count = 0`
- `cross_project_memory_leak_count = 0`
- `token_per_portfolio_brief_p95 <= 180`
- `stale_capsule_promoted_as_fresh = 0`

## 5) 文件级架构改造

### 5.1 X-Terminal 侧

- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 统一 portfolio state、event intake、drill-down 路由
- `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - 新增 portfolio summary rail、critical queue、project cards
- `x-terminal/Sources/AppModel+MultiProject.swift`
  - 绑定多项目状态更新源
- `x-terminal/Sources/Project/MultiProjectManager.swift`
  - 产出项目动作事件与 capsule
- `x-terminal/Sources/Project/AXProjectStore.swift`
  - 固化 project status digest / capsule 生成
- `x-terminal/Sources/Hub/HubIPCClient.swift`
  - Hub 侧 portfolio snapshot / event delta 拉取与写回

### 5.2 Hub 侧

- `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - 项目 capsule / action event / portfolio snapshot 服务入口
- `x-hub/grpc-server/hub_grpc_server/src/event_bus.js`
  - event delta 广播与 jurisdiction 过滤
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
  - Supervisor orchestration mode 的摘要组装与 drill-down 限流

### 5.3 新增建议文件

- `x-terminal/Sources/Supervisor/SupervisorPortfolioStore.swift`
- `x-terminal/Sources/Supervisor/SupervisorProjectActionFeed.swift`
- `x-terminal/Tests/SupervisorPortfolioStoreTests.swift`
- `x-terminal/Tests/SupervisorProjectActionFeedTests.swift`

## 6) 子工单分解

### 6.1 `XT-W3-31-A` Jurisdiction Registry 冻结

- 目标：明确 Supervisor 管辖项目集合，不再靠 UI 当前打开了什么项目来推断。
- 当前本地进展（2026-03-11）：
  - 已落 `SupervisorJurisdictionRegistry.swift`
  - 已接入 `SupervisorManager` 的 portfolio / action feed 过滤
  - 已冻结本地角色基线：`owner|observer|triage_only`
  - 已落地 drill-down 最大可见范围：`owner -> capsule_plus_recent`、`observer/triage_only -> capsule_only`
  - 已补纯本地验证：`SupervisorJurisdictionRegistryTests` + `SupervisorPortfolioSnapshotTests`
- 实施：
  1. 冻结 `xt.supervisor_jurisdiction_registry.v1`
  2. 为 `owner|observer|triage_only` 定义可见范围
  3. Hub 侧强制 jurisdiction 过滤
- 交付物：
  - `build/reports/xt_w3_31_a_jurisdiction_registry_evidence.v1.json`
- DoD：
  - Supervisor 只能看到 jurisdiction 内项目
  - observer 模式不可触发越权 drill-down

### 6.2 `XT-W3-31-B` Project Capsule 统一生成

- 目标：为每个项目生成稳定 capsule，供 Supervisor 低 token 消费。
- 当前进展（2026-03-11）：
  - 已落 `SupervisorProjectCapsule` 统一契约：`schema_version/project_state/current_action/top_blocker/next_step/memory_freshness/status_digest/audit_ref`
  - 已落 `SupervisorProjectCapsuleBuilder`，将 digest 编译为稳定 capsule，并可直接投影到 portfolio card
  - 已落 `SupervisorProjectCapsuleCanonicalSync`，将 capsule 以 `xterminal.project.capsule.*` 写入既有 project canonical memory 通道
  - 已在 `SupervisorManager.publishSupervisorMemoryInfo` 接入 capsule 去重同步：同一 `audit_ref` 不重复刷写，避免 Supervisor 面板刷新造成 Hub 噪音
  - 已补 `HubIPCClient.syncSupervisorProjectCapsule`，本地 IPC 先写、远端 canonical route 复用现有 Hub 配对链路
  - 已补状态归类修正：`queued/排队中` 不再误判为 `active`，与 snapshot 聚合语义对齐
  - 已补 focused tests：授权态、完成态、queued->idle 语义回归、capsule canonical key 契约、capsule IPC writeback
- capsule 最低字段：
  - `project_state`
  - `current_action`
  - `top_blocker`
  - `next_step`
  - `memory_freshness`
  - `status_digest`
- 实施：
  1. 从项目状态机、memory、runtime state 统一编译 capsule
  2. 区分 `fresh|ttl_cached|stale`
  3. 通过既有 `project_canonical_memory` 路由保存 Hub-side project capsule
- 交付物：
  - `build/reports/xt_w3_31_b_project_capsule_evidence.v1.json`
- DoD：
  - 打开 Supervisor 时无需扫描全文即可得到项目摘要

### 6.3 `XT-W3-31-C` Project Action Event Feed

- 目标：项目当前动作必须上报为结构化事件。
- 当前进展（2026-03-11）：
  - 已落本地 `SupervisorProjectActionEvent` feed
  - 已把 project action delivery 决策接入统一 notification policy
  - 已落 machine-readable audit sink：`supervisor_project_action_audit`
  - 已覆盖 `delivered` / `suppressed_duplicate` 两种 audit 状态
  - 已补 Hub service-side consumer：`FileIPC` + `UnixSocketServer` + `audit_events` 持久化
  - 已补 Hub focused tests：IPC round-trip + audit row persistence
  - 已补 paired remote route：通过 `UpsertCanonicalMemory` 将 project action canonical delta 写回 Hub
  - 已补 project action canonical sync tests：固定 key 集 + summary_json 契约
- 必须覆盖事件：
  - `started`
  - `progressed`
  - `blocked`
  - `unblocked`
  - `awaiting_authorization`
  - `completed`
  - `memory_refreshed`
- 实施：
  1. 项目侧动作变化统一走 event emitter
  2. 事件附带 severity 与 refs
  3. 去重相邻相同事件
- 交付物：
  - `build/reports/xt_w3_31_c_project_action_feed_evidence.v1.json`
- DoD：
  - “当前动作”有明确 machine-readable 来源

### 6.4 `XT-W3-31-D` Portfolio Snapshot 聚合

- 目标：Supervisor 一次加载即可看到全局 portfolio。
- 当前进展（2026-03-11）：
  - 已落 `SupervisorPortfolioSnapshotBuilder` 聚合：`counts + critical_queue + sorted project cards`
  - 已支持 `runtime_state -> current_action` fallback，避免无摘要项目被空白化
  - 已补 `AXProjectEntry -> SupervisorProjectActionEvent` 投影：授权态/阻塞态/完成态/推进态统一归类
  - 已补 focused tests：排序、计数、critical queue、authorization/blocker severity、queued idle fallback
  - 已补 `SupervisorPortfolioSnapshotCanonicalSync`：冻结 `xt.supervisor_portfolio_snapshot.v1`，输出 `status_line + counts_json + critical_queue_digest + projects_digest + summary_json`
  - 已补 `HubIPCClient.syncSupervisorPortfolioSnapshot` + `SupervisorManager` 指纹去重同步：`updated_at` 漂移不再触发重复写回
  - 已补 Hub 本地 `device_canonical_memory` 写入：`HubModels + FileIPC + UnixSocketServer + DeviceCanonicalMemoryStorage`
  - 已补 paired remote `device` scope canonical upsert：Supervisor portfolio 可以经 Hub 远程记忆真源消费
  - 已补 focused XT/Hub tests：canonical contract、local IPC sync、Hub payload roundtrip、Hub device store roundtrip
- 实施：
  1. Hub 聚合 jurisdiction 内项目 capsule
  2. 编译 `critical_queue`
  3. 输出 counts / order / snapshot version
- 交付物：
  - `build/reports/xt_w3_31_d_portfolio_snapshot_evidence.v1.json`
- DoD：
  - snapshot 不依赖项目全文扫描
  - blocker / awaiting_authorization 项进入优先队列
  - Hub device canonical truth-source 落地且可由 XT/Hub 双侧机读消费

### 6.5 `XT-W3-31-E` Directed Notification Policy

- 目标：所有项目动作能通知到 Supervisor，但不刷屏。
- 当前本地进展（2026-03-11）：
  - 已落 `SupervisorProjectNotificationPolicy.swift`
  - 已冻结本地 severity -> delivery channel 映射：`silent_log|badge_only|brief_card|interrupt_now`
  - 已把 project event interrupt 逻辑收敛到统一策略层，不再在 `handleEvent` 里散落条件分支
  - 已落 dedupe window：重复 authorization / interrupt 不再反复打断
  - 已在 portfolio 面板显示 notification policy 状态线
  - 已接入 Hub push route：`brief_card` / `interrupt_now` 项目动作会写到 `push_notification`，并沿用同一 dedupe fingerprint
- 实施：
  1. 冻结 severity -> delivery channel 映射
  2. 实现 dedupe window
  3. 实现 `interrupt_now` / `authorization_required` 强提醒
  4. 非关键进度降为 badge 或 brief
- 交付物：
  - `build/reports/xt_w3_31_e_notification_policy_evidence.v1.json`
- DoD：
  - duplicate interrupt flood 为零
  - missed critical event 为零

### 6.6 `XT-W3-31-F` Supervisor Portfolio UI

- 目标：把当前零散 digest 升级为真实 portfolio 面板。
- 当前本地进展（2026-03-11）：
  - 已落 portfolio board：counts / critical queue / recent action feed
  - 已接入 notification policy 状态线
  - 已把 project card 绑定到本地 drill-down panel
  - portfolio 有可见项目时会自动定位第一张卡的 drill-down
- UI 最低要求：
  - 总项目数
  - active/blocked/awaiting_authorization/completed 计数
  - critical queue
  - 每项目卡片：
    - project_name
    - project_state
    - current_action
    - top_blocker
    - next_step
    - memory_freshness
    - last_event
- 交付物：
  - `build/reports/xt_w3_31_f_portfolio_ui_evidence.v1.json`
- DoD：
  - 用户打开 Supervisor 首屏即可回答“当前所有项目到哪了”

### 6.7 `XT-W3-31-G` Drill-down Contract + Scope-safe Memory

- 目标：让 Supervisor 能进一步看单项目，但不破坏 token 和安全边界。
- 当前本地进展（2026-03-11）：
  - 已落 `SupervisorProjectDrillDown.swift`
  - 已在 `SupervisorManager` 冻结本地 drill-down contract：`capsule_only` / `capsule_plus_recent`
  - 已实现 jurisdiction 先验过滤，项目不可见时直接 deny
  - 已实现 observer / triage_only 的 scope cap，禁止升级到 `capsule_plus_recent`
  - 已把 portfolio card 接到 drill-down panel，用户可直接查看 scope-safe 单项目摘要
  - 已把 scope-safe Hub refs 接到 drill-down panel：`xterminal.project.snapshot` / `xterminal.project.capsule.summary_json` / `xterminal.project.action.summary_json`
  - raw evidence 在本地 contract 中继续保持禁用
- 实施：
  1. 默认只打开 `capsule_only`
  2. critical event / blocked triage 时允许 `capsule_plus_recent`
  3. raw evidence 默认禁用
  4. jurisdiction 外一律 deny
- 交付物：
  - `build/reports/xt_w3_31_g_drilldown_contract_evidence.v1.json`
- DoD：
  - 不发生跨项目全文注入
  - raw evidence 不被自动展开

### 6.8 `XT-W3-31-H` Require-real 回归 + GO/NO-GO

- 目标：用真实多项目运行样本验证整条链路。
- 当前本地进展（2026-03-11）：
  - 已落 `build/reports/xt_w3_31_require_real_capture_bundle.v1.json`，供 `XT-Main` 直接按 7 个 SPF-G5 样本执行并回填
  - 已落 `build/reports/xt_w3_31_h_require_real_evidence.v1.json`，供 `QA-Main` fail-closed 消费 capture bundle 并给出 shadow checklist 结论
  - 已落 `scripts/update_xt_w3_31_require_real_capture_bundle.js`，供执行者按样本最小增量回填 machine-readable 结果
  - 已落 `scripts/generate_xt_w3_31_require_real_report.js`，用于在 capture bundle 更新后自动重算 `XT-W3-31-H` 的 QA 机读结论
  - 已落 `scripts/xt_w3_31_require_real_status.js` + `docs/memory-new/xt-w3-31-require-real-runbook-v1.md`，用于两机实跑时直接定位“下一个样本 + 建议回填命令 + QA 重算命令”
  - 当前口径仍为 `NO_GO`：A..G 已有机读证据，但 H 仅到 `ready_for_execution`，真实样本尚未执行
- require-real 最小样本：
  1. 新项目创建后 3 秒内出现在 portfolio
  2. 项目进入 blocked 后 Supervisor 收到 brief
  3. 项目进入 awaiting_authorization 后 Supervisor 收到 interrupt
  4. 项目完成后 current_action 清空并转 completed
  5. 同时 3 个项目高频更新时，无 duplicate interrupt flood
  6. observer jurisdiction 下无法 drill-down 到 owner-only 项目
  7. stale capsule 不被展示成 fresh
- 交付物：
  - `build/reports/xt_w3_31_require_real_capture_bundle.v1.json`
  - `build/reports/xt_w3_31_h_require_real_evidence.v1.json`
  - `scripts/update_xt_w3_31_require_real_capture_bundle.js`
  - `scripts/generate_xt_w3_31_require_real_report.js`
  - `scripts/xt_w3_31_require_real_status.js`
  - `docs/memory-new/xt-w3-31-require-real-runbook-v1.md`
- DoD：
  - SPF-G5 转绿前不得宣告 release-ready

## 7) 回归样例

### 7.1 Portfolio 可见性

- 场景：Supervisor 绑定 5 个项目，其中 2 个 active、1 个 blocked、1 个 awaiting_authorization、1 个 completed
- 断言：
  - counts 正确
  - critical queue 正确
  - 每个项目卡片字段完整

### 7.2 动作上报

- 场景：项目从 `implementation` 进入 `blocked(waiting_rr02)`
- 断言：
  - 生成 `blocked` event
  - severity = `brief_card`
  - Supervisor 卡片 current_action 与 top_blocker 同步更新

### 7.3 授权中断

- 场景：项目进入高风险动作，需要用户授权
- 断言：
  - event_type = `awaiting_authorization`
  - severity = `authorization_required`
  - Supervisor 能看到 why_it_matters + next_action

### 7.4 去重

- 场景：相同 progress 事件 10 秒内连续 3 次
- 断言：
  - 只允许 1 次 brief
  - 其余进入 silent_log 或合并

### 7.5 Scope-safe drill-down

- 场景：Supervisor 请求某项目 drill-down
- 断言：
  - 只返回 capsule/recent/refs
  - 不自动附 raw evidence
  - observer 不可越权展开 owner-only 项目

### 7.6 Stale freshness

- 场景：某项目 Hub snapshot 超过 TTL，且未刷新
- 断言：
  - `memory_freshness = stale`
  - UI 不得显示为 latest/fresh

## 8) 风险与 fail-closed 规则

### 8.1 风险

- 项目过多时 portfolio 事件风暴
- 项目动作与项目 capsule 不一致
- stale cache 被误当成最新状态
- observer / triage_only 误拿到深层上下文
- 多终端同时开 Supervisor 时出现重复提醒

### 8.2 Fail-closed

- jurisdiction 缺失 -> 不展示项目
- capsule 字段不完整 -> 不宣告 visibility complete
- event severity 缺失 -> 降级为 `silent_log`，不得冒充 interrupt
- freshness 不确定 -> 标记 `stale`
- drill-down contract 缺失 -> 只返回 capsule_only

## 9) 不在本包范围内

- 不把 Supervisor 升级成跨项目全文聊天搜索器
- 不自动把所有项目完整记忆注入到一个 prompt
- 不改变高风险授权链本身
- 不做跨组织/跨租户 portfolio
- 不处理 portfolio 外的 enterprise billing/reporting

## 10) 验收口径

- 用户打开 Supervisor 时，能自然看到自己管辖的所有项目进度
- 每个项目都有可见 current_action
- 所有关键动作变化都能通知到 Supervisor
- 默认显示 summary/delta，不依赖全文扫描
- 需要深入时有 scope-safe drill-down
- 没有 cross-project memory leak
- 没有 duplicate interrupt flood

## 11) 交付建议顺序

1. `XT-W3-31-A` registry
2. `XT-W3-31-B` capsule
3. `XT-W3-31-C` action event
4. `XT-W3-31-D` portfolio snapshot
5. `XT-W3-31-E` notification policy
6. `XT-W3-31-F` portfolio UI
7. `XT-W3-31-G` drill-down contract
8. `XT-W3-31-H` require-real

## 12) 对 7 条 / 4 条 AI 的执行要求

- 只允许按 `capsule + event + snapshot + drill-down` 这四层推进，不扩功能范围。
- 不允许把单项目全文记忆广播给 Supervisor。
- 不允许用 synthetic/mock 冒充 `require-real`。
- 所有新增 UI/事件/状态必须 machine-readable 落盘。
- release 口径只在 `SPF-G0..G5` 全绿后开放。
