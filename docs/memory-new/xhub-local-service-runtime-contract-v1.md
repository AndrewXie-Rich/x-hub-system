# X-Hub Local Service Runtime Contract v1

## 1. 目标

把 `xhub_local_service` 定义为 X-Hub 自管的本地推理服务面，作为未来本地 `embedding / vision / audio / chat` 的统一 Hub-first 执行入口。

这份 contract 的目的不是“再包一层第三方 helper”，而是把下面三件事收成同一个真相源：

- Hub 怎么判断“本地服务真的可用”
- Provider pack 怎么声明“这个 provider 走 service，而不是走当前 Python 进程”
- UI / Doctor / Incident export 怎么把失败原因讲清楚

## 2. 非目标

- 不把“进程活着”当成 ready
- 不把“端口能连上”当成 ready
- 不把 LM Studio / OpenCode / 其他外部 runtime 当成主线依赖
- 不绕过 Hub 的 provider registry、audit、grant、doctor、kill-switch

## 3. 单一真相源状态机

`xhub_local_service` 必须只暴露下面 6 个机读状态：

1. `xhub_local_service_config_missing`
   - 没有 `runtimeRequirements.serviceBaseUrl`
   - 也没有 `XHUB_LOCAL_SERVICE_BASE_URL`
2. `xhub_local_service_nonlocal_endpoint`
   - `serviceBaseUrl` 不是 loopback HTTP endpoint
   - Hub 必须 fail-closed，不能把非本机地址当成自管本地服务
3. `xhub_local_service_unreachable`
   - `/health` 无法建立有效 HTTP 响应
4. `xhub_local_service_starting`
   - `/health` 已响应，但状态还是 `starting / booting / warming`
5. `xhub_local_service_not_ready`
   - `/health` 已响应，但不满足 ready 判定
6. `xhub_local_service_ready`
   - `/health` 明确返回 ready，可接 live traffic

Hub、Doctor、UI、incident export 一律以这个 reason code 为准，不再自己猜测。

## 4. 必备接口

### `GET /health`

最关键的唯一 readiness 入口。至少返回：

- `ok: boolean`
- `status: ready | starting | booting | warming | degraded | failed`
- `version: string`
- `capabilities: string[]`

建议后续追加：

- `providers`
- `loadedModels`
- `queueDepth`
- `memory`
- `lastError`

### `GET /v1/models`

返回当前 service 可见的模型/adapter inventory。用途：

- Hub library / runtime monitor 对齐
- warmup 前能力确认
- Doctor 导出“服务看到了什么模型”

### `POST /v1/embeddings`

最小对齐 OpenAI-style embeddings contract。要求：

- machine-readable usage
- fail-closed，不得偷偷 fallback 到远端

### `POST /v1/chat/completions`

承载本地 chat / vision / OCR 等统一 completion 面。多模态能力由 `messages[].content[]` 声明，不要另造平行接口。

### `POST /admin/warmup`

Hub 的显式常驻预热入口。必须支持：

- `provider`
- `model`
- `taskKind`
- `loadProfile`
- `instanceKey`

### `POST /admin/unload`

显式卸载指定 model / instance。

### `POST /admin/evict`

显式驱逐指定 instance / idle residency。

## 5. Ready 判定规则

Hub 侧必须 fail-closed：

- 只有 `GET /health` 返回 `ok=true`，且 `status in {ready, running, ok}` 才算 ready
- 只看到进程 pid、launchd job、监听端口，全部不算 ready
- 只看到 `/v1/models` 能返回，也不算 ready
- `/health` 若能回但 `status=starting`，必须继续标成 `starting`，不能偷跑 live traffic

一句话：`/health` 是 readiness truth，别的都只是证据，不是结论。

## 6. Provider Pack 接线

Provider pack runtime requirements 新增：

- `executionMode = "xhub_local_service"`
- `serviceBaseUrl`

这样 provider 不再依赖“当前 Python 进程里有没有装对包”，而是显式声明“我走 Hub 自管服务面”。

## 7. Fail-Closed 规则

- service 不 ready 时，provider status 必须落成 `runtime_missing`
- `serviceBaseUrl` 只能是 `http://127.0.0.1:<port>`、`http://localhost:<port>` 或 `http://[::1]:<port>`
- 非 loopback、带 path/query/credential 的 endpoint 一律记成 `xhub_local_service_nonlocal_endpoint`
- 不允许 silent fallback 到 user Python
- 不允许 silent fallback 到 remote API
- UI 必须能直接展示当前 endpoint、reason code、runtime hint

## 8. 当前落地切面

本轮已完成第一段可运行切面：

