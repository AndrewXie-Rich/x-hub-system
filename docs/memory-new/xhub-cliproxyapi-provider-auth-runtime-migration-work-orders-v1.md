# CLIProxyAPI -> Hub Provider Auth Runtime Migration Work Orders v1

- status: active-proposed
- updatedAt: 2026-04-20
- owner: Hub Runtime（Primary）/ RELFlowHub / XT-L1 / Security / QA / Product
- scope:
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/`
  - `x-hub-system/x-hub/macos/RELFlowHub/`
  - `x-hub-system/x-terminal/`
  - `x-hub-system/protocol/`
  - `x-hub-system/docs/memory-new/`
- purpose: 把 `CLIProxyAPI-main` 中“对 Hub 真正适用”的剩余能力，收口为 Hub-first 的 provider auth / key pool / runtime lifecycle / doctor explainability 主链；不引入通用代理产品面，不破坏现有 Hub / XT 契约。
- depends on:
  - `docs/memory-new/xhub-hub-xt-multimodel-auth-pool-work-orders-v1.md`
  - `docs/memory-new/xhub-provider-auth-pool-contract-v1.md`
  - `x-hub-system/protocol/hub_protocol_v1.proto`
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_store.js`
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_router.js`
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_source_watcher.js`
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/server.js`
  - `x-hub-system/x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ProviderKeyStorage.swift`
  - `x-hub-system/x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteModelTrialRunner.swift`
  - `x-hub-system/x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteKeyHealthScanner.swift`
  - `x-hub-system/x-hub/macos/RELFlowHub/Sources/RELFlowHub/CodexUsageService.swift`
  - `x-hub-system/x-terminal/Sources/Hub/HubProviderKeysClient.swift`
  - `x-hub-system/x-terminal/Sources/Hub/ProviderKeyManager.swift`
  - `x-hub-system/x-terminal/Sources/Hub/ProviderKeySelectionSupport.swift`
  - `source/CLIProxyAPI-main/sdk/cliproxy/auth/types.go`
  - `source/CLIProxyAPI-main/sdk/cliproxy/auth/conductor.go`
  - `source/CLIProxyAPI-main/internal/watcher/watcher.go`
  - `source/CLIProxyAPI-main/sdk/cliproxy/usage/manager.go`
  - `source/CLIProxyAPI-main/sdk/api/management.go`

## 0) 使用方式（先看）

- 本工单包不是把 `CLIProxyAPI-main` 整个嵌入 `X-Hub`，而是只迁移：`auth lifecycle`、`per-model runtime state`、`incremental watcher`、`usage/error feedback`、`refresh/retry`、`doctor snapshot`、`有限 OAuth 管理面`。
- 推进顺序固定为：`runtime conductor -> per-model state -> runtime feedback -> refresh normalizer -> contract v2 -> XT/doctor parity -> incremental watcher -> limited OAuth surface`。
- 所有新能力必须保持 `Hub-first truth`：Hub 是 durable source of truth；XT、RELFlowHub UI、临时导入文件、健康扫描结果都不能成为最终调度权威。
- 所有新字段必须 additive；既有 `hub_provider_keys.json`、`HubProviderKeysClient`、`ProviderKeyStorage`、`XT doctor` 必须保持兼容读取。
- 默认 fail-closed：缺 scope、token expired、refresh 失败、quota block、network timeout、runtime stale、model unsupported 都不得静默冒绿。

## 1) 冻结结论

### 1.1 只迁移“适合 Hub 的部分”

1. 不迁移 `CLIProxyAPI-main` 的 merged proxy、provider route aliases、通用 HTTP 翻译层。
2. 不迁移其 Go embedding SDK 形态。
3. 只迁移对 Hub 现有产品真正有用的“状态机 + 解释性 + 管理主链”。

### 1.2 Hub 继续掌握真实调度权

1. `ListProviderKeys` 继续只返回 redacted 数据。
2. 真实 API key / refresh token 只允许通过：
   - `ProviderKeyStorage.loadResolvedCredential(...)`
   - `HubAIRequest.provider_key`
   - 受控 refresh executor
3. XT 不得从列表接口或 doctor 文案推导出真实凭证。

### 1.3 Account 级状态不再是唯一真相

1. 当前 account 级 `error_state` / `quota` 要保留。
2. 但新增 `refresh_state` 与 `model_states` 后，account 级状态只作为聚合输出，不再代表全部执行真相。
3. 任何模型级别的 block / cooldown / stale，都必须能落在 machine-readable shard 上。

### 1.4 导入监听要升级，但不能破坏 source ownership

1. `source_owners` 与 `import_source_statuses` 继续保留。
2. watcher 可以升级为增量 diff，但不能回退成“整池重刷导致误删”。
3. 删除 source 时只 prune 属于该 owner 的 account 绑定，不得误删其他 owner 持有的同池账号。

### 1.5 XT / doctor 只能消费同一份决策快照

1. Model Settings
2. Troubleshoot
3. Unified Doctor
4. Hub provider key settings

以上四处最终必须显示同一份候选排序、同一份 fallback reason、同一份 retry 时间、同一份 import blocker。

## 2) Gate 体系

- `HCP-G0 / Contract Freeze`
  - provider key runtime 元数据、proto 增量字段、XT snapshot 字段冻结。
- `HCP-G1 / Lifecycle Correctness`
  - refresh loop、refresh backoff、scheduler reschedule、refresh pending 状态正确。
- `HCP-G2 / Model-State Correctness`
  - 同一 account 对不同 model 的可用性可独立表达，且不会把模型级错误错误提升为全账号永久阻断。
- `HCP-G3 / Feedback Closure`
  - 所有真实执行路径都把 usage/error 统一回写到同一条 provider key feedback pipeline。
- `HCP-G4 / XT / Doctor Parity`
  - XT、Hub settings、doctor、troubleshoot 的 route/repair/retry 解释一致。
- `HCP-G5 / Fail-Closed`
  - auth、quota、network、runtime stale、config、missing scope 等坏状态不静默冒绿。
- `HCP-G6 / Release Ready`
  - require-real 回归、回滚点、兼容证据、迁移说明齐备。

## 3) P0 / P1 总览

### P0（阻断型）

1. `HCP-W1-01` Provider-Key Runtime Conductor
2. `HCP-W1-02` Per-Model Runtime State Shards
3. `HCP-W1-03` Unified Runtime Feedback Pipeline
4. `HCP-W1-04` Refresh Executors + Retry-Time Normalization

### P1（收口型）

5. `HCP-W2-05` Provider-Key API Contract v2
6. `HCP-W2-06` XT / Doctor Unified Decision Snapshot
7. `HCP-W2-07` Incremental Auth / Config Watcher
8. `HCP-W2-08` Limited OAuth Management Surface

## 4) 详细工单（可直接执行）

### HCP-W1-01（P0 / 对应 `HUB-CLIPROXY-01`）Provider-Key Runtime Conductor

- 目标：
  - 把 Hub 的 provider key 能力从“静态存储 + 请求时筛选”升级为“有 refresh / retry / reschedule / scheduler awareness 的长期运行状态机”。
- 契约：
  - 在 account 上新增 additive `refresh_state`：
    - `status = idle|pending|refreshing|cooldown|failed`
    - `last_attempt_at_ms`
    - `last_success_at_ms`
    - `next_refresh_at_ms`
    - `failure_count`
    - `last_error_code`
    - `last_error_message`
  - 保留既有 `last_refresh_at_ms`，但它变成聚合兼容字段。
  - conductor 只能改 runtime truth，不得绕过 `provider_key_store` 直接写出另一本权威状态文件。
- 变更文件：
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_runtime_conductor.js`（new）
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_store.js`
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_router.js`
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/server.js`
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/services.js`
- 测试清单：
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_runtime_conductor.test.js`（new）
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_store_phase2.test.js`
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_keys_service_auth.test.js`
- 验收标准：
  - Hub 启动时会拉起 conductor，关闭时会优雅 stop。
  - refresh 失败会进入 backoff，并正确落到 `next_refresh_at_ms`。
  - refresh pending / failed 的 key 不会被错误地继续当成 ready key。
  - scheduler 能在 refresh 成功后自动 reschedule，不需要人工重启。
- Gate：
  - `HCP-G0`
  - `HCP-G1`
- 估时：1.5 天。

### HCP-W1-02（P0 / 对应 `HUB-CLIPROXY-02`）Per-Model Runtime State Shards

- 目标：
  - 让同一 provider key 对不同模型的支持、冷却、异常、恢复时间可以独立表达，不再只有 account 级单一状态。
- 契约：
  - 在 account 上新增 additive `model_states`：
    - key: canonical model id
    - value:
      - `status = ready|cooldown|blocked|disabled|stale`
      - `reason_code`
      - `status_message`
      - `next_retry_at_ms`
      - `retry_at_source`
      - `last_error_code`
      - `last_error_at_ms`
      - `updated_at_ms`
  - account 级 `error_state` 继续存在，但只输出聚合态：
    - 聚合优先级：`disabled > blocked_auth > blocked_quota > blocked_network > blocked_provider > stale > healthy`
  - 路由选择先看 `model_states[requested_model]`，没有命中时再退回 account 聚合态。
- 变更文件：
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_store.js`
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_router.js`
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub-system/protocol/hub_protocol_v1.proto`
  - `x-hub-system/x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ProviderKeyStorage.swift`
  - `x-hub-system/x-terminal/Sources/Hub/HubProviderKeysClient.swift`
  - `x-hub-system/x-terminal/Sources/Hub/ProviderKeySelectionSupport.swift`
