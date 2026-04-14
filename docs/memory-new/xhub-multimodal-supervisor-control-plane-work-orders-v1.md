# X-Hub Multimodal Supervisor Control Plane Work Orders v1

- version: v1.0
- updatedAt: 2026-03-19
- owner: Hub-L5 / XT-L2 / Mobile-L1 / Security / QA
- status: active-planning
- scope: one Supervisor across XT, voice, operator channels, mobile companion, trusted runner, shopping / robot pilot
- contract freeze:
  - `docs/memory-new/xhub-multimodal-supervisor-control-plane-contract-freeze-v1.md`
  - `docs/memory-new/schema/xhub_multimodal_supervisor_control_plane_contract.v1.json`
- parent:
  - `docs/memory-new/xhub-multimodal-supervisor-control-plane-architecture-memo-v1.md`
  - `docs/memory-new/xhub-multimodal-supervisor-control-plane-contract-freeze-v1.md`
  - `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
  - `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## 0) Why This Plan Exists

目前 voice、operator channels、trusted automation、governed recipe runtime 都有独立工单，但还缺一个系统级收口：

- 用户应该只面对一个 `Supervisor`
- `Hub` 应该是所有 surface 的唯一控制平面
- `x-hub` 记忆系统应成为所有 brief / grant / checkpoint 的 continuity 底座
- embodied 场景必须沿用同一条 `risk -> policy -> grant -> execute -> audit -> memory` 主链

这份工单的作用不是替代现有专项包，而是把它们编排成一个可落地的主路径。

## 1) Finished State

完成后，系统至少要满足以下事实：

1. `voice / XT UI / mobile companion / Slack / Telegram / Feishu / runner events` 先统一进入 `Hub Supervisor Facade`。
2. 所有 surface 共用 `brief projection`、`pending grants digest`、`next best action`、`checkpoint challenge` 四类 Hub 投影视图。
3. 路由固定收敛为：
   - `hub_only`
   - `hub_to_xt`
   - `hub_to_runner`
4. 高风险授权在任何 surface 上都不会绕开 Hub voice / mobile / grant 主链。
5. shopping / robot v1 以 bounded recipe 和 checkpoint 方式运行，而不是自由代理。
6. 设备离线、权限缺失、remote posture 不足时，所有 surface 都返回一致 deny / downgrade 语义。

## 2) Hard Boundaries

- 不把 mobile companion 做成新的 trust anchor。
- 不把 raw audio、外部 IM 附件、第三方链接默认写入 canonical memory。
- 不把 attachment metadata 的可见性误当成 attachment/blob body 的读取权限。
- 不把 attachment/blob body 默认塞进 multi-surface brief projection 或 remote prompt bundle。
- 不把任意自然语言直接升级为 `terminal.exec`、`device.*`、`connector.send`、`grant.approve`。
- 不把 `WhatsApp personal` 作为首版 require-real 绿色能力；若使用本机会话，必须继续走 `trusted_automation + local runner`。
- 不在 v1 声称“全自动机器人购物”；首版只做 supervised shopping / bounded mission pilot。

## 2.1) Wave-1 A6 承接范围（Attachment Visibility + Blob ACL）

来自 `docs/memory-new/xhub-memory-open-source-reference-wave1-execution-pack-v1.md` 的 `attachment visibility + blob ACL`，在多模态控制平面下的正式承接范围如下：

- 本工单只承接 `MMS-W2 / MMS-W4` 所需的 cross-surface 语义对齐，不回改 `docs/memory-new/xhub-multimodal-supervisor-control-plane-contract-freeze-v1.md` 已冻结主 contract。
- 所有 surface 的 attachment/blob 输入先是 `untrusted ingress ref`，不是默认可读 body。
- 多模态 surface 只能共享同一套 `metadata-first / body-gated / remote-export-fenced / audit-bound` 语义，不能因为 voice / IM / mobile / XT 形态不同而产生不同默认权限。

### 2.1.1 Metadata-first projection

- brief projection、channel summary、mobile digest 默认只允许带：
  - `attachment_ref`
  - `mime_type`
  - `size`
  - `visibility`
  - `redaction_state`
  - `summary / evidence_refs`
- `metadata visible != body readable` 必须成为所有 surface 的固定解释。
- metadata route 默认不得自动继承 body read authority。

### 2.1.2 Remote export fence

- voice / XT / channel / mobile companion 的 remote bundle 默认只允许：
  - metadata
  - summary
  - selected refs
- attachment/blob body 默认不得外发；未显式授权时必须 deny 或 downgrade。
- 阻断结果必须能在各 surface 上回放成一致的 machine-readable deny / downgrade 语义。

### 2.1.3 Body read grant binding

- attachment/blob body 的读取必须重新绑定：
  - `scope`
  - `grant_id`
  - `audit_ref`
  - `body_read_reason`
- cross-surface reuse、grant drift、replay tamper 必须 fail-closed。
- `MMS` 侧只承接 surface 解释与 projection/fence 一致性；grant 主链仍挂在既有 Hub policy / M3 grant chain。

## 3) Workstreams

### 3.1 `MMS-W1` Hub Supervisor Facade + Surface Ingress Normalization

