# X-Hub / X-Terminal 无感首配、切网续连与 Doctor/Self-Heal 实施包

- version: v1.0
- updatedAt: 2026-03-29
- owner: Hub Runtime / XT Pairing / XT Doctor / Supervisor / QA
- status: active
- scope: 首配、配对后稳定连接、切网换环境无感切换、doctor 连续巡检、自愈闭环、release 证据
- parent:
  - `X_MEMORY.md`
  - `docs/WORKING_INDEX.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`
  - `docs/memory-new/xhub-remote-pairing-autoreconnect-security-work-orders-v1.md`
  - `docs/memory-new/xhub-external-remote-access-official-version-memo-v1.md`
  - `docs/memory-new/xhub-security-innovation-work-orders-v1.md`
  - `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json`
  - `docs/memory-new/schema/xhub_doctor_output_contract.v1.json`
  - `x-terminal/work-orders/xt-assistant-runtime-alignment-implementation-pack-v1.md`

## 0) 使用方式（先看）

- 这是当前“XT 与 Hub 首配、异网续连、doctor、自愈”这条线的单文件执行入口。
- 任何新 AI 第一次接手这条线时，先读本文件，再读文末列出的代码入口与命令；不要先翻长聊天记录。
- 如果用户只说“继续”“按优先级推”“把这条线补完”，默认按本文件 `P0 -> P1 -> P2` 顺序推进。
- 除非用户明确改边界，否则不要重新讨论本文件第 1 节里已经冻结的决策。
- 每个工单必须同时交付：
  - 代码
  - 对应测试
  - doctor / export / incident 输出
  - source-run 或 require-real 证据

### 0.1 冷启动阅读顺序

1. 本文件第 1 节到第 5 节
2. `docs/memory-new/xhub-remote-pairing-autoreconnect-security-work-orders-v1.md`
3. `docs/memory-new/xhub-external-remote-access-official-version-memo-v1.md`
4. `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json`
5. `docs/memory-new/schema/xhub_doctor_output_contract.v1.json`
6. 第 2 节列出的代码入口
7. 第 8 节列出的命令与测试

### 0.2 本文件解决的核心问题

- 为什么 XT 首配必须回同网，但离开 Wi-Fi 后又必须继续可用。
- 怎么让切 Wi-Fi、切热点、切公司网、睡眠唤醒、Hub 重启后尽量无感续连。
- doctor 怎么从“静态诊断页”升级成“连续巡检 + repair policy + 回验闭环”。
- 哪些问题允许系统自动修，哪些问题必须 fail-closed 并导向人工修复。

## 1) 已冻结边界（不要重开）

### 1.1 首配边界冻结

- 首次配对继续只允许在同一 Wi-Fi / 同一局域网内完成。
- Hub owner 本机批准继续是首配必要条件，不允许异网直接建立首信任。
- Hub 继续是 pairing / device trust / grant / paid model / policy 的唯一权威。

### 1.2 远端入口边界冻结

- 正式异网入口只允许稳定命名入口，不把 raw IP 当正式长期入口。
- 邀请链接、QR、正式接入包继续优先承载 `hub_host + invite_token + hub_instance_id`。
- raw IP 只允许作为 repair / fallback / backward-compat 诊断路径，不得作为 release 推荐路径。

### 1.3 自愈边界冻结

- route 类问题允许自动探测、自动切换、自动重试、自动回验。
- identity / pairing / approval / policy / grant 类问题不允许自动绕过，只能 fail-closed。
- file IPC 或本地 fallback 不得伪装成 off-LAN success。
- doctor 任何时候都要先输出真相，再输出 repair；不能为了“看起来恢复”而偷改状态。

### 1.4 成功定义冻结

- `pairing ok` 不等于 `remote ready`。
- `same-LAN first pair complete + cached reconnect smoke pass + stable remote route healthy` 才能进入产品级异网 ready。
- `Hub reachable` 不等于 `runtime ready`。
- `runtime ready` 不等于 `policy ready`。

## 2) 当前已存在的基础能力与代码入口

本节是给第一次接手的 AI 用的“快速定向表”。先读这些文件，不要盲目全仓搜索。

### 2.1 XT 配对 / 路由 / 邀请

