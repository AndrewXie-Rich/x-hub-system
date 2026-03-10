# X-Hub Storage Encryption & Key Management v1（可执行规范 / Draft）

- Status: Draft（用于直接落地；后续按版本迭代）
- Updated: 2026-02-12
- Applies to: X-Hub（Core + hub_grpc_server + Bridge/Connectors）
- Goals: Secrets 永不明文落盘；敏感记忆可加密落库；支持密钥轮换、备份恢复、审计与回滚。

> 本规范解决：Hub 端“存储加密 / 密钥管理 / 轮换 / 恢复”的工程落地细节。
> 它与 `docs/xhub-client-modes-and-connectors-v1.md`、`docs/xhub-memory-core-policy-v1.md` 配合使用。

---

## 0) 术语

- Hub Base Dir：`<hub_base>`（默认 App Group：`~/Library/Group Containers/group.rel.flowhub`）
- Vault：Hub 内“只存密钥/凭证/高敏配置”的安全存储子系统
- Secret：密钥、Token、邮箱密码、证书私钥、支付/出票凭证等
- KEK（Key Encryption Key）：用于包裹/解包 DEK 的密钥（轮换粒度）
- DEK（Data Encryption Key）：每条记录/每个对象的随机数据密钥（最小泄漏面）
- AAD（Additional Authenticated Data）：参与认证但不加密的数据（防替换/串改）
- KID：key id，标识使用哪一个 KEK 版本

---

## 1) 目标与非目标

### 1.1 目标（必须）
1) **Secrets 永不明文落盘**（包括日志、DB、JSON 配置、崩溃报告）
2) **加密默认 fail-closed**：无法解密就拒绝执行相关能力（paid models / connectors）
3) **最小可行轮换**：支持新增 KEK（KID 增长），新写入使用新 KID；旧数据仍可解密
4) **可备份可恢复**：在“备份文件被窃取”的情况下仍然不泄漏 secrets
5) **可审计**：vault 写入/读取/轮换/导出均写 audit

### 1.2 非目标（v1 不强求，但要预留）
- 全库 SQLCipher（node:sqlite 不直接支持；v1 先做字段级/对象级加密）
- 远程硬件密钥（HSM/KMS）
- 多人共享与组织级密钥治理（先单用户/家庭模式）

---

## 2) 数据分级与加密策略（与 Memory-Core 对齐）

数据敏感级别：`public | internal | secret`

### 2.1 强制加密（secret）
以下数据必须进入 Vault（加密 blob），不得以明文存储：
- paid model provider keys（OpenAI/Anthropic/Gemini/OpenAI-compatible 等）
- Email（IMAP/SMTP）用户名/密码/应用专用密码
- OAuth refresh tokens（v2 才会用，但 schema 先预留）
- mTLS client private keys / Hub CA private key（如果落盘）
- “冷存储 token”（用于更新宪章/Policy/Skills 的高权限 token，见 Memory-Core）

### 2.2 可选加密（internal）
默认可不加密，但建议逐步支持（配置开关）：
- Canonical/Longterm 中的 internal 信息（例如内部架构摘要）
- 审计中的部分字段（例如收件人邮箱，可做 hash/脱敏）

### 2.3 不加密（public）
公开信息可明文存储（仍需防篡改/签名能力由其它 spec 覆盖）。

---

## 3) 密钥体系（Key Hierarchy）

### 3.1 Keychain Root（HubRootKey）
Hub 首次初始化时生成 32 bytes 随机根密钥 `hub_root_key`，写入 macOS Keychain。

约束：
- 不写入任何文件
- 仅 Hub App（同 TeamID/BundleId）可读取
- 若 Keychain 项缺失：Hub 进入“Vault Locked”状态（拒绝 paid/connectors）

Keychain item（建议）
- service: `com.xhub.vault`
- account: `hub_root_key`
- data: raw bytes（32）

### 3.2 KEK（可轮换）
从 `hub_root_key` 通过 HKDF 派生出 KEK（每个 KID 一个）：

- `kek = HKDF-SHA256(ikm=hub_root_key, salt="xhub.vault.kek", info="kek:"+kid, len=32)`
- KID 形如：`kek_v1`, `kek_v2`, ...

规则：
- 有且仅有一个 active KID
- 加密写入使用 active KID
- 解密允许历史 KID（只要能派生）

