# X-Hub Client Modes & Connectors v1（可执行规范 / Draft）

- Status: Draft（用于直接落地实现；后续按版本迭代）
- Applies to: “普通终端/第三方客户端” + X-Terminal（统一走 X-Hub 的 AI 与能力控制面）
- Decision (2026-02-12):
  - **默认启用 Mode 2（AI + Connectors）**；用户可在 Client Policy 中选择 **Mode 1（AI-only）**
  - Generic Terminal 默认 capability 预设：**Full**
  - Email Connector MVP：优先 **IMAP + SMTP**
  - Commit 风控默认：**全自动**（不默认 queued；queued/审批作为可选能力保留）
  - Email “撤销窗口 / Undo Send”：默认 **30s**
  - Paid models：**首次人工一次性授权**后，后续 **自动续签/自动放行**（在配额与策略内）

> 本文把“普通终端配合 X-Hub”时的安全承诺讲清楚：X-Hub 能控制什么、不能控制什么；以及如何在“不牺牲终端体验（skills ecosystem 风格）”的前提下，做到 Secrets/付费/联网审计/Kill-Switch 尽可能都在 Hub。

---

## 0) 术语

- **X-Hub**：唯一可信核心（models + grants + audit + memory governance + kill-switch + connectors）
- **Bridge**：X-Hub 内唯一联网进程（具备 network entitlement）；Core 可保持 offline
- **Client**：任何接入 X-Hub 的终端/应用
  - **X-Terminal**：白皮书定义的“深度客户端”（可使用 Hub Memory + Hub Skills）
  - **Generic Terminal**：普通终端/第三方客户端（默认不使用 Hub Memory，不托管 Skills）
- **Connectors**：Hub 侧的“外部系统连接器”（Email/Calendar/Travel/Payments/Shipping/Cloud 等）
  - 原则：**外部动作必须从 Hub 发起**（以便审计、限额、Kill-Switch、Secrets 不出 Hub）
- **Secrets**：OAuth tokens、API keys、Cookie、证书、支付/出票凭证等
- **Audit**：Hub 落库的不可抵赖操作日志（含 AI 调用、connector 调用、grant 决策、kill-switch 变更）
- **Kill-Switch**：Hub 全局开关（禁模型/禁网络/禁 connectors），即时生效、可审计

---

## 1) 两种接入模式（Mode 1 / Mode 2）

### 1.1 Mode 1：AI-only（模型路由器模式）
**目标**：把“模型选择/付费/额度/远程模型的外发风险”收敛到 Hub；但不对客户端本机工具/联网动作负责。

Hub 负责（能承诺）
- 付费模型 API keys 只保存在 Hub（加密存储；客户端拿不到明文 key）
- 模型路由与用量控制（token cap / cost cap / time cap / daily cap）
- 对“Hub 发生的 AI 调用”做审计与 Kill-Switch（禁 paid models / 禁所有模型）
-（可选）对 `HubWeb.Fetch` 做审计与 Kill-Switch（仅限客户端确实走 HubWeb）

Hub 不负责（不能承诺）
- 客户端本机直连互联网的行为审计/拦截
- 客户端本机读取/写入的 Secrets 安全（除非 Secrets 也放在 Hub 并仅通过 Hub API 使用）
- 客户端执行任意本机命令/读写任意文件的后果（Hub 无法“远程杀死”客户端进程）

适用场景
- 用户只想“统一模型入口 + 付费/额度控制”，并接受其它能力不被 Hub 审计/拦截

### 1.2 Mode 2：AI + Connectors（能力代理模式，默认）
**目标**：在不牺牲终端体验的前提下，把“外部动作与 Secrets”尽可能收敛到 Hub，以实现：
`Secrets + 付费 + 联网审计 + Kill-Switch ≈ 都归 Hub（在 Hub 边界内可强保证）`

