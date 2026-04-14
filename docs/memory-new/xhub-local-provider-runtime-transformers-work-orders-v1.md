# X-Hub Local Provider Runtime + Transformers Integration 执行工单

- version: v1.3
- updatedAt: 2026-03-25
- owner: Hub Runtime / Memory / Security / QA
- status: active
- scope: local provider runtime、provider-aware model catalog、Transformers embeddings/audio/vision、policy/audit/doctor/release gate
- parent:
  - `docs/xhub-local-provider-runtime-and-transformers-integration-v1.md`
  - `docs/xhub-runtime-stability-and-launch-recovery-v1.md`
  - `docs/xhub-memory-system-spec-v2.md`
  - `docs/xhub-hub-architecture-tradeoffs-v1.md`
  - `docs/xhub-multi-model-orchestration-and-supervisor-v1.md`
  - `docs/memory-new/xhub-memory-open-source-reference-wave0-execution-pack-v1.md`

## 0) 目标与边界

目标（本轮）
- 把 X-Hub 的本地模型执行面从“MLX-only runtime”升级为 `Local Provider Runtime`（LPR）。
- 让本地模型不再只覆盖文本生成，还能承接 `embeddings / speech_to_text / vision_understand / ocr` 等专业任务。
- 保持 Hub-first：本地专业模型能力也必须继续服从 Hub 的 policy / audit / kill-switch / routing / diagnostics。
- 让 paired terminal 设备可拥有独立的本地 load profile，优先从 `context_length` 开始，后续再扩到 GPU/offload 等 machine-dependent 参数。
- 给后续代码实现提供可直接执行的工单拆分，避免继续停留在“将来支持 transformers”的口头阶段。

边界（本轮不做）
- 不做在线模型商店或自动从 Hugging Face 拉模型。
- 不做“任何第三方 Python pipeline 都能自动插进 Hub”的开放插件系统。
- 不把 X-Terminal 变成直接加载本地模型的第二信任面。
- 不在 v1 里承诺图像生成、视频、TTS 等高体积多模态能力。

## 1) 为什么需要单独开这份工单

当前代码已经具备三类基础，但还没有被收敛成一个真正可演进的本地执行面：

- 协议与模型 catalog 已经允许多 backend，而不是只允许 `mlx`。
- Python runtime 已经是独立进程，具备继续承载本地 provider 的物理位置。
- Memory v2/v3 已经明确需要本地 embeddings，这本质上要求本地 runtime 不再只做文本生成。

但目前仍有几个结构性问题：

- Hub UI 的本地模型导入仍主要按“MLX 模型目录”处理。
- `ai_runtime_status.json` 和 Swift 侧状态判断仍然把“本地 runtime 是否可用”简化成 `mlxOk`。
- Hub 内部本地生成链路默认只面向 `generate`，而不是 task-aware 的本地执行协议。
- 音频、视觉、embedding 这类任务没有正式 task kind、能力声明、限流和审计入口。

如果继续在 `relflowhub_mlx_runtime.py` 里追加条件分支，结果会是：

- UI / runtime / gRPC / policy 各自理解不同的“本地模型能力”
- 新 backend 能跑 demo，但进不了 Hub 的正式治理主链
- 后续 memory / voice / operator / OCR 路线继续各自绕行

所以必须把这条线升级成正式主工单。

## 2) 决策冻结（本工单执行的前提）

### 2.1 唯一执行面：Local Provider Runtime（LPR）

- `mlx` 继续存在，但降级为 provider adapter，而不是“全部本地能力”的代名词。
- v1 必须新增高层运行时入口，例如 `relflowhub_local_runtime.py`。
- 所有本地任务统一走 LPR，而不是让 Swift / Node / Python 各自发明私有路径。

### 2.2 v1 默认严格离线

- 只允许加载本地已存在模型目录。
- 默认保持：
  - `HF_HUB_OFFLINE=1`
  - `TRANSFORMERS_OFFLINE=1`
- 不得把在线下载做成默认产品路径。

### 2.3 本地任务不再等于 `generate`

v1 固定 task kinds：
- `text_generate`
- `embedding`
- `rerank`
- `speech_to_text`
- `vision_understand`
- `ocr`
- `classify`

任何 task kind 与模型能力不匹配时，必须 fail-closed。

### 2.4 capability 必须细化

本地能力不能继续只有 `ai.generate.local` 一个开关。

v1 至少拆成：
- `ai.generate.local`
- `ai.embed.local`
- `ai.audio.local`
- `ai.vision.local`

### 2.5 模型注册必须升级为能力声明

本地模型导入不再只是“路径 + backend + quant”。

v1 必须引入：
- `task_kinds[]`
- `input_modalities[]`
- `output_modalities[]`
- `model_format`
- `offline_ready`
- `resource_profile`
- `trust_profile`
- 可选 `xhub_model_manifest.json`

### 2.6 Health / Doctor / Diagnostics 必须 provider-aware

- UI 不得继续把本地 runtime readiness 简化成 `mlxOk`。
- 若 MLX 不可用但 Transformers embeddings 可用，系统必须明确显示“部分本地能力可用”。

### 2.7 Model Identity 与 Load Profile 必须拆开

- `model_id / model_path / task_kinds / trust_profile / resource_profile` 属于静态模型身份。
- `context_length / gpu_offload / rope scaling / eval_batch_size` 属于加载配置。
- paired terminal 的设备级本地模型偏好必须进入独立 store，不得直接覆写 `models_catalog.json`。
- runtime loaded instance 必须能由 `provider + model_id + load_profile_hash` 唯一判定，否则不同 terminal 设备的上下文长度会互相踩踏。

### 2.8 外部参考基线（LM Studio / OpenCode）

- 可以参考 `lmstudio-js` 与 `opencode`，但只借模式，不搬整套架构。
- 从 LM Studio 借：
  - `ModelInfo` 与 `ModelInstanceInfo` 分离
  - `loadModelConfig` 一等化
  - `contextLength` / `ttl` / `deviceIdentifier` 成为明确 load 参数
  - `listLoaded / unload / getOrLoad / progress` 这类 loaded-instance contract
- 从 OpenCode 借：
  - `providerID + modelID` 的 provider-agnostic 标识
  - `capabilities` + `input/output modalities` + `limit.context/output` 的统一模型元数据
  - transform-time unsupported modality fail-closed，而不是 silent downgrade
- 不借：
  - 不用 LM Studio 替换 X-Hub 的 resident daemon + provider registry
  - 不把 OpenCode 的云 provider auth / pricing / SaaS 假设带进本地模型主链
  - 不把本地多模态模型退化成文本优先的统一 picker
- 对应落点：
  - catalog schema：补 `provider_id / provider_model_key / capabilities / modalities / limits`
  - per-device load profile：继续把 `context_length` 作为第一优先级字段，后续再扩 `gpu_offload / rope / batch`
  - loaded instance inventory：保留 `load_profile_hash / effective_context_length / loaded_at / last_used_at / ttl`
  - bench / monitor：都以同一份 capability 与 loaded-instance truth 为准

### 2.9 LM Studio 运行态拆解结论（2026-03-15）

这次不再只参考 `lmstudio-js-main` 的 type/schema；同时以本机安装包做了运行态拆解，结论如下：

- LM Studio 不是“一个 CLI + 一个推理脚本”，而是 `daemon + domain workers + engine extensions`。
- 当前安装体里能看到独立 worker：
  - `llmworker`
  - `embeddingworker`
  - `asrworker`
  - `imagegenworker`
- 当前安装体里能看到独立 engine/backend manifest：
  - `mlx-llm`
  - `llama.cpp`
- `lms load` 已把 `context-length / gpu / parallel / ttl / identifier` 做成了明确 load 参数，而不是散落 UI 的临时字段。
- MLX engine 的 release notes 已长期携带 `mlx-vlm` 版本与视觉模型支持记录；这说明“MLX 文本”和“MLX 视觉”在产品层不该继续被当成同一个能力黑盒。

因此，X-Hub 下一阶段固定借以下模式：

- 借 `provider pack / engine manifest`：不要把所有本地 backend 继续硬塞进一个 ambient Python 环境。
- 借 `typed load config`：把 `context_length / ttl / parallel / gpu_offload` 收敛成显式 load config。
- 借 `ModelInfo vs LoadedInstanceInfo`：模型静态身份与运行态实例必须继续分层。
- 借 `Loaded Models / Runtime Operations`：把 loaded instances 做成一等 UI，而不是只在诊断页暗藏状态。
- 借 `capability-first library UX`：用户先看“模型能做什么”，而不是先看 backend 名字。

明确不借：

- 不把 LM Studio daemon 直接当成 X-Hub runtime。
- 不把 X-Hub 的 Hub-first policy / audit / grant / kill-switch 交给 provider 包自己决定。
- 不把“backend 选择器”当成普通用户必做步骤。

## 3) Gate 与 KPI

### 3.1 Gate（沿用 spec 的 LPR-G0..G10）

