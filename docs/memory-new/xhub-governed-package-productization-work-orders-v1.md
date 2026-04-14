# X-Hub Governed Package 产品化执行工单 v1

- version: v1.0
- updatedAt: 2026-03-18
- owner: Hub Runtime / X-Terminal / Packaging / Security / QA / Product 联合推进
- status: active-proposed
- parent:
  - `docs/memory-new/xhub-ironclaw-reference-adoption-checklist-v1.md`
  - `docs/memory-new/xhub-extension-productization-borrowed-patterns-v1.md`
  - `docs/memory-new/xhub-product-experience-leapfrog-work-orders-v1.md`
  - `docs/memory-new/xhub-spec-gates-work-orders-v1.md`

## 0) 使用方式（先看）

- 本工单把前面的 IronClaw 借鉴分析，收口成 X-Hub 可直接排期的 governed package 产品化任务。
- 目标不是“引入另一个插件体系”，而是把 skills、operator channels、connectors、local provider packs 统一纳入 Hub-first governed execution。
- 所有包相关能力，必须继续经过主链：`ingress -> risk classify -> policy -> grant -> execute -> audit`。
- 本文按 `P0 > P1 > P2` 排序，P0 不完成，不得把任何新 package surface 当成正式产品能力宣传。

## 1) 北极星目标与借鉴红线

### 1.1 北极星目标

- 目标 A：把可复用能力单元从“仓库里散落的实现”升级成“可发现、可验证、可安装、可诊断、可撤销”的 governed package。
- 目标 B：让 official skills、operator channels、local provider packs 共用一套 manifest、registry、doctor、compatibility、lifecycle 纪律。
- 目标 C：在不削弱 Hub-first truth / grant / audit / kill authority 的前提下，补上安装性、诊断性、版本兼容性、灰度与回滚能力。

### 1.2 不可跨越红线

- 不允许把 XT、web gateway、channel runtime、local runtime 升格为新的 durable truth source。
- 不允许把 package activation 等同于 permission grant。
- 不允许 auth 成功后直接跳过 `policy + grant + audit`。
- 不允许动态生成包未经 `stage -> validate -> review -> sign -> promote -> activate` 直接上线。
- 不允许 external adapter / MCP / local script 与官方 governed package 在 trust tier 上被表述为等价物。

## 2) 适用对象与非适用对象

### 2.1 适用对象

1. `Official Skill Package`
2. `Operator Channel Package`
3. `Connector Package`
4. `Local Provider Pack`
5. `External Adapter Package`（仅限低信任分层接入）

### 2.2 非适用对象

- `grant / policy / audit / kill-switch` 本身
- `Hub memory truth` 本身
- `project governance truth` 本身
- `trusted automation permission owner` 本身

这些属于 control-plane primitive，不是普通 package。

## 3) Governed Package Gate 体系

- `GP-G0 / Scope Boundary Freeze`
  - 借鉴内容、非借鉴内容、trust boundary 必须写清楚。
- `GP-G1 / Contract Freeze`
  - manifest、registry、doctor、compatibility contract 版本化冻结。
- `GP-G2 / Integrity + Compatibility`
  - checksum、signature、source fallback、旧包 + 新宿主兼容门禁通过。
- `GP-G3 / Governed Execution`
  - 不得绕过 `policy + grant + audit + kill-switch`。
- `GP-G4 / Diagnostics + Recovery`
  - `doctor`、setup、repair、degraded recovery、recent failures 可用。
- `GP-G5 / Replay + Fuzz`
  - 关键场景 replay 与高风险 parser fuzz 纳入 CI。
- `GP-G6 / Release Ready`
  - catalog 发布、撤销、灰度、回滚、changelog、安装说明齐备。

## 4) DoR / DoD（每个工单都必须满足）

Definition of Ready (DoR)
- package surface 边界明确，知道是 `official_skill / operator_channel / connector / local_provider_pack / external_adapter` 哪一类。
- 输入输出、失败语义、auth/setup、compatibility、doctor 需求完整。
- 受影响系统标注清楚：`Hub / XT / channel ingress / local runtime / docs / CI`。
- 验收指标可量化，并有 audit、metrics、report 或 fixture 作为数据源。

Definition of Done (DoD)
- 代码、contract、文档、测试、诊断、回滚方案同步完成。
- package 具备 `manifest + registry + integrity + compatibility + doctor + lifecycle + audit_ref`。
- 通过对应 `GP-Gate`，无口头豁免。
- 新增 surface 必须支持 `metrics + audit + rollback + revoke + owner`。

