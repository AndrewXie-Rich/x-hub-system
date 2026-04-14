# Local Provider Runtime + Transformers Integration 实现子工单包

- version: v1.1
- updatedAt: 2026-03-25
- owner: Hub Runtime（Primary）/ Memory / Security / QA
- status: active
- scope: `LPR-W1-01..05` + `LPR-W2-01..04` + `LPR-W3-01..08` + `LPR-W4-01..09`
- parent:
  - `docs/xhub-local-provider-runtime-and-transformers-integration-v1.md`
  - `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
  - `docs/xhub-memory-system-spec-v2.md`
  - `docs/xhub-runtime-stability-and-launch-recovery-v1.md`

## 0) 为什么需要这份包

主工单已经冻结了方向与 Gate，但要真正进入实施，还需要再往下一层拆成：

- 具体文件路径
- 具体改动点
- 每项子工单的 DoD
- 回归与证据文件名
- 建议执行顺序

本包的目的，就是把 LPR 这条线从“已经有 spec 和主工单”推进到“可以直接开工分段落地”。

## 1) 实施主链与红线

### 1.1 主链

Local Provider Runtime 只能按下面这条主链推进：

1. schema / manifest / status freeze
2. backend-aware model import
3. provider runtime skeleton
4. MLX compatibility
5. embeddings
6. audio / ASR
7. capability split / policy / diagnostics
8. vision preview
9. require-real
10. provider pack / runtime bundle / typed load config
11. auto-detect model import / capability-first library
12. loaded instance console / runtime operations
13. bench + monitor fusion
14. `mlx_vlm` / `llama.cpp` provider expansion + product exit

### 1.2 红线

- 不得在没有 LPR 统一入口前，直接把 Transformers 逻辑硬塞进 `relflowhub_mlx_runtime.py` 成为长期结构。
- 不得先做在线下载，再补治理。
- 不得让 XT 或其它 client 直接绕 Hub 调本地 provider。
- 不得让 `mlxOk=false` 被误解释成“全部本地能力不可用”。
- 不得在 capability 未细分前，口头放行音频/视觉本地任务。

## 2) 当前基线（可复用资产）

### 2.1 Swift / Hub App

- `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelModels.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/AddModelSheet.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/AIRuntimeStatus.swift`

### 2.2 Python runtime

- `x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`
- `x-hub/python-runtime/python_service/relflowhub_model_worker.py`
- `x-hub/python-runtime/python_service/relflowhub_ai_worker.py`

### 2.3 Node / gRPC bridge

- `x-hub/grpc-server/hub_grpc_server/src/mlx_runtime_ipc.js`
- `x-hub/grpc-server/hub_grpc_server/src/services.js`
- `x-hub/grpc-server/hub_grpc_server/src/models_watcher.js`

### 2.4 Memory 相关

- `docs/xhub-memory-system-spec-v2.md`
- `x-hub/grpc-server/hub_grpc_server/src/memory_*`

## 3) 子工单分解（直接执行粒度）

### 3.1 `LPR-W1-01-A` Model Descriptor Schema Freeze

- 目标：扩展 `ModelCatalogEntry` / `HubModel` 的 canonical 字段。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelModels.swift`
- 必做字段：
  - `modelFormat`
  - `taskKinds`
  - `inputModalities`
  - `outputModalities`
  - `offlineReady`
  - `resourceProfile`
  - `trustProfile`
  - `processorRequirements`
- DoD：
  - 新字段支持 decode 老数据
  - encode 后仍可落盘到 `models_catalog.json` / `models_state.json`
  - 无字段时默认 fail-safe，不假绿
- 证据：
  - `build/reports/lpr_w1_01_a_model_descriptor_schema_evidence.v1.json`

### 3.2 `LPR-W1-01-B` Local Manifest v1 Parser

- 目标：定义并解析 `xhub_model_manifest.json`。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/AddModelSheet.swift`
  - 可新增 parser/support 文件于 `RELFlowHubCore`
- DoD：
  - manifest schema 与 spec 一致
  - 缺 manifest 时允许推断
  - 推断失败返回 machine-readable error
- 证据：
  - `build/reports/lpr_w1_01_b_manifest_parser_evidence.v1.json`

### 3.3 `LPR-W1-01-C` Runtime Status v2

- 目标：把本地运行时状态从 `mlxOk` 升级为 provider-aware。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/AIRuntimeStatus.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
  - `x-hub/python-runtime/python_service/`
- DoD：
  - 新状态支持 `providers.mlx` / `providers.transformers`
  - 老状态仍可解析
  - UI 至少能显示 `MLX only / Transformers only / partial / all down`
- 证据：
  - `build/reports/lpr_w1_01_c_runtime_status_v2_evidence.v1.json`

### 3.4 `LPR-W1-02-A` Add Model Backend Selector

- 目标：让 Add Model UI 先选 backend，再走对应校验。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/AddModelSheet.swift`
- DoD：
  - UI 支持 `MLX` 与 `Transformers`
  - MLX 导入流程无回归
  - Transformers 导入只接受本地目录
- 证据：
  - `build/reports/lpr_w1_02_a_add_model_backend_selector_evidence.v1.json`

### 3.5 `LPR-W1-02-B` Catalog Compatibility Migration

- 目标：兼容旧 `models_catalog.json` / `models_state.json`。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelModels.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/ModelStore.swift`
- DoD：
  - 老 catalog 不崩
  - 新字段缺失时有稳定默认值
  - backend 未识别时不 silent drop
- 证据：
  - `build/reports/lpr_w1_02_b_catalog_migration_evidence.v1.json`

### 3.6 `LPR-W1-03-A` Local Runtime Entry

- 目标：新增高层运行时入口。
- 涉及路径：
  - `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
- DoD：
  - 启动后能输出 provider-aware ready/status
  - 支持 `run_local_task`
  - 可兼容旧 `generate`
- 证据：
  - `build/reports/lpr_w1_03_a_local_runtime_entry_evidence.v1.json`

### 3.7 `LPR-W1-03-B` Provider Base + MLX Adapter

- 目标：把现有 MLX 路径收敛成 provider adapter。
- 涉及路径：
  - `x-hub/python-runtime/python_service/providers/base.py`
  - `x-hub/python-runtime/python_service/providers/mlx_provider.py`
  - `x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`
- DoD：
  - MLX 通过 provider 接口暴露 `text_generate`
  - 保留当前 load/unload/generate 能力
  - 旧脚本可作为实现细节继续复用
- 证据：
  - `build/reports/lpr_w1_03_b_mlx_provider_adapter_evidence.v1.json`

### 3.8 `LPR-W1-03-C` Transformers Provider Skeleton

- 目标：新增 Transformers provider 骨架。
- 涉及路径：
  - `x-hub/python-runtime/python_service/providers/transformers_provider.py`
- DoD：
  - 可上报健康状态
  - 可列出已注册模型
  - 能拒绝未实现 task，而不是 silent success
- 证据：
  - `build/reports/lpr_w1_03_c_transformers_provider_skeleton_evidence.v1.json`

### 3.9 `LPR-W1-04-A` Swift HubStore Bridge Generalization

- 目标：让 `HubStore` 不再硬编码“本地 runtime == MLX”。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
- DoD：
  - `aiGenerate` 至少按 `task_kind=text_generate` 与 provider-aware readiness 工作
  - 本地 runtime 不可用时，错误文案能区分 provider 级问题
- 证据：
  - `build/reports/lpr_w1_04_a_hubstore_bridge_generalization_evidence.v1.json`

### 3.10 `LPR-W1-04-B` Node Runtime IPC Generalization

- 目标：让 Node 本地 runtime bridge 不再只认 MLX。
- 涉及路径：
  - `x-hub/grpc-server/hub_grpc_server/src/mlx_runtime_ipc.js`
  - 如必要可新增 `local_runtime_ipc.js`
- DoD：
  - `models_state.json` 读取逻辑兼容新字段
  - `run_local_task` 能桥接到本地 runtime
  - 旧 `generate` 不回退
- 证据：
  - `build/reports/lpr_w1_04_b_node_runtime_bridge_evidence.v1.json`

### 3.11 `LPR-W1-05-A` MLX Regression Matrix

- 目标：引入 LPR 后锁住 MLX 回归。
- 涉及路径：
  - Python provider tests
  - Swift model/runtime tests
  - Node bridge tests
- DoD：
  - load/unload/generate 主链回归全绿
  - MLX import error 仍能被 doctor/diagnostics 正确识别
- 证据：
  - `build/reports/lpr_w1_05_a_mlx_regression_matrix_evidence.v1.json`

### 3.12 `LPR-W2-01-A` Embedding Task Contract

- 目标：定义并接通 `embedding` 请求。
- 涉及路径：
  - `relflowhub_local_runtime.py`
  - `providers/transformers_provider.py`
  - Node memory integration
- DoD：
  - batch embeddings 可执行
  - 返回 dims / vector count / latency
  - 大文本与敏感文本遵守 policy
- 证据：
  - `build/reports/lpr_w2_01_a_embedding_contract_evidence.v1.json`

### 3.13 `LPR-W2-01-B` Memory v2 Integration

- 目标：把本地 embeddings 接进 Memory v2。
- 涉及路径：
  - `x-hub/grpc-server/hub_grpc_server/src/memory_*`
  - `docs/xhub-memory-system-spec-v2.md` 对齐实现
- DoD：
  - local embeddings provider 可被 memory path 调用
  - `ai.embed.local` capability 生效
  - audit / deny / fallback 完整
- 证据：
  - `build/reports/lpr_w2_01_b_memory_embeddings_integration_evidence.v1.json`

### 3.14 `LPR-W2-02-A` Speech-to-Text Task Contract

- 目标：定义并接通 `speech_to_text`。
- 涉及路径：
  - `providers/transformers_provider.py`
  - `relflowhub_local_runtime.py`
- DoD：
  - 支持本地音频文件输入
  - 返回 text / segments / usage
  - 失败语义 machine-readable
- 证据：
  - `build/reports/lpr_w2_02_a_asr_contract_evidence.v1.json`

### 3.15 `LPR-W2-02-B` Audio Input Guard

- 目标：音频输入限制 fail-closed。
- 涉及路径：
  - Node/Swift 请求入口
  - local runtime request validator
- DoD：
  - 时长、大小、格式限制生效
  - oversized / unsupported 格式显式拒绝
- 证据：
  - `build/reports/lpr_w2_02_b_audio_guard_evidence.v1.json`

### 3.16 `LPR-W2-03-A` Capability Split / Policy Wiring

- 目标：把本地任务能力从一个开关拆成多个。
- 涉及路径：
  - `protocol/hub_protocol_v1.md`
  - `protocol/hub_protocol_v1.proto`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- DoD：
  - 至少支持 `ai.generate.local / ai.embed.local / ai.audio.local / ai.vision.local`
  - policy 与 deny_code 对齐
  - kill-switch 能按 provider/task 生效
- 证据：
  - `build/reports/lpr_w2_03_a_capability_policy_evidence.v1.json`

### 3.17 `LPR-W2-03-B` Local Task Audit / Deny Map

