# X-Hub Multimodal Supervisor Control Plane Architecture Memo v1

- version: v1.0
- updatedAt: 2026-03-13
- owner: Hub-L5 / XT-L2 / Mobile-L1 / Security / QA
- status: proposed-active
- scope: voice, operator channels, mobile companion, trusted execution plane, embodied shopping / robot pilot
- contract freeze:
  - `docs/memory-new/xhub-multimodal-supervisor-control-plane-contract-freeze-v1.md`
  - `docs/memory-new/schema/xhub_multimodal_supervisor_control_plane_contract.v1.json`
- parent:
  - `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
  - `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## 0) Problem Statement

我们要支持的不是单一“桌面聊天”场景，而是同一个 `Supervisor` 在多种现实场景下持续工作：

- 用户在户外用耳机接收 `Supervisor` 主动汇报，并用麦克风给出下一步指导或授权。
- 用户在 `Slack / Telegram / Feishu / WhatsApp` 中和同一个 `Supervisor` 沟通，而不是和不同 bot、不同设备状态碎片化对话。
- 用户通过 `X-Terminal` 或后续 companion surface 持续推进项目，`Supervisor` 负责跨项目、跨泳道、跨时段 continuity。
- 机器人或本地执行面去购物、巡检、取证、触发外部动作，但高风险权力仍留在 `X-Hub`。

如果按“每个入口各做一套状态机”推进，最终会失去 X-Hub-System 最大的架构优势：

- `Hub-first` 真相源
- 统一 `grant / policy / audit / kill-switch`
- `project-first` 路由
- `x-hub` 记忆系统作为 continuity 与行为边界底座

## 1) One-Line Decision

产品方向冻结为：

`One Supervisor, many surfaces; one Hub, many execution legs.`

翻译成系统设计：

- `X-Hub` 是唯一可治理的 `Supervisor Control Plane`
- `X-Terminal`、mobile / wearable companion、IM channels、robot / runner 都只是 surface 或 execution plane
- 所有入口先进入 Hub，再由 Hub 决定是 `hub_only`、`hub_to_xt` 还是 `hub_to_runner`

## 2) Finished-State User Model

用户看到的是一个 `Supervisor`，不是四五套产品：

- 在耳机里，`Supervisor` 会在 `blocked / awaiting_authorization / critical_path_changed / completed` 时主动播报简报。
- 在手机或手表上，用户可以看到同一条授权 challenge、同一条项目摘要、同一条下一步建议。
- 在 `Slack / Telegram / Feishu` 中，用户默认面向的是 `project`，不是某台机器；设备离线时系统必须明确返回 `hub_only_status` 或 `xt_offline`。
- 在购物或外出任务中，本地执行面只负责动作执行和环境感知；预算、支付、授权、记忆、回滚与 kill-switch 继续由 Hub 管。

## 3) Architecture Stance

### 3.1 Hub Is The Supervisor Control Plane

`X-Hub` 固定持有以下职责：

- memory truth-source
- project / run / mission route truth
- risk classify / policy / grant / audit / budget / kill-switch truth
- connector secrets 与 paid provider credentials
- voice / channel / robot / XT ingress normalization

### 3.2 X-Terminal Is A Rich Surface And A Project-Scoped Local Execution Plane

`X-Terminal` 固定负责：

- local UI / voice I/O / TTS / microphone / presence
- project-scoped orchestration view
- 受 Hub 许可的本地工具与 `device.*` 执行桥
- 与 local runner / permission owner 的同机受控通信

它不是：

- grant source-of-truth
- payment authority
- memory source-of-truth
- channel secret owner

### 3.3 Companion Surfaces Are Satellites, Not New Trust Anchors

未来 mobile / wearable companion 的职责应固定为：

- 接收 brief / challenge / alert / status snapshot
- 采集语音与用户二次确认
- 呈现 `Hub` 返回的 machine-readable state

它们不应成为：

- standalone agent runtime
- secrets vault
- policy override point

### 3.4 Embodied Automation Must Be Recipe-Bound, Not Free-Form

机器人、购物 runner、外出执行面不应理解为“会自己决定一切的 agent”。

正确模型是：

`goal -> manifest -> bounded recipe -> checkpoint -> challenge if needed -> execute -> audit -> memory`

## 4) Canonical Runtime Objects

为避免 voice / channel / robot 各长一套数据结构，建议新增并冻结以下跨 surface 机读对象：

1. `xhub.supervisor_surface_ingress.v1`
   - 统一承接 `voice / mobile / slack / telegram / feishu / whatsapp / xt-ui / robot event`
   - 固定字段：`surface_type`, `actor_ref`, `project_ref`, `raw_intent_ref`, `trust_level`, `request_id`
