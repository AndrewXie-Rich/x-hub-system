# X-Hub / X-Terminal 跨网自动重连与安全收口执行工单

- version: v1.0
- updatedAt: 2026-03-10
- owner: Hub Runtime / XT Pairing / Security / QA
- status: active
- scope: pairing bootstrap, route resolution, off-LAN auto reconnect, VPN/Tunnel security posture, release evidence
- parent:
  - `docs/xhub-client-modes-and-connectors-v1.md`
  - `docs/xhub-hub-architecture-tradeoffs-v1.md`
  - `docs/axhubctl_tunnel_mode3.md`
  - `docs/memory-new/xhub-connector-reliability-kernel-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w1-02-route-state-machine.md`
  - `x-terminal/work-orders/xt-w3-27-hub-xt-ui-productization-r1-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-28-paired-terminal-trust-profile-and-budget-visibility-implementation-pack-v1.md`

## 0) 为什么需要这份工单

当前代码已经具备下面这些基础能力：

- XT 远程路由不是单一路径，已显式区分 `lan` / `internet` / `internetTunnel`。
- XT 连接器已经是 `LAN first`，失败后再试 `internetHost` 直连，再试 tunnel。
- Hub UI 也已经明确写出：`Internet Host` 应该是 Terminal 可达的 `LAN/VPN/Tunnel host`，并且不建议把 gRPC 端口直接暴露到公网。

但当前主路径仍有明显缺口：

- `192.168.x.x` 一类 LAN 地址不能作为“离开局域网后仍可自动连接”的稳定身份。
- XT 当前只有一个 `Internet Host` 字段，混合承载了 LAN、VPN、tunnel 三种语义，用户和 Doctor 都很难判断“只是本地能连”还是“跨网也能连”。
- pairing 成功并不等于 off-LAN ready；如果 `Internet Host` 为空，离开局域网后当前实现会直接失败。
- 当前安全建议已存在，但还没有被收敛成一套默认 fail-closed 的产品主链和发布门禁。

这份工单的目标是：

- pairing 完成后，X-Terminal 在离开局域网时仍能自动重连 X-Hub。
- 默认安全姿态不退化，不依赖“用户自己理解网络拓扑”。
- 明确区分 `local_ready` 和 `remote_ready`，避免“本地能通就误以为跨网可用”。

## 1) 目标与非目标

### 1.1 目标

- 保留 `192.168.x.x` / LAN 地址作为同网段快速路径，但不再把它当成跨网主身份。
- 引入明确的 `lan_host + remote_host + managed_tunnel_fallback` 路由模型。
- 让 XT 在 `auto` / `grpc` 模式下都能对 off-LAN 场景做出可解释、可审计的路径决策。
- 把远程模式默认收敛到 `VPN/Tunnel + mTLS + CIDR allowlist + admin local-only`。
- 增加 remote reconnect smoke 与机读证据，成为发布门禁的一部分。

### 1.2 非目标

- 不支持“只填一个 `192.168.x.x`，离开局域网后系统自动魔法可达”。
- 不把“公网直接暴露 gRPC/pairing 端口”做成默认方案。
- 不放松既有 grant、audit、device trust、mTLS 边界。
- 不把 file IPC 伪装成跨网可用方案。

## 2) 决策冻结

### 2.1 Host 语义冻结

- `lan_host`
  - 含义：同一 LAN / 同一子网 / 同一 VPN 子网内的首选直连目标。
  - 允许值：LAN IP、局域网 hostname、同机 loopback。
  - 作用：性能优化，不代表 off-LAN continuity。
- `remote_host`
  - 含义：离开当前局域网后仍可达的稳定主机标识。
  - 允许值：VPN IP、tailnet name、受控 tunnel 域名或入口地址。
  - 作用：off-LAN continuity 的必要条件。
- `managed_tunnel_fallback`
  - 含义：当 `remote_host` 直连失败时的受控 tunnel 兜底路径。
  - 作用：不是第一选择，但必须可观测、可诊断、可回滚。

### 2.2 路由顺序冻结

固定顺序：

1. `lan_host`
2. `remote_host` direct
3. `managed_tunnel_fallback`

