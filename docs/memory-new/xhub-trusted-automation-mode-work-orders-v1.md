# X-Hub / X-Terminal Trusted Automation Mode（外部自动化终端兼容能力面）执行工单

- version: v1.0
- updatedAt: 2026-03-10
- owner: Hub-L5 / XT-L2 / Security / QA
- status: active
- scope: paired-device trust profile, XT project binding, local device permission owner, auto-grant chain, remote posture, doctor/release gate
- parent:
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/memory-new/xhub-remote-pairing-autoreconnect-security-work-orders-v1.md`
  - `docs/memory-new/xhub-security-innovation-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w3-25-automation-product-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-27-hub-xt-ui-productization-r1-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-28-paired-terminal-trust-profile-and-budget-visibility-implementation-pack-v1.md`

## 0) 为什么需要这份工单

当前代码已经有几块关键基础，但它们还是分散的：

- Hub 已经有 `Approve with Policy` 的首次配对审批入口。
- Hub 已经有 paired device 的 `Local-only / Full` capability 快捷配置。
- XT 已经有 project-local `toolProfile=minimal|coding|full`。
- Hub grant 链已经能处理 `terminal.exec` / `skills.execute.runner` / `web.fetch` / `ai.generate.paid` 的授权与审计。
- Hub / XT 已经各自有 Doctor、Settings、权限修复入口。

但它还不是一个可以产品化暴露的“全功能自动化模式”：

- 现在的 `Full` 只是 Hub 侧 capability 组合，不等于“设备级全权限”。
- XT 当前 `toolProfile=full` 只是本地工具面放开，不等于项目已经被授予设备控制权。
- `capabilities=[]` 在现有 Hub runtime 中仍会走 backward-compatible allow-all，这只能算兼容兜底，不能做正式用户开关。
- macOS 的设备级权限属于“App / helper bundle”，不属于“project”。也就是说，不能真的把一个项目本身变成“系统权限拥有者”；项目只能被允许调用一个已获授权的本地执行面。
- 你们的云是 X-Hub，所以正确架构不是“云拿本地系统权限”，而是：
  - X-Hub 作为控制平面与真相源
  - X-Terminal 本地执行面作为设备权限持有者与动作执行者

这份工单的目标，是把这些零散能力收敛成一个明确、可审计、可回滚、可远程安全运行的 `trusted automation mode`，其体验层面可覆盖用户想要的“外部自动化终端兼容能力面”，但实现方式必须继续遵守 X-Hub-System 的安全边界。

## 1) 目标与非目标

### 1.1 目标

- 提供一个显式命名的模式：`trusted_automation`。
- 用户打开开关后，得到的是“受控全功能自动化模式”，而不是隐藏式 allow-all。
- 把四条链收敛成一个主链：
  - Hub paired-device trust profile
  - XT project-local automation binding
  - local device permission owner / runner
  - Hub grant / audit / kill-switch / budget
- 让“一个项目可以使用完整设备自动化面”成为有边界的真命题：
  - 仅限被绑定的 project/workspace
  - 仅限已通过系统权限检查的本地执行面
  - 仅限已通过 Hub trust profile 的设备
- 保留 `Hub-first`：
  - 付费模型、联网、skills、审计、kill switch、远程策略仍由 Hub 统一裁决
  - XT 只执行本地设备动作，不成为第二个后端

### 1.2 非目标

- 不把 `capabilities=[]` 暴露为用户可点的“超级开关”。
- 不声称“开关一开就能自动拿到 macOS 所有系统权限”。
- 不允许未绑定 project 默认继承全部设备自动化能力。
- 不把“Allow any source IP (unsafe)”与 trusted automation 打包成推荐路径。
- 不把 X-Hub 云端本身设计成设备系统权限持有者。

## 2) 决策冻结

### 2.1 架构冻结：Hub 控制平面 + XT 设备执行平面

- `X-Hub`
  - 真相源
  - paired device policy source-of-truth
  - auto-grant / deny / audit / budget / kill-switch source-of-truth
- `X-Terminal`
  - 项目作用域的本地运行面
  - 只在被绑定 project 上暴露 trusted automation capability
- `X-Terminal Automation Runner`（可为主 app，也可为专用 helper，但必须有稳定 bundle identity）
  - 真正持有设备级系统权限
  - 真正执行本地 device automation 动作

冻结结论：

- “项目拥有设备权限”在系统层面应解释为：
  - 项目被允许调用一个已获授权的本地执行面
  - 而不是项目自己持有 OS 权限

### 2.2 模式命名冻结

- 内部机读模式名：`trusted_automation`
- UI 可展示为：
  - `Trusted Automation`
  - 副标题：`Full automation compatibility surface`
- 模式状态固定为：
  - `off`
  - `armed`
  - `active`
  - `blocked`

语义：

- `off`
  - 未启用
- `armed`
  - Hub / project 绑定已完成，但系统权限或远程姿态尚未完全 ready
- `active`
  - 四个平面全部 ready，可执行受控全功能自动化
- `blocked`
  - 明确被 kill switch / deny code / remote posture / permission 缺失阻断

### 2.3 四平面同时为真才算 Active

只有下面四项都为真，才允许 UI 显示 `active`：

1. Hub paired-device profile 为 `trusted_automation`
2. XT 当前 project 已绑定该 trusted profile
3. local device permission owner 已 ready
4. Hub grant / budget / kill switch / remote posture 当前允许

任一缺失都只能显示 `armed` 或 `blocked`，不得假绿。

### 2.4 `capabilities=[]` 禁止作为新主链

- 现有 runtime 的 empty-capabilities allow-all 仅保留给 legacy compatibility。
- 对于 `policy_mode=new_profile` 或 `trust_mode=trusted_automation`：
  - `capabilities` 必须显式列出
  - 若为空，必须 fail-closed
  - 必须写 audit

### 2.5 Project 绑定冻结

- trusted automation 不允许做成“设备全局所有项目默认生效”。
- 必须绑定到：
  - `project_id`
  - 或 `workspace_root`
  - 或两者同时存在
- 允许多个 project 绑定同一设备 profile，但必须显式列出。
- cross-project 调用默认 deny。

### 2.6 系统权限冻结

- 设备级权限必须由固定 bundle 持有。
- toggle 只能：
  - 检查状态
  - 提示用户授权
  - 打开系统设置
  - 读取 MDM/PPPC managed 状态
- toggle 不能：
  - 伪装成“已自动授权”
  - 跳过系统提示
  - 把缺失权限状态隐藏成可继续

### 2.7 Remote 姿态冻结

- 如果 `trusted_automation` 需要跨网工作，则自动继承 remote strict posture：
  - `remote_host` 非空
  - mTLS on
  - `allowed_cidrs` 收敛到 private / VPN overlay
  - `Allow any source IP (unsafe)` 默认禁止
  - remote admin 默认关闭
- remote posture 不达标时：
  - 本地同网可继续显示 `local_ready`
  - 但不得显示 `trusted_automation active`

### 2.8 XT 默认 `toolProfile=full` 不等于 trusted automation

- 现有 XT 默认工具档位是 `full`，这是开发便利，不是产品级安全承诺。
- 新模式必须增加一个独立判断层：
  - `toolProfile=full` 只是必要非充分条件
  - 只有 `trusted_automation binding + permission owner ready + Hub allow` 才可执行 device automation surface

## 3) 机读契约

### 3.1 `hub.trusted_automation_profile.v1`

```json
{
  "schema_version": "hub.trusted_automation_profile.v1",
  "device_id": "device_xt_001",
  "device_name": "Andrew-MBP-XT",
  "mode": "trusted_automation",
  "state": "armed",
  "policy_mode": "new_profile",
  "hub_capabilities": [
    "models",
    "events",
    "memory",
    "skills",
    "ai.generate.local",
    "ai.generate.paid",
    "web.fetch"
  ],
  "allowed_project_ids": [
    "project_alpha"
  ],
  "allowed_workspace_roots": [
    "/Users/andrew.xie/Documents/AX"
  ],
  "xt_binding_required": true,
  "auto_grant_profile": "trusted_automation_default",
  "network_posture_ref": "hub.remote_pairing_profile.v1:device_xt_001",
  "device_permission_owner_ref": "xt.device_permission_owner_readiness.v1:local_owner",
  "audit_ref": "audit-trusted-automation-001"
}
```

### 3.2 `xt.project_trusted_automation_binding.v1`

```json
{
  "schema_version": "xt.project_trusted_automation_binding.v1",
  "project_id": "project_alpha",
  "project_root": "/Users/andrew.xie/Documents/AX",
  "device_id": "device_xt_001",
  "mode": "trusted_automation",
  "state": "armed",
  "tool_profile": "full",
  "tool_allow": [
    "group:full",
    "group:device_automation"
  ],
  "tool_deny": [],
  "device_tool_groups": [
    "device.ui.observe",
    "device.ui.act",
    "device.screen.capture",
    "device.clipboard",
    "device.browser.control",
    "device.applescript"
  ],
  "requires_hub_profile": true,
  "workspace_binding_hash": "sha256:...",
  "audit_ref": "audit-xt-binding-001"
}
```

### 3.3 `xt.device_permission_owner_readiness.v1`

```json
{
  "schema_version": "xt.device_permission_owner_readiness.v1",
  "owner_id": "local_owner",
  "owner_type": "xterminal_automation_runner",
  "bundle_id": "com.xterminal.automationrunner",
  "install_state": "ready",
  "mode": "managed_or_prompted",
  "permissions": {
    "accessibility": "granted",
    "automation": "granted",
    "screen_recording": "missing",
    "full_disk_access": "missing",
    "input_monitoring": "missing"
  },
  "can_prompt_user": true,
  "managed_by_mdm": false,
  "overall_state": "partial",
  "open_settings_actions": [
    "privacy_accessibility",
    "privacy_automation",
    "privacy_screen_recording",
    "privacy_full_disk_access",
    "privacy_input_monitoring"
  ],
  "audit_ref": "audit-permission-owner-001"
}
```

### 3.4 `hub.automation_grant_resolution.v1`

```json
{
  "schema_version": "hub.automation_grant_resolution.v1",
  "device_id": "device_xt_001",
  "project_id": "project_alpha",
  "requested_action": "terminal.exec",
  "requested_scope": "same_project_only",
  "decision": "auto_approved",
  "reason_code": "",
  "trusted_mode": "trusted_automation",
  "hub_capability_checked": true,
  "project_binding_checked": true,
  "system_permission_checked": true,
  "budget_checked": true,
  "kill_switch_checked": true,
  "grant_id": "grant_001",
  "expires_at_ms": 0,
  "audit_ref": "audit-grant-resolution-001"
}
```

### 3.5 `xt.device_automation_surface.v1`

```json
{
  "schema_version": "xt.device_automation_surface.v1",
  "surface_id": "trusted_automation_default",
  "local_tools": [
    "run_command",
    "web_fetch",
    "web_search",
    "browser_read"
  ],
  "device_tools": [
    "device.ui.observe",
    "device.ui.act",
    "device.screen.capture",
    "device.clipboard.read",
    "device.clipboard.write",
    "device.browser.control",
    "device.applescript"
  ],
  "required_permissions": {
    "accessibility": true,
    "automation": true,
    "screen_recording": true,
    "full_disk_access": "recommended",
    "input_monitoring": "optional"
  },
  "audit_ref": "audit-device-surface-001"
}
```

### 3.6 统一拒绝码

- `trusted_automation_mode_off`
- `trusted_automation_project_not_bound`
- `trusted_automation_workspace_mismatch`
- `trusted_automation_profile_missing`
- `trusted_automation_capabilities_empty_blocked`
- `device_permission_owner_missing`
- `device_permission_owner_install_invalid`
- `system_permission_missing`
- `system_permission_partial`
- `device_automation_capability_denied`
- `kill_switch_active`
- `budget_exceeded`
- `grant_scope_mismatch`
- `remote_posture_insufficient`
- `unsafe_any_source_ip_forbidden`
- `legacy_allow_all_blocked_for_new_profile`

## 4) Gate / KPI

### 4.1 Gate

- `TAM-G0`：`trusted_automation_profile / project_binding / permission_owner_readiness / automation_grant_resolution / device_automation_surface` 五份契约冻结并落盘。
- `TAM-G1`：Hub UI 与 XT UI 都支持显式 `trusted_automation` 开关与状态展示，不再依赖 `Full`/隐式默认值。
- `TAM-G2`：`policy_mode=new_profile` 下禁止空 capability allow-all；legacy 兼容路径不影响新主链。
- `TAM-G3`：未绑定 project 不能借用已授权设备能力，cross-project 逃逸为 0。
- `TAM-G4`：缺失系统权限时状态必须落在 `armed|blocked`，不能显示 `active`。
- `TAM-G5`：`terminal.exec / skills.execute.runner / web.fetch / ai.generate.paid` 在 happy path 上可 auto-approve，在越界路径上可 machine-readable deny。
- `TAM-G6`：remote 模式下继续遵守 `VPN/tunnel + mTLS + CIDR allowlist + no any-source default`。
- `TAM-G7`：Doctor、CI、审计导出、回归证据全部接线，可进入 release gate。

### 4.2 KPI

- `trusted_automation_happy_path_manual_steps_after_enable = 0`
- `trusted_automation_false_green_rate = 0`
- `cross_project_device_scope_escape = 0`
- `capabilities_empty_used_as_new_profile_super_switch = 0`
- `system_permission_missing_but_active = 0`
- `unsafe_any_source_ip_enabled_by_default = 0`
- `trusted_automation_grant_auto_approve_success_rate >= 0.99`
- `remote_trusted_automation_success_rate >= 0.99`

## 5) 实施工单拆解

### P0（阻断主链）

#### `TAM-W1-01` Canonical Mode / Schema / Migration Freeze

- 目标：把 trusted automation 从“零散默认行为”升级成显式 schema 与状态机。
- 具体要求：
  - `trust_mode` / `policy_mode` 增加 `trusted_automation` 语义。
  - 新 profile 必须显式保存 `hub_capabilities`、`allowed_project_ids`、`device_permission_owner_ref`。
  - 对 `policy_mode=new_profile` 增加 hardening：
    - `capabilities=[]` -> deny
    - 写 audit
    - UI 不允许保存
  - 旧设备不自动迁移成 trusted automation，只保持当前行为。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubGRPCServerSupport.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/clients.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-terminal/work-orders/xt-w3-28-paired-terminal-trust-profile-and-budget-visibility-implementation-pack-v1.md`