- 测试清单：
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_model_state.test.js`（new）
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_store_phase2.test.js`
  - `x-hub-system/x-terminal/Tests/ProviderKeySelectionSupportTests.swift`
  - `x-hub-system/x-terminal/Tests/XTDoctorProjectionPresentationTests.swift`
- 验收标准：
  - 同一 key 可表达“`gpt-4o` blocked、`o3` ready、`gpt-5.4` cooldown”。
  - XT 选择逻辑按模型级状态排除候选，不再因为 account 聚合错误导致整个 pool 假死。
  - doctor 能输出模型级阻断原因，而不是只给 provider 级笼统 badge。
- Gate：
  - `HCP-G0`
  - `HCP-G2`
  - `HCP-G5`
- 估时：2 天。

### HCP-W1-03（P0 / 对应 `HUB-CLIPROXY-04`）Unified Runtime Feedback Pipeline

- 目标：
  - 把真实执行路径上的 usage / auth error / quota / timeout / provider failure 统一回写到一条 provider key feedback pipeline，消除“试跑一套逻辑、正式执行另一套逻辑”的分裂。
- 契约：
  - 定义内部机读事件 `provider_key_runtime_event.v1`：
    - `account_key`
    - `provider`
    - `model_id`
    - `outcome = success|auth_error|quota_error|network_error|provider_error|config_error`
    - `http_status`
    - `reason_code`
    - `tokens_used`
    - `latency_ms`
    - `occurred_at_ms`
  - 所有路径只通过统一事件入口驱动：
    - `quota`
    - `error_state`
    - `model_states`
    - `refresh_state`
  - 禁止在单个 provider client 内各写各的 cooldown 逻辑。
