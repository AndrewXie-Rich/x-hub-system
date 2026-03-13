# Trusted Automation Mode 实现子工单包

- version: v1.0
- updatedAt: 2026-03-10
- owner: Hub-L5（Primary）/ XT-L2 / Security / QA / AI-COORD-PRIMARY
- status: planned
- scope: `TAM-W1-01..05` + `TAM-W2-01..03`
- parent:
  - `docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
  - `docs/memory-new/xhub-remote-pairing-autoreconnect-security-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w3-25-automation-product-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-27-hub-xt-ui-productization-r1-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-28-paired-terminal-trust-profile-and-budget-visibility-implementation-pack-v1.md`

## 0) 为什么要有这份包

`xhub-trusted-automation-mode-work-orders-v1.md` 已经把方向、边界、契约、Gate 冻结下来，但它仍偏“主工单层”。要真正进入实现，需要把它拆成：

- 可分 lane
- 可直接开工
- 有明确落点路径
- 有回归与证据文件名
- 能交给协作 AI 直接执行

本包的目标就是把 `trusted_automation` 主链拆到“写代码前最后一步”。

## 0.1) 已拆出的直接执行子包

- `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - 负责本地 permission owner、runner、device tool、Hub device grant bridge。
- `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - 负责 governed automation 的 goal -> recipe -> trigger -> run runtime 主链，并把现有 `AutomationProductGapClosure.swift` 骨架拉直到真实产品运行面。

两份子包分别对应“本地设备执行面”和“持续自动运行面”，共同补齐离 OpenClaw 模式仍缺的两大主缺口。

## 1) 主链与红线

### 1.1 主链

trusted automation 只在以下四平面同时为真时成立：

1. Hub paired-device profile = `trusted_automation`
2. XT current project 已绑定 trusted profile
3. 本地 device permission owner readiness = ready
4. Hub grant / budget / kill-switch / remote posture 允许

### 1.2 红线

- 不得把 `capabilities=[]` 当作新主链 super switch。
- 不得把 project 直接说成“持有 OS 权限主体”。
- 不得让未绑定 project 继承 trusted automation。
- 不得把 `Allow any source IP (unsafe)` 放进 trusted automation 默认路径。
- 不得出现“权限缺失但 UI 显示 active”的假绿。

## 2) 泳道拆分

### 2.1 Hub-L5

- 配对审批模式扩展
- trusted profile 存储与 runtime hardening
- auto-grant / deny / audit chain
- Hub operator views

### 2.2 XT-L2

- project binding
- device tool taxonomy
- runtime gate
- slash/UI 入口
- doctor/explainability

### 2.3 Security

- permission owner identity
- system permission readiness snapshot
- MDM/PPPC posture
- remote strict posture binding

### 2.4 QA

- contract regression
- happy-path / deny-path matrix
- require-real evidence
- release gate

## 3) Gate / KPI 绑定

### 3.1 Gate

- `TAM-G0`：五份契约冻结并落盘。
- `TAM-G1`：Hub / XT 都有显式 `trusted_automation` 开关与状态。
- `TAM-G2`：`new_profile` 路径禁用空 capability allow-all。
- `TAM-G3`：project binding 生效，cross-project escape = 0。
- `TAM-G4`：system permission 缺失不会假绿。
- `TAM-G5`：happy path auto-approve，越界路径 deny code 稳定。
- `TAM-G6`：remote strict posture 绑定完成。
- `TAM-G7`：doctor / CI / release gate 机判接线。

### 3.2 KPI

- `trusted_automation_happy_path_manual_steps_after_enable = 0`
- `trusted_automation_false_green_rate = 0`
- `cross_project_device_scope_escape = 0`
- `system_permission_missing_but_active = 0`
- `trusted_automation_grant_auto_approve_success_rate >= 0.99`
- `remote_trusted_automation_success_rate >= 0.99`

## 4) 子工单分解

### 4.1 `TAM-W1-01-A` Trusted Profile Schema / Store / Migration

- 目标：把 `trusted_automation` 作为正式 trust profile 落到存储与迁移层。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubGRPCServerSupport.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/clients.js`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/PairingSupport.swift`
- 具体要求：
  - 为 paired device 增加 `mode/state/allowed_project_ids/allowed_workspace_roots/auto_grant_profile/device_permission_owner_ref`。
  - 旧设备不自动升级为 `trusted_automation`。
  - profile 缺字段时只能 `off|armed`，不能直达 `active`。
- 交付物：
  - `build/reports/tam_w1_01_a_profile_store_evidence.v1.json`

### 4.2 `TAM-W1-01-B` Runtime Hardening for `new_profile`

- 目标：堵住 `capabilities=[]` 在新主链上被当作 allow-all 的口子。
- 涉及路径：
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/clients.js`
- 具体要求：
  - `policy_mode=new_profile` 或 `trust_mode=trusted_automation` 时：
    - empty capabilities -> deny
    - deny code = `trusted_automation_capabilities_empty_blocked`
    - append audit
  - legacy path 兼容逻辑保留，但要显式隔离。
