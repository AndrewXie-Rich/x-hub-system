# XT-W3-30 OpenClaw-Mode Capability Gap Closure Implementation Pack v1

- owner: XT-L2（Primary）/ Hub-L5 / Security / QA / Product
- status: planned
- last_updated: 2026-03-11
- purpose: 针对当前与 OpenClaw 现成能力面的关键差距，按 `Hub-first trust + XT execution surface` 的既定架构，补齐 `managed browser runtime + external triggers + email/channel action plane + autonomy policy surface + extension/MCP bridge + node capability registry` 六条主链，让系统从“受控自动化骨架”进入“可开箱自主执行”的下一阶段。
- depends_on:
  - `x-terminal/work-orders/xt-w3-25-automation-product-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
  - `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-assistant-runtime-alignment-implementation-pack-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`

## 0) 为什么要单开这份包

当前系统已经具备以下骨架优势：

- `Hub` 仍是记忆、授权、策略、审计、kill-switch 的唯一真相源。
- `X-Terminal` 已有 session runtime、Supervisor orchestration、Hub memory UX、受控 device automation、pending grants 与 operator surfaces。
- `XT-W3-25` 和 `trusted_automation` 两组包已经把“自动化 runtime 骨架”和“本机设备执行底盘”收口到可继续推进的状态。

但和 OpenClaw 这类现成自主执行产品相比，当前公开缺口不在底层治理，而在“可直接拿来用的执行面”：

1. 浏览器执行面还停留在 `web_fetch/web_search/browser_read + open_url`，没有形成受管浏览器 runtime。
2. 自动触发语义已经存在，但实际落到 run runtime 的主链仍以 `manual` 为主。
3. Hub 侧已有多渠道与 webhook 边界，但邮件/消息执行链仍未形成 `draft -> send -> reply -> cancel -> audit` 的成品面。
4. XT 用户侧还缺少一个明确的“完全自治 / 受控自治 / 手动”策略面，用户与 Hub 都无法从单一入口限制或放开能力。
5. 现有 skills/store 更接近“file-backed skills catalog + pins”，还不是 OpenClaw 那种完整插件/MCP 扩展 runtime。
6. 设备执行目前是 `macOS-first`，离跨 `macOS / iOS / Android` 的 node family 还有明显距离。

本包的目标不是复制 OpenClaw 的 hosted 形态，也不是扩张对外 release claim。

本包的目标是：在不破坏 `Hub-first` 架构的前提下，把最关键的执行面缺口做成真正可交付、可治理、可降级、可回滚的下一阶段主链。

补充说明：

- `XT-W3-30` 负责“执行面能力差距”。
- `XT-W3-32` 负责“Supervisor 控制平面差距”。

没有 `XT-W3-32`，即使 `XT-W3-30` 的 browser / trigger / connector / extension execution surfaces 都到位，系统仍只会停留在“能被调用”，而不是“能被 Supervisor 持续编排”。

## 1) 当前已验证基线

下列事实应视为当前起点，而不是待讨论假设：

- 浏览器类能力当前主要是：
  - `web_fetch`
  - `web_search`
  - `browser_read`
  - `device.browser.control`
- `device.browser.control` 当前只形成 `open_url` 级能力，还不是受管浏览器 session/runtime。
- 自动化 trigger contract 已覆盖 `schedule|webhook|connector_event|manual`，但当前实际生成 run request 的主链仍以 `manual` 为主。
- Hub Integrations 当前偏向 `Mail (counts only)`、`Messages (counts only)`、`Slack (best-effort)`，不能把这些状态面误当成真实执行面。
- skills 侧当前更接近 `catalog + search + pins + resolved view`，尚未形成完整的 `plugin install / runtime bridge / revocation / MCP adapter` 产品面。
- `trusted_automation` 已经具备 project binding、tool group、permission readiness、Hub grant bridge 的收口方向，但仍主要服务 `macOS-first` 的本地执行面。

## 2) 北极星目标

### 2.1 要达成的目标

把系统推进到下面这条最小事实链：

1. 用户可在 XT 侧为单个项目显式选择自治档位，而不是只能靠隐式配置。
2. 在 `trusted / governed` 条件满足时，系统可使用受管浏览器 runtime 完成真实网页动作，而不是只读网页文本。
3. 外部触发可直接驱动 `recipe -> run -> timeline -> delivery` 主链，而不是必须人工再次输入“继续”。
4. 邮件/消息 side effect 具备正式 action plane，可审计、可取消、可降级、可回滚。
5. 扩展能力可通过 Hub 审核后的 package / plugin / MCP bridge 接入，而不是把能力散落在未治理脚本里。
6. 系统对“OpenClaw-mode ready”的定义是可机读、可 require-real 验证、可局部回退的，而不是口头判断。

### 2.2 明确不做

- 不在 XT 内形成第二套 model/provider auth/control plane。
- 不让 XT 直接持有 connector secrets、邮件密钥或浏览器会话主权。
- 不把 iOS/Android node 在未有真机证据前包装成 ready。
- 不在 P0 做 Canvas / Voice Wake / Talk Mode / 全渠道复制。
- 不以“看起来能跑”代替 `require-real` 证据。

## 3) 硬边界

- `X-Hub` 继续是唯一信任锚点；所有高风险 capability 仍以 Hub grant / policy / audit 为最终裁决。
- 默认 memory 继续优先走 Hub；高风险 device/browser/connector 动作必须继续走 fresh memory recheck。
- “完全自治”必须是：
  - project-scoped
  - TTL-bound
  - user-explicit
  - Hub-overridable
  - kill-switch capable
- XT 不能私自新增外部副作用直连路径；浏览器、邮件、connector、插件 side effect 都必须带上 route decision / grant / audit ref。
- 不允许把 counts-only、best-effort 或 preview surface 宣称成 action-capable surface。

## 4) 分层推进

### 4.1 P0：先补最短板，达成桌面级 OpenClaw-mode

- `XT-W3-30-A` Managed Browser Runtime
- `XT-W3-30-B` External Trigger -> Recipe Run Closure
- `XT-W3-30-C` Email / Channel Action Plane
- `XT-W3-30-D` Full-Autonomy Policy Surface + Kill Switch

### 4.2 P1：补扩展面与桌面自治稳定性

- `XT-W3-30-E` Managed Extension / Plugin / MCP Bridge
- `XT-W3-30-G` Require-Real Parity Graduation Harness

### 4.3 P2：补跨设备 node family

- `XT-W3-30-F` Node Capability Registry + macOS/iOS/Android Expansion

## 5) 机读契约

### 5.1 `xt.browser_runtime_session.v1`

```json
{
  "schema_version": "xt.browser_runtime_session.v1",
  "session_id": "brs-20260311-001",
  "project_id": "project_alpha",
  "profile_id": "managed_profile_project_alpha",
  "browser_engine": "chromium",
  "ownership": "hub_governed_xt_runtime",
  "action_mode": "read_only|interactive|interactive_with_upload",
  "open_tabs": 2,
  "snapshot_ref": "build/reports/browser_snapshot_001.v1.json",
  "grant_policy_ref": "policy://browser-runtime/project-alpha",
  "updated_at_ms": 1760000000000
}
```

### 5.2 `xt.external_trigger_ingress_envelope.v1`

```json
{
  "schema_version": "xt.external_trigger_ingress_envelope.v1",
  "trigger_id": "webhook/github_pr/001",
  "trigger_type": "schedule|webhook|connector_event|manual",
  "source": "github|slack|telegram|email|hub|timer",
  "connector_id": "github",
  "project_id": "project_alpha",
  "payload_ref": "local://trigger-payloads/20260311-001.json",
  "dedupe_key": "sha256:...",
  "requires_grant": true,
  "cooldown_sec": 120,
  "audit_ref": "audit-001"
}
```

### 5.3 `xt.connector_action_job.v1`

```json
{
  "schema_version": "xt.connector_action_job.v1",
  "job_id": "caj-20260311-001",
  "action_class": "email.send|email.reply|channel.send|channel.reply",
  "connector": "email",
  "target_ref": "email://thread/123",
  "draft_ref": "local://drafts/email_123.md",
  "grant_id": "grant-001",
  "state": "queued|sending|sent|canceled|failed",
  "undo_window_sec": 15,
  "audit_ref": "audit-002"
}
```

### 5.4 `xt.autonomy_runtime_policy.v1`

```json
{
  "schema_version": "xt.autonomy_runtime_policy.v1",
  "project_id": "project_alpha",
  "mode": "manual|guided|trusted_openclaw_mode",
  "allow_device_tools": true,
  "allow_browser_runtime": true,
  "allow_connector_actions": false,
  "allow_extensions": false,
  "ttl_sec": 3600,
  "hub_override_mode": "none|clamp_guided|clamp_manual|kill_switch",
  "updated_at_ms": 1760000000000
}
```

### 5.5 `xt.extension_runtime_manifest.v1`

```json
{
  "schema_version": "xt.extension_runtime_manifest.v1",
  "extension_id": "browser.forms.helper",
  "kind": "skill|plugin|mcp_bridge",
  "package_ref": "hub://skills/packages/sha256-001",
  "capabilities_required": ["device.browser.control", "connectors.email"],
  "sandbox_class": "strict|governed|trusted_device_only",
  "signature_ref": "sig://sha256-001",
  "status": "staged|enabled|revoked|quarantined"
}
```

### 5.6 `xt.node_capability_registry.v1`

```json
{
  "schema_version": "xt.node_capability_registry.v1",
  "node_id": "node-macos-main",
  "platform": "macos|ios|android",
  "connection_mode": "local_pair|remote_pair",
  "capabilities": ["device.ui.observe", "device.screen.capture"],
  "permission_posture": "ready|partial|blocked",
  "grant_surface_ref": "policy://node/macos-main",
  "ready": true
}
```

## 6) Gate / KPI

### 6.1 Gate

- `XT-OC-G0`: 上述 6 类机读契约冻结完成。
- `XT-OC-G1`: 受管浏览器 runtime 可运行，session/profile/snapshot/audit 全链路成立。
- `XT-OC-G2`: `schedule/webhook/connector_event` 至少两类真实接入 run runtime，不再只靠 manual。
- `XT-OC-G3`: 邮件/消息 action plane 具备真实 side effect、outbox/undo/audit 主链。
- `XT-OC-G4`: XT 与 Hub 双侧自治策略面成立，kill-switch 与 clamp 生效。
- `XT-OC-G5`: 扩展 / plugin / MCP bridge 接入不破坏 Hub 主权和 revocation。
- `XT-OC-G6`: 桌面级 OpenClaw-mode ready 具备 require-real 样本，可发布内部 GO/NO-GO 决策。
- `XT-OC-G7`: node family 扩展完成真实设备证据，不再停留在文档。

### 6.2 KPI

- `managed_browser_session_reuse_success_rate >= 0.98`
- `trigger_source_manual_only_ratio <= 0.20`
- `connector_action_without_audit = 0`
- `autonomy_mode_drift = 0`
- `unsigned_extension_execution = 0`
- `desktop_openclaw_mode_require_real_coverage = 100%`
- `mobile_node_public_claim_without_require_real = 0`

## 7) 详细工单

### 7.1 `XT-W3-30` OpenClaw-Mode Capability Gap Closure

- 目标：形成一份统一父包，约束浏览器、触发器、connector、自治策略、扩展、node family 六条链路的推进顺序与毕业标准。
- 交付物：`build/reports/xt_w3_30_openclaw_mode_gap_closure_evidence.v1.json`
- DoD:
  - P0/P1/P2 边界冻结，不再把不同成熟度能力混成一个“已具备”口径。
  - 内部 Ready 定义改为机读 gate + require-real evidence。
  - 所有新增能力均有回退路径，不挟持 XT 主链。

### 7.2 `XT-W3-30-A` Managed Browser Runtime + Profile Governance

- 优先级：`P0`
- 主责：XT-L2；协同：Hub-L5 / Security / QA
- 目标：把当前“抓网页 + 打开默认浏览器”升级为受管浏览器 runtime。
- 推荐代码落点：
  - `x-terminal/Sources/Tools/BrowserRuntime/`
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
  - `x-terminal/Sources/Project/AXProjectStore.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- 实施步骤：
  1. 冻结 `xt.browser_runtime_session.v1` 与 managed profile 命名规则。
  2. 引入受管浏览器 profile，默认不污染用户主浏览器 profile。
  3. 首批动作冻结为：
     - `open`
     - `navigate`
     - `snapshot`
     - `extract`
     - `click`
     - `type`
     - `upload`
  4. 所有浏览器 side effect 写入 snapshot / audit / action ledger。
  5. 与 Hub grant / fresh memory recheck / deny-code 主链接通。
