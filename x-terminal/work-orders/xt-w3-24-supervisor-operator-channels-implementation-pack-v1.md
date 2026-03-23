# XT-W3-24 Supervisor Operator Channels Implementation Pack v1

- version: v1.0
- updatedAt: 2026-03-12
- owner: Hub-L5（Primary）/ XT-L2 / XT-L1 / Security / QA / Product
- status: planned
- scope: `Hub-first` 多渠道 `Supervisor Operator Channel` 产品面；首版 `Slack + Telegram + Feishu`，P1 `WhatsApp hybrid`
- parent:
  - `x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-25-automation-product-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-hub-security-impact-gate-v1.md`
  - `docs/xhub-client-modes-and-connectors-v1.md`
  - `docs/xhub-connectors-isolation-and-runtime-v1.md`
  - `docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
  - `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## Direct-Execution Child Pack

- `x-terminal/work-orders/xt-w3-24-safe-operator-channel-onboarding-automation-implementation-pack-v1.md`
  - Purpose: 把首次接入从“手工建 binding”升级为 `unknown ingress quarantine -> admin approve once -> auto-bind -> first smoke`，让 Slack / Telegram / Feishu / WhatsApp Cloud API 的首用路径更自动，但不降低 Hub-first 安全基线。

## 0) Why This Pack Exists

`XT-W3-24` 已经把“多渠道入口、流式体验、operator console、channel-hub boundary”作为父级产品目标冻结下来，但还缺一份真正可直接开工的子包，来回答下面这些更细的问题：

1. Slack / Telegram / Feishu 连上后，到底是跟 Hub 对话，还是跟某台 XT 设备直接对话？
2. 外部 IM 指令怎样变成 Supervisor 可治理的结构化动作，而不是“自然语言直接跑高风险副作用”？
3. 怎样把“告警推送、审批卡片、项目状态查询、deploy plan、grant approve”这几类高频动作收敛到一条主链？
4. OpenClaw 里已经有的 channel/plugin 资产哪些可以直接借，哪些只能借接口形状，哪些绝对不能照搬？

本包只解决这一件事：把“多渠道入口”从 bot-style 外壳，收口为 `Hub-first` 的 `Supervisor Operator Channel` 产品面。

## 1) Finished State

完成后，系统至少要满足以下事实：

1. `Slack / Telegram / Feishu` 可以作为 `Supervisor` 的外部操作入口，但真正的控制平面仍在 `Hub`。
2. 用户默认不是“跟某台设备聊天”，而是“跟某个 project / incident / approval queue 的 Supervisor 聊天”；只有设备诊断类场景才显式按设备路由。
3. 外部 IM 的入站消息统一视为 `untrusted ingress`，只允许通过 `structured actions + policy + grant + audit` 主链触发高风险动作。
4. `project binding + preferred_device_id` 可以把同一 project 的会话优先路由到指定 XT；但设备离线时必须 fail-closed 或降级到 `Hub-only status mode`，不得伪成功。
5. `Slack + Telegram + Feishu` 的首版都具备：
   - 状态查询
   - blocker / queue / pending grants 查询
   - approval / reject / continue / pause / retry
   - 主动推送 heartbeat / incident / cron / delivery summary
6. `WhatsApp` 不允许在首版被口头宣称为与 `Slack / Telegram / Feishu` 同成熟度：
   - `Cloud API` 路径可作为 `Hub connector`
   - `personal QR / local session` 路径只能挂到 `trusted_automation + local runner`，未完成 require-real 前只能 `planned`

## 2) Hard Boundaries

- 外部 IM 渠道只和 `Hub Supervisor Facade` 对话，不直接连 XT 进程。
- 默认不向 provider / operator 客户端暴露 Hub 原始 IP；外部入口以 `domain / relay endpoint / tunnel hostname` 形态出现。
- `Hub` 继续是唯一真相源：memory / auth / grant / audit / policy / kill-switch / connector secrets 不下放到 XT。
- 任何来自 IM 的外部副作用都必须先编译成 `structured action`，再走 `risk classify -> policy -> grant -> execute -> audit`。
- 默认主对象是 `project scope`；`device scope` 仅用于：
  - device doctor
  - permission readiness
  - trusted automation diagnostics
  - explicit preferred-device route inspection
