# X-Hub Connectors Isolation & Runtime v1（可执行规范 / Draft）

- Status: Draft（用于直接落地实现 connectors MVP；后续按版本迭代）
- Updated: 2026-02-12
- Applies to: X-Hub Bridge（唯一联网进程）+ hub_grpc_server（控制面）+（未来）X-Terminal

> 本规范解决：在“不牺牲体验”的前提下，Connectors 如何做到：
> - Secrets 不出 Hub，且不明文落盘
> - 外部动作可审计、可冻结（Kill-Switch）
> - Hub Core 不运行第三方可执行代码（降低被攻破风险）
> - 崩溃恢复、幂等、撤销窗口（Email UndoSend=30s）

---

## 0) 设计约束（硬性）

1) **Bridge 是唯一联网进程**（network entitlement 只给 Bridge）
2) **hub_grpc_server 作为控制面**：负责鉴权、grants、审计、policy、把请求转交给 Bridge
3) **Connector 实现运行在 Bridge 侧**（或 Bridge 管理的隔离 worker），不得在 Hub Core 内直接外联
4) **Secrets 必须来自 Vault**（见 `docs/xhub-storage-encryption-and-keymgmt-v1.md`）
5) 所有不可逆动作必须具备：
   - idempotency（去重）
   - audit（可追责）
   - kill-switch（可止血）

---

## 1) 组件与职责

### 1.1 hub_grpc_server（控制面）
职责：
- Client auth（token/mTLS/capabilities）
- Grants：是否允许某个 client 调用 connector operation
- Policy：rate-limit / allowlist / retention / undo_window
- Audit：写 `connector.*` 事件（默认 metadata-only）
- 转发：把 connector 请求通过 IPC 转交给 Bridge 执行

禁止：
- 不直接发起任何外网连接（即使 Node 能发，也不允许）

### 1.2 Bridge（数据面，唯一联网）
职责：
- 执行 connectors：IMAP/SMTP/Web 等外联
- Outbox worker：延迟发送、撤销窗口
- 网络 allowlist：限制 connector 可访问的域名/端口

### 1.3 Vault（Secrets）
职责：
- 加密落盘、解密到内存
- 对 Bridge 提供“按次取 secret”的内存通道（不落盘）

---

## 2) IPC：hub_grpc_server <-> Bridge（推荐：文件 dropbox v1）

> 当前项目已有“file dropbox / IPC JSONL”传统（见 `docs/ipc-sequence.md`、现有 mlx_runtime IPC）。
> v1 推荐先复用：在 `<hub_base>/connectors_requests/` 写请求 JSON，在 `<hub_base>/connectors_responses/` 写响应 JSONL。

### 2.1 请求文件
- Path：`<hub_base>/connectors_requests/req_<request_id>.json`
- 内容（示例）
```json
{
  "schema_version": "xhub.connector_request.v1",
  "request_id": "req_...",
  "client": { "device_id":"...", "user_id":"...", "app_id":"...", "project_id":"...", "session_id":"..." },
  "connector_id": "email",
  "operation": "send_draft",
  "idempotency_key": "idem_...",
  "params": { "draft_id": "d_...", "undo_window_sec": 30 },
  "created_at_ms": 0
}
```

### 2.2 响应事件（JSONL）
- Path：`<hub_base>/connectors_responses/resp_<request_id>.jsonl`
- 事件类型：`start|progress|done|error`

示例：
```json
{"type":"start","request_id":"req_...","started_at_ms":0}
{"type":"done","request_id":"req_...","ok":true,"result":{"send_job_id":"sj_..."},"finished_at_ms":0}
```

### 2.3 Secrets 传递（禁止明文落盘）
Bridge 执行 connector 需要凭证时：
- 不允许 hub_grpc_server 把 secret 写进 req_*.json
- v1 推荐方案（两选一）：
  1) Bridge 通过本机 IPC 向 Vault 请求解密（Vault 服务在 Core，返回仅在内存中使用的明文）
  2) hub_grpc_server 调用 Vault 解密并通过 **Unix domain socket** / **shared memory** 发给 Bridge（仅内存通道）

硬规则：
- Secrets 不得进入文件 dropbox
- Secrets 不得写入 audit/log

---

## 3) Connector 插件模型（Bridge 侧）