- 目标：为本地多任务补齐审计与拒绝码。
- 涉及路径：
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/db.js`
- DoD：
  - 每个本地任务写 audit metadata
  - deny_code 覆盖 capability / modality / size / provider_unavailable / policy_blocked
- 证据：
  - `build/reports/lpr_w2_03_b_local_task_audit_evidence.v1.json`

### 3.18 `LPR-W2-04-A` Provider-aware Diagnostics

- 目标：Diagnostics 正式显示 provider 级状态。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubDiagnosticsBundleExporter.swift`
- DoD：
  - diagnostics 展示 `mlx / transformers` 各自状态与 root-cause
  - 诊断包导出 provider-aware 状态
- 证据：
  - `build/reports/lpr_w2_04_a_provider_diagnostics_evidence.v1.json`

### 3.19 `LPR-W2-04-B` Doctor / Operator Summary

- 目标：Doctor 与 operator summary 能解释 provider-ready 状态。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
  - 相关 doctor / settings 入口
- DoD：
  - 至少支持“MLX down / embeddings up / audio blocked”的组合解释
  - 支持一键复制 operator summary
- 证据：
  - `build/reports/lpr_w2_04_b_operator_summary_evidence.v1.json`

### 3.20 `LPR-W3-01-A` Vision/OCR Preview Contract

- 目标：冻结视觉 preview 的请求契约。
- 涉及路径：
  - local runtime
  - provider contract
  - request validator
- DoD：
  - `vision_understand` 或 `ocr` 至少一条 preview 主链可跑
  - 输出 schema 固定
- 证据：
  - `build/reports/lpr_w3_01_a_vision_preview_contract_evidence.v1.json`

### 3.21 `LPR-W3-01-B` Image Input Guard

- 目标：图像输入大小/像素/格式限制 fail-closed。
- DoD：
  - 不合规图片显式拒绝
  - usage / audit 可记录 image bytes / dimensions
- 证据：
  - `build/reports/lpr_w3_01_b_image_guard_evidence.v1.json`

### 3.22 `LPR-W3-02-A` Runtime Resource Policy

- 目标：Provider 共存时的资源调度与并发控制。
- 涉及路径：
  - `relflowhub_local_runtime.py`
  - provider registry / scheduler
- DoD：
  - provider 级并发限制
  - 资源画像字段被消费
  - contention 时 fail-closed / queued 语义明确
- 证据：
  - `build/reports/lpr_w3_02_a_runtime_resource_policy_evidence.v1.json`

### 3.23 `LPR-W3-04-A` Load Profile Schema / Merge Rules

- 执行状态（2026-03-13）：
  - delivered
  - 已完成 `maxContextLength / defaultLoadProfile / device load profile store` schema 落地
  - 已保持 `contextLength -> default_load_profile.context_length` 兼容映射
  - 已补 `LocalProviderRuntimeSchemaTests` 覆盖 snake_case / legacy decode / paired-terminal profile snapshot

- 目标：把本地模型的静态身份与 device-scoped load profile 正式拆开。
- 涉及路径：
  - `docs/xhub-local-provider-runtime-and-transformers-integration-v1.md`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelModels.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubGRPCServerSupport.swift`
- DoD：
  - 新增 `maxContextLength` / `defaultLoadProfile` / `device load profile` 的明确语义
  - 现有 `contextLength` 保持兼容，但只作为 `default_load_profile.context_length` 映射
  - paired terminal 的设备级配置进入独立 store，而不是覆写 model catalog
- 证据：
  - `build/reports/lpr_w3_04_a_load_profile_schema_evidence.v1.json`

### 3.24 `LPR-W3-04-B` Paired Terminal Settings / Effective Context UX

- 执行状态（2026-03-13）：
  - delivered
  - Hub `Edit Paired Device` 已可按 local model 设置 `context_length` override，并保留隐藏 load fields 不被 UI 覆写丢失
  - Hub UI 已展示 `max / default / effective / source`，其中 source 支持 `hub_default / device_override / runtime_clamped`
  - X-Terminal `Model Settings / Supervisor Settings` 已显示 Hub catalog 的 `default / max` context，并明确把 per-device override 入口收口到 Hub pairing

- 目标：让 Hub/X-Terminal 能为每个 paired terminal 展示并修改 effective local context。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubGRPCServerSupport.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - `x-terminal/Sources/UI/ModelSettingsView.swift`
  - `x-terminal/Sources/UI/SupervisorSettingsView.swift`
- DoD：
  - paired terminal 可设置本地模型 `context_length` override
  - UI 同时展示 `max / default / effective` context
  - UI 可明确显示 source：`hub_default` / `device_override` / `runtime_clamped`
- 证据：
  - `build/reports/lpr_w3_04_b_effective_context_ux_evidence.v1.json`

### 3.25 `LPR-W3-04-C` Runtime Instance Cache by Load Profile Hash

- 目标：让同一模型在不同 terminal 设备上可按不同 load profile 被安全复用或隔离。
- 涉及路径：
  - `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
  - `x-hub/python-runtime/python_service/local_provider_scheduler.py`
  - `x-hub/python-runtime/python_service/providers/transformers_provider.py`
  - `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_embeddings.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_audio.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_vision.js`
- 当前状态（2026-03-13）：
  - delivered：LPR `run-local-task` 主链现已按 `provider + model_id + load_profile_hash` 生成 `instance_key`
  - delivered：scheduler active lease telemetry 已暴露 `device_id / load_profile_hash / instance_key / effective_context_length`
  - delivered：Transformers embedding / ASR cache key 已切到 `instance_key` 优先
  - delivered：Node 本地 embedding / audio / vision 请求已透传 `device_id`，memory path 已接通 paired terminal 设备上下文
  - 2026-03-20 revalidated：legacy `relflowhub_mlx_runtime.py` 的 load / unload / generate / bench 已统一消费 `instance_key / load_profile_hash / effective_context_length`，public instance identity 与 loaded-instance inventory 现已按 load profile 收口
  - remain honest：`LPR-G6` 仍待真实本地模型目录 smoke；没有 require-real 样本前不能把 W3 主链报成 fully green
- DoD：
  - loaded instance key 至少包含 `provider + model_id + load_profile_hash`
  - 相同 effective load profile 的请求优先复用实例
  - 不同 `context_length` 的请求不会 silent mutate 同一已加载实例
  - 资源不足时显式 `queue / reject / unload-then-load`
- 证据：
  - `build/reports/lpr_w3_04_c_instance_cache_evidence.v1.json`

### 3.26 `LPR-W3-03-A` Require-Real Runbook / Evidence

- 目标：把 LPR 纳入真实样本与发布门禁。
- 涉及路径：
  - `scripts/`
  - `docs/memory-new/`
- DoD：
  - embeddings / audio / vision 各至少 1 条真实样本
  - 证据生成与校验脚本可运行
- 证据：
  - `build/reports/lpr_w3_03_a_require_real_evidence.v1.json`
- 当前落点：
  - `docs/memory-new/xhub-local-provider-runtime-require-real-runbook-v1.md`
  - `build/reports/lpr_w3_03_require_real_capture_bundle.v1.json`
  - `scripts/generate_lpr_w3_03_a_require_real_evidence.js`
  - `scripts/update_lpr_w3_03_require_real_capture_bundle.js`
  - `scripts/lpr_w3_03_require_real_status.js`
  - `scripts/generate_lpr_w3_03_b_runtime_candidate_probe.js`
  - `scripts/generate_lpr_w3_03_c_model_native_loadability_probe.js`
  - `scripts/generate_lpr_w3_03_d_helper_bridge_probe.js`
  - `build/reports/lpr_w3_03_b_runtime_candidate_probe.v1.json`
  - `build/reports/lpr_w3_03_c_model_native_loadability_probe.v1.json`
  - `build/reports/lpr_w3_03_d_helper_bridge_probe.v1.json`
  - 2026-03-20 probe 结论：`LM Studio cpython3.11 + app-mlx-generate site-packages` 已可把 `torch + transformers + PIL + tokenizers` 组合成 ready runtime，但当前本机 embedding 模型目录仍真实 fail-closed 为 `unsupported_quantization_config`
  - 2026-03-20 model probe 结论：本机只发现 `1` 条 embedding 候选目录，且 `0` 条是 `torch/transformers native-loadable`；当前目录的静态标记为 `quantization_config_missing_quant_method + scales/biases sidecars`
  - 2026-03-21 helper probe 结论：helper binary `~/.lmstudio/bin/lms` 存在，但当前 root blocker 已收敛为 `helper_local_service_disabled`；机读证据显示 `~/.lmstudio/settings.json` 为 `enableLocalService=false`, `cliInstalled=false`, `appFirstLoad=true`
  - 同一 probe 也确认：`lms daemon up --json` 与 `lms server start --bind 127.0.0.1 --port 1234` 仍会停在 `Waking up LM Studio service...` 并超时；即使 `llmster` 进程仍存活并监听 `127.0.0.1:41343`，`server status --json` 仍为 `{"running":false}`
  - 2026-03-21 prewire 结论：已新增 `xhub_local_service` contract / resolver / schema / guidance 接线，当前 UI 与 runtime 机读面已经能区分 `xhub_local_service_config_missing / unreachable / starting / not_ready / ready`，后续可以在不碰 LM Studio 设置的前提下，继续把 Hub 自管 local service 作为主线推进
  - 2026-03-21 multimodal proxy 结论：`x-hub/python-runtime/python_service/xhub_local_service_runtime.py` 现已把 `/v1/embeddings`、`/v1/chat/completions` 接到 `run_local_task(...)`，输出 OpenAI-style response shape；同时补了 service-internal runtime resolution，让 `executionMode=xhub_local_service` 在 service 自己的进程里按 service-hosted modules 做真实可执行性判断，而不是继续递归探测 `/health`；当前 chat 已支持本地图片 content part 路由到 `vision_understand / ocr`，并对远程 `http(s)` image URL 保持 fail-closed
  - 2026-03-21 doctor/export 结论：Hub doctor 现在会把 `xhub_local_service_config_missing / unreachable / starting / not_ready` 直接投影成 `current_failure_code`，同时 diagnostics bundle 新增 `xhub_local_service_snapshot.redacted.json`，把 provider->endpoint->reason_code->queue/loaded_instance 证据导出成 machine-readable snapshot，便于 incident export 和自动归因
  - 2026-03-21 richer multimodal contract 结论：Transformers provider 已补齐 `image_paths` / `multimodal_messages` 的真实消费，multi-image real runtime 与 helper bridge 都会传递全部图片，而不是只吃第一张；同时修掉 image path 被 lower-case 后导致大小写路径失真的风险；`xhub_local_service` response 现已稳定输出 `routeTrace(selectedTaskKind/selectionReason/explicitTaskKind/resolvedImages/blockedReasonCode)`，可直接作为后续 monitor / export 的统一上游
  - 2026-03-21 routeTrace export 结论：Transformers provider quick bench 成功面现在会带出底层 task 的 `routeTrace`；`relflowhub_local_runtime.py` 会把它归档到 `models_bench.json.results[].routeTrace`，并生成 `routeTraceSummary`；`ai_runtime_status.json` 与 `monitorSnapshot` 会同步暴露 `recentBenchResults`；Hub JS IPC 则归一化为 `recent_bench_results[].route_trace_summary`，方便 supervisor/operator 直接读“最近一次 bench 走的是 real runtime / helper bridge / fallback preview 哪条路径”
  - 2026-03-21 routeTrace wording 结论：macOS core 已补 `recentBenchResults.routeTraceSummary` decode，`providerOperatorSummary` / `providerDoctorText` / `runtimeMonitorOperatorSummary` / `XHubDoctorOutputHub.buildMonitorCheck(...)` / diagnostics export 现会把最近一次 bench 的 `execution_path / fallback_mode / blocked_reason / image_count` 提到 operator-readable 文案，而不是只剩 monitor raw JSON
  - 2026-03-21 multi-image OCR page-aware 结论：provider 现已把 OCR 多图请求改成按页 fanout，再聚合成单次 `ocr` 结果；因此 `spans[]` 不再在 `image_count>1` 时直接清空，而会稳定带 `pageIndex / pageCount / fileName / bbox`，聚合 `text` 也带 `[page N]` 分段；service proxy 与 Hub local vision 归一化层都会原样保留这些页级字段