- `Slack / Telegram / Feishu` 首版走 `Hub + Bridge` 数据面；不得把 live token / webhook secret / bot secret 变成 XT 私有运行时状态。
- `WhatsApp personal` 路径不得通过“先塞进 XT 再说”方式偷跑；若采用本机会话，必须显式走 `XTerminalAutomationRunner` 与 Hub grant bridge。
- 不允许把自然语言模糊表达直接升级为：
  - `terminal.exec`
  - `device.*`
  - `connector.send`
  - `deploy.execute`
  - `grant.approve`
- 外部 IM 的附件、链接、卡片回调、按钮动作都视为 `untrusted input`，默认不写入 canonical memory。

## 3) OpenClaw Reuse Freeze

本包默认原则：`能复用的就复用，但只复用不会冲穿 Hub-first 边界的层`。

### 3.1 可直接移植或最小改写的纯逻辑

本地参考根路径（machine-local only，非 release dependency）：

- `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main`

具体参考文件：

- `src/channels/registry.ts`
- `src/channels/plugins/types.plugin.ts`
- `src/channels/plugins/types.adapters.ts`
- `src/channels/plugins/types.core.ts`
- `src/channels/command-gating.ts`
- `src/utils/message-channel.ts`
- `src/utils/delivery-context.ts`
- `src/auto-reply/reply/session-delivery.ts`

冻结结论：

- 直接借 `channel registry / meta / alias normalization` 的设计形状，用于 `HubChannelRegistry`。
- 直接借 `command gating` 的纯函数口径，作为 `channel action gate` 的基线。
- 直接借 `message channel` 与 `delivery context` 归一化逻辑，用于 `conversation_id + account_id + thread_key` 的路由键。
- 借 `plugin contract` 的切分方式，但不照抄运行位置；X-Hub 需要的是 `HubChannelAdapter`，不是 XT 进程内的 privileged channel plugin。

### 3.2 只借接口形状，不直接照搬实现

具体参考文件：

- `ui/src/ui/controllers/channels.ts`
- `ui/src/ui/views/channels.ts`
- `src/telegram/webhook.ts`
- `src/telegram/inline-buttons.ts`
- `src/slack/monitor/message-handler/prepare.ts`
- `src/agents/tools/slack-actions.ts`

冻结结论：

- 借 `channels status snapshot`、`start/wait/logout`、`health card` 的 UX 组织方式。
- 借 Telegram webhook secret 校验、inline buttons scope、topic/thread 路由、draft-stream fallback 的形状。
- 借 Slack 的 `thread_ts`、DM/group 区分、interactive action、reply-to mode、delivery context 形状。
- `Feishu` 在 OpenClaw 没有现成实现，因此只复用前述通用 contract，不额外重复造新的 registry / routing / command-gating 语义。

### 3.3 明确禁止复用的部分

- 不复用“channel runtime in-process 持有 live tokens / cookies / QR session”到 XT。
- 不复用“消息渠道 = 权限主体”的模型。
- 不复用“bot 应用内直接执行本机动作”的信任放置。
- 不复用“自然语言命令直接落低层工具”的执行捷径。

## 4) Machine-Readable Contracts

### 4.1 `xhub.im_identity_binding.v1`

```json
{
  "schema_version": "xhub.im_identity_binding.v1",
  "provider": "feishu",
  "external_user_id": "ou_123",
  "external_tenant_id": "tenant_001",
  "hub_user_id": "user_ops_alice",
  "roles": ["release_manager", "approver"],
  "status": "active",
  "synced_at_ms": 1760000000000,
  "audit_ref": "audit-im-id-001"
}
```

### 4.2 `xhub.supervisor_operator_channel_binding.v1`