- DoD：
  - `browser runtime` 与 `default browser` 明确区分。
  - 不支持的动作返回稳定 deny code，而不是静默降级。
  - 上传/表单/点击等副作用动作全部可审计、可回溯。
- 回归样例：
  - profile 污染用户日常浏览器状态 -> 失败
  - 高风险提交动作未触发 fresh memory recheck -> 失败
  - 浏览器驱动漂移后仍假成功 -> 失败
- 证据：
  - `build/reports/xt_w3_30_a_browser_runtime_evidence.v1.json`

### 7.3 `XT-W3-30-B` External Trigger -> Recipe Run Closure

- 优先级：`P0`
- 主责：XT-L2；协同：Hub-L5 / QA
- 目标：把 `schedule/webhook/connector_event` 从 contract 语义推进到真实 run runtime。
- 推荐代码落点：
  - `x-terminal/Sources/Supervisor/XTAutomationRunCoordinator.swift`
  - `x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/pairing_http.js`
- 实施步骤：
  1. 冻结 `xt.external_trigger_ingress_envelope.v1`。
  2. 将 `schedule/webhook/connector_event/manual` 统一编译进 `XTAutomationRunRequest`。
  3. 接入 dedupe、cooldown、retry-after、manual cancel、restart recovery。
  4. 将 connector ingress 授权结果映射为稳定 trigger route decision。
  5. 对 grant pending / policy clamp / missing posture 做 fail-closed 或 downgrade。
