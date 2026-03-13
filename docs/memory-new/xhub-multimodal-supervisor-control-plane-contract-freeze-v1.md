# X-Hub Multimodal Supervisor Control Plane Contract Freeze v1

- version: v1.0
- frozenAt: 2026-03-13
- owner: Hub-L5 / XT-L2 / Mobile-L1 / Security / QA
- status: frozen
- scope: `MMS-W1` / `MMS-W2` contract-only（surface ingress + route decision + brief projection + guidance resolution + checkpoint challenge）
- machine-readable contract: `docs/memory-new/schema/xhub_multimodal_supervisor_control_plane_contract.v1.json`
- related:
  - `docs/memory-new/xhub-multimodal-supervisor-control-plane-architecture-memo-v1.md`
  - `docs/memory-new/xhub-multimodal-supervisor-control-plane-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
  - `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - `protocol/hub_protocol_v1.md`
  - `protocol/hub_protocol_v1.proto`

## 0) 目标与边界

目标：把多模态 `Supervisor` 主链最容易漂移的对象先冻结成单一事实源，避免 voice / channel / mobile / runner 各长一套 envelope、route、brief、challenge 语义。

统一执行链冻结为：

`ingress -> identity_bind -> normalize -> project_bind -> risk_classify -> route_decide -> policy -> grant -> execute -> audit -> memory_project`

本冻结覆盖：

- `xhub.supervisor_surface_ingress.v1`
- `xhub.supervisor_route_decision.v1`
- `xhub.supervisor_brief_projection.v1`
- `xhub.supervisor_guidance_resolution.v1`
- `xhub.supervisor_checkpoint_challenge.v1`
- 核心 `surface_type` / `trust_level` / `intent_type` / `route_decision` / `deny_code` 字典

本冻结不覆盖：

- UI 文案与视觉样式
- ASR / TTS 引擎选型
- mobile companion 的具体产品壳形态
- shopping mission 的业务枚举细节
- provider SDK / bot SDK 的适配实现

## 1) 架构边界冻结

### 1.1 Hub-first 边界

- 所有 surface 输入先进入 `Hub Supervisor Facade`。
- `Hub` 是以下事实的唯一真相源：
  - memory truth
  - route decision
  - grant / policy / audit / kill-switch / budget
  - connector secrets
- `X-Terminal`、mobile companion、IM channels、runner 都不是新的 trust anchor。

### 1.2 Project-first 边界

- 默认主对象必须是 `project`。
- `device` 只允许在以下场景成为主对象：
  - doctor
  - permission readiness
  - trusted automation diagnostics
  - explicit preferred-device inspection
- 若 surface 请求无法绑定到 project，默认 `fail_closed` 或降级成 `hub_only status`，不得伪造 `hub_to_xt` / `hub_to_runner` 成功。

### 1.3 Natural Language Never Jumps Straight To Side Effects

以下动作必须先变成结构化对象，再走 policy / grant / audit：

- `terminal.exec`
- `device.*`
- `connector.send`
- `grant.approve`
- `payment.*`

未结构化前，不得直接执行。

## 2) 枚举冻结

### 2.1 `surface_type`

- `xt_ui`
- `xt_voice`
- `mobile_companion`
- `wearable_companion`
- `slack`
- `telegram`
- `feishu`
- `whatsapp_cloud_api`
- `whatsapp_personal_runner`
- `runner_event`
- `hub_internal`

说明：

- `whatsapp_personal_runner` 仅表示“本机会话经 trusted runner 接入”，不表示其可直接越过 Hub。
- `runner_event` 仅表示本地执行面上报 observation / checkpoint / result，不等于它拥有 grant 权。

### 2.2 `trust_level`

- `trusted_local_surface`
- `paired_surface`
- `external_untrusted_ingress`
- `runner_observation`
- `hub_internal`

冻结规则：

- `slack / telegram / feishu / whatsapp_*` 默认 `external_untrusted_ingress`
- `xt_ui / xt_voice` 默认 `paired_surface`
- `runner_event` 默认 `runner_observation`
- `hub_internal` 仅允许 Hub 自身 heartbeat / scheduler / policy paths 使用

### 2.3 `normalized_intent_type`

- `progress_query`
- `directive`
- `authorization_request`
- `approval_card_action`
- `mission_checkpoint`
- `status_ack`
- `help`
- `cancel`
- `unknown`