Hub 负责（能承诺）
- Mode 1 的全部能力（模型路由/付费/额度/审计/Kill-Switch）
- Secrets 只保存在 Hub（Connector secrets + paid model keys），客户端通过能力调用使用
- 外部动作走 Hub Connectors（读邮件/写草稿/发送/归档/订票/订酒店/下单/快递…）
- 对“外部动作”做全量审计（谁、何时、对哪个系统、做了什么、结果如何）
- Kill-Switch 一键“冻结外部动作”（禁 connectors / 禁网络），并可撤销 grants

Hub 仍然不负责（必须讲清楚边界）
- 客户端如果仍可自行直连外部系统（例如客户端自己带 SMTP/IMAP/浏览器自动化），Hub 无法审计/拦截这部分。
  - 解决方案（可选，不强制）：提供“Network Shim / Proxy 配置指南”，让客户端把联网都走 Hub（或至少走 Hub Web/Connectors）。

适用场景
- 希望获得 skills ecosystem 风格“AI 读/写/发/归档邮件、订票、下单”的完整体验，同时要可控/可审计/可冻结

---

## 2) 能力覆盖矩阵（你能对用户说的“承诺”）

| 能力/承诺 | Mode 1（AI-only） | Mode 2（AI+Connectors） |
|---|---|---|
| 付费模型 keys 只在 Hub | Yes | Yes |
| 付费额度/Token/时间控制 | Yes（仅 AI 调用） | Yes（AI 调用 + connectors 可加 spend cap） |
| 联网审计 | 仅 Hub 内的 AI/Web | Hub 内 AI/Web + 全 connectors（更接近“全量”） |
| Kill-Switch | 仅冻结 Hub 能力 | 冻结 Hub 能力 + 冻结外部动作（connectors） |
| 用户邮箱/票务等 Secrets 不落地客户端 | 不保证 | Yes（默认） |
| “完全阻止客户端私自联网” | No | No（除非额外网络约束/代理） |

关键表述建议（避免过度承诺）
- 对外：X-Hub 对 **“经由 Hub 的能力调用”** 提供强审计与 Kill-Switch；Mode 2 让绝大多数关键动作都自然走 Hub，从而“接近全覆盖”。

---

## 3) Client Policy：如何默认 Mode 2，但允许选择 Mode 1

### 3.1 Policy 存储（Hub 侧）
现状（代码已具备，可直接复用做 MVP）
- Hub 已有轻量“客户端白名单”文件：`<hub_base>/hub_grpc_clients.json`（见 `x-hub/grpc-server/hub_grpc_server/src/clients.js` / `x-hub/grpc-server/hub_grpc_server/src/services.js`）。
- 每个 client entry 自带 `capabilities` allowlist（字符串数组）。服务端用 `clientAllows(auth, <capability_key>)` 做拦截：**未声明 capabilities 的老客户端默认全放行**（向后兼容）。

因此 v1 推荐：
- 先用 `hub_grpc_clients.json.capabilities` 作为 Client Policy 的 MVP，不引入新表也能把 Mode 1/2 落地；
- 之后再上 DB 表（`client_policies` / `connector_policies`）承载更复杂的 per-connector 参数（audit_level/retention/spend-cap/allowlists 等）。

`hub_grpc_clients.json`（MVP 结构示例）
```json
{
  "schema_version": "hub_grpc_clients.v1",
  "updated_at_ms": 0,
  "clients": [
    {
      "device_id": "generic_terminal_1",
      "name": "Generic Terminal",
      "token": "axhub_client_...",
      "enabled": true,
      "capabilities": ["models", "events", "ai.generate.local", "ai.generate.paid", "web.fetch", "connectors.email"],
      "allowed_cidrs": ["private", "loopback"],
      "cert_sha256": ""
    }
  ]
}
```

建议的 capability keys（与 Mode 映射）
- Mode 1（AI-only）：允许 `models|events|ai.generate.*`（以及可选 `web.fetch`）；**不包含** `connectors.*`；Generic 默认也不包含 `memory`
- Mode 2（AI+Connectors）：在 Mode 1 基础上增加 `connectors.email`（后续可扩展 `connectors.calendar` / `connectors.travel` …）
- X-Terminal：在 Mode 2 基础上增加 `memory`（Hub memory consumption surface，而不是 memory authority；以及未来 `skills` 相关 capability）

