# X-Hub Local Provider Runtime + Transformers Integration v1（可执行规范 / Draft）

- Status: Draft
- Updated: 2026-03-15
- Applies to: X-Hub macOS App（SwiftUI）+ embedded Node gRPC server + `x-hub/python-runtime/python_service/` + local model catalog / runtime status / Hub policy & audit
- Decision (2026-03-12):
  - **MLX 保持本地文本生成主路径**
  - **新增 Transformers Adapter 作为第二本地 backend**
  - **v1 默认严格离线**：只加载“本地已存在”的模型目录；不默认联网下载
  - **Hub 仍是唯一可信控制面**：X-Terminal / Generic clients 不得直接加载本地 Transformers 模型绕过 Hub

> 目标：把 X-Hub 从“本地模型基本等于 MLX”升级成“Hub 统一治理的 Local Provider Runtime”，从而支持本地 embeddings、音频、视觉/OCR 等专业模型，同时不破坏 Hub-first 的安全、审计、路由和 kill-switch 边界。

依赖与相关文档：
- `protocol/hub_protocol_v1.md`
- `docs/xhub-runtime-stability-and-launch-recovery-v1.md`
- `docs/xhub-memory-system-spec-v2.md`
- `docs/xhub-client-modes-and-connectors-v1.md`
- `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
- `docs/memory-new/xhub-local-provider-runtime-transformers-implementation-pack-v1.md`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelModels.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/AddModelSheet.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
- `x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`

---

## 0) 范围与非目标

### 0.1 v1 必须解决的问题

当前仓库里，“协议层允许多 backend”与“本地 runtime 实际只服务 MLX”之间存在明显落差：
- 协议和模型 catalog 已允许 `backend` 扩展，不限于 `mlx`
- Hub UI 的“Add Model”与本地 runtime 健康判断，仍主要按 MLX 语义编写
- Hub 内部本地生成链路默认把 `local runtime ready` 等同于 `mlxOk=true`
- Memory v2/v3 已经需要本地 embeddings，但当前本地 runtime 仍未升级为多 provider 抽象

v1 必须把以下四件事收敛为一套唯一实现：
1. 本地模型 backend 抽象
2. 本地模型能力声明（task/modality/capability）
3. 运行时健康、加载、执行、审计的一致协议
4. 与 Hub policy / grants / kill-switch / audit 的一致接线

### 0.2 v1 要覆盖的能力

v1 的正式范围：
- MLX：继续承载本地 `text_generate`
- Transformers：新增本地 `embedding`
- Transformers：新增本地 `speech_to_text`
- Transformers：预留本地 `vision_understand` / `ocr` 能力声明与路由接口

说明：
- `vision_understand` / `ocr` 可以在 v1 中以 preview 方式落地，不要求一开始支持所有视觉模型
- `text_generate` 的 Transformers 适配在 v1 不是硬要求；它可以放到 v1.1/v2

### 0.3 v1 不做

v1 明确不做：
- 不做 Hugging Face / ModelScope / 其它 registry 的自动在线下载
- 不做“任意第三方 Python pipeline 都能塞进 Hub”的开放插件系统
- 不做本地图像生成、视频生成、TTS 全家桶
- 不把 X-Terminal 变成直接操控本地模型的信任面
- 不因支持 Transformers 而弱化 Hub policy / audit / kill-switch

---

## 1) 唯一架构（Canonical）

### 1.1 新的唯一名词：Local Provider Runtime（LPR）

从本规范起，X-Hub 本地模型执行面统一命名为：
- **Local Provider Runtime（LPR）**

它不是“MLX runtime + 一些补丁”，而是：
- 一个 Hub 管理的本地执行调度层
- 其下挂多个 provider adapter
- 由 Hub UI / Hub gRPC / Hub policy 统一调用

### 1.2 架构分层

唯一推荐分层：

1. **Hub Control Plane**
   - SwiftUI Hub App
   - embedded Node gRPC server
   - policy / grants / audit / kill-switch / routing

2. **Local Provider Runtime（调度层）**
   - provider 注册
   - 任务路由
   - 健康汇总
   - 加载/卸载/并发控制
   - 统一的文件 IPC / 本地 RPC 契约

3. **Provider Adapters（执行层）**
   - `mlx`
   - `transformers`
   - future: `onnx` / `llama_cpp` / specialized local runtime

4. **Provider Workers（可选拆分）**
   - 单独子进程承载重依赖
   - 避免把所有 Python 依赖硬塞进一个脚本

### 1.3 规范性要求

- `relflowhub_mlx_runtime.py` 不再被视作未来唯一 runtime 入口
- v1 必须新增一个更高层的运行时入口，例如：
  - `relflowhub_local_runtime.py`
- `mlx` 必须收敛成 provider adapter，而不是继续代表“全部本地能力”

### 1.4 外部参考基线（LM Studio / OpenCode）

X-Hub 可以借 `LM Studio` 与 `OpenCode` 的产品做法，但只借模式，不直接替换当前 Hub-first 架构。

固定借用：
- 从 LM Studio 借 `provider pack / engine manifest`
- 从 LM Studio 借 `typed load config`
- 从 LM Studio 借 `ModelInfo` 与 `LoadedInstanceInfo` 分层
- 从 LM Studio 借 `Loaded Models / Runtime Operations` 作为一等产品面
- 从 OpenCode 借 `provider_id + model_id` 身份、`capabilities / modalities / limits` 元数据形状
- 从 OpenCode 借 unsupported modality / unsupported task 的 fail-closed 行为

明确不借：
- 不把 LM Studio daemon 直接当成 X-Hub runtime
- 不把 OpenCode 的云端 auth / pricing / SaaS 假设带入本地模型主链
- 不把 backend/provider 手工选择保留成普通用户的日常主路径

2026-03-15 本机 LM Studio 安装体已验证：
- 它是 `daemon + domain workers + engine extensions`
- 已能看到独立 worker：`llmworker / embeddingworker / asrworker / imagegenworker`
- 已能看到独立 engine manifest：`mlx-llm / llama.cpp`
- MLX engine release 记录长期跟踪 `mlx-vlm`

这直接说明：
- X-Hub 不该继续把“MLX 文本”和“MLX 视觉”当成同一个黑盒
- `mlx_vlm` 与 `llama.cpp` 必须走 pack-aware 扩展路线，而不是再做两次散装集成

---

## 2) Provider 抽象（唯一接口）

### 2.1 Provider 类型

v1 统一使用以下 provider 类型：
- `mlx`
- `transformers`
- `remote`（仅用于与远程 provider 语义对齐；不属于本规范实现重点）

### 2.2 Provider 接口（Hub 内部规范）

Provider 必须实现以下最小接口：

```text
provider_id() -> string
supported_task_kinds() -> string[]
supported_input_modalities() -> string[]
supported_output_modalities() -> string[]
healthcheck() -> ProviderHealth
list_registered_models() -> ModelDescriptor[]
load_model(model_id, opts) -> LoadResult
unload_model(model_id) -> UnloadResult
run_task(request) -> TaskResult | TaskStream
```

说明：
- `run_task` 是唯一执行入口；不要为每个 provider 发明完全不同的私有执行协议
- `generate/embed/transcribe/vision_analyze/rerank` 等都视为 `run_task` 的 task kinds

### 2.3 ProviderHealth（必须机器可判）

Provider 健康信息最小字段：
- `provider`
- `ok`
- `reason_code`
- `runtime_version`
- `available_task_kinds[]`
- `loaded_models[]`
- `device_backend`（`cpu|mps|metal|unknown`）
- `updated_at`

---

## 3) 任务模型（Task Kinds / Modalities）

### 3.1 Canonical task kinds

本地任务统一收敛到以下枚举：
- `text_generate`
- `embedding`
- `rerank`
- `speech_to_text`
- `vision_understand`
- `ocr`
- `classify`

### 3.2 输入输出模态

统一模态字段：
- 输入：`text | image | audio`
- 输出：`text | embedding | labels | spans | segments | scores`

### 3.3 v1 支持矩阵

| task_kind | mlx | transformers | v1 要求 |
| --- | --- | --- | --- |
| `text_generate` | Yes | Optional | MLX 必做 |
| `embedding` | Optional | Yes | Transformers 必做 |
| `rerank` | No | Optional | 可后置到 v1.1 |
| `speech_to_text` | No | Yes | Transformers 必做 |
| `vision_understand` | No | Preview | v1 预留，v1.1 建议落地 |
| `ocr` | No | Preview | v1 预留，v1.1 建议落地 |
| `classify` | Optional | Optional | 后置 |

规范要求：
- Hub 不得把 `speech_to_text`、`vision_understand` 之类任务伪装成 `text_generate`
- 若请求 task_kind 与模型能力不匹配，必须 `fail_closed`

---

## 4) 模型注册与能力声明（必须从“模型路径”升级为“能力声明”）

### 4.1 现状问题

当前 local model 注册主要围绕以下字段：
- `id`
- `name`
- `backend`
- `quant`
- `contextLength`
- `paramsB`
- `modelPath`

这对 MLX LLM 足够，但对音频、视觉、embedding 模型明显不够。

另外，当前 `contextLength` 还是一个混合语义字段：
- 有时被当作“模型能力上限”
- 有时被当作“当前加载配置”
- 有时又被 UI 当作“推荐默认值”

一旦 Hub 需要给不同 paired terminal 设备设置不同的本地上下文长度，这三个语义必须拆开，否则同一模型会出现“catalog 静态元数据”和“设备运行态”互相覆盖的问题。

### 4.2 ModelDescriptor（v1 必须新增的字段）

`ModelCatalogEntry` / `HubModel` 必须扩展以下字段：
- `backend`
- `model_format`（`mlx|hf_transformers|gguf|onnx|other`）
- `max_context_length`（若 provider / manifest 可判）
- `default_load_profile`
  - `context_length`
  - `gpu_offload`
  - `rope_frequency_base`
  - `rope_frequency_scale`
  - `eval_batch_size`
- `task_kinds[]`
- `input_modalities[]`
- `output_modalities[]`
- `offline_ready`
- `resource_profile`
  - `preferred_device`
  - `memory_floor_mb`
  - `dtype`
- `trust_profile`
  - `allow_secret_input`
  - `allow_remote_export`
- `processor_requirements`
  - `tokenizer_required`
  - `processor_required`
  - `feature_extractor_required`

兼容要求：
- 现有 `contextLength` 字段在迁移期继续保留
- 其 canonical 语义改为 `default_load_profile.context_length` 的兼容别名
- “模型能力上限”不得再复用 `contextLength`，应使用 `max_context_length`

### 4.3 本地 manifest（推荐强制）

每个本地模型目录建议包含：
- `xhub_model_manifest.json`

示例：

```json
{
  "schema_version": "xhub_model_manifest.v1",
  "backend": "transformers",
  "model_format": "hf_transformers",
  "task_kinds": ["speech_to_text"],
  "input_modalities": ["audio"],
  "output_modalities": ["text", "segments"],
  "offline_ready": true,
  "resource_profile": {
    "preferred_device": "mps",
    "memory_floor_mb": 4096,
    "dtype": "float16"
  },
  "processor_requirements": {
    "tokenizer_required": false,
    "processor_required": true,
    "feature_extractor_required": true
  }
}
```

### 4.4 Hub UI 行为

`Add Model` 的 canonical 产品路径必须从“手工选 backend/role”演进成“自动探测 + capability-first 导入”。

兼容期允许：
- 在 debug / advanced 面板里手工 override backend/provider
- 在旧 UI 未完全收口前暂时保留显式 backend 选择

正式路径最低要求：
1. 用户选择本地模型目录
2. Hub 自动探测 manifest / format / provider candidate / task kinds / modalities / runtime pack readiness
3. 推断失败时阻断导入，并返回 machine-readable reason
4. `Role` 与 `Backend Override` 不得继续作为普通导入路径的前置步骤

backend-aware 校验仍然必须存在，但应作为自动探测后的内部校验，而不是普通用户第一步：

最低要求：
- `MLX`
  - 校验 `config.json`
  - 兼容现有导入流程
- `Transformers`
  - 校验 `config.json`
  - 校验 tokenizer / processor / feature_extractor 中至少满足该 task 所需组合
  - 若缺失 manifest，则 Hub 尝试推断；推断失败必须阻断导入

### 4.5 Canonical 分层：Model Identity != Load Profile

参考 LM Studio 这类本地模型产品，X-Hub v1 后续演进必须固定以下唯一分层：

1. **Model Identity（静态工件身份）**
   - `model_id`
   - `model_path`
   - `backend`
   - `model_format`
   - `task_kinds`
   - `input/output modalities`
   - `trust_profile`
   - `resource_profile`
   - `max_context_length`

2. **Hub Default Load Profile（Hub 默认加载配置）**
   - 属于 Hub 控制面默认值
   - 可由 operator 在 Hub 上设置
   - 用于未显式配置 terminal 设备 override 的场景

3. **Terminal Device Load Profile Override（设备级加载配置）**
   - key 必须至少包含：`device_id + model_id`
   - 只允许覆盖 machine-dependent / runtime-dependent 参数
   - v1 首批至少允许：
     - `context_length`
   - v1.1/v2 可继续扩到：
     - `gpu_offload`
     - `rope_frequency_base`
     - `rope_frequency_scale`
     - `eval_batch_size`
     - `flash_attention`

强制要求：
- paired terminal 不得直接改写 `models_catalog.json` 中的模型身份字段
- 设备级 override 不得写进 `trust_profile` 或模型 manifest
- `max_context_length`、`task_kinds`、`model_path` 之类静态字段不允许被 terminal 设备覆盖

推荐新增单独存储，而不是复用 model catalog：
- `hub_paired_terminal_local_model_profiles.json`

原因：
- trust/pairing profile 属于授权与身份域
- local load profile 属于运行调优域
- 两者更新频率、审计口径和冲突策略不同，不应混写

### 4.6 Provider Pack / Runtime Bundle / Loaded Instance Contract（W4 基线）

为了避免 `mlx_vlm`、`llama.cpp` 和后续 provider 再次退化成一次性接入，W4 起固定以下结构：

1. **Provider Pack / Engine Manifest**
   - 记录 `provider_id / engine / version / supported_formats / supported_domains / runtime_requirements`
   - Hub / runtime / diagnostics 必须共享同一份 installed-pack truth

2. **Provider-owned Runtime Bundle**
   - provider 可以声明自己依赖的 `python / wheel bundle / helper binary / native dylib`
   - 运行态必须明确区分：
     - `pack_runtime_ready`
     - `user_runtime_fallback`
     - `runtime_missing`

3. **ModelInfo vs LoadedInstanceInfo**
   - `ModelInfo` 只表达磁盘上的静态模型信息
   - `LoadedInstanceInfo` 只表达内存里当前实例、effective load config、ttl、progress、last_used
   - Hub UI 不得再混用两套语义

4. **Loaded Instance Inventory**
   - `warmup / unload / evict / bench / monitor` 都必须读同一份 loaded-instance truth
   - provider pack、runtime bundle、load config source 也必须能挂到实例视图上解释

---

## 5) 运行时协议（Runtime Contract）

### 5.1 兼容原则

现有 `type=generate` 文件 IPC 不得被粗暴删除。

v1 兼容要求：
- 旧 `generate` 请求继续可用
- 新能力统一走更通用的 envelope
- 推荐新增：
  - `type=run_local_task`

兼容映射：
- `generate` == `run_local_task(task_kind=text_generate)`

### 5.2 Canonical request

```json
{
  "type": "run_local_task",
  "req_id": "uuid",
  "task_kind": "speech_to_text",
  "preferred_model_id": "transformers/whisper-large-v3-local",
  "input": {
    "audio_path": "/tmp/clip.wav"
  },
  "options": {
    "language": "en",
    "timestamps": true
  },
  "created_at": 0
}
```

### 5.3 Canonical response

必须支持两类返回：
- 单次结果：`result`
- 流式结果：`delta* -> done`

示例：

```json
{
  "type": "done",
  "req_id": "uuid",
  "ok": true,
  "task_kind": "speech_to_text",
  "model_id": "transformers/whisper-large-v3-local",
  "provider": "transformers",
  "usage": {
    "input_audio_sec": 12.4,
    "latency_ms": 1830
  }
}
```

### 5.4 Runtime status（必须从 `mlxOk` 升级）

当前 `ai_runtime_status.json` 语义偏 MLX。v1 必须升级为 provider-aware：

```json
{
  "schema_version": "xhub.local_runtime_status.v2",
  "runtime_alive": true,
  "runtime_version": "2026-03-12-local-provider-runtime-v1",
  "providers": {
    "mlx": {
      "ok": true,
      "reason_code": "",
      "available_task_kinds": ["text_generate"]
    },
    "transformers": {
      "ok": true,
      "reason_code": "",
      "available_task_kinds": ["embedding", "speech_to_text"]
    }
  },
  "updated_at": 0
}
```

硬要求：
- UI 不得再把“本地 runtime 可用”简化成 `mlxOk`
- 若 MLX 不可用但 Transformers 可用，Hub 必须明确呈现“部分本地能力可用”

### 5.5 Loaded Instance Identity（新增）

一旦引入 per-device `context_length` 等 load profile，同一个 `model_id` 不能再被假定为“全局只有一个唯一加载实例”。

v1 后续规范要求：
- runtime loaded instance 的 canonical key 必须至少包含：
  - `provider`
  - `model_id`
  - `load_profile_hash`
- scheduler 应优先复用 effective load profile 完全相同的已加载实例
- 当两个 terminal 设备对同一模型要求不同 `context_length` 时：
  - 若资源允许，可保留多个 loaded instances
  - 若资源不允许，按 `LPR-W3-02` 资源策略执行 `queue / reject / unload-then-load`

这样做的目的：
- 避免 A 设备把 `context_length` 改成 32k 后，B 设备正在使用的 8k 实例被隐式篡改
- 让 scheduler 能基于 profile hash 正确估算资源占用和实例复用率
- 让 doctor / diagnostics 能解释“模型已加载，但当前设备 profile 不匹配”的状态

---

## 6) 路由与策略（Hub-first，不允许退化成 terminal-first）

### 6.1 路由输入

本地任务路由最小输入：
- `task_kind`
- `input_modality`
- `device_id`
- `preferred_model_id`（可选 hint）
- `policy profile`
- `sensitivity`
- `device capability`

### 6.2 路由规则

规范顺序：
1. 按 `task_kind` 过滤
2. 按 `input/output modalities` 过滤
3. 按 `policy / sensitivity / trust_profile` 过滤
4. 按 provider 健康与资源可用性过滤
5. 再考虑 `preferred_model_id`

说明：
- `preferred_model_id` 只是 hint，不得绕过能力/策略检查
- `text_generate` 不能抢占 `speech_to_text` / `vision_understand` 的请求

### 6.3 Effective Load Profile Resolution（新增）

当请求命中本地 provider 时，Hub 必须先解析 effective load profile，再决定是否复用已加载实例。

唯一推荐合并顺序：
1. provider safe defaults
2. model descriptor 的 `default_load_profile`
3. paired terminal 的 `device_id + model_id` override
4. request 级临时 hint（仅在 policy 显式允许时）

强制要求：
- 若 override 超过 `max_context_length` 或 provider 可接受上限，保存阶段必须阻断
- 若 runtime 发现 provider 的真实上限低于 catalog 记录，可 runtime clamp，但必须写审计并暴露 `load_profile_clamped=true`
- 不得 silent mutate 全局 model catalog 来表达某一台 terminal 的加载偏好

### 6.4 capability 划分（必须细化）

本地任务 capability 不得全部塞进一个 `ai.generate.local`。

v1 建议至少拆成：
- `ai.generate.local`
- `ai.embed.local`
- `ai.audio.local`
- `ai.vision.local`

原因：
- 音频/视觉输入体积、资源占用、风险面都和文本生成不同
- 后续 policy、配额、kill-switch 需要单独控制

### 6.5 kill-switch

v1 必须支持以下最小 kill-switch 粒度：
- 禁用全部本地任务
- 禁用某个 provider（如 `transformers`）
- 禁用某类 task（如 `ai.audio.local`）

---

## 7) 安全与治理（必须 fail-closed）

### 7.1 v1 安全原则

1. 所有本地模型调用仍必须经过 Hub
2. 默认离线
3. 默认无自动下载
4. 模型目录必须可审计、可定位、可 hash
5. task/modality/manifest 不匹配时一律阻断

### 7.2 输入约束

针对多模态任务，必须新增输入约束：
- `audio`
  - 最大时长
  - 最大文件大小
  - 允许格式白名单
- `image`
  - 最大像素
  - 最大文件大小
  - 允许格式白名单

### 7.3 secret 与本地多模态

原则：
- `secret` 数据默认优先允许本地处理，不允许被路由到远程
- 但并不意味着“任何本地模型都能吃 secret”

因此模型 manifest 必须声明：
- `allow_secret_input=true|false`

默认策略：
- 未声明时按 `false`
- 只有明确声明、且 policy 允许时，才可处理 secret 级输入

### 7.4 审计

每个本地任务至少审计：
- `req_id`
- `task_kind`
- `provider`
- `model_id`
- `input_modality`
- `input_size_bytes`
- `policy_decision`
- `latency_ms`
- `deny_code`（若失败）

不得默认审计明文音频、图像或原始大文本。

---

## 8) 资源与并发（不要把多模态运行时做成不透明黑盒）

### 8.1 资源画像

每个模型必须声明最小资源需求：
- `memory_floor_mb`
- `preferred_device`
- `estimated_load_ms`
- `supports_concurrent_requests`

### 8.2 调度规则

v1 建议：
- 同一 provider 默认串行加载重模型
- `embedding` 可批处理
- `speech_to_text` 默认限制并发为 1
- `vision_understand` 默认限制并发为 1

### 8.3 Apple Silicon 与 Intel

产品口径保持不变：
- X-Hub 主推荐平台仍是 Apple Silicon desktop Macs

v1 规范要求：
- 不要求把 Intel 变成本地大模型正式支持平台
- 允许将小型 `embedding` / `speech_to_text` 以 CPU fallback 作为开发能力，但不得默认承诺生产可用

### 8.4 Per-Device Load Profile 与调度协同

per-device local load profile 不是单纯 UI 偏好，它必须直接接入资源调度：

- `context_length` 提升会改变 KV cache / 内存占用估算
- `gpu_offload` / `eval_batch_size` 后续引入时也会改变实例占用与并发上限
- 因此 scheduler 的资源画像必须基于 effective load profile，而不是只看 `model_id`

v1 要求：
- diagnostics 至少展示：
  - `max_context_length`
  - `default_context_length`
  - `effective_context_length`
  - `effective_profile_source`（`provider_default|hub_default|device_override|request_hint`）
- paired terminal 设备修改 local load profile 后：
  - Hub 必须重新评估资源是否允许
  - 若不允许，必须显式拒绝或排队，不得静默降级成另一个上下文长度
- X-Terminal UI 不得直接声称“上下文已改为 32k”，除非 Hub 已返回已生效的 effective profile

---

## 9) 与现有代码的迁移方案（必须渐进式）

### 9.1 现有文件保留

以下资产在 v1 中继续保留：
- `relflowhub_mlx_runtime.py`
- `models_catalog.json`
- `models_state.json`
- 现有 MLX load/unload/generate 流程

### 9.2 新增入口

v1 推荐新增：
- `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
- `x-hub/python-runtime/python_service/providers/base.py`
- `x-hub/python-runtime/python_service/providers/mlx_provider.py`
- `x-hub/python-runtime/python_service/providers/transformers_provider.py`
- `hub_paired_terminal_local_model_profiles.json`（或同级单独存储）