## 5) 季度 KPI（用于判断这条线值不值）

- `package_manifest_coverage = 100%`（进入主链的 package 全覆盖 manifest）
- `package_registry_coverage >= 95%`
- `checksum_verification_coverage = 100%`（official package）
- `compatibility_gate_block_rate = 100%`（不兼容包必须阻断）
- `doctor_bundle_coverage >= 90%`
- `degraded_package_guided_recovery_rate >= 80%`
- `install_or_upgrade_unknown_state_incidents = 0`
- `bypass_grant_execution = 0`

## 6) 工单总览（P0 / P1 / P2）

### P0（阻断型，先做）

1. `GP-W1-01` Governed Package Manifest v1 冻结
2. `GP-W1-02` Registry + Checksum + Source Fallback Contract v1
3. `GP-W1-03` Governed Package Manager 生命周期状态机
4. `GP-W1-04` Auth / Setup Contract + Wizard / Repair Path
5. `GP-W2-05` Compatibility Gates（contract / protocol / runtime）
6. `GP-W2-06` Doctor Output Contract + First 4 Bundles
7. `GP-W2-07` Scenario Replay Rig 骨架
8. `GP-W2-08` `xhub_security_kernel` + HTTP Allowlist Hardening

### P1（关键收益，形成产品壳层）

9. `GP-W3-09` Official Skills 全量接入 governed package
10. `GP-W3-10` Operator Channels 接入统一 lifecycle + diagnostics
11. `GP-W3-11` Local Provider Packs 接入 registry + compatibility + failover
12. `GP-W3-12` Signed Remote Catalog + Revoke / Rollback
13. `GP-W3-13` Capability Matrix + Public Parity Discipline
14. `GP-W3-14` Setup Wizard 增量持久化与分步修复
15. `GP-W4-15` Replay/Fuzz CI 门禁与兼容样本池

### P2（生态增强，需带边界）

16. `GP-W4-16` External Adapter / MCP Trust Tiering
17. `GP-W4-17` Gateway / Surface Boundary 整理
18. `GP-W4-18` Import / Migration Framework
19. `GP-W4-19` Heartbeat / Routines 与 Package 状态协同
20. `GP-W4-20` Release / Changelog / Install Discipline 收口

## 7) 详细工单（可直接执行）

### GP-W1-01（P0）Governed Package Manifest v1 冻结

- 目标：统一所有 governed package 的声明式 contract，消灭 service-specific setup 和 capability 配置散落。
- 依赖：无。
- 交付物：
  - `xhub_governed_package_manifest.v1.json`
  - manifest 字段说明文档
  - 示例 package 清单各 1 份：skill、channel、provider pack
- 验收指标：
  - 主链 package manifest 覆盖率 `>= 80%`
  - 字段漂移零容忍，contract 变更必须 version bump
- 回归样例：
  - 缺 `trust_tier` / `required_grants` / `doctor_checks` -> 阻断
  - device side effect package 未声明四平面 readiness -> 阻断
- Gate：`GP-G1/GP-G3`
- 估时：1 天

### GP-W1-02（P0）Registry + Checksum + Source Fallback Contract v1

- 目标：建立 official package catalog 分发基线，杜绝 README 安装说明式分发。
- 依赖：`GP-W1-01`
- 交付物：
  - `xhub_package_registry_entry.v1.json`
  - embedded catalog 示例
  - checksum mismatch / source fallback 错误码字典
- 验收指标：
  - official package checksum 覆盖率 `= 100%`
  - revoked package 激活成功次数 `= 0`
- 回归样例：
  - artifact checksum mismatch -> fail closed
  - remote catalog 不可达 + fallback 不存在 -> 明确错误语义
- Gate：`GP-G1/GP-G2/GP-G6`
- 估时：1 天

### GP-W1-03（P0）Governed Package Manager 生命周期状态机

- 目标：把 skills、channels、provider packs 的安装/验证/授权/激活/撤销收口到统一 manager。
- 依赖：`GP-W1-01`, `GP-W1-02`
- 交付物：
  - 统一 state enum：`discovered -> staged -> verified -> auth_required -> approval_required -> ready -> active -> degraded -> revoked -> removed`
  - package status truth contract
  - install / upgrade / revoke / remove API 草案
