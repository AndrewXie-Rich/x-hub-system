# X-Hub 远端付费模型与本地模型统一管理执行计划 v1

- status: active-proposed
- updatedAt: 2026-04-29
- owner: Hub Runtime / RELFlowHub / XT / Local Runtime / QA
- scope:
  - `x-hub/macos/RELFlowHub/`
  - `x-hub/python-runtime/python_service/`
  - `x-terminal/`
  - `docs/memory-new/`
- parent:
  - `docs/memory-new/xhub-provider-auth-pool-contract-v1.md`
  - `docs/memory-new/xhub-hub-xt-multimodel-auth-pool-work-orders-v1.md`
  - `docs/memory-new/xhub-cliproxyapi-provider-auth-runtime-migration-work-orders-v1.md`
  - `docs/memory-new/xhub-xt-ui-runtime-smoothness-execution-plan-v1.md`
- purpose: 把远端付费模型、本地模型、账号池、额度池、能力预检、runner、doctor 和 XT 展示收口成一套可解释、可回归、可运营的统一模型管理面。

## 0) 结论

Hub 必须成为模型可用性、账号池、额度、route decision、能力预检和 runtime health 的唯一真相源。

XT 不应该自己猜 provider key、账号额度、OAuth scope、本地模型能不能跑。XT 只读取 Hub 暴露的 snapshot、route decision 和 preflight 结果，然后负责展示、交互和执行请求。

远端付费模型和本地模型可以是两套资源，但对 XT 和 Supervisor 来说必须表现为同一个“可执行模型目录”：

- 远端模型负责强推理、复杂 coding、长上下文、工具调用、高风险审查。
- 本地模型负责低成本总结、分类、隐私上下文处理、轻量 draft、离线 fallback。
- Hub route policy 负责在两者之间选择、降级、解释和记录。

## 1) 非目标和边界

### 1.1 非目标

- 不在 Hub 中保存用户邮箱密码。
- 不实现 provider 网站的密码自动登录、验证码处理或风控绕过。
- 不让 XT 直接读取或持久化 provider token 作为主链路。
- 不让 CLIProxy config.yaml 成为 Hub durable truth source。
- 不把本地模型包装成“永远可用”的静态标签。

### 1.2 必须保持的安全边界

- Provider OAuth 只允许走 Hub 原生 OAuth、CLIProxy management import、或已有 token / key 导入。
- `auth.json`、refresh token、access token 只能进入受控 keychain / provider key store，不得写入日志、doctor 明文或 XT 普通 UI state。
- scope 不足、quota 不足、token 过期、模型无权限必须 fail closed。
- pool summary 只能聚合，不得覆盖逐账号真相。
- 本地 runtime 不得绕过 Hub grant、capability gate、doctor 和 audit。

## 2) 目标状态

### 2.1 远端付费模型

远端模型目录不再是“模型 + 单个 key”的扁平列表，而是：

- `model_id` 表示能力入口，例如 `gpt-5.5`、`claude-sonnet-4-5`、`qwen3.6-plus`。
- `provider key pool` 表示真实账号池和付费/免费额度库存。
- `quota pool` 表示共享额度家族，例如 OpenAI、Claude、Gemini、Qwen。
- `route decision` 表示本次调用为什么选中某个账号、为什么跳过其它账号。
- `runtime feedback` 把调用失败写回账号池，让下一次调用跳过冷却或阻断账号。

### 2.2 本地模型

本地模型目录不再只看文件是否存在，而是至少要能表达：

- 文件来源、路径、大小、checksum、量化格式、context 能力。
- runtime provider 是否存在、是否可启动、是否支持该模型。
- 当前机器资源是否足够加载。
- 该模型支持哪些能力：text、embedding、vision、OCR、transcription、TTS、tool calling。
- 该模型适合哪些任务：summary、classification、coder、reviewer、supervisor、privacy fallback。
- 加载、卸载、崩溃、内存风险、runtime 缺失等状态。

