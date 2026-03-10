> NOTE (2026-02-13): P0 已整理为正式 spec：`docs/xhub-runtime-stability-and-launch-recovery-v1.md`。本文件保留作为临时备忘与后续 P1 草稿入口。

## P0：Runtime Stability + Launch Recovery（待写成正式 spec）
  目标：解决“App 打不开 / runtime 报错”，要求可定位、可复现、可降级（UI 仍可打开）。

  硬要求：
  - 明确启动状态机（每步时间戳 + 稳定错误码）
  - 明确归因（gRPC / Bridge / Runtime 哪个失败）
  - 安全降级：
    - Bridge 不可用：禁 paid/web；其余可用；审计写 blocked 原因
    - Runtime 不可用：禁 local；其余可用
    - DB 可疑：只读启动 + 提供修复/导出入口
  - 一键导出诊断包（脱敏）：logs tail + 组件状态 + 配置(脱敏) + DB integrity 结果

  建议状态机：
  - BOOT_START
  - ENV_VALIDATE
  - START_GRPC_SERVER -> WAIT_GRPC_READY
  - START_BRIDGE -> WAIT_BRIDGE_READY
  - START_RUNTIME -> WAIT_RUNTIME_READY
  - SERVING / DEGRADED_SERVING / FAILED

  用户可点的恢复按钮（明确效果）：
  - Retry Start
  - Restart Components
  - Reset Volatile Caches（不动 DB）
  - Repair DB（Safe）
  - Factory Reset（Danger，需要 admin 确认）

  v1 验收：
  - App UI 总能打开
  - 任一失败都能给出单一 root-cause 组件 + 错误码
  - 诊断包可导出
  - 至少 1 个降级模式可跑通端到端

  ## P1：Local Models — Transformers Integration（待写成正式 spec）
  现状：本地模型主路径是 MLX；你反馈“本地模型目前只支持 XML”，需要引入 HF Transformers。

  v1（务实落地）：
  - MLX 保持主路径
  - 增加 Transformers Adapter（Python），先支持“本地已下载 HF 模型加载”
  - v1 默认不做联网下载（避免供应链/网络/体验不可控）；后续 opt-in

  统一抽象：ModelProvider 接口（mlx/transformers/remote）
  - list_models()
  - load_model(model_id, opts)
  - generate(request)（流式）
  - unload(model_id)
  - healthcheck()

  v2：
  - 可选在线下载：allowlist + checksum + provenance logging
  - 按需支持 embeddings/rerank（给 Memory v2 用）

  ## P1：Paid Model Provider Gateway（待写成正式 spec）
  现状（从代码可见）：至少有 OpenAI 的 seed 模型；“主流都打通了？”需要统一验收口径。

  “某 provider 已打通”的验收标准（必须同时满足）：
  - 跑通 1 次流式请求 end-to-end
  - 成本/Token 计量入库（可先粗略，但要一致）
  - 完整审计记录
  - Kill-Switch 能拦截
  - 配额能生效

  Gateway 需要：
  - Provider adapter（OpenAI first，后续 Anthropic/Gemini/...）
  - 统一策略：一次性授权后自动续签（在 quota/policy 内）
  - entitlement 粒度：(device_id,user_id,app_id)
  - retry/backoff + circuit breaker + fallback（blocked 默认降级到 local）
  - prompt 外发门禁：secret 可选禁远程（deny-by-default）

  ## X_MEMORY.md（下次要同步更新的点）
  - updatedAt: 2026-02-13
  - 把“App 打不开/Runtime 报错”升到 P0
  - 把 Transformers 集成写成 v1/v2 里程碑
  - 把 paid provider “已打通”验收口径写清楚（不是口头支持）
  EOF