### 3.3 DEK（每条记录）
每个 vault item 生成随机 `dek`（32 bytes），用于 AES-256-GCM 加密 payload。

DEK 包裹（wrap）
- `wrapped_dek = AES-256-GCM(key=kek, nonce=random12, plaintext=dek, aad=wrap_aad)`
- `wrap_aad` 建议包含：`schema_version + item_id + created_at_ms`

这样做的好处：
- 攻击者拿到 DB 也只有 wrapped_dek + ciphertext，无法解密
- 轮换 KEK 时无需重加密 payload，只需 rewrap DEK（可选优化，v2）

---

## 4) 加密算法与编码规范（必须一致）

### 4.1 算法
- 对称加密：AES-256-GCM
- Nonce：12 bytes（96-bit）
- Tag：16 bytes
- KDF：HKDF-SHA256

### 4.2 编码
- DB 内存储：BLOB 优先；若必须文本则用 base64（标准，不带换行）
- AAD：JSON Canonical（字段排序固定）或 `key=value` 拼接，必须稳定

### 4.3 AAD 规则（防替换攻击）
对 payload encryption 的 AAD 建议至少包含：
- `schema_version`
- `item_id`
- `scope`
- `name`（或 `key`）
- `sensitivity`

解密时 AAD 必须完全一致，否则解密失败（fail-closed）。

---

## 5) Vault 存储：SQLite schema（v1 推荐）

> v1 建议：在 hub_grpc_server 的 SQLite 中新增 **Secrets Vault** 表 `secret_vault_items`；只存加密 blob + 最少元数据。
> （后续可拆为独立 vault DB。）

### 5.1 表结构（建议）
```sql
CREATE TABLE IF NOT EXISTS secret_vault_items (
  item_id TEXT PRIMARY KEY,
  scope TEXT NOT NULL,              -- "hub|device|user|project"
  name TEXT NOT NULL,               -- e.g. "openai.api_key" / "email.imap_password"
  sensitivity TEXT NOT NULL,        -- must be "secret" for v1

  enc_alg TEXT NOT NULL,            -- "aes-256-gcm"
  enc_kid TEXT NOT NULL,            -- "kek_v1"

  wrapped_dek_nonce BLOB NOT NULL,  -- 12 bytes
  wrapped_dek_ct BLOB NOT NULL,     -- ciphertext (dek) + tag separated or combined (see below)
  wrapped_dek_tag BLOB NOT NULL,    -- 16 bytes

  payload_nonce BLOB NOT NULL,      -- 12 bytes
  payload_ct BLOB NOT NULL,         -- ciphertext(payload)
  payload_tag BLOB NOT NULL,        -- 16 bytes

  aad_json TEXT NOT NULL,           -- stable JSON string
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_secret_vault_unique
  ON secret_vault_items(scope, name);
```

实现备注：
- `wrapped_dek_ct/tag` 与 `payload_ct/tag` 拆分存储，避免拼接错误；也便于跨语言实现
- scope/name 唯一约束用于 idempotent upsert

### 5.2 Vault API（Hub 内部接口）
对外（终端/客户端）不暴露原始 secrets；只暴露“connector 已配置/未配置”的状态。

内部最小 API（示例）
- `VaultUpsert(scope, name, plaintext_bytes, sensitivity='secret') -> item_id`
- `VaultGet(scope, name) -> plaintext_bytes`（仅 Hub/Connector Host 调用）
- `VaultDelete(scope, name)`
- `VaultList(scope, prefix?) -> [{name, updated_at_ms}]`（不返回值）
- `VaultRotateKeys(new_kid)`（仅 admin）

所有 Vault API 都必须写审计（见 9）。

### 5.3 Raw Vault（Memory Evidence）加密（与 Secrets Vault 同一套密钥体系）
除 Secrets Vault 外，X‑Hub 的 Memory Raw Vault（`vault_items`）也需要 at-rest 加密：
- 目的：邮件正文/附件、网页内容、工具输出等可能包含 PII/凭证/商业机密，必须避免明文落盘。
- 建议：Raw Vault 采用与本规范相同的 **Key Hierarchy（Keychain root -> KEK -> per-row DEK）** 与 **AES-256-GCM**。
- 区别：Secrets Vault（`secret_vault_items`）存“凭证类 secrets”；Raw Vault（`vault_items`）存“证据 payload”。