- 交付物：
  - `build/reports/tam_w1_01_schema_migration_evidence.v1.json`
- 验收：
  - 新 profile 不再能通过 empty capabilities 获得隐式 allow-all。

#### `TAM-W1-02` Hub Paired Device Toggle + Policy Editor Productization

- 目标：把 Hub 现有配对审批与设备编辑，产品化成真正的 `trusted_automation` 开关。
- 具体要求：
  - 在首次配对页增加 mode 选择：
    - `standard`
    - `trusted_automation`
  - 在设备编辑页增加状态展示：
    - `off / armed / active / blocked`
  - 当切到 `trusted_automation` 时，自动填充：
    - Hub capability baseline
    - project binding required
    - strict remote posture requirement
  - 显示明确风险提示：
    - “这不是系统权限自动授予”
    - “需要本地 permission owner ready”
  - `Full` 按钮保留，但不得等同于 trusted automation。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/PairingSupport.swift`
- 交付物：
  - `build/reports/tam_w1_02_hub_ui_policy_evidence.v1.json`
- 验收：
  - 用户可以从 Hub 一眼看出：设备只是 `Full`，还是已经进入 `trusted_automation`。

#### `TAM-W1-03` XT Project Binding + Device Tool Group Convergence

- 目标：把 trusted automation 收敛到 project 维度，而不是泛化成“整个 XT 永久全开”。
- 具体要求：
  - `AXProjectConfig` 增加：
    - `automationMode`
    - `trustedAutomationDeviceId`
    - `deviceToolGroups`
    - `workspaceBindingHash`
  - 引入新 token / group：
    - `group:device_automation`
  - `toolProfile=full` 仅代表工具档位，不代表 trusted automation active。
  - 新增 project 入口：
    - project settings toggle 或 `/automation` slash command
  - 新增 device automation tool taxonomy，但必须明确挂在 trusted automation binding 上。
- 涉及路径：
  - `x-terminal/Sources/Project/AXProjectConfig.swift`
  - `x-terminal/Sources/Tools/ToolProtocol.swift`
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
  - `x-terminal/Sources/UI/TerminalChatView.swift`
- 交付物：
  - `build/reports/tam_w1_03_xt_project_binding_evidence.v1.json`
- 验收：
  - 同一设备上的未绑定 project 无法调用 `group:device_automation`。

#### `TAM-W1-04` Device Permission Owner / Runner + System Permission Readiness

- 目标：把“设备级权限”从模糊说法落到一个固定的本地权限持有者。
- 具体要求：
  - 冻结一个稳定 bundle identity：
    - `X-Terminal.app`
    - 或 `XTerminalAutomationRunner.app`
  - 以该 bundle 为唯一系统权限 owner。
  - 读取并展示下列状态：
    - Accessibility
    - Automation
    - Screen Recording
    - Full Disk Access
    - Input Monitoring
  - 状态枚举固定为：
    - `granted`
    - `missing`
    - `denied`
    - `managed`
  - trusted automation 打开后，如权限不全：
    - 显示 `armed` 或 `blocked`
    - 提供 `Open Settings`
    - 不得继续伪执行
  - 参考 Hub 现有 Install Doctor / Accessibility doctor 模式，但实现收口在 XT 本地执行面。
- 涉及路径：
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-terminal/Sources/UI/HubSetupWizardView.swift`
  - `x-terminal/Sources/UI/SettingsView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/AppInstallDoctor.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SystemSettingsLinks.swift`
