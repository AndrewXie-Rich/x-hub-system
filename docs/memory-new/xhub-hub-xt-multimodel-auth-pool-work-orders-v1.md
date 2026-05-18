# Hub / XT 多凭证池与多类型模型执行链工单包 v1

- status: active-proposed
- updatedAt: 2026-04-18
- owner: Hub Runtime（Primary）/ XT-L1 / Local Runtime / QA / Product
- scope:
  - `x-hub/macos/RELFlowHub/`
  - `x-terminal/`
  - `docs/memory-new/`
- purpose: 把 Hub 当前“能导入 auth、能扫描本地模型”的分散能力，收口成“多 key 池化、可解释调度、远端 / 本地多类型模型统一执行面”。
- depends on:
  - `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
  - `docs/memory-new/xhub-governed-package-productization-work-orders-v1.md`
  - `x-terminal/work-orders/xt-l1-skills-ux-preflight-runner-contract-v1.md`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ProviderKeyStorage.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteModelTrialRunner.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteKeyHealthScanner.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteRetryTimeSupport.swift`
  - `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`

## 0) 使用方式（先看）

- 本工单不是把 `CLIProxyAPI-main` 整个接入 Hub，而是只借它的状态模型、调度语义、alias / fallback 规则、管理面解释性输出。
- 推进顺序固定为：`auth pool contract -> pool merge identity -> scheduler -> route fallback -> doctor/explainability -> XT parity -> local multimodal live chain`。
- 所有新能力必须保持 Hub-first truth，不允许 XT、local runtime、或临时导入文件成为 durable truth source。
- 本工单按 `P0 > P1` 排序；P0 未完成前，不允许对外宣称“Hub/XT 已完整支持多 key 池和多类型模型执行链”。

## 1) 北极星目标

### 1.1 Auth Pool

- 同 provider 的多把 key 必须能按稳定规则合并进同一 pool。
- 同一 pool 下每把 key 必须保留独立健康、额度、冷却、错误原因、预计恢复时间。
- pool 级 summary 只能做聚合展示，不得吞掉逐 key 真相。

### 1.2 Route / Execution

- 远端模型执行要统一支持：`provider pool fallback`、`model alias pool fallback`、`responses -> chat/completions` fallback。
- 本地模型执行要统一支持：`text / embedding / transcription / vision / ocr / tts` 的 live / unavailable / stale 判定。
- XT 看到的执行面必须和 Hub 的实际 route 决策一致。

### 1.3 Explainability

- 任何“不可用”都必须能回答三件事：
  - 为什么不能用
  - 预计什么时候再试
  - 现在还需要做什么动作
- 任何“被选中的 route”都必须能回答两件事：
  - 为什么选它
  - 为什么跳过其它候选

## 2) Gate 体系

- `HXM-G0 / Contract Freeze`
  - auth pool / route / retry 元数据契约冻结并版本化。
- `HXM-G1 / Pool Correctness`
  - 同 provider 多 key 正确并池；误并池与漏并池都要有回归保护。
- `HXM-G2 / Routing Correctness`
  - model pool / provider pool / wire API fallback 行为稳定。
- `HXM-G3 / XT Parity`
  - XT 读取的状态、建议和 Hub 实际状态一致。
- `HXM-G4 / Fail-Closed`
  - missing scope、token expired、runtime stale、model unsupported、network timeout 均不静默冒绿。
- `HXM-G5 / Release Ready`
  - require-real 回归、doctor 文案、rollback point、audit snapshot 齐备。

## 3) P0 / P1 总览

### P0（阻断型）

1. `HXM-W1-01` Auth Pool 元数据契约冻结
2. `HXM-W1-02` Pool identity 与并池语义
3. `HXM-W1-03` Scheduler 与 cooldown 状态机
4. `HXM-W1-04` 执行路由与 wire API fallback
5. `HXM-W2-05` 管理面 / doctor / explainability 输出
6. `HXM-W2-06` XT 逐 key 状态读取与展示
7. `HXM-W2-07` 本地 vision / OCR / TTS provider/model live 注册链
8. `HXM-W2-08` XT governed dispatch 与多类型本地模型打通

### P1（增强型）

9. `HXM-W3-09` Usage / quota / reset-time 聚合
10. `HXM-W3-10` 导入 diff 与 repair hints
11. `HXM-W3-11` 角色化模型池策略
12. `HXM-W3-12` replay / chaos / require-real 门禁

## 4) 详细工单（可直接执行）

### HXM-W1-01（P0）Auth Pool 元数据契约冻结

- 目标：冻结 provider key pool 的稳定身份、健康状态、重试窗口、来源、wire 能力字段，避免 Hub / XT / doctor 再次漂移。
- 主要文件：
  - `docs/memory-new/xhub-provider-auth-pool-contract-v1.md`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ProviderKeyStorage.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteRetryTimeSupport.swift`
- 交付物：
  - `pool_id`、`provider_host`、`wire_api`、`status_message`、`reason_code`、`last_refresh_at_ms`、`next_retry_at_ms`、`retry_at_source` 字段冻结。
  - additive 兼容规则：旧 `hub_provider_keys.json` 不重写、不破坏读取。
- DoD：
  - 逐 key 行可表达“原因 + 时间 + route 关键元数据”。
  - resolved credential 读取面也能拿到这些字段。
- 回归样例：
  - 旧 schema 仍可 decode。
  - 新 schema 字段可 round-trip 读取。
- Gate：`HXM-G0`
- 估时：1 天。

### HXM-W1-02（P0）Pool identity 与并池语义

- 目标：把同 provider 多 key 正确合并进一个 pool，同时防止不同 host / wire / headers 误并池。
- 主要文件：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ProviderKeyStorage.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/CodexProviderImportResolver.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/ProviderAuthImport.swift`
- 规则：
  - pool key 至少包含：`canonical_provider + host + wire_api + custom_header_fingerprint`。
  - provider group summary 不得覆盖子 key 明细。