### 3.27 `LPR-W3-05-A` Local Runtime Warmup / Unload Contract

- 目标：为非 MLX provider 建立显式的 warmup / unload / evict contract，而不是继续复用 legacy `model_command`.
- 涉及路径：
  - `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
  - `x-hub/python-runtime/python_service/providers/base.py`
  - `x-hub/python-runtime/python_service/providers/mlx_provider.py`
  - `x-hub/python-runtime/python_service/providers/transformers_provider.py`
  - `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js`
- DoD：
  - LPR 支持 `warmup_local_model` / `unload_local_model` / `evict_local_instance`
  - warmup 结果返回 `provider / model_id / task_kinds / instance_key / device_backend / cold_start_ms`
  - unsupported provider 或 unsupported task 必须 fail-closed
  - legacy MLX `model_command` 仍兼容，但不再是唯一推荐控制面
- 落地：
  - `ProviderHealth` 与 `LocalProvider` 新增 lifecycle contract 字段与默认 fail-closed 行为
  - `relflowhub_local_runtime.py` 新增 `manage_local_model(...)` 与 `manage-local-model` CLI 入口，并复用 scheduler 做 provider 级串行化
  - `MLXProvider` 明确标记 `lifecycleMode=mlx_legacy`，所有新 lifecycle action 统一返回 `unsupported_lifecycle:mlx_legacy`
  - `TransformersProvider` 新增 `warmup_model / unload_model / evict_instance`，并把 warmable task 明确限定为 `embedding / speech_to_text`
  - runtime / IPC status 新增 `lifecycleMode / supportedLifecycleActions / warmupTaskKinds / residencyScope`，同时 Node 侧提供 `manageLocalModelLifecycle(...)`
  - provider cache 元数据补齐到 `instance_key / load_profile_hash / effective_context_length / loaded_at / last_used_at`
- residual gap：
  - 初版 contract 以 `process_local` 为保守基线；`LPR-W3-05-D` 已补上 resident daemon proxy，当常驻 runtime 持有 provider 且 heartbeat 新鲜时，Transformers residency 可升级为 `runtime_process`
  - preview-only task 仍必须显式返回 `preview_only` 或 `unsupported_lifecycle:*`，不得借 resident proxy 假装可 warmup
- 验证：
  - `PYTHONPYCACHEPREFIX=/tmp python3 -m py_compile x-hub/python-runtime/python_service/providers/base.py x-hub/python-runtime/python_service/providers/mlx_provider.py x-hub/python-runtime/python_service/providers/transformers_provider.py x-hub/python-runtime/python_service/relflowhub_local_runtime.py x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
  - `PYTHONPYCACHEPREFIX=/tmp python3 x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_embeddings.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_audio.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_vision.test.js`
- 证据：
  - `build/reports/lpr_w3_05_a_warmup_contract_evidence.v1.json`

### 3.28 `LPR-W3-05-B` Hub UI Warmup / Unload Generalization

- 目标：让 Hub 模型列表对本地非 MLX 模型显示正确动作，而不是直接提示 legacy 阻断文案。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/ModelStore.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/AIRuntimeStatus.swift`
- DoD：
  - `Load` 对 provider-aware 模型改成 `Warmup`
  - `Unload` 对支持实例生命周期的 provider 可见
  - action failure 文案不再写死 `legacy MLX command path`
  - UI 可区分 `warmable`、`ephemeral_on_demand`、`mlx_legacy`
- 落地：
  - `AIRuntimeProviderStatus` 新增 lifecycle / loaded instance schema：`lifecycleMode / supportedLifecycleActions / warmupTaskKinds / residencyScope / loadedInstances`
  - Swift 侧新增 `hubControlMode(forModelTaskKinds:)`，把 provider metadata 统一收敛为 `mlx_legacy / warmable / ephemeral_on_demand`
  - Hub 模型卡片新增 lifecycle badge；`MLX Legacy` 保留 `Load/Sleep/Unload/Bench`
  - `ModelStore.enqueue(...)` 改为 provider-aware planner：先检查 runtime/provider readiness，再按 lifecycle truth 决定 `legacy command` 或 fail-closed
  - `process_local` provider 不再显示伪 warmup；当前 `transformers` 模型卡片显示 `On-Demand`
- residual gap：
  - `LPR-W3-05-D` 已把 `runtime_process` warmable provider 的 `Warmup / Unload` 接到 resident daemon transport；只有 `process_local` provider 仍保留 `On-Demand` fail-closed 语义
  - Hub action planner 现在会诚实区分 `runtime_process` 与 `process_local`；是否真正展示已加载状态仍依赖常驻 runtime 定期回写 `models_state.json`
  - live-model require-real smoke 仍待补上，用来证明真实本地模型目录在 Hub UI 上可以稳定 warmup / unload / bench
- 验证：
  - `swift test --filter LocalProviderRuntimeSchemaTests`
  - `swift test --filter LocalModelRuntimeActionPlannerTests`
- 证据：
  - `build/reports/lpr_w3_05_b_hub_warmup_ui_evidence.v1.json`

### 3.29 `LPR-W3-05-C` Loaded Instance Inventory / Idle Eviction Semantics

- 目标：把 runtime 内已加载实例做成一等对象，支撑 unload、monitor、bench 与 idle eviction。
- 涉及路径：
  - `x-hub/python-runtime/python_service/providers/base.py`
  - `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
  - `x-hub/python-runtime/python_service/providers/transformers_provider.py`
  - `x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`
  - `x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
  - `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
- DoD：
  - provider status 暴露 `loaded_instances[]`
  - 每个 instance 至少带 `instance_key / model_id / task_kinds / load_profile_hash / effective_context_length / loaded_at / last_used_at`
  - 明确 `resident` 与 `ephemeral` 区别
  - idle eviction 行为 machine-readable，不得 silent evict
- 落地：
  - `ProviderHealth` 新增 lifecycle inventory 字段：`loadedInstances / idleEviction`，provider status 不再只能表达 `loadedModels[]`
  - `TransformersProvider` 新增进程本地 sidecar：`xhub_transformers_process_local_state.v1.json`，记录 `loadedInstances / loadedInstanceCount / idleEviction / ownerPid`
  - `TransformersProvider.healthcheck(...)` 现在显式暴露 `loadedInstances`，并把 `manual_evict_instance / manual_unload / process_exit / process_exit_reconciled` 写成 machine-readable eviction reason，而不是 silent disappear
  - `relflowhub_local_runtime.py` 聚合 provider 状态到顶层 `loadedInstances / loadedInstanceCount / idleEvictionByProvider`，并在 `run_local_task(...)` 与 `manage_local_model(...)` 后回写 runtime status
  - `relflowhub_mlx_runtime.py` 的 resident status writer 现在保留 provider 级 loaded instance 与 idle eviction 聚合结果，Node 侧 `local_runtime_ipc.js` 会统一归一化这些字段
  - scheduler active task telemetry 同步补齐 `device_id / load_profile_hash / instance_key / effective_context_length`，让 loaded instance 和 active task 可以对齐到同一 identity
  - 回归覆盖 manual evict、manual unload、process exit reconciliation、Node snapshot normalization，以及 `local_embeddings / local_audio / local_vision` 主链不回退
- residual gap：
  - resident runtime 现在会把 non-MLX loaded state 与 provider inventory 同步回 `models_state.json`，但仅在 daemon heartbeat 新鲜且 provider 由常驻 runtime 持有时才会表现为 `runtime_process`
  - one-shot Python 命令路径仍保留为 backward-compatible fallback；daemon 缺席或过旧时，inventory 会继续回到 `process_local` / `process_exit*` 语义
  - require-real 还未用真实本地模型验证 idle eviction、multi-instance warmup 与 bench 之间的联动稳定性
- 验证：
  - `PYTHONPYCACHEPREFIX=/tmp python3 -m py_compile x-hub/python-runtime/python_service/providers/base.py x-hub/python-runtime/python_service/providers/transformers_provider.py x-hub/python-runtime/python_service/relflowhub_local_runtime.py x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
  - `PYTHONPYCACHEPREFIX=/tmp python3 x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_embeddings.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_audio.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_vision.test.js`
- 证据：
  - `build/reports/lpr_w3_05_c_loaded_instance_inventory_evidence.v1.json`

### 3.30 `LPR-W3-08-A` Task Routing Settings Schema v2

- 目标：把本地任务默认模型绑定从环境变量和隐式首选，升级成正式 routing store。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/LocalTaskRoutingSettings.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/RoutingSettings.swift`
  - `x-hub/macos/RELFlowHub/Tests/RELFlowHubCoreTests/LocalTaskRoutingSettingsTests.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/mlx_runtime_ipc.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
  - `x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`
  - `x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
- DoD：
  - 新 schema 支持 `task_kind -> model_id`
  - 可选支持 `device_id + task_kind -> model_id`
  - schema 向后兼容现有 `routing_settings.json`
  - source trace 可区分 `hub_default / device_override / request_override / auto_selected`
- 落地：
  - `LocalTaskRoutingSettings` 新增 v2 schema：`hubDefaultModelIdByTaskKind / devicePreferredModelIdByTaskKind`，并保留 `preferredModelIdByTask` 作为 legacy alias
  - Hub `RoutingSettingsStorage` 现在能读写 v2，同时继续兼容 dict-only / `preferredModelIdByTask` 旧格式，不会把旧用户配置直接读崩
  - Node 侧 `mlx_runtime_ipc.js` 新增 `readTaskRoutingSettings(...) / resolveTaskRoutingBinding(...)`；`local_runtime_ipc.js` 暴露本地 runtime wrapper，供后续 `W3-08-B/C` 直接复用
  - `relflowhub_mlx_runtime.py` 改成解析 v2 routing store，并支持 `device_id` 维度的 binding；同时修掉 routing cache 跨 base-dir 复用的隐性错误
  - MLX file IPC request 现在可透传可选 `device_id`，runtime `start`/`no_model_routed` 事件开始显式带 `route_source`
  - source trace 统一收敛到 `request_override / device_override / hub_default / auto_selected`，不再把 request override 和 routing store 来源混成一个 `preferred_model`