- DoD：
  - 至少两类非 manual trigger 可真实驱动 run。
  - re-entry/restart 后 run identity 不漂移。
  - trigger ingress 不绕过 Hub allowlist / replay guard / scope gate。
- 回归样例：
  - webhook 重放造成双 run -> 失败
  - `connector_event` 进入 run 但无 project scope -> 失败
  - grant pending 仍推进外部副作用 -> 失败
- 证据：
  - `build/reports/xt_w3_30_b_external_trigger_runtime_evidence.v1.json`

### 7.4 `XT-W3-30-C` Email / Channel Action Plane

- 优先级：`P0`
- 主责：Hub-L5；协同：XT-L2 / Security / QA
- 目标：把当前 counts-only / best-effort 集成升级为正式 connector action plane。
- 推荐代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/UI/`
- 实施步骤：
  1. 冻结 `xt.connector_action_job.v1`。
  2. 首批 action class 收口：
     - `email.send`
     - `email.reply`
     - `channel.send`
     - `channel.reply`
  3. 引入 draft -> approval -> outbox -> undo -> sent/failed 的稳定状态机。
  4. 将 `Mail (counts only)`、`Messages (counts only)`、`Slack (best-effort)` 明确与 action-capable connector 区分显示。
  5. 全部 secrets、connector auth、send job audit 继续归 Hub。
- DoD：
  - 发送面和计数面不会混淆。
  - 外部 side effect 有 outbox、undo、audit、deny-path。
  - XT/Supervisor 可看到 pending/sent/failed/canceled 状态。
- 回归样例：
  - counts-only 通道被误显示为可发送 -> 失败
  - 已发送 job 无 audit ref -> 失败
  - send failed 后 UI 仍显示 sent -> 失败
- 证据：
  - `build/reports/xt_w3_30_c_connector_action_plane_evidence.v1.json`

### 7.5 `XT-W3-30-D` Full-Autonomy Policy Surface + Kill Switch

- 优先级：`P0`
- 主责：XT-L2 / Hub-L5；协同：Security
- 目标：让“像 OpenClaw 一样更自主”成为显式、可限制、可回收的策略面，而不是隐式工程配置。
- 推荐代码落点：
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Sources/UI/SettingsView.swift`
  - `x-terminal/Sources/Project/AXProjectStore.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
- 实施步骤：
  1. 冻结 `xt.autonomy_runtime_policy.v1`。
  2. 提供 XT 侧 project-scoped 选择：
     - `manual`
     - `guided`
     - `trusted_openclaw_mode`
  3. 提供 Hub 侧 override：
     - `none`
     - `clamp_guided`
     - `clamp_manual`
     - `kill_switch`
  4. 将 `device/browser/connector/extension` 四类面统一挂到自治策略面。
  5. 所有模式切换必须写 audit，并显示 TTL/剩余时间/当前被 Hub clamp 状态。
- DoD：
  - 用户能按项目明确选择自治程度。
  - Hub 能单侧收紧权限，不依赖 XT 自觉遵守。
  - mode 漂移、跨项目继承、过期后未回收全部为 fail case。
- 回归样例：
  - `trusted_openclaw_mode` 自动跨项目继承 -> 失败
  - kill switch 下浏览器/device 仍可执行 -> 失败
  - TTL 到期但 UI 仍显示 trusted -> 失败
- 证据：
  - `build/reports/xt_w3_30_d_autonomy_policy_surface_evidence.v1.json`

### 7.6 `XT-W3-30-E` Managed Extension / Plugin / MCP Bridge

- 优先级：`P1`
- 主责：Hub-L5；协同：XT-L2 / Security / QA
- 目标：在不复制 OpenClaw 全生态的前提下，先把“可治理扩展面”做成正式产品边界。
- 推荐代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
  - `x-terminal/Sources/Project/AXSkillsLibrary.swift`
  - `x-terminal/Sources/AppModel.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