禁止：

- 在没有 `remote_host` 的情况下，把 `pairing ok` 描述成 `remote ready`
- 在 `grpc` 模式下静默退回 file IPC 伪装为“远程连接成功”
- 在严格安全配置下，把裸公网 IP 直连默认视为安全路径

### 2.3 安全姿态冻结

- 远程默认档位：`vpn_strict`
- 默认要求：
  - `remote_host` 非空
  - `Allowed CIDRs` 绑定到 VPN / overlay 子网
  - mTLS 开启；如暂不强制，也必须给出 blocking warning
  - remote admin RPC 默认关闭
  - pairing / gRPC 端口不得建议直接公网映射
- 仅保留一个显式的逃生口：`unsafe_public_dev_mode`
  - 默认关闭
  - 必须强警告
  - 不得在 release / doctor green / sample docs 中当作推荐路径

## 3) 机读契约

### 3.1 `hub.remote_pairing_profile.v1`

```json
{
  "schema_version": "hub.remote_pairing_profile.v1",
  "device_id": "device_xt_001",
  "pairing_request_id": "pair_req_001",
  "lan_host": "192.168.1.8",
  "remote_host": "hub-main.tailnet.ts.net",
  "remote_transport": "vpn_direct",
  "security_profile": "vpn_strict",
  "allowed_cidrs_mode": "vpn_subnet_only",
  "mtls_required": true,
  "remote_admin_enabled": false,
  "last_remote_smoke_at_ms": 0,
  "last_remote_route": "internet",
  "audit_ref": "audit-remote-pairing-001"
}
```

### 3.2 `xt.remote_route_resolution.v1`

```json
{
  "schema_version": "xt.remote_route_resolution.v1",
  "transport_mode": "auto",
  "pairing_state": "remote_ready",
  "selected_route": "internet",
  "reason_code": "",
  "candidates_tried": [
    "lan_host",
    "remote_host_direct"
  ],
  "auto_reconnect_enabled": true,
  "requires_user_action": false,
  "next_action": "continue",
  "audit_ref": "audit-route-resolution-001"
}
```

### 3.3 `hub.remote_reconnect_smoke.v1`

```json
{
  "schema_version": "hub.remote_reconnect_smoke.v1",
  "run_id": "remote_smoke_001",
  "scenario": "paired_terminal_off_lan_reconnect",
  "success": true,
  "used_route": "internet_tunnel",
  "attempts": [
    {
      "route": "lan",
      "ok": false,
      "reason_code": "network_unreachable"
    },
    {
      "route": "internet_tunnel",
      "ok": true,
      "reason_code": ""
    }
  ],
  "handshake_ms": 1830,
  "security_checks": {
    "remote_host_present": true,
    "mtls_enabled": true,
    "remote_admin_disabled": true,
    "public_grpc_exposure_detected": false
  },
  "audit_ref": "audit-remote-smoke-001"
}
```

### 3.4 统一拒绝码

- `remote_host_missing`
- `remote_security_profile_missing`
- `remote_route_unreachable`
- `lan_only_profile`
- `public_grpc_exposure_forbidden`
- `remote_admin_not_allowed`
- `vpn_cidr_required`
- `mtls_required`
- `remote_smoke_failed`
- `managed_tunnel_unhealthy`

## 4) Gate / KPI

### 4.1 Gate

- `RPS-G0`：`remote_pairing_profile / remote_route_resolution / remote_reconnect_smoke` 三份契约冻结并落盘。
- `RPS-G1`：XT 与 Hub UI 都能明确区分 `local_ready` 和 `remote_ready`，禁止语义混淆。
- `RPS-G2`：连接顺序固定为 `lan_host -> remote_host -> tunnel fallback`，并输出 machine-readable route evidence。
- `RPS-G3`：当 XT 离开局域网时，配置完整的 paired device 可自动重连成功。
- `RPS-G4`：远程默认安全姿态达标；裸公网 gRPC 暴露默认被阻断或红牌告警。
- `RPS-G5`：旧配置迁移不误判；已有仅 LAN 的用户不会被自动标绿成 remote ready。
- `RPS-G6`：回归、doctor、CI、证据导出全接线，能作为 release gate。