- 交付物：
  - `build/reports/tam_w1_04_permission_owner_readiness_evidence.v1.json`
- 验收：
  - 权限缺失时，UI 只能给出修复动作，不能给出假成功。

#### `TAM-W1-05` Auto-Grant / Deny / Audit Chain for Trusted Automation

- 目标：让 trusted automation happy path 不再需要重复手批，但所有越界路径仍然 fail-closed。
- 具体要求：
  - 为下列动作增加 trusted-automation 自动批准语义：
    - `terminal.exec`
    - `skills.execute.runner`
    - `web.fetch`
    - `ai.generate.paid`
    - 未来 `device.*` 动作
  - 自动批准前必须检查：
    - Hub capability
    - project binding
    - system permission readiness
    - budget / quota
    - kill switch
    - remote posture
  - 越界时返回统一 deny code，不得退回无上下文 `permission_denied`。
  - 所有 auto-approve / deny 都必须写 audit。
- 涉及路径：
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_agent_grant_chain.test.js`
  - `x-terminal/Sources/Hub/HubAIClient.swift`
  - `x-terminal/Sources/UI/Components/TroubleshootPanel.swift`
- 交付物：
  - `build/reports/tam_w1_05_grant_chain_evidence.v1.json`
- 验收：
  - happy path 首次启用后不再要求项目自己给自己批同类 grant。

### P1（产品化与远程收口）

#### `TAM-W2-01` Hub / XT Doctor / Explainability Unification

- 目标：让 trusted automation 的状态、阻断原因、修复入口在 Hub 与 XT 两边都一致。
- 具体要求：
  - Hub 侧展示 device state + project bindings + permission owner readiness 摘要。
  - XT 侧展示 current project 是否 bound、缺哪个权限、缺哪条 remote posture。
  - `permission_denied`、`grant_required` 必须升级为带上下文的 trusted-automation 解释卡。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-terminal/Sources/UI/SettingsView.swift`
  - `x-terminal/Sources/UI/HubSetupWizardView.swift`