- 实施步骤：
  1. 冻结 `xt.extension_runtime_manifest.v1`。
  2. 首批支持三类扩展：
     - managed skill package
     - signed plugin package
     - MCP bridge descriptor
  3. 将 capability allowlist、sandbox class、signature、revocation、quarantine 统一接入 Hub。
  4. XT 侧只消费 resolved extension/runtime state，不持有扩展主权。
  5. 未签名、超 scope、被撤销扩展一律 fail-closed。
- DoD：
  - 扩展状态可见、可撤销、可隔离。
  - MCP bridge 不得绕过 Hub policy / memory / audit。
  - “装上即运行”必须改成“通过 policy 后 staged/enabled”。
- 回归样例：
  - 被 revoke 的扩展仍继续执行 -> 失败
  - 未签名扩展通过 XT 本地旁路启用 -> 失败
  - MCP 变更未进审计 -> 失败
- 证据：
  - `build/reports/xt_w3_30_e_extension_bridge_evidence.v1.json`

### 7.7 `XT-W3-30-F` Node Capability Registry + Device Family Expansion

- 优先级：`P2`
- 主责：Hub-L5 / XT-L2；协同：QA / Product
- 目标：从 `macOS-first` 扩展到统一 node registry，但不提前做虚假成熟度宣称。
- 推荐代码落点：
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Tools/DeviceAutomationTools.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- 实施步骤：
  1. 冻结 `xt.node_capability_registry.v1`。
  2. 先将 macOS node registry 做成正式真相源。
  3. 为 iOS/Android 预留 capability + permission posture + action taxonomy。
  4. 建立 platform-specific deny code，不得返回模糊 `not_supported`。
  5. 所有公开平台状态必须区分：
     - `implemented`
     - `paired_not_ready`
     - `planned_only`
