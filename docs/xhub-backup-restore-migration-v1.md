# X-Hub Backup / Restore / Migration v1（可执行规范 / Draft）

- Status: Draft（用于直接落地实现；后续按版本迭代）
- Updated: 2026-03-21
- Applies to: X-Hub（Core + hub_grpc_server + Bridge/Connectors）
- Primary goal: “备份被偷也不泄密；Hub 丢失也能恢复可用状态（含 secrets）”

> 本规范定义：
> - 备份包含什么、怎么做一致性快照
> - 备份文件格式与加密方式
> - 恢复流程与安全边界
> - 数据库 schema 迁移与回滚策略

---

## 0) 前置：依赖 Vault 加密

备份的前提是 Vault 已落地：
- Secrets 必须以加密 blob 存储（见 `docs/xhub-storage-encryption-and-keymgmt-v1.md`）
- 备份文件不允许出现明文 secrets

---

## 1) 备份范围（Backup Set）

### 1.1 必须包含（MVP）
- Hub DB（SQLite）：
  - grants / audit / threads / turns / canonical / outbox_jobs / paid_entitlements（等）
- Vault items（如果在同一 SQLite 表里，随 DB 一起；如果独立文件，则单独打包）
- Policy 配置：
  - `hub_grpc_clients.json`（clients allowlist + capabilities）
  - kill-switch state（若不在 DB）
  - `memory_model_preferences`（若已落地在 DB / config 中，必须一并备份，避免恢复后静默切换 memory executor）
  - connector policies / memory policy materialization（例如 `memory_core_policy.json`）
  - 若已落地 `Memory-Core` recipe asset version metadata / active state / 审计链，也应与上面这份 materialized policy view 一并备份，避免恢复后只有派生视图、缺少版本真相源
- TLS/Pairing 相关：
  - Hub CA 证书（public）+ 已签发客户端证书（public）
  - 私钥（若存在）必须在 Vault 内加密存储后再纳入备份

### 1.2 可选包含（建议）
- 模型目录与权重（通常体积巨大，不建议默认包含）
- 缓存与索引（可重建的不要备份）
- 临时队列（可重放的队列可选）

---

## 2) 一致性快照（Consistency Snapshot）

### 2.1 SQLite + WAL 的一致性
备份时必须避免“只拷贝 main db 文件导致丢数据”。

v1 推荐两种方式（二选一）

1) **SQLite Online Backup API**（首选）
- 使用 SQLite 的备份接口从 live DB 导出到 `snapshot.sqlite3`
- 优点：无需停机；一致性最好

2) **停机窗口 + 文件拷贝**
- 先停止 hub_grpc_server 与 Bridge（或进入只读模式）
- 确认 WAL checkpoint
- 再拷贝 db + wal + shm
- 优点：实现简单；缺点：需要短暂停机

> 注：当前 hub_grpc_server 使用 `node:sqlite`，后续实现备份时可优先走“停机窗口”快速落地。

---

## 3) 备份文件格式（xhubbackup.v1）

### 3.1 容器格式
备份文件建议扩展名：
- `.xhubbackup`

内部结构：
- `manifest.json`（明文，但不含 secrets）
- `payload.tar`（包含 DB snapshot 与配置文件）
- `payload.enc`（对 payload.tar 的加密结果）

### 3.2 manifest.json（示例）
```json
{
  "schema_version": "xhub.backup_manifest.v1",
  "backup_id": "bkp_...",
  "created_at_ms": 0,
  "hub_version": "x.y.z",
  "db_schema_version": 1,
  "vault_kid_active": "kek_v2",
  "kdf": {
    "alg": "argon2id",
    "salt_b64": "base64:...",
    "mem_kib": 262144,
    "iters": 3,
    "parallelism": 1
  },
  "cipher": {
    "alg": "aes-256-gcm",
    "nonce_b64": "base64:..."
  },
  "payload": {
    "sha256": "....",
    "size_bytes": 0
  }
}
```

规则：
- `payload.sha256` 是加密前 `payload.tar` 的 sha256（用于解密后校验）
- manifest 不包含任何明文 secret

---

## 4) 备份加密（必须）

