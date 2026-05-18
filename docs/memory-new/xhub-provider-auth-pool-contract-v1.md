# X-Hub Provider Auth Pool Contract v1

- status: draft
- updatedAt: 2026-04-18
- owner: Hub Runtime
- scope:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ProviderKeyStorage.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteRetryTimeSupport.swift`
  - `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`
- parent:
  - `docs/memory-new/xhub-hub-xt-multimodel-auth-pool-work-orders-v1.md`

## 0) 目标

本契约冻结 Hub 侧 provider auth pool 的最小真相字段，使下列三层读取同一语义：

- Hub 调度 / doctor / health scanner
- XT 展示 / preflight / route explainability
- usage / retry-time / quota 估计服务

本契约只做 additive 扩展，不改变现有 `hub_provider_keys.json` 基础结构，也不要求旧文件立即重写。

## 1) 不变量

1. `providerGroups[].accounts[]` 仍是 durable truth source。
2. pool summary 只能聚合，不得覆盖 account row 真相。
3. 任一 account row 都必须能表达：
   - 我是谁
   - 我属于哪个 pool
   - 为什么现在不能被优先选中
   - 什么时候可能恢复
4. `reason_code` 必须优先 machine-readable，`status_message` 负责用户解释。
5. `next_retry_at_ms` 表示“预计最早重试时刻”，不代表一定恢复成功。

## 2) Row 契约（account row）

在现有 account row 上增加以下 additive 字段：

```json
{
  "account_key": "openai:oauth-primary.json",
  "provider": "openai",
  "base_url": "https://api.openai.com/v1",
  "proxy_url": "",
  "auth_type": "oauth",
  "pool_id": "openai:api.openai.com:chat_completions",
  "provider_host": "api.openai.com",
  "wire_api": "chat_completions",
  "last_refresh_at_ms": 1717001234000,
  "error_state": {
    "status": "blocked_auth",
    "status_message": "missing scope: api.responses.write",
    "reason_code": "missing_scope",
    "last_error_code": "missing_scope",
    "last_error_at_ms": 1717001234000,
    "next_retry_at_ms": 1717087634000,
    "retry_at_source": "usage_window",
    "auto_disabled": false
  }
}
```

## 3) 字段语义

### 3.1 身份 / 路由字段

- `pool_id`
  - 稳定 pool 身份。
  - 若文件未显式提供，Hub 可由 `canonical_provider + host + wire_api` 推导。
  - 当存在非默认 proxy/base-path/custom-header 边界时，允许在末尾追加稳定 fingerprint，避免误并池。
- `provider_host`
  - 规范化 host，用于 pool 归并、展示和 explainability。
  - 优先 `base_url.host`，其后可退到 `proxy_url.host`。
- `wire_api`
  - 当前账户默认执行面，允许值：`responses`、`chat_completions`、`""`。
  - 空值不代表不可用，只代表未显式冻结。
- `last_refresh_at_ms`
  - 最近一次成功刷新该账户运行态元数据的时间。

### 3.2 状态字段

- `error_state.status`
  - 当前健康类状态，建议枚举：
    - `healthy`
    - `degraded`
    - `blocked_auth`
    - `blocked_quota`
    - `blocked_network`
    - `blocked_provider`
    - `blocked_config`
    - `unknown_stale`
- `error_state.status_message`
  - 用户可读的主要原因；允许保留 provider 原始错误摘要，但不应只返回原始 JSON blob。
- `error_state.reason_code`
  - 机读原因码，推荐值：
    - `missing_scope`
    - `token_expired`
    - `quota_exceeded`
    - `provider_timeout`
    - `network_unreachable`
    - `model_unsupported`
    - `runtime_stale`
    - `invalid_base_url`
    - `auth_missing`
- `error_state.next_retry_at_ms`
  - 预计最早可再次尝试的 UTC 毫秒时间戳。
- `error_state.retry_at_source`
  - 恢复时间来源，推荐值：
    - `quota`
    - `provider_header`
    - `usage_window`
    - `scheduler`
    - `refresh`
    - `manual`

## 4) 读取兼容规则

- 若 `pool_id` 缺失，Hub 允许推导默认值。
- 若 `provider_host` 缺失，Hub 允许从 `base_url` / `proxy_url` 推导。
- 若 `wire_api` 缺失，Hub 允许按当前 import / runtime fallback 规则推导。
- 若 `error_state.reason_code` 缺失，可退到 `error_state.last_error_code`。
- 若 `error_state.next_retry_at_ms` 缺失，可退到 `quota.cooldown_until_ms`。

## 5) XT / Doctor 输出要求

读取本契约的上层必须至少能生成：

- provider / pool summary
- per-key detail
- `为什么不能用`
- `预计下次可用`
- `当前仍可手动使用但会后排` 这类 recommendation 解释

## 5.1) Hub API Contract v2

自 `HCP-W2-05` 起，`hub_provider_keys.json` 不再是 XT / doctor 获取 provider-key runtime/import/route 真相的唯一入口。Hub 必须通过正式 RPC 暴露同一份语义：

- `GetProviderKeyRuntimeSnapshot`
  - 返回 account runtime row、`refresh_state`、`model_states`、`required_refresh_metadata`
  - 返回 `import_source_statuses`
- `GetProviderKeyRouteDecision`
  - 返回当前模型的 provider-key route decision
  - 返回 candidate state / retry / metadata hints

约束：

- 旧 RPC 继续保留：
  - `ListProviderKeys`
  - `GetProviderKeySummary`
  - `GetKeyUsage`
- 新 RPC 只做 additive 扩展，不改变旧字段语义。
- XT / doctor 可以保留本地缓存或文件回退，但新的实时真相必须优先来自 Hub RPC。
- `provider_key_route_context_snapshot` / `providerKeyRouteContextProjection` 应作为 XT troubleshoot 的主输入；旧 split provider-key troubleshoot 参数只保留兼容 wrapper。
- `hub_provider_keys.json` 只能作为显式兼容回退路径存在，不能再被 XT 新代码当成默认主链路。

## 6) 非目标

本契约当前不冻结：

- 权重调度算法本身
- pool 内 weighted load balance
- provider 级 usage 聚合输出 schema
- XT 最终 UI 布局

这些在后续 `HXM-W1-03`、`HXM-W2-05`、`HXM-W3-09` 中继续冻结。