- Goal:
  - 把多 surface 输入统一为 Hub 可治理入口。
- Scope:
  - 新增 `xhub.supervisor_surface_ingress.v1`
  - 新增 `xhub.supervisor_route_decision.v1`
  - 冻结 `surface_type`, `actor_ref`, `project_ref`, `preferred_device_id`, `runner_required`, `deny_code`
- Suggested touchpoints:
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_registry.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_delivery_context.js`
  - `protocol/hub_protocol_v1.proto`
  - `protocol/hub_protocol_v1.md`
- Frozen by:
  - `docs/memory-new/xhub-multimodal-supervisor-control-plane-contract-freeze-v1.md`
  - `docs/memory-new/schema/xhub_multimodal_supervisor_control_plane_contract.v1.json`
- Depends on:
  - `xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
- DoD:
  - 所有入口都先落入统一 ingress envelope
  - 任何 route 决策都能落 machine-readable audit
  - `project-first + preferred-device` 与 `hub_only` 降级语义统一
- Gate:
  - `MMS-G1`
- KPI:
  - `cross_surface_route_semantic_drift = 0`
  - `device_offline_false_success = 0`

### 3.2 `MMS-W2` Hub Memory Projection Layer For Supervisor

- Goal:
  - 把 `x-hub` 记忆系统投影成多 surface 可复用的运营视图。
- Scope:
  - 新增 `xhub.supervisor_brief_projection.v1`
  - 新增 `pending grants digest`
  - 新增 `next best action` projection
  - 新增 `mission / checkpoint ledger` projection
  - 新增 attachment metadata-first projection 约束
- Suggested touchpoints:
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
  - `x-terminal/Sources/Supervisor/MemoryUXAdapter.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- Frozen by:
  - `docs/memory-new/xhub-multimodal-supervisor-control-plane-contract-freeze-v1.md`
  - `docs/memory-new/schema/xhub_multimodal_supervisor_control_plane_contract.v1.json`
- Depends on:
  - `docs/xhub-memory-system-spec-v2.md`
  - `x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md`
- DoD:
  - voice brief、channel summary、mobile digest 都来自同一 projection 层
  - projection 带 `evidence_refs`
  - raw audio / external attachment 默认不写 canonical
  - attachment 默认只以 metadata / summary / refs 进入 projection，body 不得默认混入
- Gate:
  - `MMS-G2`
- KPI:
  - `brief_compile_p95_ms <= 800`
  - `projection_without_evidence_ref = 0`
  - `attachment_body_projection_leak = 0`

### 3.3 `MMS-W3` Outdoor Voice + Mobile Companion Authorization Chain

- Goal:
  - 把户外耳机 / 手机 / 手表场景做成正式主链，而不是桌面语音功能堆叠。
- Scope:
  - 复用 `XT-W3-29` 的 wake、brief、directive、voice challenge
  - 增加 lightweight `mobile companion` 角色
  - 固定高风险默认 `voice + mobile confirm`
- Suggested touchpoints:
  - `x-terminal/Sources/UI/VoiceInputView.swift`
  - `x-terminal/Sources/Supervisor/`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `protocol/hub_protocol_v1.proto`
  - companion app / shell 新目录（待定）
- Depends on:
  - `xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
- DoD:
  - `blocked / awaiting_authorization / critical_path_changed / completed` 可主动播报
  - directive 一定绑定 `project/run/pool/lane/mission`
  - 高风险 voice-only 默认不能放行
  - mobile 端只消费 Hub state，不自持 secrets
- Gate:
  - `MMS-G3`
- KPI:
  - `high_risk_voice_only_bypass = 0`
  - `voice_directive_binding_accuracy >= 0.95`
  - `voice_brief_interrupt_recovery_success_rate >= 0.98`

### 3.4 `MMS-W4` Operator Channels Unification On Hub Facade

- Goal:
  - 让 `Slack / Telegram / Feishu` 真正成为 Supervisor 的外部入口，而不是单独的 bot 体系。
- Scope:
  - 共用 `MMS-W1` ingress 和 route decision
  - 共用 `MMS-W2` projection
  - 统一 `structured action -> grant -> audit -> delivery`
- Suggested touchpoints:
  - `x-hub/grpc-server/hub_grpc_server/src/channel_registry.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_runtime_snapshot.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-terminal/Sources/UI/ChannelsCenter/ChannelsCenterView.swift`
- Depends on:
  - `xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
- DoD:
  - channel query、approval card、heartbeat push、delivery summary 共用 Hub facade
  - XT 离线时返回真实 route 状态
  - 附件 / callback / button 全部当作 untrusted ingress
  - channel attachment 的 metadata/body split 与 XT / voice / mobile 保持一致
- Gate:
  - `MMS-G4`
- KPI:
  - `channel_query_to_first_response_p95_ms <= 3000`
  - `unauthorized_channel_action = 0`
  - `cross_project_channel_route_leak = 0`
  - `cross_surface_attachment_acl_drift = 0`

### 3.5 `MMS-W5` Trusted Execution Route For `hub_to_runner`

- Goal:
  - 把语音 / IM / XT 触发的本地执行统一接到 trusted runner，而不是各自旁路。
- Scope:
  - 统一 `hub_to_runner` 路由
  - runner 重验 `same user + same device + same project scope`
  - `device.*` 必须带 `grant_id` / `route_decision_ref`
- Suggested touchpoints:
  - `x-terminal/Sources/AutomationRunner/`
  - `x-terminal/Sources/Tools/DeviceAutomationGateway.swift`
  - `x-terminal/Sources/Project/TrustedAutomationSessionBinder.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- Depends on:
  - `docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
  - `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