冻结规则：

- `unknown` 默认 `fail_closed` 或转人工澄清，不允许隐式升级成 directive / authorization。

### 2.4 `route_decision`

- `hub_only`
- `hub_to_xt`
- `hub_to_runner`
- `fail_closed`

冻结规则：

- `hub_only`：只返回状态 / 摘要 / 建议，不依赖 XT 或 runner 在线。
- `hub_to_xt`：需要 XT 的 project-scoped runtime 或 UI state。
- `hub_to_runner`：需要 trusted automation 执行面，本地 device / robot / embodied side effect 经此路径。
- `fail_closed`：目标、身份、授权、姿态或边界不成立，默认拒绝。

### 2.5 `projection_kind`

- `progress_brief`
- `pending_grants_digest`
- `next_best_action`
- `mission_checkpoint_digest`

### 2.6 `guidance_type`

- `priority_shift`
- `scope_narrow`
- `scope_hold`
- `resume_lane`
- `pause_lane`
- `delivery_mode_change`
- `budget_change_request`
- `mission_replan_request`

### 2.7 `checkpoint_type`

- `payment`
- `substitution`
- `budget_exceed`
- `scope_expansion`
- `external_side_effect`
- `remote_posture_drop`
- `geofence_exit`

## 3) Object Freeze

### 3.1 `xhub.supervisor_surface_ingress.v1`

用途：

- 统一承接语音、IM、mobile companion、runner event、XT UI 入口。

最小字段：

- `schema_version`
- `ingress_id`
- `request_id`
- `surface_type`
- `surface_instance_id`
- `actor_ref`
- `project_id`
- `run_id`
- `trust_level`
- `normalized_intent_type`
- `raw_intent_ref`
- `received_at_ms`
- `audit_ref`

可选字段：

- `conversation_id`
- `thread_key`
- `preferred_device_id`
- `mission_id`
- `structured_action_ref`

冻结规则：

- `project_id` 为空时，只允许 `help`、`status_ack` 或 `hub_only` 可解析查询进入下一步；其余默认 fail-closed。
- 外部 IM 附件、链接、按钮回调全部先转成 `raw_intent_ref`，不得直接写 canonical memory。
- `surface_type + surface_instance_id + request_id` 共同构成幂等追踪键。

示例：

```json
{
  "schema_version": "xhub.supervisor_surface_ingress.v1",
  "ingress_id": "ing-20260313-001",
  "request_id": "req-20260313-001",
  "surface_type": "slack",
  "surface_instance_id": "ops-slack-bot",
  "actor_ref": "xhub.im_identity_binding.v1:slack/U123",
  "project_id": "payments-prod",
  "run_id": "run-xt-001",
  "trust_level": "external_untrusted_ingress",
  "normalized_intent_type": "authorization_request",
  "raw_intent_ref": "local://supervisor-ingress/ing-20260313-001.json",
  "received_at_ms": 1760000000000,
  "audit_ref": "audit-ingress-001"
}
```

### 3.2 `xhub.supervisor_route_decision.v1`

用途：

- 冻结 `hub_only / hub_to_xt / hub_to_runner / fail_closed` 的统一裁决结果。

最小字段：

- `schema_version`
- `route_id`
- `request_id`
- `project_id`
- `decision`
- `risk_tier`
- `xt_online`
- `runner_required`
- `same_project_scope`
- `requires_grant`
- `deny_code`
- `audit_ref`

可选字段：

- `preferred_device_id`
- `bound_device_id`
- `runner_id`
- `mission_id`
- `grant_scope`

冻结规则：

- `decision=hub_to_runner` 时，`runner_required=true` 必须为真。
- `decision=hub_to_xt` 或 `hub_to_runner` 时，`same_project_scope=true` 必须为真；否则 `fail_closed`。
- `xt_online=false` 时不得返回伪成功；只能 `hub_only` 或 `fail_closed`。
- `deny_code=none` 仅允许在非 fail 路径出现。

示例：

```json
{
  "schema_version": "xhub.supervisor_route_decision.v1",
  "route_id": "route-20260313-001",
  "request_id": "req-20260313-001",
  "project_id": "payments-prod",
  "decision": "hub_to_xt",
  "risk_tier": "high",
  "preferred_device_id": "xt-mini-bj-01",
  "xt_online": true,
  "runner_required": false,
  "same_project_scope": true,
  "requires_grant": true,
  "deny_code": "none",
  "audit_ref": "audit-route-001"
}
```