- DoD：
  - 不同平台 readiness 状态统一可读。
  - 没有真机 require-real 证据的平台不能被标成 ready。
  - platform mismatch / unavailable capability 有稳定拒绝码。
- 回归样例：
  - Android capability 仅文档存在却显示 ready -> 失败
  - iOS node 未配对仍可进入 action flow -> 失败
- 证据：
  - `build/reports/xt_w3_30_f_node_registry_evidence.v1.json`

### 7.8 `XT-W3-30-G` Require-Real Parity Graduation Harness

- 优先级：`P1`
- 主责：QA；协同：XT-L2 / Hub-L5 / Product
- 目标：把“离 OpenClaw 还有多远”从主观讨论变成 require-real 证据链。
- 样本要求：
  - 受管浏览器任务
  - webhook 触发自动 run
  - schedule 触发自动 run
  - 邮件/通道 action
  - trusted_openclaw_mode 下的自恢复
  - 扩展/MCP bridge 参与任务
- DoD：
  - 所有样本区分 `contract pass` 与 `require-real pass`。
  - 不允许 synthetic 样本冒充 parity evidence。
  - 只能对外宣称“已通过内部 require-real 的能力”，不得写成笼统“已达到 OpenClaw 全能力”。
- 回归样例：
  - require-real 样本缺 1 类仍宣告 ready -> 失败
  - 用 counts-only 代替真实 connector action -> 失败
