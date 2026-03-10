# XT-W3-24 多渠道入口与流式体验产品化实现子工单包

- version: v1.0
- updatedAt: 2026-03-06
- owner: XT-L1（Primary）/ XT-L2 / Hub-L5 / QA / AI-COORD-PRIMARY
- status: active
- scope: `XT-W3-24`（Multi-Channel Gateway Productization）+ `XT-W3-24-A/B/C/D/E/F`
- parent:
  - `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md`
  - `docs/xhub-client-modes-and-connectors-v1.md`
  - `docs/xhub-memory-remote-export-and-prompt-gate-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md`
  - `docs/memory-new/xhub-security-innovation-work-orders-v1.md`
  - `X_MEMORY.md`

## 0) 目标与硬边界

- 目标：吸收 `iflow-bot` 在“多渠道入口、快速上手、流式可见输出、会话运维”上的产品化优势，但底层继续坚持 Hub-first 的安全、记忆、授权与审计架构。
- 目标：让 X-Terminal 对外具备“像 bot 一样好上手”的入口产品体验，包括 `install/onboard/start/status`、首版多渠道接入、streaming UX、session/status/restart/logs 面板，以及 heartbeat/cron 运营入口。
- 目标：让渠道层成为“产品入口壳”，而不是第二个 AI/记忆/权限后端；所有高风险能力、长期记忆、支付、授权与外部动作仍收敛到 Hub。
- 目标：把多渠道入口与 `XT-W3-21 Project Intake Manifest`、`XT-W3-22 Acceptance Pack`、`XT-W3-23 Memory UX Adapter` 接通，形成完整的“接案 -> 执行 -> 交付 -> 通知”产品面。
- 目标：首版先做 `Telegram + Slack + Feishu` 三渠道最小可运行包；`DingTalk/Discord/Email` 作为后续扩展能力，不阻塞首版收口。
- 硬边界：
  - 渠道层不得保存 canonical/longterm 真相源；记忆仍以 Hub 为唯一事实源，XT/渠道仅可缓存短期胶囊与崩溃恢复缓冲。
  - 任何渠道触发的外部动作、工具调用、联网、付费模型、发送消息、写邮件、技能执行，均必须走 Hub connectors/grants/audit 主链。
  - 渠道 token、webhook secret、bot secret 不得进入提示词、工作区明文文件或远程 prompt bundle；必须受 secret gate / DLP / redaction 约束。
  - 默认不暴露模型原始思维链；对用户只允许展示 `progress / tool hint / concise rationale`，不得把隐藏 CoT 直接转发到渠道。
  - `install/onboard` 体验不得通过“默认 yolo 放权”换速度；高风险授权与跨 scope 能力仍按 fail-closed 处理。

## 1) 机读契约

### 1.1 `xt.channel_gateway_manifest.v1`

```json
{
  "schema_version": "xt.channel_gateway_manifest.v1",
  "project_id": "uuid",
  "gateway_id": "xt-gateway-1",
  "enabled_channels": ["telegram", "slack", "feishu"],
  "default_transport_mode": "streaming|non_streaming",
  "source_of_truth": "hub",
  "session_policy_ref": "xt.channel_session_projection.v1",
  "hub_boundary_policy_ref": "xt.channel_hub_boundary_policy.v1",
  "operator_console_ref": "board://xt/channel-console/project-a",
  "audit_ref": "audit-xxxx"
}
```

### 1.2 `xt.channel_session_projection.v1`

```json
{
  "schema_version": "xt.channel_session_projection.v1",
  "project_id": "uuid",
  "channel": "telegram",
  "channel_chat_id": "chat-123",
  "hub_session_id": "session-uuid",
  "user_scope_ref": "scope://user/u-1",
  "project_scope_ref": "scope://project/p-1",
  "memory_capsule_ref": "build/reports/xt_memory_capsule_project_a.v1.json",
  "cross_channel_resume_allowed": false,
  "audit_ref": "audit-xxxx"
}
```

### 1.3 `xt.channel_streaming_capability.v1`

```json
{
  "schema_version": "xt.channel_streaming_capability.v1",
  "channel": "telegram",
  "stream_mode": "message_edit|card_patch|chunk_append|final_only",
  "supports_progress_hint": true,
  "supports_tool_hint": true,
  "max_update_rate_per_sec": 1,
  "fallback_mode": "progress_then_final|final_only",
  "audit_ref": "audit-xxxx"
}
```

### 1.4 `xt.channel_operator_console_state.v1`