### 4.1 备份口令（Passphrase）
v1 采用“用户口令加密备份”的方案：
- 用户在 Hub UI 输入 passphrase（不存盘）
- 通过 Argon2id 派生 `backup_key`（32 bytes）
- 用 `backup_key` 对 `payload.tar` 做 AES-256-GCM 加密 -> `payload.enc`

默认 KDF 参数建议（可调）
- mem: 256 MiB（262144 KiB）
- iters: 3
- parallelism: 1

### 4.2 为什么不用“直接拷贝 Keychain”
- Keychain 不一定可跨设备迁移
- passphrase backup 是跨设备恢复的通用方案

---

## 5) Restore（恢复）流程

### 5.1 恢复模式（两种）
1) In-place restore（原 Hub 恢复）
2) New Hub restore（新设备恢复）

### 5.2 New Hub restore 的关键点
- 新 Hub 会生成新的 `hub_root_key`（Keychain）
- 备份中的 Vault items 仍是加密 blob：
  - 若 Vault 采用“派生 KEK”且依赖 hub_root_key，则必须提供“Vault rekey”流程

因此 v1 推荐的 Vault 备份策略（必须选一种）

A) **备份包含“Vault export key”**（推荐）
- 在备份时生成一次性 `vault_export_key`（随机 32 bytes）
- 用当前 hub_root_key 派生的 KEK 加密它，存入 payload（仍是加密 blob）
- 同时用 `backup_key`（passphrase）再次加密它
- 恢复时：用 passphrase 解开 `vault_export_key`，用于解密 Vault items 或用于 rewrap

B) **只支持 In-place restore**
- 不支持跨设备恢复 secrets（体验较差，不推荐）

v1 建议采用 A（可跨设备恢复）。

### 5.3 恢复步骤（New Hub）
1) 用户选择 `.xhubbackup` 文件
2) 输入 passphrase，派生 `backup_key`
3) 解密 `payload.enc` -> `payload.tar`，校验 sha256
4) 解包到 staging 目录
5) 导入 DB snapshot（替换或迁移）
6) 执行 Vault rekey/rewrap（把旧 Vault items 迁移到新 hub_root_key 派生的 KEK）
7) 启动 x-hub/grpc-server/hub_grpc_server/Bridge
8) 写入审计：`backup.restore.completed`

恢复边界（必须）
- 恢复流程不得静默改写用户原先选定的 memory executor；`memory_model_preferences` 应原样恢复或显式提示不兼容。
- 恢复流程不得把 `Memory-Core` 降格成普通 installable skill/runtime；其 active rule asset state 应按备份真相恢复。
- 恢复后的 durable memory writes 仍只允许经 `Writer + Gate`，恢复工具本身不应顺手把 terminal/client 侧状态升格成新的 durable truth。

---

## 6) Migration（数据库迁移）

### 6.1 版本字段（必须）
Hub DB 需要有 `schema_versions`（或 meta 表）记录：
- `db_schema_version`
- `app_version`

### 6.2 迁移原则
- forward-only（默认只向前迁移）
- 每个 migration 必须可重复运行（幂等）
- 迁移失败必须回滚到备份快照（或中止并保持旧 DB 不变）
- migration 可以调整 schema / storage layout，但不得静默更改 `memory_model_preferences` 的语义，也不得改写 `Memory-Core -> Scheduler/Worker -> Writer + Gate` 的控制面边界

### 6.3 恢复时的迁移
当备份 DB schema_version < 当前 Hub 支持：
- 先 restore 到 staging
- 再运行 migrations
- 再切换到正式 DB 路径

---

## 7) 回滚（Rollback）

v1 最小保证：
- restore/migrate 前必须先做一次本地临时备份（如果当前 Hub 有数据）
- 迁移失败可回滚到 restore 前状态

---

## 8) 审计（Audit）

必须记录：
- `backup.create.started|completed|failed`
- `backup.restore.started|completed|failed`
- `backup.migrate.started|completed|failed`

审计中禁止：
- passphrase
- 任何明文 secrets

---

## 9) 与其它规范的关系
- Vault 与密钥轮换：`docs/xhub-storage-encryption-and-keymgmt-v1.md`
- Update/Release 与迁移触发：`docs/xhub-update-and-release-v1.md`