- 交付物：
  - `build/reports/tam_w1_01_b_runtime_hardening_evidence.v1.json`

### 4.3 `TAM-W1-02-A` Pairing Approval Toggle / Editor UX

- 目标：把 Hub 现有 `Approve with Policy` 和设备编辑页升级成 `trusted_automation` 模式入口。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/PairingSupport.swift`
- 具体要求：
  - 首次审批可选 `standard / trusted_automation`。
  - 设备编辑页展示 `off / armed / active / blocked`。
  - `Full` 仅保留为 capability shortcut，不等同 trusted automation。
  - UI 明确提示“系统权限不会被自动授予”。
- 交付物：
  - `build/reports/tam_w1_02_a_hub_pairing_ui_evidence.v1.json`

### 4.4 `TAM-W1-02-B` Hub Operator Summary / Binding Visibility

- 目标：让 operator 一眼看出 trusted profile、binding、permission owner、remote posture 是否齐全。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
- 具体要求：
  - 设备列表至少展示：
    - mode
    - state
    - allowed projects
    - permission owner state
    - remote strict posture state
  - 提供一键复制 operator summary。
- 交付物：
  - `build/reports/tam_w1_02_b_operator_summary_evidence.v1.json`

### 4.5 `TAM-W1-03-A` XT Project Binding Persistence

- 目标：把 trusted automation 绑定到 project，而不是整个 XT。
- 涉及路径：
  - `x-terminal/Sources/Project/AXProjectConfig.swift`
  - `x-terminal/Sources/Project/ProjectModel.swift`
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
- 具体要求：
  - `AXProjectConfig` 新增：
    - `automationMode`
    - `trustedAutomationDeviceId`
    - `deviceToolGroups`
    - `workspaceBindingHash`
  - project snapshot 输出 binding 状态。
  - 未绑定 project 默认没有 device automation surface。
- 交付物：
  - `build/reports/tam_w1_03_a_project_binding_store_evidence.v1.json`

### 4.6 `TAM-W1-03-B` Device Tool Group Taxonomy + Runtime Gate

- 目标：为 device automation 新增独立工具组，并绑定到 trusted automation 条件。
- 涉及路径：
  - `x-terminal/Sources/Tools/ToolProtocol.swift`
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
  - `x-terminal/Sources/UI/TerminalChatView.swift`
- 具体要求：
  - 新增 `group:device_automation`。
  - 冻结首批 device tools：
    - `device.ui.observe`
    - `device.ui.act`
    - `device.screen.capture`
    - `device.clipboard.read`
    - `device.clipboard.write`
    - `device.browser.control`
    - `device.applescript`
  - runtime gate 必须检查：
    - project binding
    - permission owner readiness
    - same-project scope
    - Hub allow
- 交付物：
  - `build/reports/tam_w1_03_b_device_tool_gate_evidence.v1.json`

### 4.7 `TAM-W1-03-C` Slash / Settings Entry for Per-Project Arming

- 目标：给当前 project 一个明确的启用/查看入口。
- 涉及路径：
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
  - `x-terminal/Sources/UI/TerminalChatView.swift`
  - `x-terminal/Sources/UI/SettingsView.swift`
- 具体要求：
  - 新增 `/automation` 或 `/trusted-automation` 入口。
  - 可查看：
    - current mode
    - current state
    - bound device id
    - missing prerequisites
  - 可切换 `off / armed`，但 `active` 只能由 readiness 自动计算。
- 交付物：
  - `build/reports/tam_w1_03_c_project_entry_evidence.v1.json`

### 4.8 `TAM-W1-04-A` Device Permission Owner Identity Freeze

- 目标：明确哪一个 bundle 是 OS permission owner。
- 涉及路径：
  - `x-terminal/`
  - 新增或冻结 `Automation Runner` 相关路径
- 具体要求：
  - v1 必须在以下二选一中明确：
    - `X-Terminal.app` 自身持有权限
    - `XTerminalAutomationRunner.app` 持有权限
  - 选定后必须固定 bundle identity，避免反复触发系统权限重授权。
  - 安装位置异常时必须出 install doctor 提示。
- 交付物：
  - `build/reports/tam_w1_04_a_permission_owner_identity_evidence.v1.json`

### 4.9 `TAM-W1-04-B` System Permission Readiness Snapshot

- 目标：把设备权限 readiness 机读化。
- 涉及路径：
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-terminal/Sources/UI/HubSetupWizardView.swift`
  - `x-terminal/Sources/UI/SettingsView.swift`
  - 参考：
    - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SystemSettingsLinks.swift`
    - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/AppInstallDoctor.swift`