- `LPR-G0`：Schema Freeze
- `LPR-G1`：MLX Compatibility
- `LPR-G2`：Transformers Embeddings
- `LPR-G3`：Transformers Audio
- `LPR-G4`：Transformers Vision
- `LPR-G5`：Security / Governance
- `LPR-G6`：Require-Real
- `LPR-G7`：Managed Provider Pack / Engine Manifest
- `LPR-G8`：Typed Load Config / Loaded Instance UX
- `LPR-G9`：Expanded Provider Coverage（`mlx_vlm` / `llama.cpp`）
- `LPR-G10`：Product Exit / Migration / Operator Usability

### 3.2 KPI

- `local_provider_runtime_false_green_rate = 0`
- `mlx_regression_rate = 0`
- `local_embeddings_success_rate >= 0.99`
- `local_asr_success_rate >= 0.99`
- `provider_mismatch_route_count = 0`
- `local_task_unaudited_count = 0`
- `unauthorized_local_modality_execution = 0`
- `auto_online_model_download_count = 0`
- `manual_backend_selection_rate = 0`
- `provider_pack_auto_detect_accuracy >= 0.99`
- `load_config_drift_bug_count = 0`
- `loaded_instance_truth_mismatch_count = 0`
- `mlx_vlm_real_load_success_rate >= 0.95`
- `gguf_import_success_rate >= 0.95`

## 3.3 Wave-0 `A1` 承接边界

本工单是 `A1 / MRA-A1-*` 的运行时承接面之一，负责：

- 让 memory route 的 `model_id / route_source / route_reason_code / fallback_applied / fallback_reason` 在本地 provider runtime 相关路径里保持一致
- 避免 memory routing 与本地 provider routing 出现两套不一致的 explain 词典
- 把 diagnostic-first route surface 优先落在 runtime / doctor / diagnostics，而不是先做复杂 UI

本轮不负责：

- 重做 memory preferences 真相源
- 为 memory job route 新建第二套 scheduler
- 让本地 provider runtime 越权决定 memory durable writeback

## 3.4 Wave-0 `W0-A1-S3` Diagnostic-First Route Surface 冻结

本工单在 `W0-A1-S3` 下承担的是“把已冻结的 memory route 结果稳定暴露到 runtime / doctor / diagnostics / operator export”，而不是重新发明一套 route 逻辑。

本工单下必须暴露的最小诊断面：

- `request_snapshot`
  - `job_type / mode / sensitivity / trust_level / budget_class / remote_allowed_by_policy`
- `resolution_chain`
  - 至少看得见 `project_mode -> project -> mode -> user_default -> system_fallback`
- `winning_profile`
  - 至少看得见 `resolved_profile_id / scope_kind / selection_strategy / policy_version`
- `winning_binding`
  - 至少看得见 `binding_kind / provider / model_id / selected_by_user`
- `route_result`
  - 至少看得见 `route_source / route_reason_code / fallback_applied / fallback_reason / deny_code`
- `constraint_snapshot`
  - 至少看得见 `remote_allowed_after_user_pref / remote_allowed_after_policy / budget_blocked / policy_blocked_remote`

固定要求：

- LPR 只能展示和导出 route diagnostics，不得在本地 provider runtime 内部重跑一套独立 memory resolver。
- doctor / diagnostics / operator export / loaded instance console 对同一条 route，必须看到相同的 `route_source / route_reason_code / model_id / fallback` 语义。
- 若 doctor bundle 当前承载的是 memory route 结果，优先挂只读 `memory_route_truth_snapshot`，直接复用上游 `Diagnostic-First Route Surface` 六组字段。
- provider/runtime 自己的本地执行事实必须单列表达，例如：
  - `provider`
  - `instance_key`
  - `load_profile_hash`
  - `effective_context_length`
  - `queue_state`
  - `runtime_failure_code`
- 不允许把 provider fallback、runtime recovery、memory route fallback 三者混写成一套模糊 reason。
- 如需产品化友好文案，可以派生展示字段，但不得覆盖冻结后的原始 machine-readable 字段。
- diagnostics export 不得泄露：
  - 原始 preference JSON
  - 本地模型绝对路径
  - provider secret
  - 仅供内部预算器使用的原始参数

当前挂靠到以下 LPR 子工单：

- `LPR-W1-01`
  - 冻结 diagnostics payload 与 status surface 基本词典
- `LPR-W4-01-C`
  - 把 route diagnostics 接到 runtime status / diagnostics bundle / operator export
- `LPR-W4-05-B`
  - 提供 copy diagnostics，可直接复制 route trace 与 fallback 解释（2026-03-23 已交付 Runtime tab clipboard report，直接带出 monitor summary、current targets、active tasks 与 fallback hint）
- `LPR-W4-05-C`
  - 在 loaded instance / route trace 汇总里展示 memory route diagnostics，而不是只显示 provider 层 fallback
  - 当同一 doctor/export 同时展示 provider route 与 memory route 时，二者必须拆成独立区块，不得共用一套 `route_reason_code`

## 4) 工单拆解（按优先级）

### P0（先把底座冻住）

#### `LPR-W1-01` Canonical Schema / Manifest / Status Freeze

- 目标：冻结本地 provider runtime 的 schema、task kinds、manifest、runtime status。
- 完成标准：
  - `ModelCatalogEntry / HubModel` 字段扩展冻结
  - `xhub_model_manifest.json` v1 冻结
  - `xhub.local_runtime_status.v2` 冻结
  - 旧 `mlxOk` 仍兼容，但不得再作为唯一语义
- 交付物：
  - schema diff
  - machine-readable 示例
  - 迁移策略

#### `LPR-W1-02` Backend-aware Model Catalog / Add Model

- 目标：把本地模型导入从“MLX-only”升级成 backend-aware。
- 完成标准：
  - Add Model UI 可选 `MLX / Transformers`
  - MLX 与 Transformers 校验路径分开
  - 缺 manifest 时可推断；推断失败必须阻断导入
  - 旧 catalog 数据自动兼容
- 交付物：
  - UI 入口
  - manifest parser
  - catalog migration

#### `LPR-W1-03` Local Provider Runtime Skeleton

- 目标：建立 LPR 高层运行时入口与 provider registry。
- 完成标准：
  - 新增 `relflowhub_local_runtime.py`
  - 新增 provider base / registry
  - `mlx_provider` 接回现有 MLX 主链
  - 统一 `run_local_task` envelope
- 交付物：
  - Python runtime skeleton
  - provider registry
  - request/response contract

#### `LPR-W1-04` Swift / Node Provider-aware Bridge

- 目标：让 Swift UI 与 Node gRPC 不再直接假定“本地运行时 == MLX”。
- 完成标准：
  - `HubStore.aiGenerate` 对本地 runtime 状态的判断 provider-aware
  - gRPC 本地运行时桥接支持新 task kinds
  - 旧 `generate` 请求兼容
- 交付物：
  - Swift bridge patch
  - Node bridge patch
  - compatibility tests

#### `LPR-W1-05` MLX Compatibility Gate

- 目标：确保引入 LPR 后不打断现有 MLX 主链。
- 完成标准：
  - 现有 load/unload/generate 行为不回退
  - 原有 MLX model catalog、状态和 UI 不崩
  - 现有 diagnostics 仍可定位 MLX import error
- 交付物：
  - regression tests
  - compatibility evidence

### P1（把最值钱的专业模型接进来）

#### `LPR-W2-01` Transformers Embeddings

- 目标：优先接通本地 embeddings，服务 Memory v2/v3。
- 完成标准：
  - 可加载本地 embeddings 模型
  - 支持 batch embedding
  - `ai.embed.local` capability / audit / kill-switch 生效
  - Memory v2 可消费 embeddings 路径
- 交付物：
  - provider implementation
  - memory integration patch
  - benchmark / regression evidence

#### `LPR-W2-02` Transformers Audio / ASR

- 目标：接通本地 `speech_to_text`。
- 完成标准：
  - 音频输入白名单、大小和时长限制生效
  - ASR 结果链路与 usage/audit 完整
  - capability / kill-switch / deny codes 完整
- 交付物：
  - ASR provider implementation
  - task contract
  - input guard

#### `LPR-W2-03` Local Capability Split + Policy / Kill-Switch

- 目标：把本地文本、embedding、音频、视觉从策略面拆开。
- 完成标准：
  - capability 细分
  - policy 决策可按 task_kind / modality 工作
  - kill-switch 可按 provider / capability 关闭
- 交付物：
  - policy patch
  - audit patch
  - deny-code map

#### `LPR-W2-04` Provider-aware Doctor / Diagnostics / Operator UX

- 目标：把 provider 运行态做成可解释运维入口。
- 完成标准：
  - Diagnostics 能显示每个 provider 的 readiness
  - Doctor 能显示“为什么 embeddings 可用但 MLX 不可用”
  - operator summary 支持复制 provider 状态
- 交付物：
  - diagnostics patch
  - doctor patch
  - report exports

### P2（v1 preview 能力补强）

#### `LPR-W3-01` Vision Understand / OCR Preview

- 目标：提供一条正式、受治理的本地视觉主链。
- 完成标准：
  - 至少一个 `vision_understand` 或 `ocr` provider 跑通
  - 图像输入白名单 / 大小限制 / 审计完整
  - capability 与 kill-switch 生效
- 交付物：
  - preview provider
  - image guards
  - evidence pack

#### `LPR-W3-02` Resource Scheduling / Concurrency / Load Policy

