# XT-W3-29 Supervisor 语音进度汇报 + 语音指导授权实现子工单包

- version: v1.0
- updatedAt: 2026-03-10
- owner: XT-L2（Primary）/ Hub-L5 / XT-L1 / QA / AI-COORD-PRIMARY
- status: active
- scope: `XT-W3-29`（Supervisor Voice Progress + Guided Authorization）+ `XT-W3-29-A/B/C/D/E/F`
- parent:
  - `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-supervisor-rhythm-user-explainability-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-29-whisperkit-funasr-voice-runtime-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-29-supervisor-conversation-window-persistent-session-implementation-pack-v1.md`
  - `docs/xhub-scenario-map-v1.md`
  - `protocol/hub_protocol_v1.md`
  - `docs/memory-new/xhub-memory-v3-execution-plan.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## 0) 为什么要有这份包

当前 Supervisor 已经具备这些关键基础：

- heartbeat / lane health / blocker state 可机读
- pool / lane / critical path / directed unblock 已可编排
- Acceptance Pack / delivery summary 已可收口
- XT 侧已经存在基础语音输入组件：`x-terminal/Sources/UI/VoiceInputView.swift`
- Hub 侧已经存在高风险动作语音授权基础：`IssueVoiceGrantChallenge / VerifyVoiceGrantResponse`

但系统还缺最后一层产品化闭环：

- Supervisor 还不能在 `blocked / completed / awaiting_authorization / critical-path change` 时主动用语音向用户汇报
- 用户还不能直接用语音问“现在进度怎样了”
- 用户还不能用语音给方向指导，例如“先做后端，暂停 iPad 范围”
- 用户还不能把语音和授权链打通成一个统一入口
- 还没有“唤醒词 / 提示词唤醒 + 语音会话 + TTS 回报 + fail-closed 授权边界”这一条完整主链

本包的目标，就是把这些已有能力收敛成一个真正可用的 `voice supervisor loop`：

- Supervisor 能主动汇报
- 用户能主动问
- 用户能语音下方向
- 用户能语音授权，但高风险授权仍必须保持双通道与 fail-closed
- 用户能通过唤醒词或提示词进入 Supervisor 语音回路

## 1) 目标与硬边界

### 1.1 目标

- 在当前项目发生 `blocked / completed / awaiting_authorization / critical_path_changed` 时，Supervisor 自动用语音汇报项目进度。
- 用户可随时通过唤醒词或提示词唤醒 Supervisor，主动查询项目状态、blocker、下一步建议、交付进度。
- 用户可通过语音给出方向指导，并把指导绑定到当前项目、当前 run、当前 pool/lane 或当前 blocker。
- 用户可通过语音处理授权链，但授权必须继续服从 Hub grant / policy / audit / fail-closed。
- 语音输出不是闲聊，而是基于 heartbeat、run state、acceptance、memory bus 的可追溯项目状态。

### 1.2 硬边界

- 不允许把语音识别结果直接当作高风险不可逆动作的最终批准结果；高风险动作必须继续走 Hub 侧语音授权主链，且默认 `voice + mobile` 双通道。
- 不允许因为“语音体验”绕过 `grant`, `policy`, `scope`, `audit`, `delivery freeze`。
- 不允许自动语音播报失控刷屏；必须有 dedupe、quiet hours、active-project-only、cooldown。
- 不允许把 raw audio 作为 Hub 长期记忆或常规审计内容；默认只保留结构化意图、必要文本摘录、审计摘要。
- 不允许在意图歧义、项目指向不清、范围可能扩张时自动执行指导；必须降级为确认或 fail-closed。
- 不允许把语音场景包装成当前 validated public release claim；它属于 roadmap/productization lane。

## 2) 用户主路径

### 2.1 主动播报

触发源：

- 当前项目进入 `blocked`
- 当前项目恢复关键 blocker
- 当前项目进入 `awaiting_authorization`
- 当前项目达成阶段性完成或最终完成
- 关键路径切换导致用户应当知道“现在该看哪个项目”

预期体验：

- Supervisor 自动播报一句短语音
- 同时在 UI 中落一条 voice timeline 卡片
- 用户可立刻打断继续问，也可忽略

### 2.2 被动问答

用户示例：

- “Supervisor，现在 Phoenix 项目进度怎样？”
- “Supervisor，哪些 lane 卡住了？”
- “Supervisor，下一个关键解阻点是什么？”
- “Supervisor，今天给我一个交付摘要。”

预期体验：

- 唤醒后进入一次短会话
- Supervisor 先基于 heartbeat / run state / acceptance / memory bus 生成简短口头汇报
- 若用户继续追问，再按最小必要上下文追加说明

### 2.3 方向指导

用户示例：

- “Supervisor，先保主线，暂停 iPad 范围。”
- “Supervisor，把 API 修完再做 UI。”
- “Supervisor，这个 blocker 不要升级到 release blocker，先走降级方案。”

预期体验：

- 系统先识别成结构化 directive
- 明确绑定：`project + run + target_scope + action`
- 若歧义，先复述确认
- 确认后回填到 orchestrator / run state / memory bus / directed baton

### 2.4 语音授权

用户示例：

- “Supervisor，批准这次 remote fetch。”
- “Supervisor，这次先临时放行。”
- “Supervisor，允许支付这单。”

预期体验：

- 低风险或 scope-safe 授权：可在语音确认后生成结构化授权请求
- 高风险动作：必须转入 Hub `IssueVoiceGrantChallenge / VerifyVoiceGrantResponse`
- 若风险高到 `voice-only` 不允许，则强制升级为双通道

### 2.5 唤醒方式

支持三种模式：

- `push_to_talk`
- `wake_phrase`
- `prompt_phrase_only`

示例唤醒词 / 提示词：

- `Supervisor`
- `Hey Supervisor`
- `汇报一下`
- `给我项目进度`

## 3) 机读契约冻结

### 3.1 `xt.supervisor_voice_wake_profile.v1`

```json
{
  "schema_version": "xt.supervisor_voice_wake_profile.v1",
  "user_id": "local-user",
  "enabled": true,
  "wake_mode": "push_to_talk|wake_phrase|prompt_phrase_only",
  "wake_phrases": ["Supervisor", "Hey Supervisor", "汇报一下"],
  "language": "zh-CN",
  "active_project_only": true,
  "quiet_hours": {
    "enabled": true,
    "from_local": "22:00",
    "to_local": "08:00"
  },
  "auto_report_enabled": true,
  "authorization_mode": "voice_query_only|voice_guidance|voice_guidance_plus_auth",
  "audit_ref": "audit-xxxx"
}
```

### 3.2 `xt.supervisor_voice_progress_brief.v1`

```json
{
  "schema_version": "xt.supervisor_voice_progress_brief.v1",
  "project_id": "uuid",
  "run_id": "uuid",
  "trigger": "user_query|blocked|completed|awaiting_authorization|critical_path_changed|daily_digest",
  "summary_level": "short|standard|full",
  "topline": "Project Phoenix is blocked on paid model authorization.",
  "status": "running|blocked|completed|awaiting_authorization|hold",
  "critical_blocker": "grant_pending",
  "next_action": "approve_remote_model_once_or_downgrade_to_local",
  "voice_script": [
    "Phoenix is currently blocked on remote model authorization.",
    "The safest next step is to approve once or downgrade to local."
  ],
  "evidence_refs": [
    "build/reports/xt_w3_29_voice_progress_brief.v1.json"
  ],
  "audit_ref": "audit-xxxx"
}
```

### 3.3 `xt.supervisor_voice_directive.v1`

```json
{
  "schema_version": "xt.supervisor_voice_directive.v1",
  "project_id": "uuid",
  "run_id": "uuid",
  "directive_id": "uuid",
  "directive_type": "priority_shift|scope_narrow|scope_hold|resume_lane|pause_lane|delivery_mode_change|budget_change_request",
  "target_scope": {
    "pool_id": "xt-main",
    "lane_id": "XT-W3-26-E"
  },
  "normalized_instruction": "backend first, hold ipad scope",
  "requires_confirmation": true,
  "requires_authorization": false,
  "decision": "pending|confirmed|rejected|fail_closed",
  "deny_code": "none|ambiguous_target|scope_expansion_detected|authorization_required",
  "audit_ref": "audit-xxxx"
}
```

### 3.4 `xt.supervisor_voice_authorization_resolution.v1`

```json
{
  "schema_version": "xt.supervisor_voice_authorization_resolution.v1",
  "project_id": "uuid",
  "request_id": "uuid",
  "authorization_type": "grant_extension|tool_execute|remote_fetch|payment|external_side_effect",
  "risk_tier": "low|medium|high|critical",
  "voice_only_allowed": false,
  "hub_voice_challenge_required": true,
  "challenge_id": "uuid",
  "resolution": "pending|verified|denied|downgraded",
  "deny_code": "none|voice_only_not_allowed|challenge_expired|identity_mismatch|policy_denied",
  "audit_ref": "audit-xxxx"
}
```

### 3.5 `xt.supervisor_voice_session_state.v1`

```json
{
  "schema_version": "xt.supervisor_voice_session_state.v1",
  "session_id": "uuid",
  "state": "idle|listening|transcribing|intent_classified|awaiting_confirmation|awaiting_hub_voice_challenge|speaking|completed|fail_closed",
  "recognized_text": "string",
  "intent": "progress_query|direction_guidance|authorization_request|cancel|help",
  "project_binding": "uuid",
  "run_binding": "uuid",
  "last_brief_id": "uuid",
  "last_updated_at_ms": 0
}
```

### 3.6 `xt.supervisor_voice_auto_report_policy.v1`

```json
{
  "schema_version": "xt.supervisor_voice_auto_report_policy.v1",
  "enabled": true,
  "report_reasons": [
    "blocked",
    "awaiting_authorization",
    "critical_path_changed",
    "completed"
  ],
  "cooldown_sec": 120,
  "dedupe_window_sec": 300,
  "summary_level": "short",
  "speak_only_when_user_present": true,
  "suppress_during_quiet_hours": true,
  "audit_ref": "audit-xxxx"
}
```

## 4) 状态机

主状态机：

`idle -> listening -> transcribing -> intent_classified -> speaking -> completed`

方向指导分支：

`intent_classified -> awaiting_confirmation -> confirmed -> orchestrator_bound -> speaking -> completed`

授权分支：

`intent_classified -> awaiting_hub_voice_challenge -> verified|denied -> speaking -> completed`

自动播报分支：

`heartbeat_triggered -> brief_compiled -> policy_check -> speaking -> completed`

异常分支：

- `intent_classified -> fail_closed`
- `awaiting_confirmation -> timeout -> fail_closed`
- `awaiting_hub_voice_challenge -> challenge_expired -> fail_closed`
- `brief_compiled -> dedupe_suppressed`

## 5) 产品交互草图

### 5.1 Supervisor Cockpit

新增区块：

- `Voice Status Chip`
  - `idle / listening / speaking / awaiting_auth / quiet_hours`
- `Auto Report`
  - `on/off`
  - `blocked only / blocked + completed / full`
- `Wake Mode`
  - `push-to-talk / wake phrase / prompt phrase only`
- `Quiet Hours`
  - 时间窗口
- `Last Voice Brief`
  - 最近一次播报摘要

### 5.2 主动播报样例

场景：项目进入 blocker

1. heartbeat 发现 `status=blocked`
2. `SupervisorVoiceBriefBuilder` 生成简报
3. 若通过 dedupe / quiet-hours / presence policy
4. TTS 播报：
   - “Supervisor update. Phoenix is blocked on remote model authorization. Recommended next step: approve once or downgrade to local.”
5. UI 同步落卡片：
   - `trigger=blocked`
   - `project=Phoenix`
   - `next_action=approve_once_or_downgrade`

### 5.3 用户主动询问样例

用户：

- “Supervisor，现在 Atlas 怎么样？”

系统：

- “Atlas is running. Two lanes are active. One blocker remains on integration tests. The next critical step is pool merge verification.”

继续追问：

- “哪个 lane 卡住了？”

系统：

- “Lane XT-W3-18-S1 is waiting on global integration verification.”

### 5.4 方向指导样例

用户：

- “Supervisor，先保主线，暂停 iPad 范围。”

系统第一次回显：

- “I heard: keep the mainline, hold iPad scope. Apply this to project Phoenix only. Confirm?”

用户：

- “确认。”

系统：

- “Confirmed. I updated project Phoenix to mainline-first with iPad scope on hold.”

### 5.5 授权样例

低风险例子：

- 用户：“Supervisor，批准这次 remote fetch。”
- 系统：“Approve one remote fetch for Phoenix current run only. Confirm?”
- 用户：“确认。”
- 系统：生成结构化授权请求并写审计

高风险例子：

- 用户：“Supervisor，允许支付这单。”
- 系统：“This action requires dual-channel authorization. I have issued a voice challenge and sent a mobile confirmation.”
- 若验证成功：落 `verified`
- 若失败或超时：`fail_closed`

### 5.6 唤醒词样例

- “Supervisor”
- “Hey Supervisor”
- “汇报一下”
- “给我项目进度”

规则：

- 唤醒后只开一个短窗口
- 若连续追问，则复用当前 voice session
- 若长时间无回应，自动回到 `idle`

## 6) 专项 Gate / KPI

### 6.1 Gate

- `XT-VOICE-G0`：六类机读契约冻结完成。
- `XT-VOICE-G1`：wake / transcribe / intent classify / project bind 主链通过。
- `XT-VOICE-G2`：heartbeat / blocker / completion / authorization trigger 可正确生成 voice brief，且 dedupe 生效。
- `XT-VOICE-G3`：方向指导可绑定到项目与 run，不发生 silent scope expansion。
- `XT-VOICE-G4`：语音授权与 Hub challenge 主链打通，高风险 `voice-only` 绕过次数为零。
- `XT-VOICE-G5`：Voice timeline、quiet hours、回放、用户可解释输出、审计与隐私边界全部齐备。

### 6.2 KPI

- `wake_to_transcript_p95_ms <= 2500`
- `heartbeat_to_voice_brief_p95_ms <= 2000`
- `false_wake_rate_per_hour <= 0.05`
- `auto_report_duplicate_leak = 0`
- `voice_directive_binding_accuracy >= 0.95`
- `silent_scope_expansion_by_voice = 0`
- `high_risk_voice_only_bypass = 0`
- `raw_audio_persisted_to_hub = 0`
- `user_interrupt_recovery_p95_ms <= 1000`

## 7) 子工单分解

### 7.1 `XT-W3-29-A` Voice Wake Phrase + Session Router

- 目标：把 `VoiceInputView` 从通用 STT 组件提升为 Supervisor 专用语音入口，支持 `push_to_talk / wake_phrase / prompt_phrase_only`。
- 交付物：`build/reports/xt_w3_29_a_voice_wake_router_evidence.v1.json`

### 7.2 `XT-W3-29-B` Heartbeat Digest + Auto Report Trigger

- 目标：把 heartbeat / run state / lane health / delivery summary 收敛成可去重的主动播报触发器。
- 交付物：`build/reports/xt_w3_29_b_voice_auto_report_evidence.v1.json`

### 7.3 `XT-W3-29-C` Progress Brief Builder + TTS Delivery

- 目标：生成适合口头播报的短摘要，并通过本地 TTS 输出。
- 交付物：`build/reports/xt_w3_29_c_voice_progress_brief_evidence.v1.json`

### 7.4 `XT-W3-29-D` Voice Guidance Intent Router + Directive Binder

- 目标：把用户语音方向指导转成结构化 directive，并安全绑定到项目/run/pool/lane。
- 交付物：`build/reports/xt_w3_29_d_voice_directive_binding_evidence.v1.json`

### 7.5 `XT-W3-29-E` Voice Authorization Bridge

- 目标：把语音授权请求接到 Hub `IssueVoiceGrantChallenge / VerifyVoiceGrantResponse` 主链上。
- 交付物：`build/reports/xt_w3_29_e_voice_authorization_bridge_evidence.v1.json`

### 7.6 `XT-W3-29-F` Voice Timeline UX + Quiet Hours + Replay

- 目标：把语音会话、主动播报、确认、失败闭锁、回放与静默时段做成可见产品面。
- 交付物：`build/reports/xt_w3_29_f_voice_timeline_ux_evidence.v1.json`

## 8) 任务级执行包

### 8.1 `XT-W3-29-A` Voice Wake Phrase + Session Router

- 目标：把语音输入从“按下按钮收一段文本”升级为“Supervisor voice session”。
- 详细窗口/常驻会话落地见：
  - `x-terminal/work-orders/xt-w3-29-supervisor-conversation-window-persistent-session-implementation-pack-v1.md`
- 代码落点：
  - `x-terminal/Sources/UI/VoiceInputView.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - 新增建议：
    - `x-terminal/Sources/Supervisor/SupervisorVoiceCoordinator.swift`
    - `x-terminal/Sources/Supervisor/SupervisorVoiceIntentRouter.swift`
