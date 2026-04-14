# XT-W3-24 Safe Operator Channel Onboarding Automation Implementation Pack v1

- version: v1.0
- updatedAt: 2026-03-26
- owner: Hub-L5（Primary）/ XT-L2 / Security / QA / Product
- status: preview-working
- scope: `XT-W3-24-O/P/Q/R/S`；把 `Slack / Telegram / Feishu / WhatsApp Cloud API` 的首次接入收敛成 `unknown ingress quarantine -> admin approve once -> auto-bind -> first smoke`
- parent:
  - `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-hub-security-impact-gate-v1.md`
  - `docs/xhub-connectors-isolation-and-runtime-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `protocol/hub_protocol_v1.proto`

## 0) Why This Pack Exists

`XT-W3-24-G..N` 已经把多渠道 operator 主链补到“可治理、可路由、可审计”的程度，但现在第一次接入仍然太工程化：

1. 要先启动 Hub。
2. 要先启动 provider worker。
3. 要配置 provider webhook 或 polling。
4. 要手工建 `identity binding`。
5. 要手工建 `channel binding`。
6. 然后第一条消息才真的能用。

这条链路的问题不是“做不到”，而是：

- 用户第一次接入时体验很重。
- 工程师容易为了提速去手工放大权限或绕开 binding 主链。
- 安全上最脆弱的恰好就是第一次接入，因为这时最容易出现“先通了再补治理”的偷跑。

本包只解决这一段：把首次接入变成安全优先、自动化优先、但不降低 Hub 边界的标准流程。

## 1) Finished State

完成后，首版至少要满足以下事实：

1. `Slack / Telegram / Feishu` 的第一次消息进入 Hub 后，如果发送者或会话还没绑定，不会直接报工程错误，也不会直接跑副作用。
2. Hub 会自动创建 `pending discovery ticket`，把这次未知接入收口到待审核队列。
3. 未知接入只能进入 `quarantine / discovery`，不得触发：
   - `deploy.execute`
   - `grant.approve`
   - `device.*`
   - `connector.send`
   - 任何写 canonical memory 的高风险动作
4. 管理员只需要做一次明确批准：
   - 选定这是哪个 Hub user
   - 选定这是哪个 project / scope
   - 选定这是 DM、group 还是 thread/topic 级绑定
   - 选定允许的低风险动作集合
5. 批准后，Hub 自动写入：
   - `xhub.im_identity_binding.v1`
   - `xhub.supervisor_operator_channel_binding.v1`
6. 写入成功后，Hub 自动发回“已开通”确认，并跑一次低风险 first smoke，优先是：
   - `supervisor.status.get`
   - 或 `supervisor.blockers.get`
7. 高风险动作仍然走原主链，不因为“首次接入自动化”而被静默放权：
   - `structured_action -> policy -> grant -> execute -> audit`
8. 默认仍不暴露 Hub 原始 IP；首次接入也只走 `domain / relay endpoint / tunnel hostname`。
9. `WhatsApp Cloud API` 走同一模型设计，但 release 口径仍受 `require-real` 约束；`whatsapp_personal_qr` 不在本包内冒绿。

## 2) Hard Boundaries

- `unknown ingress` 在批准前只能创建 discovery 记录和安全回复，不能触发外部副作用。
- 首次接入自动化不允许复用 `HUB_ADMIN_TOKEN`；必须继续使用更窄的 `HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN` 或同等级专用 connector 凭证。
- 不允许按昵称、display name、群名、机器人展示名做身份绑定。
- 不允许把 DM 批准自动扩写成 group allowlist。
- 不允许把 group allowlist 自动扩写到该 provider 的所有群。
- 不允许“批准接入”同时隐式发放：
  - `deploy.execute`
  - `grant.approve`
  - `device.permission_grant`
  - `connector.secret.read`
- 不允许 unknown sender 在 IM 里自助完成最终批准。
- 首版管理员批准默认只允许在本地可信管理面完成：
  - Hub UI
  - `axhubctl`
  - 已可信且已绑定的 admin-only operator channel（可选二阶段，不是首版发布前置）
- 不允许为了减少一步操作，把 raw Hub IP 暴露给 provider webhook、operator client 或文档说明。

## 3) OpenClaw Reuse Freeze

本包继续参考本地 `OpenClaw` 代码，但只复用不会冲穿 `Hub-first` 边界的部分。

本地参考根路径（machine-local only）：

- `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main`

### 3.1 可复用的形状

具体参考：

- `src/pairing/pairing-messages.ts`
- `src/pairing/pairing-store.ts`
- `src/commands/doctor-config-flow.ts`
- `src/channels/registry.ts`
- `src/channels/command-gating.ts`
- `src/utils/delivery-context.ts`

冻结结论：

- 复用 `pairing reply` 的产品形状：未知发送者收到明确、可执行、不会暴露内部实现的“待批准”反馈。
- 复用 `pending request -> owner approve once` 的心智模型，但把存储与权限真相源放在 Hub，而不是 provider 本地 pairing store。
- 复用 `doctor` 对空 allowlist / 错误策略的诊断提示形状，用于 Hub admin 审批页的风险提示与补救建议。
- 继续复用 `registry / command-gating / delivery context` 的纯逻辑与字段口径，避免第一次接入又造一套并行 route 语义。

### 3.2 明确禁止复用的部分

- 不复用 OpenClaw 的 `approve pairing code -> 直接写 allowFrom` 这条捷径。
- 不复用 provider-local pairing store 作为授权真相源。
- 不复用 `doctor --fix` 对 live unknown ingress 直接改配置的方式。
- 不复用“消息渠道自己就是权限主体”的模型。

换句话说，本包借的是：

- reply shape
- approve-once 心智
- allowlist 风险提示

不借的是：

- 直接把 unknown sender 塞进 allowFrom 就算完成授权

## 4) Machine-Readable Contracts

### 4.1 `xhub.channel_onboarding_discovery_ticket.v1`

```json
{
  "schema_version": "xhub.channel_onboarding_discovery_ticket.v1",
  "ticket_id": "chan-onb-20260313-001",
  "provider": "feishu",
  "account_id": "default",
  "external_user_id": "ou_xxx",
  "external_tenant_id": "tenant_001",
  "conversation_id": "oc_xxx",
  "thread_key": "",
  "ingress_surface": "group",
  "first_message_preview": "status",
  "proposed_scope_type": "project",
  "proposed_scope_id": "payments-prod",
  "recommended_binding_mode": "conversation_binding",
  "status": "pending",
  "created_at_ms": 1773331200000,
  "expires_at_ms": 1773417600000,
  "audit_ref": "audit-chan-onb-001"
}
```

### 4.2 `xhub.channel_onboarding_approval_decision.v1`

```json
{
  "schema_version": "xhub.channel_onboarding_approval_decision.v1",
  "decision_id": "chan-onb-decision-001",
  "ticket_id": "chan-onb-20260313-001",
  "decision": "approve",
  "approved_by_hub_user_id": "user_ops_admin",
  "approved_via": "hub_local_ui",
  "hub_user_id": "user_ops_alice",
  "scope_type": "project",
  "scope_id": "payments-prod",
  "preferred_device_id": "xt-mac-mini-bj-01",
  "allowed_actions": [
    "supervisor.status.get",
    "supervisor.blockers.get",
    "supervisor.queue.get"
  ],
  "grant_profile": "low_risk_readonly",
  "audit_ref": "audit-chan-onb-decision-001"
}
```

### 4.3 `xhub.channel_onboarding_auto_bind_result.v1`

```json
{
  "schema_version": "xhub.channel_onboarding_auto_bind_result.v1",
  "ticket_id": "chan-onb-20260313-001",
  "identity_binding_ref": "xhub.im_identity_binding.v1:feishu/ou_xxx",
  "channel_binding_ref": "xhub.supervisor_operator_channel_binding.v1:bind-feishu-payments-prod",
  "transaction_id": "chan-onb-tx-001",
  "status": "committed",
  "idempotency_key": "sha256:...",
  "audit_ref": "audit-chan-onb-bind-001"
}
```

### 4.4 `xhub.channel_onboarding_first_smoke_receipt.v1`

```json
{
  "schema_version": "xhub.channel_onboarding_first_smoke_receipt.v1",
  "smoke_id": "chan-onb-smoke-001",
  "ticket_id": "chan-onb-20260313-001",
  "provider": "feishu",
  "conversation_id": "oc_xxx",
  "thread_key": "",
  "command_name": "supervisor.status.get",
  "result": "success",
  "route_mode": "hub_only_status",
  "completed_at_ms": 1773331215000,
  "audit_ref": "audit-chan-onb-smoke-001"
}
```

### 4.5 Existing APIs To Reuse

本包默认复用已有 Hub Runtime API，不重造并行执行面：

- `GetChannelRuntimeStatusSnapshot`
- `UpsertChannelIdentityBinding`
- `ListChannelIdentityBindings`
- `UpsertSupervisorOperatorChannelBinding`
- `ListSupervisorOperatorChannelBindings`
- `EvaluateChannelCommandGate`
- `ResolveSupervisorChannelRoute`
- `ExecuteOperatorChannelHubCommand`

新增工作主要是：

1. discovery ticket 与审批编排
2. 批准后的自动写 binding 事务
3. first smoke 与失败可解释回执

## 5) Safe Automation Flow

### 5.1 Unknown First Message

1. provider worker 收到第一条消息。
2. 先做 provider 原生验签、replay guard、body cap、allow-from 前置校验。
3. 归一化：
   - provider stable user id
   - tenant/account id
   - conversation id
   - thread/topic key
4. 查已有 `identity binding + channel binding`。
5. 若已存在且 active，走常规 `gate -> route -> execute` 主链。
6. 若不存在，进入 discovery。

### 5.2 Discovery / Quarantine

1. Hub 创建 `discovery ticket`。
2. 同一 `provider + account + external_user_id + conversation_id + thread_key` 组合必须 dedupe。
3. 默认返回 provider-native 安全消息：
   - 已收到
   - 当前未授权执行
   - 管理员批准后可使用
   - 不泄露内部路径、token、Hub 地址
4. discovery 只允许：
   - 写 ticket
   - 写审计
   - 发安全回复

### 5.3 Admin Approve Once

1. 本地可信管理员在 Hub UI 或 `axhubctl` 里看到待审核 ticket。
2. 管理员选定：
   - 映射到哪个 Hub 用户
   - 绑定到哪个 project / incident / diagnostics scope
   - 这是 DM、group 还是 thread/topic 绑定
   - 低风险 allowed actions
   - 可选 `preferred_device_id`
3. Hub 写 `approval decision` 审计。

### 5.4 Auto-Bind

1. Hub 事务式写入 `identity binding`。
2. Hub 事务式写入 `channel binding`。
3. 失败必须：
   - fail-closed
   - 保留 ticket
   - 返回确定性错误原因
   - 不得形成半绑定状态

### 5.5 First Smoke

1. 批准成功后，Hub 自动回发确认消息。
2. Hub 自动执行一次低风险 smoke：
   - `supervisor.status.get` 优先
   - 路由不可用时降级到 `hub_only_status`
3. 把结果写入 `xhub.channel_onboarding_first_smoke_receipt.v1`。
4. 若失败，回发明确下一步：
   - `xt_offline`
   - `runner_not_ready`
   - `scope_missing`
   - `provider_delivery_failed`

## 6) First-Use Flows By Channel

### 6.1 Slack

目标流程：

1. 运营侧只需要安装 Slack app 并启动 Slack worker。
2. 用户在目标 DM 或 thread 里发第一条消息，例如 `status`。
3. Hub 自动创建 discovery ticket，并在 Slack 内回“待管理员批准”。
4. 管理员在本地 Hub UI/CLI 批准一次。
5. Hub 自动写好 identity + channel binding，并回发第一次 `status` 结果。

首版不要求用户手工调用 binding API。

### 6.2 Telegram

目标流程：

1. 运营侧只需要配置 webhook 或 polling worker。
2. 用户在 DM 或 group topic 里发第一条消息。
3. Hub 自动创建 discovery ticket，topic 作为 `thread_key`。
4. 管理员批准一次后，自动完成绑定并回第一次 low-risk 结果。

### 6.3 Feishu

目标流程：

1. 运营侧只需要把 bot 加到目标群并启动 Feishu worker。
2. 用户在目标 project room 发第一条消息。
3. Hub 自动创建 discovery ticket。
4. 管理员本地批准一次，选定 project 与 room 绑定。
5. Hub 自动回发“已开通 + 当前状态摘要”。

### 6.4 WhatsApp Cloud API

目标流程与前三者一致，但 release 口径继续受 `require-real` 约束：

1. 设计和实现可以并行推进。
2. 没有真实证据前，不得对外宣称“已接好”。
3. `whatsapp_personal_qr` 继续留在 `trusted_automation + local runner` 路径，不并入本包的 Hub connector 首次接入主链。

## 7) Gate / KPI

### 7.1 Gate

- `XT-CHAN-ONB-G0`：未知 ingress 能稳定创建 discovery ticket，且 approval 前零副作用。
- `XT-CHAN-ONB-G1`：本地管理员审批面可用，decision model 冻结。
- `XT-CHAN-ONB-G2`：auto-bind 事务闭环可用，零半绑定。
- `XT-CHAN-ONB-G3`：批准后 first smoke 可跑，失败可解释且不 silent drop。
- `XT-CHAN-ONB-G4`：安全回归、release wording、证据与 `require-real` 边界完整。

### 7.2 KPI

- `unknown_ingress_side_effect_before_approval = 0`
- `approve_once_to_first_status_p95_ms <= 120000`
- `manual_binding_api_calls_for_wave1 = 0`
- `auto_binding_partial_commit = 0`
- `display_name_based_binding = 0`
- `dm_to_group_auto_expand = 0`
- `silent_onboarding_failure = 0`
- `first_smoke_high_risk_action = 0`

## 8) Direct-Execution Work Orders

### 8.1 `XT-W3-24-O` Unknown Ingress Quarantine + Discovery Queue

- 目标：把首次未知消息统一收敛到 Hub discovery queue，而不是让各 provider adapter 自己散落处理。
- 推荐代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/channel_onboarding_discovery_store.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_onboarding_discovery_service.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_adapters/*/*OperatorWorkerRuntime.js`
- 实施步骤：
  1. 为 Slack / Telegram / Feishu / WhatsApp Cloud 统一抽出 unknown ingress 判定。
  2. 落地 `xhub.channel_onboarding_discovery_ticket.v1` 存储与 TTL。
  3. 做同源 dedupe、replay-safe、idempotency。
  4. 对 provider 回安全回复，不直接报 500 或技术细节。
  5. 给本地管理员暴露 `list/get pending discovery tickets` 查询面。