- DoD:
  - runner 不接受无 project binding 或无 grant 的命令
  - route deny code 与 Hub 保持一致
  - `toolProfile=full` 不再被误认为 trusted automation active
- Gate:
  - `MMS-G5`
- KPI:
  - `runner_without_hub_allow = 0`
  - `cross_project_runner_escape = 0`

### 3.6 `MMS-W6` Shopping / Embodied Mission Pilot

- Goal:
  - 以最小可验证方式把“外出购物 / embodied task”接进现有架构。
- Scope:
  - 只做 bounded mission，不做自由自治
  - 固定任务对象：`shopping mission`
  - 固定 checkpoint：`item match`, `substitution`, `budget exceed`, `payment`, `geofence exit`
- Suggested touchpoints:
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift`
  - `x-terminal/Sources/Supervisor/`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- Depends on:
  - `MMS-W2`
  - `MMS-W5`
- DoD:
  - mission 有 manifest、预算、替代规则、checkpoint policy
  - 支付只能通过 Hub challenge
  - 所有 checkpoint 都有 evidence ref 与 audit
- Gate:
  - `MMS-G6`
- KPI:
  - `payment_without_challenge = 0`
  - `mission_checkpoint_audit_coverage = 1.0`

### 3.7 `MMS-W7` Require-Real Gates, Evidence, And Release Posture

- Goal:
  - 把这条主线从“设计合理”推进到“真实可用、可验证”。
- Scope:
  - 构建系统级 require-real 回归包
  - 覆盖 `voice`, `channel`, `mobile confirm`, `runner`, `shopping mission`
  - 冻结演示边界与 release wording
- Suggested touchpoints:
  - `x-terminal/scripts/ci/xt_release_gate.sh`
  - `.github/workflows/`
  - `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`
  - `docs/WORKING_INDEX.md`
- Depends on:
  - `MMS-W1..W6`
- DoD:
  - 每条主链都有 machine-readable evidence
  - 失败路径有 deny code 与回放样本
  - external wording 不超出 require-real 范围
- Gate:
  - `MMS-G7`
- KPI:
  - `structured_action_without_audit = 0`
  - `require_real_demo_pass_rate = 1.0`

## 4) Recommended Sequence

1. `MMS-W1`
   - 先统一入口和路由，否则 voice、channel、runner 会继续分叉。
2. `MMS-W2`
   - 再统一 brief / grant / next-action 投影，否则各 surface 会各自拼摘要。
3. `MMS-W3 + MMS-W4`
   - 语音和 operator channels 并行推进，但必须消费同一 projection / route 主链。
4. `MMS-W5`
   - 在上层入口稳定后，收紧 trusted runner 执行面。
5. `MMS-W6`
   - 最后做 shopping / robot pilot，避免把高风险 embodied 场景当成基础能力验证场。
6. `MMS-W7`
   - 用 require-real 与 release gate 做最终收口。

## 5) Suggested 6-Week Cut

### Week 1

- Freeze `surface ingress`, `route decision`, `brief projection` contracts
- 明确 `hub_only / hub_to_xt / hub_to_runner` 统一语义

### Week 2

- 落地 `MMS-W2` 的 brief / pending grants / next action projection
- 让 XT 与 channel 都先消费只读 projection

### Week 3

- 打通户外耳机主路径：
  - auto brief
  - directive binding
  - voice challenge
  - mobile confirm stub

### Week 4

- 打通 `Slack / Telegram / Feishu` 与同一 Supervisor facade
- 演示 `project-first + preferred-device + true offline downgrade`

### Week 5

- 收紧 `hub_to_runner` 与 `device.*` 主链
- 补 `same-project scope`, `permission readiness`, `remote posture` 回归

### Week 6

- 做 `shopping mission` pilot
- 输出 require-real evidence、演示脚本、release wording freeze

## 6) Open Questions To Resolve Early

1. mobile companion 是独立 app、XT companion mode，还是先用现有 mobile terminal 壳？
2. 户外耳机模式下的 `user present` / `trusted wearable present` 如何判定？
3. shopping pilot 的首个支付 connector 选哪条路径，如何做最小可验证闭环？
4. `WhatsApp personal` 是否只保留 planned，不进入 6 周 require-real 范围？

## 7) One-Sentence Conclusion

先把 `Supervisor` 做成一个由 `X-Hub` 统一治理的多模态控制平面，再让语音、IM、XT、runner、购物任务作为共用主链上的不同 surface 和 execution leg；这是最快、最安全、也最能放大 X-Hub + X-Terminal + Hub memory 架构优势的路径。