- DoR：
  - 现有 `VoiceInputManager` 可稳定输出 `recognizedText`
  - Supervisor 当前已有项目、lane、run state 真相源
- 实施子步骤：
  1. 落地 `SupervisorVoiceCoordinator`，统一管理 `idle/listening/transcribing/speaking`。
  2. 为 `VoiceInputManager` 增加 wake phrase / prompt phrase mode。
  3. 落地 `SupervisorVoiceIntentRouter`，分类 `progress_query|direction_guidance|authorization_request|cancel|help`。
  4. 绑定当前项目解析：优先 `active project`，其次 `recently spoken project`，最后走 disambiguation。
  5. 产出机读证据：`build/reports/xt_w3_29_a_voice_wake_router_evidence.v1.json`
- DoD：
  - 用户可通过唤醒词进入 Supervisor 语音会话
  - 意图分类错误不会直接触发高风险操作
  - 歧义项目必须要求确认
- Gate/KPI：
  - Gate: `XT-VOICE-G0`, `XT-VOICE-G1`
  - KPI: `wake_to_transcript_p95_ms <= 2500`, `false_wake_rate_per_hour <= 0.05`
- 回归样例：
  - 唤醒成功但项目绑定错误 -> 失败
  - 非 Supervisor 词误触发执行意图 -> 失败
  - 同音歧义项目未确认直接绑定 -> 失败