### 3.1 ConnectorHost
Bridge 内部提供 `ConnectorHost`，负责：
- 注册 connector（email/calendar/...）
- 解析 connector request
- 执行 operation（并统一做超时、重试、错误码映射）

### 3.2 安全边界（强制）
- Connector 代码应运行在“最小权限上下文”
- 允许分两级隔离：
  - v1：同进程模块隔离（最快落地）
  - v2：每个 connector 独立子进程（崩溃隔离 + 更低 RCE 风险）

若采用 v2：
- Bridge 作为 supervisor，fork `xhub-connector-email` 等子进程
- 与子进程用 stdin/stdout JSONL 通信

---

## 4) Email Connector（IMAP+SMTP）执行规范（MVP）

参考：`docs/xhub-client-modes-and-connectors-v1.md`（Email API + Outbox/UndoSend）

### 4.1 最小操作集
- `ListMessages(query, limit)`
- `GetMessage(message_id, include_body)`
- `CreateDraft(...)`
- `SendDraft(draft_id, idempotency_key, undo_window_sec=30)` -> `send_job_id`
- `Archive(message_id)`

### 4.2 状态存储（Outbox）
Outbox 必须由 Hub/Bridge 持久化（避免重启丢任务）：
- 表建议：`outbox_jobs`（在 Hub DB 或 Bridge DB 均可；推荐 Hub DB，便于审计/查询）
- `send_job_id` 为主键
- job 的“正文/附件引用”必须走短 TTL 缓存（不得长期落盘明文）

### 4.3 UndoSend=30s（默认）
- `SendDraft` 只入队，不立即 SMTP send
- worker 每秒或每 500ms 扫描到期任务
- 用户/系统可以 `CancelSend(send_job_id)`（仅 queued 且未到期）

### 4.4 幂等（必须）
- `(client_id, idempotency_key)` 作为 send 的去重键
- 重复调用必须返回同一个 `send_job_id`
- worker 发送前也必须二次检查（防并发/重启 double-send）

### 4.5 SMTP 发送与错误处理
- 建议不自动重试（MVP）：避免多次发送同一封邮件
- 若 SMTP 返回“临时错误”：标记 failed，并提示用户手动重试（新的 idempotency_key）

---

## 5) Policy 与 Kill-Switch（必须覆盖 connectors）

### 5.1 Kill-Switch 行为
- `network_disabled=true` 或 `connectors_disabled=true`（若你后续拆分开关）时：
  - 新 connector 请求直接拒绝（error_code=`kill_switch_active`）
  - Outbox 队列任务：
    - 默认策略：到期后不发送，直接 fail 并记审计（避免积压后突然爆发发送）

### 5.2 Rate limit / Allowlist（可选但建议）
v1 可先不拦截，但必须预留字段与接口：
- per-connector 每分钟最大调用次数
- per-user 每日 send cap
- SMTP 目标域名 allowlist/denylist（可选）

---

## 6) 审计（Audit）最小要求

必须记录（metadata-only）：
- `connector.email.list`
- `connector.email.get`
- `connector.email.draft.create`
- `connector.email.send.queued|sent|canceled|failed`
- `connector.email.archive`

禁止记录：
- 邮件正文/附件内容（默认）
- 明文凭证

推荐记录：
- message_id / thread_id（provider side id）
- recipient domains（仅域名或 hash）
- send_job_id
- undo_window_sec

---

## 7) 崩溃恢复与一致性

### 7.1 崩溃恢复（必须）
Bridge 或 Hub 重启后：
- `queued` 未到期：继续等待
- `queued` 已到期：继续发送（除非 kill-switch）
- `sent/canceled/failed`：不再处理

### 7.2 一致性（必须）
任何 connector operation 都必须：
- 先写入 “start” 审计或状态（可重放）
- 完成后写 “done” 审计与最终状态
- 失败写 error_code/error_message（不含 secrets）

---

## 8) 与其它规范的关系
- Client 模式、grants、UndoSend、paid entitlement：`docs/xhub-client-modes-and-connectors-v1.md`
- Vault 加密与密钥轮换：`docs/xhub-storage-encryption-and-keymgmt-v1.md`
- 记忆分级与远程外发 gate：`docs/xhub-memory-core-policy-v1.md`