- 具体要求：
  - readiness 至少覆盖：
    - Accessibility
    - Automation
    - Screen Recording
    - Full Disk Access
    - Input Monitoring
  - 每项状态枚举：
    - `granted`
    - `missing`
    - `denied`
    - `managed`
  - `overall_state=partial` 时，不允许 active。
- 交付物：
  - `build/reports/tam_w1_04_b_permission_readiness_evidence.v1.json`

### 4.10 `TAM-W1-04-C` Deep Links / Repair Cards / Explainability

- 目标：权限缺失时，用户可以直接修复，不再只看到模糊 deny。
- 涉及路径：
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-terminal/Sources/UI/Components/TroubleshootPanel.swift`
  - `x-terminal/Sources/UI/HubSetupWizardView.swift`
- 具体要求：
  - 缺失权限必须显示：
    - 缺什么
    - 为什么需要
    - 去哪开
    - 开完后如何 refresh
  - repair entry 要和 Hub 侧 system settings deep links 保持语义一致。
- 交付物：
  - `build/reports/tam_w1_04_c_permission_repair_cards_evidence.v1.json`

### 4.11 `TAM-W1-05-A` Trusted Automation Auto-Grant Resolver

- 目标：happy path 自动批准，越界 fail-closed。
- 涉及路径：
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_agent_grant_chain.test.js`
- 具体要求：
  - 自动批准范围：
    - `terminal.exec`
    - `skills.execute.runner`
    - `web.fetch`
    - `ai.generate.paid`
    - 预留 `device.*`
  - 批准前依次检查：
    - hub capability
    - project binding
    - permission owner readiness
    - budget
    - kill switch
    - remote posture
  - `same_project_only` 固化为默认 scope guard。
- 交付物：
  - `build/reports/tam_w1_05_a_auto_grant_evidence.v1.json`

### 4.12 `TAM-W1-05-B` Deny Code / Audit / XT Explainability

- 目标：拒绝路径稳定且可解释。
- 涉及路径：
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-terminal/Sources/Hub/HubAIClient.swift`
  - `x-terminal/Sources/UI/Components/TroubleshootPanel.swift`
- 具体要求：
  - 统一 deny code 输出。
  - XT 端把 deny code 映射为：
    - headline
    - why it happened
    - next action
    - bound device name
    - project binding status
  - 不再退化成无上下文 `permission_denied`。
- 交付物：
  - `build/reports/tam_w1_05_b_deny_explainability_evidence.v1.json`

### 4.13 `TAM-W2-01` Hub / XT Unified Doctor

- 目标：Hub 与 XT 对 trusted automation 的状态解释完全一致。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-terminal/Sources/UI/SettingsView.swift`
  - `x-terminal/Sources/UI/HubSetupWizardView.swift`