### 4.2 KPI

- `off_lan_reconnect_success_rate >= 0.99`
- `remote_failover_p95_sec <= 8`
- `lan_only_profile_misreported_as_remote_ready = 0`
- `public_grpc_port_exposure_count = 0`
- `remote_admin_enabled_by_default = 0`
- `remote_smoke_without_evidence_count = 0`
- `unsafe_public_dev_mode_enabled_in_release = 0`

## 5) 实施工单拆解

### P0（阻断主链）

#### `RPS-W1-01` Dual Host 契约与配置迁移

- 目标：把当前单一 `Internet Host` 迁移为显式 `lan_host` 与 `remote_host`。
- 具体要求：
  - XT 新增 `hub_lan_host` / `hub_remote_host` 持久化字段。
  - 保留旧 `hubInternetHostKey` 迁移逻辑。
  - 迁移规则必须 fail-safe：
    - 旧值为空：`lan_host=''`, `remote_host=''`
    - 旧值为 loopback：仅写 `lan_host`
    - 旧值为 RFC1918 / 局域网地址：仅写 `lan_host`
    - 旧值为域名、VPN 地址、tailnet host：优先写 `remote_host`
  - 迁移后禁止自动宣称 `remote_ready`，除非 `remote_host` 明确存在且 smoke 通过。
- 涉及路径：
  - `x-terminal/Sources/Hub/HubAIClient.swift`
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/UI/HubSetupWizardView.swift`
  - `x-terminal/Sources/UI/SettingsView.swift`
- 交付物：
  - `build/reports/rps_w1_01_dual_host_migration_evidence.v1.json`
- 验收：
  - 旧用户升级后不会被错误标记为 off-LAN ready。

#### `RPS-W1-02` 路由状态机与连接器收敛

- 目标：把 XT 当前 `lan -> internet -> tunnel` 路径升级成显式、可解释、可回放的状态机。
- 具体要求：
  - `HubRouteStateMachine` 新增配对就绪语义：
    - `local_ready`
    - `remote_ready`
    - `remote_degraded`
    - `remote_blocked`
  - `HubPairingCoordinator` 固定按 `lan_host -> remote_host direct -> tunnel` 顺序尝试。
  - `auto` 模式允许 file IPC 回落，但不得伪装成 remote success。
  - `grpc` 模式维持严格 fail-closed。
  - 所有分支都输出 `reason_code` 与 `candidates_tried`。
- 涉及路径：
  - `x-terminal/Sources/Hub/HubRouteStateMachine.swift`
  - `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/work-orders/xt-w1-02-route-state-machine.md`
- 交付物：
  - `build/reports/rps_w1_02_route_resolution_evidence.v1.json`
- 验收：
  - 关闭 LAN 后仍能自动切到 `remote_host` 或 tunnel。

#### `RPS-W1-03` Remote Readiness UX / Doctor / Copy Vars

- 目标：让用户清楚知道“现在只是本地可用”还是“跨网也可用”。
- 具体要求：
  - XT Hub Setup / Settings 中分开展示：
    - `LAN Host`
    - `Remote Host`
    - `Remote Transport`
    - `Security Profile`
    - `Last Remote Smoke`
  - Hub Settings 中同样分开展示并支持一键复制。
  - Doctor 增加明确状态：
    - `pairing_valid_local_only`
    - `pairing_remote_ready`
    - `pairing_remote_degraded`
  - Copy Connect Vars 输出必须包含双 host 信息，而不是单个 `Internet Host`。
- 涉及路径：
  - `x-terminal/Sources/UI/HubSetupWizardView.swift`
  - `x-terminal/Sources/UI/SettingsView.swift`
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubGRPCServerSupport.swift`
- 交付物：
  - `build/reports/rps_w1_03_remote_readiness_ui_evidence.v1.json`
- 验收：
  - 没有 `remote_host` 时，所有主路径都必须清楚显示 `local_only`。

#### `RPS-W1-04` 远程默认安全姿态收口