- 变更文件：
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_usage_events.js`（new）
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub-system/x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteModelTrialRunner.swift`
  - `x-hub-system/x-terminal/Sources/Hub/HubAIClient.swift`
  - `x-hub-system/x-terminal/Sources/LLM/OpenAICompatibleProvider.swift`
  - `x-hub-system/x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteKeyHealthScanner.swift`
- 测试清单：
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_runtime_feedback.test.js`（new）
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_store_phase2.test.js`
  - `x-hub-system/x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/RemoteRetryTimeSupportTests.swift`
  - `x-hub-system/x-terminal/Tests/ProviderKeySelectionSupportTests.swift`
- 验收标准：
  - 同一错误类型在 `RemoteModelTrialRunner`、正式 `HubAI`、XT OpenAI-compatible 执行链上会落成同一份 `reason_code` 与 `next_retry_at_ms`。
  - usage 成功事件会清理连续错误计数，失败事件会进入统一 cooldown / blocked 逻辑。
  - 修掉 `x-hub-system/x-terminal/Sources/LLM/OpenAICompatibleProvider.swift` 中“把 redacted key 当真实 key”的风险点。
- Gate：
  - `HCP-G1`
  - `HCP-G3`
  - `HCP-G5`
- 估时：2 天。

### HCP-W1-04（P0 / 对应 `HUB-CLIPROXY-05`）Refresh Executors + Retry-Time Normalization