- residual gap：
  - Hub 侧 routing store / UI 已具备 `Use For...` 与 per-device route 编辑，但 runtime 侧真正消费这些 binding 还要等 `LPR-W3-08-C`
  - embedding / ASR / vision / ocr 的具体调用入口还没有统一接入新的 routing resolver；这部分在 `LPR-W3-08-C`
  - 目前大多数 MLX 文本请求生产端还不会主动填写 `device_id`；schema 已就绪，但真实设备级绑定要等后续 UI / caller plumbing
- 验证：
  - `swift test --filter LocalTaskRoutingSettingsTests`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
  - `PYTHONPYCACHEPREFIX=/tmp python3 -m py_compile x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
  - `PYTHONPYCACHEPREFIX=/tmp python3 x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
- 证据：
  - `build/reports/lpr_w3_08_a_task_routing_schema_evidence.v1.json`

### 3.31 `LPR-W3-08-B` Hub `Use For...` Binding UI

- 目标：让用户在 Hub 里直接把模型绑定给具体用途，而不是手工记环境变量；其中 `text_to_speech / Voice` 作为一等 task kind，用来标记适合作为 `Supervisor voice` 的本地模型。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/LocalTaskRoutingCatalog.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
- 交付：
  - HubStore 从单纯的 `[task:model]` alias 升级成完整 `routingSettings` 持有者，并保留旧 alias 给已有 `assist/review/...` 文本流与 preview UI 继续使用
  - 新增 `LocalTaskRoutingCatalog`，统一 Hub 本地 task kind 的枚举与 label：`text_generate / embedding / speech_to_text / vision_understand / ocr`
  - `MainPanelView` 的本地模型行新增 `Use For...` 菜单，可直接把当前模型设为某个本地任务的 Hub default；同时显示该模型当前承担的 hub-default 任务摘要
  - `SettingsSheetView > Edit Paired Device` 新增 `Per-Device Local Task Routing` 区块，逐 task 展示 `Hub default / Device override / Effective / Source`
  - paired device route 编辑采用草稿态，只有点击 `Save` 才把 `routing_settings.json` 写回，避免用户在设备 sheet 中做一半时即时污染全局 binding
- DoD：
  - 模型卡片支持 `Use For...`
  - 至少支持 `Generate / Embedding / ASR / Voice / Vision / OCR`
  - paired terminal 视图可显示设备级 override
  - UI 清楚展示 routing source
- 验证：
  - `swift test --filter LocalTaskRoutingCatalogTests`
  - `swift test --filter LocalTaskRoutingSettingsTests`
  - `swift test --filter LocalModelRuntimeActionPlannerTests`
- residual gap：
  - `LPR-W3-08-B` 只负责 Hub side binding/edit UI；真正让 `embedding / speech_to_text / vision_understand / ocr` 请求在 Node/service path 里解析这些 binding，仍属于 `LPR-W3-08-C`
  - 当前 Hub Settings 里历史 `AI Routing` 文本框仍保留给旧 `assist/review/...` flow；新本地任务 UI 是增量接入，不是替换整套旧 routing surface
- 证据：
  - `build/reports/lpr_w3_08_b_use_for_binding_ui_evidence.v1.json`

### 3.32 `LPR-W3-08-C` Node / Runtime Local Task Resolution

- 目标：让所有本地任务都能按 routing store 解析目标模型，而不是散落在 env 和 fallback 逻辑里。
- 涉及路径：
  - `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_embeddings.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_embeddings.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_audio.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_audio.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_vision.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_vision.test.js`
- 交付：
  - `local_runtime_ipc.js` 新增共享 resolver `resolveLocalTaskModelRecord(...)`，把 routing store 解析、runtime model record 匹配、provider/task/local-path 兼容性检查集中到一处，避免 embedding / ASR / vision / ocr 各自复制“找第一个兼容模型”的逻辑
  - resolver 严格沿用 `LPR-W3-08-A` 的 source precedence：`request_override -> device_override -> hub_default -> auto_selected`
  - 当 binding 指向坏模型时改成 fail-closed，不再悄悄回退到另一个兼容模型；reason code 统一收敛到 `routed_model_not_registered / routed_model_not_local / routed_model_provider_mismatch / routed_model_task_mismatch / no_compatible_model_registered`
  - `local_embeddings.js`、`local_audio.js`、`local_vision.js` 全部改为通过共享 resolver 选模；其中 OCR 继续走 `local_vision.js` 的 task 分支，但同样受 routing store 约束
  - 本地任务返回结构现在带 `route_source / resolved_model_id`，失败路径还会带 `route_reason_code`，这样上层 audit 和后续 monitor 可以区分是“自动挑中”还是“显式 route 失效”
  - `services.js` 的 memory-route embedding audit snapshot 已接入这些字段，`memory.route.applied` 与 `ai.embed.local.*` 审计会显式记录 route trace
- DoD：
  - local embedding / ASR / vision / ocr 全部接入 routing resolution
  - request override 优先级高于 device override，高于 hub default
  - route miss 时给出 explainable deny
  - audit 记录 route source 与 resolved model id
- 验证：
  - `node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_embeddings.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_audio.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_vision.test.js`
- residual gap：
  - `services.js` 目前只有 embedding 这条高层 service path 真正在产出 route-aware audit；audio / vision / ocr 的 route trace 已在本地 task module 内可用，但对应的 service-level 接入还在后续 monitor/diagnostics 里补齐
  - 用户要在 Hub 里看见这些 route trace、loaded instance、fallback 与 last error 的聚合视图，还需要 `LPR-W3-07`
  - Hub 已在 `LPR-W3-06` 提供 quick bench，但 route trace 还没有直接并入 bench 结论页
- 证据：
  - `build/reports/lpr_w3_08_c_task_resolution_evidence.v1.json`

### 3.33 `LPR-W3-07-A` Runtime Monitor Snapshot v1

- 目标：冻结一份面向 UI/diagnostics 的 monitor snapshot，聚合 provider、active task、loaded instance 与 fallback 信息。
- 涉及路径：
  - `x-hub/python-runtime/python_service/providers/base.py`
  - `x-hub/python-runtime/python_service/providers/mlx_provider.py`
  - `x-hub/python-runtime/python_service/providers/transformers_provider.py`
  - `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
  - `x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
  - `x-hub/python-runtime/python_service/local_provider_scheduler.py`
  - `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
- 交付：
  - `ProviderHealth` 扩展出 `realTaskKinds / fallbackTaskKinds / unavailableTaskKinds`，runtime status 不再只能回答“provider 是否可用”，而是能表达“哪些 task 真实可跑，哪些只是 fallback 就绪”
  - `TransformersProvider.healthcheck(...)` 现在显式回传 real/fallback/unavailable task 集合；`MLXProvider` 则把 `text_generate` 标记成 real-ready，供 monitor snapshot 做准确聚合
  - `local_provider_scheduler.py` 的 telemetry 新增 `oldestWaiterStartedAt / oldestWaiterAgeMs`，让 queue 不只是个整数，而是能解释“已经等了多久”
  - `relflowhub_local_runtime.py` 新增 `build_runtime_monitor_snapshot(...)`，把 provider health、scheduler state、loaded instances、idle eviction 聚合成 `monitorSnapshot`
  - `ai_runtime_status.json` 现在在保留 legacy `mlxOk / importError / activeMemoryBytes / peakMemoryBytes` 兼容字段的同时，额外写入 `monitorSnapshot`；active task、queue、last error、fallback counter 都在这一层冻结成稳定 contract
  - `local_runtime_ipc.js` 读取 runtime status 后会继续做 snake_case 归一化，并在旧文件没有 `monitorSnapshot` 时自动合成 `monitor_snapshot`，保证 UI / diagnostics 后续接入不受状态文件版本漂移影响
- DoD：
  - snapshot 至少包含 `providers / active_tasks / loaded_instances / queue / last_errors / fallback_counters`
  - 结构兼容旧 `ai_runtime_status.json`
  - active task 可关联到 `request_id / model_id / instance_key`
  - memory / queue 字段无值时必须显式 `unknown` 或 `0`，不能假绿
- 验证：
  - `node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_embeddings.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_audio.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_vision.test.js`
  - `PYTHONPYCACHEPREFIX=/tmp python3 x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
- residual gap：
  - 当前 monitor snapshot 还只是 runtime / IPC contract；真正给用户看的 Hub 面板属于 `LPR-W3-07-B`
  - diagnostics bundle / operator summary 还没有开始消费这份 snapshot；属于 `LPR-W3-07-C`
  - quick bench 已在 `LPR-W3-06` 落地，但尚未把 monitor counter 自动折算成更细的 slowdown root-cause explanation
- 证据：
  - `build/reports/lpr_w3_07_a_runtime_monitor_snapshot_evidence.v1.json`

### 3.34 `LPR-W3-07-B` Hub Runtime Monitor View

- 目标：提供一块用户能看懂、且对排障有帮助的本地模型运行态 UI。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/AIRuntimeStatus.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
  - `x-hub/macos/RELFlowHub/Tests/RELFlowHubCoreTests/LocalProviderRuntimeSchemaTests.swift`
- 交付：
  - `AIRuntimeStatus.swift` 新增显式 `AIRuntimeMonitor*` model，Hub 不再靠原始 JSON 字典硬解 monitor snapshot
  - `AIRuntimeStatus` 新增 `monitorSnapshot` 与 `runtimeMonitorOperatorSummary(ttl:)`，后续 UI / diagnostics / copy action 可复用同一份 operator-readable contract
  - `AIRuntimeStatus` 顶层解码现在兼容 `monitorSnapshot` 与 `monitor_snapshot`，同时兼容 `runtime_version / mlx_ok / active_memory_bytes` 等 snake_case 形态，避免后续读取 Node 归一化快照时丢字段
  - `HubStore` 新增 `aiRuntimeStatusSnapshot`，沿用已有 runtime status 存储与轮询链路，不再另开 monitor fetch path
  - `SettingsSheetView` 新增 `Runtime Monitor` section：显示 provider metrics、queue、loaded instances、fallback、last errors、stale heartbeat 提示与 copy actions
  - `copyLocalProviderSummaryToClipboard(...)` 现在会附带 runtime monitor summary；operator 可直接拷走 summary / active tasks / loaded instances / last errors
  - active task / last error 列表改用枚举 identity，避免重复 `leaseId` 或重复 provider error 时出现 SwiftUI identity 冲突
- DoD：
  - Hub UI 至少显示 active tasks、loaded instances、queue wait、memory、fallback mode、last error
  - 重点字段支持复制
  - 视图对 provider 数量变化容错，不写死 `mlx/transformers` 两行
  - 无 active tasks 时仍能显示 warm/cold 与 readiness
- 验证：
  - `swift test --filter LocalProviderRuntimeSchemaTests`
  - `swift test --filter LocalModelRuntimeActionPlannerTests`