- DoD：
  - 未知消息不会直接掉到工程错误日志里后静默失败。
  - 同一 unknown sender 不会刷出无穷重复 ticket。
  - discovery 前不会触发 `ExecuteOperatorChannelHubCommand`。
- 回归样例：
  - unknown Slack thread 直接触发 `status` 执行。
  - Telegram topic 重复刷票导致队列膨胀。
  - Feishu 卡片回调在未绑定状态下落到 side effect。
- 证据：
  - `build/reports/xt_w3_24_o_safe_discovery_queue_evidence.v1.json`

### 8.2 `XT-W3-24-P` Admin Approval Wizard + Decision Model

- 目标：把管理员批准做成一条正式、安全、可理解的本地主链，而不是让工程师手填 binding JSON。
- 推荐代码落点：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/OperatorChannelsOnboardingView.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `protocol/hub_protocol_v1.proto`
- 实施步骤：
  1. 增加 pending ticket 列表与详情。
  2. 审批时必须显式选择：
     - `hub_user_id`
     - `scope_type/scope_id`
     - `binding surface`
     - `allowed_actions`
     - `preferred_device_id`（可选）
  3. 支持 `approve / reject / hold` 三种稳定决策。
  4. 所有决策都写 `approval decision` 审计。
  5. 首版默认只允许本地可信管理面批准；已可信 admin operator channel 审批作为二阶段能力，不阻塞首版。