DB 方案（v2，可选）
- `client_policies`
- `connector_policies`（可选：按 connector 单独配置）

`client_policies`（示例字段；比 capabilities 更易表达）
- `client_id`：来自 pairing/mTLS 的稳定标识（不要只用 IP）
- `client_type`：`x_terminal|generic`
- `mode`：`ai_only|ai_plus_connectors`
- `memory_enabled`：bool（默认：x_terminal=true，generic=false）
- `connectors_enabled`：bool（默认：true；当 mode=ai_only 时强制 false）
- `allowed_connectors`：JSON array（默认：`["email"]` 起步）
- `audit_level`：`metadata_only|include_bodies_ephemeral|include_bodies_persisted`（默认：metadata_only）
- `content_retention_ttl_sec`：默认 0 或很小（例如 3600，用于幂等/重放保护）

这里的 `memory` / `memory_enabled` 只表示 client 是否允许消费 Hub memory surface（如 retrieval、context injection、writeback candidate transport），不意味着 client 获得 memory control-plane authority。
真正执行 memory jobs 的 AI 仍由用户在 X-Hub 中通过 `memory_model_preferences` 选择，`Memory-Core` 仍是 governed rule layer，而 durable writes 仍只经 `Writer + Gate`。

### 3.2 Policy 设定入口
需要同时提供：
1) Hub App UI：配对完成后可一键切换 Mode（默认 Mode 2）
2) CLI：`axhubctl/xhubctl client set-mode <client_id> ai_only|ai_plus_connectors`

### 3.3 默认值（推荐）
Generic Terminal（默认 Mode 2）
- `mode=ai_plus_connectors`
- `memory_enabled=false`
- `allowed_connectors=["email"]`
- capabilities（两档预设，便于产品化）
  - Full（推荐默认）：`["models","events","ai.generate.local","ai.generate.paid","web.fetch","connectors.email"]`
  - Balanced（可选，更保守/更少外发面）：`["models","events","ai.generate.local","connectors.email"]`

Generic Terminal（Mode 1 可选）
- `mode=ai_only`
- capabilities（两档预设）
  - Full（推荐）：`["models","events","ai.generate.local","ai.generate.paid","web.fetch"]`
  - Balanced（可选）：`["models","events","ai.generate.local"]`

X-Terminal（深度客户端）
- `mode=ai_plus_connectors`
- `memory_enabled=true`（允许使用 Hub Memory consumption surface；并允许未来 Hub Skills）
- capabilities（推荐）：在 Generic Full 基础上加 `memory`

---

## 4) 授权与执行：不牺牲体验的前提下如何更安全

### 4.1 总原则：把“不可逆动作”做成 Hub 侧的 Commit
为了让 AI 像 skills ecosystem 一样自动完成任务，同时把风险拦在 Hub：
- **Prepare（可逆）**：生成草稿/计划/待发送内容（draft）
- **Commit（不可逆）**：真正发送/下单/出票/转账/删除等（commit）

推荐实现形态
- 对每个 connector action，至少提供：
  - `PrepareXxx(...) -> draft_id`
  - `CommitXxx(draft_id, idempotency_key) -> result`

好处
- 允许“全自动”：客户端/AI 可以直接调用 Commit（在 grants/预算/策略允许时）
- 允许“低摩擦人工介入”（可选能力）：若命中风控（如新收件人/大额/异常域名），Hub 可以把该 commit 变成 `GRANT_DECISION_QUEUED`，让用户在 Hub App/X-Terminal 里一键批准

本项目默认策略（2026-02-12）
- Commit 风控默认 **Auto**：不默认排队；只做审计 + Kill-Switch + 配额/限额。

### 4.2 Grants（权限）建议：把 connectors 纳入 grants 控制面
现状：proto 里 `Capability` 只有 AI/Web。

落地建议（两种都可）
1) 扩展 `Capability`：加入 `CAPABILITY_CONNECTOR_EMAIL_READ/SEND/...`（细粒度）
2) 引入通用 capability：`CAPABILITY_CONNECTOR_CALL` + `connector_id` + `operation`（通用且可扩展）

