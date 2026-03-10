# X-Hub Connector Reliability Kernel 执行工单（效率 + 安全）

- version: v1.0
- updatedAt: 2026-02-28
- owner: Hub Connectors / Memory / Security / Supervisor 联合推进
- status: active
- parent:
  - `docs/memory-new/xhub-memory-v3-execution-plan.md`
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`

## 0) 目标与边界

目标（本轮）
- 抽象一套可复用的 Connector 可靠性内核：统一处理重连、回退、游标、去重、幂等投递、审计与门禁。
- 让 X-Hub 在多通道/多终端并发下，保持“低时延 + 可恢复 + 不越权”。
- 为 M3 场景（Supervisor 并行项目、机器人任务链路、支付前确认）提供稳定底座。

边界（本轮不做）
- 不引入新的业务能力（如新支付协议、新模型供应商）。
- 不改变既有 Memory truth model（仍以 DB source-of-truth + Promotion Gate 为准）。
- 不牺牲 fail-closed：任何 gate/状态异常都默认阻断或降级，而不是放行。

## 1) 设计原则

- `fail_closed_first`：门禁异常、状态损坏、签名不可信，一律 deny/downgrade。
- `idempotency_by_default`：所有入站事件与出站动作必须可重放、可去重。
- `durable_cursor`：游标持久化与断点续跑是默认能力，不依赖内存态。
- `explicit_state_machine`：连接/投递/回写全流程状态机化，禁止隐式分支。
- `audit_minimal_but_sufficient`：审计默认 metadata-only，保留可追溯字段。
- `policy_in_the_path`：策略门禁必须在运行链路内联，不依赖“文档约定”。
- `authz_parity_for_all_ingress`：消息与非消息入口（reaction/pin/member/webhook）必须同等授权校验。
- `bounded_preauth_surface`：未鉴权请求必须有 body/key/state 上限，防资源耗尽。
- `approval_identity_binding`：审批与执行身份强绑定（argv/cwd/identity），禁止审批复用。

## 2) 内核能力模型

### 2.1 Inbound Reliability

- 目标：确保“收到一次就处理一次；重复收到不重复执行”。
- 核心能力：
  - 目标级游标（cursor）持久化 + debounce 写盘。
  - 消息 ID 去重（滑动窗口 + TTL）。
  - 重连失败自动回退（WebSocket -> polling/watch）。
  - 目标级锁（target lock）避免并发乱序。

### 2.2 Outbound Reliability

- 目标：确保“外部动作要么可确认完成，要么可恢复重试，不出现不可解释状态”。
- 核心能力：
  - Outbox（prepare -> dispatch -> ack/fail -> compensate）。
  - 幂等键（`connector + target + action + nonce`）防止重复副作用。
  - 可选补偿（undo window）与超时回滚。
  - 统一错误语义（`timeout`, `unavailable`, `forbidden`, `policy_blocked`, `state_corrupt`）。

### 2.3 Security Gate Inline

- 目标：外发前最后一道闸门，阻断 secret/credential 越界。
- 核心能力：
  - sensitivity/trust/scope gate 强制执行。
  - `prompt_bundle` 二次 DLP 与 credential 永久 deny。
  - blocked 后统一降级：`downgrade_to_local` 或显式错误返回。

### 2.4 Observability

- 目标：让可靠性和安全问题都可量化、可定位、可回放。
- 必备指标：
  - `connector_reconnect_ms_p95`
  - `inbound_dup_drop_rate`
  - `outbox_ack_ms_p95`
  - `delivery_retry_count_p95`
  - `policy_block_rate`
  - `downgrade_rate`
  - `state_corrupt_incidents`
  - `preauth_reject_rate`
  - `unauthorized_flood_drop_count`
  - `webhook_replay_block_rate`

## 3) 数据与接口（建议实现约束）

### 3.1 新增持久化对象（建议）

- `connector_cursor_state`
  - key: `(connector, target_id)`
  - fields: `cursor`, `updated_at_ms`, `version`
- `connector_seen_events`
  - key: `(connector, target_id, event_id_hash)`
  - fields: `first_seen_at_ms`, `ttl_expire_at_ms`
- `connector_outbox`
  - key: `outbox_id`
  - fields: `scope`, `action_kind`, `payload_hash`, `state`, `retry_count`, `next_retry_at_ms`
- `connector_delivery_receipts`
  - key: `(connector, target_id, idempotency_key)`
  - fields: `delivery_state`, `provider_receipt`, `updated_at_ms`
- `connector_webhook_replay_guard`
  - key: `(connector, target_id, replay_key_hash)`
  - fields: `first_seen_at_ms`, `expire_at_ms`

### 3.2 统一状态机

- 连接态：`idle -> connecting -> ready -> degraded_polling -> recovering -> ready`
- 入站态：`received -> dedup_checked -> gated -> queued -> processed`
- 出站态：`prepared -> gated -> dispatched -> acked | retrying | failed | compensated`
- 任何非法状态迁移：`-> state_corrupt (fail-closed)`

### 3.3 审计扩展字段（对齐 `xhub.memory.metrics.v1`）

- `metrics.connector.name`
- `metrics.connector.target_kind`
- `metrics.connector.delivery_state`
- `metrics.connector.retry_count`
- `metrics.security.blocked`
- `metrics.security.deny_code`
- `metrics.security.downgraded`

## 4) 工单拆解（按优先级）

### P0（阻断主线）

1. `CRK-W1-01` 统一 Connector Envelope 协议
- 目标：统一 inbound/outbound 事件 envelope（含 scope/sensitivity/trust/request_id）。
- 交付物：schema + parser + validation（坏包 fail-closed）。
- 验收：非法字段/缺字段/版本不匹配均可解释拒绝。

2. `CRK-W1-02` Cursor + Seen Event 持久化
- 目标：补齐 durable cursor 与去重表。
- 交付物：DB schema + storage API + TTL 清理作业。
- 验收：重启后可从上次 cursor 续跑；重复消息不重复处理。

3. `CRK-W1-03` Outbox 幂等投递骨架
- 目标：出站统一走 outbox，禁止直发。
- 交付物：prepare/dispatch/ack/retry 状态机。
- 验收：网络抖动下不出现重复副作用；可回放。

4. `CRK-W1-04` 内联 Security Gate
- 目标：出站与远程外发强制走 gate。
- 交付物：gate hook（scope/sensitivity/trust/DLP）。
- 验收：命中 credential/key material 必阻断，审计字段齐全。

5. `CRK-W1-05` 统一错误语义与 fail-closed
- 目标：收敛 connector 错误码，不再“字符串猜错”。
- 交付物：error map + typed error + downgrade policy。
- 验收：所有失败路径有稳定错误码，默认不放行。

6. `CRK-W1-06` 非消息入口授权等价
- 目标：确保 reaction/pin/member/webhook 事件与 message 同级别授权，不留侧门。
- 交付物：shared ingress authorizer + 事件类型规范化 + 拒绝码映射。
- 验收：`non_message_ingress_policy_coverage = 100%`；`blocked_event_miss_rate < 1%`。
- 实施进度（2026-02-28）：已新增 `x-hub/grpc-server/hub_grpc_server/src/connector_ingress_authorizer.js` 并接入 `pairing_http.js` 入口，统一 `message/reaction/pin/member/webhook` 授权链；补齐 DM pairing 与 group allowlist 边界隔离（`dm_pairing_scope_violation`）、统一 machine-readable deny_code 与 `connector.ingress.allowed|denied` 审计；新增 `connector_ingress_authorizer.test.js` 与 `pairing_http_preauth_replay.test.js` 回归覆盖未授权 `reaction/pin/member/webhook` 拒绝、DM 边界、`non_message_ingress_policy_coverage` 与 `blocked_event_miss_rate` 统计字段；并新增 `audit_write_failed` fail-closed（connector ingress 授权审计写失败时拒绝放行）。同时补齐 machine-readable gate 证据快照：`xhub.connector.non_message_ingress_gate.v1`（`pass` + `incident_codes`），并新增 `buildNonMessageIngressGateSnapshot(FromAuditRows)` 统一发布证据结构，Webhook 审计扩展字段补齐 `non_message_ingress_gate_metrics` 便于 release gate 直接消费；新增 Admin 证据导出接口 `GET /admin/pairing/connector-ingress/gate-snapshot`（支持 `source=auto|audit|scan`）用于真实审计证据归档。
- Admin 证据接口契约（v1）：
  - 路径：`GET /admin/pairing/connector-ingress/gate-snapshot`
  - 鉴权：`Authorization: Bearer ${HUB_ADMIN_TOKEN}`
  - Query：`source=auto|audit|scan`；可选 `since_ms/until_ms/device_id/user_id/project_id/request_id/limit`
  - `source=auto`：优先返回 `audit` 快照；无审计行时自动回退 `scan`
  - 成功响应关键字段：`source_used`、`data_ready`、`audit_row_count`、`scan_entry_count`、`snapshot`、`snapshot_audit`、`snapshot_scan`
  - `snapshot.schema_version` 固定：`xhub.connector.non_message_ingress_gate.v1`
  - `snapshot.metrics` 固定包含：`non_message_ingress_policy_coverage`、`blocked_event_miss_rate`
  - 非法 `source`：HTTP `400` + `error.code=invalid_request`
  - XT-Ready 证据链接通：`scripts/m3_fetch_connector_ingress_gate_snapshot.js` 负责抓取该接口快照，`scripts/m3_extract_xt_ready_incident_events_from_audit.js --connector-gate-json` 负责把 `snapshot.metrics.blocked_event_miss_rate` 注入 E2E summary（`summary.blocked_event_miss_rate`）。
  - XT-Ready 硬门禁已升级：`scripts/m3_check_xt_ready_gate.js` 额外强制 `summary.non_message_ingress_policy_coverage >= 1`，并在 `.github/workflows/m2-memory-bench.yml` 接入 snapshot 抓取（Hub real 优先，sample fallback）。
  - 增量加固（2026-02-28）：当 `--require-real-audit-source` 开启时，`scripts/m3_check_xt_ready_gate.js` 额外强制 E2E 证据 `source.connector_gate_source_used = audit` 且 `source.connector_gate_snapshot_attached = true`，防止真实审计模式下误接 `scan` 快照。

7. `CRK-W1-07` 预鉴权限流与重放防护
- 目标：阻断 pre-auth 资源耗尽与 webhook 重放。
- 交付物：pre-auth body cap、key-cap、stale-state prune、replay dedupe store。
- 验收：`preauth_memory_growth_unbounded = 0`；`webhook_replay_accept_count = 0`。
- 实施进度（2026-02-28）：`pairing_http.js` 已补齐 pre-auth 资源边界（body cap + source-key state cap + stale prune）与 webhook replay guard（`(connector,target_id,replay_key_hash)` TTL 去重）；新增 `pairing_http_preauth_replay.test.js` 覆盖高频 source-key 旋转有界、重复签名二次拒绝、同 signature 不同 replay_key 不误杀、state overflow 拒绝、组件异常 fail-closed（含 preauth/replay 组件异常）、replay TTL 到期后可重新接收，以及 ingress 审计指标完整性断言（accepted/rejected 均必须输出 `preauth_reject_rate` / `webhook_replay_block_rate`）；新增 `connector_webhook_replay_guard` DB 持久去重表与 `claim/prune/stats` 原子接口，Webhook 防重放可跨 Hub 重启持续生效，并新增“同 replay key 跨重启二次必拒绝”的实测用例；`kq_security_invariants.test.js` 已并入 `CM-W3-18/CRK-W1-07` guard 回归用例（含 replay TTL、false-positive 防护语义与 HubDB reopen 持久化重放拒绝），且 `.github/workflows/kq-security-invariants.yml` 已接入 `connector_ingress_authorizer.test.js` + `pairing_http_preauth_replay.test.js` 双重门禁用于 CI 持续校验。

8. `CRK-W1-08` WebSocket 未授权洪泛熔断
- 目标：避免单连接重复 `unauthorized` 请求拖垮网关。
- 交付物：per-connection flood breaker、拒绝日志采样、连接级速率惩罚。
- 验收：`unauthorized_flood_drop_count` 可观测且服务吞吐不退化。
- 实施进度（2026-02-28）：`pairing_http.js` 已新增 `createUnauthorizedFloodBreaker`（单连接窗口计数 + penalty 窗口 + stale prune + state cap）并接入 webhook ingress 链路，连续未授权请求触发 `unauthorized_flood_dropped` 早拒绝；拒绝审计支持采样（`HUB_UNAUTHORIZED_FLOOD_AUDIT_SAMPLE_EVERY`）并补齐 `unauthorized_flood_drop_count` 指标；新增 `pairing_http_preauth_replay.test.js` 覆盖 keep-alive 单连接洪泛熔断与组件异常 fail-closed，`kq_security_invariants.test.js` 补齐 guard 级别不变式（跨连接隔离 + fail-closed）。

### P1（关键收益）

9. `CRK-W2-01` Reconnect/Fallback Orchestrator
- 目标：统一 WebSocket 重连与 polling 回退调度器。
- 交付物：connector runtime state manager。
- 验收：断网/恢复下 reconnect p95 达标。
- 实施进度（2026-02-28）：已新增 `connector_reconnect_orchestrator.js` 最小骨架，提供显式连接状态机（`idle -> connecting -> ready -> degraded_polling -> recovering -> ready`）、指数退避重连调度（`reconnect_tick` 触发）、state cap + stale prune 与 fail-closed 拒绝（`state_corrupt` / `orchestrator_fail_closed`）；`snapshot()` 已输出 `connector_reconnect_ms_p95`、`reconnect_attempts`、`fallback_entries`、`state_corrupt_incidents`。`pairing_http.js` 已接入 orchestrator（webhook 收敛链路写入 `polling_ok` 信号，异常时 `connector_runtime_orchestrator_error` fail-closed），并新增 admin 运行态端点（`/admin/pairing/connector-runtime/{signal|target|snapshot}`）用于受控注入/观测。新增 `connector_reconnect_orchestrator.test.js` 与 `pairing_http_preauth_replay.test.js` 回归覆盖主干迁移、非法迁移 fail-closed、时钟异常 fail-closed、target 集合有界与 prune 回收，以及 runtime 端点状态驱动与 webhook 入口 fail-closed。

10. `CRK-W2-02` Target-level Lock + Ordering Guard
- 目标：目标级串行保证与乱序防护。
- 交付物：target lock + sequence check。
- 验收：并发高压下不出现乱序回写。
- 实施进度（2026-02-28）：已新增 `connector_target_ordering_guard.js` 最小可运行实现（target lock + event_id 去重 + sequence 单调检查 + stale prune + state cap），并在 webhook ingress 链路接入 `begin/complete`（受理前加锁、提交后更新序列）；新增 fail-closed 拒绝码 `ordering_guard_error` 与 machine-readable 拒绝码 `target_locked` / `out_of_order_event` / `duplicate_event`。`pairing_http.js` 已补 admin 观测端点（`/admin/pairing/connector-ordering/{snapshot|target}`）与 ordering 审计指标（`connector_target_lock_conflict_count` / `connector_out_of_order_reject_count` / `connector_duplicate_event_reject_count`）。新增 `connector_target_ordering_guard.test.js` 与 `pairing_http_preauth_replay.test.js` 覆盖 target lock、乱序拒绝、入口 fail-closed。

11. `CRK-W2-03` Delivery Receipt & Compensation
- 目标：投递回执统一建模，支持补偿/撤销窗口。
- 交付物：receipt store + compensate worker。
- 验收：失败可恢复，补偿动作幂等。
- 实施进度（2026-02-28）：已新增 `connector_delivery_receipt_compensator.js` 最小骨架，补齐 `prepare/commit/undo` 显式状态迁移（`prepared -> committed | undo_pending -> compensated`）、commit timeout 自动转补偿、补偿重试窗口与 state cap/stale prune；`pairing_http.js` webhook ingress 已联动 receipt `prepare -> commit`，在 runtime/order/receipt 异常路径统一触发 `undo` 并以 `connector_delivery_receipt_error` fail-closed 拒绝；新增 admin 观测/执行端点 `GET /admin/pairing/connector-receipt/{snapshot|target|item}` 与 `POST /admin/pairing/connector-receipt/compensate`。测试已覆盖 `connector_delivery_receipt_compensator.test.js`（状态机、超时补偿、补偿重试、有界性/fail-closed）以及 `pairing_http_preauth_replay.test.js` 与 `kq_security_invariants.test.js` 的 W2-03 回归（入口 fail-closed、补偿端点、守卫异常 fail-closed）。

12. `CRK-W2-04` Metrics & Dashboard Wiring
- 目标：接入统一指标 schema 与告警阈值。
- 交付物：metrics emitter + dashboard panels。
- 验收：异常可在 5 分钟内定位 connector/target/阶段。

### P2（增强项）

13. `CRK-W3-01` Chaos Drill Suite
- 目标：网络分区、半开连接、重复事件、时钟偏移演练。
- 交付物：chaos scripts + weekly drill report。
- 验收：关键故障 MTTR 达标。

14. `CRK-W3-02` Adaptive Backoff & Priority Queue
- 目标：高负载时优先保障高价值/低风险动作。
- 交付物：优先级队列 + backoff 策略。
- 验收：p95 延迟与失败率可控，无饥饿。

## 5) 六周排程映射（与 M2/M3 对齐）

- 2026-03-02 ~ 2026-03-08（W1）
  - 完成 `CRK-W1-01..03`（协议、游标、outbox 基座）。
- 2026-03-09 ~ 2026-03-15（W2）
  - 完成 `CRK-W1-04..07`（内联 gate + 错误语义 + 非消息入口授权等价 + pre-auth 防护）。
- 2026-03-16 ~ 2026-03-22（W3）
  - 完成 `CRK-W1-08` + `CRK-W2-01..02`（WS 洪泛熔断 + 重连回退 + 乱序防护）。
- 2026-03-23 ~ 2026-03-29（W4）
  - 完成 `CRK-W2-03`（回执与补偿），联动 Connector prepare/commit/undo。
- 2026-03-30 ~ 2026-04-05（W5）
  - 完成 `CRK-W2-04`（观测看板），纳入发布门禁。
- 2026-04-06 ~ 2026-04-12（W6）
  - 完成 `CRK-W3-01` chaos drills；`CRK-W3-02` 灰度验证。

## 6) 回归矩阵（最小集合）

Correctness
- 空 payload / 损坏 payload / 超长 payload / schema 版本不匹配。
- 重复 event_id / 重复 idempotency_key。
- 断点续跑后顺序一致性。

Security
- 越界 scope 请求。
- secret shard 远程外发。
- credential finding 命中阻断。
- gate 组件异常时 fail-closed。
- 非消息入口越权事件（reaction/pin/member/webhook）必须拒绝。
- DM pairing 授权不得跨到 group allowlist。
- pre-auth body 超限与重复签名 webhook 重放必须拒绝。

Reliability
- 连接抖动（短断/长断）。
- WebSocket 不可用自动降级 polling。
- provider 回执丢失后重试与去重。
- rollback/compensation 幂等。

Performance
- reconnect p95。
- outbox ack p95。
- retry 开销上限。
- 高并发下 queue 深度与 oldest wait。

## 7) 里程碑 DoD

M2 末（Gate-ready）
- P0 工单全完成。
- Security gate 内联路径覆盖率 100%。
- 出站动作全量可追踪到 outbox + receipt。

M3 末（Scenario-ready）
- 多项目 heartbeat + Supervisor 汇总在连接抖动下稳定。
- 机器人链路（拍照/报价/确认/支付）可在故障场景下安全降级。
- 故障演练报告可复现，且未出现越权副作用。