- DoD：
  - 不需要工程师手工调用两个 upsert API 才能完成首次接入。
  - 审批界面能明确显示 stable id、conversation id、thread key、provider、建议 scope。
  - 审批动作不会复用 admin token 给 connector worker。
- 回归样例：
  - 按 display name 审批。
  - 直接把 DM 审批扩写为所有群。
  - unknown sender 在 IM 里自助批准自己。
- 证据：
  - `build/reports/xt_w3_24_p_approval_wizard_evidence.v1.json`

### 8.3 `XT-W3-24-Q` Auto-Bind Transaction Writer

- 目标：把批准后的 identity + channel binding 写成单一事务语义，避免半成功。
- 推荐代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/channel_identity_store.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_bindings_store.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_onboarding_transaction.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- 实施步骤：
  1. 批准前再次校验 ticket 是否仍有效、stable ids 是否未漂移。
  2. 写 `UpsertChannelIdentityBinding`。
  3. 写 `UpsertSupervisorOperatorChannelBinding`。
  4. 回写 auto-bind receipt 与审计。
  5. 失败时必须可重试、可回滚、可解释。
- DoD：
  - 没有“人绑好了 identity 但忘了绑 conversation”的半状态。
  - 幂等重复批准不会产出重复 binding。
  - auto-bind 不会顺手授予高风险动作。