- `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - XT 当前 pairing、bootstrap、远端连接、reason code 提炼的核心入口。
- `x-terminal/Sources/Hub/XTHubRemoteAccessHostClassification.swift`
  - 现有 `missing / lan_only / raw_ip / stable_named` 远端入口分类逻辑。
- `x-terminal/Sources/Hub/XTFreshPairReconnectSmokeSnapshot.swift`
  - 首配后复连 smoke 的结构化快照。
- `x-terminal/Sources/UI/Components/HubInviteStatusCard.swift`
  - 邀请链接 / invite token 的用户侧状态表达。
- `x-terminal/Sources/UI/HubSetupWizardView.swift`
  - 首配、一键连接、repair copy 的主要用户流程。
- `x-terminal/Sources/AppModel.swift`
  - 首配错误上下文、repair 跳转、XT 全局连接状态汇总。

### 2.2 XT doctor / troubleshoot / supervisor

- `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - XT 原生 doctor source truth，负责 `hub_reachability`、`pairing_validity` 等 section 汇总。
- `x-terminal/Sources/UI/XHubDoctorOutput.swift`
  - XT doctor 统一归一化输出 contract。
- `x-terminal/Sources/UI/Components/TroubleshootPanel.swift`
  - failure code 到修复目标的映射。
- `x-terminal/Sources/XTDeepLinkActionExecutor.swift`
  - repair destination 的实际跳转执行。
- `x-terminal/Sources/Supervisor/SupervisorXTReadyIncidentPresentation.swift`
  - doctor / reconnect smoke / runtime diagnosis 进 Supervisor incident 的呈现层。

### 2.3 Hub pairing / identity / invite / runtime recovery

- `x-hub/grpc-server/hub_grpc_server/src/pairing_http.js`
  - pairing HTTP 面、invite token、same-LAN first pair、preauth 防重放。