### 2.3 统一消费面

XT、Supervisor、Skills、普通 terminal 和外部 API 都读取同一个 Hub 模型可用性视图：

- `GetModelInventorySnapshot`
- `GetModelRouteDecision`
- `GetModelPreflight`
- `GetProviderKeyRuntimeSnapshot`
- `GetLocalRuntimeReadinessSnapshot`

旧文件读取可以保留为兼容 fallback，但新代码不能把文件当主真相源。

## 3) Success Metrics

1. 用户点“获取模型列表”时，scope 不足会显示缺哪个 scope，同时仍能展示可用 fallback catalog。
2. 用户输入 `GPT5.5`、`gpt5.5`、`openai/gpt5.5` 时，统一归一成稳定模型 ID。
3. 同一模型有多个账号时，runner 会跳过冷却、阻断、过期账号。
4. 429 后能记录 `quota_exceeded`、`rate_limited`、预计恢复时间和跳过原因。
5. XT 上看到的“可用/不可用/冷却/需要登录”与 Hub 实际 runner 决策一致。
6. 本地模型显示“可加载”前必须通过 runtime provider preflight。
7. Supervisor 高风险任务不会静默落到不合适的本地小模型。
8. 所有 route decision 都能解释“选了谁、跳过谁、为什么”。

## 4) Gate

- `RLM-G0 / Contract Freeze`
  - 远端模型、账号池、本地模型、preflight、route decision 契约冻结。
- `RLM-G1 / Remote Pool Correctness`
  - 远端账号池、quota、scope、alias、failover 正确。
- `RLM-G2 / Local Runtime Correctness`
  - 本地模型 preflight、runtime readiness、capability tags 正确。
- `RLM-G3 / Unified Route`
  - 远端和本地统一 route decision 可解释、可回放。
- `RLM-G4 / XT Parity`
  - XT UI、preflight、runner 使用同一份 Hub 真相。
- `RLM-G5 / Fail Closed`
  - scope、quota、auth、model unsupported、runtime missing 均不冒绿。
- `RLM-G6 / Require Real`
  - 至少一条远端真实调用链和一条本地真实加载链通过 smoke。

## 5) P0 / P1 总览

### P0

1. `RLM-W0-01` 冻结统一模型库存契约
2. `RLM-W1-01` 远端模型 ID 归一化和 alias table
3. `RLM-W1-02` Provider account pool route trace
4. `RLM-W1-03` 远端错误分类和恢复时间写回
5. `RLM-W1-04` 远端模型列表 fallback 和 scope explainability
6. `RLM-W2-01` 本地模型 artifact inventory
7. `RLM-W2-02` 本地 runtime provider preflight
8. `RLM-W2-03` 本地模型 capability snapshot
9. `RLM-W3-01` 统一 route decision API
10. `RLM-W3-02` XT 统一模型可用性视图
11. `RLM-W3-03` Doctor / UI explainability
12. `RLM-W4-01` 回归测试和 require-real smoke

### P1

13. `RLM-W5-01` 角色化模型池策略
14. `RLM-W5-02` 成本、预算、usage trend
15. `RLM-W5-03` 本地模型生命周期和存储治理
16. `RLM-W5-04` route replay / chaos / shadow compare

## 6) P0 详细工单

### RLM-W0-01 统一模型库存契约冻结