- 回归样例：
  - 批准后只写 identity 不写 channel。
  - conversation id 漂移后仍把旧 ticket 写活。
  - allowed actions 意外含 `deploy.execute`。
- 证据：
  - `build/reports/xt_w3_24_q_auto_binding_evidence.v1.json`

### 8.4 `XT-W3-24-R` First Smoke + Guided Reply

- 目标：批准后立即给出“已经真的能用”的低风险反馈，避免用户还要再试一轮才知道通没通。
- 推荐代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/channel_outbox.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_onboarding_reply_builder.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_adapters/*/*Egress.js`
- 实施步骤：
  1. 批准成功后自动发一条 provider-native 成功确认。
  2. 自动跑一次 first smoke，默认 `supervisor.status.get`。
  3. 如 route 未就绪，显式返回 `hub_only_status|xt_offline|runner_not_ready`。
  4. 把结果写 `xhub.channel_onboarding_first_smoke_receipt.v1`。
  5. 失败时附稳定 remediation hint，而不是 silent drop。
- DoD：
  - 用户批准后能直接看到第一条真实结果。
  - first smoke 限定在 low-risk 集合。
  - 失败不会被误描述成“已连接”。
- 回归样例：
  - first smoke 直接调用 `deploy.execute`。
  - route 失败但 UI 显示 success。
  - provider delivery 失败后没有重试或说明。
- 证据：
  - `build/reports/xt_w3_24_r_first_smoke_evidence.v1.json`

### 8.5 `XT-W3-24-S` Security Regression + Release Wording + Require-Real Boundary

- 目标：把“安全自动化首次接入”收成发布可判定的证据包，而不是口头上说已经自动化。
- 推荐代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/operator_channels_service_api.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_adapters/*/*.test.js`
  - `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-hub-security-impact-gate-v1.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`
- 实施步骤：
  1. 增加以下回归：
     - approval 前零 side effect
     - display name 不参与授权
     - DM 不自动扩 group
     - auto-bind 不隐式放权
     - first smoke 仅低风险
  2. 固定 release wording：
     - `Slack / Telegram / Feishu` 为 wave1 safe onboarding
     - `WhatsApp Cloud API` 设计已接线但未有 require-real 前不得口头冒绿
     - `whatsapp_personal_qr` 仍走 local trusted automation
  3. 出具 require-real 与 release-ready 证据。
- DoD：
  - 这套首次接入自动化不会削弱现有 Hub 安全门。
  - 发布口径与真实证据一致。
  - 没有“体验自动化了，权限也顺带自动放开了”的倒挂。
- 回归样例：
  - 未批准消息触发 action。
  - 批准一次后所有群都变可用。
  - WhatsApp Cloud 在无真实样本时被标成 ready。
- 证据：
  - `docs/open-source/evidence/xt_w3_24_s_safe_onboarding_release_evidence.v1.json`
- 2026-03-25 进展补记：
  - `invalid token / signature mismatch / replay suspicion` 现在都已在 live-test evidence 层有显式回归，不再只停留在底层 repair-hint 规则。
  - `operator_channel_live_test_evidence.test.js` 已覆盖：
    - `verification_token_invalid -> required_next_step`
    - `signature_invalid -> required_next_step`
    - `replay_detected -> required_next_step`
  - `channel_onboarding_admin_http.test.js` 已补 `Slack signature_invalid` 的 admin endpoint 端到端断言，确保不是只有纯函数层通过。
  - Hub 本地 Swift `LiveTestEvidenceBuilder` 也已加 parity tests；当前包验证被 `MainPanelView.swift` 一带的现有编译错误阻塞，需等该处收口后再把 Swift 侧验证补绿。
- 2026-03-26 进展补记：
  - `MainPanelView.swift` 的重复 `HubTaskType`、缺失通知 digest 依赖、bench 可选值阻塞已收掉，`OperatorChannelsOnboardingSupportTests` / `ModelLibrarySectionPlannerTests` / `ModelLibraryUsageDescriptionBuilderTests` 都已跑绿。
  - 已新增 tracked evidence packet：`docs/open-source/evidence/xt_w3_24_s_safe_onboarding_release_evidence.v1.json`
  - 已新增一键生成脚本：`scripts/generate_xt_w3_24_s_safe_onboarding_release_evidence.js`
  - 已新增 focused gate：`scripts/ci/xt_w3_24_s_safe_onboarding_gate.sh`
  - 已新增 GitHub Actions workflow：`.github/workflows/xt-w3-24-safe-onboarding-gate.yml`
  - Hub 本地 `OperatorChannelsOnboardingView` 现在已补 provider-first 首次接入总览，会按 provider 显示 runtime / readiness / pending review / next step，不再只靠工单列表承载 first-run 壳。
  - 首次接入总览卡片现在也已按状态输出 CTA：
    - 待审核 provider 直接给 `审阅工单`
    - 已有历史工单且当前 ready 的 provider 直接给 `查看`
    - runtime / readiness 未就绪的 provider 直接给 `复制配置包` + `重新加载状态`
  - 这意味着 first-run 壳已不只是“展示当前状态”，而是开始提供 provider-first 的最短修复 / 审阅入口。
  - 当前剩余缺口主要是把该包接进更宽 public release checklist，以及 first-run product shell，而不是 repair path 或 parity coverage 缺失。

## 9) Critical Path

1. `XT-W3-24-O`
2. `XT-W3-24-P`
3. `XT-W3-24-Q`
4. `XT-W3-24-R`
5. `XT-W3-24-S`

依赖说明：

- `O` 默认依赖 `XT-W3-24-H/I/F`，因为没有 identity、binding、route、安全边界就不该做 discovery 自动化。
- `Q` 默认复用 `UpsertChannelIdentityBinding` 与 `UpsertSupervisorOperatorChannelBinding`，不新建平行存储。
- `R` 默认依赖 `XT-W3-24-J/K/L/M` 的 provider egress 与 outbox 主链。

## 10) Pass Conditions

- `unknown_ingress_side_effect_before_approval = 0`
- `approval_without_audit = 0`
- `auto_binding_partial_commit = 0`
- `display_name_based_binding = 0`
- `dm_to_group_auto_expand = 0`
- `manual_binding_api_calls_for_wave1 = 0`
- `first_smoke_high_risk_action = 0`
- `silent_onboarding_failure = 0`

## 11) Relationship To XT-W3-24-G..N

这份包不是替代 `XT-W3-24-G..N`，而是把那条主链补成“第一次就能安全用”的产品闭环：

- `G/H/I` 解决 registry、identity、route 主体问题。
- `J/K/L/M` 解决多 provider adapter 与 outbox。
- `N` 解决 structured action / grant / audit / WhatsApp split。
- 本包 `O..S` 解决第一次接入如何安全地从“未知”变成“已治理可用”。

没有这份包，多渠道入口依然是“工程上能接”，但不是“产品上真能用”。