### 3.3 `xhub.supervisor_brief_projection.v1`

用途：

- 统一 voice TTS、mobile card、IM heartbeat、XT cockpit 的摘要输入。

最小字段：

- `schema_version`
- `projection_id`
- `projection_kind`
- `project_id`
- `run_id`
- `status`
- `topline`
- `next_best_action`
- `evidence_refs`
- `generated_at_ms`
- `audit_ref`

可选字段：

- `critical_blocker`
- `pending_grant_count`
- `mission_id`
- `tts_script`
- `card_summary`
- `expires_at_ms`

冻结规则：

- 所有 brief projection 都必须带 `evidence_refs`。
- 若 `projection_kind=pending_grants_digest`，`pending_grant_count` 必须存在。
- 不允许把 raw audio transcript、外部附件正文或未脱敏链接直接塞入 brief。

示例：

```json
{
  "schema_version": "xhub.supervisor_brief_projection.v1",
  "projection_id": "brief-20260313-001",
  "projection_kind": "progress_brief",
  "project_id": "phoenix",
  "run_id": "run-001",
  "status": "blocked",
  "critical_blocker": "grant_pending",
  "topline": "Phoenix is blocked on remote model authorization.",
  "next_best_action": "approve_once_or_downgrade_to_local",
  "tts_script": [
    "Phoenix is blocked on remote model authorization.",
    "The safest next step is to approve once or downgrade to local."
  ],
  "evidence_refs": [
    "local://brief-evidence/brief-20260313-001.json"
  ],
  "generated_at_ms": 1760000000500,
  "audit_ref": "audit-brief-001"
}
```

### 3.4 `xhub.supervisor_guidance_resolution.v1`

用途：

- 把用户的语音 / IM / UI 指导统一编译成结构化 directive。

最小字段：

- `schema_version`
- `directive_id`
- `request_id`
- `project_id`
- `run_id`
- `guidance_type`
- `normalized_instruction`
- `target_scope`
- `requires_confirmation`
- `requires_authorization`
- `resolution`
- `deny_code`
- `audit_ref`

`target_scope` 冻结字段：

- `scope_type`
- `pool_id`
- `lane_id`
- `mission_id`

冻结规则：

- `resolution=confirmed` 前，directive 不得写入 orchestrator 主链。
- scope expansion、delivery freeze override、project 指向不清时必须 fail-closed。
- `mission_id` 仅在 embodied / shopping 场景可选出现，不改变 `project-first` 原则。

示例：

```json
{
  "schema_version": "xhub.supervisor_guidance_resolution.v1",
  "directive_id": "dir-20260313-001",
  "request_id": "req-20260313-002",
  "project_id": "phoenix",
  "run_id": "run-001",
  "guidance_type": "scope_hold",
  "normalized_instruction": "hold ipad scope and keep backend first",
  "target_scope": {
    "scope_type": "lane",
    "pool_id": "xt-main",
    "lane_id": "XT-W3-26-E"
  },
  "requires_confirmation": true,
  "requires_authorization": false,
  "resolution": "confirmed",
  "deny_code": "none",
  "audit_ref": "audit-guidance-001"
}
```

### 3.5 `xhub.supervisor_checkpoint_challenge.v1`

用途：

- 统一表示高风险 checkpoint：支付、替代品、超预算、scope expansion、外部副作用、姿态下降。

最小字段：

- `schema_version`
- `challenge_id`
- `request_id`
- `project_id`
- `checkpoint_type`
- `risk_tier`
- `decision_path`
- `state`
- `scope_digest`
- `evidence_refs`
- `audit_ref`

可选字段：

- `mission_id`
- `amount_digest`
- `requires_mobile_confirm`
- `bound_device_id`
- `expires_at_ms`
- `deny_code`

冻结规则：

- `risk_tier=high|critical` 时，默认 `requires_mobile_confirm=true`。
- `decision_path=voice_only` 只允许低风险；高风险必须返回 `voice_plus_mobile`、`approval_card` 或 `manual_review`。
- `payment` challenge 默认要求 `amount_digest`。
- `state=verified` 只能由 Hub challenge / verify 主链写入。