- priority: P0
- owner: Hub Runtime
- gate: `RLM-G0`
- files:
  - `docs/memory-new/xhub-remote-paid-and-local-model-management-execution-plan-v1.md`
  - `docs/memory-new/xhub-provider-auth-pool-contract-v1.md`
  - `protocol/hub_protocol_v1.proto`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-terminal/Sources/Hub/HubModels.swift`

Tasks:
1. 定义 `ModelInventorySnapshot`。
2. 定义 `RemoteModelInventoryRow`。
3. 定义 `LocalModelInventoryRow`。
4. 定义 `ModelRouteDecision`.
5. 定义 `ModelPreflightResult`.
6. 定义 `ModelCapabilityProfile`.
7. 在 proto / IPC / Swift model 中只做 additive 字段。
8. 给旧客户端保留兼容 fallback。

Contract fields:
- `model_id`
- `display_name`
- `source_kind`: `remote` / `local`
- `provider`
- `provider_host`
- `family_key`
- `capabilities`
- `task_fit`
- `availability_state`
- `blocking_reason_code`
- `blocking_message`
- `next_retry_at_ms`
- `route_policy_id`
- `last_health_at_ms`
- `last_success_at_ms`
- `last_failure_at_ms`

DoD:
- Hub 能返回统一库存 snapshot。
- XT 能 decode 新字段但不依赖全部字段存在。
- 缺字段不会 crash，只会显示 unknown / needs refresh。

Tests:
- `HubModels` decode additive fields。
- `services.js` 输出包含 remote/local 两类 row。
- 旧 fixture 仍能通过。

### RLM-W1-01 远端模型 ID 归一化和 alias table

- priority: P0
- owner: RELFlowHub
- gate: `RLM-G1/RLM-G5`
- files:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/RemoteProviderEndpoints.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/AddRemoteModelSheet.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteModelTrialRunner.swift`
  - `x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/RemoteModelTrialRunnerTests.swift`

Tasks:
1. 建立集中 alias normalizer。
2. 归一化 UI 输入模型 ID。
3. 归一化 config/auth 导入模型 ID。
4. 归一化 runner 真实请求模型 ID。
5. 对 provider prefix 做统一处理，例如 `openai/gpt5.5`。
6. 对大小写和缺横线的常见输入做修复。

Minimum aliases:
- `GPT5.5` -> `gpt-5.5`
- `gpt5.5` -> `gpt-5.5`
- `openai/gpt5.5` -> `gpt-5.5`
- `openai/GPT5.5` -> `gpt-5.5`
- `GPT-5.5` -> `gpt-5.5`

DoD:
- UI、存储、runner 使用同一个 normalizer。
- 错模型名不会直接导致不可解释 404。

Tests:
- alias table unit test。
- runner request body model ID test。
- import config model ID test。

### RLM-W1-02 Provider account pool route trace

- priority: P0
- owner: RELFlowHub
- gate: `RLM-G1/RLM-G3/RLM-G5`
- files:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ProviderKeyStorage.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteModelTrialRunner.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteProviderKeyRuntimeFeedbackSupport.swift`
  - `x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/RemoteModelTrialRunnerTests.swift`
  - `x-hub/macos/RELFlowHub/Tests/RELFlowHubCoreTests/ProviderKeyStorageImportSyncTests.swift`

Tasks:
1. 为 `loadRoutableCredentialPool` 返回候选账号 trace。
2. trace 中包含每个账号的 state、skip reason、next retry、priority。
3. runner 记录本次选择的 account key、pool id、route candidate order。
4. round-robin 策略记录 cursor 命中。
5. fill-first 策略记录 priority 命中。
6. 失败 fallback 时追加 attempted credentials。

Trace shape:
```json
{
  "model_id": "gpt-5.5",
  "pool_id": "openai:api.openai.com:responses",
  "routing_strategy": "round-robin",
  "selected_account_key": "openai:acct-ready",
  "candidates": [
    {
      "account_key": "openai:acct-cooling",
      "state": "cooldown",
      "routable": false,
      "reason_code": "quota_exceeded",
      "next_retry_at_ms": 1770000000000
    }
  ]
}
```

DoD:
- 每次 route 都能解释“为什么选中 / 为什么跳过”。
- UI 和 doctor 不需要重新推断 route 逻辑。

Tests:
- cooling account 被跳过。
- blocked auth 被跳过。
- stale OAuth 被跳过。
- degraded 账号可用但后排。
- round-robin 两个 ready account 轮转。

### RLM-W1-03 远端错误分类和恢复时间写回

- priority: P0
- owner: RELFlowHub
- gate: `RLM-G1/RLM-G5`
- files:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteProviderClient.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteProviderKeyRuntimeFeedbackSupport.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/ProviderKeyRefreshCoordinator.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ProviderKeyStorage.swift`
  - `x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/RemoteProviderClientTests.swift`