无论哪种，都必须支持：
- TTL（默认短）
- Quota（次数/金额/收件人域名/航司/酒店/国家等维度）
- 绑定 client（mTLS identity）+ 绑定 project/session（防 token 滥用）
- 可随时撤销（Kill-Switch / RevokeGrant）

Paid models（你已确认的默认策略，2026-02-12）
- 目标：**不牺牲体验**，但避免“任意新终端一连上就能默默烧钱”。
- 策略：`ai.generate.paid` **第一次**需要人工一次性授权；授权后在策略内自动续签/自动批准。

落地（MVP 实现方式，推荐）
1) client capabilities（静态）：
   - Generic Terminal 默认 Full 仍包含 `ai.generate.paid`（表示“允许请求 paid grant”）
2) paid entitlement（动态，一次性开闸）：
   - Hub 在 DB 新增 `paid_entitlements`（或 `client_policies.paid_enabled=true`）记录
   - key（decision）：`(device_id, user_id, app_id)`（更安全；避免“一次授权放开同用户所有设备/所有终端”）
3) RequestGrant 行为：
   - 若 `capability=ai.generate.paid` 且 entitlement 不存在：强制返回 `GRANT_DECISION_QUEUED`（理由：`first_paid_requires_manual`），并推送事件让 Hub UI 处理
   - 人工批准后：写入 entitlement，并批准本次 grant
   - entitlement 存在后：在 `max_ttl_sec/max_token_cap_per_grant/daily_cap/allowed_models` 内自动批准（等价于“自动续签”）

建议的 entitlement 字段（最小集）
- `device_id`, `user_id`, `app_id`
- `enabled`（bool）
- `allowed_models_json`（array，默认允许所有 paid；也可只允许某些）
- `max_ttl_sec`（默认：1800）
- `max_token_cap_per_grant`（默认：5000）
- `daily_token_cap`（默认：按 user/device 配置）
- `approved_by`, `approved_at_ms`, `note`

建议的端到端流程（必须写进实现/测试用例）
1) Generic Terminal 发起 paid 请求：
   - `HubGrants.RequestGrant(capability=AI_GENERATE_PAID, model_id=..., requested_ttl_sec<=1800, requested_token_cap<=5000)`
2) Hub 判断：
   - 若该 `(device_id,user_id,app_id)` 不存在 entitlement：返回 queued，并发出事件给 Hub UI
3) 用户在 Hub App 做一次性授权（ApproveGrant）：
   - Hub 在同一事务里：写入 entitlement + 创建 grant（满足本次请求）
4) 后续同设备再次请求 paid：
   - Hub 检查 entitlement + quota + kill-switch，满足则自动批准（不再打断用户）

请求处理伪代码（HubGrants.RequestGrant，paid 分支）
```text
if capability != ai.generate.paid:
  handle_as_usual()

if kill_switch_active or quota_exceeded:
  deny()

if !client_allows_capability('ai.generate.paid'):
  deny()

ent = db.getPaidEntitlement(device_id, user_id, app_id)
if !ent or !ent.enabled:
  queue(reason='first_paid_requires_manual')
  audit('grant.request.queued', reason)
  return

if model_id not in ent.allowed_models (when configured):
  deny(reason='model_not_allowed')

ttl = min(requested_ttl_sec, ent.max_ttl_sec)
cap = min(requested_token_cap, ent.max_token_cap_per_grant)
approve_grant(ttl, cap)  // auto
```

自动续签（Auto-renew）的定义（避免歧义）
- Hub 不需要“后台自动延长 grant”；只要 entitlement 仍启用，客户端按需再次 `RequestGrant` 时 Hub 自动批准，即达成“续签体验”。
- 若你希望更丝滑：可在 grant 即将过期时由 Hub 主动发 `grant_expiring_soon` 事件提示客户端预取新 grant（可选增强）。

### 4.3 审计（Audit）建议：要能“复盘与追责”，但不默认保存敏感正文
建议新增审计事件类型（示例）
- `connector.email.list`
- `connector.email.get`
- `connector.email.draft.create`
- `connector.email.send`
- `connector.email.archive`