```json
{
  "schema_version": "xt.channel_operator_console_state.v1",
  "gateway_id": "xt-gateway-1",
  "channels": [
    {
      "channel": "telegram",
      "status": "running|degraded|stopped",
      "last_heartbeat_at": "2026-03-06T10:00:00Z",
      "active_sessions": 12,
      "last_restart_at": "2026-03-06T09:30:00Z"
    }
  ],
  "heartbeat_enabled": true,
  "cron_enabled": true,
  "log_tail_ref": "board://xt/logs/channel-gateway",
  "audit_ref": "audit-xxxx"
}
```

### 1.5 `xt.onboard_bootstrap_bundle.v1`

```json
{
  "schema_version": "xt.onboard_bootstrap_bundle.v1",
  "project_id": "uuid",
  "install_mode": "pip|pkg|source",
  "required_envs": ["CHANNEL_TOKEN_REF"],
  "generated_files": ["AGENTS.md", "HEARTBEAT.md", "channel-config.template.json"],
  "smoke_command": "xt gateway start --smoke telegram",
  "rollback_command": "xt gateway stop && xt gateway reset-smoke",
  "audit_ref": "audit-xxxx"
}
```

### 1.6 `xt.channel_hub_boundary_policy.v1`

```json
{
  "schema_version": "xt.channel_hub_boundary_policy.v1",
  "project_id": "uuid",
  "hub_is_truth_source": true,
  "channel_local_memory_mode": "capsule_only",
  "requires_grant_for_side_effects": true,
  "remote_export_secret_mode": "deny|allow_sanitized",
  "webhook_replay_guard_required": true,
  "channel_scope_enforcement": "dm|group|allowlist",
  "decision": "allow|deny|downgrade_to_local",
  "audit_ref": "audit-xxxx"
}
```

## 2) 专项 Gate / KPI

### 2.1 Gate

- `XT-CHAN-G0`：多渠道契约冻结完成，gateway/session/streaming/operator/onboard/boundary 六类 schema 已冻结。
- `XT-CHAN-G1`：最小可运行路径通过，`install -> onboard -> start -> status -> first message` 可由新环境独立完成。
- `XT-CHAN-G2`：渠道与 Hub 安全边界通过，`cross_channel_session_leak = 0`、`channel_secret_exposure = 0`、`unauthorized_channel_side_effect = 0`。
- `XT-CHAN-G3`：流式输出与用户可见体验通过，首版三渠道的 streaming/fallback 行为可复现。
- `XT-CHAN-G4`：session/status/restart/logs/heartbeat/cron 操作台通过，且恢复/重启有证据与回滚点。
- `XT-CHAN-G5`：首版发布证据完整，接入质量、回滚、最小可运行包、开源入口说明已齐。

### 2.2 KPI

- `first_wave_channel_coverage = 3/3`
- `onboard_to_first_message_p95_ms <= 180000`
- `channel_delivery_success_rate >= 0.98`
- `streaming_first_update_p95_ms <= 1500`
- `cross_channel_session_leak = 0`
- `channel_secret_exposure = 0`
- `operator_status_command_success_rate = 1.0`
- `restart_recovery_success_rate >= 0.95`
- `silent_channel_failure = 0`

## 3) 子工单分解

### 3.1 `XT-W3-24-A` Channel Gateway Registry + Capability Manifest

- 目标：建立统一渠道注册表、能力清单与配置契约，让所有渠道接入都复用同一条 gateway 主链。
- 交付物：`build/reports/xt_w3_24_a_channel_gateway_registry_evidence.v1.json`

### 3.2 `XT-W3-24-B` First-Wave Connectors（Telegram + Slack + Feishu）

- 目标：实现首版三渠道接入，支持基础收发、会话映射、最小状态同步与失败可恢复。
- 交付物：`build/reports/xt_w3_24_b_first_wave_channels_evidence.v1.json`

### 3.3 `XT-W3-24-C` Streaming Output UX

- 目标：实现首版三渠道的流式输出/渐进展示能力，并统一 fallback 行为与用户可解释提示。
- 交付物：`build/reports/xt_w3_24_c_streaming_output_evidence.v1.json`

### 3.4 `XT-W3-24-D` Operator Console（Sessions / Status / Restart / Heartbeat / Logs）

- 目标：提供会话、状态、重启、日志、心跳、cron 的运营控制台与可机判状态视图。
- 交付物：`build/reports/xt_w3_24_d_operator_console_evidence.v1.json`

### 3.5 `XT-W3-24-E` Onboard / Bootstrap / Minimal Runnable UX

- 目标：把首版开源用户的启动路径压缩成最短链路，并生成可复制的 bootstrap bundle 与 smoke 命令。
- 交付物：`build/reports/xt_w3_24_e_onboard_bootstrap_evidence.v1.json`