- `x-hub/grpc-server/hub_grpc_server/src/hub_identity.js`
  - Hub `internet_host_hint` 选择逻辑。
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubSecureRemoteSetupPack.swift`
  - 正式远端接入包与 bootstrap command。
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - Hub 侧 pairing repair、stale client、设备列表与 repair surface。
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/XHubDoctorOutputHub.swift`
  - Hub runtime doctor 归一化输出。
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/XHubLocalServiceDiagnostics.swift`
  - Hub 本地服务 primary issue 归因。
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/XHubLocalServiceRecoveryGuidance.swift`
  - Hub runtime recovery guidance。
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/LocalRuntimeRepairSurface.swift`
  - Hub repair surface 汇总呈现层。

### 2.4 现有测试与脚本入口

- `x-terminal/Tests/HubPairingCoordinatorTests.swift`
- `x-terminal/Tests/XTUnifiedDoctorReportTests.swift`
- `x-terminal/Tests/XHubDoctorOutputTests.swift`
- `x-terminal/Tests/SupervisorIncidentExportTests.swift`
- `x-hub/grpc-server/hub_grpc_server/src/pairing_http_preauth_replay.test.js`
- `scripts/run_xhub_doctor_from_source.command`
- `scripts/ci/xhub_doctor_source_gate.sh`
- `x-terminal/tools/build_xterminal_app.command`
- `x-hub/tools/build_hub_app.command`

## 3) 当前距离目标还差什么

### 3.1 连接层缺口

- 还没有一个版本化的 `paired route set`，XT 仍偏向单一路由缓存心智。
- 还没有正式的 route scorer / cooldown / breaker，切网后更像“失败了再试”，不是主动 handoff。
- 还没有完整的网络变化触发器链路，无法在 Wi-Fi 切换、睡眠唤醒、默认路由变化后提前预热新 route。
- 首配完成还缺结构化 `completion proof`，无法严格区分：
  - 只完成同网首配
  - 完成首配但异网未准备好
  - 正式异网 ready

### 3.2 Doctor / Self-Heal 缺口

- doctor 已有强结构化输出，但更偏“生成快照”，还不是持续巡检内核。
- route repair、runtime repair、identity repair 还没有统一 repair policy engine。
- 自动动作与手动动作缺少统一 repair ledger，难以做效果回溯和熔断。
- failure code 已不少，但 reason family 还没有彻底收束到统一的自动化执行语义。

### 3.3 Release / QA 缺口

- 缺少完整 require-real 场景矩阵来证明：
  - 首配后离开 Wi-Fi 可以继续工作
  - 切不同网络环境能自动 handoff
  - stale profile / invalid invite / hub restart 不会进入无穷重试
- 缺少一组固定 KPI 来定义“丝滑无感”的产品线，而不只是“功能存在”。

## 4) 下一位 AI 的最小接手包

如果新 AI 时间只有 15 到 30 分钟，先完成下面这组阅读和判断：

1. 读本文件第 1 节到第 5 节，确认边界与优先级。
2. 读 `HubPairingCoordinator.swift`，判断当前 route / bootstrap / reconnect 的真实主链。
3. 读 `XTUnifiedDoctor.swift` 与 `XHubDoctorOutput.swift`，确认 doctor contract 已有哪些字段可复用。
4. 读 `pairing_http.js` 与 `hub_identity.js`，确认 Hub 当前对 `same-LAN first pair`、`invite token`、`internet_host_hint` 的收口。
5. 读 `HubSecureRemoteSetupPack.swift` 与 `HubInviteStatusCard.swift`，确认正式接入包和 XT 邀请 UX 的现有主路径。
6. 用本文件第 8 节命令跑一遍 build / doctor / focused tests，先拿到真实基线。

新 AI 不要一开始就做的事：

- 不要先讨论是否取消 same-LAN 首配。
- 不要先讨论把 raw IP 变成正式远端入口。
- 不要先做新 UI 皮肤，而忽略 route contract 和 repair contract。
- 不要先加自动修复按钮，而没有 verify / rollback / breaker。

## 5) 分阶段实施清单

### 5.1 P0 主链阻断项

### `SHR-W1-01` 版本化 `paired_route_set` 契约与迁移

- 目标：
  - 让 XT 拥有一份结构化、版本化、可回验的已配对路由集合，而不是只有松散缓存字段。
- 必做：
  - 新增 `paired_route_set` 持久化模型，至少包含：
    - `hub_instance_id`
    - `pairing_profile_epoch`
    - `route_pack_version`
    - `lan_route`
    - `stable_remote_route`
    - `last_known_good_route`
    - `last_success_at_ms`
    - `last_failure_code`
  - 从现有 `internetHost` / 邀请链接 / pairing 结果迁移。
  - 迁移必须 fail-safe：
    - raw IP 不能自动被标成正式 remote ready
    - 旧缓存缺信息时只能降级成 `local_ready` 或 `unknown`
- 代码入口：
  - `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/UI/HubSetupWizardView.swift`
  - `x-terminal/Sources/UI/SettingsView.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/pairing_http.js`
- 测试：
  - `x-terminal/Tests/HubPairingCoordinatorTests.swift`
  - `x-terminal/Tests/HubInviteStatusPlannerTests.swift`
  - `x-terminal/Tests/XHubDoctorOutputTests.swift`
- 证据产物：
  - `xt_paired_route_set.v1.json`
- 完成定义：
  - 旧用户升级后不会被误报为 off-LAN ready。
  - 新邀请接入后，XT 能稳定拿到 `stable_remote_route + hub_instance_id`。

### `SHR-W1-02` route scorer / cooldown / handoff 状态机

- 目标：
  - 把“失败后重试”升级成显式 route handoff 状态机。
- 必做：
  - 固定 route 优先级：
    1. `lan_direct`
    2. `stable_named_remote`
    3. `managed_tunnel_fallback`
  - raw IP 只允许 repair fallback，不进入正式长期主路径。
  - 为每条 route 加：
    - `health_score`
    - `cooldown_until`
    - `recent_success_count`
    - `recent_failure_count`
  - 输出 machine-readable：
    - `selected_route`
    - `candidates_tried`
    - `handoff_reason`
    - `cooldown_applied`
- 代码入口：
  - `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - 推荐新增 `x-terminal/Sources/Hub/HubConnectivityOrchestrator.swift`
  - `x-terminal/Sources/UI/XHubDoctorOutput.swift`