### 8.2 `XT-W3-29-B` Heartbeat Digest + Auto Report Trigger

- 目标：让 Supervisor 基于 heartbeat 主动讲进度，而不是等用户点开看卡片。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `x-terminal/Sources/Supervisor/LaneRuntimeState.swift`
  - `x-terminal/Sources/Supervisor/CriticalPathSeatAllocator.swift`
  - `x-terminal/Sources/Supervisor/MemoryUXAdapter.swift`
- DoR：
  - heartbeat / lane health / directed unblock / one-shot run state 已可读
  - `SupervisorManager` 已有 dedupe / cooldown 基础
- 实施子步骤：
  1. 落地 `SupervisorVoiceAutoReportPolicyStore`
  2. 从 `blocked/completed/awaiting_authorization/critical_path_changed` 生成统一 trigger
  3. 引入 cooldown + dedupe + quiet hours + active-project-only
  4. 生成 `xt.supervisor_voice_progress_brief.v1`
  5. 产出机读证据：`build/reports/xt_w3_29_b_voice_auto_report_evidence.v1.json`
- DoD：
  - blocker / completion / awaiting auth 都能稳定生成播报摘要
  - 不会因 heartbeat 抖动重复刷屏
  - quiet hours 生效
- Gate/KPI：
  - Gate: `XT-VOICE-G2`
  - KPI: `heartbeat_to_voice_brief_p95_ms <= 2000`, `auto_report_duplicate_leak = 0`