- 验收指标：
  - 未知状态事件 `= 0`
  - 安装与撤销结果均带 `audit_ref`
- 回归样例：
  - 已 revoked 包尝试恢复 active -> 必须拒绝
  - auth 完成但 grant 未完成 -> 不得进入 active
- Gate：`GP-G1/GP-G3/GP-G4`
- 估时：1.5 天

### GP-W1-04（P0）Auth / Setup Contract + Wizard / Repair Path

- 目标：把 auth/setup 从散落实现改成统一 contract，并补上首次配置与修复路径。
- 依赖：`GP-W1-01`
- 交付物：
  - auth method enum 与 `auth_summary` contract
  - setup wizard 路径：`full_onboarding / provider_only_repair / channel_only_repair / package_only_repair / quick_setup`
  - incremental persist 规则
- 验收指标：
  - setup 中断后状态丢失率 `< 1%`
  - provider/channel repair 完成后恢复成功率 `>= 80%`
- 回归样例：
  - validation endpoint 失败 -> guided repair
  - auth 成功但 `owner_local_approval_required` 未满足 -> 仍阻断执行
- Gate：`GP-G1/GP-G3/GP-G4`
- 估时：1.5 天

### GP-W2-05（P0）Compatibility Gates（contract / protocol / runtime）

- 目标：建立“旧包 + 新宿主”自动化兼容门禁，防止静默损坏。
- 依赖：`GP-W1-01`, `GP-W1-02`
- 交付物：
  - `package_manifest_check`
  - `package_compat_check`
  - `artifact_integrity_check`
  - `fallback_install_check`
- 验收指标：
  - 官方历史包样本兼容检查覆盖率 `>= 90%`
  - 不兼容包进入 active 的次数 `= 0`
- 回归样例：
  - manifest contract version 漂移
  - proto / ingress envelope 不兼容
  - host runtime 无法实例化旧包
- Gate：`GP-G2/GP-G6`
- 估时：1.5 天

### GP-W2-06（P0）Doctor Output Contract + First 4 Bundles

- 目标：把 package 诊断从“看日志猜问题”升级成标准化 doctor 输出。
- 依赖：`GP-W1-03`, `GP-W1-04`
- 交付物：
  - `xhub_package_doctor_output_contract.v1.json`
  - 4 个 doctor bundle：`official_skills`, `operator_channels`, `local_provider_runtime`, `trusted_automation_readiness`
  - `next_step` 语义规范
- 验收指标：
  - degraded package 可给出可执行 `next_step` 的比例 `>= 90%`
  - doctor 输出缺 `audit_ref` 次数 `= 0`
- 回归样例：
  - artifact 破损
  - webhook binding 丢失
  - provider runtime 缺失依赖
  - trusted automation 四平面未满足
- Gate：`GP-G4/GP-G6`
- 估时：1.5 天

### GP-W2-07（P0）Scenario Replay Rig 骨架

- 目标：建立 package 关键主链 replay 基础设施，避免功能存在但无法稳定回归。
- 依赖：`GP-W1-03`, `GP-W2-05`, `GP-W2-06`
- 交付物：
  - replay fixture 目录结构
  - 首批 4 个 replay 样本：
    - skill install -> verify -> pin -> invoke -> retry
    - channel first onboarding -> approve once -> bind -> first smoke
    - local provider pack activate -> route selected -> runtime recover
    - degraded package -> doctor output -> guided recovery
- 验收指标：
  - 首批 replay 样本稳定率 `>= 95%`
  - replay 失败可追溯到 `package_id + contract_version + host_version`
- 回归样例：
  - source fallback 安装路径
  - revoke 后重试激活
- Gate：`GP-G5`
- 估时：1.5 天

### GP-W2-08（P0）`xhub_security_kernel` + HTTP Allowlist Hardening

- 目标：把高风险校验沉淀为共享安全内核，而不是散在 package handler 里。
- 依赖：`GP-W1-01`
- 交付物：
  - 第一版模块边界：`url_validator / checksum_verifier / signature_verifier / manifest_parser / auth_metadata_validator / leak_guard`
  - HTTP allowlist 深化校验：`scheme / userinfo / host / method / path_prefix / normalization`
  - deny code 标准化
- 验收指标：
  - allowlist 绕过回归阻断率 `= 100%`
  - 共享 validator 重用率 `>= 80%`