- 具体要求：
  - 双端统一展示：
    - mode
    - state
    - missing prerequisites
    - remote strict posture
    - last deny code
  - Hub 是 device/operator 视角，XT 是 current project 视角，但口径必须一致。
- 交付物：
  - `build/reports/tam_w2_01_unified_doctor_evidence.v1.json`

### 4.14 `TAM-W2-02` Remote Strict Posture Binding

- 目标：trusted automation 和 remote strict posture 主链打通。
- 涉及路径：
  - `docs/memory-new/xhub-remote-pairing-autoreconnect-security-work-orders-v1.md`
  - `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
- 具体要求：
  - remote trusted automation 需要：
    - `remote_host`
    - mTLS
    - CIDR allowlist
    - no `any source IP`
  - 姿态不满足时，只能 `armed|blocked`。
  - 不允许 remote 绿牌绕过 `RPS` 主链。
- 交付物：
  - `build/reports/tam_w2_02_remote_binding_evidence.v1.json`

### 4.15 `TAM-W2-03` QA / CI / Release Gate Integration

- 目标：把这条链接到机判门禁。
- 涉及路径：
  - `.github/workflows/`
  - `scripts/`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_agent_grant_chain.test.js`
  - `x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift`
- 具体要求：
  - 增加 contract check、regression fixtures、vertical slice evidence。
  - release gate 至少包含：
    - happy path
    - empty capabilities deny
    - missing permission owner deny
    - cross-project deny
    - remote strict posture deny
  - require-real 证据优先。
- 交付物：
  - `build/reports/tam_w2_03_release_gate_evidence.v1.json`

## 5) 任务级执行包

### 5.1 `TAM-W1-01-A/B`

- 存储层优先做结构化字段，不要把 trusted automation 继续塞回单一 `capabilities[]`。
- `clients.js` 归一化输出必须能直接生成：
  - `mode`
  - `state`
  - `allowed_project_ids`
  - `device_permission_owner_ref`
- `services.js` 中 `clientAllows(...)` 的 legacy allow-all 逻辑必须和 new-profile path 明确分叉。
- 推荐新增测试：
  - `TrustedAutomationProfileNormalizationTests`
  - `TrustedAutomationCapabilitiesHardeningTests`

### 5.2 `TAM-W1-02-A/B`

- Hub UI 不允许把 trusted automation 做成隐藏式高级开关。
- pairing 与设备编辑两个入口都必须能看见 mode/state。
- operator summary 必须至少包含：
  - device name
  - mode/state
  - bound projects count
  - permission owner state
  - remote strict posture state

### 5.3 `TAM-W1-03-A/B/C`

- `toolProfile=full` 继续保留，但只表示工具档位。
- `group:device_automation` 必须独立存在，禁止把它隐含进 `group:full`。
- `/automation` 命令最少支持：
  - `/automation`
  - `/automation arm`
  - `/automation off`
  - `/automation status`
- 建议新增测试：
  - `ProjectTrustedAutomationBindingTests`
  - `ToolExecutorTrustedAutomationGateTests`

### 5.4 `TAM-W1-04-A/B/C`

- v1 优先做 readiness 与解释，不强行在本包内完成全部系统权限 API 接线。
- 如果屏幕录制 / FDA 检测能力有限，允许先以“显式 unknown + not active” fail-closed。
- install doctor 与 permission doctor 文案都要避免承诺“自动授权”。
- 建议新增测试：
  - `DevicePermissionOwnerReadinessTests`
  - `TrustedAutomationRepairCardSnapshotTests`

### 5.5 `TAM-W1-05-A/B`