- DoD：
  - `auth17.json + auth19.json + config149.toml` 这类同 host / 同 provider / 同 overlay 的输入会并池。
  - 不同 host / 不同 wire API / 不同 header policy 的输入不会误并池。
- Gate：`HXM-G1`
- 估时：1 天。

### HXM-W1-03（P0）Scheduler 与 cooldown 状态机

- 目标：把 provider key 组从“静态存储”升级为“真正会选路、会冷却、会跳过坏 key”的调度器。
- 主要文件：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/ProviderKeyPoolScheduler.swift`（new）
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteModelTrialRunner.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteKeyHealthScanner.swift`
- 规则：
  - 至少支持 `ready / cooldown / blocked / disabled / stale`。
  - `401/403/429/model_not_supported/timeout/network` 分类不同。
  - blocked key 不消耗 retry budget。
- DoD：
  - 调度日志或 snapshot 能解释“为什么选这把 key / 为什么跳过其它 key”。
- Gate：`HXM-G1/HXM-G2/HXM-G4`
- 估时：1.5 天。

### HXM-W1-04（P0）执行路由与 wire API fallback

- 目标：把 `responses / chat_completions / compat-host fallback / alias model pool` 统一成一条稳定执行链。
- 主要文件：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteModelTrialRunner.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/CodexProviderImportResolver.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/ProviderAuthImport.swift`
- 规则：
  - OAuth / Codex / third-party compat host 必须支持 `responses -> chat/completions` 有条件降级。
  - 请求形状错误停止 fallback；模型不支持允许换模型；auth/network/quota 允许换 key 或 route。
- DoD：
  - 不再出现“chat/completions 可用，但被 responses 卡死”的回归。
- Gate：`HXM-G2/HXM-G4`
- 估时：1.5 天。

### HXM-W2-05（P0）管理面 / doctor / explainability 输出

- 目标：把逐 key 失败原因、预计恢复时间、route explainability 做成 Hub 标准输出。
- 主要文件：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteKeyHealthScanner.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteKeyHealthPresentationSupport.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/AIRuntimeStatus.swift`
- DoD：
  - doctor 输出“为什么不能用 / 下次可用时间 / 还需要什么动作”。
  - 不再出现“还没有登记可用的快速评审任务”这类中间态开发文案。
- Gate：`HXM-G3/HXM-G4`
- 估时：1 天。

### HXM-W2-06（P0）XT 逐 key 状态读取与展示

- 目标：让 XT 显示 pool summary + per-key 详情，而不是只有 provider 级单 badge。
- 主要文件：
  - `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`
  - `x-terminal/Sources/Hub/HubProviderKeysClient.swift`
  - `x-terminal/Sources/UI/*`（按需要）
- DoD：
  - XT 可以展示默认选中 key、异常 key 原因、预计恢复时间、手动试用入口。
- Gate：`HXM-G3`
- 估时：1 天。

### HXM-W2-07（P0）本地 vision / OCR / TTS provider/model live 注册链

- 目标：把本地多模态从“扫描到模型”提升到“provider pack live + capability live + XT 可绑定”。
- 主要文件：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/AIRuntimeStatus.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/LocalProviderPackRegistry.swift`
  - `x-hub/python-runtime/python_service/provider_pack_registry.py`
- DoD：
  - `local-vision`、`local-ocr`、`local-tts`、`local-transcribe` 都能成为真正 live capability。
- Gate：`HXM-G3/HXM-G4`
- 估时：1.5 天。

### HXM-W2-08（P0）XT governed dispatch 与多类型本地模型打通

- 目标：让 XT 的 builtin local wrappers 真正依赖 Hub live route，而不是静态 wrapper 名义存在。
- 主要文件：
  - `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
  - `x-terminal/Sources/Supervisor/SupervisorSkillRegistrySnapshot.swift`
- DoD：
  - 在未显式提供 `model_id` 时，XT 绑定“最佳 runnable Hub local model”。
  - 无 live model 时给出 machine-readable 阻断原因。
- Gate：`HXM-G3/HXM-G4`
- 估时：1 天。

### HXM-W3-09（P1）Usage / quota / reset-time 聚合

- 目标：补齐 pool 级额度聚合，同时保留逐 key 真相。
- Gate：`HXM-G3`

### HXM-W3-10（P1）导入 diff 与 repair hints

- 目标：导入 auth / config 后自动生成 merge diff、skip reason、repair hints。
- Gate：`HXM-G3/HXM-G5`

### HXM-W3-11（P1）角色化模型池策略

- 目标：让 XT 能按 `coder / reviewer / vision / ocr / tts / transcription` 读取不同 route policy。
- Gate：`HXM-G2/HXM-G3`

### HXM-W3-12（P1）replay / chaos / require-real 门禁

- 目标：把多 key、多 route、多 provider、多类型本地模型回归补成真正 release gate。
- Gate：`HXM-G5`

## 5) 推荐推进顺序

1. 先做 `HXM-W1-01` + `HXM-W1-02`，冻结字段和并池边界。
2. 再做 `HXM-W1-03` + `HXM-W1-04`，把调度和 route fallback 稳定下来。
3. 然后做 `HXM-W2-05` + `HXM-W2-06`，确保 XT 与 Hub 可解释性一致。
4. 最后做 `HXM-W2-07` + `HXM-W2-08`，把本地多类型模型真正接上 XT 执行链。
