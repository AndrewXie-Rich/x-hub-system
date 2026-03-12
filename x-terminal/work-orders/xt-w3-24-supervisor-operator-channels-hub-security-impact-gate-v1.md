# XT-W3-24 Supervisor Operator Channels Hub Security Impact Gate v1

- version: v1.0
- updatedAt: 2026-03-12
- owner: Hub-L5（Primary）/ Security / QA / XT-L2 / Product
- status: planned
- scope: `XT-W3-24-G..N` 的 `Hub` 安全冲击评估、release 前置门禁与 fail-closed 实施清单
- parent:
  - `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md`
  - `docs/xhub-connectors-isolation-and-runtime-v1.md`
  - `docs/xhub-client-modes-and-connectors-v1.md`
  - `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## 0) Why This Gate Exists

`Hub-first` 仍然是 `Slack / Telegram / Feishu / WhatsApp` 多渠道入口的正确方向，但这条路线会把 `Hub` 从“主要承接 paired client + gRPC control-plane”的节点，升级成“长期承接外部 IM webhook / callback / operator ingress”的边界服务。

这不会自动否定 `Hub-first`，但会显著提高 `Hub` 的安全要求：

1. 外部 `untrusted ingress` 会长期打到 Hub 边界。
2. provider secrets / webhook secrets / bot tokens 会进一步集中到 Hub。
3. `Hub` 若被打穿，blast radius 会大于单台 XT 设备。
4. channel 流量峰值、重试风暴、provider 回调异常会直接冲击 Hub 可用性。
5. 若身份绑定、structured action、grant bridge 任一层做弱，风险会直接从“读状态”升级为“批量高风险 side effect”。

所以本文件的作用不是扩 scope，而是把一句“安全优先”变成 release 前必须满足的硬门禁。

## 1) Security Position

### 1.1 架构立场不变

- 外部 IM 继续只对 `Hub Supervisor Facade` 讲话。
- `Hub` 继续持有 `auth / policy / grant / audit / kill-switch / secret residency` 真相源。
- `XT` 只作为 route target 或 `trusted_automation` 本地执行面，不暴露为外部 IM 的直接入口。

### 1.2 复用立场

可以复用当前 Hub 里已经存在的安全原语：

- `pairing_http.js` 中的 preauth / body cap / replay guard / ingress audit 原语
- `connector_ingress_authorizer.js` 中的 `dm/group/webhook` allowlist 语义
- `db.js` 中的持久化 replay guard 表与 claim 逻辑
- `auth.js` / `services.js` 中的 client auth、capability gate、deny_code 语义

但下面两条必须冻结：

- 可以复用这些原语，不等于可以把“长期 provider webhook 入口”永久保留在现有主 Hub pairing/admin 暴露面里。
- 可以复用 channel ingress 基础设施，不等于允许“自然语言 -> 高风险 side effect”的执行捷径回流到 Hub。

### 1.3 Release 立场

首版内部开发允许用现有原语快速收敛，但 `release-ready` 必须满足：

1. provider webhook termination 与主 `hub_grpc_server` 控制面至少做到 `dedicated listener or dedicated ingress worker` 的隔离。
2. pairing/admin/public install 路由不得与长期 operator webhook 暴露面共用同一默认公开入口。
3. 所有 provider ingress 必须默认 `fail-closed`，`audit_write_failed` / `replay_guard_error` / `signature_invalid` / `scope_missing` 时不可继续向下游推进。
4. 默认不暴露 Hub 原始 IP；provider、operator 客户端与公开安装流只接触 `domain / relay endpoint / tunnel hostname`。

## 2) Main Security Risks

### 2.1 外部 Ingress 面扩大

- 风险：Slack/Telegram/Feishu webhook、card callback、button action 变成长期对 Hub 开放的公网/半公网入口。
- 后果：请求洪泛、异常 payload、解析崩溃、状态机卡死会直接冲击 Hub。
- 说明：隐藏 Hub 原始 IP 可以降低直扫与误暴露概率，但不会消除逻辑层攻击面；真正公开的是 `domain / relay ingress`，不是“没有暴露面”。

### 2.2 身份绑定混淆

- 风险：把昵称、display name、群名、机器人文本字段当成授权主体。
- 后果：cross-project route leak、越权审批、错误 deploy。

### 2.3 Structured Action 升级错误

- 风险：自然语言或弱解析结果直接落到 `deploy.execute / device.* / connector.send / grant.approve`。
- 后果：Hub 从“治理平面”退化成“bot 直接执行器”。

### 2.4 Secret Residency 漂移

- 风险：bot token、webhook secret、session cookie、QR/local session 被写入 XT、本地文件、prompt bundle、日志或 canonical memory。
- 后果：Hub 被绕开；一旦终端或日志泄露，整条 channel 被接管。

### 2.5 可用性与 DoS

- 风险：provider retry storm、callback loop、outbox 回压、receipt/order/replay guard 热点写入，拖慢 Hub gRPC / pairing / audit。
- 后果：Hub 明明没被攻破，但先不可用。

### 2.6 Memory / Audit 污染

- 风险：原始 IM payload、附件、链接、群消息历史直接进入 canonical memory 或长留审计。
- 后果：secret 外溢、memory poisoning、token 浪费、scope 污染。

### 2.7 XT Bypass

- 风险：外部 IM 通过 route shortcut、local runner shortcut、provider callback shortcut 直接调用 XT 或 `device.*`。
- 后果：Hub-first 形同虚设。

## 3) Hard Invariants

- `external_im_direct_xt_bypass = 0`
- `natural_language_direct_side_effect = 0`
- `provider_secret_in_xt_runtime = 0`
- `raw_channel_payload_to_canonical_memory = 0`
- `audit_write_failed_but_continue = 0`
- `device_offline_false_success = 0`
- `identity_binding_by_display_text = 0`
- `group_scope_auto_expands_from_dm = 0`
- `provider_webhook_unsigned_accept = 0`
- `provider_webhook_replay_accept = 0`

## 4) Security Gates

### 4.1 `XH-CHAN-SI-G0` Ingress Topology Isolation

- 要求：
  - 默认不向 provider、operator 客户端、公开安装流分发 Hub 原始 IP。
  - 对外只暴露 `domain / relay endpoint / tunnel hostname`。
  - provider webhook / callback ingress 必须运行在 `dedicated listener` 或 `dedicated ingress worker`。
  - 不允许把长期 channel webhook 默认继续和 pairing/admin/public install 共用一个公开入口。
  - ingress worker 只做：签名校验、replay、allowlist、provider normalize、速率限制、审计写入、结构化 envelope 产出。
  - ingress worker 不持有 `deploy/device/grant commit` 权限。
- 可复用：
  - 当前 `pairing_http.js` 的 preauth / audit / replay / ordering / receipt primitives 可直接借。
- No-Go：
  - 若 provider 配置、client discovery、operator 文档、诊断输出里默认暴露 Hub 原始 IP，直接 `NO_GO`。
  - 若 release 版本仍把 `/pairing/*`、`/admin/pairing/*` 与长期 `/webhook/connectors/*` 暴露在同一默认公开 listener，直接 `NO_GO`。
- 证据：
  - `build/reports/xt_w3_24_si_g0_ingress_topology_evidence.v1.json`

### 4.2 `XH-CHAN-SI-G1` Signature / Replay / Allowlist / Body Cap

- 要求：
  - 每个 provider 都必须有签名校验。
  - replay guard 必须持久化，Hub 重启后仍能拒绝重复事件。
  - 必须有 per-source/per-target rate limit、unauthorized flood breaker、body size cap。
  - `audit_write_failed` 必须 fail-closed。
- 可复用：
  - `connector_ingress_authorizer.js`
  - `pairing_http.js:createWebhookReplayGuard`
  - `db.js:connector_webhook_replay_guard`
- 证据：
  - `build/reports/xt_w3_24_si_g1_webhook_hardening_evidence.v1.json`

### 4.3 `XH-CHAN-SI-G2` Stable Identity Binding + Scope Separation

- 要求：
  - 授权主体只认 provider stable id。
  - DM / group / topic / thread 必须独立 allowlist 与 binding。
  - `dm_pairing` 不得自动升级为 `group allowlist`。
  - `grant.approve`、`deploy.execute`、`device.*` 只能由显式角色触发。
- No-Go：
  - 若出现 display name / nickname / room title 驱动的授权判断，直接 `NO_GO`。
- 证据：
  - `build/reports/xt_w3_24_si_g2_identity_scope_evidence.v1.json`

### 4.4 `XH-CHAN-SI-G3` Structured Action Quarantine

- 要求：
  - 所有外部 IM 输入先编译成 allowlisted `structured action`。
  - 只允许 slash command、button/card action、固定模板参数触发高风险动作。
  - 普通自然语言最多触发 `status / blockers / queue / help` 级别查询。
  - `grant.approve` 必须二次验 `identity + role + scope + pending grant ownership`。
- No-Go：
  - 若自然语言可直接越过 `structured_action -> policy -> grant -> audit` 主链，直接 `NO_GO`。
- 证据：
  - `build/reports/xt_w3_24_si_g3_action_quarantine_evidence.v1.json`

### 4.5 `XH-CHAN-SI-G4` Secret Residency + Runtime Split

- 要求：
  - provider bot token / webhook secret / signing secret / app secret 只在 Hub vault / Bridge memory 可见。
  - secrets 不进入 XT、本地 prompt、file dropbox、canonical memory、审计正文。
  - `WhatsApp personal QR` 不进入 Hub 主 webhook 面，只能走 `trusted_automation + local runner`。
  - provider egress/connector 实现仍运行在 Bridge 或 Bridge 管理的隔离 worker。
- 证据：
  - `build/reports/xt_w3_24_si_g4_secret_residency_evidence.v1.json`

### 4.6 `XH-CHAN-SI-G5` Availability Bulkhead + Circuit Breaker

- 要求：
  - ingress queue、outbox queue、provider callback worker、Hub gRPC query path 要有隔离预算。
  - provider 错误率过高时必须自动降级或熔断。
  - channel 高峰流量不得拖死 pairing / gRPC / audit。
  - `status query` 与 `delivery outbox` 必须能区分优先级。
- No-Go：
  - 若三渠道压测下 Hub pairing/gRPC latency 明显失控且无 bulkhead/circuit breaker，直接 `NO_GO`。
- 证据：
  - `build/reports/xt_w3_24_si_g5_availability_bulkhead_evidence.v1.json`

### 4.7 `XH-CHAN-SI-G6` Audit / DLP / Memory Hygiene

- 要求：
  - 审计默认 `metadata_only`。
  - 原始 payload、附件、链接、卡片参数默认不进入 canonical memory。
  - 需要短期排障留存的 raw payload 必须短 TTL、受加密、带敏感级别。
  - `audit_write_failed`、`dlp_blocked`、`remote_secret_denied` 都要有稳定 deny code。
- 证据：
  - `build/reports/xt_w3_24_si_g6_audit_memory_hygiene_evidence.v1.json`

### 4.8 `XH-CHAN-SI-G7` Emergency Controls + Incident Drill

- 要求：
  - 必须能按 `provider / account / binding / scope` 级别 kill-switch。
  - 必须有 `rotate secret / disable ingress / pause outbox / revoke grant` 路径。
  - 必须完成至少一次 require-real incident drill：
    - webhook secret 泄露
    - unauthorized flood
    - replay storm
    - false delivery receipt loop
- 证据：
  - `build/reports/xt_w3_24_si_g7_incident_control_evidence.v1.json`

## 5) Mapping To `XT-W3-24-G..N`

- `XT-W3-24-G`
  - 必须同时满足：`XH-CHAN-SI-G0`, `XH-CHAN-SI-G1`, `XH-CHAN-SI-G5`
- `XT-W3-24-H`
  - 必须同时满足：`XH-CHAN-SI-G2`, `XH-CHAN-SI-G3`
- `XT-W3-24-I`
  - 必须同时满足：`XH-CHAN-SI-G2`, `XH-CHAN-SI-G3`
- `XT-W3-24-J`
  - 必须同时满足：`XH-CHAN-SI-G1`, `XH-CHAN-SI-G3`, `XH-CHAN-SI-G5`, `XH-CHAN-SI-G6`
- `XT-W3-24-K`
  - 必须同时满足：`XH-CHAN-SI-G1`, `XH-CHAN-SI-G3`, `XH-CHAN-SI-G5`, `XH-CHAN-SI-G6`
- `XT-W3-24-L`
  - 必须同时满足：`XH-CHAN-SI-G1`, `XH-CHAN-SI-G3`, `XH-CHAN-SI-G5`, `XH-CHAN-SI-G6`
- `XT-W3-24-M`
  - 必须同时满足：`XH-CHAN-SI-G4`, `XH-CHAN-SI-G5`, `XH-CHAN-SI-G6`, `XH-CHAN-SI-G7`
- `XT-W3-24-N`
  - 必须同时满足：`XH-CHAN-SI-G3`, `XH-CHAN-SI-G4`, `XH-CHAN-SI-G6`, `XH-CHAN-SI-G7`

## 6) Direct Execution Checklist

### 6.1 `XT-W3-24-G` 必做补件

1. 产出 `provider exposure matrix`，列出 `listener/process/path/auth_mode/replay_mode/body_cap/rate_limit`。
2. 从当前 `pairing_http.js` 抽出可复用 preauth/replay/ordering/receipt 原语，禁止 provider adapter 各自重写。
3. 冻结 `HubChannelIngressEnvelope`，只允许归一化字段进入下游。

### 6.2 `XT-W3-24-H` 必做补件

1. 增加 `stable_external_id` 唯一主键。
2. 明确 `approval_only_identity`、`viewer`、`release_manager`、`ops_admin` 角色矩阵。
3. 禁止任何 display text 参与权限判断。

### 6.3 `XT-W3-24-I` 必做补件

1. 默认 `project-first`，设备只是 hint。
2. route 失败时只允许返回 `hub_only_status|xt_offline|runner_not_ready`。
3. `device diagnostics` 必须显式切 scope，不得复用项目主线程。

### 6.4 `XT-W3-24-J/K/L` 必做补件

1. provider-specific signature verify + replay key strategy 文档化。
2. 统一 `message -> structured action` 编译器，避免 adapter 内直接做 side effect routing。
3. 所有 callback/button/card 动作都必须附带 `audit_ref`。

### 6.5 `XT-W3-24-M` 必做补件

1. outbox queue 和 query path 隔离预算。
2. provider failure backoff、dead-letter、manual retry 入口。
3. 告警推送熔断时，Supervisor 侧必须能看到明确 degradation。

### 6.6 `XT-W3-24-N` 必做补件

1. 固定 allowlisted `structured action` 列表。
2. `grant.approve` 必须校验 pending grant ownership 与 scope。
3. `whatsapp_cloud_api` 与 `whatsapp_personal_qr` 必须分开记账、分开 gate、分开 release 口径。

## 7) No-Go List

- webhook/provider callback 长期与 pairing/admin/public install 共用同一默认公开 listener
- provider 配置、install/discovery、operator 文档默认暴露 Hub 原始 IP
- provider token / webhook secret 落到 XT、本地文件、prompt bundle、canonical memory
- display name / room title 驱动授权或路由
- natural language 可直接触发 `deploy.execute`、`device.*`、`grant.approve`
- `audit_write_failed` 后仍继续执行下游动作
- `dm allowlist` 自动扩张为 `group allowlist`
- provider ingress 直接唤起 XT 进程或 runner，不经过 Hub grant/policy/audit
- `whatsapp_personal_qr` 在无 require-real 证据时被宣称 ready

## 8) Pass Conditions

- `hub_webhook_public_surface_unisolated = 0`
- `hub_raw_ip_exposed_by_default = 0`
- `provider_secret_in_xt_runtime = 0`
- `display_text_auth_binding = 0`
- `natural_language_direct_side_effect = 0`
- `audit_write_failed_but_continue = 0`
- `channel_raw_payload_to_canonical = 0`
- `pairing_admin_and_channel_webhook_same_default_listener = 0`
- `channel_peak_load_degrades_hub_control_plane_unbounded = 0`

## 9) Relationship To Current Hub Implementation

这份 gate 的核心不是否定当前 Hub，而是明确“哪些现有能力可以直接复用，哪些必须在 release 前升级”：

- 可以直接复用：
  - `auth.js` 的 client/admin auth
  - `services.js` 的 capability gate / deny_code 语义
  - `connector_ingress_authorizer.js` 的 allowlist / DM-group 分离
  - `pairing_http.js` 的 preauth / replay / ordering / receipt 守门
  - `db.js` 的持久化 replay guard
- 必须升级：
  - provider webhook 长期暴露面的拓扑隔离
  - IM identity 到 Hub principal 的稳定绑定
  - structured action quarantine
  - outbox / query / audit 的 availability bulkhead
  - incident kill-switch 与 require-real drill

换句话说，本 gate 不是要求“重写一套 Hub”，而是要求：

- 重用现有守门原语
- 但不把它们直接拼成一个高暴露、低隔离、难止血的新入口面