- 测试：
  - `x-terminal/Tests/HubPairingCoordinatorTests.swift`
  - `x-terminal/Tests/XHubDoctorOutputTests.swift`
  - `x-terminal/Tests/SupervisorIncidentExportTests.swift`
- 证据产物：
  - `xt_route_handoff_evidence.v1.json`
- 完成定义：
  - 关闭 LAN 后，XT 可以在受控时间窗内自动切到稳定远端入口。
  - 连续失败时会进入 cooldown，而不是疯狂抖动。

### `SHR-W1-03` 网络变化触发器与无感预切换

- 目标：
  - 在用户发起请求前完成 route 预切换，减少“断了再修”的体感。
- 必做：
  - 增加以下触发器：
    - Wi-Fi / 默认路由变化
    - 睡眠唤醒
    - App 前后台切换
    - Hub 心跳恢复 / 消失
  - 每次触发执行轻量 probe：
    - `lan probe`
    - `stable remote probe`
    - 必要时 `tunnel probe`
  - 探测结果只改变 active route，不得改变 pairing trust。
- 代码入口：
  - 推荐新增 `x-terminal/Sources/Hub/HubConnectivityMonitor.swift`
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
- 测试：
  - 新增 `HubConnectivityMonitor` 单测与 route handoff 集成测试。
- 证据产物：
  - `xt_network_handoff_probe_log.v1.json`
- 完成定义：
  - 切 Wi-Fi、切热点、睡眠唤醒后，XT 能先更新 route，再继续会话。

### `SHR-W1-04` 首配完成证明与 shadow reconnect smoke

- 目标：
  - 让系统能严格区分“只完成首配”和“正式异网 ready”。
- 必做：
  - 新增 `first_pair_completion_proof`，至少包含：
    - `same_lan_verified`
    - `owner_local_approval_verified`
    - `pairing_material_issued`
    - `cached_reconnect_smoke_passed`
    - `stable_remote_route_present`
    - `remote_shadow_smoke_passed`
  - 首配成功后必须自动跑一轮 cached reconnect smoke。
  - 若存在稳定远端入口，低优先级再跑一轮 remote shadow smoke。
  - doctor / incident / troubleshoot 必须显示：
    - `local_ready`
    - `remote_ready`
    - `remote_degraded`
    - `remote_blocked`
