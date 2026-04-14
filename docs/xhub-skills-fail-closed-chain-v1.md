# X-Hub Skills Fail-Closed Chain v1（SKC-W1-03 / SKC-W1-04）

- Status: Executable Spec
- Updated: 2026-03-01
- Owner Lane: Hub-L2
- Scope: 信任根 / 签名校验 / 哈希校验 / 分层 pin 冲突解析 / revocation 双侧阻断

> 本文定义生产默认链路：`ingress -> verify -> policy -> pin/resolve -> distribute/execute -> audit`。  
> 任一校验节点失败必须 `deny`，不得“放行后补救”。

---

## 1) Manifest Canonical 签名校验器规范

### 1.1 签名输入（canonical bytes）

1. 取 manifest JSON 对象，删除顶层 `signature` 字段。
2. 对对象做递归 key 排序（数组保持原顺序）。
3. 使用无空白 JSON 序列化（UTF-8）。
4. 对 canonical bytes 执行 `Ed25519` 验签。

### 1.2 信任根与验签来源

- Trust roots 文件：`<hub_base>/skills_store/trusted_publishers.json`
- 生产默认：
  - publisher 不在 trust roots -> `deny(publisher_untrusted)`
  - 公钥不匹配 -> `deny(publisher_key_mismatch)`
  - 签名缺失/无效 -> `deny(signature_missing|signature_invalid)`
- `developer_mode=true` 仅允许**低风险**技能放宽：
  - 可允许 unsigned / untrusted（仍做 hash 校验）
  - **高风险技能（capabilities 命中高风险集）禁止放宽**

### 1.3 稳定 deny_code（签名链）

- `signature_missing`
- `signature_invalid`
- `signature_algorithm_unsupported`
- `signature_key_invalid`
- `publisher_untrusted`
- `publisher_key_mismatch`

---

## 2) Package / File 双 Hash 校验规则

### 2.1 Package hash

- `package_sha256 = SHA256(uploaded_bytes)`（Hub 入库唯一键）。
- 若 manifest 显式声明包 hash（`package_sha256` / `package.sha256`），必须与计算值一致；否则 `deny(hash_mismatch)`。

### 2.2 File hash（archive 内文件）

- 支持：`tgz` / `tar` / `zip`（store/deflate）。
- 路径必须规范化：
  - 禁止绝对路径、`..` 路径穿越、重复路径。
- `manifest.files[]` 必须存在且为稳定 `path + sha256` 列表。
- 校验策略（fail-closed）：
  1) manifest 每个文件必须在包中存在且 hash 一致；
  2) 包中每个普通文件必须被 manifest 列出（禁止“隐身文件”）。
- 任一失败 -> `deny(hash_mismatch)`（或 archive 结构类 deny_code）。

### 2.3 稳定 deny_code（hash / archive）

- `hash_mismatch`
- `archive_corrupt`
- `archive_path_invalid`
- `archive_duplicate_path`
- `archive_unsupported`
- `invalid_manifest`

---

## 3) 分层 Pin 冲突解析与 Revocation 双侧阻断

### 3.1 分层 pin 解析（deterministic）

- 普通 client-visible pin 生效优先级：`global > project`
- `memory_core` 为保留系统层；若内部兼容快照暴露该层，也只表示规则资产状态，不接受普通 client pin。
- 同层冲突：`updated_at_ms DESC`，再 `package_sha256` 字典序兜底。
- 输出必须 deterministic（同输入重复解析结果一致）。

补充边界：
- `memory_core` 被保留并不意味着 client/runner 获得 memory authority；memory executor 仍由用户在 X-Hub 中选择。
- 即使技能链路 fail-closed，也不替代 `memory_model_preferences -> Scheduler -> Worker -> Writer + Gate` 这条 memory 控制面。

### 3.2 Revocation 数据面

- 文件：`<hub_base>/skills_store/revoked.json`
- 支持三类撤销键：
  - `revoked_sha256[]`
  - `revoked_skill_ids[]`
  - `revoked_publishers[]`

### 3.3 双侧阻断规则

1. **Hub Download 侧**  
   `GetSkillManifest` / `DownloadSkillPackage` 命中 revoked -> `deny(revoked)`。
2. **Runner Execute 侧**  
   执行前调用统一 gate（`evaluateSkillExecutionGate`）：
   - 先判 revocation；
   - 再判签名 + 双 hash；
   - 任一失败 -> `allowed=false, deny_code=*`。

### 3.4 冲突 + revoked 的 fail-closed 策略

- 若高优先级 pin 命中 revoked，不回退低优先级 pin（避免绕过撤销），输出 blocked 结果并审计。

---

## 4) 回滚点（Rollback Points）

治理文件活跃路径与快照路径：

- `skills_pins.json` -> `skills_pins.last_stable.json`
- `trusted_publishers.json` -> `trusted_publishers.last_stable.json`
- `revoked.json` -> `revoked.last_stable.json`

说明：
- pin 写入前自动保留上个稳定快照。
- trusted/revoked 在首次加载时保留稳定快照（若快照缺失）。

---

## 5) Gate / KPI 对齐

- Gate: `SKC-G2` / `SKC-G4`
- KPI:
  - `unsigned_high_risk_skill_exec = 0`
  - `tamper_detect_rate = 100%`
  - `revoked_skill_execution_attempt_success = 0`
  - `pin_resolution_determinism = 100%`

---

## 6) 机判证据（当前实现）

- 校验实现：`x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
- 服务阻断/审计：`x-hub/grpc-server/hub_grpc_server/src/services.js`
- 回归用例：`x-hub/grpc-server/hub_grpc_server/src/skills_store_security.test.js`

回归命令：

```bash
cd x-hub/grpc-server/hub_grpc_server
node src/skills_store_security.test.js
```

覆盖回归：
- manifest 签名篡改 -> `deny(signature_invalid)`
- 文件 hash 漂移 -> `deny(hash_mismatch)`
- revoked 后离线缓存重放 -> `execute deny(revoked)`