- 目标：让多 provider 共存时不把 Hub 变成资源黑盒。
- 完成标准：
  - provider 级并发限制
  - 资源画像字段生效
  - provider 加载/卸载/抢占规则可解释
- 交付物：
  - runtime scheduler policy
  - resource telemetry
  - contention regression

#### `LPR-W3-04` Per-Device Local Load Profile / Context Control

- 目标：借用 LM Studio 的产品做法，把“模型身份”和“加载配置”拆开，并让 Hub 可以为每个 paired terminal 设备保存本地模型 load profile。
- 当前执行进度（2026-03-13）：
  - `LPR-W3-04-A` delivered：schema/store、legacy decode、snake_case / manifest 兼容已落地
  - `LPR-W3-04-B` delivered：Hub paired-device 编辑页已支持 per-model `context_length` override 与 effective context 展示；X-Terminal 已补 default/max context 提示
  - `LPR-W3-04-C` delivered：`run-local-task` 主链已补齐 `effective_load_profile / load_profile_hash / instance_key`，scheduler telemetry、Transformers cache key、Node local task `device_id` 透传均已接通
  - 2026-03-20 revalidation：`relflowhub_mlx_runtime.py` 已按 `instance_key / load_profile_hash / effective_context_length` 收口；MLX 多实例现在可共享同一物理 load，但 public instance identity、bench/generate 上下文长度与 loaded-instance inventory 已按 load profile 隔离
  - 剩余缺口只在 `LPR-G6`：真实本地模型目录的 require-real 样本尚未执行完，不能提前报绿
- 完成标准：
  - paired terminal 可按 `device_id + model_id` 保存 local load profile
  - `context_length` 从模型 catalog 语义中拆出，成为 Hub default + device override 的 effective merge 结果
  - runtime loaded instance 按 `load_profile_hash` 区分，避免不同 terminal 设备互相改写同一实例
  - diagnostics / operator summary 可显示 `max_context_length`、`default_context_length`、`effective_context_length` 与来源
- 交付物：
  - device-scoped load profile schema
  - paired terminal settings / API patch
  - runtime instance-cache / scheduler integration
  - diagnostics / operator evidence

#### `LPR-W3-03` Require-Real / Release Gate

- 目标：把本地 provider runtime 纳入真实样本与发布门禁。
- 完成标准：
  - embeddings / audio / vision 至少各 1 条 require-real 样本
  - 真实模型目录与真实输入样本完成演练
  - release gate 与 doctor 证据接线完成
- 交付物：
  - require-real runbook
  - evidence generator/checker
  - release hints