- 目标：
  - 把 provider-specific refresh、usage window、quota reset、header retry、timeout retry 收口成统一 refresh / retry 决策层，避免现在“有些 provider 有时间、有些 provider 只有文案”的不一致。
- 契约：
  - 冻结 `retry_at_source` 枚举：
    - `quota`
    - `provider_header`
    - `usage_window`
    - `scheduler`
    - `refresh`
    - `manual`
  - 定义 refresh executor 返回结构：
    - `ok`
    - `next_refresh_at_ms`
    - `next_retry_at_ms`
    - `retry_at_source`
    - `last_error_code`
    - `status_message`
  - `last_refresh` 与 `next retry` 的展示一律由统一层产出，不允许 provider-specific UI 自行拼接时间。
- 变更文件：
  - `x-hub-system/x-hub/macos/RELFlowHub/Sources/RELFlowHub/ProviderKeyRefreshCoordinator.swift`（new）
  - `x-hub-system/x-hub/macos/RELFlowHub/Sources/RELFlowHub/CodexUsageService.swift`
  - `x-hub-system/x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteProviderClient.swift`
  - `x-hub-system/x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteKeyHealthScanner.swift`
  - `x-hub-system/x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteRetryTimeSupport.swift`
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_runtime_conductor.js`
- 测试清单：
  - `x-hub-system/x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/ProviderKeyRefreshCoordinatorTests.swift`（new）
  - `x-hub-system/x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/RemoteRetryTimeSupportTests.swift`
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_runtime_conductor.test.js`
- 验收标准：
  - `token_expired`、`missing scope`、quota window、provider timeout 最终都能映射为统一的 `next_retry_at_ms + retry_at_source`。
  - RELFlowHub 与 XT 展示的是同一份重试时间，不再出现一个地方有时间、另一个地方显示“未知”。
  - refresh 失败不会覆盖 quota reset 这种更可信的下次可用时间。
- Gate：
  - `HCP-G1`
  - `HCP-G3`
  - `HCP-G5`
- 估时：1.5 天。

### HCP-W2-05（P1 / 对应 `HUB-CLIPROXY-06`）Provider-Key API Contract v2

- 目标：
  - 把 runtime state、import state、route decision 从“只能读本地 json / 只能靠多处推断”升级为正式 Hub 契约输出。
- 契约：
  - `hub_protocol_v1.proto` 增量新增：
    - `ProviderKeyRefreshState`
    - `ProviderKeyModelState`
    - `ProviderKeyImportSourceStatus`
    - `ProviderKeyRouteDecision`
  - 新 RPC 建议至少二选一：
    - `GetProviderKeyRuntimeSnapshot`
    - `GetProviderKeyRouteDecision`
  - 旧 RPC 保持兼容，不删除：
    - `ListProviderKeys`
    - `GetProviderKeySummary`
    - `GetKeyUsage`