```json
{
  "schema_version": "xhub.supervisor_operator_channel_binding.v1",
  "binding_id": "bind-feishu-payments-prod",
  "provider": "feishu",
  "account_id": "default",
  "conversation_id": "oc_xxx",
  "thread_key": "",
  "scope_type": "project",
  "scope_id": "payments-prod",
  "preferred_device_id": "xt-mac-mini-bj-01",
  "allowed_actions": [
    "supervisor.status.get",
    "supervisor.blockers.get",
    "deploy.plan",
    "grant.approve"
  ],
  "approval_surface": "card",
  "threading_mode": "provider_native",
  "status": "active",
  "audit_ref": "audit-bind-001"
}
```

### 4.3 `xhub.supervisor_channel_session_route.v1`

```json
{
  "schema_version": "xhub.supervisor_channel_session_route.v1",
  "route_id": "route-20260312-001",
  "provider": "feishu",
  "conversation_id": "oc_xxx",
  "thread_key": "thread-1",
  "scope_type": "project",
  "scope_id": "payments-prod",
  "supervisor_session_id": "sup-sess-001",
  "preferred_device_id": "xt-mac-mini-bj-01",
  "resolved_device_id": "xt-mac-mini-bj-01",
  "route_mode": "hub_to_xt",
  "xt_online": true,
  "runner_required": false,
  "same_project_scope": true,
  "audit_ref": "audit-route-001"
}
```

### 4.4 `xhub.channel_structured_action_request.v1`

```json
{
  "schema_version": "xhub.channel_structured_action_request.v1",
  "action_id": "act-20260312-001",
  "provider": "slack",
  "conversation_id": "C123",
  "thread_key": "1741770000.12345",
  "actor_ref": "xhub.im_identity_binding.v1:slack/U123",
  "scope_type": "project",
  "scope_id": "payments-prod",
  "action_name": "deploy.plan",
  "args_json": "{\"version\":\"2026.03.12-rc2\"}",
  "risk_tier": "high",
  "required_grant_scope": "deploy.execute",
  "route_pref": "preferred_device",
  "decision": "pending",
  "audit_ref": "audit-action-001"
}
```

### 4.5 `xhub.channel_delivery_job.v1`

```json
{
  "schema_version": "xhub.channel_delivery_job.v1",
  "job_id": "deliver-20260312-001",
  "provider": "telegram",
  "account_id": "ops_bot",
  "conversation_id": "-1001234567890",
  "thread_key": "topic:42",
  "delivery_class": "alert|approval_card|summary|stream_delta|final_result",
  "payload_ref": "local://channel-payloads/deliver-001.json",
  "dedupe_key": "sha256:...",
  "state": "queued|sending|sent|failed|canceled",
  "retry_after_ms": 0,
  "audit_ref": "audit-delivery-001"
}
```

### 4.6 `xhub.channel_runtime_status_snapshot.v1`

```json
{
  "schema_version": "xhub.channel_runtime_status_snapshot.v1",
  "gateway_id": "hub-supervisor-operator-channels",
  "channels": [
    {
      "provider": "slack",
      "configured": true,
      "running": true,
      "connected": true,
      "active_bindings": 3,
      "last_heartbeat_at_ms": 1760000000000,
      "last_error": ""
    },
    {
      "provider": "telegram",
      "configured": true,
      "running": true,
      "connected": true,
      "active_bindings": 2,
      "last_heartbeat_at_ms": 1760000000500,
      "last_error": ""
    }
  ],
  "audit_ref": "audit-runtime-snapshot-001"
}
```

## 5) Example Product Slice

### 5.1 Feishu Project Control Room

标准场景冻结如下：

1. 飞书群 `支付发布指挥室` 绑定到 `project:payments-prod`。
2. 该绑定配置 `preferred_device_id=xt-mac-mini-bj-01`。
3. 用户在群里发：
   - `/status`
   - `/blockers`
   - `/deploy plan version=2026.03.12-rc2`
   - 审批卡片上的 `Approve / Reject`
4. Hub 先完成：
   - 飞书签名校验
   - `open_id -> hub_user_id` 身份映射
   - role / allowlist / project binding 检查
   - structured action 编译