- 目标：把“推荐用 VPN/Tunnel，不要公网直暴露”变成产品默认行为。
- 具体要求：
  - Hub 新增远程安全档位：
    - `lan_only`
    - `vpn_strict`
    - `tunnel_strict`
    - `unsafe_public_dev_mode`
  - `vpn_strict` 默认要求：
    - `remote_host` 非空
    - `allowed_cidrs` 绑定 VPN / overlay 子网
    - mTLS 打开
    - remote admin 禁用
  - `unsafe_public_dev_mode` 必须是显式 opt-in，并带红色风险文案。
  - 如果检测到直接公网暴露 pairing/gRPC 且不在 dev mode，Doctor 必须红牌。
- 涉及路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubGRPCServerSupport.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - `docs/xhub-hub-architecture-tradeoffs-v1.md`
- 交付物：
  - `build/reports/rps_w1_04_remote_security_posture_evidence.v1.json`
- 验收：
  - release 路径下不能把裸公网 gRPC 暴露当推荐配置。

#### `RPS-W1-05` Remote Reconnect Smoke 与证据主链

- 目标：把“跨网是否真的能连”从口头确认升级为机读证据。
- 具体要求：
  - 新增 off-LAN reconnect smoke：
    - 强制跳过 LAN
    - 尝试 `remote_host`
    - 必要时尝试 tunnel
  - 记录：
    - used route
    - handshake latency
    - security checks
    - reason code
  - XT / Hub UI 都能触发 smoke，并显示最近一次结果。
  - XT 侧若通过 `XTUnifiedDoctor` 暴露 reconnect state / reason code，source report 受 `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json` 约束，generic export 继续受 `docs/memory-new/schema/xhub_doctor_output_contract.v1.json` 约束。