- 回归样例：
  - 同一 blocker 连续 10 次 heartbeat 重复播报 -> 失败
  - quiet hours 中仍主动播报 -> 失败
  - 当前非 active project 乱入播报 -> 失败

### 8.3 `XT-W3-29-C` Progress Brief Builder + TTS Delivery

- 目标：输出可听、简短、可解释的口语化 Supervisor 汇报。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - 新增建议：
    - `x-terminal/Sources/Supervisor/SupervisorVoiceBriefBuilder.swift`
    - `x-terminal/Sources/Supervisor/SupervisorSpeechSynthesizer.swift`
- DoR：
  - 当前系统已有 `doctor summary`, `acceptance summary`, `lane summary`, `delivery summary` 文本基础
- 实施子步骤：
  1. 把 `lane health + run state + acceptance pack` 汇成 `short|standard|full`
  2. 输出 `voice_script[]`
  3. 接本地 TTS，支持 interrupt / replay
  4. UI 同步落 `Last Voice Brief` 与 `Voice Timeline`
  5. 产出机读证据：`build/reports/xt_w3_29_c_voice_progress_brief_evidence.v1.json`
- DoD：
  - 语音汇报不读内部字段垃圾值
  - 口头摘要与 UI 摘要一致
  - 用户可回放最近一次播报