- residual gap：
  - diagnostics bundle / operator export 不在本 UI 子工单内；独立导出已由 `LPR-W3-07-C` 收口
  - Bench 已在 `LPR-W3-06` 落地，但 queue / fallback / memory monitor 还没有被进一步融合成更细粒度的 bench explanation
  - 当前 Runtime Monitor 还是只读视图；更进一步的 provider 级操作按钮不在本子工单范围
- 进展补记（2026-03-23）：
  - 已补正式 evidence 出口：`HubDiagnosticsBundleExporterTests` 可导出 `build/reports/w9_c1_provider_truth_surface_evidence.v1.json`，把 Runtime Monitor / Models Runtime / doctor-export 的 provider truth 一致性固化
  - 已在 `Settings -> Runtime Monitor` 与 `Models -> Runtime` 共用一套 `LocalRuntimeRepairSurfaceSummary`，把 `runtime stale / no provider ready / partial provider down` 收成统一 repair entry；当前仍不提供一键 restart，但用户已能看到一致的下一步和修复入口
  - 已补正式 evidence 出口：`LocalRuntimeRepairSurfaceSummaryTests` 可导出 `build/reports/w9_c4_runtime_repair_entry_evidence.v1.json`，把 shared repair surface 和 doctor 对齐结果一起固化
  - XT 侧已补共享的 `XTModelInventoryTruthPresentation`，把 Hub doctor / runtime monitor 真相接到 XT 的模型治理入口；对应 evidence 已落盘为 `build/reports/w9_c2_xt_local_provider_truth_evidence.v1.json`
- 证据：
  - `build/reports/lpr_w3_07_b_runtime_monitor_ui_evidence.v1.json`

### 3.35 `LPR-W3-07-C` Operator / Diagnostics Export

- 目标：让 monitor 信息进入 diagnostics bundle 与 operator summary，而不是只停留在 UI 上。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubDiagnosticsBundleExporter.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - `x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/HubDiagnosticsBundleExporterTests.swift`
- 交付：
  - diagnostics bundle 现在除了原有 `local_runtime_provider_summary.txt` 之外，额外导出 `local_runtime_monitor_summary.txt` 与 `local_runtime_monitor_snapshot.redacted.json`
  - `local_runtime_provider_summary.txt` 升级到 `xhub_local_runtime_provider_summary.v2`，在 provider/operator summary 之外附带 `runtime_monitor` 段，operator 不用再手动拼接两份文本
  - `local_runtime_monitor_summary.txt` 直接落 `runtimeMonitorOperatorSummary(ttl:)` 的关键 telemetry，便于 support / QA 快速判断 `why_slow / why_failed / why_cpu_fallback`
  - `local_runtime_monitor_snapshot.redacted.json` 用结构化 envelope 导出 monitor snapshot，保留 `runtime_alive / status_schema_version / monitor_summary / monitor_snapshot`
  - diagnostics redact 规则新增 `request_payload / payload / prompt / messages / input_path / file_path / image_path / audio_path / video_path` 等敏感键，避免分享 bundle 时泄出输入内容或输入文件路径
  - issue snippet copy 现在会附带 `runtime_monitor` 段，提交 issue 或转 support 时不再只剩 provider summary
- DoD：
  - diagnostics bundle 导出 runtime monitor snapshot
  - operator summary 可复制关键字段
  - redact 规则对 request payload / input path 生效
  - 证据包能解释 `why_slow / why_failed / why_cpu_fallback`
- 验证：
  - `swift test --filter HubDiagnosticsBundleExporterTests`
  - `swift test --filter LocalProviderRuntimeSchemaTests`
  - `swift test --filter LocalModelRuntimeActionPlannerTests`
- residual gap：
  - diagnostics bundle 当前覆盖的是 builder/export 层单测；尚未有一条 UI 驱动的 zip 文件清单 smoke
  - Runtime Monitor 导出仍是只读证据，不提供一键 restart / unload / evict 控制动作
  - Bench 已在 `LPR-W3-06` 落地，但 monitor telemetry 还没有自动并入 exported bench explanation
- 证据：
  - `build/reports/lpr_w3_07_c_monitor_export_evidence.v1.json`

### 3.36 `LPR-W3-06-A` Bench Schema v2 / Storage Migration

- 目标：把 `models_bench.json` 从 MLX 文本测速结构升级成 task-aware schema。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelBench.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/ModelStore.swift`
- DoD：
  - bench 结果按 `model_id + task_kind + load_profile_hash + fixture_profile` 可区分
  - schema 至少包含 `latency / throughput / peak_memory / fallback_mode / verdict / notes`
  - 旧 bench 文件可读，不崩
  - UI 若读取到 legacy bench，明确标记 `legacy_text_bench`
- 落地：
  - `ModelBenchResult` / `ModelsBenchSnapshot` 已升级为 schema v2，bench identity 固定为 `model_id + task_kind + load_profile_hash + fixture_profile`
  - `ModelBenchStorage` 新增 `save / load / upsert`，统一读写 `models_bench.json`，不再只依赖 legacy append 风格
  - legacy MLX 文本 bench 仍可被 decode，并在 Swift UI 中显式标记为 `legacy`
  - `ModelStore` 现已同时保留完整 bench snapshot 与“每个模型最新一条结果”摘要，模型卡片和 Bench sheet 可复用同一份存储
- residual gap：
  - Bench summary 目前仍按“每模型最新结果”折叠展示；跨 task 的完整历史对比尚未做成独立视图
  - Bench 结论还未与 runtime monitor 的 queue / fallback counter 聚合解释；这部分属于后续 bench-monitor 联动增强
- 验证：
  - `swift test --filter LocalProviderRuntimeSchemaTests`
  - `python3 x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
- 证据：
  - `build/reports/lpr_w3_06_a_bench_schema_v2_evidence.v1.json`

### 3.37 `LPR-W3-06-B` Runtime Bench Adapters

- 目标：为 text/embed/asr/vision/ocr 提供统一 quick bench 执行器。
- 涉及路径：
  - `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
  - `x-hub/python-runtime/python_service/providers/mlx_provider.py`
  - `x-hub/python-runtime/python_service/providers/transformers_provider.py`
  - `x-hub/grpc-server/hub_grpc_server/src/`
- DoD：
  - text bench 继续支持 MLX 真跑
  - embedding / ASR / vision / ocr bench 至少能输出 `cold_start / single_run_latency / batch_or_fixture_profile`
  - fallback bench 明确标记 `fallback_only`
  - bench 执行不污染常规 request path 的审计/配额语义
- 落地：
  - `LocalProvider` 基类新增 `run_bench()` contract，`MLXProvider` 提供 legacy 文本 bench 兼容输出，`TransformersProvider` 提供 task-aware quick bench
  - `relflowhub_local_runtime.py` 新增 `run_local_bench(...)` 与 `run-local-bench` CLI，bench 可绕过长期 runtime loop 对非 MLX 模型直接执行
  - `TransformersProvider` 已支持 `embedding / speech_to_text / vision_understand / ocr` quick bench，并输出 `latency / throughput / peak_memory / fallback_mode / verdict / reasonCode`
  - `local_runtime_ipc.js` 新增 `runLocalBench(...)` 与 bench payload 归一化逻辑，Node 侧不再只理解 MLX `tok/s`
- residual gap：
  - 非 MLX quick bench 当前仍走 one-shot subprocess，不提供 resident worker 级持续 warm state
  - quick bench 是产品化能力探针，不是长压测替代；大上下文和批量真实业务数据仍需额外评估
- 验证：
  - `python3 x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
- 证据：
  - `build/reports/lpr_w3_06_b_runtime_bench_adapters_evidence.v1.json`

### 3.38 `LPR-W3-06-C` Hub Quick Bench UX / Recommendation Summary

- 目标：让 Bench 对用户表达“这个模型适不适合我”，而不是只显示原始数字。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
- DoD：
  - 模型卡片显示最新 bench 摘要
  - 点击 Bench 可选择 task / fixture profile
  - UI 输出 verdict：如 `Fast / Balanced / Heavy / Preview only / CPU fallback`
  - bench failure 不得只显示笼统红字，要显示 reason code
- 落地：
  - `MainPanelView` 的模型卡片现在显示最新 bench 摘要，包含 task、verdict、latency、throughput、fallback 和 legacy 标记
  - `QuickBenchSheet` 已支持按 task kind 与 fixture profile 运行 quick bench，非 MLX 本地模型不再被 UI 直接拦截
  - `ModelStore.runBench(...)` 现已同时支持 legacy MLX path 和 provider-aware subprocess path，并把失败结果与 reason code 持久化到 bench store
  - `SettingsSheetView` 新增 quick bench verdict legend，给 operator 一份统一的 `Fast / Balanced / Heavy / Preview only / CPU fallback` 解释
- residual gap：
  - 当前 UI 仍以 quick summary 为主，没有多次 bench 的趋势图或任务矩阵对比面板
  - verdict 还没有把 runtime monitor 的 queue / loaded instance telemetry 进一步折算成更强解释性建议
- 验证：
  - `swift test --filter LocalProviderRuntimeSchemaTests`
  - `swift test --filter LocalModelRuntimeActionPlannerTests`
- 证据：
  - `build/reports/lpr_w3_06_c_quick_bench_ui_evidence.v1.json`

### 3.39 `LPR-W3-06-D` Bench Fixture Pack / Require-Real Hook

- 目标：把 quick bench 的样本、fixture profile 与 require-real 门禁接起来，避免 bench 沦为一次性 demo。
- 涉及路径：
  - `scripts/`
  - `docs/memory-new/`
  - `build/reports/`
- DoD：
  - 至少提供 `text_short / embed_small_docs / asr_short_clip / vision_single_image / ocr_dense_doc` fixture profile
  - fixture profile 可被本地 quick bench 与 require-real 共用
  - 缺 fixture 时 fail-closed，不 silent skip
  - 证据生成脚本产物稳定
- 落地：
  - Swift 资源包新增 `bench_fixture_pack.v1.json`，并通过 `LocalBenchFixtureCatalog` 暴露 task-aware fixture 目录给 Hub UI
  - `TransformersProvider` 对 ASR / vision / OCR bench 采用 generator-backed WAV/PNG materialization，不在仓库中提交大体积二进制样本
  - fixture pack 的 schema 版本、fixture ID、task mapping 与 fail-closed reason code 已冻结在 `docs/memory-new/xhub-local-bench-fixture-pack-v1.md`
  - 新增 `scripts/generate_lpr_w3_06_d_bench_fixture_pack_evidence.js`，输出稳定的 fixture-pack evidence 产物
- residual gap：
  - 当前 require-real hook 冻结的是 shared fixture ID contract；真正的 capture bundle 生产线仍可在后续 require-real gate 中继续扩展
  - 生成型 fixture 适合 quick bench 与离线回归，不等同于完整真实媒体语料库
