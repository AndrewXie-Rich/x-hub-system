# XT-W3-29 Supervisor Voice Productization Gap Closure 详细实施包

- version: v1.0
- updatedAt: 2026-03-11
- owner: XT-L2（Primary）/ XT-L1 / Hub-L5 / QA
- status: planned
- scope:
  - `XT-W3-29` 后续产品化补强
  - 在不破坏 `Hub voice challenge / verify`、`fail-closed route policy`、`Supervisor session truth-source` 的前提下，补齐成熟语音助手体验差距
  - 重点吸收：全局唤醒词同步、连续 talk loop、interrupt-on-speech、streaming TTS、多端语音节点协同
- parent:
  - `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-29-whisperkit-funasr-voice-runtime-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-29-supervisor-conversation-window-persistent-session-implementation-pack-v1.md`
  - `protocol/hub_protocol_v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
- explicit_non_release_claim:
  - 本包只定义后续产品化增量，不扩大任何已冻结的 validated release scope。
  - 本包不新增任何未验证 public claim。

## 0) 为什么要补这份包

当前仓库已经有一条正确的 Supervisor 语音主线：

- `FunASR streaming + system fallback` 的 route / health / fail-closed 框架
- `SupervisorConversationSessionController` 的唤醒后短时常驻会话
- `SupervisorConversationPanel` 的统一窗口主链
- `Hub voice challenge / verify` 的高风险授权桥
- `SupervisorSpeechSynthesizer` 的基础 TTS 播报

但从“企业级受控执行系统”走向“成熟语音产品体验”，还差几块关键拼图：

1. 唤醒词还是 XT 本地偏单机语义，缺少 pair / device 级同步与冲突收口。
2. 常驻会话仍是“Supervisor 会话 TTL”形态，不是完整的 `listen -> think -> speak -> resume` talk loop。
3. TTS 还是系统播报优先，缺少 streaming playback、打断恢复、voice persona 控制。
4. 缺少设备级语音状态协同，配对成功不等于语音链路 ready。
5. UI 仍偏工程态诊断，不够像一个长期可用的 voice cockpit。

这份包的目标不是把 XT 变成通用消费级语音助手，而是：

- 借成熟语音产品的交互完成度
- 保留 X-Hub / X-Terminal 的 fail-closed、审计、授权和 Supervisor 主控边界

## 1) 架构口径冻结

### 1.1 允许吸收的能力

- 全局唤醒词列表与多端同步
- 持续对话状态机
- interrupt-on-speech
- streaming TTS 与 system fallback
- 平台权限预检、设备级语音 readiness
- 常驻语音入口的专用 UI 容器

### 1.2 必须按我们边界改造的能力

- 唤醒词命中只能打开 Supervisor 会话，不得直接触发高风险动作
- talk loop 不能绕开 `SupervisorManager`
- 语音回复必须保留 `quiet hours / dedupe / blocker-first` 策略
- 任何 voice command 只可进入现有 Supervisor / tool gate，不能新增隐式直达执行链
- 语音权限、pairing、tool route、model route 任一不满足时，仍必须 fail-closed

### 1.3 明确拒绝引入的能力

- “说一句就直接执行系统动作”的无授权捷径
- 把 voice runtime 直接做成 Hub 模型执行的 side door
- 未经约束的全局 always-listening，绕过当前 XT route / pairing / trust state
- 将第三方 provider secret 暴露给不具备 `trusted_operator` 或等价信任条件的客户端

## 2) 差距归类

### 2.1 可直接复用的现有资产

- `x-terminal/Sources/Voice/VoiceSessionCoordinator.swift`
- `x-terminal/Sources/Voice/VoiceRoutePolicy.swift`
- `x-terminal/Sources/Voice/FunASR/FunASRStreamingClient.swift`
- `x-terminal/Sources/Voice/SystemSpeechCompatibilityTranscriber.swift`
- `x-terminal/Sources/Supervisor/SupervisorConversationSessionController.swift`
- `x-terminal/Sources/Supervisor/SupervisorConversationWindowBridge.swift`
- `x-terminal/Sources/UI/Supervisor/SupervisorConversationPanel.swift`
- `x-terminal/Sources/Voice/SupervisorSpeechSynthesizer.swift`
- `x-terminal/Sources/UI/Components/SupervisorVoiceAuthorizationCard.swift`
- `x-terminal/Sources/Hub/HubIPCClient.swift`
- `x-terminal/Sources/Hub/HubPairingCoordinator.swift`

### 2.2 需要新加的中间层

- `VoiceWakeProfile` 与 pair-synced vocabulary store
- `SupervisorTalkLoopRuntime`
- `VoicePlaybackCoordinator`
- `StreamingTTSProvider` 抽象
- `VoiceReadinessAggregator`
- `SupervisorVoicePresenceSurface`
- `VoiceNodeSyncSnapshot`

### 2.3 需要严格守住的真相源

- Supervisor 对话与任务推进真相源：`SupervisorManager`
- 短时常驻会话真相源：`SupervisorConversationSessionController`
- 高风险授权真相源：`Hub voice challenge / verify`
- runtime route 真相源：`VoiceRoutePolicy`

## 3) 机读契约冻结

### 3.1 `xt.supervisor_voice_wake_profile.v1`

```json
{
  "schema_version": "xt.supervisor_voice_wake_profile.v1",
  "profile_id": "default",
  "trigger_words": ["x hub", "supervisor"],
  "updated_at_ms": 0,
  "scope": "paired_device_group",
  "source": "hub_pairing_sync|local_override",
  "wake_mode": "wake_phrase|prompt_phrase_only|push_to_talk",
  "requires_pairing_ready": true,
  "audit_ref": "audit-xxxx"
}
```

### 3.2 `xt.supervisor_talk_loop_state.v1`

```json
{
  "schema_version": "xt.supervisor_talk_loop_state.v1",
  "session_id": "uuid",
  "enabled": true,
  "phase": "idle|listening|thinking|speaking|paused|fail_closed",
  "route": "funasr_streaming|whisperkit_local|system_speech_compatibility|manual_text|fail_closed",
  "interrupt_on_speech": true,
  "last_interrupted_at_ms": 0,
  "blocked_by": "none|pairing_incomplete|tool_route_unready|tts_provider_unavailable",
  "audit_ref": "audit-xxxx"
}
```

### 3.3 `xt.supervisor_voice_playback_job.v1`

```json
{
  "schema_version": "xt.supervisor_voice_playback_job.v1",
  "job_id": "uuid",
  "provider": "system|streaming_remote",
  "voice_id": "default",
  "mode": "blocking_reply|background_brief",
  "interruptible": true,
  "text_hash": "sha256:xxxx",
  "started_at_ms": 0,
  "completed_at_ms": 0,
  "fallback_used": false,
  "reason_code": "none",
  "audit_ref": "audit-xxxx"
}
```

### 3.4 `xt.supervisor_voice_readiness_snapshot.v1`

```json
{
  "schema_version": "xt.supervisor_voice_readiness_snapshot.v1",
  "pairing_ready": false,
  "model_route_ready": false,
  "bridge_tool_ready": false,
  "session_runtime_ready": false,
  "wake_profile_ready": false,
  "talk_loop_ready": false,
  "tts_ready": false,
  "reason_codes": [
    "pairing_incomplete",
    "bridge_heartbeat_missing"
  ],
  "audit_ref": "audit-xxxx"
}
```

## 4) 代码级任务拆分

### 4.1 `XT-W3-29-P1` Pair-Synced Wake Profile

- 目标：
  - 把“唤醒词/唤醒模式”从本地孤立设置，升级到“可配对同步、可诊断、可回滚”的 wake profile。
- 主要文件：
  - 新增 `x-terminal/Sources/Voice/VoiceWakeProfile.swift`
  - 新增 `x-terminal/Sources/Voice/VoiceWakeProfileStore.swift`
  - 新增 `x-terminal/Sources/Voice/VoiceWakeSyncClient.swift`
  - 修改 `x-terminal/Sources/Hub/HubIPCClient.swift`
  - 修改 `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - 修改 `x-terminal/Sources/UI/SupervisorSettingsView.swift`
  - 修改 `x-terminal/Sources/LLM/SettingsStore.swift`