- Gate/KPI：
  - Gate: `XT-VOICE-G2`, `XT-VOICE-G5`
  - KPI: `user_interrupt_recovery_p95_ms <= 1000`
- 回归样例：
  - TTS 读出内部 raw JSON -> 失败
  - UI 显示 blocked 但语音说 completed -> 失败
  - 回放内容与原 brief 不一致 -> 失败

### 8.4 `XT-W3-29-D` Voice Guidance Intent Router + Directive Binder

- 目标：把“先做什么、暂停什么、往哪走”的语音指令安全写入编排主链。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorOrchestrator.swift`
  - `x-terminal/Sources/Supervisor/MemoryUXAdapter.swift`
  - `x-terminal/Sources/Supervisor/OneShotIntakeCoordinator.swift`
  - `x-terminal/Sources/Supervisor/OneShotReplayHarness.swift`
- DoR：
  - 当前 one-shot run state、memory bus、directed baton 已可承载结构化指导
- 实施子步骤：
  1. 抽象 `VoiceDirectiveNormalizer`
  2. 识别 `priority_shift|scope_hold|resume_lane|pause_lane|delivery_mode_change`
  3. 做 `project/run/pool/lane` 绑定
  4. 歧义时必须复述确认
  5. scope expansion / delivery freeze override 默认 fail-closed
  6. 产出机读证据：`build/reports/xt_w3_29_d_voice_directive_binding_evidence.v1.json`
- DoD：
  - 用户可通过语音改变当前项目推进方向
  - 指导有审计、有绑定、有边界
  - 不会因自然语言歧义偷偷改 scope
- Gate/KPI：
  - Gate: `XT-VOICE-G3`
  - KPI: `voice_directive_binding_accuracy >= 0.95`, `silent_scope_expansion_by_voice = 0`
- 回归样例：
  - “暂停 iPad 范围” 被误识别成“删除 iPad 功能” -> 失败
  - 无项目绑定情况下直接写 directive -> 失败
  - delivery freeze 期间语音扩 scope 未阻断 -> 失败

### 8.5 `XT-W3-29-E` Voice Authorization Bridge

- 目标：让 Supervisor 语音授权走到 Hub 现有语音 challenge 主链，而不是本地假授权。
- 代码落点：
  - `x-terminal/Sources/Hub/HubAIClient.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `protocol/hub_protocol_v1.proto`
  - `protocol/hub_protocol_v1.md`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- DoR：
  - Hub 侧 `IssueVoiceGrantChallenge / VerifyVoiceGrantResponse` 已存在
  - 高风险动作 `voice-only` 默认禁用规则已存在