5. 再由 Hub 决定：
   - `hub_only`：只回项目状态，不需要 XT 在线
   - `hub_to_xt`：需要指定 XT 的 Supervisor runtime 响应
   - `hub_to_runner`：需要 trusted automation / device doctor 等本地执行面
6. 所有结果仍经 Hub 审计后回发飞书。

产品口径：

- 用户体验上像“在飞书里和某台 XT 的 Supervisor 对话”
- 架构上实际是“在飞书里和 Hub 托管的 Supervisor facade 对话，Hub 再路由到首选 XT 设备”

## 6) Gate / KPI

### 6.1 Gate

- `XT-CHAN-OP-G0`：上述 6 类契约与 OpenClaw reuse map 冻结完成。
- `XT-CHAN-OP-G1`：`IM identity -> Hub principal -> scope binding` 主链通过，`unauthorized_channel_action = 0`。
- `XT-CHAN-OP-G2`：Supervisor route 主链通过，`project-first + preferred-device` 路由成立，XT 离线不会伪成功。
- `XT-CHAN-OP-G3`：`Slack + Telegram + Feishu` 三渠道最小 operator 面通过。
- `XT-CHAN-OP-G4`：structured action / grant / audit / approval card 主链通过。
- `XT-CHAN-OP-G5`：alert / heartbeat / cron / delivery summary 主动推送通过。
- `XT-CHAN-OP-G6`：`WhatsApp hybrid` 的 release 口径冻结；未有 require-real 前不得口头冒绿。

### 6.2 KPI

- `channel_query_to_first_response_p95_ms <= 3000`
- `approval_card_roundtrip_p95_ms <= 5000`
- `unauthorized_channel_action = 0`
- `cross_project_channel_route_leak = 0`
- `device_offline_false_success = 0`
- `channel_secret_exposure = 0`
- `structured_action_without_audit = 0`
- `alert_delivery_success_rate >= 0.99`
- `operator_binding_lookup_p95_ms <= 1500`

## 7) Direct-Execution Work Orders

### 7.1 `XT-W3-24-G` OpenClaw Reuse Normalization + HubChannelRegistry