- 证据：
  - `build/reports/xt_w3_30_g_parity_graduation_harness_evidence.v1.json`

## 8) 关键路径顺序

1. `XT-W3-30-D`
2. `XT-W3-30-A`
3. `XT-W3-30-B`
4. `XT-W3-30-C`
5. `XT-W3-30-E`
6. `XT-W3-30-G`
7. `XT-W3-30-F`

原因：

- 没有显式自治策略面，就不该扩张“完全自治”能力口径。
- 没有受管浏览器 runtime，就仍然和 OpenClaw 差一个核心执行面。
- 没有非 manual trigger closure，就还不算真正自主运行。
- 没有正式 connector action plane，就还不算具备“自己发邮件/自己发消息”的成品能力。
- 扩展/MCP bridge 必须排在桌面自治主链稳定之后，避免把未治理能力过早引入。
- node family 是下一阶段扩展，不应阻塞桌面级 OpenClaw-mode ready 的 first graduation。

## 9) 什么叫“桌面级 OpenClaw-mode ready”

只有同时满足下列事实，才允许在内部把桌面级能力标成 ready：

1. `trusted_openclaw_mode` 已形成 XT 选择面 + Hub clamp/kill-switch。
2. 受管浏览器 runtime 已具备真实动作与证据。
3. 至少两类外部 trigger 已能真实驱动 run。
4. 邮件/消息 action plane 已具备真实 side effect。
5. 全部高风险动作继续经过 Hub grant / audit / memory safety chain。
6. `XT-OC-G0..G6` 已通过 require-real。

注意：

- 这不等于“全平台 OpenClaw parity”。
- 这不等于 `iOS/Android node` ready。
- 这不等于 `Canvas / Voice Wake / Talk Mode` ready。

## 10) 预期结果

本包完成后，系统的口径会从：

- “治理和记忆更强，但执行面还在补”

推进到：

- “桌面级自主执行面已经成型，且仍保持 Hub-first 的安全和审计主权”

这才是下一阶段真正有价值的差异化：

- 比通用 agent terminal 更可治理
- 比纯架构文档更可直接使用
- 比“只会自动继续”更接近真实自主执行产品
