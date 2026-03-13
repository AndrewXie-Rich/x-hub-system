# X-Hub Local Provider Runtime + Transformers Integration 执行工单

- version: v1.0
- updatedAt: 2026-03-12
- owner: Hub Runtime / Memory / Security / QA
- status: planned
- scope: local provider runtime、provider-aware model catalog、Transformers embeddings/audio/vision、policy/audit/doctor/release gate
- parent:
  - `docs/xhub-local-provider-runtime-and-transformers-integration-v1.md`
  - `docs/xhub-runtime-stability-and-launch-recovery-v1.md`
  - `docs/xhub-memory-system-spec-v2.md`
  - `docs/xhub-hub-architecture-tradeoffs-v1.md`
  - `docs/xhub-multi-model-orchestration-and-supervisor-v1.md`

## 0) 目标与边界

目标（本轮）
- 把 X-Hub 的本地模型执行面从“MLX-only runtime”升级为 `Local Provider Runtime`（LPR）。
- 让本地模型不再只覆盖文本生成，还能承接 `embeddings / speech_to_text / vision_understand / ocr` 等专业任务。
- 保持 Hub-first：本地专业模型能力也必须继续服从 Hub 的 policy / audit / kill-switch / routing / diagnostics。
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

## 3) Gate 与 KPI

### 3.1 Gate（沿用 spec 的 LPR-G0..G6）

- `LPR-G0`：Schema Freeze
- `LPR-G1`：MLX Compatibility
- `LPR-G2`：Transformers Embeddings
- `LPR-G3`：Transformers Audio
- `LPR-G4`：Transformers Vision
- `LPR-G5`：Security / Governance
- `LPR-G6`：Require-Real

### 3.2 KPI

- `local_provider_runtime_false_green_rate = 0`
- `mlx_regression_rate = 0`
- `local_embeddings_success_rate >= 0.99`
- `local_asr_success_rate >= 0.99`
- `provider_mismatch_route_count = 0`
- `local_task_unaudited_count = 0`
- `unauthorized_local_modality_execution = 0`
- `auto_online_model_download_count = 0`

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

## 5) 六周排程（建议）

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
  - `LPR-W3-03`

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

### Performance

- embeddings batch latency
- ASR 单文件 latency
- provider load time
- provider 切换后的 first-task latency

## 7) 里程碑 DoD

M1 末：
- `LPR-G0`、`LPR-G1` 全绿

M2 末：
- `LPR-G2`、`LPR-G3` 全绿

M3 末：
- `LPR-G4`、`LPR-G5`、`LPR-G6` 全绿

## 8) 当前建议执行顺序

如果只允许先做一条最稳的主链，顺序固定为：

1. schema/status freeze
2. backend-aware Add Model
3. local provider runtime skeleton
4. MLX compatibility gate
5. embeddings
6. ASR
7. vision preview

这个顺序的原因很简单：
- 先冻 schema，避免 Swift / Python / Node 并行漂移
- 先保住 MLX，再扩展 Transformers
- 先做 embeddings，是因为它和 Memory v2/v3 的系统性价值最大