- 目标：把 OpenClaw 里可直接借的 channel registry / delivery context / command gate 纯逻辑收敛成 X-Hub 的 channel runtime 基础层。
- 推荐代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/channel_registry.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_types.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_delivery_context.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_runtime_snapshot.js`
  - `x-terminal/Sources/UI/ChannelsCenter/ChannelsCenterView.swift`
- 实施步骤：
  1. Port/adapt OpenClaw 的 `channel registry`、`message channel normalize`、`delivery context key` 纯逻辑。
  2. 冻结 `provider/aliases/capabilities/threading_mode/approval_surface` 字段。
  3. 统一导出 `xhub.channel_runtime_status_snapshot.v1` 给 Hub UI 与 XT UI 复用。
  4. 给“直接复用 vs 仅借形状 vs 禁止复用”三类路径都写 machine-readable 判定。
- DoD：
  - registry / aliases / route key 不再散落在各 adapter 内部硬编码。
  - snapshot 可被 Hub 与 XT 同时消费。
  - OpenClaw reuse map 有单一事实源。
- 回归样例：
  - alias 漂移导致同渠道被识别成两个 provider。
  - Slack `thread_ts` 与 Telegram `topic` 路由键混淆。
  - 未注册 provider 被默认为可 deliverable。
- 证据：
  - `build/reports/xt_w3_24_g_channel_registry_reuse_evidence.v1.json`

### 7.2 `XT-W3-24-H` IM Identity Mapping + Access Groups + Command Gate

- 目标：把外部 IM 用户、群聊、私聊、topic/thread 统一映射为 Hub principal + scope policy，不允许靠昵称或 provider 文本弱绑定。
- 推荐代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/channel_identity_store.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_bindings_store.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_command_gate.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
- 实施步骤：
  1. 落地 `xhub.im_identity_binding.v1` 与 `xhub.supervisor_operator_channel_binding.v1`。
  2. Port/adapt OpenClaw 的 `command-gating.ts` 纯函数，新增 `role + scope + action` 三维校验。
  3. 区分：
     - DM allowlist
     - group allowlist
     - thread/topic allowlist
     - approval-only identities
  4. 所有 deny 都必须带稳定 `deny_code` 与审计事件。
- DoD：
  - provider stable id 变化外的文本字段不影响权限判定。
  - group / dm / thread policy 能独立配置。
  - `grant.approve` 与 `deploy.execute` 默认不是普通 viewer 可触发动作。
- 回归样例：
  - 改昵称后越权通过。
  - 群聊 allowlist 错误放大到所有群。
  - 无 binding 的 channel message 仍可触发 side effect。
- 证据：
  - `build/reports/xt_w3_24_h_identity_command_gate_evidence.v1.json`

### 7.3 `XT-W3-24-I` Supervisor Operator Session + Project / Device Route Binding

- 目标：把“外部 IM 线程在跟谁说话”做成可机判的 route layer，默认 project-first，设备只是 route hint。
- 推荐代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/supervisor_channel_session_store.js`
  - `x-hub/grpc-server/hub_grpc_server/src/supervisor_channel_route_facade.js`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/AppModel+MultiProject.swift`
- 实施步骤：
  1. 落地 `xhub.supervisor_channel_session_route.v1`。
  2. 统一 `project scope`、`incident scope`、`device diagnostics scope` 三类 route mode。
  3. 支持 `preferred_device_id`，但设备离线时明确返回：
     - `hub_only_status`
     - `xt_offline`
     - `runner_not_ready`
  4. 保留 provider native thread key，不在 Hub 内重新发明 thread id。
- DoD：
  - 同一会话默认只落一个 scope。
  - project 路由与 device 路由不会互相污染。
  - XT 离线时不会伪造“已执行”。
- 回归样例：
  - 一个飞书群误连到两个项目。
  - device diagnostics 命令污染项目主会话。
  - preferred device 离线后静默丢消息。
- 证据：
  - `build/reports/xt_w3_24_i_supervisor_route_binding_evidence.v1.json`

### 7.4 `XT-W3-24-J` Slack Operator Adapter

- 目标：把 Slack 作为首版企业 operator channel，支持 thread-aware 查询、审批、按钮动作和主动推送。
- OpenClaw 参考：
  - `src/slack/monitor/message-handler/prepare.ts`
  - `src/agents/tools/slack-actions.ts`
  - `src/gateway/server-http.ts`
  - `src/channels/plugins/onboarding/slack.ts`
- 推荐代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/channel_adapters/slack/SlackIngress.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_adapters/slack/SlackEgress.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_adapters/slack/SlackInteractiveActions.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_adapters/slack/SlackHealth.js`
- 实施步骤：
  1. 建立 Slack ingress：socket/webhook 二选一，但首版只保留一条主链，避免双入口并存。
  2. 固化 `thread_ts` / channel id / DM routing 语义。
  3. 支持 `status / blockers / queue / pending grants / approve / reject / continue / pause / retry`。
  4. 增加 interactive button / action callback 到 structured action 主链。
  5. 输出 runtime snapshot 与 health probe。
- DoD：
  - Slack thread 可以稳定绑定到一个 project scope。
  - 按钮动作不会绕过 grant / audit。
  - status + approve + push summary 三条主线都可 smoke。
- 回归样例：
  - `thread_ts` 丢失导致跨 thread 串线。
  - interactive callback 无审计。
  - 群聊消息在缺 allowlist 时仍放行。
- 证据：
  - `build/reports/xt_w3_24_j_slack_operator_evidence.v1.json`

### 7.5 `XT-W3-24-K` Telegram Operator Adapter

- 目标：把 Telegram 作为轻量 operator / oncall channel，支持 DM、group topic、inline approval 与受控流式回执。
- OpenClaw 参考：
  - `src/telegram/webhook.ts`
  - `src/telegram/inline-buttons.ts`
  - `src/telegram/targets.ts`
  - `src/telegram/draft-stream.ts`
  - `src/telegram/bot/delivery.send.ts`