- Python resolver 已识别 `executionMode=xhub_local_service`
- provider pack schema 已支持 `serviceBaseUrl`
- Swift guidance / import detection 已能展示 `runtimeSource=xhub_local_service`
- LM Studio helper 仍保留为参考桥接路径，但不再是唯一主线
- 最小 runnable service 已落地在 `x-hub/python-runtime/python_service/xhub_local_service_runtime.py`
- 当前真实可用接口：`GET /health`、`GET /v1/models`
- 当前已接 delegation 的 lifecycle 接口：`POST /admin/warmup`、`POST /admin/unload`、`POST /admin/evict`
- 当前已接 live inference proxy：
  - `POST /v1/embeddings` -> `run_local_task(..., task_kind=embedding)`
  - `POST /v1/chat/completions`
    - text-only -> `run_local_task(..., task_kind=text_generate)`
    - local image chat part -> `run_local_task(..., task_kind=vision_understand | ocr)`
    - 已支持 multi-image、multi-turn image mix、显式 `task_kind=ocr|vision_understand` override
    - success / error payload 已带 machine-readable `routeTrace`
      - `selectedTaskKind / selectionReason / explicitTaskKind`
      - `imageCount / resolvedImageCount / resolvedImages`
      - `blockedReasonCode / blockedImageIndex`
    - 当前仅支持本地路径、`file://`、`data:` 图片；远程 `http(s)` image URL 继续 fail-closed
- 当前 `routeTrace` 已继续并入 bench / runtime monitor / operator export：
  - `models_bench.json` 会持久化 `routeTrace + routeTraceSummary`
  - `ai_runtime_status.json` / `monitorSnapshot` 会暴露 `recentBenchResults`
  - Hub JS IPC 归一化层会输出 `recent_bench_results[].route_trace / route_trace_summary`
- 当前 multi-image OCR 已补 page-aware span contract：
  - OCR 多图请求会按页 fanout，再聚合回单次结果
  - `spans[]` 现会稳定带出 `pageIndex / pageCount / fileName / bbox`
  - 聚合 `text` 会保留 `[page N]` 分段，避免多页 OCR 重新塌成无边界纯文本
- 已补 service-internal runtime resolution：当 provider pack 走 `executionMode=xhub_local_service` 时，service 进程内会按 service-hosted modules 评估真实可执行性，而不是递归把自己再次当成外部服务探测对象
- 已补 Hub 自管生命周期第一段：
  - resolver 在 `executionMode=xhub_local_service` 且 `/health` 不通时，会尝试自动拉起 `xhub_local_service_runtime.py serve`
  - 仅允许 loopback endpoint 参与 auto-start；非本机 endpoint 一律 fail-closed
  - 启动后会立即 re-probe `/health`，成功才给 `xhub_local_service_ready`
  - 已有同 target pid 且进程仍存活时，会复用现有 managed state，避免重复拉起
- 已补 managed service state snapshot：
  - 默认写到 `base_dir/xhub_local_service_state.json`
  - 至少包含 `baseUrl / bindHost / bindPort / pid / processState / startedAtMs / lastProbeAtMs / lastReadyAtMs / lastLaunchAttemptAtMs / startAttemptCount / lastStartError`
  - provider status 现会带 `managedServiceState`，供后续 doctor / incident / supervisor 继续上浮消费
- smoke 验证在：
  - `x-hub/python-runtime/python_service/test_xhub_local_service_runtime.py`
  - `x-hub/python-runtime/python_service/test_transformers_provider_multimodal_contract.py`
  - `x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`

## 9. 下一步

1. 继续把 `xhub_local_service_state.json / managedServiceState` 深化接进 doctor / diagnostics export / auto-recovery；本轮已补 `primary_issue + doctor_projection` 结构化导出、Hub base-dir sidecar 落盘，以及 XT `incident export / XT-Ready` 对该 snapshot 的 fallback 消费；`2026-03-22` 又补了一层 `scripts/generate_xhub_local_service_operator_recovery_report.js`，可直接把 source gate summary 转成 operator action / support FAQ / release wording；下一步重点转向更细 recovery automation，而不是只停留在原始 provider 证据
2. 把 managed lifecycle 再接进 release gate / incident bundle，而不是只停留在 resolver 首跳；当前 source gate 已能机读 `hub_local_service_snapshot_support`，后续应继续把这份 truth 接到 release-ready decision、operator runbook 和 support FAQ 的正式出口
3. 视需要再补更细粒度 OCR 结构层，比如 `line / block / token confidence`，但前提是真实 runtime 能稳定提供，而不是伪结构