- 代码入口：
  - `x-terminal/Sources/Hub/XTFreshPairReconnectSmokeSnapshot.swift`
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-terminal/Sources/UI/XHubDoctorOutput.swift`
  - `x-terminal/Sources/Supervisor/SupervisorXTReadyIncidentPresentation.swift`
- 测试：
  - `x-terminal/Tests/XTUnifiedDoctorReportTests.swift`
  - `x-terminal/Tests/XHubDoctorOutputTests.swift`
  - `x-terminal/Tests/SupervisorIncidentExportTests.swift`
- 证据产物：
  - `xt_first_pair_completion_proof.v1.json`
- 完成定义：
  - 只完成同网首配但 remote shadow smoke 未过时，系统必须保持 `local_ready`，不得冒绿成 `remote_ready`。

### `SHR-W1-05` `pairing_profile_epoch` / `route_pack_version` / stale repair 刷新

- 目标：
  - 解决设备撤销、证书轮换、邀请刷新后持续旧档案重试的问题。
- 必做：
  - Hub 侧在以下场景提升 `pairing_profile_epoch` 或 `route_pack_version`：
    - 设备重新批准
    - invite token 轮换
    - 正式远端 host 变化
    - 证书或 profile 刷新
  - XT 侧发现 epoch/version 落后时：
    - 直接进入 repair path
    - 停止无意义自动重试
    - 引导刷新邀请或重拉 route pack
  - 新增 reason code：
    - `pairing_profile_epoch_stale`
    - `route_pack_outdated`
    - `hub_instance_mismatch`
- 代码入口：
  - `x-hub/grpc-server/hub_grpc_server/src/pairing_http.js`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubSecureRemoteSetupPack.swift`
  - `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - `x-terminal/Sources/UI/Components/TroubleshootPanel.swift`
- 测试：
  - `x-hub/grpc-server/hub_grpc_server/src/pairing_http_preauth_replay.test.js`
  - `x-terminal/Tests/HubPairingCoordinatorTests.swift`
  - `x-terminal/Tests/FirstPairTroubleshootRoutingTests.swift`
- 证据产物：
  - `xt_stale_profile_repair_evidence.v1.json`
- 完成定义：
  - `invite_token_invalid`、`unauthenticated`、`certificate_required` 这类 stale 相关错误不再进入死循环。

### 5.2 P1 Doctor / 自愈闭环

### `SHR-W2-06` reason family 与 repair policy contract 统一

- 目标：
  - 让 XT / Hub / Supervisor / CLI 不只是共享 failure code，还共享 repair 语义。
- 必做：
  - 为 doctor 输出新增统一字段：
    - `reason_family`
    - `repair_kind`
    - `auto_executable`
    - `verify_required`
    - `breaker_scope`
  - 最低 family 收束为：
    - `identity`
    - `route`
    - `runtime`
    - `policy`
  - XT 与 Hub 的 doctor output 同步接入。
- 代码入口：
  - `x-terminal/Sources/UI/XHubDoctorOutput.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/XHubDoctorOutputHub.swift`
- 完成定义：
  - 所有主要 blocking finding 都能被明确分到一个 family，并带出统一 repair 语义。

### `SHR-W2-07` route repair executor + breaker + cooldown

- 目标：
  - 把 route 类自愈变成正式执行器，而不是散在 UI 的重试按钮。
- 必做：
  - 自动动作只覆盖 route 类：
    - 切备用 route
    - 刷新 DNS / route cache
    - 软重建传输连接
    - 带退避的 probe retry
  - breaker 规则：
    - `identity` / `policy` / `pairing approval` 类错误立刻熔断自动动作
    - route 类连续失败达到阈值后进入 cooldown
  - 自动动作必须写 ledger。
- 代码入口：
  - 推荐新增 `x-terminal/Sources/Hub/HubConnectivityRepairExecutor.swift`
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-terminal/Sources/Supervisor/SupervisorXTReadyIncidentPresentation.swift`
- 完成定义：
  - 切网失败时系统先尝试 route self-heal，再决定是否升级到人工 repair。

### `SHR-W2-08` Hub runtime / provider 自愈与验证环

- 目标：
  - 让 Hub runtime repair 也进入同一条“动作 -> 验证 -> 结果”闭环。
- 必做：
  - `XHubLocalServiceRecoveryGuidance` 输出结构化 verify step。
  - `LocalRuntimeRepairSurface` 除文案外还输出：
    - `auto_restart_allowed`
    - `verify_after_ms`
    - `expected_recovery_signal`
  - route 可达但 runtime 不可用时，doctor 明确分离 `hub_reachability` 与 `runtime_readiness`。
- 代码入口：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/XHubLocalServiceRecoveryGuidance.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/LocalRuntimeRepairSurface.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/XHubDoctorOutputHub.swift`
- 完成定义：
  - runtime repair 不再只有推荐动作，还具备 machine-readable verify 语义。

### `SHR-W2-09` repair ledger 与 supervisor incident 统一

- 目标：
  - 让所有 repair 动作可追踪、可回放、可做后续优化。
- 必做：
  - 新增 repair ledger，最少记录：
    - trigger
    - failure_code
    - reason_family
    - action
    - owner
    - result
    - verify_result
    - final_route
  - incident export 中加入最近 repair 尝试摘要。
  - supervisor 视图可直接看到“系统已经做了什么，还差什么”。
- 代码入口：
  - 推荐新增 `x-terminal/Sources/Supervisor/XTRepairLedgerStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorXTReadyIncidentPresentation.swift`
  - `x-terminal/Sources/UI/XHubDoctorOutput.swift`
- 完成定义：
  - 再次出现同类故障时，系统能知道上一次 auto repair 是否有效。

### `SHR-W2-10` 连续 doctor 调度器与增量巡检

- 目标：
  - 把 doctor 从“用户点一次生成一次”升级成“事件驱动的连续巡检”。
- 必做：
  - 增量触发器：
    - 网络变化
    - 睡眠唤醒
    - pairing material 更新
    - Hub heartbeat 消失 / 恢复
    - runtime provider 状态变化
  - 支持 section 级增量复检，而不是每次全量重算。
  - 保留最近一次 full doctor 快照与最近一次 delta run。
- 代码入口：
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/XHubDoctorOutputHub.swift`
  - `scripts/run_xhub_doctor_from_source.command`