- 变更文件：
  - `x-hub-system/protocol/hub_protocol_v1.proto`
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub-system/x-terminal/Sources/Hub/HubProviderKeysClient.swift`
  - `x-hub-system/x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ProviderKeyStorage.swift`
  - `x-hub-system/docs/memory-new/xhub-provider-auth-pool-contract-v1.md`
- 测试清单：
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_keys_service_runtime_contract.test.js`（new）
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_keys_service_auth.test.js`
  - `x-hub-system/x-hub/macos/RELFlowHub/Tests/RELFlowHubCoreTests/ProviderKeyStorageContractTests.swift`（new）
- 验收标准：
  - XT / RELFlowHub 不再必须直接读 `hub_provider_keys.json` 才能拿到 runtime/import 细节。
  - 旧客户端继续工作；新客户端可以拿到更完整的 route / retry / import 机读状态。
  - 所有新 message 均为 additive，老字段不改含义。
  - XT snapshot store 默认优先 Hub RPC + cache；文件回退必须是显式 compatibility-only path。
- Gate：
  - `HCP-G0`
  - `HCP-G4`
- 估时：1.5 天。

### HCP-W2-06（P1 / 对应 `HUB-CLIPROXY-07`）XT / Doctor Unified Decision Snapshot

- 目标：
  - 让 XT Model Settings、Troubleshoot、Unified Doctor、Hub provider keys settings 统一引用同一份 route decision snapshot，而不是多处各自重算。
- 契约：
  - 扩展 `ProviderKeyCandidateDecision` / `ProviderKeySelectionDecision`：
    - `providerHost`
    - `selectedWireAPI`
    - `retryAtSource`
    - `snapshotUpdatedAtMs`
    - `modelStateKey`
  - import source blocker 与 selection decision 合并成单一 `route context` 输出。
  - XT 不得各自发明一套 fallback reason 名称。
  - XT troubleshoot 必须把 route context 作为 provider-key 主输入；旧 split troubleshoot 参数只保留 deprecated compatibility wrapper。
- 变更文件：
  - `x-hub-system/x-terminal/Sources/Hub/ProviderKeyManager.swift`
  - `x-hub-system/x-terminal/Sources/Hub/ProviderKeySelectionSupport.swift`
  - `x-hub-system/x-terminal/Sources/Hub/ProviderKeySelectionSnapshotStore.swift`
  - `x-hub-system/x-terminal/Sources/Hub/ProviderKeyImportSourceSnapshotStore.swift`
  - `x-hub-system/x-terminal/Sources/UI/ProviderKeySelectionPresentationSupport.swift`
  - `x-hub-system/x-terminal/Sources/UI/ProviderKeyImportSourcePresentationSupport.swift`
  - `x-hub-system/x-terminal/Sources/UI/ProviderKeyRouteContextPresentationSupport.swift`
  - `x-hub-system/x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-hub-system/x-terminal/Sources/UI/XHubDoctorOutput.swift`
- 测试清单：
  - `x-hub-system/x-terminal/Tests/ProviderKeySelectionSupportTests.swift`
  - `x-hub-system/x-terminal/Tests/ProviderKeyRouteContextPresentationTests.swift`
  - `x-hub-system/x-terminal/Tests/XTUnifiedDoctorReportTests.swift`
  - `x-hub-system/x-terminal/Tests/XHubDoctorOutputTests.swift`
- 验收标准：
  - 同一个 provider key 问题，在 XT 四个面板里看到相同的原因、相同的时间、相同的下一步动作。
  - doctor report 输出机器字段时，不再需要从 raw detail lines 反向解析才能找回 route truth。
  - 任何 selection/fallback 文案都能追溯回同一份 `decision snapshot`。
  - XT 新代码不再默认直读 `hub_provider_keys.json`；若保留文件回退，必须显式标记为 compatibility-only。
- Gate：
  - `HCP-G3`
  - `HCP-G4`
  - `HCP-G6`
- 估时：1.5 天。

### HCP-W2-07（P1 / 对应 `HUB-CLIPROXY-03`）Incremental Auth / Config Watcher

- 目标：
  - 把 Hub 当前粗粒度 polling watcher 升级为带增量 diff 语义的 source watcher，保住 source ownership，又减少整源重导入与误删风险。
- 契约：
  - 内部事件 `provider_key_source_update.v1`：
    - `action = add|modify|delete`
    - `source_kind = auth_dir|config_path`
    - `source_ref`
    - `fingerprint`
    - `account_keys`
    - `updated_at_ms`
  - watcher 语义：
    - add -> 只导入新增对象
    - modify -> 只更新受影响对象
    - delete -> 只 prune 对应 source owner
  - `import_source_statuses` 继续保留，必要时补充：
    - `last_fingerprint`
    - `last_event_kind`
- 变更文件：
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_source_watcher.js`
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_import_diff.js`（new）
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_store.js`
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/server.js`
- 测试清单：
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_source_watcher.test.js`（new）
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_store.test.js`
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_keys_service_auth.test.js`
- 验收标准：
  - 修改单个 auth 文件不会导致整个 source 被先 prune 再重导。
  - 删除单个 auth 文件只影响对应 account/source owner，不会误伤同池其他 account。
  - `unsupported_toml_config`、missing source、rename replace 等边界都有稳定状态输出。
