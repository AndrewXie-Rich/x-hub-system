# X-Hub 扩展产品化借鉴模式 v1

- version: v1.0
- updatedAt: 2026-03-18
- owner: Hub Runtime / X-Terminal / Security / Packaging / QA
- status: proposed-active
- scope: 把从 `IronClaw` 提炼出的高价值扩展工程模式，转译成适用于 `X-Hub-System` 的 governed package / governed capability productization 方案。
- related:
  - `docs/memory-new/xhub-ironclaw-reference-adoption-checklist-v1.md`
  - `docs/xhub-skills-signing-distribution-and-runner-v1.md`
  - `docs/xhub-skills-discovery-and-import-v1.md`
  - `docs/xhub-client-modes-and-connectors-v1.md`
  - `docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `protocol/hub_protocol_v1.proto`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `official-agent-skills/`

## 0) One-Line Product Rule

冻结规则：

`任何将进入 X-Hub 主链的可复用能力单元，都必须被视为 governed package，而不是“仓库里多一个脚本 / 本地多一个插件 / runtime 里多一个开关”。`

这意味着它至少要有：

- 声明式 manifest
- artifact 完整性验证
- auth / setup contract
- compatibility gate
- activation / revoke lifecycle
- doctor / diagnostics
- scenario test evidence

## 1) 适用对象

本模式适用于 4 类包：

1. `Official Skill Package`
   - 官方 skills
   - 官方 agent skill channel
   - governed retry / audit / pin / revoke 主链

2. `Operator Channel Package`
   - Slack
   - Telegram
   - Feishu
   - WhatsApp Cloud / WhatsApp Personal QR

3. `Connector Package`
   - Email
   - Calendar
   - future Docs / Drive / enterprise connectors

4. `Local Provider Pack`
   - embeddings
   - audio / speech
   - vision / OCR
   - local inference provider adapters

## 2) 明确不适用对象

下面这些不能伪装成普通 extension：

- `grant / policy / audit / kill-switch` 本身
- `Hub memory truth` 本身
- `project governance truth` 本身
- `trusted automation local permission owner` 本身

这些是 control-plane primitive，不是普通 package。

## 3) 目标形态

### 3.1 Package = 能力单元，不等于“可完全信任的代码块”

在 X-Hub 里，package 只是：

- 可被发现
- 可被验证
- 可被安装
- 可被授权
- 可被激活
- 可被诊断
- 可被升级 / 回滚 / 撤销

它不自动等于：

- 已被完全信任
- 可直接访问 secrets
- 可直接执行高风险动作
- 可绕过 grant / audit / policy

### 3.2 Package Lifecycle 必须统一

统一状态建议冻结为：

1. `discovered`
2. `staged`
3. `verified`
4. `auth_required`
5. `approval_required`
6. `ready`
7. `active`
8. `degraded`
9. `revoked`
10. `removed`

## 4) Manifest Contract（借鉴 IronClaw，但改成 Hub-first）

### 4.1 顶层字段

每个 package 最少包含：

- `package_id`
- `display_name`
- `kind`
- `version`
- `contract_version`
- `protocol_compat_version`
- `description`
- `keywords`
- `tags`
- `owner_scope`
- `trust_tier`
- `source`
- `artifacts`
- `auth_summary`
- `capabilities`
- `required_grants`
- `doctor_checks`
- `audit_contract`

### 4.2 `kind` 建议冻结

- `official_skill`
- `operator_channel`
- `connector`
- `local_provider_pack`
- `external_adapter`

### 4.3 `trust_tier` 建议冻结

- `hub_native`
- `governed_package`
- `local_runner_bound`
- `external_process_low_trust`

说明：
- `hub_native` 只留给 control-plane 内建能力。
- 普通 package 默认不进入 `hub_native`。

### 4.4 `source` 字段

建议支持：

- `embedded_catalog`
- `signed_remote_catalog`
- `local_staging`
- `source_fallback`

### 4.5 `artifacts` 字段

至少包含：

- `download_url`
- `sha256`
- `signature_ref`
- `artifact_kind`
- `capabilities_manifest_url`
- `doctor_bundle_ref`

## 5) Capability Contract（必须声明式，不可散落）

### 5.1 统一 capability 分类

建议按 7 类冻结：

1. `http`
2. `workspace_read`
3. `package_invoke`
4. `secret_mapping`
5. `webhook`
6. `channel_surface`
7. `device_execution_bridge`

### 5.2 `http` capability 需要声明

- `allowlist`
- `methods`
- `path_prefix`
- `max_request_bytes`
- `max_response_bytes`
- `timeout_ms`
- `rate_limit`
- `credential_mappings`

### 5.3 `secret_mapping` 需要声明

- `secret_name`
- `injection_location`
- `host_patterns`
- `scope`
- `rotation_policy`

### 5.4 `channel_surface` 需要声明

- `allowed_paths`
- `webhook_secret`
- `polling_allowed`
- `workspace_prefix`
- `emit_rate_limit`
- `owner_binding_mode`

### 5.5 `device_execution_bridge` 需要声明

仅适用于 trusted automation 相关包：

- `requires_paired_device_profile`
- `requires_project_binding`
- `requires_permission_owner`
- `requires_hub_remote_posture`

说明：
- 任何涉及 device side effect 的 package，不能只声明“我需要某个 device API”。
- 必须声明四平面 readiness 条件。

## 6) Auth / Setup Contract（要产品化，不要散到主程序）

### 6.1 统一 auth 模式

建议冻结：

- `oauth`
- `manual_secret`
- `approve_once_binding`
- `shared_auth_group`
- `none`

### 6.2 `auth_summary` 至少包含

- `method`
- `provider`
- `secrets`
- `shared_auth`
- `setup_url`
- `token_hint`
- `validation_endpoint`

### 6.3 为什么要学这个模式

如果没有统一 auth/setup contract，后面一定会出现：

- Hub UI 一套 setup
- X-Terminal 一套 setup
- gRPC service 一套 setup
- work order 文档再写一套 setup

结果是：

- 用户路径不一致
- secret policy 不一致
- 审计缺口多

### 6.4 对 X-Hub 的适配要求

和 IronClaw 不同，X-Hub 必须额外声明：

- `grant_scope_required`
- `paired_surface_required`
- `owner_local_approval_required`
- `remote_export_posture_required`

也就是说：

auth 成功不等于可以执行。

## 7) Registry / Catalog Model

### 7.1 为什么 registry 是必需品

没有 registry，包分发就会退化成：

- 仓库路径约定
- 人工复制文件
- README 里写几句安装说明

这对 governed package 不够。

### 7.2 建议的 catalog 分层

1. `Embedded Official Catalog`
   - 随 Hub 发布
   - 离线可用
   - 适合 official skills / official channels

2. `Signed Remote Catalog`
   - 用于更新、灰度、撤销、增量分发

3. `Local Staging Catalog`
   - 给管理员 / 开发者在本地做 review 与 smoke

### 7.3 registry entry 建议字段

- `package_id`
- `kind`
- `display_name`
- `description`
- `version`
- `tags`
- `downloadability`
- `buildability`
- `auth_hint`
- `doctor_support`
- `fallback_source`
- `risk_summary`

## 8) Artifact Integrity And Compatibility Gates

### 8.1 必须要有 checksum / signature / fallback

建议冻结：

- artifact 下载必须校验 `sha256`
- official package 必须校验签名
- 校验失败必须显式 deny
- 如果允许 source fallback，必须也走验证链

### 8.2 兼容门禁至少三层

1. `contract compatibility`
   - manifest schema
   - capability schema

2. `protocol compatibility`
   - proto / gRPC
   - channel ingress envelope
   - skill dispatch contract

3. `runtime compatibility`
   - 当前 host 是否能实例化/执行该包

### 8.3 建议新增门禁

- `package_compat_check`
- `package_manifest_check`
- `artifact_integrity_check`
- `fallback_install_check`

## 9) Unified Package Manager（Hub 内统一）

### 9.1 职责边界

统一 package manager 负责：

- search
- stage
- verify
- auth
- activate
- deactivate
- revoke
- upgrade
- remove
- diagnostics

### 9.2 不应该由 package manager 直接做的事

- 充当最终 trust root
- 覆盖 Hub policy / grant 决策
- 直接持有长期 memory truth

### 9.3 推荐状态对象

每个 package 至少应有：

- `package_id`
- `version`
- `state`
- `verified_at`
- `auth_state`
- `approval_state`
- `doctor_state`
- `degraded_reason`
- `last_success_at`
- `last_failure_at`
- `audit_ref`

## 10) Diagnostics / Doctor / Recovery

### 10.1 每个 package 都应有 doctor checks

最少支持：

- manifest parse
- artifact integrity
- auth readiness
- endpoint readiness
- grant readiness
- runtime readiness
- recent failure summary

### 10.2 doctor 输出建议

统一格式：

- `pass`
- `fail`
- `skip`
- `next_step`

### 10.3 对你们最重要的 4 个 doctor 组合包

1. `official skills doctor`
2. `operator channels doctor`
3. `local provider runtime doctor`
4. `trusted automation readiness doctor`

## 11) Testing Strategy（不要只做 unit test）

### 11.1 测试分层

1. `T1 Manifest / schema tests`
2. `T2 package lifecycle tests`
3. `T3 compatibility tests`
4. `T4 replay scenario tests`
5. `T5 fuzz tests`

### 11.2 Replay Scenario Tests

建议首批覆盖：

- official skill install -> verify -> pin -> invoke -> retry
- channel first onboarding -> approve once -> bind -> first smoke
- local provider pack activate -> route selected -> runtime recover
- degraded package -> doctor output -> guided recovery

### 11.3 Compatibility Tests

从 IronClaw 借鉴的核心不是 WIT 本身，而是：

`旧包 + 新宿主` 必须有自动化验收。

对于 X-Hub，建议做：

- 历史 skill package 与当前 Hub 的兼容测试
- 历史 channel package 与当前 ingress/runtime 的兼容测试
- 历史 provider pack 与当前 provider runtime resolver 的兼容测试

### 11.4 Fuzz Tests

优先对象：

- package manifest parser
- capability parser
- auth metadata parser
- URL allowlist validator
- channel binding payload parser
- package doctor input parser

## 12) Setup Wizard / First-Run / Repair Flows

### 12.1 为什么要纳入本协议

package 如果只有 manifest、没有 setup / repair path，最终仍然不可用。

### 12.2 建议支持的模式

- `full onboarding`
- `provider-only repair`
- `channel-only repair`
- `package-only repair`
- `quick setup`

### 12.3 必须支持 incremental persist

理由：
- 多步 setup 最怕后一步失败导致前面信息丢失
- 对 channel / provider / connector 尤其致命

## 13) Dynamic Package Authoring（只能受治理）

### 13.1 可借鉴部分

可以借鉴：

- requirement extraction
- scaffold generation
- build loop
- validation
- package output

### 13.2 必须禁止部分

禁止：

- 动态生成后直接 `active`
- 无 review 进入 high-risk capability
- 把生成包默认视为官方可信包

### 13.3 正确路径

冻结为：

`generate -> stage -> validate -> security review -> package sign -> promote -> activate`

## 14) 外部生态接入分层（MCP / external process / adapters）

### 14.1 要学的不是“全接”，而是“明确分层”

建议冻结：

- `hub_native`
- `governed_package`
- `external_adapter_low_trust`

### 14.2 为什么重要

否则后面容易把：

- official skills
- external MCP
- local scripts
- connectors

都讲成“工具”，最终边界崩掉。

## 15) 与 X-Hub 当前主线的映射

### 15.1 Official Skills Channel

优先借鉴：

- manifest
- registry
- checksum
- compatibility gate
- doctor
- replay test rig

### 15.2 Operator Channels

优先借鉴：

- auth/setup contract
- approve-once binding
- validation endpoint
- package lifecycle manager
- degraded diagnostics

### 15.3 Local Provider Packs

优先借鉴：

- pack registry
- compatibility check
- doctor checks
- setup / repair flow
- fallback source / checksum

### 15.4 Trusted Automation

只借鉴产品化壳层：

- package manifest
- doctor
- replay tests

不借鉴其 trust simplification：

- device execution 仍必须满足四平面 readiness

## 16) 不该借鉴的模式

### 16.1 不把 XT 当扩展真相源

原因：
- 与 Hub-first truth 冲突

### 16.2 不把 package activation 当作最终授权

原因：
- 激活 != grant
- auth != permission

### 16.3 不把 external adapter 当作官方 governed package 等价物

原因：
- trust tier 不同

## 17) 建议的实施顺序

### P0

- 冻结 `governed package manifest v1`
- 冻结 `registry entry schema v1`
- 冻结 `artifact integrity gate v1`
- 冻结 `doctor output contract v1`

### P1

- official skills channel 全面接入
- operator channel packages 接入
- local provider packs 接入
- compatibility gate 上 CI

### P2

- dynamic package staging
- import / migration
- external adapter trust tiering

## 18) 最终结论

本文件的核心不是“把 IronClaw 的 WASM 生态照搬过来”，而是把它已经证明有效的扩展产品化模式，重写成适用于 X-Hub 的 Hub-first 版本：

`受治理包必须是可发现、可验证、可配置、可诊断、可升级、可撤销的能力单元；但它永远不能绕过 Hub 的 truth、grant、policy、audit 与 kill authority。`