- 完成定义：
  - 用户不必每次手动打开 doctor 页，系统也能在关键事件后自动更新诊断真相。

### 5.3 P2 Release / require-real / 观测收口

### `SHR-W3-11` require-real 场景矩阵与 source gate

- 目标：
  - 把“切网仍可工作”从产品口号变成 release 证据。
- 必做：
  - 新增或扩展 smoke 场景：
    - same-LAN 首配成功
    - 离开 Wi-Fi 后切到稳定远端入口
    - Wi-Fi A -> 手机热点 -> Wi-Fi B -> 回 Wi-Fi A
    - 睡眠唤醒后续连
    - Hub 重启后续连
    - invite token 轮换 / stale profile repair
    - raw IP 仅配置时不得冒绿 remote ready
  - 将关键场景接入 `scripts/ci/xhub_doctor_source_gate.sh` 或其子门禁。
- 完成定义：
  - 这条线可以作为 source gate / release gate 的固定项目，不再靠人工口头验证。

### `SHR-W3-12` 稳定性 KPI 与 dashboard

- 目标：
  - 明确“丝滑无感”的可量化定义。
- 必做：
  - 最低 KPI：
    - `network_handoff_p95_sec <= 5`
    - `fresh_pair_cached_reconnect_success_rate >= 0.99`
    - `stable_remote_reconnect_success_rate >= 0.99`
    - `duplicate_request_after_handoff = 0`
    - `raw_ip_marked_remote_ready = 0`
    - `stale_profile_retry_loop = 0`
    - `doctor_false_green_on_off_lan = 0`
  - dashboard 与 report 导出最少要有 json + md。
- 完成定义：
  - 每次回归能清楚看到这条线是在变好还是变差。

### `SHR-W3-13` XT / Hub / Supervisor 文案与 repair UX 收口

- 目标：
  - 让用户看到的状态、doctor 输出、supervisor incident、Hub repair surface 使用同一套术语。
- 必做：
  - 统一以下概念：
    - `local_ready`
    - `remote_ready`
    - `remote_degraded`
    - `remote_blocked`
    - `identity repair required`
    - `runtime repair required`
  - 同一 failure code 在 XT / Hub / Supervisor 上给出一致修复方向。
- 完成定义：
  - 不再出现 XT 说“已连接”但 Hub / doctor / supervisor 实际表达不同含义。

## 6) 多 AI 并行时的建议切分

如果一次要并行给多个 AI，这样切写入面最稳：

### 6.1 Hub Runtime Lane

- 负责：
  - `pairing_http.js`
  - `hub_identity.js`
  - `HubSecureRemoteSetupPack.swift`
  - `XHubDoctorOutputHub.swift`
  - `XHubLocalServiceRecoveryGuidance.swift`
- 推荐工单：
  - `SHR-W1-05`
  - `SHR-W2-08`

### 6.2 XT Pairing Lane

- 负责：
  - `HubPairingCoordinator.swift`
  - `AppModel.swift`
  - `HubSetupWizardView.swift`
  - `SettingsView.swift`
- 推荐工单：
  - `SHR-W1-01`
  - `SHR-W1-02`
  - `SHR-W1-03`

### 6.3 XT Doctor / Supervisor Lane

- 负责：
  - `XTUnifiedDoctor.swift`
  - `XHubDoctorOutput.swift`
  - `TroubleshootPanel.swift`
  - `SupervisorXTReadyIncidentPresentation.swift`
- 推荐工单：
  - `SHR-W1-04`
  - `SHR-W2-06`
  - `SHR-W2-07`
  - `SHR-W2-09`
  - `SHR-W2-10`

### 6.4 QA / Gate Lane

- 负责：
  - `pairing_http_preauth_replay.test.js`
  - `HubPairingCoordinatorTests.swift`
  - `XTUnifiedDoctorReportTests.swift`
  - `XHubDoctorOutputTests.swift`
  - `SupervisorIncidentExportTests.swift`
  - `scripts/run_xhub_doctor_from_source.command`
  - `scripts/ci/xhub_doctor_source_gate.sh`