### 9.2.1 `contextLength` 迁移口径（新增）

为了避免一次性推翻现有 UI / catalog：

1. 现有 `ModelCatalogEntry.contextLength` / `HubModel.contextLength`
   - 暂继续保留
   - 视为 `default_load_profile.context_length` 的兼容映射
2. 后续 provider / manifest 若能给出能力上限：
   - 新增 `max_context_length`
3. paired terminal 的设备级差异：
   - 进入独立的 local load profile store
   - 不写回 model catalog

迁移目标很明确：
- catalog 表示“这是什么模型 + Hub 默认怎么加载”
- runtime state 表示“当前加载了哪些 instance + effective context 是多少”
- paired terminal profile 表示“某台 terminal 想怎么用这台 Hub 的本地模型”

### 9.3 Swift 侧必须修改的入口

最低改动面：
- `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelModels.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/AddModelSheet.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/AIRuntimeStatus.swift`

### 9.4 Node / gRPC 侧必须修改的入口

最低改动面：
- `x-hub/grpc-server/hub_grpc_server/src/mlx_runtime_ipc.js`
  - 需要升级为 provider-aware 的 local runtime IPC bridge
- `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - 需要支持本地多 task 能力与更细 capability/audit

### 9.5 兼容原则

- v1 期间允许 `mlx_runtime_ipc.js` 名字暂不改，但内部语义必须兼容多 provider
- 对外 `models_state.json` 仍作为统一模型可见性快照
- 老 UI/老测试若只识别 `mlx`，必须保持不崩溃；未知 backend 至少可显示为可见但不可操作，不能 silent discard

---

## 10) 分期（建议按里程碑执行）

### M0：Spec + Schema Freeze

完成标准：
- 冻结本文件
- 冻结 `ModelDescriptor` 扩展字段
- 冻结 `task_kind` / `modality` 枚举
- 冻结 runtime status v2

### M1：Local Provider Runtime 骨架

完成标准：
- `relflowhub_local_runtime.py` 可启动
- `mlx_provider` 接通现有 MLX 路径
- provider-aware health/status 落地
- MLX 现有功能无回归

### M2：Transformers Embeddings

完成标准：
- 支持本地已下载 embeddings 模型加载
- 与 Memory v2 的本地 embeddings 路径接通
- `ai.embed.local` capability / audit / kill-switch 生效

### M3：Transformers Audio（ASR）

完成标准：
- 支持本地已下载 ASR 模型加载
- `speech_to_text` 请求链路、审计、输入限制、失败语义落地

### M4：Transformers Vision Preview

完成标准：
- 支持至少一种 `vision_understand` 或 `ocr`
- 图像输入白名单与上限生效
- capability 与审计闭环完整

### M5：Require-Real + Release Gate

完成标准：
- 真机样本验证
- 至少 1 个 embeddings、1 个 audio、1 个 vision 样例通过
- Hub diagnostics 能明确区分 `mlx unavailable` 与 `transformers unavailable`

### M6：Managed Provider Pack + Typed Load Config

完成标准：
- `mlx`、`transformers` 迁入 installed provider pack registry
- provider runtime bundle 状态可被 doctor / diagnostics / monitor 一致解释
- `context_length / ttl / parallel / gpu_offload` 进入 typed load config
- `ModelInfo` 与 `LoadedInstanceInfo` 正式分层

### M7：Loaded Instance UX + Bench / Monitor Fusion

完成标准：
- Add Model 正常路径改成 auto-detect + capability-first
- Loaded Models / Runtime Operations 成为一等 UI
- Bench 与 Monitor 共享同一份 loaded-instance / load-config truth
- 普通用户不再需要手工选择 backend/provider

### M8：Expanded Provider Coverage（`mlx_vlm` / `llama.cpp`）

完成标准：
- 至少一类真实 MLX 视觉模型可完成 `add -> load -> route -> bench -> monitor`
- GGUF 模型可被识别并映射到 `llama.cpp` provider pack
- 新 provider 继续走相同 policy / audit / kill-switch / diagnostics 主链

### M9：Product Exit / Migration

完成标准：
- 旧 catalog / bench / runtime settings 能迁移到新 schema
- real-machine matrix 覆盖 MLX 文本、MLX 视觉、Transformers embed+ASR、GGUF
- operator runbook 可明确区分 `missing_pack / runtime_missing / provider_mismatch / unsupported_task`

---

## 11) 验收门禁（LPR-G0..G10）

### LPR-G0 Schema Freeze
- `task_kind` / `modality` / model manifest / runtime status v2 冻结

### LPR-G1 MLX Compatibility
- 原有 MLX load/unload/generate 行为不回退

### LPR-G2 Transformers Embeddings
- 本地 embeddings 可跑通
- Memory v2 可消费

### LPR-G3 Transformers Audio
- 本地 ASR 可跑通
- 输入限制、审计、deny_code 完整

### LPR-G4 Transformers Vision
- 本地图像理解/OCR 至少 1 条主链跑通
- 输入限制、审计、deny_code 完整

### LPR-G5 Security / Governance
- 无自动下载
- 无 terminal bypass
- capability / kill-switch / audit 全闭环

### LPR-G6 Require-Real
- 真机样本与真实本地模型目录完成演练
- 诊断与 root-cause 可定位

### LPR-G7 Managed Provider Pack / Engine Manifest
- installed provider pack registry 成立
- `mlx`、`transformers` 至少走 pack inventory
- pack 缺失、版本不兼容、依赖缺失都有 machine-readable reason

### LPR-G8 Typed Load Config / Loaded Instance UX
- `context_length / ttl / parallel / gpu_offload` 进入 typed load config
- `ModelInfo` 与 `LoadedInstanceInfo` 明确分层
- Hub 可显示 loaded instances、load config source、ttl、progress、last_used

### LPR-G9 Expanded Provider Coverage
- `mlx_vlm` 至少一类真实模型可 load / run / bench / monitor
- `llama.cpp` / GGUF 至少一类真实模型可 import / run / bench / monitor
- 新 provider 不得绕过 Hub-first policy / audit / kill-switch

### LPR-G10 Product Exit / Migration / Operator Usability
- 旧用户升级后不会因为 schema 变化丢模型或 bench 历史
- 至少四类真实本地样本完成 `add -> load -> route -> bench -> monitor`
- operator 有明确 runbook，可解释 pack/runtime/provider 层失败原因

---

## 12) 推荐的下一阶段实现顺序（按 2026-03-15 仓库状态）

如果从当前仓库状态继续推进，而不是回到 v1 起点，顺序固定为：

1. `LPR-W3-04` residual closure（补齐 legacy MLX IPC 与 load-profile-aware lifecycle 收口）
2. `LPR-W3-03` require-real
3. `LPR-W4-01` managed provider pack / engine manifest
4. `LPR-W4-02` managed runtime bundle / dependency isolation
5. `LPR-W4-03` typed load config / loaded instance contract
6. `LPR-W4-04` Add Model / library UX simplification
7. `LPR-W4-05` loaded models / runtime operations console
8. `LPR-W4-06` bench + monitor fusion
9. `LPR-W4-07` `mlx_vlm` provider pack
10. `LPR-W4-08` `llama.cpp` / GGUF provider pack
11. `LPR-W4-09` product exit / migration / require-real closure

原因：
- 先补 `W3-04/W3-03`，避免当前主线在 require-real 之前继续扩张
- 先做 provider pack，再做新 provider，避免 `mlx_vlm` 与 `llama.cpp` 继续散装集成
- 先做 typed load config，再做 UI，避免 `context_length` 一类字段再次分散到多个临时控件
- 先做 loaded-instance console，再做 bench-monitor 融合，才能保证用户看到的是同一份运行态真相

---

## 13) 结论（v1 的唯一口径）

本地模型能力的正确升级方向不是“在 MLX runtime 里继续加 if/else 支持 transformers”，而是：

- 用 **Local Provider Runtime** 统一承载本地 provider
- 用 **Transformers Adapter** 承接非 MLX 的 embeddings / audio / vision 专业模型
- 用 **能力声明 + policy/audit/kill-switch** 保持 Hub-first 的治理边界

只有这样，X-Hub 才能从“本地 LLM 控制面”升级为“本地多模态与专业模型的受治理 Hub”。