### 3.6 `XT-W3-24-F` Channel-Hub Security Boundary

- 目标：把渠道入口的 webhook、token、session、side effect、prompt export 全部收敛到 Hub 安全主链并形成 fail-closed 边界。
- 交付物：`build/reports/xt_w3_24_f_channel_hub_boundary_evidence.v1.json`

## 4) 任务级执行包

### 4.1 `XT-W3-24` 多渠道入口与流式体验产品化（总任务）

- 目标：把 X-Terminal 对外产品面做成“像 bot 一样好接入、像平台一样可治理”的多渠道入口层，补齐 `channel gateway + first-wave connectors + streaming UX + operator console + onboard/bootstrap + channel-hub security boundary` 六项能力。
- DoR：
  - `docs/xhub-client-modes-and-connectors-v1.md` 已冻结 Hub connectors / mode 1/2 / kill-switch 基线。
  - `XT-W3-21/XT-W3-22/XT-W3-23` 已提供接案、验收、记忆 UX 适配层与 memory bus 入口。
  - Hub 端已存在 connector ingress 授权与 webhook replay / allow_from / scope gate 的实现与回归基线。
  - 开源最小可运行包检查单已存在，可作为首版 onboarding 的发布边界。
- 实施子步骤：
  1. 冻结六类机读契约并统一 gateway/channel/session/operator/onboard 字段命名。
  2. 落地首版多渠道 gateway registry 与 `Telegram + Slack + Feishu` 三渠道接入。
  3. 落地 streaming UX 与 fallback 行为，不暴露 raw CoT。
  4. 落地 session/status/restart/logs/heartbeat/cron 的 operator console。
  5. 落地 `install -> onboard -> start -> status -> first message` 极短路径与 smoke 命令。
  6. 把 token/webhook/session/外部副作用统一挂到 Hub 边界与审计主链。
  7. 补齐 Gate/KPI/回归与 release evidence。
- DoD：
  - 新环境可在最小步骤内起一个可用的三渠道首版 gateway。
  - 渠道层不保存长期真相源，不绕过 Hub grants/connectors/audit。
  - streaming/session/status/onboard 都有清晰的用户可见入口与 machine-readable 证据。
  - 渠道侧失败、重启、降级、fallback 与回滚都可观测、可解释、可恢复。
- Gate：`XT-CHAN-G0/G1/G2/G3/G4/G5` + `XT-MP-G4/G5` + `XT-MEM-G2`
- KPI：
  - `first_wave_channel_coverage = 3/3`
  - `channel_delivery_success_rate >= 0.98`
  - `cross_channel_session_leak = 0`
- 回归样例：
  - 渠道 A 的 session 被错误复用于渠道 B -> 失败。
  - webhook 重放/错 scope 输入被当成正常消息消费 -> 失败。
  - onboarding 成功提示已显示，但 `first message` 实际无法投递 -> 失败。

### 4.2 `XT-W3-24-A` Channel Gateway Registry + Capability Manifest

- 目标：先把多渠道产品面做成统一 gateway 抽象，而不是每个渠道各写一套孤立逻辑。
- DoR：
  - 首版渠道集合与 transport mode 已冻结。
  - `XT-W3-21` intake 能提供 `channel_targets / touch_policy / acceptance_mode`。
- 实施子步骤：
  1. 实现 `ChannelGatewayRegistry`，统一 `channel_id/capabilities/fallback_mode/security_policy_ref`。
  2. 为每个渠道注册 `receive/send/stream/status/health/restart` 能力矩阵。
  3. 把 gateway 配置编译为 `xt.channel_gateway_manifest.v1`，供 XT-L1/XT-L2/QA 复用。
  4. 产出 evidence：`build/reports/xt_w3_24_a_channel_gateway_registry_evidence.v1.json`。
- DoD：
  - 新渠道可通过注册表挂接，而不是散落在各处硬编码。
  - capability matrix 缺字段或 channel 不支持某能力时 fail-closed。
  - operator console / acceptance pack 能消费同一份 gateway manifest。
- Gate：`XT-CHAN-G0/G1`
- KPI：`gateway_manifest_schema_coverage = 100%`, `unsupported_channel_silent_fallback = 0`
- 回归样例：
  - 未声明 streaming capability 却进入 streaming 分支 -> 失败。
  - channel id 与 security policy ref 不一致仍上线 -> 失败。
  - 新渠道未注册 health/restart 能力却被标记 ready -> 失败。

### 4.3 `XT-W3-24-B` First-Wave Connectors（Telegram + Slack + Feishu）

