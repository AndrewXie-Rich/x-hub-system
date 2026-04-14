# Trusted Automation Device Execution Plane Implementation Pack v1

- version: v1.0
- updatedAt: 2026-03-10
- owner: XT-L2（Primary）/ Security / Hub-L5 / QA
- status: planned
- scope: `trusted_automation` 的本地设备执行面、permission owner、runner IPC、device tool adapters、grant/audit bridge、real-device evidence
- parent:
  - `docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
  - `docs/memory-new/xhub-trusted-automation-mode-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-25-automation-product-gap-closure-implementation-pack-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## 0) 为什么要单开这份包

当前 `trusted_automation` 的控制平面、绑定平面、deny-path 与审计平面已经在收口，但离“可像 OpenClaw 模式那样真正自动调用设备能力”还差最后一层硬件面:

- 哪个 bundle 才是稳定的 OS permission owner 还没有真正冻结到代码目标。
- XT 还缺一个可机读、可审计、可回滚的本地 automation runner 执行面。
- `device.*` 还没有以正式工具组接到 Hub grant / audit / deny code 主链。
- real-device smoke / release evidence 还没有形成 require-real 主链。

这份包只解决这一个问题：把“设备级自动化能力”从概念和权限说明，收口为真正可执行的本地运行面。

## 1) 成品目标

完成后，`trusted_automation` 至少要满足下面事实：

1. 当前 project 被绑定后，可以调用一个已冻结身份的本地 automation runner。
2. runner 只接受来自同用户、同设备、同 project、同 session 边界内的指令。
3. 所有 `device.*` 动作在执行前都要经过 Hub capability / grant / budget / kill-switch / posture 审核。
4. 系统权限缺失时永远 fail-closed，只能显示 `armed|blocked`，不得假绿。
5. 每次本地设备动作都可追溯到：
   - run / request / grant
   - project binding
   - permission owner readiness
   - audit event

## 2) 冻结建议

### 2.1 v1 推荐采用独立 Runner Bundle

推荐路径：

- `XTerminal.app` = 控制面 / UX / supervisor / project runtime
- `XTerminalAutomationRunner.app` = 设备权限持有者与本地动作执行者

原因：

- 系统权限重授权成本高，bundle identity 必须稳定。
- 将高风险本地自动化面与主 UI 进程隔离，更利于后续 code-sign / notarization / doctor / crash triage。
- 未来如果要收敛为 helper / login item / managed install，也更容易演进。

### 2.2 v1 首批正式工具组冻结

- `device.ui.observe`
- `device.ui.act`
- `device.screen.capture`
- `device.clipboard.read`
- `device.clipboard.write`
- `device.browser.control`
- `device.applescript`

规则：

- 首批之外的动作全部默认 deny。
- `group:device_automation` 独立存在，不隐含于 `group:full`。
- 高风险动作必须继续走 Hub grant，不得因为本地 ready 就旁路。

## 3) 机读契约

### 3.1 `xt.device_automation_command.v1`

```json
{
  "schema_version": "xt.device_automation_command.v1",
  "command_id": "cmd-20260310-001",
  "project_id": "project_alpha",
  "workspace_root": "/Users/andrew.xie/Documents/AX",
  "session_id": "sess-001",
  "tool_name": "device.browser.control",
  "grant_id": "grant-001",
  "risk_tier": "high",
  "args_json": "{\"action\":\"open_url\",\"url\":\"https://example.com\"}",
  "requested_at_ms": 1760000000000,
  "audit_ref": "audit-001"
}
```

### 3.2 `xt.device_automation_result.v1`

```json
{
  "schema_version": "xt.device_automation_result.v1",
  "command_id": "cmd-20260310-001",
  "runner_id": "xterminal_automation_runner",
  "executed": true,
  "deny_code": "",
  "side_effect_class": "browser_control",
  "evidence_ref": "build/reports/tam_device_action_cmd_001.v1.json",
  "completed_at_ms": 1760000001200
}
```

### 3.3 `xt.device_permission_owner_status.v1`

```json
{
  "schema_version": "xt.device_permission_owner_status.v1",
  "owner_id": "xterminal_automation_runner",
  "bundle_id": "com.xterminal.automationrunner",
  "install_state": "ready",
  "permissions": {
    "accessibility": "granted",
    "automation": "granted",
    "screen_recording": "missing",
    "full_disk_access": "missing",
    "input_monitoring": "missing"
  },
  "overall_state": "partial",
  "checked_at_ms": 1760000000100
}
```

### 3.4 `xt.device_automation_route_decision.v1`

