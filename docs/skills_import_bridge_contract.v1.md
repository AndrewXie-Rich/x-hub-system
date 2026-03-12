# Skill 导入桥接契约（Client Pull + Upload + Pin）v1

- version: v1.0
- frozenAt: 2026-03-01
- owner: Hub-L1
- scope: `SKC-W1-02`
- status: frozen
- machine-readable contract: `docs/skills_abi_compat.v1.json#import_bridge_contract`

## 1) 协议目标

在不改变 本机 add 心智的前提下，打通 Hub 纳管闭环：
- 本机继续按 skills ecosystem 习惯拉包（client pull）。
- Hub 执行入库规范化与审计（upload）。
- Hub 执行分层生效（pin）。

协议必须满足：
- fail-closed（不满足契约直接 deny）。
- 幂等可复放（重复请求不产生语义漂移）。
- 可审计（成功与失败均可机读复核）。

## 2) 协议主链

### Step-1 `client_pull`

输入：
- `source_id`
- `package_bytes`（tgz/zip）
- `manifest_json`（来自包内 `skill.json` 或显式参数）

要求：
- 仅拉包，不做 Hub 安全判定。
- 若 pull 失败，客户端本地直接报错（不进入 Hub）。

### Step-2 `upload` (`HubSkills.UploadSkillPackage`)

输入：
- `client`
- `request_id?`
- `source_id`
- `package_bytes`
- `manifest_json`

Hub 行为（冻结）：
1. source gate（allowlist）
2. manifest parse + ABI 映射
3. 核心字段校验（`skill_id/version/entrypoint.command`）
4. 生成 `package_sha256` 与 `manifest_sha256`
5. content-addressed 去重写入 `skills_store`
6. 落审计（成功/失败都写）

输出：
- `package_sha256`
- `already_present`
- `skill`（canonical SkillMeta）

### Step-3 `pin` (`HubSkills.SetSkillPin`)

输入：
- `client`（含 `user_id`，project scope 需 `project_id`）
- `request_id?`
- `scope`（`global|project`）
- `skill_id`
- `package_sha256`
- `note?`

Hub 行为（冻结）：
1. scope/identity 校验
2. `package_sha256` -> skill 元数据匹配校验
3. 按 `(scope,user_id,project_id,skill_id)` upsert pin
4. 落审计（成功/失败都写）

输出：
- `scope/user_id/project_id/skill_id/package_sha256/previous_package_sha256`

## 3) 幂等与去重语义

### 3.1 Upload 幂等

- dedup key: `package_sha256`
- 同包重复上传：
  - 不重复落盘包体
  - 响应 `already_present=true`
  - 保持语义稳定（不生成重复 skill 记录）

### 3.2 Pin 幂等

- upsert key: `scope + user_id + project_id + skill_id`
- 同 key 同 sha 重复 pin：
  - 允许重放
  - 返回稳定 `package_sha256`
  - `previous_package_sha256` 可用于判定是否发生版本切换

### 3.3 request_id 语义

- `request_id` 在 v1 作为追踪字段（审计关联），不是主幂等键。

## 4) 审计字段定义（Machine-Readable）

### 4.1 统一公共字段

- `event_type`
- `created_at_ms`
- `device_id`
- `user_id`
- `app_id`
- `project_id`
- `session_id`
- `request_id`
- `ok`
- `error_code`
- `error_message`

### 4.2 `skills.package.imported`

成功 `ext_json` 最小字段：
- `source_id`
- `package_sha256`
- `manifest_sha256`
- `abi_compat_version`
- `compatibility_state`
- `mapping_aliases_used[]`
- `defaults_applied[]`
- `skill_id`
- `version`
- `entrypoint_runtime`
- `entrypoint_command`
- `entrypoint_args[]`
- `package_size_bytes`
- `already_present`

失败 `ext_json` 最小字段：
- `source_id`
- `deny_code`
- `fix_suggestion`

### 4.3 `skills.pin.updated`

成功 `ext_json` 最小字段：
- `scope`
- `skill_id`
- `previous_package_sha256`
- `package_sha256`

失败 `ext_json` 最小字段：
- `scope`
- `skill_id`
- `package_sha256`
- `deny_code`
- `fix_suggestion`

## 5) 可执行修复建议（非抽象错误）

失败返回必须包含：
- 稳定 `deny_code`
- 可执行 `fix_suggestion`

示例：
- `invalid_manifest` -> “补齐 `skill_id/version/entrypoint.command` 后重试”
- `source_not_allowlisted` -> “改用 allowlist source_id，或先登记到 `skill_sources.json`”
- `package_not_found` -> “先 upload，再 pin”

## 6) KPI 绑定

- `skill_import_success_rate >= 98%`
- `import_to_first_run_p95_ms <= 12000`

契约口径：
- 成功率统计范围为经过 Step-2 + Step-3 的完整导入事务。
- 延迟口径从 upload request ingress 到首次 runner 可解析 resolved skill 为止。

## 7) Gate 对齐

- `SKC-G0`：契约字段、deny_code、审计字段冻结。
- `SKC-G1`：兼容正确性（别名映射、缺字段阻断、重复导入幂等）。
- `SKC-G3`：导入效率与首跑延迟达标。