- 验证：
  - `node scripts/generate_lpr_w3_06_d_bench_fixture_pack_evidence.js`
  - `python3 x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
  - `swift test --filter LocalProviderRuntimeSchemaTests`
- 证据：
  - `build/reports/lpr_w3_06_d_bench_fixture_pack_evidence.v1.json`

### 3.40 `LPR-W3-05-D` Resident Daemon Proxy / Warmable Lifecycle Activation

- 目标：把 `warmable` provider 从“UI 已知道但必须 fail-closed”推进到“常驻 runtime 可真正接管 warmup / unload / bench / task 执行”的 resident control plane。
- 涉及路径：
  - `x-hub/python-runtime/python_service/providers/transformers_provider.py`
  - `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
  - `x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`
  - `x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/ModelStore.swift`
  - `x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/LocalModelRuntimeActionPlannerTests.swift`
- DoD：
  - resident runtime heartbeat 新增 `localCommandIpcVersion`，one-shot CLI 能识别新鲜 daemon 并优先代理
  - `relflowhub_mlx_runtime.py` 常驻 loop 可消费 provider-aware `run_local_task / run_local_bench / manage_local_model` 命令
  - resident-owned Transformers provider 明确上报 `residencyScope=runtime_process`
  - Hub planner 对 `runtime_process` + `warmable` provider 放通 `Warmup / Unload`
  - daemon 不存在、过旧或心跳过期时，命令自动回退到 direct one-shot，保持兼容
- 落地：
  - `TransformersProvider` 新增 resident runtime mode，并在常驻 registry 中把 residency scope 提升为 `runtime_process`
  - `relflowhub_local_runtime.py` 新增 `xhub.local_runtime_command_ipc.v1` marker、file-based command proxy 与 fresh-heartbeat 检测；`run-local-task / run-local-bench / manage-local-model` 优先代理到常驻 daemon
  - `relflowhub_mlx_runtime.py` 在原有 resident loop 内接入 provider-aware command scanner / response writer，并把 provider loaded state 同步回 `models_state.json`
  - `relflowhub_mlx_runtime.py` 启动改为先走子进程安全探测 MLX；即便 `mlx_lm / libmlx` 在当前环境硬崩，resident daemon 也会继续存活，并把 MLX 标成 `import_error`
  - `ModelStore.swift` 的 planner / enqueue 路径已接受 provider lifecycle command；`runtime_process` warmable provider 不再被 UI 无条件阻断
  - compat tests 新增 file IPC round-trip 与 `main(...)` 优先走 daemon proxy 的验证
  - 已完成一轮真实目录 smoke：使用 `/Users/andrew.xie/Documents/AX/Local Model/GLM-4.6V-Flash-MLX-4bit` 注册为 `transformers / vision_understand`，daemon 在 `mlx_probe_failed` 条件下仍可存活，`run-local-bench` 经 daemon proxy 返回 `fallback_only / Preview only`，`warmup_local_model` 对视觉模型继续 fail-closed
- residual gap：
  - 这一工单验证的是 contract、proxy 与 planner；仍需要用真实本地模型目录做一轮 Hub UI require-real smoke，才能完成 `LPR-G6`
  - `process_local` provider 仍保持 `On-Demand`，不应因为 resident daemon 已存在就误报为可 warmup
  - 当前实机 smoke 只覆盖了视觉 preview fallback；真正的 warmable resident require-real 还缺一套本地 `embedding` 或 `speech_to_text` 模型，以及本机可用的 `torch`
- 验证：
  - `python3 x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
  - `swift test --filter LocalProviderRuntimeSchemaTests`
  - `swift test --filter LocalModelRuntimeActionPlannerTests`
  - `REL_FLOW_HUB_BASE_DIR=/tmp/xhub_lpr_real_glm_8T5FGQ XHUB_TRANSFORMERS_ALLOW_VISION_FALLBACK=1 python3 x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`
  - `REL_FLOW_HUB_BASE_DIR=/tmp/xhub_lpr_real_glm_8T5FGQ XHUB_TRANSFORMERS_ALLOW_VISION_FALLBACK=1 python3 x-hub/python-runtime/python_service/relflowhub_local_runtime.py manage-local-model '{...vision_understand...}'`
  - `REL_FLOW_HUB_BASE_DIR=/tmp/xhub_lpr_real_glm_8T5FGQ XHUB_TRANSFORMERS_ALLOW_VISION_FALLBACK=1 python3 x-hub/python-runtime/python_service/relflowhub_local_runtime.py run-local-bench '{...vision_single_image...}'`
- 证据：
  - `build/reports/lpr_w3_05_d_resident_runtime_proxy_evidence.v1.json`

### 3.41 `LPR-W4-01-A` Provider Pack Manifest / Installed Registry

- 状态：
  - 2026-03-16 已完成 contract 落地与三端回归
  - Python runtime 已输出 `providerPacks[]` 与 provider-level `packId / packEngine / packVersion / packInstalled / packEnabled / packState / packReasonCode`
  - Node IPC 已统一归一化 pack inventory 并回填 provider pack truth
  - Swift schema 已新增 `AIRuntimeProviderPackStatus` / `AIRuntimeProviderPackRuntimeRequirements`，支持 pack inventory decode 与 legacy synthesize/backfill
  - 同日已补上 file-backed `provider_pack_registry.json` override；`disabled / not_installed` pack 会让 provider status 与 task/bench/warmup path 一起 fail-closed
  - diagnostics/operator summary 已开始消费 pack inventory；bundle 会额外导出 `provider_pack_registry.redacted.json`
- 本轮证据：
  - `node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
  - `PYTHONPYCACHEPREFIX=/tmp python3 x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
  - `swift test --filter LocalProviderRuntimeSchemaTests`
  - `swift test --filter HubDiagnosticsBundleExporterTests`

- 目标：把本地 provider 从“代码里写死的 provider 名称”升级成可盘点、可诊断、可版本化的 installed pack inventory。
- 涉及路径：
  - `docs/xhub-local-provider-runtime-and-transformers-integration-v1.md`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/LocalProviderPack.swift`（new）
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/AIRuntimeStatus.swift`
  - `x-hub/python-runtime/python_service/provider_pack_registry.py`（new）
  - `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
  - `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js`
- DoD：
  - provider pack manifest schema 冻结：`provider_id / engine / version / supported_formats / supported_domains / runtime_requirements / min_hub_version`
  - Hub / runtime / diagnostics 能看到同一份 installed pack truth
  - `mlx`、`transformers` 先迁入 pack registry
  - pack 缺失、版本不兼容、pack disabled 都 machine-readable
- 落地：
  - 新增 installed pack registry store，并把 provider string 升级成 pack-aware metadata
  - runtime status 新增 `providerPacks[] / packState / packReasonCode`
  - `local_runtime_ipc.js` 统一归一化 pack inventory，避免 Swift 直接读底层 JSON 细节
  - Swift schema 新增 pack badge / install-state decode，供 Add Model、Monitor、Diagnostics 共用
- residual gap：
  - 本子工单只解决 pack inventory，不解决 provider-owned runtime；后者属于 `LPR-W4-02-A`
  - 只有 pack 被安装不代表模型一定可 load；具体 load config 与 instance truth 属于 `LPR-W4-03-A`
- 验证：
  - `swift test --filter LocalProviderRuntimeSchemaTests`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
  - `PYTHONPYCACHEPREFIX=/tmp python3 x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
- 证据：
  - `build/reports/lpr_w4_01_a_provider_pack_registry_evidence.v1.json`

### 3.42 `LPR-W4-02-A` Provider-owned Runtime Bundle Resolution

- 目标：减少对用户系统 Python / 全局依赖的隐式耦合，让每个 provider 能声明自己的 runtime bundle 与 fallback 路径。
- 涉及路径：
  - `x-hub/python-runtime/python_service/providers/base.py`
  - `x-hub/python-runtime/python_service/provider_runtime_resolver.py`（new）
  - `x-hub/python-runtime/python_service/providers/mlx_provider.py`
  - `x-hub/python-runtime/python_service/providers/transformers_provider.py`
  - `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/AIRuntimeStatus.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
- DoD：
  - provider 启动时能明确区分 `pack_runtime_ready / user_runtime_fallback / runtime_missing`
  - doctor / runtime monitor / diagnostics 能解释 provider 实际绑定了哪套 runtime
  - 失败原因可以区分 `missing_pack / missing_runtime / import_error / native_dependency_error`
  - 不再把“某个系统 Python 包是否存在”当成唯一产品路径
- 落地：
  - 新增 runtime requirement contract：`python / wheel_bundle / helper_binary / native_dylib`
  - provider 初始化统一先走 `provider_runtime_resolver`
  - runtime status 与 operator summary 暴露 `runtimeSource / runtimeVersion / fallbackUsed`
  - Settings / Diagnostics 显示可复制的 install hint，而不是笼统 import failure
- 2026-03-16 首轮落地：
  - 新增 `provider_runtime_resolver.py`，把 provider runtime 解析成 `pack_runtime_ready / user_runtime_fallback / runtime_missing`
  - `mlx` 改成 safe probe，不在 resolver 里直接 import `mlx`，避免 Metal 初始化崩溃
  - `transformers` runtime status 现在会把 `runtimeSource / runtimeSourcePath / runtimeResolutionState / runtimeReasonCode / fallbackUsed / runtimeHint` 透传到 Python/Node/Swift schema
  - operator summary、runtime monitor、diagnostics bundle、Settings provider hint 已消费这批字段
  - tests 已覆盖 `user_runtime_fallback` 与 `hub_py_deps -> pack_runtime_ready` 两条主路径
- 2026-03-16 二轮补齐：
  - `TransformersProvider` 的 `run_task / warmup_model / run_bench` 失败路径现在统一携带 runtime envelope，不再把 `runtime_missing` 折叠成笼统 `unsupported_task` 或裸 `missing_module:*`
  - warmup 失败时保留 `taskKinds`，bench 失败时会把 `runtimeSource / runtimeResolutionState / runtimeReasonCode / runtimeHint / missing requirements` 一并回传
  - `models_bench.json`、Node `local_runtime_ipc.js` 与 Swift `ModelBenchResult` 已新增 bench runtime 字段透传，bench 历史记录不再丢掉 provider runtime 解释
  - tests 补到 task/warmup/bench runtime-missing 合约，并验证 Python/Node/Swift 三段 schema 兼容
- residual gap：
  - 这一步只把运行时来源显式化，不负责新 provider pack 的真实载入；`mlx_vlm` 与 `llama.cpp` 仍属于后续子工单
- 验证：
  - `swift test --filter LocalProviderRuntimeSchemaTests`
  - `swift test --filter HubDiagnosticsBundleExporterTests`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
  - `PYTHONPYCACHEPREFIX=/tmp python3 x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
- 证据：
  - `build/reports/lpr_w4_02_a_runtime_bundle_resolution_evidence.v1.json`

### 3.43 `LPR-W4-03-A` Typed Load Config / Loaded Instance Info v1

- 目标：把当前 `defaultLoadProfile + effectiveContextLength + instanceKey` 升级成正式 typed load config，并把模型静态信息与实例运行态彻底分层。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelModels.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/AIRuntimeStatus.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
  - `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
  - `x-hub/python-runtime/python_service/local_provider_scheduler.py`
  - `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js`