实现对齐点（建议）：
- AAD 必须包含 `schema_version + vault_item_id + sensitivity + created_at_ms`（防替换/串改）
- `payload_sha256` 建议对 plaintext payload bytes 计算，用于 provenance（即使 ciphertext 不同也能稳定引用）

Raw Vault 的表结构与 ingest 规则见：
- `docs/xhub-memory-progressive-disclosure-hooks-v1.md`（3.1/3.2）

---

## 6) Secrets 如何被使用（关键：不泄漏到日志/审计）

### 6.1 Paid models keys
- 使用时机：Bridge/Runtime 发起远程 paid 请求
- 规则：
  - 仅在发起请求前从 Vault 解密到内存
  - 请求完成立即从内存引用释放（best-effort）
  - 禁止写入 audit（只记 provider/model/usage/cost，不记 key）

### 6.2 Email（IMAP/SMTP）
- 使用时机：Connector worker 执行 list/get/draft/send/archive
- 规则：
  - 仅 Bridge/Connector worker 需要明文凭证
  - 推荐：由 Core 解密后通过本机 IPC 传给 Bridge（仅内存通道），Bridge 不落盘
  - 如必须缓存：仅做短 TTL（<= 2h）内存缓存；不得落盘

---

## 7) 轮换（Rotation）

### 7.1 轮换目标
- 定期/事件触发生成新 KID（`kek_vN`）
- 新写入使用新 KID
- 旧数据仍可解密

### 7.2 v1 最小实现（不 rewrap）
因为 KEK 是派生自 root key + KID：
- 轮换 = “更新 active_kid 配置”
- 新写入使用新 KID
- 旧记录解密：根据记录 `enc_kid` 派生 KEK 即可

`active_kid` 存储位置（建议）
- `<hub_base>/vault/vault_state.json`（只存非敏感元数据）
```json
{ "schema_version":"xhub.vault_state.v1", "active_kid":"kek_v1", "updated_at_ms":0 }
```

### 7.3 v2 增强（rewrap）
当需要废弃某个 KID（例如疑似泄漏）：
- 对所有 `secret_vault_items`：解密 wrapped_dek -> 用新 KEK 重包裹 -> 更新 enc_kid 与 wrapped_dek_*
- 不重加密 payload（节省成本）

---

## 8) 恢复与“Keychain 丢失”策略（必须写清楚）

现实：Keychain 项丢失 = 无法派生 KEK = 无法解密 Vault。

v1 策略（可执行）
- Hub 检测到 root key 缺失：
  - 标记 Vault Locked
  - 禁用 paid models + connectors（返回错误：`vault_locked`）
  - UI 引导用户：从备份恢复（见 backup spec）或重新初始化 Vault（清空 secrets）

禁止的行为
- 不能“自动生成新 root key 并继续用旧 ciphertext”——那会造成隐蔽的数据不可恢复

---

## 9) 审计（Audit）要求

必须写入 `audit_events`（或现有 audit 表）：
- `vault.upsert`（不含明文；可记 name/scope/sensitivity）
- `vault.get`（不含明文；可记 name/scope/actor）
- `vault.delete`
- `vault.rotate_kid`
- `vault.unlock_failed` / `vault.locked`

审计字段建议
- actor: device_id/user_id/app_id/project_id
- vault_item: scope/name
- ok/error_code
- created_at_ms

---

## 10) 测试用例（必须实现）

### 10.1 互操作测试（跨语言）
需要至少一组“金向量”：
- 固定 root_key + kid + plaintext -> 期望 nonce/ciphertext/tag
- Node 与 Swift 都能解密彼此生成的数据

### 10.2 反篡改
- 修改任意 1 bit 的 payload_ct/tag/aad_json -> 解密必须失败

### 10.3 漏洞回归
- 确认日志/审计中永不出现明文 secrets（grep 检查）

---

## 11) 与其它规范的关系
- 连接器与 Outbox/UndoSend：`docs/xhub-client-modes-and-connectors-v1.md`
- 记忆分级/远程外发/DLP：`docs/xhub-memory-core-policy-v1.md`
- 备份/恢复：见 `docs/xhub-backup-restore-migration-v1.md`（待实现）