- 代码要点：
  - 本地保留缓存，但 Hub/paired device group 为默认真相源。
  - profile 下发失败时保留最后一次有效配置，不自动切空。
  - wake profile 不 ready 时，`wake_phrase` 必须降级为 `push_to_talk` 或 `fail_closed`，不能假装已生效。
- DoD：
  - 唤醒词更新后，XT UI、paired XT session、Hub pairing diagnostics 一致。
  - 断网/断配对时能显示 `stale_profile` 或等价 reason code。
- 回归：
  - paired sync success
  - hub unavailable fallback to cached profile
  - stale profile detected
  - invalid profile rejected fail-closed

### 4.2 `XT-W3-29-P2` Continuous Talk Loop Runtime

- 目标：
  - 在现有短时常驻会话之上，加一层完整 `listen -> think -> speak -> resume` talk loop，但入口仍绑定 Supervisor。
- 主要文件：
  - 新增 `x-terminal/Sources/Voice/SupervisorTalkLoopRuntime.swift`
  - 新增 `x-terminal/Sources/Voice/VoiceSilenceWindowMonitor.swift`
  - 修改 `x-terminal/Sources/Voice/VoiceSessionCoordinator.swift`
  - 修改 `x-terminal/Sources/Supervisor/SupervisorConversationSessionController.swift`
  - 修改 `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 修改 `x-terminal/Sources/UI/VoiceInputView.swift`
- 代码要点：
  - talk loop 是会话模式，不替代单次 `VoiceInputButton`。
  - final transcript 统一回到 `SupervisorManager.sendMessage(..., fromVoice: true)`。
  - 任何 `tool route unready / model route missing / bridge heartbeat missing` 都会把 talk loop 收敛到 `paused|fail_closed`。
- DoD：
  - 可以连续说两轮以上，第二轮不需要重新点按钮。
  - 语音回复完成后自动回到 listening，而不是 stuck 在 completed。
  - upstream readiness 缺口出现时，UI 明确展示 blocked reason。
- 回归：
  - silence finalize
  - assistant reply resume listening
  - fail-closed after bridge/tool regression
  - manual end session stops loop cleanly

### 4.3 `XT-W3-29-P3` Interruptible Streaming TTS

- 目标：
  - 用可插拔 provider 补齐 streaming TTS 和 interrupt-on-speech，同时保留系统 TTS fallback。
- 主要文件：
  - 新增 `x-terminal/Sources/Voice/StreamingTTSProvider.swift`
  - 新增 `x-terminal/Sources/Voice/VoicePlaybackCoordinator.swift`
  - 新增 `x-terminal/Sources/Voice/VoicePlaybackDirective.swift`
  - 修改 `x-terminal/Sources/Voice/SupervisorSpeechSynthesizer.swift`
  - 修改 `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 修改 `x-terminal/Sources/UI/SupervisorSettingsView.swift`