- 目标：先把首版最有传播力和代表性的三渠道打通，作为对外开源与产品展示面。
- DoR：
  - gateway registry 已可用。
  - `Hub connectors + ingress authorizer + allow_from / scope gate` 基线已存在。
- 实施子步骤：
  1. 实现 Telegram connector：基础收发、session projection、status、smoke route。
  2. 实现 Slack connector：基础收发、group/dm scope 区分、status、smoke route。
  3. 实现 Feishu connector：基础收发、签名/验证、status、smoke route。
  4. 为每个渠道补 `channel smoke + failure recovery + replay/duplicate protection` 证据。
  5. 产出 evidence：`build/reports/xt_w3_24_b_first_wave_channels_evidence.v1.json`。
- DoD：
  - 三渠道均可收发首条消息并进入会话映射。
  - 每个渠道至少有一条最小可运行 smoke 命令与一条恢复路径。
  - duplicate/replay/错 scope/未授权输入都 fail-closed。
- Gate：`XT-CHAN-G1/G2/G5`
- KPI：`first_wave_channel_coverage = 3/3`, `channel_delivery_success_rate >= 0.98`
- 回归样例：
  - Telegram 与 Slack 共享同一 `channel_chat_id` 时误合并 session -> 失败。
  - Feishu webhook 验签失败仍被消费 -> 失败。
  - Slack group allowlist 不满足仍放行 -> 失败。

### 4.4 `XT-W3-24-C` Streaming Output UX

- 目标：把渠道层的“实时反馈”体验做成标准能力，但只展示允许对外暴露的进度/提示/结果，不暴露隐藏思维链。
- DoR：
  - `xt.channel_streaming_capability.v1` 已冻结。
  - `XT-W3-23` memory capsule 与 `XT-W2-24` token 胶囊可提供精简上下文。
- 实施子步骤：
  1. 为 `message_edit|card_patch|chunk_append|final_only` 定义统一 streaming adapter。
  2. 把 `progress hint / tool hint / concise rationale / final answer` 区分为可控输出层。
  3. 对不支持 streaming 的渠道自动降级到 `progress_then_final|final_only`。
  4. 接入 update rate / backpressure / final flush 守门，避免渠道 API 过载。
  5. 产出 evidence：`build/reports/xt_w3_24_c_streaming_output_evidence.v1.json`。
- DoD：
  - 首版三渠道都具备稳定的 streaming 或显式 fallback。
  - 不会把 raw CoT、secret、未经允许的工具细节直接流到渠道。
  - 渠道掉线/编辑失败时会自动降级并保底投递最终答复。
- Gate：`XT-CHAN-G2/G3/G5`
- KPI：`streaming_first_update_p95_ms <= 1500`, `final_message_loss = 0`
- 回归样例：
  - Telegram message edit 失败后既没降级也没最终答复 -> 失败。
  - streaming 输出泄露 hidden rationale -> 失败。
  - 渠道速率限制触发后持续刷 API -> 失败。

### 4.5 `XT-W3-24-D` Operator Console（Sessions / Status / Restart / Heartbeat / Logs）

- 目标：让操作者能像用成熟 bot 产品一样管理 gateway，而不是靠 grep 日志和手工猜状态。
- DoR：
  - `XT-W3-21` intake 能输出 `operator_console_required=true|false`。
  - gateway registry 与 session projection 已存在。
- 实施子步骤：
  1. 实现 `session list/filter/clear/rebind` 视图与命令。
  2. 实现 `status/health/restart/log tail` 视图与命令。
  3. 接入 heartbeat/cron 的 enable/disable/trigger/status 命令与审计。
  4. 把 operator 状态导出为 `xt.channel_operator_console_state.v1`。
  5. 产出 evidence：`build/reports/xt_w3_24_d_operator_console_evidence.v1.json`。
- DoD：
  - 操作者可查看会话、状态、最近重启、心跳与日志。
  - 任意 restart/clear session 都有审计与回滚说明。
  - degraded/stopped 状态不会被误报成 healthy。
- Gate：`XT-CHAN-G1/G4/G5`
- KPI：`operator_status_command_success_rate = 1.0`, `restart_recovery_success_rate >= 0.95`
- 回归样例：
  - restart 执行成功但状态面板仍显示旧状态 -> 失败。
  - 清 session 误清到其他项目 scope -> 失败。
  - heartbeat/cron 已禁用却仍自动触发 -> 失败。

### 4.6 `XT-W3-24-E` Onboard / Bootstrap / Minimal Runnable UX