Tasks:
1. 标准化错误分类。
2. 从 provider body/header 中提取 retry/reset 时间。
3. 写回 `error_state.reason_code`。
4. 写回 `error_state.status_message`。
5. 写回 `error_state.next_retry_at_ms`。
6. 写回 `quota.cooldown_until_ms` 或 `quota.next_recover_at_ms`。
7. 写回 `retry_at_source`。

Reason code baseline:
- `missing_scope`
- `token_expired`
- `invalid_api_key`
- `auth_missing`
- `quota_exceeded`
- `rate_limited`
- `model_not_found`
- `model_not_supported`
- `invalid_base_url`
- `provider_timeout`
- `network_unreachable`

DoD:
- 429 不再只显示“额度用完”，必须区分 quota / rate limit / reset time。
- 404 不再只显示“模型不存在”，必须保留 provider body 和 normalized model。
- missing scope 能显示缺哪个 scope。

Tests:
- `api.model.read` 缺失。
- `api.responses.write` 缺失。
- OpenAI quota 429。
- rate limit reset。
- model_not_found 404。

### RLM-W1-04 远端模型列表 fallback 和 scope explainability

- priority: P0
- owner: RELFlowHub
- gate: `RLM-G1/RLM-G5`
- files:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/CodexModelCatalogFallback.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteProviderClient.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/DiscoverModelsSheet.swift`
  - `x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/RemoteProviderClientTests.swift`

Tasks:
1. `/models` 缺 `api.model.read` 时启用安全 fallback catalog。
2. fallback 结果必须标记来源：`provider_models` / `fallback_catalog` / `configured_model`。
3. UI 显示“模型列表读取 scope 不足，但可按配置模型继续尝试”。
4. 对 ChatGPT / Codex OAuth alias 启用 Codex catalog fallback。
5. fallback 不得掩盖生成请求的 scope 缺失。

DoD:
- “获取模型列表”不会因为 `api.model.read` 缺失直接变成 0 个模型。
- 真正生成时仍按 `api.responses.write` 或 chat completions 权限 fail closed。

Tests:
- 403 missing `api.model.read` fallback。
- 401 auth failed 不 fallback。
- unsupported models endpoint fallback。
- configured preferred model first。

### RLM-W2-01 本地模型 artifact inventory

- priority: P0
- owner: RELFlowHub / Local Runtime
- gate: `RLM-G2`
- files:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/LocalModelImportDetection.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/LocalModelManagedStorage.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/LocalProviderPackRegistry.swift`
  - `x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/LocalModelImportDetectorTests.swift`
  - `x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/LocalModelManagedStorageTests.swift`

Tasks:
1. 为本地模型记录 source、path、size、checksum。
2. 记录 format：GGUF、MLX、CoreML、Transformers、unknown。
3. 记录 quantization。
4. 记录 family 和 display name。
5. 记录 context length，如果无法识别则标 unknown。
6. 记录 artifact stale / missing / moved。
7. UI 不再只按文件名判断能力。

DoD:
- 模型移动、删除、损坏时能显示明确状态。
- 重扫不会重复导入同一个 artifact。

Tests:
- GGUF path scan。
- MLX folder scan。
- missing artifact stale。
- duplicate checksum dedupe。

### RLM-W2-02 本地 runtime provider preflight