- auto-grant 只能建立在 same-project scope。
- project 未绑定时，不允许因为设备整体是 trusted 就自动放行。
- deny code 至少固定以下项：
  - `trusted_automation_project_not_bound`
  - `device_permission_owner_missing`
  - `system_permission_missing`
  - `kill_switch_active`
  - `remote_posture_insufficient`
- 建议新增测试：
  - `TrustedAutomationGrantChainTests`
  - `TrustedAutomationDenyMappingTests`

### 5.6 `TAM-W2-01/02/03`

- doctor / remote posture / release gate 三条线必须并行推进，不要等功能完了再补。
- `trusted_automation active` 的绿牌逻辑只允许有一个统一实现，Hub 与 XT 都消费同一判断结果或同一字段口径。
- release gate 先做 contract + regression，再追加 require-real。

## 6) 最小回归矩阵

### 6.1 Happy Path

- 新 paired device 选择 `trusted_automation`
- 当前 project 完成 binding
- permission owner readiness = ready
- `terminal.exec` auto-approved
- `web.fetch` auto-approved
- `ai.generate.paid` auto-approved

### 6.2 Security Path

- `policy_mode=new_profile` + `capabilities=[]` -> deny
- project 未绑定 -> deny
- workspace hash 不匹配 -> deny
- `Allow any source IP (unsafe)=true` -> remote active denied
- kill switch active -> deny

### 6.3 Permission Path

- Accessibility missing -> not active
- Screen Recording missing -> not active
- install path unstable -> install doctor warning
- MDM managed permissions -> state=`managed`

### 6.4 Explainability Path

- XT 显示当前 deny code + next action
- Hub 显示当前 device state + missing prerequisites
- 无上下文 `permission_denied` 清零

## 7) 发布证据最小集

- `build/reports/tam_w1_01_a_profile_store_evidence.v1.json`
- `build/reports/tam_w1_01_b_runtime_hardening_evidence.v1.json`
- `build/reports/tam_w1_02_a_hub_pairing_ui_evidence.v1.json`
- `build/reports/tam_w1_02_b_operator_summary_evidence.v1.json`
- `build/reports/tam_w1_03_a_project_binding_store_evidence.v1.json`
- `build/reports/tam_w1_03_b_device_tool_gate_evidence.v1.json`
- `build/reports/tam_w1_03_c_project_entry_evidence.v1.json`
- `build/reports/tam_w1_04_a_permission_owner_identity_evidence.v1.json`
- `build/reports/tam_w1_04_b_permission_readiness_evidence.v1.json`
- `build/reports/tam_w1_04_c_permission_repair_cards_evidence.v1.json`
- `build/reports/tam_w1_05_a_auto_grant_evidence.v1.json`
- `build/reports/tam_w1_05_b_deny_explainability_evidence.v1.json`
- `build/reports/tam_w2_01_unified_doctor_evidence.v1.json`
- `build/reports/tam_w2_02_remote_binding_evidence.v1.json`
- `build/reports/tam_w2_03_release_gate_evidence.v1.json`

## 8) 并行推进顺序

1. `Hub-L5`
- 先做 `TAM-W1-01-A/B` 与 `TAM-W1-02-A`
- 再做 `TAM-W1-05-A/B`

2. `XT-L2`
- 并行做 `TAM-W1-03-A/B/C`
- 与 Security 协作做 `TAM-W1-04-B/C`

3. `Security`
- 先冻结 `TAM-W1-04-A`
- 再把 `TAM-W2-02` 接到 `RPS` 主链

4. `QA`
- 从第一天开始准备 regression fixtures，不等功能完工
- 最后汇总 `TAM-W2-03`

## 9) DoD

- [ ] 每个子工单都有明确路径、证据文件、回归样例。
- [ ] Hub / XT / Security / QA 的职责边界已冻结。
- [ ] `trusted_automation` 不再停留在概念层，而是具备直接开工的子任务集合。
- [ ] 后续协作 AI 可以直接按本包 claim 任务，不需要再反向拆分。