- 实施子步骤：
  1. 在 XT 增加 `SupervisorVoiceAuthorizationBridge`
  2. 对授权请求做 `risk_tier` 解析
  3. 低风险：允许本地确认后发结构化授权请求
  4. 高风险：必须发 Hub challenge
  5. challenge 结果回写 `xt.supervisor_voice_authorization_resolution.v1`
  6. 产出机读证据：`build/reports/xt_w3_29_e_voice_authorization_bridge_evidence.v1.json`
- DoD：
  - 语音授权和 Hub grant 主链口径一致
  - 高风险 `voice-only` 不会被放行
  - 用户能知道授权成功、失败或升级到双通道的原因
- Gate/KPI：
  - Gate: `XT-VOICE-G4`
  - KPI: `high_risk_voice_only_bypass = 0`
- 回归样例：
  - 高风险支付被 voice-only 放行 -> 失败
  - challenge 超时却仍写 verified -> 失败
  - 风险等级漂移导致授权路径不一致 -> 失败

#### 8.5.1 Hub / XT 接口对接清单

Hub 已有协议锚点：

- `protocol/hub_protocol_v1.proto`
  - `IssueVoiceGrantChallengeRequest`
  - `IssueVoiceGrantChallengeResponse`
  - `VerifyVoiceGrantResponseRequest`
  - `VerifyVoiceGrantResponseResponse`
- `protocol/hub_protocol_v1.md`
  - `IssueVoiceGrantChallenge / VerifyVoiceGrantResponse`
- `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `IssueVoiceGrantChallenge`
  - `VerifyVoiceGrantResponse`

XT 当前对接现状：

- 已有 `HubIPCClient` + `HubPairingCoordinator` 远端授权动作模板，但还没有 voice challenge 对应封装。
- 已有 `SupervisorManager` pending grant 处理路径，可作为 UI/状态回填参考。
- 已有本地语音输入基础件 `VoiceInputView.swift`，但还没有 challenge/verify 桥接。

接口映射必须精确对齐如下字段：

1. `IssueVoiceGrantChallengeRequest`
   - `request_id`
   - `client`
   - `template_id`
   - `action_digest`
   - `scope_digest`
   - `amount_digest`
   - `challenge_code`
   - `risk_level`
   - `bound_device_id`
   - `mobile_terminal_id`
   - `allow_voice_only`
   - `requires_mobile_confirm`
   - `ttl_ms`
2. `IssueVoiceGrantChallengeResponse`
   - `challenge.challenge_id`
   - `challenge.template_id`
   - `challenge.action_digest`
   - `challenge.scope_digest`
   - `challenge.amount_digest`
   - `challenge.challenge_code`
   - `challenge.risk_level`
   - `challenge.requires_mobile_confirm`
   - `challenge.allow_voice_only`
   - `challenge.bound_device_id`
   - `challenge.mobile_terminal_id`
   - `challenge.issued_at_ms`
   - `challenge.expires_at_ms`
3. `VerifyVoiceGrantResponseRequest`
   - `request_id`
   - `client`
   - `challenge_id`
   - `challenge_code`
   - `transcript`
   - `transcript_hash`
   - `semantic_match_score`
   - `parsed_action_digest`
   - `parsed_scope_digest`
   - `parsed_amount_digest`
   - `verify_nonce`
   - `bound_device_id`
   - `mobile_confirmed`
4. `VerifyVoiceGrantResponseResponse`
   - `verified`
   - `decision`
   - `deny_code`
   - `challenge_id`
   - `transcript_hash`
   - `semantic_match_score`
   - `challenge_match`
   - `device_binding_ok`
   - `mobile_confirmed`

硬约束：

- XT 不得把 `transcript` 当长期持久化正文；Hub 侧只允许长期保留 `transcript_hash`。
- XT 必须把 `risk_tier`、`voice_only_allowed`、`requires_mobile_confirm` 视为 Hub 真相源，不得本地猜测覆盖。
- 高风险动作若 Hub 返回 `voice_only_not_allowed`，XT 只能升级双通道，不得 fallback 为本地批准。
- `request_id`、`challenge_id`、`verify_nonce` 必须是 machine-readable 幂等键，不允许 UI 临时字符串替代。

#### 8.5.2 XT 侧代码级任务拆分

1. `HubIPCClient` 新增 voice challenge / verify 请求封装
   - 文件：
     - `x-terminal/Sources/Hub/HubIPCClient.swift`
   - 新增建议类型：
     - `VoiceGrantChallengeRequestPayload`
     - `VoiceGrantChallengeSnapshot`
     - `VoiceGrantVerificationPayload`
     - `VoiceGrantVerificationResult`
   - 新增建议方法：
     - `issueVoiceGrantChallenge(...) async -> VoiceGrantChallengeResult`
     - `verifyVoiceGrantResponse(...) async -> VoiceGrantVerificationResult`
   - 路由要求：
     - 优先 remote/grpc
     - 若 `requiresRemote=true` 且 remote 不可用，显式返回 fail-closed reason
     - file-IPC 初版可明确 `not_supported`，但不能静默成功

2. `HubPairingCoordinator` 新增远端 voice challenge / verify 桥
   - 文件：
     - `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
   - 参照模板：
     - `fetchRemotePendingGrantRequests`
     - `approveRemotePendingGrantRequest`
     - `denyRemotePendingGrantRequest`
   - 新增建议类型：
     - `HubRemoteVoiceGrantChallengeResult`
     - `HubRemoteVoiceGrantVerifyResult`
   - 新增建议方法：
     - `issueRemoteVoiceGrantChallenge(...)`
     - `verifyRemoteVoiceGrantResponse(...)`
   - 新增建议脚本源：
     - `remoteVoiceGrantChallengeScriptSource()`
     - `remoteVoiceGrantVerifyScriptSource()`