- priority: P0
- owner: Local Runtime
- gate: `RLM-G2/RLM-G5`
- files:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/LocalModelRuntimeReadiness.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/LocalModelRuntimeSupportProbe.swift`
  - `x-hub/python-runtime/python_service/provider_pack_registry.py`
  - `x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`
  - `x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/LocalLibraryRuntimeReadinessResolverTests.swift`

Tasks:
1. 建立 runtime provider readiness snapshot。
2. 检测 provider executable / python package / model loader。
3. 检测 Metal / MLX / llama.cpp / transformers 依赖。
4. 检测可用内存和建议最大模型大小。
5. 检测模型是否能 dry-run load。
6. 将失败原因映射为 machine-readable code。

State baseline:
- `ready`
- `missing_runtime`
- `missing_dependency`
- `unsupported_format`
- `memory_risky`
- `load_failed`
- `unknown_stale`

DoD:
- UI 显示“为什么本地模型不能加载”。
- runner 不会把未通过 preflight 的模型当 available。

Tests:
- missing runtime。
- unsupported format。
- load failed。
- memory risky。

### RLM-W2-03 本地模型 capability snapshot

- priority: P0
- owner: Local Runtime / Hub Runtime
- gate: `RLM-G2/RLM-G3`
- files:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/RemoteModels.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/LocalModelExecutionProviderResolver.swift`
  - `x-terminal/Sources/Project/XTSkillCapabilityProfileSupport.swift`
  - `x-terminal/Sources/Supervisor/SupervisorModelRoutePolicy.swift`

Tasks:
1. 统一本地模型 capability schema。
2. 标注 text generation。
3. 标注 embedding。
4. 标注 vision。
5. 标注 OCR。
6. 标注 transcription。
7. 标注 TTS。
8. 标注 tool calling 支持级别。
9. 标注推荐 task fit。

Capability baseline:
- `text.generate`
- `text.summarize`
- `code.assist`
- `code.review`
- `embedding.generate`
- `vision.describe`
- `vision.ocr`
- `audio.transcribe`
- `audio.tts`
- `tool.calling`

DoD:
- Supervisor 不会把不支持 tool calling 的模型分配到强工具任务。
- XT skill preflight 可以按 capability fail closed。

Tests:
- capability decode。
- model route policy rejects missing capability。
- fallback model selected only when capability matches。

### RLM-W3-01 统一 route decision API