- 推荐代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/channel_adapters/telegram/TelegramWebhook.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_adapters/telegram/TelegramInlineActions.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_adapters/telegram/TelegramDelivery.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_adapters/telegram/TelegramHealth.js`
- 实施步骤：
  1. 固化 webhook secret、allowed updates、body size/timeouts、health path。
  2. 支持 DM 与 group topic binding，topic 作为 `thread_key`。
  3. 支持 inline buttons 审批，scope 受 allowlist / role 约束。
  4. 支持受控流式回执：`progress hint -> final summary`，不暴露 raw CoT。
  5. 输出 provider-native failure/fallback 语义。
- DoD：
  - Telegram webhook 安全主链独立可 smoke。
  - inline approval / status query / final summary 可运行。
  - group topic 与 DM 不串 scope。
- 回归样例：
  - 无 secret token 时 webhook 仍启动。
  - group topic 错误复用 DM scope。
  - inline button 超 scope 仍允许 approve。
- 证据：
  - `build/reports/xt_w3_24_k_telegram_operator_evidence.v1.json`

### 7.6 `XT-W3-24-L` Feishu Operator Adapter

- 目标：把 Feishu 作为企业级项目控制室入口，优先支持 project room、审批卡片、部署计划和状态摘要。
- OpenClaw 参考：
  - 无直接 Feishu adapter；复用 `registry / command-gating / delivery context / status snapshot` 通用 contract
- 推荐代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/channel_adapters/feishu/FeishuIngress.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_adapters/feishu/FeishuCards.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_adapters/feishu/FeishuEgress.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_adapters/feishu/FeishuHealth.js`
- 实施步骤：
  1. 实现 Feishu 事件入口、签名校验、bot 事件与卡片 action 解析。
  2. 支持 `project room -> preferred_device` 绑定模型。
  3. 支持卡片级：
     - approval
     - reject
     - open evidence
     - show blocker
  4. 支持 status / blockers / deploy plan / grant approve 的结构化动作。
  5. 输出 runtime snapshot 与 operator summary。
- DoD：
  - 飞书群能作为 `project control room` 使用。
  - card action 全走 structured action 主链。
  - provider 错误、签名失败、scope 缺失都 fail-closed。
- 回归样例：
  - 卡片回调无签名仍可过。
  - 同群多项目绑定不报错。
  - 设备离线时仍显示“已下发执行”。
- 证据：
  - `build/reports/xt_w3_24_l_feishu_operator_evidence.v1.json`

### 7.7 `XT-W3-24-M` Delivery Outbox + Alert / Heartbeat / Cron Push Plane

- 目标：把主动推送能力做成正式 outbox，不让告警、日报、cron、delivery summary 变成散落脚本。
- OpenClaw 参考：
  - `../Opensource/openclaw-main/ui/src/ui/views/channels.ts`
  - `../Opensource/openclaw-main/src/logging/diagnostic.ts`
- 推荐代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/channel_outbox.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_delivery_jobs.js`
  - `x-terminal/Sources/Supervisor/DeliveryNotifier.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- 实施步骤：
  1. 落地 `xhub.channel_delivery_job.v1`。
  2. 支持 `alert / heartbeat / cron summary / run summary / approval request` 五类 delivery class。
  3. 实现 outbox dedupe、retry-after、cooldown、provider backoff。
  4. 将 runtime health、last error、last success 回写 `channel_runtime_status_snapshot`。
  5. 给 operator console 增加 channel outbox / failures / retry 面板。
- DoD：
  - 主动推送不是直接发一次算一次，而是有正式 job id。
  - 失败不会 silent drop。
  - alert / summary / approval 三类投递都能审计追溯。
- 回归样例：
  - 同一告警双发。
  - provider failure 没有 retry-after。
  - channel outbox job 无法映射回 originating run / incident。
