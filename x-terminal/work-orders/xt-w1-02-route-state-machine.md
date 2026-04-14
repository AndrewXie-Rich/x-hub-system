# XT-W1-02：Hub 路由状态机收敛（auto/grpc/file）

- workOrder: `XT-W1-02`
- priority: `P0`
- gate: `XT-G1`, `XT-G4`
- status: `in_progress`
- owner: `Lane-A (Core Transport)`
- updatedAt: `2026-02-27`

## 1) 目标与边界

目标：让 `auto | grpc | file` 在成功/失败/回退行为上完全可预测，避免“看起来像自动回退、实际静默失败”的分叉。

本轮边界（代码落点）：
- `Sources/Hub/HubRouteStateMachine.swift`
- `Sources/Hub/HubAIClient.swift`
- `Sources/Hub/HubIPCClient.swift`
- `Sources/Chat/ChatSessionModel.swift`

## 2) 统一状态机定义

### 2.1 路由决策输入

- `mode`: `auto` / `grpc` / `file`
- `hasRemoteProfile`: 是否存在 Hub 远端配对配置（`hub.env` 可用）

### 2.2 路由决策输出（统一）

- `preferRemote`: 是否优先走远端 gRPC
- `allowFileFallback`: 远端失败后是否允许回退 file IPC
- `requiresRemote`: 是否必须远端（fail-closed）

### 2.3 决策矩阵

| mode | hasRemoteProfile | preferRemote | allowFileFallback | requiresRemote | 语义 |
|---|---:|---:|---:|---:|---|
| auto | true | true | true | false | 远端优先，路由失败可回退 file |
| auto | false | false | true | false | 直接 file 路由 |
| grpc | true | true | false | true | 仅远端，不允许 silent fallback |
| grpc | false | false | false | true | fail-closed（`hub_env_missing`） |
| file | 任意 | false | false | false | 仅 file IPC |

## 3) 错误码映射（回退判定）

仅 `auto` 模式会执行“远端失败 -> file 回退”，且只对“路由不可用类错误”触发。

### 3.1 触发回退（route-unavailable class）

- `hub_env_missing`
- `grpc_route_unavailable`
- `client_kit_missing`
- `node_missing`
- `discover_failed*`
- `bootstrap_failed*`
- `connect_failed*`
- `connection_refused*`
- `network_unreachable*`
- `service_unavailable*`
- `timeout*`
- `tls_error*`

> `*` 表示前缀/包含匹配。

### 3.2 不触发回退（业务错误直接抛出）

- `model_not_found`
- `model_not_loaded`
- `api_key_missing`
- `remote_model_not_found`
- 其他模型/鉴权/业务拒绝类错误

## 4) 已落地行为（本次变更）

1. 新增统一状态机实现：
   - `HubRouteStateMachine.resolve(...)`
   - `HubRouteStateMachine.shouldFallbackToFile(...)`
   - `HubRouteStateMachine.runSelfChecks()`
2. `HubAIClient`：
   - 统一使用状态机做路由决策。
   - 远端生成失败时，`auto` + 路由不可用错误 -> 自动回退本地 file IPC。
   - `grpc` 模式保持 fail-closed，不允许 silent fallback。
3. `HubIPCClient`：
   - `requestNetworkAccess/requestMemoryContext/requestSchedulerStatus/requestPendingGrantRequests/approve/deny` 统一接入状态机决策。
4. Slash 可观测：
   - `/hub route` 展示“有/无 remote profile”下的显式行为。
   - `/hub route selftest` 输出状态机规则自检结果。

## 5) 回归样例（对应工单验收）

### Case-A: grpc 不可用 + auto 模式

- 前置：`mode=auto`，远端链路失败且 reason 属于 route-unavailable（如 `hub_env_missing`）。
- 预期：自动回退 file IPC，不中断主流程。

### Case-B: grpc 模式失败

- 前置：`mode=grpc`，远端不可用（无 profile 或连接失败）。
- 预期：直接 fail-closed（例如 `hub_env_missing`），不得 silent fallback 到 file。

### Case-C: 业务错误（非路由错误）

- 前置：`mode=auto`，远端返回 `model_not_found` / `api_key_missing` 等业务错误。
- 预期：不回退 file，直接暴露错误，保证语义清晰。

## 6) 手工验证命令

- 查看当前策略：
  - `/hub route`
- 路由规则自检：
  - `/hub route selftest`
- 切换模式：
  - `/hub route auto`
  - `/hub route grpc`
  - `/hub route file`

## 7) 下一步（衔接 XT-W1-03 / XT-W1-04）

1. 将 pending grants 读取/审批链路挂到同一 `HubRouteStateMachine` 审计字段上（Lane-D）。
2. 将高风险 grant gate 的拒绝码统一到 route/error taxonomy（Lane-C）。
3. ✅ 已纳入发布前 smoke：新增 `--xt-route-smoke`，`XT-G4` 现在同时要求 `xt-route-smoke + xt-grant-smoke + xt-supervisor-voice-smoke + 新增静态检查` 通过。