- priority: P0
- owner: Hub Runtime / RELFlowHub
- gate: `RLM-G3/RLM-G5`
- files:
  - `protocol/hub_protocol_v1.proto`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteModelTrialRunner.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubGRPCServerSupport.swift`
  - `x-terminal/Sources/Hub/HubAIClient.swift`

Tasks:
1. 添加 route decision 查询。
2. 输入包含 task type、model preference、capability requirement、budget preference。
3. 输出包含 selected route。
4. 输出包含 skipped candidates。
5. 输出包含 fallback chain。
6. 输出包含 fail-closed reason。
7. 输出包含 user action hints。

Decision types:
- `remote_paid_primary`
- `remote_pool_fallback`
- `local_privacy_primary`
- `local_cost_primary`
- `local_offline_fallback`
- `blocked_missing_capability`
- `blocked_auth`
- `blocked_quota`
- `blocked_runtime`

DoD:
- XT 可以先 preflight 再发起执行。
- route decision 和真实 runner 行为一致。

Tests:
- remote ready selected。
- remote quota fallback to sibling account。
- remote exhausted fallback to local only when task allows。
- high-risk task blocks instead of weak local fallback。

### RLM-W3-02 XT 统一模型可用性视图

- priority: P0
- owner: XT
- gate: `RLM-G4`
- files:
  - `x-terminal/Sources/Hub/HubModels.swift`
  - `x-terminal/Sources/Hub/HubAIClient.swift`
  - `x-terminal/Sources/UI/ModelSettingsView.swift`
  - `x-terminal/Sources/UI/SettingsView.swift`
  - `x-terminal/Sources/UI/XTModelInventoryTruthPresentation.swift`
  - `x-terminal/Tests/XTModelInventoryTruthPresentationTests.swift`

Tasks:
1. XT 模型页读取 Hub inventory snapshot。
2. 区分 remote / local。
3. 显示账号池状态摘要。
4. 显示本地 runtime readiness。
5. 显示 capability tags。
6. 显示 route action：登录、刷新、等待额度、修复 runtime、导入模型。
7. 移除 XT 自己推断 provider quota 的新路径。

DoD:
- XT 显示的可用状态与 Hub runner 一致。
- XT 不需要读取 token 明文。
- XT 可以显示“为什么不能用”和“下一步做什么”。

Tests:
- remote quota blocked projection。
- missing scope projection。
- local runtime missing projection。
- local capability mismatch projection。

### RLM-W3-03 Doctor / UI explainability

- priority: P0
- owner: RELFlowHub / XT / QA
- gate: `RLM-G4/RLM-G5`
- files:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteKeyHealthPresentationSupport.swift`
  - `x-terminal/Sources/UI/XHubDoctorOutput.swift`
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`

Tasks:
1. 为远端模型显示 provider、pool、account、scope、quota、retry。
2. 为本地模型显示 artifact、runtime、capability、memory。
3. 为 route decision 显示 selected / skipped。
4. 为用户动作显示 one-click repair target。
5. 把 provider 原始错误压缩成用户可读摘要。
6. 保留 machine-readable reason code。

DoD:
- 用户能从 UI 看出“free 额度为什么显示用完”。
- 用户能从 UI 看出“模型名错还是账号无权访问”。
- 用户能从 UI 看出“本地模型是文件问题、runtime 问题还是内存问题”。

Tests:
- presentation helper tests。
- doctor fixture tests。
- missing scope fixture。
- quota recovery fixture。

### RLM-W4-01 回归测试和 require-real smoke

- priority: P0
- owner: QA
- gate: `RLM-G6`
- files:
  - `x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/RemoteModelTrialRunnerTests.swift`
  - `x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/RemoteProviderClientTests.swift`
  - `x-hub/macos/RELFlowHub/Tests/RELFlowHubCoreTests/ProviderKeyStorageImportSyncTests.swift`
  - `x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/LocalModelRuntimeReadinessResolverTests.swift`
  - `scripts/ci/`

Tasks:
1. 增加远端 route trace fixture。
2. 增加本地 preflight fixture。
3. 增加 XT projection fixture。
4. 增加真实 OpenAI-compatible endpoint smoke，可用 env gate 控制。
5. 增加本地模型 dry-run smoke，可用小模型 fixture 或 explicit env path。
6. CI 默认跑 unit，require-real 只在显式环境变量下跑。

Suggested commands:
- `swift test --filter RemoteProviderClientTests`
- `swift test --filter RemoteModelTrialRunnerTests`
- `swift test --filter ProviderKeyStorageImportSyncTests`
- `swift test --filter LocalModelRuntimeReadinessResolverTests`
- `swift test --filter XTModelInventoryTruthPresentationTests`

DoD:
- P0 所有 unit tests 通过。
- require-real smoke 产生可保存 evidence。
- 失败 evidence 不包含 token 明文。

## 7) P1 详细工单

### RLM-W5-01 角色化模型池策略

- priority: P1
- owner: Hub Runtime / XT Supervisor
- files:
  - `x-terminal/Sources/Supervisor/SupervisorModelRoutePolicy.swift`
  - `x-terminal/Sources/Supervisor/SupervisorTurnRouter.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubTaskRoutingPolicy.swift`

Tasks:
1. 定义 `supervisor`、`coder`、`reviewer`、`summarizer`、`classifier`、`vision` 等 route profile。
2. 每个 profile 指定 required capabilities。
3. 每个 profile 指定 remote/local preference。
4. 每个 profile 指定 fallback permission。
5. 高风险任务禁止静默降级到弱模型。

DoD:
- Supervisor 路由策略可解释。
- XT UI 能显示当前任务为何选择某模型。

### RLM-W5-02 成本、预算、usage trend

- priority: P1
- owner: Hub Runtime / Product
- files:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteQuotaCenterSupport.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RemoteQuotaTrendSupport.swift`
  - `x-terminal/Sources/Hub/ProviderKeyRuntimeFeedbackSupport.swift`