- 回归样例：
  - userinfo 注入
  - path normalize 绕过
  - wildcard host 漏洞
- Gate：`GP-G2/GP-G3/GP-G5`
- 估时：2 天

### GP-W3-09（P1）Official Skills 全量接入 governed package

- 目标：把 `official-agent-skills` 从 catalog + manifest + lifecycle + doctor 角度完成产品化接入。
- 依赖：`GP-W1-01..GP-W2-08`
- 交付物：
  - official skills catalog
  - skill install / verify / pin / revoke 流程
  - first-party doctor bundle 接线
- 验收指标：
  - official skill governed coverage `>= 90%`
  - 未声明 manifest 的官方 skill 数 `= 0`
- 回归样例：
  - skill manifest 缺 grant
  - skill 版本升级后旧 pin 失效
- Gate：`GP-G2/GP-G4/GP-G6`
- 估时：2 天

### GP-W3-10（P1）Operator Channels 接入统一 lifecycle + diagnostics

- 目标：让 Slack / Telegram / Feishu / WhatsApp channel 走统一包生命周期与 setup/repair。
- 依赖：`GP-W1-04`, `GP-W2-06`
- 交付物：
  - operator channel package manifest 模板
  - channel onboarding / repair / smoke contract
  - degraded reason 标准化
- 验收指标：
  - operator channels doctor 覆盖率 `>= 90%`
  - 首次配置成功率持续提升并可观测
- 回归样例：
  - webhook secret 漂移
  - shared auth group 失效
  - approve-once binding 过期
- Gate：`GP-G3/GP-G4/GP-G6`
- 估时：2 天

### GP-W3-11（P1）Local Provider Packs 接入 registry + compatibility + failover

- 目标：把 embeddings / audio / vision / local inference provider adapters 统一成 provider pack。
- 依赖：`GP-W2-05`, `GP-W2-06`
- 交付物：
  - provider pack registry
  - runtime compatibility rules
  - provider failover / cooldown policy
- 验收指标：
  - provider 恢复时间 `p95 <= 30s`
  - incompatible provider pack 进入 active 次数 `= 0`
- 回归样例：
  - 本地 runtime 缺依赖
  - provider 冷却期内被错误重新选路
  - 同一 pack 在不同 host 能力下错误激活
- Gate：`GP-G2/GP-G4/GP-G6`
- 估时：2 天

### GP-W3-12（P1）Signed Remote Catalog + Revoke / Rollback

- 目标：让 catalog 具备远程灰度、撤销、回滚，而不是只能跟随代码发布。
- 依赖：`GP-W1-02`, `GP-W1-03`
- 交付物：
  - signed remote catalog contract
  - revoke state / rollback policy
  - catalog sync 审计报表
- 验收指标：
  - catalog 签名验证覆盖率 `= 100%`
  - revoke 生效延迟 `p95 <= 5min`
- 回归样例：
  - 远程 catalog 被篡改
  - 本地缓存过期仍激活 revoked 包
- Gate：`GP-G2/GP-G6`
- 估时：1.5 天

### GP-W3-13（P1）Capability Matrix + Public Parity Discipline

- 目标：建立对外可解释的 package capability matrix，避免 README 口径漂移。
- 依赖：`GP-W3-09`, `GP-W3-10`, `GP-W3-11`
- 交付物：
  - `XHUB_CAPABILITY_MATRIX_v1.md`
  - `validated / preview_working / protocol_frozen / implementation_in_progress / direction_only` 标注规范
- 验收指标：
  - 影响 capability state 的 PR 同步更新率 `= 100%`
  - README 与 matrix 冲突次数 `= 0`
- 回归样例：
  - capability 已降级但外部文案未更新 -> 阻断
- Gate：`GP-G0/GP-G6`
- 估时：1 天

### GP-W3-14（P1）Setup Wizard 增量持久化与分步修复

- 目标：把 wizard 真正做成产品化修复器，而不是一次性设置页。
- 依赖：`GP-W1-04`, `GP-W2-06`
- 交付物：
  - 增量持久化策略
  - package-only / channel-only / provider-only repair 流程
  - guided recovery 视图规范
- 验收指标：
  - 中途中断后恢复成功率 `>= 85%`
  - “重装解决”类问题比例持续下降
- 回归样例：
  - onboarding 第 3 步失败后重新进入
  - secret rotation 后局部修复
- Gate：`GP-G4/GP-G6`
- 估时：1.5 天