- 代码要点：
  - provider 失败时必须回落 system voice，不允许静默丢播报。
  - 用户开口说话可中断当前 reply，但 heartbeat brief 默认不抢占用户输入。
  - voice/persona 只能作为 reply playback hint，不得影响 Hub 授权模板内容。
- DoD：
  - reply 播报可被用户说话打断。
  - provider down 时自动走 system fallback。
  - quiet hours / blockersOnly / summary 模式仍然生效。
- 回归：
  - interrupt-on-speech
  - streaming provider failure fallback
  - duplicate brief suppression still works
  - quiet hours suppression still works

### 4.4 `XT-W3-29-P4` Voice Presence UX + Window Unification

- 目标：
  - 把语音状态从“几个字段”升级为真实可用的 voice cockpit，但继续共用同一 Supervisor window truth-source。
- 主要文件：
  - 新增 `x-terminal/Sources/UI/Supervisor/SupervisorVoicePresenceCard.swift`
  - 新增 `x-terminal/Sources/UI/Supervisor/SupervisorTalkLoopOverlay.swift`
  - 修改 `x-terminal/Sources/UI/Supervisor/SupervisorConversationPanel.swift`
  - 修改 `x-terminal/Sources/UI/Supervisor/SupervisorChatWindow.swift`
  - 修改 `x-terminal/Sources/ContentView.swift`
  - 修改 `x-terminal/Sources/AXAppNotifications.swift`