3. `SupervisorVoiceAuthorizationBridge` 落地为独立协调器
   - 新增文件建议：
     - `x-terminal/Sources/Supervisor/SupervisorVoiceAuthorizationBridge.swift`
   - 责任：
     - 从语音意图生成 `action_digest/scope_digest/amount_digest`
     - 根据 `risk_tier` 决定 issue-only 还是 issue+verify 主链
     - 把 Hub 响应映射成 `xt.supervisor_voice_authorization_resolution.v1`
     - 输出 UI 友好状态：`pending / verified / denied / escalated_to_mobile / fail_closed`

4. `SupervisorManager` 接入 voice authorization 状态
   - 文件：
     - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
   - 新增建议状态：
     - `@Published private(set) var voiceAuthorizationResolution: VoiceAuthorizationResolution?`
     - `@Published private(set) var activeVoiceChallenge: VoiceGrantChallengeSnapshot?`
   - 新增建议方法：
     - `startVoiceAuthorization(...)`
     - `confirmVoiceAuthorization(...)`
     - `cancelVoiceAuthorization(...)`
   - 复用参考：
     - pending grant action inflight 去重
     - system message / notification 回填

5. `SupervisorView` / `VoiceInputView` 接入 challenge UX
   - 文件：
     - `x-terminal/Sources/Supervisor/SupervisorView.swift`
     - `x-terminal/Sources/UI/VoiceInputView.swift`
   - 最低产品要求：
     - 展示 challenge 状态
     - 展示 `requires_mobile_confirm`
     - 展示 `deny_code`
     - 允许用户重试 verify / 取消 challenge

6. `HubAIClient` 仅负责连接选项复用，不承载业务决策
   - 文件：
     - `x-terminal/Sources/Hub/HubAIClient.swift`
   - 用途：
     - 继续复用 `transportMode()`
     - 继续复用 `remoteConnectOptionsFromDefaults(stateDir:)`
   - 禁止：
     - 不要把 voice authorization 业务状态塞进文本生成客户端逻辑

#### 8.5.3 请求与响应组装规则

Issue 阶段：

1. XT 从当前语音意图生成授权上下文：
   - `authorization_type`
   - `project_id`
   - `request_id`
   - `risk_tier`
   - `action_digest`
   - `scope_digest`
   - `amount_digest`
2. XT 绑定当前设备标识：
   - `bound_device_id`
   - `mobile_terminal_id`
3. XT 根据策略决定：
   - `allow_voice_only=false` 为默认
   - `requires_mobile_confirm=true` 为高风险默认
4. XT 发 `IssueVoiceGrantChallenge`
5. XT 保存：
   - `challenge_id`
   - `expires_at_ms`
   - `risk_level`
   - `requires_mobile_confirm`

Verify 阶段：

1. XT 收集本次识别文本
2. 若不传 `transcript`，必须传 `transcript_hash`
3. XT 生成：
   - `semantic_match_score`
   - `parsed_action_digest`
   - `parsed_scope_digest`
   - `parsed_amount_digest`
   - `verify_nonce`