- 目标：把“第一次部署一个可用 bot”的步骤压到最少，并和开源最小可运行包清单一致。
- DoR：
  - 开源最小可运行包检查单已冻结。
  - 首版三渠道的 config template、smoke route 与 rollback route 已定义。
- 实施子步骤：
  1. 实现 `install/onboard/start/status/smoke` 的最短路径与文档模板。
  2. 自动生成 `xt.onboard_bootstrap_bundle.v1`，包含 env checklist、生成文件、smoke 命令、rollback 命令。
  3. 为 `pip|pkg|source` 三种安装形态统一最小差异的启动说明。
  4. 补齐 minimal runnable 包的 smoke evidence 与回滚锚点。
  5. 产出 evidence：`build/reports/xt_w3_24_e_onboard_bootstrap_evidence.v1.json`。
- DoD：
  - 新用户不看内部文档也能按最短路径起首版 gateway。
  - onboarding 不会静默遗漏必填 secret/token/config。
  - smoke 成功与 rollback 路径都可复现。
- Gate：`XT-CHAN-G1/G5`
- KPI：`onboard_to_first_message_p95_ms <= 180000`, `bootstrap_missing_required_env = 0`
- 回归样例：
  - onboard 生成成功但缺少必要 env/template -> 失败。
  - smoke 命令通过但 status 不可读 -> 失败。
  - rollback 命令缺失仍标记 release-ready -> 失败。

### 4.7 `XT-W3-24-F` Channel-Hub Security Boundary

- 目标：明确规定渠道层与 Hub 的安全边界，确保“产品更好用”不会削弱我们的安全、记忆、授权主线。
- DoR：
  - `docs/xhub-client-modes-and-connectors-v1.md`、`XT-W3-23`、安全创新主线均已冻结相关边界。
  - Hub 已具备 connector ingress authorizer、webhook replay guard、audit fail-closed 基线。
- 实施子步骤：
  1. 固化 `xt.channel_hub_boundary_policy.v1`，把 truth source、grant、replay、scope、remote export 决策统一机读化。
  2. 所有渠道 ingress 必须附带 `source_id/channel_scope/signature/replay window` 校验并写审计。
  3. 渠道触发的外部副作用必须显式拿 grant；无 grant 一律 deny。
  4. 渠道 token/secret 只保留 secret ref，不进提示词、不进本地长期明文。
  5. 产出 evidence：`build/reports/xt_w3_24_f_channel_hub_boundary_evidence.v1.json`。
- DoD：
  - 渠道层无法绕过 Hub 进行高风险动作与长期记忆写入。
  - webhook 重放、错 scope、审计失败、secret 泄露路径都 fail-closed。
  - Acceptance Pack 能引用 boundary policy 与审计证据。
- Gate：`XT-CHAN-G2/G5` + `XT-MEM-G2` + `SI-G1/SI-G2/SI-G4`
- KPI：`cross_channel_session_leak = 0`, `channel_secret_exposure = 0`, `unauthorized_channel_side_effect = 0`
- 回归样例：
  - webhook replay 命中后仍被视为新消息 -> 失败。
  - 渠道层未拿 grant 直接触发发送邮件/调用付费模型 -> 失败。
  - channel token 被写进工作区模板或远程 prompt bundle -> 失败。

## 5) 泳道落地建议

- `XT-L1`：主导 `XT-W3-24-B/C/D/E`，负责渠道接入体验、streaming UX、operator console、bootstrap 文档与最小可运行产品面。
- `XT-L2`：主导 `XT-W3-24-A/F`，负责 gateway registry、契约冻结、Hub 边界、流程编排与和 `XT-W3-21/22/23` 的集成。
- `Hub-L5`：负责 connectors/grants/audit 真相源、replay/scope/allow_from 基线、真实样本与 Gate 采样。
- `QA`：负责 `XT-CHAN-G0..G5` require-real 回归、三渠道 smoke、重启恢复、streaming/fallback 与安全负面样例。
- `AI-COORD-PRIMARY`：仅做优先级与契约裁决，不直接接管渠道实现。

## 6) 发布约束

- 未通过 `XT-CHAN-G1` 前，禁止把 `XT-W3-24` 对外描述为“最小可运行开箱即用”。
- 未通过 `XT-CHAN-G2` 前，禁止把多渠道入口默认连到任何高风险 side effect；仅允许只读/本地/降级模式。
- 未通过 `XT-CHAN-G3` 前，不得承诺“稳定 streaming UX”；只能标记为 experimental/fallback-first。
- 未通过 `XT-CHAN-G4` 前，operator console 只能用于内部诊断，不宣称可用于稳定运营。
- 未通过 `XT-CHAN-G5` 前，禁止把该能力纳入首版公开发布主链。