示例：

```json
{
  "schema_version": "xhub.supervisor_checkpoint_challenge.v1",
  "challenge_id": "chk-20260313-001",
  "request_id": "req-20260313-003",
  "project_id": "shopping-berlin",
  "mission_id": "mission-001",
  "checkpoint_type": "payment",
  "risk_tier": "critical",
  "decision_path": "voice_plus_mobile",
  "state": "pending",
  "scope_digest": "buy-listed-items-only",
  "amount_digest": "max-89.00-eur",
  "requires_mobile_confirm": true,
  "evidence_refs": [
    "local://mission-checkpoints/chk-20260313-001.json"
  ],
  "audit_ref": "audit-challenge-001"
}
```

## 4) deny_code Dictionary Freeze

| deny_code | stage | frozen meaning | action | retryable |
| --- | --- | --- | --- | --- |
| `none` | any success path | no denial applied | allow | n/a |
| `identity_unbound` | `identity_bind` | IM / companion / surface actor 未绑定到 Hub principal | `fail_closed` | yes |
| `project_not_bound` | `project_bind` | 无法安全绑定到 project scope | `fail_closed` | yes |
| `ambiguous_target` | `normalize/project_bind` | 指令或授权目标不清 | `fail_closed` | yes |
| `scope_expansion_detected` | `normalize/policy` | guidance 或 action 导致 scope 变大 | `fail_closed` | no |
| `xt_offline` | `route_decide` | 需要 XT 但目标 XT 不在线 | `hub_only` or `fail_closed` | yes |
| `runner_not_ready` | `route_decide` | 需要 runner 但本地执行面未 ready | `fail_closed` | yes |
| `trusted_automation_project_not_bound` | `route_decide/grant` | project 未绑定 trusted automation profile | `fail_closed` | yes |
| `remote_posture_insufficient` | `route_decide/policy` | remote 姿态不满足 trusted path 要求 | `fail_closed` | yes |
| `grant_required` | `grant` | 需要授权但当前未放行 | `fail_closed` | yes |
| `voice_only_not_allowed` | `grant` | 高风险动作不能只靠语音批准 | `fail_closed` | yes |
| `policy_denied` | `policy` | 策略明确拒绝 | `fail_closed` | maybe |
| `challenge_expired` | `grant` | checkpoint / voice challenge 超时 | `fail_closed` | yes |
| `device_not_bound` | `grant/execute` | challenge 或 route 中设备绑定不成立 | `fail_closed` | yes |
| `runtime_error` | `execute` | 执行链路异常 | `fail_closed` | yes |

冻结规则：

- 未识别 deny_code 默认视为 `runtime_error` 级别 fail-closed，不得默认为 allow。
- 所有 deny path 必须同时输出 machine-readable `deny_code` 与人话解释。

## 5) 审计与记忆边界冻结

### 5.1 审计最小字段

以下对象最少必须带：

- `request_id`
- `project_id`
- `audit_ref`
- `schema_version`

若为 fail path，还必须带：

- `deny_code`

### 5.2 记忆写入边界

- 允许写入长期记忆：
  - 结构化 directive
  - brief 摘要
  - challenge 结果摘要
  - mission checkpoint 结果
  - evidence 引用
- 默认不写入 canonical / longterm：
  - raw audio
  - 外部附件正文
  - 外部链接原文
  - 未脱敏 transcript

## 6) Change Control

- 本文件是 `MMS-W1 / MMS-W2` 的冻结记录。
- 以下变更必须 `v1 -> v2`：
  - 删除或重命名对象
  - 改变 `route_decision` 语义
  - 改变高风险 challenge 默认路径
  - 把 fail-closed 放宽成 fail-open
- 仅新增可选字段时，可做 `v1.x` 增补，但必须同步更新 machine-readable contract 文件。

## 7) Machine-check

```bash
node ./scripts/mms_check_supervisor_control_plane_contract.js \
  --out-json ./build/mms_supervisor_control_plane_contract_report.json

node ./scripts/mms_check_supervisor_control_plane_contract.test.js
```

最小门禁目标：

- `freeze doc -> contract json -> proto -> protocol md` 四层零漂移
- `HubSupervisor` service 与 5 个核心 RPC 必须存在
- 关键 `deny_code` 与 `route_decision` 字典缺失时必须 fail