- 交付物：
  - `build/reports/tam_w2_01_doctor_explainability_evidence.v1.json`

#### `TAM-W2-02` Remote Strict Posture Integration

- 目标：trusted automation 跨网运行时，不退化成不安全的公网裸露模式。
- 具体要求：
  - 绑定 remote pairing profile。
  - 若 `trusted_automation` + remote：
    - `remote_host` required
    - mTLS required
    - CIDR allowlist required
    - `Allow any source IP` 默认禁用
  - remote posture 不满足时：
    - 允许 local-only
    - 禁止 remote-active
- 涉及路径：
  - `docs/memory-new/xhub-remote-pairing-autoreconnect-security-work-orders-v1.md`
  - `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
- 交付物：
  - `build/reports/tam_w2_02_remote_posture_evidence.v1.json`

#### `TAM-W2-03` CI / QA / Release Gate

- 目标：trusted automation 不只停留在设计文档，而是进入可机判的发布门禁。
- 具体要求：
  - 增加 contract checks。
  - 增加 vertical slice evidence：
    - pair device
    - bind project
    - prompt permissions
    - auto-approve `terminal.exec`
    - auto-approve `web.fetch`
    - deny cross-project escape
  - 增加 doctor/export artifact。
  - 形成 release GO/NO-GO checklist。
- 涉及路径：
  - `scripts/`
  - `.github/workflows/`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_agent_grant_chain.test.js`
  - `x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift`