- DoD：
  - `load_config.v1` 至少支持 `context_length / ttl / parallel / gpu_offload / identifier / vision.image_max_dimension`
  - `LoadedInstanceInfo` 至少支持 `current_context_length / max_context_length / load_config_hash / residency / ttl / progress / last_used_at`
  - UI 可明确区分 `max_context_length`、`default_context_length`、`effective_context_length`
  - scheduler / bench / monitor / warmup 共享同一份 `load_config_hash`
- 落地：
  - Swift schema 增加 `LoadConfigV1` 与 `LoadedModelInstanceInfo`
  - runtime status 写入 typed load config 与 loaded-instance envelope，不再只靠散落字段
  - Node 归一化层统一 snake_case / camelCase，避免后续 UI 与 Python 各讲一套
  - `HubStore` 生成 operator summary 时直接引用 load-config source 与 instance info
- residual gap：
  - typed load config 就绪后，普通用户导入流程仍需收口到 auto-detect；属于 `LPR-W4-04-A`
  - loaded instances 的集中操作面板属于 `LPR-W4-05-A`
- 验证：
  - `swift test --filter LocalProviderRuntimeSchemaTests`
  - `swift test --filter LocalModelRuntimeActionPlannerTests`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
  - `PYTHONPYCACHEPREFIX=/tmp python3 x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
- 证据：
  - `build/reports/lpr_w4_03_a_typed_load_config_evidence.v1.json`

### 3.44 `LPR-W4-04-A` Add Model Auto-detect / Manual Picker 收口

- 目标：把 Add Model 正常路径改成“扫目录 -> 自动判 provider / task / modality / pack readiness”，移除普通用户的 backend/role 前置操作。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/AddModelSheet.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelModels.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/LocalProviderPack.swift`
  - `x-hub/python-runtime/python_service/provider_pack_registry.py`
  - `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js`
- DoD：
  - 普通用户导入模型时不再必须先选 `MLX / Transformers / Role`
  - Hub 能自动探测格式、provider candidate、task kinds、modalities、runtime pack readiness
  - 推断失败时 fail-closed，并直接给出 `missing_pack / runtime_missing / missing_processor / unsupported_format`
  - backend/provider override 仅保留在 advanced/debug 面板
- 落地：
  - `AddModelSheet.swift` 改成目录扫描优先，再显示 capability summary 与阻断原因
  - `Role` picker 从普通导入流移除；只保留 debug override
  - provider pack inventory 直接进入导入结果页，用户能马上看见“模型可识别，但当前 pack/runtime 不可用”
- 2026-03-16 当前进度：
  - Add Model 已默认走 backend auto-detect，不再要求普通用户先选 `Role`
  - 导入页新增 provider pack / runtime readiness summary：可直接显示 `Pack: ready|disabled|not installed` 与 `Runtime: ready|user Python|missing`
  - 导入页 warning 现在会合并 `importWarning + providerHint`，并在可自动恢复时提示 “Hub can auto-restart AI Runtime on first load/warmup”
  - 这一步仍是“导入前解释清楚”，还没把 `missing_pack / runtime_missing` 变成统一 fail-closed gate；那部分留在本子工单后续收口
- residual gap：
  - 导入成功后的 capability-first 库视图与 filters 属于 `LPR-W4-04-B`
- 验证：
  - `swift test --filter LocalProviderRuntimeSchemaTests`
  - `swift test --filter LocalModelRuntimeActionPlannerTests`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
- 证据：
  - `build/reports/lpr_w4_04_a_add_model_autodetect_evidence.v1.json`

### 3.45 `LPR-W4-04-B` Capability-first Library Filters / Model Cards

- 目标：让模型库按“能做什么、能不能 load、当前是否已加载”来组织，而不是先暴露 backend 细节。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/ModelStore.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelLibraryFilterState.swift`（new）
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/AIRuntimeStatus.swift`
- DoD：
  - 模型列表支持 `Loaded / Text / Embedding / Audio / Vision / OCR / Preview` 过滤
  - 模型卡片显示 capability、provider pack state、runtime bundle state、loaded state、preview / fallback badge
  - 不可用原因直接显示在模型卡片或 drawer 中，而不是藏在诊断页
- 落地：
  - 新增 capability chips 与 loaded-state filter
  - 模型卡片摘要从“backend/quant”升级为“用途 + 当前可用性 + 阻断原因”
  - preview / fallback-only / pack-missing 统一用 machine-readable state 驱动 UI
- residual gap：
  - 集中的 loaded instances 操作台仍需要 `LPR-W4-05-A`
- 验证：
  - `swift test --filter LocalProviderRuntimeSchemaTests`
  - `swift test --filter LocalModelRuntimeActionPlannerTests`
- 证据：
  - `build/reports/lpr_w4_04_b_model_library_capability_ui_evidence.v1.json`

### 3.46 `LPR-W4-05-A` Loaded Models Console / Runtime Operations

- 目标：把“磁盘上有哪些模型”与“内存里当前有哪些实例”彻底分开，并给用户一个集中的 runtime operations 面板。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/AIRuntimeStatus.swift`
  - `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
  - `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js`
- DoD：
  - Loaded Instances panel 可显示 `instance_key / provider / model_id / source_device / load_config / ttl / last_used / queue_state`
  - 支持 `warmup / unload / evict / copy diagnostics`
  - route trace、fallback、pack/runtime source 能挂到实例解释里
  - 同模型不同 load profile 的多个实例不会被 UI 混成一条
- 落地：
  - `AIRuntimeStatus` 新增 loaded-instance-centric operator models
  - `HubStore` 提供 runtime operations data source 与 copy/export action
  - runtime / Node IPC 暴露 per-instance progress、ttl、last_used、eviction reason
- residual gap：
  - Bench 结果与 monitor counters 的融合属于 `LPR-W4-06-A`
- 验证：
  - `swift test --filter LocalProviderRuntimeSchemaTests`
  - `swift test --filter LocalModelRuntimeActionPlannerTests`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
- 证据：
  - `build/reports/lpr_w4_05_a_loaded_models_console_evidence.v1.json`

### 3.47 `LPR-W4-06-A` Bench + Monitor Fusion / Capability Card

- 目标：把 quick bench、runtime monitor、load config 与 loaded instance truth 融成一张用户可理解的能力卡片。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelBench.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubDiagnosticsBundleExporter.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/AIRuntimeStatus.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js`
- DoD：
  - Bench 结果可融合 `queue wait / fallback / loaded instance / load config / runtime pressure`
  - UI 生成 `Best for / Avoid for / Needs warmup / CPU fallback / Preview only` capability card
  - 导出报告包含 `task_kind + fixture + load_profile + runtime state + reason_code`
  - 失败能区分 `unsupported_task / missing_pack / runtime_missing / fallback_only / processor_init_failed`
- 落地：
  - bench store 增加 fused explanation snapshot
  - diagnostics bundle / issue snippet 直接带 capability card summary
  - MainPanel / Bench sheet 共用同一份 fused schema，不再一处看 bench、一处看 monitor
- residual gap：
  - 真实 `mlx_vlm` 与 `llama.cpp` provider 的 capability card 质量要等它们接入后再 require-real 校验
- 验证：
  - `swift test --filter LocalProviderRuntimeSchemaTests`
  - `swift test --filter HubDiagnosticsBundleExporterTests`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
- 证据：
  - `build/reports/lpr_w4_06_a_bench_monitor_fusion_evidence.v1.json`

### 3.48 `LPR-W4-07-A` `mlx_vlm` Provider Pack / Model Detection

- 目标：新增独立的 `mlx_vlm` provider pack，让 `GLM-4.6V-Flash-MLX-4bit` 这类模型不再被误判为 transformers fallback 或 unsupported。
- 涉及路径：
  - `x-hub/python-runtime/python_service/providers/mlx_vlm_provider.py`（new）
  - `x-hub/python-runtime/python_service/provider_pack_registry.py`
  - `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
  - `x-hub/grpc-server/hub_grpc_server/src/local_vision.js`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/AddModelSheet.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift`
- DoD：
  - Add Model 能把符合特征的 MLX 视觉模型映射到 `mlx_vlm`
  - `vision_understand / ocr` 能走 `mlx_vlm` provider，而不是藏在 `transformers` preview fallback
  - provider pack 能暴露 `processor / prompt format / image limits / residency` truth
  - Bench / Monitor / Audit 继续按同一主链工作
- 落地：
  - 新增 `mlx_vlm` provider contract 与 model detection 规则
  - image prompt / processor 初始化失败时明确 reason code，不退回 text-only 伪成功
  - provider pack metadata 暴露 model family / supported tasks / image guard
- residual gap：
  - 真机 require-real 验证与产品退出标准属于 `LPR-W4-07-B`
- 验证：
  - `node x-hub/grpc-server/hub_grpc_server/src/local_vision.test.js`
  - `PYTHONPYCACHEPREFIX=/tmp python3 x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
- 证据：
  - `build/reports/lpr_w4_07_a_mlx_vlm_provider_pack_evidence.v1.json`

### 3.49 `LPR-W4-07-B` MLX Vision Require-Real（`GLM-4.6V-Flash-MLX-4bit`）