- 涉及路径：
  - `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - `x-terminal/Sources/UI/HubSetupWizardView.swift`
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
- 交付物：
  - `build/reports/rps_w1_05_remote_reconnect_smoke.v1.json`
- 验收：
  - 无 smoke 证据时不得宣称 `remote_ready`。

### P1（关键收益）

#### `RPS-W2-01` Managed Tunnel 产品化与健康态可视化

- 目标：把 tunnel 从“隐式兜底”升级为“可观测、可诊断、可解释”的第二主路径。
- 具体要求：
  - Hub UI 显示 tunnel install / running / degraded 状态。
  - XT 端显示最近 tunnel fallback 原因。
  - 文案明确：这是 fallback，不是默认推荐优先级。
- 交付物：
  - `build/reports/rps_w2_01_managed_tunnel_health_evidence.v1.json`

#### `RPS-W2-02` 配对信任档案纳入远程访问档位

- 目标：把 remote access mode 纳入 pairing policy，而不是事后分散配置。
- 具体要求：
  - 在 `XT-W3-28` trust profile 中增加：
    - `remote_access_mode`
    - `security_profile`
    - `remote_ready_required`
  - 已批准设备可按设备级策略决定是否允许 off-LAN 使用。
- 涉及路径：
  - `x-terminal/work-orders/xt-w3-28-paired-terminal-trust-profile-and-budget-visibility-implementation-pack-v1.md`
  - pairing request / approved device 持久化结构
- 交付物：
  - `build/reports/rps_w2_02_remote_access_policy_evidence.v1.json`

#### `RPS-W2-03` 回归、Doctor、CI 接线

- 目标：把这条主链从“靠人记住”升级成持续回归。
- 具体要求：
  - 覆盖迁移、LAN only、VPN strict、tunnel fallback、mTLS missing、CIDR mismatch、public exposure forbidden。
  - CI 至少校验：
    - 契约存在
    - doctor state 准确
    - remote smoke evidence 结构正确
- 交付物：
  - workflow / tests / sample fixtures
- 验收：
  - `RPS-G0..G6` 可被脚本机判。

#### `RPS-W2-04` 文档与排障主路径统一

- 目标：避免用户再去猜“Internet Host 到底该填什么”。
- 具体要求：
  - 更新 Hub / XT 主文档：
    - 优先推荐 Tailscale / Headscale / WireGuard / ZeroTier
    - 明确 `lan_host != remote_host`
    - 明确“离开局域网后继续连接”需要稳定 `remote_host`
  - 排障文案统一拒绝码和下一步动作。
- 交付物：
  - 文档更新 + doctor repair entry

### P2（增强项）

#### `RPS-W3-01` Multi-Candidate Remote Host 与 RTT 评分

- 目标：一台 Hub 有多个可达远程入口时，自动选最稳的一条。
- 具体要求：
  - 支持 `remote_hosts[]`
  - 保存最近成功路径与 RTT
  - 失败时自动切换备用入口
- 验收：
  - 多入口环境下平均重连时间进一步下降。

## 6) 四周排程

- 2026-03-10 ~ 2026-03-16
  - `RPS-W1-01`
  - `RPS-W1-02`
- 2026-03-17 ~ 2026-03-23
  - `RPS-W1-03`
  - `RPS-W1-04`
- 2026-03-24 ~ 2026-03-30
  - `RPS-W1-05`
  - `RPS-W2-01`
- 2026-03-31 ~ 2026-04-06
  - `RPS-W2-02`
  - `RPS-W2-03`
  - `RPS-W2-04`

## 7) 最小回归矩阵

### Correctness

- 旧 `Internet Host` 为空升级
- 旧 `Internet Host=127.0.0.1`
- 旧 `Internet Host=192.168.x.x`
- 旧 `Internet Host=hub.tailnet.ts.net`
- `lan_host` 可用时优先走 LAN
- `lan_host` 不可用时自动切 `remote_host`
- `remote_host` 失败时 tunnel fallback 生效

### Security

- `remote_host_missing` 必须阻断 `remote_ready`
- `vpn_strict` 下 CIDR 不匹配必须红牌
- mTLS 关闭但配置为 strict 必须红牌
- 检测到公网直暴露 gRPC 且非 dev mode 必须拒绝标绿
- remote admin 默认关闭

### Reliability

- XT 从 LAN 切到蜂窝 / 外网后自动重连
- remote direct 短时失败后 tunnel fallback 成功
- tunnel 服务异常时错误码稳定
- smoke 失败后状态从 `remote_ready` 降级为 `remote_degraded`

### UX / Explainability

- Hub Setup / Settings / Doctor 对 `local_ready` 与 `remote_ready` 描述一致
- Copy Connect Vars 包含双 host 与安全档位
- 没有 `remote_host` 时，不再显示模糊的“Internet Host missing but local works”语义

## 8) 发布证据最小集

- `build/reports/rps_w1_01_dual_host_migration_evidence.v1.json`
- `build/reports/rps_w1_02_route_resolution_evidence.v1.json`
- `build/reports/rps_w1_03_remote_readiness_ui_evidence.v1.json`
- `build/reports/rps_w1_04_remote_security_posture_evidence.v1.json`
- `build/reports/rps_w1_05_remote_reconnect_smoke.v1.json`
- `build/reports/rps_w2_01_managed_tunnel_health_evidence.v1.json`
- `build/reports/rps_w2_02_remote_access_policy_evidence.v1.json`

## 9) 回滚策略

- 配置回滚：
  - 保留 legacy `hubInternetHostKey` 读取兼容，直到 `RPS-G5` 稳定通过。
- UI 回滚：
  - 若双 host UI 出现混乱，可短期保留旧 `Internet Host` 文案只读展示，但内部契约不回退。
- 安全回滚：
  - 允许从 `vpn_strict` 回退到 `lan_only`，不允许因为回滚而默认放开公网暴露。
- 路由回滚：
  - tunnel fallback 可临时关闭，但 `remote_host` 语义与 doctor 绿牌规则不得回退为旧的模糊状态。

## 10) 完成定义（DoD）

- 用户可以明确配置 `lan_host` 和 `remote_host`。
- `192.168.x.x` 继续可用于局域网直连，但不会再被系统误当作 off-LAN continuity 方案。
- XT 离开局域网后，如存在可达 `remote_host` 或 tunnel，可自动重连。
- Hub / XT UI、Doctor、日志、证据、CI 对“跨网自动重连 + 安全姿态”有统一语义。
- 默认推荐路径是 `VPN/Tunnel + mTLS + CIDR allowlist + admin local-only`，而不是公网直暴露。