建议默认审计字段
- actor（ClientIdentity）
- connector_id + operation
- target identifiers（message_id/thread_id，不要默认落 body）
- recipients domains（只落域名或哈希，按政策）
- policy decision（allowed/queued/denied + reason）
- idempotency_key + result summary（message_id / provider response id）

正文/附件处理
- 默认不把邮件 body/附件持久化到 audit（只落 metadata）
- 若为幂等或 debug 必须暂存：用 `content_retention_ttl_sec` 控制 TTL，并在到期后物理清除

建议默认（2026-02-12）
- `audit_level=metadata_only`
- `content_retention_ttl_sec=7200`（2 小时；仅用于 draft/commit 的执行缓冲；发送成功立即清除）
- `idempotency_record_retention_days=30`（仅保存 metadata：idempotency_key -> provider ids/message-id/result，用于去重与复盘；不保存正文/附件）

---

## 5) Email 场景（skills ecosystem 体验对齐）最小可行闭环

### 5.1 目标体验
- AI 可以读邮件内容 -> 生成回复 -> 存草稿 -> 发送 -> 归档
- 用户体验不加额外步骤（默认自动），但 Hub 可在高风险时弹出 1 次审批

### 5.2 最小 API（建议）
建议新增 `HubConnectorsEmail` service（或统一 `HubConnectors` + connector_id=email）。

最小操作集
- `ListMessages(query, limit)`
- `GetMessage(message_id, include_body=true|false)`
- `CreateDraft(in_reply_to_message_id, subject, body, to, cc, bcc, attachments_refs)`
- `SendDraft(draft_id, idempotency_key)`（默认走 Outbox + 30s 撤销窗口，见 5.5）
- `Archive(message_id)`

### 5.3 秘钥与授权（OAuth）
（本项目 MVP：优先 IMAP + SMTP）
- IMAP/SMTP 服务器地址、端口、TLS 配置、用户名、**密码/应用专用密码** 仅存 Hub Vault（加密）
- Generic Terminal 不持有邮件账号 secrets（避免把 secrets 暴露给客户端）
- OAuth（Gmail/Microsoft Graph 等）可作为 v2 增强：授权流程由 Hub App 发起并把 refresh token 写入 Vault

### 5.4 风控（不牺牲体验的“最低限度”）
默认自动允许（不打断体验）。以下 queued/审批作为**可选能力**（用户可打开）：
- 新收件人域名（首次出现的外域）
- 收件人数量异常（例如 > N）
- 附件包含疑似敏感（命中 DLP regex）
- 回复内容包含支付指令/转账/验证码等敏感模式
- 触发用户设定的“高价值联系人/高价值域名”保护

（参数都应可配置；用户也可把 queued 全部关闭，保持全自动）

### 5.5 Outbox + 撤销窗口（Undo Send，默认 30s）
目标：默认全自动发送，但给用户一个“几乎不影响体验”的兜底撤销。

原则
- `SendDraft` **不直接**走 SMTP 立即发送；而是写入 Hub Outbox 队列，延迟 `undo_window_sec` 后再真正发送。
- 在窗口内允许取消（Cancel）或替换（Replace draft -> new job）。

建议默认值
- `undo_window_sec = 30`

建议新增的最小 API（如果你希望 Generic Terminal 也能撤销）
- `GetSendJob(send_job_id)` -> status（queued/sent/canceled/failed）
- `CancelSend(send_job_id, reason)`（仅在 queued 且未到期时成功）

Outbox Job（建议字段）
- `send_job_id`, `draft_id`, `idempotency_key`
- `created_at_ms`, `scheduled_send_at_ms`（= now + 30s）
- `status`: `queued|sent|canceled|failed`
- `provider`: `smtp`
- `smtp_message_id`（如果可获得）
- `error_code/error_message`（失败时）

执行模型
- Connector worker 定时扫描 `status=queued AND scheduled_send_at_ms <= now` 的 job，执行 SMTP send
- 发送成功：写 `sent`，并按 retention policy 立即清理正文/附件缓存
- 发送前若 kill-switch/network disabled：保持 queued（或直接 fail/cancel，取决于策略；建议 fail 并记录原因）
- 发送前若被 Cancel：写 `canceled`，并清理缓存