```json
{
  "schema_version": "xt.device_automation_route_decision.v1",
  "command_id": "cmd-20260310-001",
  "project_id": "project_alpha",
  "runner_ready": true,
  "binding_ok": true,
  "same_project_scope": true,
  "grant_ok": true,
  "remote_posture_ok": true,
  "decision": "allow",
  "deny_code": "",
  "audit_ref": "audit-001"
}
```

## 4) 详细工单

### 4.1 `TAM-W1-04-D` Runner Target / Bundle / Signing Freeze

- 目标：真正把 permission owner 冻结为一个可构建目标，而不是停留在文档语义。
- 推荐路径：
  - `x-terminal/Package.swift`
  - `x-terminal/Sources/AutomationRunner/`
  - `x-terminal/XTerminalAutomationRunner.entitlements`
  - `x-terminal/Resources/AutomationRunner/`
- 实施步骤：
  1. 在 `Package.swift` 增加 `XTerminalAutomationRunner` target。
  2. 固定 bundle identity 与可执行名称。
  3. 为 runner 单独冻结 entitlements 与签名需求。
  4. 定义安装位置与 version compatibility 检查。
- DoD：
  - runner 可以独立构建。
  - 主 app 与 runner 版本不兼容时 fail-closed。
  - install path 漂移可被 doctor 检出。
- 回归样例：
  - bundle id 变更导致重复系统授权提示。
  - 主 app 升级后 runner 协议版本漂移仍继续执行。
- 证据：
  - `build/reports/tam_w1_04_d_runner_bundle_identity_evidence.v1.json`

### 4.2 `TAM-W1-04-E` Local IPC / Session Binding / Envelope Guard

- 目标：让主 app 与 runner 之间的通信具有本地强边界，而不是“谁都能调”。
- 推荐路径：
  - `x-terminal/Sources/AutomationRunner/RunnerIPCServer.swift`
  - `x-terminal/Sources/AutomationRunner/RunnerCommandDecoder.swift`
  - `x-terminal/Sources/Tools/DeviceAutomationGateway.swift`
  - `x-terminal/Sources/Project/TrustedAutomationSessionBinder.swift`
- 实施步骤：
  1. 使用 Unix domain socket 或等价本地-only IPC。
  2. 每个命令携带 `project_id/workspace_root/session_id/grant_id`。
  3. runner 端重验 `same user + same device + same project scope`。
  4. 所有 envelope 必须带 `schema_version` 与 `command_id`。
- DoD：
  - 跨 project / 过期 session / 缺 grant 的 envelope 一律 reject。
  - 本地 IPC 不暴露网络监听面。
  - 命令与结果都可写机器证据。
- 回归样例：
  - 复用旧 session_id 伪造高风险动作。
  - 更换 `project_id` 重放旧 command。
- 证据：
  - `build/reports/tam_w1_04_e_runner_ipc_guard_evidence.v1.json`

### 4.3 `TAM-W1-04-F` Device Tool Adapters + Tool Executor Bridge

- 目标：把 `device.*` 从抽象 taxonomy 变成 XT 可调用、Hub 可治理的正式工具。
- 推荐路径：
  - `x-terminal/Sources/Tools/ToolProtocol.swift`
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
  - `x-terminal/Sources/Tools/DeviceAutomationTools.swift`
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
- 实施步骤：
  1. 为首批 `device.*` 工具定义统一参数与返回契约。
  2. `ToolExecutor` 先走 binding / readiness / Hub grant，再发给 runner。
  3. 高风险工具动作强制带 `grant_id` 与 `route_decision_ref`。
  4. 非首批动作统一映射到稳定 deny code。
- DoD：
  - `group:device_automation` 在 XT 可机读显示。
  - 任何 device tool 的本地执行都要有 Hub 侧审计对应物。
  - 失败结果不退化成裸 `permission_denied`。
- 回归样例：
  - `toolProfile=full` 但 project 未绑定时仍可跑 device tool。
  - runner ready 但 Hub deny 时仍执行本地副作用。
- 证据：
  - `build/reports/tam_w1_04_f_device_tool_adapter_evidence.v1.json`

### 4.4 `TAM-W1-04-G` Permission Readiness Materializer + Doctor Wiring