- 目标：把“这类本地视觉模型真的能 loaded 并跑能力测试”收口成 require-real 证据，而不是继续停在 preview/fallback。
- 涉及路径：
  - `docs/memory-new/README-local-provider-runtime-productization-v1.md`
  - `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
  - `scripts/`
  - `build/reports/`
- DoD：
  - 至少一类真实 MLX 视觉模型完成 `add -> load -> route -> bench -> monitor`
  - require-real 证据能记录模型探测、warmup/load、vision fixture、bench 结论、monitor snapshot
  - 若因 pack/runtime 缺失失败，证据必须给出精确阻断层级，而不是 `unsupported_task`
- 落地：
  - 新增 MLX-VLM require-real runbook 与 evidence generator
  - quick bench fixture 与 monitor snapshot 共用一套 evidence envelope
  - operator summary 能直接回答“为什么这个视觉模型不可用 / 是否只是缺 pack / 是否已降级到 fallback”
- residual gap：
  - 只完成 MLX 视觉闭环，不覆盖 GGUF；后者属于 `LPR-W4-08-B`
- 验证：
  - `node scripts/generate_lpr_w4_07_b_mlx_vlm_require_real_evidence.js`
- 证据：
  - `build/reports/lpr_w4_07_b_mlx_vlm_require_real_evidence.v1.json`

### 3.50 `LPR-W4-08-A` GGUF Detection / `llama.cpp` Provider Pack

- 目标：给 Hub 增加第二条通用本地主链，覆盖 GGUF / `llama.cpp` 生态。
- 当前状态（`2026-03-25`）：
  - 已完成 `.gguf -> llama.cpp` 导入识别、metadata heuristic、显式 `runtimeProviderID` 映射
  - 已补 Python 内建 `llama.cpp` provider pack manifest 与 helper-backed provider；`text_generate` / `embedding` 现走现有 helper bridge，runtime status / provider pack truth 已从 `preview` 升级为 `installed`
  - Swift 侧已补 auto-managed helper pack、provider guidance，并移除 `llama.cpp` 的静态 compatibility block；valid GGUF text / embedding bench 不再被 UI 预先阻断
  - 当前剩余缺口主要是 `LPR-W4-08-B` 的真机 require-real / bench / monitor smoke，而不是 provider wiring 本身
- 涉及路径：
  - `x-hub/python-runtime/python_service/providers/llama_cpp_provider.py`（new）
  - `x-hub/python-runtime/python_service/provider_pack_registry.py`
  - `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/AddModelSheet.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js`
- DoD：
  - Add Model 能识别 `.gguf` 并自动映射到 `llama.cpp` provider pack
  - 至少支持 text / embedding；vision 仅在模型声明支持时 preview
  - 量化不兼容、缺 pack、缺 runtime、模型能力不匹配都 fail-closed
  - GGUF 模型不再需要伪装成 `MLX` 或 `Transformers`
- 落地：
  - 新增 GGUF metadata extractor 与 provider mapping
  - `llama.cpp` provider pack 走与 `mlx` / `transformers` 相同的 pack/runtime/load-config contract
  - Node / Swift 端用 capability metadata 驱动 UI，不用针对 GGUF 写死特判
- residual gap：
  - 真机 require-real 与迁移出口属于 `LPR-W4-08-B` / `LPR-W4-09-A`
- 本轮验证：
  - `python3 x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py` 通过
  - `bash -lc 'TMPDIR=/tmp SWIFTPM_MODULECACHE_OVERRIDE=/tmp/relflowhub-module-cache CLANG_MODULE_CACHE_PATH=/tmp/relflowhub-clang-module-cache swift test --package-path /Users/andrew.xie/Documents/AX/x-hub-system/x-hub/macos/RELFlowHub --filter "Local(ModelRuntimeCompatibilityPolicyTests|ModelBenchCapabilityPolicyTests|ProviderPackRegistryTests|RuntimeProviderGuidanceTests)"'` 通过
  - `node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js` 通过
- 验证：
  - `PYTHONPYCACHEPREFIX=/tmp python3 x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
  - `bash -lc 'TMPDIR=/tmp SWIFTPM_MODULECACHE_OVERRIDE=/tmp/relflowhub-module-cache CLANG_MODULE_CACHE_PATH=/tmp/relflowhub-clang-module-cache swift test --package-path /Users/andrew.xie/Documents/AX/x-hub-system/x-hub/macos/RELFlowHub --filter "Local(ModelRuntimeCompatibilityPolicyTests|ModelBenchCapabilityPolicyTests|ProviderPackRegistryTests|RuntimeProviderGuidanceTests)"'`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
- 证据：
  - `build/reports/lpr_w4_08_a_llama_cpp_provider_pack_evidence.v1.json`
  - `build/reports/lpr_w4_08_a2_llama_cpp_helper_runtime_truth_evidence.v1.json`

### 3.51 `LPR-W4-08-B` GGUF Require-Real / Bench / Monitor Smoke

- 目标：证明 GGUF 模型能完成完整的 Hub 产品闭环，而不是只停在 import success。
- `2026-03-26` closure status：
  - `scripts/generate_lpr_w4_08_b_gguf_require_real_evidence.js` 已落地并生成 `build/reports/lpr_w4_08_b_gguf_require_real_evidence.v1.json`
  - 真机证据确认 `XHub local-runtime -> LM Studio helper -> /v1/embeddings` 成功，真实 GGUF embedding 返回 `vectorCount=1`、`dims=768`
  - `ai_runtime_status.json` 与 `monitorSnapshot.providers[].loadedInstanceCount` 对同一条 `llama.cpp` loaded-instance truth 口径一致
- 涉及路径：
  - `scripts/`
  - `build/reports/`
  - `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
- DoD：
  - 至少一类真实 GGUF 模型完成 `add -> load -> route -> bench -> monitor`
  - require-real 证据能区分 `pack ready but model unsupported` 与 `runtime missing`
  - Bench / Monitor / Capability card 都能读取到同一份 loaded-instance truth
- 落地：
  - 新增 GGUF smoke runbook、fixture 选择与证据脚本
  - diagnostics bundle / operator summary 能直接带 GGUF provider 诊断信息
- residual gap：
  - 最终迁移与 release exit 仍属于 `LPR-W4-09-A`
- 验证：
  - `node scripts/generate_lpr_w4_08_b_gguf_require_real_evidence.js`
- 证据：
  - `build/reports/lpr_w4_08_b_gguf_require_real_evidence.v1.json`

### 3.52 `LPR-W4-09-A` Migration / Product Exit / Operator Runbook

- 目标：把新旧本地模型产品面收口到同一条 operator-ready 退出标准，避免升级后 schema 漂移或诊断不可用。
- `2026-03-26` checkpoint：
  - `scripts/generate_lpr_w4_09_a_product_exit_matrix.js` 与 `scripts/generate_lpr_w4_09_a_product_exit_matrix.test.js` 已落地
  - `2026-03-27` 已补 `scripts/generate_lpr_w4_09_a_mlx_text_require_real_evidence.js` 与 `scripts/generate_lpr_w4_09_a_mlx_text_require_real_evidence.test.js`，并生成 `build/reports/lpr_w4_09_a_mlx_text_require_real_evidence.v1.json`
  - `build/reports/lpr_w4_09_a_product_exit_evidence.v1.json` 当前明确 fail-closed：`mlx_text / mlx_vlm / gguf` 三个 cell 已绿，只剩 `transformers_embed_asr` 缺 release-facing require-real artifact
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelModels.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelBench.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
  - `docs/memory-new/README-local-provider-runtime-productization-v1.md`
  - `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
  - `scripts/`
- DoD：
  - 旧 catalog / old bench / old runtime settings 能迁移到新 schema
  - operator runbook 可解释 `missing_pack / runtime_missing / provider_mismatch / unsupported_task / fallback_only`
  - real-machine matrix 覆盖 MLX 文本、MLX 视觉、Transformers embed+ASR、GGUF
  - release gate 与 diagnostics 出口对齐
- 落地：
  - 新增 migration checker / compatibility report
  - 旧 bench 结果与旧 `contextLength` 字段仍可被新 UI 兼容显示
  - README / work-orders / runbook 对齐 product exit 口径
- residual gap：
  - 只有在 `W4-07-B` 与 `W4-08-B` require-real 都落地后，本子工单才能真正确认闭环
- 验证：
  - `node scripts/generate_lpr_w4_09_a_product_exit_matrix.js`
  - `swift test --filter LocalProviderRuntimeSchemaTests`
  - `swift test --filter HubDiagnosticsBundleExporterTests`
- 证据：
  - `build/reports/lpr_w4_09_a_product_exit_evidence.v1.json`

## 4) 建议执行顺序

### Phase A：先冻结构

1. `LPR-W1-01-A`
2. `LPR-W1-01-B`
3. `LPR-W1-01-C`
4. `LPR-W1-02-A`
5. `LPR-W1-02-B`

### Phase B：再接统一 runtime

6. `LPR-W1-03-A`
7. `LPR-W1-03-B`
8. `LPR-W1-03-C`
9. `LPR-W1-04-A`
10. `LPR-W1-04-B`
11. `LPR-W1-05-A`

### Phase C：先做系统性收益最高的 embeddings

12. `LPR-W2-01-A`
13. `LPR-W2-01-B`

### Phase D：再做音频与治理

14. `LPR-W2-02-A`
15. `LPR-W2-02-B`
16. `LPR-W2-03-A`
17. `LPR-W2-03-B`
18. `LPR-W2-04-A`
19. `LPR-W2-04-B`

### Phase E：最后做视觉 preview、per-device load profile 与 require-real

20. `LPR-W3-01-A`
21. `LPR-W3-01-B`
22. `LPR-W3-02-A`
23. `LPR-W3-04-A`
24. `LPR-W3-04-B`
25. `LPR-W3-04-C`
26. `LPR-W3-03-A`

### Phase F：再做 Hub 本地模型产品化控制面

27. `LPR-W3-05-A`
28. `LPR-W3-05-B`
29. `LPR-W3-05-C`
30. `LPR-W3-08-A`
31. `LPR-W3-08-B`
32. `LPR-W3-08-C`
33. `LPR-W3-07-A`
34. `LPR-W3-07-B`
35. `LPR-W3-07-C`
36. `LPR-W3-06-A`
37. `LPR-W3-06-B`
38. `LPR-W3-06-C`
39. `LPR-W3-06-D`
40. `LPR-W3-05-D`

### Phase G：先收口 require-real，再立 provider-pack / load-config 底座

41. `LPR-W3-03-A`
42. `LPR-W4-01-A`
43. `LPR-W4-02-A`
44. `LPR-W4-03-A`

### Phase H：再收口导入、库视图、已加载实例控制面

45. `LPR-W4-04-A`
46. `LPR-W4-04-B`
47. `LPR-W4-05-A`
48. `LPR-W4-06-A`

### Phase I：最后做新 provider 闭环与产品退出

49. `LPR-W4-07-A`
50. `LPR-W4-07-B`
51. `LPR-W4-08-A`
52. `LPR-W4-08-B`
53. `LPR-W4-09-A`

## 5) 回归清单（直接可抄进测试计划）

### Compatibility

- 老 MLX 模型可继续注册、加载、卸载、生成
- 老 `models_catalog.json` / `models_state.json` 不崩
- 老 `generate` 请求继续可用

### Capability / Policy

- 未启用 `ai.embed.local` 时 embedding 拒绝
- 未启用 `ai.audio.local` 时 ASR 拒绝
- `secret` 输入遇到 `allow_secret_input=false` 的模型拒绝

### Diagnostics

- `mlx down / transformers up`
- `mlx up / transformers down`
- `mlx up / transformers partial`
- `all down`

### Input Guard

- oversized audio
- unsupported audio format
- oversized image
- unsupported image format

### Runtime

- provider load/unload
- provider crash isolation
- concurrent request policy
- queue / deny / retry semantics
- same model + different `context_length` instance isolation
- effective context source visibility（`hub_default|device_override|runtime_clamped`）
- provider-aware warmup / unload / idle eviction
- task-aware routing source visibility（`hub_default|device_override|request_override|auto_selected`）
- loaded instance inventory consistency
- quick bench schema migration / legacy bench compatibility
- runtime monitor snapshot / diagnostics export consistency
- provider pack inventory / runtime bundle state consistency
- typed load config clamp / ttl / parallel / gpu_offload identity consistency
- Add Model auto-detect 与 advanced override 隔离
- capability-first library filters 与 loaded-models console truth 一致
- MLX vision real load / bench / monitor
- GGUF detection / provider mapping / fail-closed behavior

## 6) 交付口径

完成这份 implementation pack 的口径不是“跑过一个 transformers demo”，而是：

- LPR 成为唯一推荐的本地 provider runtime 结构
- MLX 继续稳定
- embeddings / audio / vision 至少能按一条正式主链进入 Hub 的 policy / audit / diagnostics / release gate
- provider pack / runtime bundle / typed load config / loaded instance UX 成为统一产品面
- `mlx_vlm` 与 `llama.cpp` 至少各有一条真实闭环，不再停在“可以导入但不能用”

只有做到这一点，X-Hub 才算真正进入“本地多后端模型治理”的阶段。
