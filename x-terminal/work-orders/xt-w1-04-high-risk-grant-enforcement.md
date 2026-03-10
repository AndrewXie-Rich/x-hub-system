# XT-W1-04：高风险动作 grant 强制 + 旁路扫描

- workOrder: `XT-W1-04`
- priority: `P0`
- gate: `XT-G2`, `XT-G4`
- status: `in_progress`
- owner: `Lane-C (Security)`
- updatedAt: `2026-02-27`

## 1) 目标与边界

目标：高风险能力（当前范围：`web_fetch`）必须携带有效 `grant_id`，否则 fail-closed；同时提供旁路扫描器，持续监控历史执行日志中的无授权执行。

本轮边界（代码落点）：
- `Sources/Tools/ToolExecutor.swift`
- `Sources/Tools/ToolProtocol.swift`
- `Sources/Chat/ChatSessionModel.swift`

## 2) 统一 gate hook（高风险动作前置校验）

### 2.1 强制规则

- `web_fetch` 必须包含 `args.grant_id`（兼容读取 `grant_request_id`）。
- 缺失/无效/过期/桥接未启用时，统一拒绝并返回标准拒绝码。
- 未通过 gate 的高风险动作不进入实际执行链路（remote/file 均阻断）。

### 2.2 标准拒绝码

- `high_risk_grant_missing`
- `high_risk_grant_invalid`
- `high_risk_grant_expired`
- `high_risk_bridge_disabled`

统一输出前缀：
- `high_risk_denied (code=..., capability=capability_web_fetch) - ...`

## 3) grant 记录与有效性

- `need_network` 成功路径（`enabled`/`autoApproved`）会登记可用 grant（含 TTL）。
- 若上游未返回 grant id，则生成会话级 `session_grant_*` 占位 token，避免“网络已开但无法携带 token”的死锁。
- `web_fetch` gate 读取运行时 grant ledger，按项目根路径 + capability + grant_id 校验。
- grant 超时后继续重放会返回 `high_risk_grant_expired`（显式拒绝 replay）。

## 4) 旁路扫描器（bypass scanner）

新增扫描能力：
- 扫描 `raw_log.jsonl` 中 `tool:web_fetch` 记录。
- 识别 `ok=true` 且输入缺失 `grant_id` 的旁路执行。
- 输出结构化统计：
  - 扫描工具事件数
  - web_fetch 事件数
  - 被 gate 拒绝数
  - 旁路发现数（`bypass_grant_execution`）

Slash 可观测：
- `/grant status`
- `/grant scan`
- `/grant selftest`

## 5) 回归样例（对应工单验收）

### Case-A: 无 grant_id 执行高风险动作

- 输入：`web_fetch` 不带 `grant_id`。
- 预期：返回 `high_risk_denied (code=high_risk_grant_missing, ...)`，执行被阻断。

### Case-B: 过期 grant 重放

- 输入：使用已过期 grant 执行 `web_fetch`。
- 预期：返回 `high_risk_grant_expired`，拒绝并标注 replay denied。

### Case-C: 旁路扫描

- 输入：对项目 raw_log 执行 `/grant scan`。
- 预期：输出 `bypass findings`，若存在无授权成功执行则明确 FAIL 并列出条目。

## 6) 手工验证建议

1. 先执行 `/grant selftest`，确认 gate 基本规则 PASS。
2. 触发 `need_network`，从输出抓取 `grant=...`，再调用 `web_fetch`：
   - 带 grant：应正常执行。
   - 不带 grant：应立即拒绝。
3. 执行 `/grant scan`，确认旁路计数为 0（或可定位历史问题条目）。

## 7) 下一步（衔接 XT-W2-07 / XT-W3-08）

1. 将高风险 capability 扩展到 skills 高风险执行路径（XT-W2-07）。
2. 将 `/grant selftest` 与 `/grant scan` 接入 CI gate smoke（XT-W3-08）。
   - 进展：已接入 `xt-grant-smoke` 运行时门禁入口（`swift run XTerminal --xt-grant-smoke`），后续补齐真实 Hub 联调回归。