### GP-W4-15（P1）Replay/Fuzz CI 门禁与兼容样本池

- 目标：把 replay/fuzz 从建议变成阻断式质量门禁。
- 依赖：`GP-W2-07`, `GP-W2-08`
- 交付物：
  - parser fuzz target 列表
  - 历史 package compatibility 样本池
  - CI 报告模板
- 验收指标：
  - 高风险 parser fuzz 覆盖率 `>= 80%`
  - 新宿主对历史样本兼容回归率持续可观测
- 回归样例：
  - manifest parser 异常输入
  - allowlist validator 模糊测试
  - doctor input parser 随机输入
- Gate：`GP-G5/GP-G6`
- 估时：1.5 天

### GP-W4-16（P2）External Adapter / MCP Trust Tiering

- 目标：把 MCP / external process / local scripts 明确划入低信任分层，不与 governed package 混淆。
- 依赖：`GP-W1-01`, `GP-W2-08`
- 交付物：
  - `hub_native / governed_package / external_process_low_trust` 分层规范
  - external adapter onboarding contract
  - capability 限流与审计策略
- 验收指标：
  - trust tier 漂移问题 `= 0`
- 回归样例：
  - external adapter 试图声明 hub_native
- Gate：`GP-G0/GP-G3`
- 估时：1 天

### GP-W4-17（P2）Gateway / Surface Boundary 整理

- 目标：明确 web gateway、XT、mobile、channel surface 只是 surface，不是 trust root。
- 依赖：`GP-W1-03`
- 交付物：
  - control surface boundary 文档
  - surface -> package manager -> Hub policy 的调用图
- 验收指标：
  - surface 直改 truth source 路径 `= 0`
- 回归样例：
  - gateway 试图绕过 Hub 直接激活包
- Gate：`GP-G0/GP-G3`
- 估时：1 天

### GP-W4-18（P2）Import / Migration Framework

- 目标：支持历史 skill/channel/provider 配置迁移，不靠人工复制文件。
- 依赖：`GP-W1-03`, `GP-W3-12`
- 交付物：
  - import contract
  - migration assistant
  - drift 检测报告
- 验收指标：
  - 历史配置迁移成功率 `>= 90%`
- 回归样例：
  - 老 catalog entry 字段缺失
  - 历史 auth binding 映射不完整
- Gate：`GP-G4/GP-G6`
- 估时：1.5 天

### GP-W4-19（P2）Heartbeat / Routines 与 Package 状态协同

- 目标：把 heartbeat / routine engine 的工程化经验改写成 X-Hub 的 package-aware orchestration，而不是引入新的自治真相源。
- 依赖：`GP-W1-03`, `GP-W2-06`
- 交付物：
  - package degraded 状态与 supervisor / scheduler 联动规则
  - routine pause / retry / escalate contract
- 验收指标：
  - degraded package 导致的 routine 误执行次数 `= 0`
- 回归样例：
  - package degraded 时 routine 仍继续高风险动作
- Gate：`GP-G3/GP-G4`
- 估时：1 天

### GP-W4-20（P2）Release / Changelog / Install Discipline 收口

- 目标：补齐开源项目层面的 release hygiene，让包生态能被外部理解和采用。
- 依赖：`GP-W3-12`, `GP-W3-13`
- 交付物：
  - package changelog 模板
  - install / upgrade / revoke 文档模板
  - release checklist
- 验收指标：
  - 发布说明缺关键字段次数 `= 0`
- 回归样例：
  - 新包发布缺 compatibility note
  - revoked 包未出公告
- Gate：`GP-G6`
- 估时：1 天

## 8) 立即执行建议（本周）

1. 先冻结 3 份 contract：manifest / registry / doctor。
2. 随后启动 `GP-W1-03`，把 package state machine 作为后续接入总线。
3. 第一个接入对象优先选 `official skills`，因为最容易形成端到端样板。
4. 第二个接入对象选 `operator channels`，验证 auth/setup/repair/doctor 真正能跑通。
5. 第三个接入对象选 `local provider packs`，验证 compatibility + failover 的价值。

## 9) 最终结论

这条线真正要做的，不是“再发明一个插件系统”，而是：

`把 X-Hub 的可复用能力单元，升级成受治理、可验证、可诊断、可兼容、可撤销的 governed package；同时严格维持 Hub-first truth、grant、audit、kill authority 不被 package 产品化壳层稀释。`