Tasks:
1. 汇总 provider family usage。
2. 汇总用户/项目/consumer usage。
3. 汇总本地模型节省估算。
4. 标记高消耗任务。
5. 给出预算耗尽前提醒。

DoD:
- 用户能知道钱花在哪里。
- 用户能知道免费额度什么时候恢复。

### RLM-W5-03 本地模型生命周期和存储治理

- priority: P1
- owner: RELFlowHub / Local Runtime
- files:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/LocalModelManagedStorage.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/LocalModelAccessBookmarkStore.swift`

Tasks:
1. 增加模型删除。
2. 增加迁移。
3. 增加重新校验。
4. 增加最近使用排序。
5. 增加模型占用空间总览。
6. 增加 stale bookmark repair。

DoD:
- 本地模型库可以长期维护，不靠手动清文件。

### RLM-W5-04 Route replay / chaos / shadow compare

- priority: P1
- owner: QA / Hub Runtime
- files:
  - `x-hub/grpc-server/hub_grpc_server/src/rust_provider_route_shadow_compare.js`
  - `x-hub/grpc-server/hub_grpc_server/src/provider_key_router.js`
  - `scripts/ci/`

Tasks:
1. 保存 route decision replay fixture。
2. 对 quota/auth/network/model unsupported 注入 chaos。
3. 对新旧 router 做 shadow compare。
4. 对 XT projection 做 snapshot compare。

DoD:
- route 改动可以先 shadow compare，再切主链路。

## 8) 推荐实施顺序

1. 先做 `RLM-W0-01`，冻结统一库存和 route decision 字段。
2. 再做 `RLM-W1-02` 和 `RLM-W1-03`，保证远端账号池真实可运营。
3. 并行做 `RLM-W2-01` 和 `RLM-W2-02`，让本地模型从“扫描到”升级为“可跑”。
4. 做 `RLM-W3-01`，把远端和本地 route 收口成同一 API。
5. 做 `RLM-W3-02`，让 XT 只读 Hub 真相。
6. 做 `RLM-W3-03` 和 `RLM-W4-01`，补 UI explainability 和回归门禁。
7. 最后做 P1 的成本、生命周期、角色化和 shadow compare。

## 9) 当前已落地能力映射

截至 2026-04-29，已有基础包括：

- ChatGPT / Codex OAuth 缺 `api.model.read` 时的 catalog fallback。
- 常见 OpenAI 模型 ID typo 归一化。
- Provider account pool 的 fill-first / round-robin runtime failover。
- 跳过 disabled、stale、auth failed、cooldown、quota recover pending 账号。
- CLIProxy OAuth 同步到 Hub provider key pool。
- CLIProxy OAuth UI 显示 Hub 账号池可路由状态。

仍需补齐：

- route decision trace 的正式 API。
- 本地模型统一 preflight snapshot。
- XT 统一模型可用性视图。
- doctor 中远端/本地统一 explainability。
- require-real smoke evidence。

## 10) 用户可见产品原则

1. 别让用户猜。
   - 显示“缺 scope: api.model.read”，不要只显示权限不足。
2. 别让用户误以为 free 额度还能用。
   - 显示 quota reason、next recover time、被跳过账号数。
3. 别让用户手动管理多个账号。
   - Hub 自动 round-robin / fill-first / failover。
4. 别让本地模型冒充强模型。
   - 本地 fallback 必须标注能力降级。
5. 别让 XT 变成第二真相源。
   - XT 展示 Hub 真相，不复制 Hub 调度逻辑。