- 代码要点：
  - 专门展示 `phase / route / ttl / pairing / talk-loop / tts provider / blocked reason`。
  - 状态栏窗口、主 Supervisor 页、wake 自动开窗都共用同一 surface model。
  - 唤醒后自动开窗只允许聚焦会话，不允许偷偷开始高风险流程。
- DoD：
  - 用户能一眼看出“能不能说、为什么不能说、下一步该修哪里”。
  - 主窗口与状态栏窗口显示一致，不再出现两套 UI 真相源。
- 回归：
  - wake opens shared window
  - status rail consistent across surfaces
  - blocked reason card updates on runtime changes

### 4.5 `XT-W3-29-P5` Device Voice Readiness + Pairing Diagnostics

- 目标：
  - 把当前“pairing 成功但 voice/tool/runtime 仍不 ready”的分裂诊断，收敛成单一 readiness snapshot。
- 主要文件：
  - 新增 `x-terminal/Sources/Voice/VoiceReadinessAggregator.swift`
  - 新增 `x-terminal/Sources/Voice/VoiceNodeSyncSnapshot.swift`
  - 修改 `x-terminal/Sources/Hub/HubAIClient.swift`
  - 修改 `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - 修改 `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 修改 `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - 修改 `x-terminal/Sources/UI/SupervisorSettingsView.swift`
- 代码要点：
  - readiness 必须至少覆盖：
    - pairing validity
    - model route readiness
    - bridge/tool readiness
    - session runtime readiness
    - wake profile readiness
    - talk loop readiness
    - tts readiness
  - doctor 输出与 runtime UI reason code 必须共享同一份 aggregation 结果。
- DoD：
  - 用户看到的是一个统一 verdict，不是四块互相打架的 warning。
  - `Verify` 行为能直接指出下一步修复顺序。
- 回归：
  - pairing valid but tool route missing
  - model inventory mismatch
  - bridge heartbeat missing
  - wake profile stale

### 4.6 `XT-W3-29-P6` Safety Invariants + Voice Replay

- 目标：
  - 在体验增强后，补足审计与回放，保证“更像产品”不等于“更难审计”。
- 主要文件：
  - 新增 `x-terminal/Sources/Voice/VoiceReplayEventStore.swift`
  - 新增 `x-terminal/Sources/Voice/VoiceSafetyInvariantChecker.swift`
  - 修改 `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 修改 `x-terminal/Sources/UI/Components/SupervisorVoiceAuthorizationCard.swift`
  - 修改 `x-terminal/Sources/UI/Supervisor/SupervisorConversationPanel.swift`
  - 新增 `x-terminal/Tests/SupervisorVoiceSafetyInvariantTests.swift`
- 代码要点：
  - replay 记录事件摘要，不落原始音频。
  - 必须显式校验：
    - wake does not imply authorization
    - talk loop does not bypass tool gates
    - provider fallback does not drop audit
    - interrupt does not corrupt pending authorization challenge