- 交付物：
  - `build/reports/tam_release_gate_evidence.v1.json`

## 6) 回归样例

### 6.1 Regression A: empty capabilities still treated as super switch

- 前置：新 profile，`policy_mode=new_profile`，`capabilities=[]`
- 期望：
  - 保存失败
  - 返回 `trusted_automation_capabilities_empty_blocked`
  - 写 audit

### 6.2 Regression B: project B 借用 project A 的 trusted binding

- 前置：device/profile 绑定到 `project_alpha`，当前打开 `project_beta`
- 期望：
  - deny
  - 返回 `trusted_automation_project_not_bound`
  - 不执行本地 device action

### 6.3 Regression C: system permission missing but state shown active

- 前置：Screen Recording 缺失
- 期望：
  - 状态为 `armed` 或 `blocked`
  - 不显示 `active`
  - 提供 deep link

### 6.4 Regression D: remote mode with any-source IP still green

- 前置：`Allow any source IP (unsafe)=true`
- 期望：
  - trusted remote posture 不通过
  - 返回 `unsafe_any_source_ip_forbidden`

### 6.5 Regression E: happy path still asks repeated manual grants

- 前置：trusted automation active，same-project，预算内
- 动作：请求 `terminal.exec` / `web.fetch`
- 期望：
  - auto-approve
  - 不再重复人工批准