- 推荐工单：
  - `SHR-W3-11`
  - `SHR-W3-12`

## 7) 验收矩阵

### 7.1 首配与远端 readiness

- 场景：XT 与 Hub 同网首配，未配置稳定远端入口
  - 期望：`local_ready=true`, `remote_ready=false`
- 场景：XT 同网首配后配置稳定命名入口，cached reconnect smoke 通过，remote shadow smoke 通过
  - 期望：`remote_ready=true`
- 场景：XT 同网首配成功，但 remote shadow smoke 失败
  - 期望：`local_ready=true`, `remote_degraded=true`

### 7.2 切网与 handoff

- 场景：Wi-Fi A -> 手机热点
  - 期望：自动切到 `stable_named_remote` 或 `managed_tunnel_fallback`
- 场景：Wi-Fi A -> Wi-Fi B
  - 期望：active route 更新，无需重新配对
- 场景：睡眠唤醒
  - 期望：重建 transport，不触发重新配对
- 场景：Hub 重启
  - 期望：短时 `runtime_degraded`，恢复后 route 与 doctor 自动回绿

### 7.3 fail-closed 与 repair

- 场景：`invite_token_invalid`
  - 期望：进入 repair，不允许自动绕过
- 场景：`pairing_profile_epoch_stale`
  - 期望：停止无意义重试，要求刷新 route pack / 重新批准
- 场景：只配置 raw IP
  - 期望：doctor 可显示临时入口，但不得冒绿为正式 remote ready
- 场景：Hub runtime down，但网络仍可达
  - 期望：`hub_reachability=pass`，`runtime_readiness=fail`

## 8) 命令、测试与建议验证顺序

### 8.1 构建命令

- `bash x-terminal/tools/build_xterminal_app.command`
- `bash x-hub/tools/build_hub_app.command`

### 8.2 doctor 与 source-run

- `bash scripts/run_xhub_doctor_from_source.command hub`
- `bash scripts/run_xhub_doctor_from_source.command xt --workspace-root /Users/andrew.xie/Documents/AX`
- `bash scripts/run_xhub_doctor_from_source.command all --workspace-root /Users/andrew.xie/Documents/AX --out-dir /tmp/xhub_doctor_bundle`

### 8.3 重点测试入口

- `node x-hub/grpc-server/hub_grpc_server/src/pairing_http_preauth_replay.test.js`
- `x-terminal/Tests/HubPairingCoordinatorTests.swift`
- `x-terminal/Tests/XTUnifiedDoctorReportTests.swift`
- `x-terminal/Tests/XHubDoctorOutputTests.swift`
- `x-terminal/Tests/SupervisorIncidentExportTests.swift`

### 8.4 最低建议验证顺序

1. 先 build `X-Terminal` 与 `X-Hub`
2. 跑 pairing / preauth / invite token 相关测试
3. 跑 XT pairing / doctor / incident 相关测试
4. 跑 `bash scripts/run_xhub_doctor_from_source.command all ...`
5. 跑 `bash scripts/ci/xhub_doctor_source_gate.sh`
6. 最后做 require-real 手工切网验证

## 9) 完成一项工单时必须同步的东西

- 更新对应代码与测试。
- 更新 doctor / incident / export 字段，而不是只改 UI。
- 生成或更新 machine-readable 证据文件。
- 若新增 failure code / reason family / repair kind，必须同步：
  - XT doctor
  - Hub doctor
  - troubleshoot routing
  - supervisor incident
  - 测试

## 10) 不要踩的坑

- 不要把“当前可达”误写成“长期稳定可达”。
- 不要让 raw IP 因为短时可连就进入正式 remote green。
- 不要为了看起来更自动，把 identity / grant / policy 故障偷偷转成 route retry。
- 不要让 source gate 只验证 UI 文案，不验证 machine-readable 输出。
- 不要在没有 verify step 的情况下新增自动 repair。

## 11) 一句话执行顺序

先把 `paired_route_set + route handoff + first_pair_completion_proof` 做扎实，再把 `reason family + repair policy + repair ledger + continuous doctor` 接上，最后用 require-real 场景矩阵和 KPI 把这条线封成 release 级主链。