- 目标：把系统权限 readiness 从 UI 文案升级为 runner 真相源快照。
- 推荐路径：
  - `x-terminal/Sources/AutomationRunner/PermissionProbe.swift`
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-terminal/Sources/UI/HubSetupWizardView.swift`
  - `x-terminal/Sources/UI/SettingsView.swift`
- 实施步骤：
  1. runner 提供权限探针输出 `xt.device_permission_owner_status.v1`。
  2. doctor 消费同一份快照，不自行拼接第二套状态机。
  2.1 若该快照被 XT doctor 挂入 `XTUnifiedDoctor`，source report contract 走 `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json`，后续 normalized export 再走 `docs/memory-new/schema/xhub_doctor_output_contract.v1.json`。
  3. 所有 `unknown` 权限状态按 fail-closed 处理。
  4. 补“去哪里开权限、为何需要、开完如何刷新”的修复卡片。
- DoD：
  - 双端 UI 不再各自推导 readiness。
  - `overall_state != ready` 时绝不显示 `active`。
  - 至少产出 machine-readable doctor export。
- 回归样例：
  - `screen_recording=missing` 仍显示 active。
  - 探针报 `unknown` 时 UI 误显示 green。
- 证据：
  - `build/reports/tam_w1_04_g_permission_materializer_evidence.v1.json`

### 4.5 `TAM-W1-04-H` Hub Grant / Audit / Dany-Code Bridge for `device.*`

- 目标：把 device automation 真正接进 Hub-first 主链。
- 推荐路径：
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_agent_grant_chain.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/paired_terminal_policy_usage.test.js`
- 实施步骤：
  1. 新增 `device.*` capability / risk mapping。
  2. grant 决策前固定检查：
     - trusted profile
     - project binding
     - permission owner readiness
     - same-project scope
     - remote posture
  3. 审计事件中带上 `runner_id`, `tool_name`, `side_effect_class`。
  4. deny code 至少冻结：
     - `device_permission_owner_missing`
     - `system_permission_missing`
     - `trusted_automation_project_not_bound`
     - `trusted_automation_workspace_mismatch`
     - `remote_posture_insufficient`
- DoD：
  - `device.*` 动作没有 Hub allow 时永远不能本地旁路执行。
  - deny-path 全部有可检索审计。
  - 与现有 `terminal.exec` / `skills.execute.runner` 口径一致。
- 回归样例：
  - 本地 runner ready 但 project 越界仍执行。
  - remote posture 不满足仍给绿灯。
- 证据：
  - `build/reports/tam_w1_04_h_hub_device_grant_bridge_evidence.v1.json`

### 4.6 `TAM-W1-04-I` Real-Device Smoke / Release Evidence / Rollback

- 目标：从“能编译”升级到“真机真权限真动作”。
- 推荐路径：
  - `x-terminal/Tests/`
  - `x-terminal/scripts/`
  - `.github/workflows/`
  - `x-terminal/scripts/ci/xt_release_gate.sh`
- 实施步骤：
  1. 增加最小真机 smoke:
     - `device.clipboard.read`
     - `device.screen.capture`（若权限齐全）
     - `device.applescript` no-op probe
  2. 证据必须区分 `contract` 与 `require-real`。
  3. 权限不足机器允许 contract 通过，但 release require-real 必须 fail。
  4. 明确 rollback: runner target / gating / capability exposure 可单独回退。
- DoD：
  - release gate 能区分“功能未开”和“权限不齐”。
  - require-real 证据缺失时不能宣告 OpenClaw-mode ready。
  - 回退后不影响普通 XT 主链。
- 回归样例：
  - synthetic 证据混入 require-real。
  - runner target 下线后 device tools 仍显示可用。
- 证据：
  - `build/reports/tam_w1_04_i_real_device_release_evidence.v1.json`

## 5) 关键路径顺序

1. `TAM-W1-04-D`
2. `TAM-W1-04-E`
3. `TAM-W1-04-G`
4. `TAM-W1-04-F`
5. `TAM-W1-04-H`
6. `TAM-W1-04-I`

原因：

- 没有稳定 runner identity，就不该接权限。
- 没有 IPC / session binding，就不该开放本地动作。
- 没有 readiness 真相源，就不该接 UI 绿牌。
- 没有 Hub grant bridge，就不该声称 OpenClaw-mode 安全可控。

## 6) 通过标准

- `device_permission_owner_bundle_identity_drift = 0`
- `device_tool_without_hub_audit = 0`
- `system_permission_missing_but_runner_executed = 0`
- `cross_project_device_scope_escape = 0`
- `require_real_device_evidence_coverage = 100%`

## 7) 与“自动运行 OpenClaw 能力”的关系

这份包完成后，只是补齐了“能安全地动设备”的执行底盘。

它不自动等于完整自动运行能力。

要真正达到“我给需求，它自己持续跑”的产品形态，还必须同时完成：

- `automation recipe / trigger / run timeline`
- directed takeover / unblock
- operator explainability
- one-click bootstrap

这些属于下一个详细包。