### 6.6 Regression F: cross-project side effect escaped through default full tool profile

- 前置：XT 默认 `toolProfile=full`，但当前 project 无 trusted binding
- 动作：请求 `device.ui.act`
- 期望：
  - deny
  - 返回 `device_automation_capability_denied`

## 7) 推进顺序

1. 先做 `TAM-W1-01` 与 `TAM-W1-02`
2. 再做 `TAM-W1-03` 与 `TAM-W1-05`
3. `TAM-W1-04` 与 Doctor/UX 并行推进
4. 远程严格姿态复用 `RPS` 主链，不单独发明第二套 remote 逻辑
5. 最后把 `TAM-W2-03` 接进 release gate

## 7.5) 当前已拆出的直接执行子包

- `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - 负责 `trusted_automation` 的 runner、permission owner、device tool adapters、Hub device grant bridge。
- `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - 负责 governed automation 的 recipe / trigger / run / checkpoint / timeline / bootstrap 主链。

这两份子包一起对应当前离“自动运行 OpenClaw 能力”仍差的两块：安全设备执行面，以及可持续自推进的 automation runtime。

## 8) 一句话结论

这份工单冻结的不是“一个危险的全权限开关”，而是一个可审计、可回滚、可跨网安全工作的 `trusted_automation` 主链：X-Hub 负责裁决，X-Terminal 本地执行面负责持有设备权限并执行动作，project 只在被绑定后才能使用这块能力面。
