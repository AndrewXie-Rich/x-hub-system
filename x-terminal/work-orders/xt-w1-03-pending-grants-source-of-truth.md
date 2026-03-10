# XT-W1-03：Pending Grants 真相源接入 Supervisor

- workOrder: `XT-W1-03`
- priority: `P0`
- gate: `XT-G1`, `XT-G3`
- status: `in_progress`
- owner: `Lane-D (Supervisor/UX)`
- updatedAt: `2026-02-27`

## 1) 目标与边界

目标：Supervisor 的授权状态只来自 Hub pending grants 快照，不再依赖日志推断；并提供可执行的审批入口（Approve / Deny / Open）。

本轮边界（代码落点）：
- `Sources/Supervisor/SupervisorManager.swift`
- `Sources/Supervisor/SupervisorView.swift`

## 2) 真相源收敛策略

### 2.1 唯一数据源

- Pending grants 只从 `HubIPCClient.requestPendingGrantRequests(...)` 快照读取。
- 不再使用 `raw_log` 的 `need_network` 事件推断“待授权”状态。
- 快照过期（stale）时，Supervisor 明确展示“快照不可用”，不做日志兜底。

### 2.2 Supervisor 发布态（给 UI / 心跳复用）

- `pendingHubGrants`: 归一化后的待授权列表（已去重、已排序）。
- `pendingHubGrantSource`: 快照来源（grpc/file）。
- `pendingHubGrantUpdatedAt`: 最近快照时间戳。
- `hasFreshPendingHubGrantSnapshot`: 快照新鲜度标志。
- `pendingHubGrantActionsInFlight`: 当前审批动作进行中集合。

## 3) 去重与排序策略（满足工单验收）

### 3.1 去重键

优先级：
1. `grant_request_id`
2. `request_id`
3. `project_id + capability + created_at_ms`（兜底合成键）

目标：同一授权请求即使被重复上报，也只显示一次。

### 3.2 排序策略

1. 能力风险优先级（`web_fetch` / `ai_generate_paid` > `ai_generate_local` > 其他）。
2. `created_at` 升序（等待更久的在前）。
3. `projectName` / `projectId` / `grantRequestId` 稳定排序。

## 4) Supervisor 交互能力

1. 新增 “Hub 待处理授权” 卡片：
   - 显示待处理数量、快照来源、更新时间、新鲜度。
   - 快照不可用时显示降级文案（显式 fail-open 禁止）。
2. 每条 pending grant 提供：
   - `Open`（跳转项目+授权上下文）。
   - `Approve`（携带请求 ttl/token 覆盖值）。
   - `Deny`（写入拒绝原因标签）。
3. 动作完成后立即强刷快照（`refreshSchedulerSnapshot(force: true)`），确保 2 秒内收敛目标可达。

## 5) 回归样例（对应 XT-W1-03）

### Case-A: 授权撤销后 UI 收敛

- 前置：存在 pending grant，执行 deny。
- 预期：Supervisor 卡片该条目即时移除并强刷；最晚下个轮询周期（2 秒）与 Hub 快照一致。

### Case-B: 重复 request 不重复显示

- 前置：Hub 快照重复返回同一 `grant_request_id`（或相同 fallback key）。
- 预期：Supervisor 只展示一条，列表稳定排序不抖动。

### Case-C: 快照不可用

- 前置：Hub pending grants API 暂不可达。
- 预期：Supervisor 显示 “快照不可用”，且不从日志推断伪 pending 状态。

## 6) 手工验证建议

- 打开 Supervisor 窗口，观察顶部 “Hub 待处理授权” 卡片是否出现。
- 触发一条高风险授权请求，验证：
  - 卡片出现并可见 `grant=` 标识；
  - `Approve` / `Deny` 后状态收敛。
- 断开 Hub 或让接口超时，验证卡片显示 “快照不可用（无日志回退）”。

## 7) 下一步（衔接 XT-W3-09 / XT-W3-08）

1. ✅ 已补齐优先级解释与可操作建议：Supervisor Doctor/Secrets 预检结果输出 P0/P1 修复建议卡片（含“为什么优先 + 如何修复 + 如何验证”）。
2. ✅ 已接入发布门禁读取 doctor 报告（XT-W3-08）：无报告/报告阻断项/关键指标异常均 fail-closed。
3. 待收口：将真实联测样本写入 doctor 配置模板，覆盖更多环境差异（dev/staging/prod）。
4. ✅ 提交前审计验证（2026-02-28）：`swift test --filter SupervisorDoctorTests` 通过；`XT_GATE_MODE=strict ... xt_release_gate.sh` 全绿；CM-W5-20 strict 缺 `secrets-dry-run-report.json` 与字段非法回归样例均已固化进门禁脚本回归检查。