- Gate：
  - `HCP-G1`
  - `HCP-G5`
- 估时：1.5 天。

### HCP-W2-08（P1 / 对应 `HUB-CLIPROXY-08`）Limited OAuth Management Surface

- 目标：
  - 在不把 Hub 变成通用 proxy 管理后台的前提下，提供最小必要的 provider OAuth token acquisition / status / callback 面，减少“必须先在外部工具登录、再回导 auth 文件”的摩擦。
- 契约：
  - 定义 `provider_oauth_session.v1`：
    - `provider`
    - `status = pending|authorized|expired|failed`
    - `auth_url`
    - `callback_state`
    - `expires_at_ms`
    - `created_at_ms`
    - `updated_at_ms`
  - 只允许受控能力：
    - request token session
    - get auth status
    - post OAuth callback
  - 明确非目标：
    - 不提供 merged proxy route
    - 不提供 provider alias proxy
    - 不提供通用 dashboard config 编辑面
- 变更文件：
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_oauth_admin_http.js`（new）或等价受控服务入口
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub-system/protocol/hub_protocol_v1.proto`
  - `x-hub-system/x-hub/macos/RELFlowHub/Sources/RELFlowHub/ProviderAuthImport.swift`
  - `x-hub-system/x-terminal/Sources/Hub/HubProviderKeysClient.swift`
- 测试清单：
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_key_oauth_admin_http.test.js`（new）
  - `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/provider_keys_service_auth.test.js`
  - callback replay / csrf / localhost-only / admin-only 定向测试
- 验收标准：
  - OAuth management 只暴露最小 token session 能力，不把 Hub 扩展成 CLIProxyAPI 那套完整代理产品面。
  - callback / state / replay / auth scope 都是 fail-closed。
  - 如果产品暂时不开放该入口，此工单可以不合并，但契约与边界必须冻结。
- Gate：
  - `HCP-G0`
  - `HCP-G5`
  - `HCP-G6`
- 估时：2 天。

## 5) 推荐推进顺序

1. 先做 `HCP-W1-01`，把 runtime conductor 建起来。
2. 再做 `HCP-W1-02`，把模型级状态引入调度真相。
3. 然后做 `HCP-W1-03`，把正式执行链和试跑链收成同一条 feedback pipeline。
4. 接着做 `HCP-W1-04`，统一 refresh / retry 时间语义。
5. 再做 `HCP-W2-05` 与 `HCP-W2-06`，把这套真相正式暴露给 XT / doctor。
6. 然后做 `HCP-W2-07`，把 watcher 升级到增量 diff 模式。
7. 最后按产品需要决定是否推进 `HCP-W2-08`。

## 6) 交付口径

- 完成 `HCP-W1-01` ~ `HCP-W1-04` 前，不允许对外宣称“Hub 已完整吸收 CLIProxyAPI 的 auth lifecycle 能力”。
- 完成 `HCP-W2-05` ~ `HCP-W2-06` 前，不允许对外宣称“XT / doctor 与 Hub route truth 已完全一致”。
- `HCP-W2-08` 未完成不影响当前 Hub 多 key / 多 provider 生命周期主线，但影响“Hub 自带 OAuth 登录入口”的产品完整度。