- 当前落点（2026-03-15）：
  - runbook：`docs/memory-new/xhub-local-provider-runtime-require-real-runbook-v1.md`
  - capture bundle：`build/reports/lpr_w3_03_require_real_capture_bundle.v1.json`
  - evidence generator：`scripts/generate_lpr_w3_03_a_require_real_evidence.js`
  - status helper：`scripts/lpr_w3_03_require_real_status.js`
  - runtime/model probe：`scripts/generate_lpr_w3_03_b_runtime_candidate_probe.js`
  - model native-loadability probe：`scripts/generate_lpr_w3_03_c_model_native_loadability_probe.js`
  - helper bridge actual probe：`scripts/generate_lpr_w3_03_d_helper_bridge_probe.js`
  - prerequisite rebuild：`scripts/rebuild_lpr_w3_03_prerequisite_evidence.js`
  - 最新 probe（2026-03-20）：`build/reports/lpr_w3_03_b_runtime_candidate_probe.v1.json` 已证明 combo runtime 可 ready，但当前本机 embedding 模型目录仍 fail-closed 为 `unsupported_quantization_config`
  - 最新 model probe（2026-03-20）：`build/reports/lpr_w3_03_c_model_native_loadability_probe.v1.json` 已确认本机只发现 `1` 条 embedding 候选目录，且 `0` 条可被 torch/transformers 原生加载；当前 blocker 不只是 sample1 单次失败，而是“现有本地 embedding 目录族本身不是 native-loadable candidate”
  - 最新 helper probe（2026-03-21）：`build/reports/lpr_w3_03_d_helper_bridge_probe.v1.json` 已确认 `~/.lmstudio/bin/lms` 存在，但当前更精确的 blocker 是 `helper_local_service_disabled`；机读证据显示 `~/.lmstudio/settings.json` 为 `enableLocalService=false`, `cliInstalled=false`, `appFirstLoad=true`
  - 同一 probe 也确认：`lms daemon up --json` 与 `lms server start --bind 127.0.0.1 --port 1234` 仍会停在 `Waking up LM Studio service...` 并超时；虽然 `llmster` 进程仍存活且监听 `127.0.0.1:41343`，但 `server status` 仍未进入 `running=true`
  - `2026-03-21` 追加主线收口：已补 `docs/memory-new/xhub-local-service-runtime-contract-v1.md`，并把 `xhub_local_service` 预接入到 Python resolver、provider pack schema、Swift guidance / import detection；当前口径改为“LM Studio 只作参考桥接样本，Hub 自管 `xhub_local_service` 才是后续主线”
  - `2026-03-21` 同步把 runnable service 往前推到 multimodal chat proxy：`x-hub/python-runtime/python_service/xhub_local_service_runtime.py` 现已提供真实 `GET /health`、`GET /v1/models`、`POST /admin/warmup|unload|evict` delegation，以及 OpenAI-style `POST /v1/embeddings`、`POST /v1/chat/completions` -> `run_local_task(...)` 代理；其中 chat 已支持本地图片 content part 路由到 `vision_understand / ocr`，但远程 `http(s)` image URL 继续 fail-closed；同时补齐 service-internal runtime resolution，避免 `executionMode=xhub_local_service` 在 service 进程内递归误判；配套 smoke 覆盖在 `x-hub/python-runtime/python_service/test_xhub_local_service_runtime.py`
  - `2026-03-21` 已把 `xhub_local_service` 证据链接到 Hub doctor / diagnostics export：doctor 的 provider readiness 现在会直出 `xhub_local_service_*` failure code 与 endpoint 细节，bundle 新增 `xhub_local_service_snapshot.redacted.json`；该快照现已额外带 `primary_issue + doctor_projection`，incident/export/自动诊断无需再从 detail text 反向猜当前主问题和建议动作；同时 Hub doctor writer 现会在 base dir 同步落 `xhub_local_service_snapshot.redacted.json` sidecar，XT `XT-Ready / incident export` 在 Hub doctor 缺失或较旧时可直接 fallback 消费
  - `2026-03-22` 已把 `xhub_local_service_snapshot` 接进 source-run release gate：新增 `scripts/smoke_xhub_doctor_hub_local_service_snapshot.sh` 并纳入 `scripts/ci/xhub_doctor_source_gate.sh`；gate summary 现新增 `hub_local_service_snapshot_support`，直接机读 `primary_issue_reason_code / doctor_failure_code / provider_id / service_state / managed_process_state / managed_start_attempt_count`，release/operator/support 不再需要反解 detail text 才能判断主问题和恢复方向
  - `2026-03-22` 已补 operator/support/release wording 报告生成器：`scripts/generate_xhub_local_service_operator_recovery_report.js` 现会消费 `xhub_doctor_source_gate_summary.v1.json + xhub_doctor_hub_local_service_snapshot_smoke_evidence.v1.json + lpr_w3_03_a_require_real_evidence.v1.json`，导出 `build/reports/xhub_local_service_operator_recovery_report.v1.json`，把 `action_category / install_hint / recommended_actions / support_faq / external_status_line` 固化为 machine-readable output
  - `2026-03-22` 已把上述 operator recovery report 接进正式 release 证据链：`scripts/refresh_oss_release_evidence.sh` 会先刷新该报告，再由 `build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json` 与 `build/reports/oss_release_readiness_v1.json` 直接消费 `action_category / external_status_line / top_recommended_action`，避免 release decision 再单独反解或改写本地恢复文案
  - `2026-03-23` 已补 Hub App 内 install hint surface：新增 Swift 侧 `XHubLocalServiceRecoveryGuidanceBuilder`，直接从 `ai_runtime_status + xhub.doctor_output.v1` 结构化生成 `action_category / install_hint / recommended_actions / support_faq`，并在 `SettingsSheetView` 的系统体检区展示 `Hub 本地服务恢复建议`；复制运行包摘要 / issue snippet 时也会一并带上这段 machine-readable recovery block，support/operator 不必只看一段自由文本 install hint
  - `2026-03-23` 同步把这份 recovery guidance 接进导出链：`XHubDoctorOutputStore.writeCurrentHubRuntimeReadinessReport(...)` 现在会额外落 `xhub_local_service_recovery_guidance.redacted.json` companion sidecar，`HubDiagnosticsBundleExporter` 也会把同名 JSON 带进 diagnostics bundle；CLI `XHub doctor --out-json ...` 产物目录同样会带这份 sidecar，便于 support/operator 直接消费结构化恢复动作与 FAQ
  - `2026-03-23` 已把 release/operator wording 链升级成 guidance-first：`scripts/smoke_xhub_doctor_hub_local_service_snapshot.sh` 现在会验证并落盘 `hub_local_service_recovery_guidance` raw evidence，`scripts/ci/xhub_doctor_source_gate.sh` summary 新增 `hub_local_service_recovery_guidance_support`，而 `scripts/generate_xhub_local_service_operator_recovery_report.js` 现会优先复用这份 sidecar 导出的 `action_category / install_hint / recommended_actions / support_faq`，仅在 guidance 缺失时才 fallback 到旧 snapshot/source-gate 推导，避免 Hub App / XT / release wording 出现三套不同恢复口径
  - `2026-03-23` 已把 `LPR-W3-03-A` 的 fail-closed 报告升级成 blocker-aware：`scripts/generate_lpr_w3_03_a_require_real_evidence.js` 现会直接消费 `lpr_w3_03_b/c/d` 三份 probe，输出 `sample1_current_blockers / sample1_runtime_ready / sample1_execution_ready / sample1_overall_recommended_action_id / sample1_preferred_route / sample1_secondary_route`，并把同一组 blocker/next-step 追加进 `verdict_reason / next_required_artifacts`；`scripts/generate_lpr_w4_09_c_product_exit_packet.js` 的 compact require-real 摘要也同步透传这组字段，operator/release 出口不再只看到 `pending` 却看不到真实卡点
  - `2026-03-23` 同步把 `scripts/lpr_w3_03_require_real_status.js` 升级成 blocker-aware status 出口：`--json` 现会直接透出 `qa_verdict_reason / qa_next_required_artifacts / qa_machine_decision`，人类可读输出也会先列出 sample1 blockers 与 `next_required_artifacts`，operator 不必再手工翻 `lpr_w3_03_a_require_real_evidence.v1.json` 才能知道当前缺哪组真实样本、validator 还卡在哪一步
  - `2026-03-22` 已补 `LPR-W4-09-C` 单出口聚合：`scripts/generate_lpr_w4_09_c_product_exit_packet.js` 会把 `operator_recovery + operator_channel_recovery + require_real + boundary + oss_readiness` 收成 `build/reports/lpr_w4_09_c_product_exit_packet.v1.json`，对缺失 release 证据明确 fail-closed，并把 operator handoff / release handoff 放在一份机读包里；其中本地 runtime recovery 仍是 release-gating truth，而 channel onboarding recovery 会作为 first-class operator/release context 被一并透传，不会再成为“helper 已生成但单出口没消费”的孤立报告；该包还会直接导出 `release_refresh_preflight.missing_inputs[]`，告诉 operator 当前还缺哪些上游 release artifact 才能跑通 `refresh_oss_release_evidence.sh`；XT-ready 预检现已按 `require_real -> db_real -> current` 证据链优先级选择，不再把旧的 `build/xt_ready_gate_e2e_report.json` 当成唯一入口，且 paired `xt_ready_evidence_source / connector_ingress_gate_snapshot` 也会按同一条链一起检查
  - `2026-03-23` 同步把 `W4-09-C` require-real 聚合面补成 blocker-aware：product exit packet 里的 `support_truth.require_real` 与 `operator_handoff.require_real_focus` 现会一并带上 `verdict_reason + next_required_artifacts`，单出口 handoff 包可直接告诉 operator 当前缺哪组真实样本、sample1 该先走哪条解阻路径，而不用再回跳 `lpr_w3_03_a_require_real_evidence.v1.json`
  - `2026-03-23` 继续把 `sample1` 执行链补成 machine-readable retry/recovery surface：`generate_lpr_w3_03_sample1_candidate_validation.js`、`generate_lpr_w3_03_sample1_candidate_shortlist.js`、`generate_lpr_w3_03_sample1_candidate_registration_packet.js` 与 `generate_lpr_w3_03_sample1_operator_handoff.js` 现都会稳定输出 `search_recovery / search_recovery_plan`，直接给出 `exact_path_shortlist_refresh_command / exact_path_validation_command / wide_shortlist_search_command / custom_scan_root_shortlist_command_template`；当前机器真实报告也已刷新到 `build/reports/lpr_w3_03_sample1_candidate_{shortlist,validation,registration_packet}.v1.json + lpr_w3_03_sample1_operator_handoff.v1.json`，并如实显示 sample1 仍被 `unsupported_quantization_config` 卡住，而不是只剩一段 prose 让 operator 自己猜下一条命令
  - `2026-03-23` 同日继续修正 discovery 盲区：默认 sample1 scan roots 新增 `~/models`，因为当前机器真实存在 `/Users/andrew.xie/models/qwen3-7b-4bit` 这类本地目录；刷新后的 shortlist/probe 已能把它记为“已搜索但非 sample1-ready”的 machine-readable truth，而不是完全漏扫
  - `2026-03-22` 已补 legacy release compatibility pack：`scripts/generate_release_legacy_compat_artifacts.js` 会把丢失的 `xt_w3_release_ready_decision / xt_w3_require_real_provenance / xt_w3_25_competitive_rollback / xt_ready_evidence_source / connector_ingress_gate_snapshot / internal_pass_lines` 以及若干 XT-W3-23/24/25 历史 evidence 文件名，用当前 XT/Hub machine-readable truth 保守回填到 legacy 路径，并输出 `build/reports/release_legacy_compat_pack.v1.json`；它只负责“让旧消费者继续有文件可读”，不会把 require-real / audit-source / internal-pass 的 fail-closed 状态伪装成 release-ready；XT-ready 输入选择现也与正式 release surface 一样遵循 `require_real -> db_real -> current`
  - `2026-03-22` 已在放行后重跑 targeted XT source-capture：`SupervisorMemoryUXAdapterTests/runtimeCaptureWritesXTW323EvidenceFilesWhenRequested`、`SupervisorMultichannelGatewayProductizationTests/runtimeCaptureWritesXTW324EvidenceFilesWhenRequested`、`SupervisorAutomationProductGapClosureTests/runtimeCaptureWritesXTW325EvidenceFilesWhenRequested` 已成功把 `xt_w3_23_*`、`xt_w3_24_e_onboard_bootstrap_evidence.v1.json`、`xt_w3_24_f_channel_hub_boundary_evidence.v1.json`、`xt_w3_25_e_bootstrap_templates_evidence.v1.json` 重新导出到 `build/reports/`；compat exporter 随后验证了它会 `preserved_existing` 这些真实产物，而不是把它们再覆盖回 compat stub
  - `2026-03-21` 已补 richer multimodal contract：Transformers provider 现已真实消费 `image_paths` / `multimodal_messages`，支持 multi-image real runtime 与 helper bridge 双路径，不再把 `image_paths` 错误 lower-case 成假路径；`xhub_local_service` chat proxy 现已稳定产出 multi-image / multi-turn / explicit-task machine-readable `routeTrace`；聚焦回归覆盖在 `x-hub/python-runtime/python_service/test_transformers_provider_multimodal_contract.py` 与 `x-hub/python-runtime/python_service/test_xhub_local_service_runtime.py`
  - `2026-03-21` 已把 `routeTrace` 接进 bench / runtime monitor / operator export：provider quick bench 成功结果现会透传底层 task 的 `routeTrace`，runtime 会在 `models_bench.json` 持久化 `routeTrace + routeTraceSummary`，`ai_runtime_status.json` / `monitorSnapshot` 新增 `recentBenchResults`，Hub JS IPC 会归一化成 `recent_bench_results[].route_trace_summary`；回归覆盖在 `x-hub/python-runtime/python_service/test_transformers_provider_multimodal_contract.py` 与 `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
  - `2026-03-21` 已把 `recentBenchResults.routeTraceSummary` 接到 Hub 上层 operator / doctor / diagnostics export：`AIRuntimeStatus` / `ModelBenchResult` 现可解 `recentBenchResults + routeTraceSummary`，`providerOperatorSummary`、`providerDoctorText`、`runtimeMonitorOperatorSummary` 与 `xhub_doctor_output_hub.redacted.json` 的 runtime monitor check 会直接给出 `execution_path / fallback_mode / blocked_reason`；回归覆盖在 `x-hub/macos/RELFlowHub/Tests/RELFlowHubCoreTests/LocalProviderRuntimeSchemaTests.swift` 与 `x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/HubDiagnosticsBundleExporterTests.swift`
  - `2026-03-21` 已补 multi-image OCR page-aware contract：provider 对 OCR 多图请求会按页 fanout 执行，再聚合成单次结果；`spans[]` 现会稳定带 `pageIndex / pageCount / fileName / bbox`，聚合 `text` 带 `[page N]` 分段，避免多页 OCR 只有无边界纯文本；回归覆盖在 `x-hub/python-runtime/python_service/test_transformers_provider_multimodal_contract.py`、`x-hub/python-runtime/python_service/test_xhub_local_service_runtime.py`、`x-hub/grpc-server/hub_grpc_server/src/local_vision.test.js`
  - `2026-03-21` 已补 `xhub_local_service` 生命周期管理第一段：Python bridge / resolver 现会对 `executionMode=xhub_local_service` 做 loopback-only endpoint 校验、managed autostart、启动后 `/health` 回探和已有 pid/state 复用；同时把 `xhub_local_service_state.json` 与 provider status `managedServiceState` 接通，状态至少带 `pid / bindHost / bindPort / startedAtMs / lastProbeAtMs / lastReadyAtMs / startAttemptCount / lastStartError`；聚焦回归覆盖在 `x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`，真实 loopback smoke 继续由 `x-hub/python-runtime/python_service/test_xhub_local_service_runtime.py` 承接
  - 若 `build/reports/` 被清空，先跑 prerequisite rebuild 恢复 `LPR-W3-03-A` 依赖的 7 份前置 evidence，再重跑 require-real QA
  - `2026-03-20` 已用 prerequisite rebuild 重建前置 evidence，并把 QA 口径从 `NO_GO(prerequisite_evidence_missing)` 推进回 `NO_GO(require_real_samples_pending)`

### P3（Hub 本地模型产品化收口）

#### `LPR-W3-05` Provider-aware Warmup / Unload / Instance Lifecycle

- 目标：把 Hub 模型列表里的 `Load / Unload` 从 legacy MLX-only 命令链升级成 provider-aware 的 `Warmup / Unload / Evict` 控制面。
- 完成标准：
  - 非 MLX 本地模型不再在 Hub UI 里被直接 fail-fast 拦截
  - Hub 可对 `text_generate / embedding / speech_to_text / vision_understand / ocr` 发起 provider-aware warmup
  - runtime status 可列出 loaded instances，并带 `instance_key / load_profile_hash / effective_context_length / last_used_at`
  - 无法显式 unload 的 provider 必须清楚标记为 `ephemeral_on_demand`，不得假装实现常驻生命周期
- 交付物：
  - warmup/unload contract
  - loaded instance inventory
  - Hub model drawer action patch
- 当前状态（2026-03-15）：
  - `LPR-W3-05-A` 已交付：LPR / Node IPC 已支持 `warmup_local_model / unload_local_model / evict_local_instance`，并保持 legacy MLX 兼容
  - `LPR-W3-05-B` 已交付：Hub UI 已引入 provider-aware action planner，可区分 `mlx_legacy / warmable / ephemeral_on_demand`
  - `LPR-W3-05-C` 已交付：loaded instance / idle eviction inventory 已进入 runtime status、Node normalization 与 monitor snapshot
  - `LPR-W3-05-D` 已交付：resident daemon command proxy 已补齐；当 `ai_runtime_status.json` 携带新鲜 `localCommandIpcVersion` 时，`run-local-task / run-local-bench / manage-local-model` 会优先代理到常驻 runtime，Swift warmable planner 也已对 `runtime_process` provider 放通 `Warmup / Unload`

#### `LPR-W3-06` Task-aware Bench v2 / Capability Summary

- 目标：让 Hub 的 `Bench` 从 MLX 文本测速升级成 task-aware 的本地模型能力概览。
- 完成标准：
  - Bench 支持 `text_generate / embedding / speech_to_text / vision_understand / ocr`
  - Bench 结果不再只存 `tok/s`，而是按 task kind 记录 latency / throughput / peak memory / fallback mode / fixture profile
  - Hub UI 能输出用户可理解的结论，如 `Fast / Balanced / Heavy / Preview only / CPU fallback`
  - Bench 失败时明确区分 `provider_not_ready / fixture_missing / fallback_only / unsupported_task`
- 交付物：
  - bench schema v2
  - runtime bench adapters
  - Hub quick bench + summary UI
- 当前状态（2026-03-15）：
  - `LPR-W3-06-A` 已交付：`models_bench.json` 升级为 task-aware schema v2，并兼容 legacy MLX bench 解码与 UI 标记
  - `LPR-W3-06-B` 已交付：runtime 新增 `run-local-bench` CLI，Transformers provider 支持 `embedding / speech_to_text / vision_understand / ocr` quick bench，MLX 保持 legacy 真跑
  - `LPR-W3-06-C` 已交付：Hub 模型卡片新增最新 bench 摘要，Bench sheet 支持按 task / fixture profile 运行 quick bench，并暴露 reason code / verdict
  - `LPR-W3-06-D` 已交付：fixture pack 资源、generator-backed 本地素材、shared fixture ID contract 与证据脚本已冻结

#### `LPR-W3-07` Runtime Monitor / Useful Telemetry

- 目标：让用户在使用本地模型时能看到真正有决策价值的运行态信息，而不是只有 `Loaded / Available`。
- 完成标准：
  - Hub 可显示 provider 级 `ready / busy / partial / fallback` 状态
  - Hub 可显示 active tasks、queue wait、loaded instances、memory、fallback mode、last error
  - Diagnostics / operator summary 可导出 monitor snapshot
  - 用户能判断“为什么慢 / 为什么失败 / 为什么走 CPU fallback”
- 交付物：
  - runtime monitor snapshot
  - Hub runtime monitor UI
  - diagnostics export patch

#### `LPR-W3-08` Task-aware Local Model Routing / Use-For Binding

- 目标：让用户导入模型之后，能把模型明确绑定到 `Generate / Embedding / ASR / Voice / Vision / OCR` 这些真实用途上，而不是靠环境变量或隐式首选。
- 完成标准：
  - Hub 可为 task kind 保存默认本地模型绑定
  - 可选支持 paired terminal 设备级 task binding override
  - Node / runtime 解析本地任务时优先读 routing store，而不是依赖硬编码 env
  - UI 可显示 routing source：`hub_default / device_override / request_override / auto_selected`
- 交付物：
  - task routing schema v2
  - Hub `Use For...` binding UI
  - local task resolution integration

### P4（LM Studio 对齐的 Managed Provider Pack + UI 收口）

#### `LPR-W4-01` Managed Provider Pack / Engine Manifest

- 目标：把本地 backend 从“代码里写死的 provider 名称”升级成可安装、可盘点、可诊断的 provider pack。
- 参考：
  - 借 LM Studio 的 engine manifest / backend inventory 模式
  - 不引入它的整套 daemon 协议
- 依赖：
  - `LPR-W3-08`
  - `LPR-W3-07`
- 子工单：
  - `LPR-W4-01-A` provider pack manifest schema（`provider_id / engine / version / supported_formats / supported_domains / runtime_requirements / min_hub_version`，2026-03-16 已落地 Python/Node/Swift contract + tests）
  - `LPR-W4-01-B` installed pack registry / enable-disable / version truth（2026-03-16 已落地 file-backed `provider_pack_registry.json` override + runtime fail-closed）
  - `LPR-W4-01-C` runtime status / diagnostics / operator export 接通 pack inventory（2026-03-16 已落地 operator summary / diagnostics bundle 首轮接入）
- 完成标准：
  - Hub 能列出已安装 provider packs，而不是只显示 provider 字符串
  - `mlx`、`transformers` 先迁入 pack registry
  - pack 缺失、版本不兼容、依赖缺失都 machine-readable
  - Add Model / Bench / Warmup / Monitor 都从 pack registry 取 provider truth
- 交付物：
  - provider pack manifest schema
  - pack registry store
  - diagnostics / operator export patch

#### `LPR-W4-02` Managed Runtime Bundle / Provider-owned Dependencies

- 目标：减少对用户系统 Python 的隐式依赖，让 provider 自己声明并管理运行时依赖。
- 参考：
  - 借 LM Studio 的 provider-owned runtime / bundled dependency 模式
- 依赖：
  - `LPR-W4-01`
- 子工单：
  - `LPR-W4-02-A` provider runtime requirement contract（`python / wheel bundle / native dylib / helper binary`，2026-03-16 已落地 resolver + runtime source/state/hint schema；同日补齐 transformers task/warmup/bench failure envelope 与 bench persistence 透传）
  - `LPR-W4-02-B` provider-specific runtime resolution（优先 pack-owned，其次 user-provided fallback）
  - `LPR-W4-02-C` doctor / auto-recovery / install hint 收口（2026-03-23 已补 Hub recovery guidance builder + diagnostics bundle/CLI sidecar export + XT loader/incident export/presentation consumption，结构化暴露 `action_category/install_hint/recommended_action/support_faq`，focused regression: `XHubDoctorOutputTests + SupervisorIncidentExportTests + SupervisorXTReadyIncidentPresentationTests + XHubLocalServiceRecoveryGuidanceTests + XHubCLIRunnerTests`）
- 完成标准：
  - provider 启动时能明确区分 `pack_runtime_ready / user_runtime_fallback / runtime_missing`
  - 不再把“有没有某个系统 Python 包”当成唯一产品路径
  - 运行时切换后，Hub UI 与 runtime monitor 都能看到 provider 绑定了哪套 runtime
  - 失败原因明确到 pack / runtime / import / native dependency 层级
- 交付物：
  - runtime resolution contract
  - provider runtime inventory
  - doctor / auto-recovery evidence
- 当前进度（2026-03-23）：
  - 已补 `scripts/generate_lpr_w4_02_b_provider_runtime_inventory_evidence.js`，直接复用 `local_runtime_ipc.readRuntimeStatusSnapshot(...)` 生成 `build/reports/lpr_w4_02_b_provider_runtime_inventory_evidence.v1.json`
  - 该报告把 `provider_packs + runtime_source + runtime_resolution_state + runtime_reason_code + fallback_used + runtime_hint` 收成单独机读 inventory，并明确区分“当前机器的 runtime blocker”与“W4-02 contract 本身是否完整”
  - 同步修正 Node snapshot 的 pack inventory 回退：当旧 `ai_runtime_status.json` 缺少顶层 `providerPacks`，但 provider 行内已带 `packId/packState/packReasonCode` 时，`local_runtime_ipc.js` 现在会优先从 provider truth 反推 pack inventory，而不是直接退化成 `legacy_unreported`
  - 当前机器已实际生成 `build/reports/lpr_w4_02_b_provider_runtime_inventory_evidence.v1.json`，报告状态为 `PASS(provider_runtime_inventory_contract_captured)`；同时保留真实 blocker：`mlx=user_runtime_fallback`、`transformers=runtime_missing(python_module:torch)`

#### `LPR-W4-03` Typed Load Config / ModelInfo vs LoadedInstanceInfo 收口

- 目标：把当前 `default_load_profile + effective_context_length + instance_key` 升级成正式的 typed load config，并显式区分模型静态信息和已加载实例信息。
- 参考：
  - 借 LM Studio 的 `loadModelConfig`
  - 借 `ModelInfo` vs `Loaded Instance Info`
- 依赖：
  - `LPR-W3-04`
  - `LPR-W4-01`
- 子工单：
  - `LPR-W4-03-A` `load_config.v1` schema：`context_length / ttl / parallel / gpu_offload / identifier / vision.image_max_dimension`
  - `LPR-W4-03-B` loaded instance contract：`current_context_length / max_context_length / load_config_hash / residency / ttl / progress`
  - `LPR-W4-03-C` Hub / X-Terminal 设置与显示统一切到 typed load config
- 完成标准：
  - `max_context_length` 与 `effective_context_length` 在 UI 中明确分离
  - 当前实例使用中的 load config 可被查看、比较、复制
  - `ttl / parallel / gpu_offload` 至少在 schema 与 runtime identity 层可用
  - bench / monitor / routing / warmup 使用同一份 load config identity
- 交付物：
  - load config schema v1
  - loaded instance schema v1
  - UI / runtime integration patch
- 当前进度（2026-03-23）：
  - Node 归一化层已开始补齐 `W4-03-A`：`listRuntimeModelRecords(...)` 现在稳定暴露 `default_context_length / max_context_length / default_load_config`，`readRuntimeStatusSnapshot(...)` / bench / scheduler active task 则补齐 `load_config_hash / current_context_length / max_context_length / load_config`
  - 该改动保持 legacy alias 兼容：旧的 `default_load_profile / load_profile_hash / effective_context_length / effective_load_profile` 继续保留，避免现有调用面一次性断裂
  - 已补 `scripts/generate_lpr_w4_03_a_typed_load_config_evidence.js`，生成 `build/reports/lpr_w4_03_a_typed_load_config_evidence.v1.json`，直接验证 `ModelInfo(default_load_config)` 与 `LoadedInstanceInfo(load_config)` 两侧 contract 是否同时可见
  - 当前机器已实际生成该报告，状态为 `PASS(typed_load_config_contract_captured)`；机读结果显示 `model_record_count=2`、`loaded_instance_count=1`，且 `load_config_hash/current_context_length/max_context_length/load_config` 全部可见
  - Hub Swift consumer 面已开始消化 `W4-03-B/C`：`AIRuntimeStatus` 解码层现在接受 `load_config_hash / current_context_length / max_context_length / load_config`，运行摘要、诊断导出、设置面板、主面板 active task 文案与集中字符串也统一切到 typed load-config 语义
  - 同一轮补齐了“写回面” contract：结构化 monitor export 现在会把 `loaded_instance / active_task / recent_bench_result` 的 `load_config_hash / current_context_length / load_config` alias 一并导出，`active_task` 还开始保留 `max_context_length`；runtime request payload 也开始并发发送 `load_config_hash / current_context_length`
  - 上述 Hub consumer slice 已做定向回归验证并通过：`LocalProviderRuntimeSchemaTests`、`LocalRuntimeOperationsSummaryBuilderTests`、`LocalModelRuntimeRequestContextTests`、`HubUIStringsTests`、`HubDiagnosticsBundleExporterTests`
  - `W4-03-B` 当前已继续补到 loaded-instance / active-task 的真实 `ttl` 面：Python scheduler telemetry 现在显式暴露 `lease_ttl_sec / lease_remaining_ttl_sec / expires_at`，provider status / runtime monitor / Node normalization / Hub Swift schema / diagnostics export / settings summary 都能稳定透出这些字段；loaded instance 顶层 `ttl` 也会从真实 load profile 回填
  - X-Terminal schema decode 已开始承接 typed load-config 扩展：`HubModels.swift` 现可解 `ttl / parallel / identifier / vision.image_max_dimension`，并已有 `XTModelCatalogTests` 覆盖 snake_case contract
  - 本轮把 `default_load_config` canonical key 也补成真正可消费主路径：Node `listRuntimeModelRecords(...)` 读模型状态时会优先吃 `default_load_config/defaultLoadConfig`，Python `_normalize_default_load_profile(...)` 也开始接受这两个 key，Hub/XT Swift decode 与 manifest decode 同时支持 `default_load_config` 主字段并继续兼容 `default_load_profile` legacy alias
  - `W4-03-C` 已继续落 XT consumer：XT 现在会读取 `local_runtime_monitor_snapshot.redacted.json`，把 Hub monitor export 里的 `runtime_operations.current_targets / loaded_instances.load_summary` 接到 XT-ready hub runtime diagnosis，并进一步在 XT-ready incident export / status 文本与 Supervisor XT-ready board 上显式 surface `hub_runtime_load_config`；模型设置页与 Hub model picker 已收口到 `默认加载配置 / 本地加载上限` typed load-config 词汇，不再 fallback 到“Hub 默认上下文 / 本地上限”旧文案；本轮又把 `/models`、`/route diagnose`、Supervisor system prompt 与 Hub runtime 尾部 fallback 文案继续统一到同一套词汇
  - 本轮 focused verification 已通过：`node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`、`PYTHONPYCACHEPREFIX=/tmp python3 x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`、`swift test --filter LocalProviderRuntimeSchemaTests`、`swift test --filter HubDiagnosticsBundleExporterTests`、`swift test --filter XHubDoctorOutputTests`、`swiftpm-testing-helper --filter SupervisorIncidentExportTests`、`swiftpm-testing-helper --filter SupervisorXTReadyIncidentPresentationTests`、`swift test --filter XTModelCatalogTests`、`swift test --filter ChatSessionModelDirectReplyTests`、`swift test --filter SupervisorPromptModelEvidenceTests`
  - 当前剩余缺口已不再是 `ttl` truth 或 residual wording drift；主 XT chat/supervisor/UI surfaces 与 Hub runtime 尾部文案都已对齐 typed load-config 词汇，`progress` 继续保持 fail-closed（上游 runtime 仍未提供真实进度），因此 `LPR-W4-03` 仍保持 `in_progress`

#### `LPR-W4-04` Add Model / Library UX Simplification

- 目标：把 Add Model 和本地模型列表做成 capability-first UX，继续减少普通用户手工选择 backend 的需要。
- 参考：
  - 借 LM Studio 的库视图、已加载状态、按能力过滤的交互思路
- 依赖：
  - `LPR-W4-01`
  - `LPR-W4-03`
- 子工单：
  - `LPR-W4-04-A` Add Model 自动探测：格式、provider candidate、task kinds、modalities、runtime pack readiness（2026-03-16 已补到导入页 readiness summary：pack/runtime state + auto-recovery hint；2026-03-17 已补卡片化导入页：summary pills、identity card、readiness card、advanced 收口）
  - `LPR-W4-04-B` model library filters：`Loaded / Text / Embedding / Audio / Vision / OCR / Preview`（2026-03-17 已补首轮 My Models 风格改造：搜索框、filter chips、library summary pills、card row、overflow actions）
  - `LPR-W4-04-C` 普通流移除 backend/role 手工选择，debug only override 收口到高级面板（2026-03-24 复核：`AddModelSheet` 普通导入流仅保留目录、身份、readiness 与自动探测摘要；`backend` 改为自动探测，`roles` 固定为 `nil`，技术 runtime/backend 信息仅作为高级项只读说明）
- 完成标准：
  - 普通用户导入模型时无需先理解 `MLX / Transformers / GGUF`
  - 模型卡片能直接显示 capability、loadability、loaded state、provider pack state
  - `Role` 与 `Backend Override` 都不再是普通导入路径的前置
  - 失败时直接给出“缺什么 pack / runtime / processor / model files”
- 交付物：
  - Add Model auto-detect patch
  - library filter / chip UI
  - My Models-inspired search + card layout patch
  - diagnostics copy patch

#### `LPR-W4-05` Loaded Models / Runtime Operations Console

- 目标：把 loaded instances 做成单独的一等产品面，让用户可查看、预热、卸载、驱逐、对比实例。
- 参考：
  - 借 LM Studio 的 loaded models / runtime operations 习惯
- 依赖：
  - `LPR-W4-03`
  - `LPR-W3-05`
  - `LPR-W3-07`
- 子工单：
  - `LPR-W4-05-A` Loaded Instances panel：显示实例、来源设备、load config、ttl、last_used、queue state（2026-03-17 已补模型抽屉 `Library / Runtime` 双视图，Runtime tab 可直接看全量 loaded instances）
  - `LPR-W4-05-B` progress / warmup / unload / evict / copy diagnostics（2026-03-23 Runtime tab 已补 `复制诊断`，直接复制 monitor summary、recent route trace、current targets、active tasks 与 fallback 解释）
  - `LPR-W4-05-C` route trace、fallback、load source、pack/runtime source 聚合展示（2026-03-17 已补 Provider Packs / Current Targets / Active Tasks 三组卡片，直接复用 runtime snapshot 与 provider diagnosis，不引入阻塞探测）
- 完成标准：
  - 用户能从一个面板看到“磁盘上有哪些模型”和“内存里当前加载了哪些实例”的差别
  - warmup/unload/evict 不再只能从零散按钮进入
  - 同一模型不同 load profile 的实例可同时解释，不再互相混淆
- 交付物：
  - loaded instance console UI
  - runtime operations contract
  - monitor / diagnostics integration

#### `LPR-W4-06` Bench + Monitor Fusion / Capability Card

- 目标：把 Bench 结果与 Runtime Monitor 融合成真正对用户有价值的能力卡片与使用建议。
- 参考：
  - 借 LM Studio “模型能力 + 当前加载参数 + 当前运行态”都可见的产品逻辑
- 依赖：
  - `LPR-W4-03`
  - `LPR-W4-05`
  - `LPR-W3-06`
  - `LPR-W3-07`
- 子工单：
  - `LPR-W4-06-A` bench result 融合 runtime counters / queue wait / fallback / loaded instance（2026-03-17 已把 Quick Bench 卡片接上 runtime monitor explanation、queue、fallback、resident target、scope）
  - `LPR-W4-06-B` capability card：`Best for / Avoid for / Needs warmup / CPU fallback / Preview only`（2026-03-17 已补 capability builder，并接到 Quick Bench 面板与模型卡片 bench 徽标）
  - `LPR-W4-06-C` operator export：把 bench + monitor + load config 合成同一份报告（2026-03-17 已增强 `local_runtime_bench_summary` 导出，并给 Quick Bench 增加 `Copy Report` 当前模型能力报告）
- 当前进度：
  - `2026-03-24` revalidation：`LocalModelBenchMonitorExplanationTests`、`LocalModelBenchCapabilityCardTests`、`HubDiagnosticsBundleExporterTests` focused green；Quick Bench 面板、模型卡片 bench 徽标与 operator export 仍保持同一套 fused bench-monitor truth，可正式视为 delivered candidate
- 完成标准：
  - Bench 不再只告诉用户“快不快”，还能告诉用户“适合干什么、为什么失败、当前是否受资源限制”
  - 结论页可见 `task_kind + fixture + load_profile + runtime state`
  - 失败诊断能区分 `unsupported_task / missing_pack / runtime_missing / fallback_only / processor_init_failed`
- 交付物：
  - fused bench-monitor schema
  - capability card UI
  - export patch

#### `LPR-W4-07` MLX-VLM Provider Pack

- 目标：把“GLM-4.6V-Flash-MLX-4bit 这类本地视觉模型真的能 loaded 并跑能力测试”收口成正式工单。
- 参考：
  - 借 LM Studio 的 `mlx-llm + mlx-vlm` 路线
  - 不强行走当前 `transformers` provider
- 依赖：
  - `LPR-W4-01`
  - `LPR-W4-02`
  - `LPR-W3-01`
- 子工单：
  - `LPR-W4-07-A` `mlx_vlm` provider contract / capability matrix / model detection
  - `LPR-W4-07-B` image prompt / processor / residency / bench adapter
  - `LPR-W4-07-C` require-real: `GLM-4.6V-Flash-MLX-4bit` 或同类模型真实 load / bench / monitor
- 完成标准：
  - MLX 多模态模型不再只会被识别为“不支持”
  - 至少一类本地 MLX 视觉模型能真实完成 `add -> warmup/load -> run -> bench -> monitor`
  - image guard、policy、audit、kill-switch 全链路继续生效
- 交付物：
  - `mlx_vlm` provider pack
  - vision bench evidence
  - require-real evidence
- 当前状态（2026-03-25）：
  - `LPR-W4-07-A` 已交付：`mlx_vlm` provider contract / capability matrix / model detection 已接通；带 helper 的 MLX 视觉 / OCR 模型现在会优先落到 `mlx_vlm`，不再继续伪装成 `transformers`
  - `LPR-W4-07-B` 已交付：`mlx_vlm` helper-bridge 已补齐 `run_local_task` 的 `vision_understand / ocr` 合同覆盖；image prompt / multimodal message adapter、route trace / device backend truth、warmup residency 与 quick bench adapter 已对齐，Hub 侧 runtime guidance 也不再把 `mlx_vlm` 降级成 generic unavailable
  - 聚焦回归现已覆盖 `x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`、`x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`、`x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/LocalRuntimeProviderGuidanceTests.swift`、`LocalModelRuntimeCompatibilityPolicyTests` 与 `LocalModelBenchCapabilityPolicyTests`
  - `2026-03-24` 已补 blocker-aware require-real generator：`scripts/generate_lpr_w4_07_b_mlx_vlm_require_real_evidence.js` 现会把 `mlx_vlm` 的 helper bridge、模型目录完整性、native route probe 与 real execution capture 缺口统一收口到 `build/reports/lpr_w4_07_b_mlx_vlm_require_real_evidence.v1.json`
  - `2026-03-25` 当前 `LPR-W4-07-C` helper bridge 已恢复到 `ready_candidate=true`：`~/.lmstudio/settings.json` 现为 `enableLocalService=true`, `appFirstLoad=false`，真实 `lms daemon status` 返回 `llmster v0.0.6+1 is running (PID: 62130)`，`lms server status` 返回 `The server is running on port 1234.`
  - 所选 runtime 仍反解到 `/Users/andrew.xie/Documents/AX/Opensource/LM Studio.app`；当前 `codesign --verify --deep --strict` 已再次通过，bundle 仍带 `com.apple.quarantine`，但该点现只保留为环境细节，不再构成 helper 主阻塞
  - blocker-aware generator 的 app bundle 健康检查与状态词误判修正继续保留：`lms daemon status` / `lms server status` 的真实 running 输出现已被机读成 `daemon_running_signal=true`、`server_running_signal=true`
  - `2026-03-25` 现已补齐 helper bridge 的真实机收口缺口：`x-hub/python-runtime/python_service/helper_binary_bridge.py` 会先用 `lms ls --json` 把本地目录 / `indexedModelIdentifier` 反解到 CLI 真正接受的 `modelKey`，并把 `identifier already exists` / load timeout 但已驻留 这两条路径都机读成 idempotent success；`providers/transformers_provider.py` 也已把 `mlx_vlm` 的 helper load/chat timeout 拉长到真实多模态运行窗口
  - `2026-03-25` 真实 `LPR-W4-07-C` 已完成：`Qwen3-VL-4B-Instruct-3bit` 通过 helper bridge 完成 `warmup -> vision_understand -> ocr -> quick bench -> monitor`，原始证据位于 `build/reports/lpr_w4_07_c_real_run/`，其中 `capture_bundle.json` 与 `lms_ps_final.json` 已回填 live residency / monitor 证据
  - `2026-03-27` 当前分支已把 `build/reports/lpr_w4_07_c_real_run/capture_bundle.json` 重新真实生成出来：新增 `scripts/generate_lpr_w4_07_c_real_run_capture.js` 会统一落 `warmup -> vision_understand -> ocr -> quick bench -> monitor` 的 request/response 与 live helper 证据，不再依赖手工重拼历史 artifact
  - `2026-03-27` 真机复跑时已确认一个真实兼容点：当前 LM Studio vision helper load 不接受 `parallel > 1`；因此 `x-hub/python-runtime/python_service/relflowhub_local_runtime.py` 现会把 `mlx_vlm` 的 `vision_understand / ocr` effective load profile 自动 clamp 到 `parallel = 1`，避免 helper load 在真机上被 `numParallelSessions must be 1 for vision models` 直接打回
  - `2026-03-27` `scripts/generate_lpr_w4_07_b_mlx_vlm_require_real_evidence.js` 现把真实 capture 视为 closure truth，高于事后可能已经 idle/stale 的 helper preflight；因此当前 `build/reports/lpr_w4_07_b_mlx_vlm_require_real_evidence.v1.json` 会稳定保持 `PASS(mlx_vlm_require_real_closure_ready)`，即便生成报告时 helper daemon 已经自动收回
  - `build/reports/lpr_w4_07_b_mlx_vlm_require_real_evidence.v1.json` 当前机读结论已为 `PASS(mlx_vlm_require_real_closure_ready)`：`helper_bridge_ready=true`、`model_directory_ready=true`、`require_real_evidence_complete=true`
  - `LPR-W4-07` 现已达到 delivered/closure-ready，可继续把主优先级切到 `LPR-W4-08`

#### `LPR-W4-08` GGUF / llama.cpp Provider Pack

- 目标：给 Hub 增加第二条高价值的本地通用模型主线，覆盖 GGUF / llama.cpp 生态。
- 当前进展（`2026-03-25`）：
  - `LPR-W4-08-A` 已完成 `.gguf` 导入识别、`backend = llama.cpp` / `runtimeProviderID = llama.cpp` 映射与 metadata heuristic
  - Python runtime 已把 `llama.cpp` 从 preview/bootstrap 提升为 helper-backed provider：`text_generate` / `embedding` 走现有 helper bridge 链路，内建 provider pack manifest 现为 `installed`
  - Swift Hub/App 已去掉 `llama.cpp` 的静态 wiring guard，并补齐 auto-managed helper pack、provider guidance 与 benchability 真值；合格 GGUF text / embedding 模型不再被静态 fail-closed
  - `2026-03-25` 聚焦回归已通过：`python3 x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`、`swift test --package-path x-hub/macos/RELFlowHub --filter 'Local(ModelRuntimeCompatibilityPolicyTests|ModelBenchCapabilityPolicyTests|ProviderPackRegistryTests|RuntimeProviderGuidanceTests)'`、`node x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js`
  - `2026-03-26` 真机 `LPR-W4-08-B` 已补齐：`build/reports/lpr_w4_08_b_gguf_require_real_evidence.v1.json` 记录了真实 GGUF `warmup -> run-local-task -> helper server -> monitor snapshot` 闭环；`XHub local-runtime` 路径返回 `ok=true`、`vectorCount=1`、`dims=768`
  - 当前剩余主缺口已收敛到 `LPR-W4-09` 的迁移 / release exit；不再继续把 `llama.cpp` 整体标成 preview fail-closed
- 参考：
  - 借 LM Studio 的 `llama.cpp` engine pack 模式
- 依赖：
  - `LPR-W4-01`
  - `LPR-W4-03`
- 子工单：
  - `LPR-W4-08-A` GGUF import detection / provider mapping / model metadata extraction
  - `LPR-W4-08-B` llama.cpp local provider pack：text / embedding；vision 按模型能力 preview
  - `LPR-W4-08-C` bench / monitor / routing / require-real smoke
- 完成标准：
  - Hub 可识别 GGUF 模型并自动映射到 `llama.cpp` provider pack
  - GGUF 模型不需要被伪装成 MLX 或 Transformers
  - provider pack 缺失、模型不支持视觉、量化不兼容都必须明确 fail-closed
- 交付物：
  - `llama.cpp` provider pack
  - GGUF import path
  - helper-backed runtime truth checkpoint：`build/reports/lpr_w4_08_a2_llama_cpp_helper_runtime_truth_evidence.v1.json`
  - require-real smoke evidence：`build/reports/lpr_w4_08_b_gguf_require_real_evidence.v1.json`

#### `LPR-W4-09` Product Exit / Migration / Require-Real Closure

- 目标：把新旧本地模型产品面收口到同一条 operator-ready 退出标准。
- 当前进展（`2026-03-27`）：
  - `scripts/generate_lpr_w4_09_a_product_exit_matrix.js` 已落地，并生成 `build/reports/lpr_w4_09_a_product_exit_evidence.v1.json`
  - `2026-03-27` 当前 matrix 已对 `MLX VLM` 与 `GGUF / llama.cpp` 两个 cell 判定为 green，分别消费 `build/reports/lpr_w4_07_b_mlx_vlm_require_real_evidence.v1.json` 与 `build/reports/lpr_w4_08_b_gguf_require_real_evidence.v1.json`
  - `2026-03-27` 已补 `scripts/generate_lpr_w4_09_a_mlx_text_require_real_evidence.js` 与 `scripts/generate_lpr_w4_09_a_mlx_text_require_real_evidence.test.js`，并生成 `build/reports/lpr_w4_09_a_mlx_text_require_real_evidence.v1.json`：legacy MLX text 现已完成真机 `load -> text_generate -> legacy_text_bench -> runtime truth` release-facing closure
  - 当前 matrix 已不再把 `MLX text` 记为 blocker；剩余 fail-closed 只剩 `Transformers embed+ASR` 一个 release-facing require-real artifact 尚未在当前分支 `build/reports/` 下物化
- 依赖：
  - `LPR-W3-03`
  - `LPR-W4-06`
  - `LPR-W4-07`
  - `LPR-W4-08`
- 子工单：
  - `LPR-W4-09-A` real machine matrix：MLX text / MLX VLM / Transformers embed+ASR / GGUF
  - `LPR-W4-09-B` migration：旧 catalog / old bench / old runtime settings 向新 schema 迁移
  - `LPR-W4-09-C` release gate / operator runbook / support FAQ
- 完成标准：
  - 老用户升级后不会因为 schema 漂移失去模型或 bench 历史
  - 至少四类真实本地样本通过 `add -> load -> route -> bench -> monitor`
  - operator 有一份明确的“如何判断 pack 缺失 / runtime 缺失 / provider 不兼容”的 runbook
- 交付物：
  - migration scripts / compatibility reports
  - `build/reports/lpr_w4_09_a_product_exit_evidence.v1.json`
  - require-real matrix
  - release runbook

## 5) 八周排程（已完成 / 已在进行）

- W1：
  - `LPR-W1-01`
  - `LPR-W1-02`
- W2：
  - `LPR-W1-03`
  - `LPR-W1-04`
- W3：
  - `LPR-W1-05`
  - `LPR-W2-01`
- W4：
  - `LPR-W2-02`
  - `LPR-W2-03`
- W5：
  - `LPR-W2-04`
  - `LPR-W3-01`
- W6：
  - `LPR-W3-02`
  - `LPR-W3-04`
  - `LPR-W3-03`
- W7：
  - `LPR-W3-05`
  - `LPR-W3-08`
- W8：
  - `LPR-W3-07`
  - `LPR-W3-06`

## 5.1) 追加五周排程（LM Studio 对齐）

- W9：
  - `LPR-W3-03`
  - `LPR-W4-01`
- W10：
  - `LPR-W4-02`
  - `LPR-W4-03`
- W11：
  - `LPR-W4-04`
  - `LPR-W4-05`
- W12：
  - `LPR-W4-06`
  - `LPR-W4-07`
- W13：
  - `LPR-W4-08`
  - `LPR-W4-09`

## 6) 回归矩阵（最小集合）

### Correctness

- backend / task_kind / modality 匹配检查
- manifest 缺字段 / 错字段 / 版本不匹配
- 旧 MLX catalog 兼容迁移
- 旧 `generate` 请求兼容

### Security

- 自动下载默认关闭
- 未声明 capability 的本地任务被阻断
- secret 输入被未声明 `allow_secret_input` 的模型拒绝
- oversized audio/image 被拒绝
- provider 健康异常时 fail-closed

### Reliability

- provider 启停 / reload / unload
- MLX 与 Transformers 同时存在时状态汇总正确
- 单 provider 崩溃不导致 UI 误判全部本地能力失效
- provider-aware warmup / unload / idle eviction 行为可解释
- loaded instance inventory 与 scheduler telemetry 一致
- task routing source 与 resolved model 一致

### Performance

- embeddings batch latency
- ASR 单文件 latency
- provider load time
- provider 切换后的 first-task latency
- quick bench 冷启动 / 热启动差异
- runtime monitor 刷新不导致 UI 卡顿或高频 IO 抖动

## 7) 里程碑 DoD

M1 末：
- `LPR-G0`、`LPR-G1` 全绿

M2 末：
- `LPR-G2`、`LPR-G3` 全绿

M3 末：
- `LPR-G4`、`LPR-G5`、`LPR-G6` 全绿

M4 末：
- `LPR-G7`、`LPR-G8` 全绿

M5 末：
- `LPR-G9`、`LPR-G10` 全绿

## 8) 当前建议执行顺序（从 2026-03-24 状态继续）

如果从当前仓库状态继续推进，而不是回到 v1 起点，顺序固定为：

1. `LPR-W4-03` typed load config / loaded instance contract
2. `LPR-W3-03` require-real
3. `LPR-W4-07` `mlx_vlm` provider pack
4. `LPR-W4-08` `llama.cpp` / GGUF provider pack
5. `LPR-W4-09` product exit / migration / require-real closure

这个顺序的原因：

- `LPR-W4-01` 与 `LPR-W4-02` 已经把 provider pack / runtime inventory 主合同补成 machine-readable；当前主线缺口不再是 schema 缺席，而是 typed load config 在 Hub / X-Terminal consumer 面还没有完全收口。
- `LPR-W3-03` 仍然重要，但它当前更像 release credibility 平行收口线，而不是唯一的产品面入口；主线产品推进应先继续把 `W4-03-B/C` 做到真实可见、可消费、可复制。
- 先做 `typed load config` 再做后续 UI/console，是为了避免又把 `context_length`、`ttl`、`parallel` 写成一批 UI 特判；当前 `LPR-W4-04 / W4-05 / W4-06` 已在这条主线之上完成候选收口，不再占据下一步 feature backlog。
- `loaded models console` 与 bench-monitor 融合都已经进入 delivered candidate，因此前向功能主线转为新 provider pack，而不是继续停留在已有 Hub 产品面润色。
- `mlx_vlm` 排在 `llama.cpp` 前，是因为它直接对应你当前最紧的真实目标：让本地 MLX 视觉模型真的能 loaded 和 bench。