幂等与去重（必须做）
- `SendDraft(draft_id, idempotency_key)`：同一 `(client_id, idempotency_key)` 重复调用必须返回同一个 `send_job_id`，禁止重复发信。
- worker 真正发送时也要二次检查 idempotency（防并发/崩溃重启导致 double-send）。

崩溃恢复（必须做）
- Hub/worker 重启后：
  - `queued` 且未到期的 job：继续等待到期
  - `queued` 且已到期的 job：继续发送（除非 kill-switch 阻断）
  - `sent/canceled/failed`：不再重试（failed 是否重试取决于策略；MVP 建议不自动重试，避免重复发送）

审计建议（新增事件）
- `connector.email.send.queued`
- `connector.email.send.sent`
- `connector.email.send.canceled`
- `connector.email.send.failed`

---

## 6) “不保存 Hub 记忆”与“仍然可控/可审计”的兼容方式

### 6.1 需要区分三类持久化
1) **AI Memory（对话/长期记忆）**：可选关闭（Generic Terminal 默认关闭）
2) **Secrets**：必须持久化（否则无法长期使用 connectors / paid models）
3) **Audit**：必须持久化（否则无法实现审计/追责/异常检测）

结论
- “普通终端不使用 Hub 记忆”不等于 Hub 不存任何东西；至少要存 `secrets + audit + policy`。

### 6.2 Generic Terminal 的默认姿势（推荐）
- `memory_enabled=false`（不写 thread/turns/canonical）
- `connectors_enabled=true`（所有外部动作走 Hub）
- `audit_level=metadata_only`（内容不长期落库）

即使未来某类 Generic client 开启 `memory_enabled=true`，它也仍然只是消费 Hub memory surface，而不是获得 memory authority；memory executor 选择继续留在 X-Hub，durable writes 继续只经 `Writer + Gate`。

---

## 7) 安全注意事项（必须提前定的边界）

### 7.1 “审查 skills 就够了”并不成立（但仍然必须做）
原因
- prompt injection 来自邮件/网页内容，不依赖恶意 skill；AI 可能被诱导去“做坏事”
对策
- 把不可逆动作变为 Hub Commit（4.1）
- 在 Hub 做 policy/rate-limit/spend-cap/allowlist

### 7.2 Hub 被攻破的风险：不要把“可执行任意代码”塞进 Hub Core
建议
- Connectors 运行在隔离进程/容器（至少独立进程 + 最小权限）
- Hub Core 不加载第三方未签名插件
- Skills（第三方脚本）默认在客户端或独立 Runner 执行，Hub 只提供能力 API（Connectors）

---

## 8) 落地计划（按最短路径）

Phase 0（设计与骨架）
- 用 `hub_grpc_clients.json.capabilities` 先落地 Mode 1/2（MVP）；后续再上 `client_policies`（DB）+ UI/CLI 切换 mode
- 将 connectors 作为 capability 纳入 grants + audit
- Paid models：增加“一次性人工授权 -> entitlement -> 后续自动批准/续签”的策略与数据结构（见 4.2）
- 定义 audit schema（connector.*）

Phase 1（Email Connector MVP）
- IMAP/SMTP 配置与凭证写入 Hub Vault（加密）
- Email connector：list/get/draft/send/archive
- SendDraft：实现 Outbox + UndoSend=30s（默认），并提供 CancelSend（可选但推荐）
- Prepare/Commit + idempotency（queued 审批作为可选能力）

Phase 2（扩展）
- Calendar / Travel / Shipping / Cloud Drive connectors
- spend cap / vendor allowlist
- 异常检测（基于 audit 的简单规则）

---

## 9) 与其它规范的关系
- 远程模型外发、敏感级别、DLP、redaction：见 `docs/xhub-memory-core-policy-v1.md`
- 传输层 TLS/mTLS、pairing、tunnel：见 `protocol/` 与 `x-hub/grpc-server/hub_grpc_server/README.md`
