# Local Provider Runtime + Transformers Integration 实现子工单包

- version: v1.0
- updatedAt: 2026-03-12
- owner: Hub Runtime（Primary）/ Memory / Security / QA
- status: planned
- scope: `LPR-W1-01..05` + `LPR-W2-01..04` + `LPR-W3-01..03`
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

### 3.23 `LPR-W3-03-A` Require-Real Runbook / Evidence

- 目标：把 LPR 纳入真实样本与发布门禁。
- 涉及路径：
  - `scripts/`
  - `docs/memory-new/`
- DoD：
  - embeddings / audio / vision 各至少 1 条真实样本
  - 证据生成与校验脚本可运行
- 证据：
  - `build/reports/lpr_w3_03_a_require_real_evidence.v1.json`

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

### Phase E：最后做视觉 preview 与 require-real

20. `LPR-W3-01-A`
21. `LPR-W3-01-B`
22. `LPR-W3-02-A`
23. `LPR-W3-03-A`

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

## 6) 交付口径

完成这份 implementation pack 的口径不是“跑过一个 transformers demo”，而是：

- LPR 成为唯一推荐的本地 provider runtime 结构
- MLX 继续稳定
- embeddings / audio / vision 至少能按一条正式主链进入 Hub 的 policy / audit / diagnostics / release gate

只有做到这一点，X-Hub 才算真正进入“本地多后端模型治理”的阶段。