- DoD：
  - 所有增强链路都能回放摘要时间线。
  - 高风险授权流程在 talk loop / interrupt 场景下仍保持一致。
- 回归：
  - wake hit + high-risk action still asks challenge
  - interrupt during auth prompt does not auto-allow
  - replay summary remains完整

## 5) 文件级实施顺序

1. `P5 Device Voice Readiness + Pairing Diagnostics`
   - 先统一 readiness 真相源，否则 talk loop / wake sync 会继续到处长 reason code。
2. `P1 Pair-Synced Wake Profile`
   - 先把唤醒配置做成可信入口，再放大 usage。
3. `P2 Continuous Talk Loop Runtime`
   - 让语音会话从“单次录音”升级到“短时常驻闭环”。
4. `P3 Interruptible Streaming TTS`
   - 再补播报体验，不先把 provider 引进来污染主路径。
5. `P4 Voice Presence UX + Window Unification`
   - 把运行态和诊断态一起收口到产品界面。
6. `P6 Safety Invariants + Voice Replay`
   - 最后补安全闭环与证据导出。

## 6) 明确不做

- 不把通用闲聊 Talk mode 作为独立真相源接进 XT。
- 不把 voice runtime 直接并入 Hub 模型 inventory 逻辑，Hub 仍只负责策略/授权/配对/模型主权。
- 不为了追求“像消费级语音助手”而削弱当前 `diagnostic_required` / `blocked_waiting_upstream` 口径。
- 不引入未经治理的多 provider secret 管理入口。

## 7) Gate / KPI

### 7.1 Gate

- `XT-VOICE-PG1`: readiness snapshot 与 runtime UI reason code 一致
- `XT-VOICE-PG2`: wake profile sync 成功且 stale/fallback 可解释
- `XT-VOICE-PG3`: talk loop 可完成两轮以上闭环
- `XT-VOICE-PG4`: interrupt-on-speech 不破坏 conversation / auth state
- `XT-VOICE-PG5`: high-risk authorization 在所有新语音路径下仍 fail-closed

### 7.2 KPI

- 第一次唤醒到窗口可交互 `< 800ms`（本地可测口径）
- 连续两轮 voice turn 不需要手动重新点按
- TTS provider 失败后 `<= 1` 次 fallback 重试即有可听输出
- 统一 readiness 诊断下，用户看到的 voice warnings 从多条收敛为单条主 verdict + ordered fixes

## 8) 测试矩阵

### 8.1 Runtime

- `FunASR ready -> wake -> talk loop -> reply -> resume`
- `FunASR degraded -> fallback route -> talk loop paused`
- `TTS streaming ready -> interrupt on user speech`
- `TTS streaming failed -> system fallback`

### 8.2 Safety

- wake hit does not auto-authorize
- voice challenge pending + user interrupt
- tool route blocked + user tries voice command
- pairing stale + cached wake profile present

### 8.3 UX

- status bar window and main Supervisor page show same voice state
- doctor output and conversation panel reason codes are identical
- quiet hours suppresses background briefs but not explicit challenge prompts

## 9) 交付定义

只有同时满足以下条件，才能认为本包交付：

1. Voice readiness verdict 已统一，不再出现多块互相冲突的 voice warnings。
2. 唤醒、短时常驻、talk loop、TTS、interrupt、authorization 能连成一条用户可见主链。
3. 所有新增体验增强都没有突破 Hub fail-closed 边界。
4. 关键场景具备自动化测试与 replay 摘要证据。
5. 未引入新的未受控外部命名、未在主仓库中把对标对象写成产品主线概念。

## 10) 下一步建议

直接执行顺序建议：

1. `XT-W3-29-P5 Device Voice Readiness + Pairing Diagnostics`
2. `XT-W3-29-P1 Pair-Synced Wake Profile`
3. `XT-W3-29-P2 Continuous Talk Loop Runtime`

原因：

- 先收口真相源与配置入口，再放大 runtime 和 UX，风险最低。