- 证据：
  - `build/reports/xt_w3_24_m_delivery_outbox_evidence.v1.json`

### 7.8 `XT-W3-24-N` Structured Action / Grant / Audit Plane + WhatsApp Hybrid Freeze

- 目标：冻结“哪些动作可从 IM 触发、如何触发、如何审计”，同时把 `WhatsApp` 的两种技术路径明确拆开，禁止混口径推进。
- 推荐代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/channel_action_router.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_grant_bridge.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_audit_events.js`
  - `x-terminal/Sources/AutomationRunner/`
  - `x-terminal/Sources/Tools/DeviceAutomationGateway.swift`
- 实施步骤：
  1. 冻结首批 `structured actions`：
     - `supervisor.status.get`
     - `supervisor.blockers.get`
     - `supervisor.queue.get`
     - `grant.approve`
     - `grant.reject`
     - `deploy.plan`
     - `deploy.execute`
     - `supervisor.pause`
     - `supervisor.resume`
     - `device.doctor.get`
     - `device.permission_status.get`
  2. 每个 action 绑定 `risk_tier + required_grant_scope + allowed_roles + route_mode`。
  3. 所有 IM action 统一写审计：`requested -> queued|approved|denied -> executed`。
  4. `WhatsApp` 明确拆成：
     - `whatsapp_cloud_api`：Hub connector path
     - `whatsapp_personal_qr`：trusted automation runner path
  5. 在 `whatsapp_personal_qr` 未拿到 require-real 证据前，必须维持 `planned / not release-blocking`。
- DoD：
  - IM 侧不存在“自然语言直接高风险 side effect”的未治理捷径。
  - `grant.approve`、`deploy.execute`、`device.*` 都有单一主链。
  - WhatsApp 路径不再混成一个口头“支持”。
- 回归样例：
  - 普通状态查询意外触发 deploy。
  - grant denied 后仍执行。
  - `whatsapp_personal_qr` 旁路 Hub grant 执行本地动作。
- 证据：
  - `build/reports/xt_w3_24_n_action_grant_whatsapp_evidence.v1.json`

## 8) Critical Path

1. `XT-W3-24-G`
2. `XT-W3-24-H`
3. `XT-W3-24-I`
4. `XT-W3-24-J`
5. `XT-W3-24-K`
6. `XT-W3-24-L`
7. `XT-W3-24-M`
8. `XT-W3-24-N`

原因：

- 没有 registry / route / identity，就不该先写具体 provider adapter。
- 没有 structured action / grant / audit plane，就不该把 IM 入口包装成“可执行”。
- `WhatsApp` 只有在前面主链稳定后，才能明确地分到 Hub connector 或 trusted runner 路径。

## 9) Pass Conditions

- `channel_binding_without_scope = 0`
- `external_im_direct_xt_bypass = 0`
- `unauthorized_channel_action = 0`
- `structured_action_without_audit = 0`
- `device_offline_false_success = 0`
- `slack_thread_route_conflict = 0`
- `telegram_topic_scope_leak = 0`
- `feishu_card_callback_unsigned_accept = 0`
- `whatsapp_personal_qr_false_ready = 0`

## 10) Relationship To XT-W3-24 / XT-W3-25 / TAM

这份包完成后，`XT-W3-24` 的“多渠道入口”就不再只是 bot 外壳和 operator console，而是形成真正的 `Supervisor Operator Channel` 主链。

它和另外两组包的关系是：

- `XT-W3-24` 父包：定义多渠道产品面的大目标与首版渠道集合
- 本包：把 Slack / Telegram / Feishu / WhatsApp 的 operator channel 细到可直接写代码
- `XT-W3-25`：把这些 channel 入口真正接到 governed automation / recipe / run timeline
- `trusted_automation`：只承接 `WhatsApp personal` 或其他必须走本机 permission owner 的路径

也就是说，本包解决的是：

- 外部渠道怎么安全地“说”
- `XT-W3-25` 解决的是接下来系统怎么持续地“做”
- `trusted_automation` 解决的是哪些动作最终可以安全地“动设备”