4. XT 发 `VerifyVoiceGrantResponse`
5. XT 只以 Hub 返回的：
   - `verified`
   - `decision`
   - `deny_code`
   - `challenge_match`
   - `device_binding_ok`
   - `mobile_confirmed`
   作为最终裁决依据

#### 8.5.4 Deny Code 与失败闭锁对齐

XT 至少要正确承接以下结果：

- `voice_only_not_allowed`
- `challenge_missing`
- `challenge_expired`
- `identity_mismatch`
- `policy_denied`
- `semantic_ambiguous`
- `device_not_bound`
- `trusted_automation_project_not_bound`
- `runtime_error`

UI 文案要求：

- 用户能看见简短人话解释
- 同时保留 machine-readable `deny_code`
- 高风险 deny 不得自动降级为“那我先帮你执行”

#### 8.5.5 Hub 侧对齐清单

Hub 侧不是新协议设计，而是对现有能力做 XT 产品化接线：

1. 协议冻结检查
   - `protocol/hub_protocol_v1.proto`
   - `protocol/hub_protocol_v1.md`
2. 服务端行为核对
   - `x-hub/grpc-server/hub_grpc_server/src/services.js`
   - 核对：
     - `clientAllows(auth, 'memory')`
     - `trustedAutomationAllows(...)`
     - `supervisor.voice.challenge_issued`
     - `supervisor.voice.denied`
     - transcript 不直存
3. DB / 审计行为核对
   - `x-hub/grpc-server/hub_grpc_server/src/memory_voice_grant.test.js`
   - 核对 deny path：
     - `challenge_missing`
     - `semantic_ambiguous`
     - `device_not_bound`
4. paired terminal policy 路径核对
   - `x-hub/grpc-server/hub_grpc_server/src/paired_terminal_policy_usage.test.js`
   - 核对 cross-project / trusted automation project binding 边界

#### 8.5.6 测试拆分

XT 侧新增建议测试：

1. `VoiceAuthorizationBridgeTests`
   - issue 请求字段完整
   - verify 请求字段完整
   - 高风险默认 `allow_voice_only=false`
2. `HubIPCClientVoiceGrantTests`
   - remote 路由成功
   - remote 不可用 fail-closed
   - unsupported file-IPC 显式失败
3. `SupervisorVoiceAuthorizationFlowTests`
   - challenge issued -> waiting mobile
   - verified -> state green
   - denied -> show deny_code
   - timeout -> fail_closed
4. `SupervisorVoiceDirectiveBoundaryTests`
   - 语音授权 deny 后不得继续推进高风险动作

Hub 侧复核测试：

1. `memory_voice_grant.test.js`
2. `paired_terminal_policy_usage.test.js`

最低联调样例：

1. `remote fetch` 低风险语音确认
2. `payment` 高风险双通道确认
3. `cross-project trusted automation` 拒绝
4. `semantic mismatch` 拒绝
5. `device binding mismatch` 拒绝

### 8.6 `XT-W3-29-F` Voice Timeline UX + Quiet Hours + Replay

- 目标：把语音 Supervisor 做成可见、可回放、可静默、可理解的产品面，而不是一个黑箱麦克风按钮。
- 详细窗口/常驻会话落地见：
  - `x-terminal/work-orders/xt-w3-29-supervisor-conversation-window-persistent-session-implementation-pack-v1.md`
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - `x-terminal/Sources/UI/VoiceInputView.swift`
  - `x-terminal/Sources/UI/SupervisorSettingsView.swift`
  - 新增建议：
    - `x-terminal/Sources/UI/SupervisorVoiceControlsView.swift`
- DoR：
  - voice session state 已存在
  - progress brief / directive / authorization resolution 已能产出结构化结果
- 实施子步骤：
  1. 增加 `Voice Status Chip`
  2. 增加 `Auto Report`、`Wake Mode`、`Quiet Hours` 设置
  3. 增加 `Voice Timeline`
  4. 增加 replay / cancel / confirm 快捷操作
  5. 产出机读证据：`build/reports/xt_w3_29_f_voice_timeline_ux_evidence.v1.json`
- DoD：
  - 用户能看见为什么播报、播报了什么、下一步是什么
  - 用户能静音、回放、取消、确认
  - 语音 Supervisor 不会变成不可控黑箱
- Gate/KPI：
  - Gate: `XT-VOICE-G5`
  - KPI: `voice_timeline_missing_explainability = 0`
- 回归样例：
  - 主动播报没有 UI 记录 -> 失败
  - quiet hours 无法关闭主动播报 -> 失败
  - 用户无法取消等待中的语音授权流程 -> 失败