2. `xhub.supervisor_brief_projection.v1`
   - 从 Hub memory / heartbeat / run-state 投影的“可口头播报、可卡片显示、可通道推送”的统一摘要
   - 固定字段：`project_id`, `run_id`, `status`, `critical_blocker`, `next_best_action`, `evidence_refs`
3. `xhub.supervisor_route_decision.v1`
   - 固定路由结果：`hub_only | hub_to_xt | hub_to_runner`
   - 同时带上 `preferred_device_id`, `runner_required`, `same_project_scope`, `deny_code`
4. `xhub.supervisor_guidance_resolution.v1`
   - 把用户指导统一编译成结构化 directive，绑定到 `project/run/pool/lane/mission`
5. `xhub.supervisor_checkpoint_challenge.v1`
   - 统一表示高风险节点：支付、外部副作用、scope expansion、remote posture 降级、预算超限

冻结锚点：

- `docs/memory-new/xhub-multimodal-supervisor-control-plane-contract-freeze-v1.md`
- `docs/memory-new/schema/xhub_multimodal_supervisor_control_plane_contract.v1.json`

这些对象都应该写 machine-readable audit，并只把必要结构化结果写入记忆系统。

## 5) How X-Hub Memory Becomes The Differentiator

这套系统真正的护城河不是“支持语音”或“支持 Slack”，而是 `x-hub` 记忆系统让所有 surface 都消费同一份 continuity。

建议把记忆系统优先投影成四类 Supervisor 运营视图：

1. `progress brief`
   - 适合耳机 TTS、IM heartbeat、mobile digest
2. `pending grants digest`
   - 适合主动提醒“现在卡在哪个授权”
3. `next best action`
   - 适合语音问答、channel `/next`, project cockpit
4. `mission / shopping checkpoint ledger`
   - 适合 embodied task 的阶段边界、证据与回滚

原则：

- raw audio、外部附件、第三方链接默认不进 canonical memory
- 进入长期记忆的是结构化事实、决策、风险、授权摘要和证据引用
- 不同 surface 只消费 projection，不各自拼第二套真相源

## 6) Three Reference Flows

### 6.1 Outdoor Earbuds

`heartbeat -> brief projection -> presence / quiet-hours gate -> TTS -> user voice guidance -> structured directive -> Hub route -> audit -> memory`

高风险授权分支：

`voice request -> challenge issued by Hub -> mobile confirm if required -> verify -> decision -> audit`

### 6.2 Operator Channels

`IM ingress -> identity bind -> project-first route -> structured action -> policy / grant -> hub_only | hub_to_xt | hub_to_runner -> delivery job`

### 6.3 Shopping / Robot Pilot

`shopping goal -> manifest -> recipe steps -> local sensing / runner action -> checkpoint -> budget / payment / substitution challenge -> execution -> evidence -> memory`

## 7) Hard Boundaries

- 不允许任何 surface 直接把自然语言映射到 `terminal.exec`、`device.*`、`connector.send`、`grant.approve`。
- 不允许把 raw audio 作为长期记忆正文；默认只保留结构化意图、hash、审计摘要。
- 不允许把 mobile companion、IM bot、robot runner 做成新的 trust anchor。
- 不允许设备离线、权限缺失、remote posture 不达标时伪成功。
- 不允许高风险 `voice-only` 作为默认主链；默认必须支持 `voice + mobile` 双通道。
- 不允许把 embodied automation 做成“无 manifest、无 checkpoint、无预算上限”的自由运行。

## 8) Recommended v1 Product Slice

为了效率和安全，v1 先不做“完全自主购物机器人”，而做下面这个可控收口：

1. 一个统一的 `Hub Supervisor Facade`
2. 一个轻量 `mobile / wearable companion`，承接户外耳机场景
3. 一个统一的 `brief / pending grant / next action` projection 层
4. `Slack / Telegram / Feishu` 与语音共用同一条 structured-action 主链
5. 一个“购物 copilot / 受控 runner”试点：
   - 找货
   - 条码 / 图片比对
   - 替代品建议
   - 超预算停下
   - 支付必须 challenge

## 9) Success Criteria

- 用户感知上只有一个 `Supervisor`，而不是若干个彼此不同步的入口。
- `voice / IM / XT / runner` 的状态、授权和记忆不再分叉。
- 高风险动作在所有 surface 上都走同一条 Hub-first 主链。
- 项目 continuity 真正来自 `x-hub` 记忆投影，而不是客户端临时上下文拼装。
- embodied 场景先以 bounded recipe 成功，再逐步扩大自动化面。
