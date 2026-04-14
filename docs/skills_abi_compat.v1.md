# Skill ABI 兼容契约（`skills_abi_compat.v1`）

- version: v1.0
- frozenAt: 2026-03-01
- owner: Hub-L1
- scope: `SKC-W1-01`, `SKC-W1-02`
- status: frozen
- machine-readable source: `docs/skills_abi_compat.v1.json`
- code anchors:
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store_manifest_compat.test.js`

## 1) 冻结边界（Fail-Closed）

本契约只冻结以下内容：
- skill manifest -> X-Hub canonical manifest 的字段映射、默认值、拒绝码。
- 导入桥接协议（`client pull + upload + pin`）与数据模型。
- 与导入相关的审计字段定义（成功与失败）。
- `memory_core` 作为保留系统层的 fail-closed 边界：不进入普通 client pin scope。

补充边界：
- `memory_core` 作为保留系统层，只表达 `Memory-Core` 规则资产状态，不决定哪个 AI 执行 memory jobs。
- memory executor 仍由用户在 X-Hub 中通过 `memory_model_preferences` 选择，durable memory writes 仍只允许经 `Writer + Gate` 落库。

不在本次冻结范围：
- grant 判定逻辑。
- 运行时安全策略阈值（allowlist 阈值、risk 阈值等）。

## 2) Manifest 核心字段映射（覆盖率目标 100%）

### 2.1 必填核心字段（安装/执行关键路径）

- `skill_id`
- `version`
- `entrypoint.command`

任一缺失：`deny(invalid_manifest)`。

### 2.2 映射表（含别名与默认值）

| Canonical 字段 | 别名输入（按优先级） | 默认值 | 缺失动作 |
|---|---|---:|---|
| `schema_version` | `schema_version`, `manifest_version` | `xhub.skill_manifest.v1` | default |
| `skill_id` | `skill_id`, `id` | - | `deny(invalid_manifest)` |
| `name` | `name`, `title` | `<skill_id>` | default |
| `version` | `version`, `skill_version` | - | `deny(invalid_manifest)` |
| `description` | `description`, `summary` | `""` | default |
| `entrypoint.runtime` | `entrypoint.runtime`, `runtime`, `entrypoint.type` | `node` | default |
| `entrypoint.command` | `entrypoint.command`, `entrypoint.exec`, `command`, `main`, `runner.command`, `entrypoint` | - | `deny(invalid_manifest)` |
| `entrypoint.args` | `entrypoint.args`, `entrypoint.arguments`, `args` | `[]` | default |
| `capabilities_required` | `capabilities_required`, `capabilities`, `required_capabilities` | `[]` | default |
| `network_policy.direct_network_forbidden` | `network_policy.direct_network_forbidden` | `true` | default |
| `publisher.publisher_id` | `publisher.publisher_id`, `publisher_id`, `publisher.id`, `author_id`, `author` | `unknown` | default |
| `install_hint` | `install_hint`, `install.command`, `install_hint.command` | `""` | default |

### 2.3 派生字段（强制 machine-readable）

- `package_sha256 = sha256(package_bytes)`（上传去重键）
- `manifest_sha256 = sha256(canonical_manifest_json)`（规范化 manifest 完整性）
- `mapping_aliases_used[]`（别名命中轨迹）
- `defaults_applied[]`（默认值命中轨迹）

## 3) Reject/Deny Code 冻结

| deny_code | 阶段 | 语义 | 修复建议类型 |
|---|---|---|---|
| `invalid_manifest` | `upload.validate_manifest` | 核心字段缺失/类型错误 | 补字段/修类型 |
| `invalid_manifest_json` | `upload.parse_manifest` | manifest 非法 JSON | 修 JSON |
| `missing_manifest_json` | `upload.parse_manifest` | 缺 manifest | 补 manifest |
| `invalid_package_bytes` | `upload.validate_package` | 包体为空/非法 | 重打包 |
| `source_not_allowlisted` | `upload.source_gate` | source 不在 allowlist | 换 source 或登记 |
| `skills_store_unavailable` | `upload.store_access` | store 不可写 | 修运行目录权限 |
| `package_too_large` | `upload.validate_package` | 包体超限 | 缩包或调阈值 |
| `invalid_pin_request` | `pin.validate_request` | pin 参数缺失 | 补参数 |
| `unsupported_scope` | `pin.validate_scope` | scope 非 global/project（含 `memory_core`） | 调整 scope |
| `missing_user_id` | `pin.identity` | 缺 user_id | 补 identity |
| `missing_project_id` | `pin.identity` | project scope 缺 project_id | 补 project_id |
| `package_not_found` | `pin.lookup` | sha 未上传 | 先 upload |
| `skill_package_mismatch` | `pin.lookup` | skill_id 与 sha 不匹配 | 用上传返回值 |

> 要求：所有 blocked 原因必须返回 machine-readable `deny_code`，并在审计中落 `fix_suggestion`。

## 4) 兼容矩阵（Supported / Partial / Blocked）

| case_id | 状态 | 输入场景 | 预期 |
|---|---|---|---|
| `OCM-001` | supported | canonical `xhub.skill_manifest.v1` | upload+pin 通过 |
| `OCM-002` | partial | 旧字段别名（`id/skill_version/main/capabilities/publisher_id`） | 正确映射并审计 alias |
| `OCM-003` | blocked | 缺 `entrypoint.command` | `deny(invalid_manifest)` |
| `OCM-004` | blocked | `source_id` 不在 allowlist | `deny(source_not_allowlisted)` |
| `OCM-005` | supported | 同包重复导入 | `already_present=true` + 去重 |
| `OCM-006` | supported | 同 skill 重复 pin | 幂等 upsert + `previous_package_sha256` 稳定 |
| `OCM-007` | blocked | client 侧 pin `memory_core`（保留系统层） | `deny(unsupported_scope)` |

## 5) 导入桥接（client pull + upload + pin）

导入桥接协议定义见：`docs/skills_import_bridge_contract.v1.md`。

本 ABI 契约与桥接协议的绑定点：
- Step-2 `UploadSkillPackage`：执行 ABI 映射、默认值补齐、deny_code fail-closed。
- Step-3 `SetSkillPin`：按 `scope+user_id+project_id+skill_id` 幂等 upsert。
- 全链路审计字段必须可复核：`source_id/package_sha256/manifest_sha256/scope/deny_code/fix_suggestion`。

## 6) Regression 契约样例（W1-01/W1-02）

- 缺 entrypoint -> `deny(invalid_manifest)`。
- 旧字段别名输入 -> 正确映射 + `mapping_aliases_used` 审计。
- 重复导入同包 -> upload 去重 + pin 幂等。

对应测试：`x-hub/grpc-server/hub_grpc_server/src/skills_store_manifest_compat.test.js`。
