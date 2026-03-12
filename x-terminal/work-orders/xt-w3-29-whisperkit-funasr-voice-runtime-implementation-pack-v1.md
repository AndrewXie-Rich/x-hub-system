# XT-W3-29 WhisperKit + FunASR Supervisor Voice Runtime 详细实施包

- version: v1.0
- updatedAt: 2026-03-10
- owner: XT-L2（Primary）/ XT-L1 / Hub-L5 / QA
- status: planned
- scope:
  - `XT-W3-29-A/B/C/F` 的 runtime 实施细化
  - 复用已落地的 `XT-W3-29-E Voice Authorization Bridge`
  - `WhisperKit（本地 fallback） + FunASR（流式 sidecar） + AVSpeechSynthesizer（TTS v1）`
- parent:
  - `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
  - `protocol/hub_protocol_v1.md`
  - `docs/xhub-scenario-map-v1.md`
- explicit_non_release_claim:
  - 本包是产品化 / roadmap lane 的代码级拆解，不构成新的 validated public release claim。
  - 不扩大此前已冻结的 validated mainline release scope。

## 0) 为什么要单独补这份包

当前代码状态已经具备一半基础，但还缺真正可用的语音 runtime 主链：

- 已有本地语音输入按钮：
  - `x-terminal/Sources/UI/VoiceInputView.swift`
- 已有 Supervisor 语音授权桥与 UI：
  - `x-terminal/Sources/Supervisor/SupervisorVoiceAuthorizationBridge.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/UI/Components/SupervisorVoiceAuthorizationCard.swift`
- 已有 Hub 侧 voice challenge / verify 主链：
  - `protocol/hub_protocol_v1.md`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Hub/HubPairingCoordinator.swift`

但还没有这些关键层：

- 常驻语音会话协调器
- 流式 partial transcript 主链
- 唤醒 / VAD / 长驻对话窗口
- Supervisor 主动 TTS 播报
- 本地 fallback STT 路由
- sidecar 健康度、诊断与 UX

`VoiceInputView.swift` 目前直接绑 `SFSpeechRecognizer`，适合“按一下录一段”，不适合：

- 常驻监听
- 流式 partial transcript
- wake phrase
- sidecar 健康切换
- fail-closed 的 runtime route 诊断

因此这里单独冻结一条可执行实现路线：

- `FunASR` 负责：流式 ASR / VAD / wake phrase / partial transcript
- `WhisperKit` 负责：XT 本地离线 fallback / final pass / sidecar 不可用时兜底
- `AVSpeechSynthesizer` 负责：Supervisor 播报 v1
- Hub 继续只负责：授权、策略、审计、信任边界

## 1) 架构结论

### 1.1 分层边界

1. `X-Terminal 主进程`
   - 麦克风权限
   - audio capture
   - `VoiceSessionCoordinator`
   - `SupervisorVoiceIntentRouter`
   - `SupervisorSpeechSynthesizer`
   - voice timeline / runtime diagnostics / settings

2. `XT 本机 sidecar`
   - `FunASR` 流式识别
   - VAD
   - wake phrase / keyword spotting
   - partial/final transcript 输出

3. `XT 本地 fallback`
   - `WhisperKit`
   - 无 sidecar 时的本地识别
   - 流式主链失效时的 failover
   - 语音 turn 的 final pass

4. `X-Hub`
   - 语音授权 challenge / verify
   - trust profile / policy / grant / audit
   - 模型与外部动作的最终裁决

### 1.2 关键设计原则

- `FunASR` 不直接嵌进 XT UI 主进程，避免 Python/C++ runtime 把 UI 和会话状态拖死。
- `WhisperKit` 不是主流式引擎，而是 XT 本地 fallback 和 final-pass 层。
- 唤醒词只能“打开会话”，不能直接触发任何授权或高风险动作。
- 高风险动作继续走已存在的 `SupervisorVoiceAuthorizationBridge`，不允许语音 runtime 绕过 Hub。
- sidecar 不可用时必须显式降级到 `whisperkit_local` 或 `manual_text`，不能伪装 ready。

### 1.3 路由优先级

默认顺序：

1. `funasr_streaming`
2. `whisperkit_local`
3. `manual_text`
4. `fail_closed`

路由切换条件：

- `funasr_streaming` 健康且 wake/VAD 可用 -> 主路径
- `funasr_streaming` 不健康但 `WhisperKit` model ready -> fallback
- 两者都不可用 -> 仅保留手动文本输入与现有 voice authorization 文本框
- 授权桥本身永远独立于 STT route；route 恢复不代表授权自动通过

## 2) 现有代码锚点

### 2.1 已有文件

- `x-terminal/Sources/UI/VoiceInputView.swift`
  - 当前是直接 `SFSpeechRecognizer` + `AVAudioEngine`
  - 需要重构为“薄 UI + 可替换 transcriber”
- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 已有 voice authorization 状态
  - 适合接 `SupervisorVoiceRuntimeState`、auto-report、session 入口
- `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - 已有 cockpit / authorization card 入口
  - 适合加 runtime rail / timeline / diagnostics
- `x-terminal/Sources/Supervisor/SupervisorVoiceAuthorizationBridge.swift`
  - 已落地
  - 本包不重复发明授权桥，只复用
- `x-terminal/Sources/Hub/HubIPCClient.swift`
  - 已有 voice challenge / verify remote 封装
- `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - 已有 remote voice challenge / verify 桥
- `x-terminal/Sources/UI/SupervisorSettingsView.swift`
  - 适合挂语音 runtime 设置
- `x-terminal/Sources/LLM/SettingsStore.swift`
  - 适合挂 route preference / quiet hours / wake mode

### 2.2 需要新增的目录

- `x-terminal/Sources/Voice/`
- `x-terminal/Sources/Voice/FunASR/`
- `x-terminal/Sources/Voice/WhisperKit/`
- `x-terminal/Tests/Voice/`
- `x-terminal/scripts/voice/`

## 3) 机读契约冻结

### 3.1 `xt.supervisor_voice_runtime_route.v1`

```json
{
  "schema_version": "xt.supervisor_voice_runtime_route.v1",
  "route": "funasr_streaming|whisperkit_local|manual_text|fail_closed",
  "reason": "preferred_streaming_ready|streaming_unhealthy_fallback_to_local|local_model_missing|microphone_denied",
  "funasr_health": "ready|degraded|unreachable|disabled",
  "whisperkit_health": "ready|loading|missing_model|failed",
  "wake_capability": "funasr_kws|prompt_phrase_only|push_to_talk_only|none",
  "audit_ref": "audit-xxxx"
}
```

### 3.2 `xt.supervisor_voice_transcript_event.v1`

```json
{
  "schema_version": "xt.supervisor_voice_transcript_event.v1",
  "session_id": "uuid",
  "turn_id": "uuid",
  "source": "funasr_streaming|whisperkit_local|manual_text",
  "kind": "partial|final|revised_final",
  "language": "zh-CN",
  "text": "Supervisor, report blocker status.",
  "confidence": 0.97,
  "is_wake_match": false,
  "project_binding": "uuid",
  "audit_ref": "audit-xxxx"
}
```

### 3.3 `xt.supervisor_voice_tts_job.v1`

```json
{
  "schema_version": "xt.supervisor_voice_tts_job.v1",
  "job_id": "uuid",
  "trigger": "heartbeat|blocked|completed|authorization|user_query_reply",
  "priority": "interrupt|normal|quiet",
  "script": [
    "Phoenix is blocked on bridge readiness.",
    "The next safe step is to repair tool routing."
  ],
  "mode": "silent|blockers_only|summary|full",
  "dedupe_key": "project-phoenix-blocked-bridge-readiness",
  "quiet_hours_suppressed": false,
  "audit_ref": "audit-xxxx"
}
```

### 3.4 `xt.supervisor_voice_sidecar_health.v1`

```json
{
  "schema_version": "xt.supervisor_voice_sidecar_health.v1",
  "engine": "funasr",
  "transport": "websocket|grpc|http",
  "endpoint": "ws://127.0.0.1:10096",
  "status": "ready|degraded|unreachable|disabled",
  "vad_ready": true,
  "wake_ready": true,
  "partial_ready": true,
  "last_error": "none",
  "audit_ref": "audit-xxxx"
}
```

## 4) 实施工单拆分

### 4.1 `XT-W3-29-R1` Voice Runtime Foundation

- 目标：把当前“按钮直接绑系统识别”的实现，重构成可插拔 runtime 层。
- Gate 映射：`XT-VOICE-G1`
- 代码落点：
  - 新增 `x-terminal/Sources/Voice/VoiceRuntimeTypes.swift`
  - 新增 `x-terminal/Sources/Voice/VoiceRoutePolicy.swift`
  - 新增 `x-terminal/Sources/Voice/VoiceAudioCapture.swift`
  - 修改 `x-terminal/Sources/UI/VoiceInputView.swift`
  - 修改 `x-terminal/Sources/LLM/SettingsStore.swift`
  - 修改 `x-terminal/Sources/LLM/XTerminalSettings.swift`
- 代码级任务：
  1. 定义协议：
     - `VoiceStreamingTranscriber`
     - `VoiceWakeEngine`
     - `VoiceSpeaker`
     - `VoiceRouteHealthProvider`
  2. 定义结构：
     - `VoiceRouteMode`
     - `VoiceRouteDecision`
     - `VoiceTranscriptChunk`
     - `SupervisorVoiceRuntimeState`
  3. 把 `VoiceInputView.swift` 改成薄 UI：
     - 不再自己管理识别路线
     - 只调用 `VoiceSessionCoordinator`
  4. 在 `SettingsStore` 增加：
     - `voicePreferredRoute`
     - `voiceWakeMode`
     - `voiceAutoReportMode`
     - `voiceQuietHours`
  5. 增加 `xt.supervisor_voice_runtime_route.v1` 输出能力
- DoD：
  - 语音输入 UI 不再硬编码单一路由
  - route health 可机读
  - 后续 `FunASR` / `WhisperKit` 可无侵入接入
- 交付物：
  - `build/reports/xt_w3_29_r1_voice_runtime_foundation_evidence.v1.json`
- 回归样例：
  - route health 缺失却 UI 显示 ready -> 失败
  - fallback 发生但没有 machine-readable reason -> 失败

### 4.2 `XT-W3-29-R2` FunASR Streaming Sidecar Transport

- 目标：把 `FunASR` 接成 XT 本机流式 sidecar，而不是把 runtime 逻辑散在 UI 里。
- Gate 映射：`XT-VOICE-G1`, `XT-VOICE-G2`
- 代码落点：
  - 新增 `x-terminal/Sources/Voice/FunASR/FunASRStreamingClient.swift`
  - 新增 `x-terminal/Sources/Voice/FunASR/FunASRSidecarHealthMonitor.swift`
  - 新增 `x-terminal/Sources/Voice/FunASR/FunASRTranscriptParser.swift`
  - 新增 `x-terminal/scripts/voice/funasr_sidecar_boot.sh`
  - 新增 `x-terminal/scripts/voice/funasr_sidecar_healthcheck.sh`
  - 新增 `x-terminal/Tests/Voice/FunASRStreamingClientTests.swift`
- 代码级任务：
  1. 冻结 sidecar 连接模型：
     - `127.0.0.1` loopback only
     - endpoint 由 settings 指定
  2. 实现流式事件解析：
     - `partial`
     - `final`
     - `vad_start`
     - `vad_end`
     - `wake_match`
  3. 健康检测输出：
     - `xt.supervisor_voice_sidecar_health.v1`
  4. sidecar 不可达时：
     - 明确返回 `unreachable`
     - 触发 route fallback
  5. 不做的事：
     - 不自动下载模型
     - 不把 raw audio 发给 Hub
- DoD：
  - XT 能接收到 `FunASR` partial/final transcript
  - sidecar 故障能被 UI 和 route policy 看见
  - 任何 sidecar 故障都不会伪装 ready
- 交付物：
  - `build/reports/xt_w3_29_r2_funasr_streaming_evidence.v1.json`
- 回归样例：
  - sidecar 断连但 session 仍声称 streaming ready -> 失败
  - remote host sidecar 被默认允许 -> 失败

### 4.3 `XT-W3-29-R3` WhisperKit Local Fallback

- 目标：提供 XT 本地 STT fallback，保证没有 `FunASR` 时也能工作。
- Gate 映射：`XT-VOICE-G1`, `XT-VOICE-G2`
- 代码落点：
  - 新增 `x-terminal/Sources/Voice/WhisperKit/WhisperKitTranscriber.swift`
  - 新增 `x-terminal/Sources/Voice/WhisperKit/WhisperKitModelInventory.swift`
  - 新增 `x-terminal/Sources/Voice/WhisperKit/WhisperKitFinalPassRefiner.swift`
  - 修改 `x-terminal/Package.swift`
  - 新增 `x-terminal/Tests/Voice/WhisperKitTranscriberTests.swift`
- 代码级任务：
  1. 增加 `WhisperKit` 依赖封装，不把第三方类型泄漏到 UI 层
  2. 实现本地模型 inventory：
     - `available`
     - `missing`
     - `loading`
     - `failed`
  3. 支持两种模式：
     - `push_to_talk_local`
     - `streaming_fallback_final_pass`
  4. `FunASR` 不可用时允许自动切到 `whisperkit_local`
  5. 若本地模型缺失，显式降级到 `manual_text`
- DoD：
  - XT 在 sidecar 不可用时仍能本地识别
  - fallback 行为可解释
  - `WhisperKit` 不参与高风险授权裁决
- 交付物：
  - `build/reports/xt_w3_29_r3_whisperkit_fallback_evidence.v1.json`
- 回归样例：
  - `FunASR` 宕机后 XT 沉默无响应 -> 失败
  - `WhisperKit` model 缺失但 route 仍显示 local ready -> 失败

### 4.4 `XT-W3-29-R4` VoiceSessionCoordinator + Intent Router

- 目标：把“转写文本”、“Supervisor 意图”、“当前项目绑定”、“授权桥入口”统一编排。
- Gate 映射：`XT-VOICE-G1`, `XT-VOICE-G3`
- 代码落点：
  - 新增 `x-terminal/Sources/Voice/VoiceSessionCoordinator.swift`
  - 新增 `x-terminal/Sources/Voice/SupervisorVoiceIntentRouter.swift`
  - 新增 `x-terminal/Sources/Voice/VoiceTranscriptEventStore.swift`
  - 修改 `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 修改 `x-terminal/Sources/Session/AXSessionManager.swift`
- 代码级任务：
  1. 管理状态：
     - `idle`
     - `listening`
     - `transcribing`
     - `intent_classified`
     - `awaiting_confirmation`
     - `awaiting_hub_voice_challenge`
     - `speaking`
     - `completed`
     - `fail_closed`
  2. 接 partial/final transcript，并写 `xt.supervisor_voice_transcript_event.v1`
  3. 做最小意图分类：
     - `progress_query`
     - `direction_guidance`
     - `authorization_request`
     - `cancel`
     - `help`
  4. 为 directive 绑定：
     - `project_id`
     - `run_id`
     - `pool_id/lane_id`
  5. 歧义时 fail-closed，不直接执行
  6. 对接现有 `SupervisorVoiceAuthorizationBridge`
- DoD：
  - session state 从音频输入到意图落点可完整追踪
  - directive / auth / progress_query 路径不串线
  - 没有项目绑定时不会静默写 directive
- 交付物：
  - `build/reports/xt_w3_29_r4_voice_session_coordinator_evidence.v1.json`
- 回归样例：
  - “暂停 iPad 范围” 被识别成 scope expansion -> 失败
  - 授权意图误走普通 query -> 失败

### 4.5 `XT-W3-29-R5` Supervisor Speech Synthesizer + Auto Report

- 目标：先把 Supervisor 主动播报做稳，TTS v1 先用系统能力，不卡在模型栈。
- Gate 映射：`XT-VOICE-G2`, `XT-VOICE-G5`
- 代码落点：
  - 新增 `x-terminal/Sources/Voice/SupervisorSpeechSynthesizer.swift`
  - 新增 `x-terminal/Sources/Voice/SupervisorVoiceAutoReportBridge.swift`
  - 新增 `x-terminal/Sources/Voice/SupervisorVoiceBriefDeduper.swift`
  - 修改 `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 修改 `x-terminal/Sources/Supervisor/SupervisorView.swift`
- 代码级任务：
  1. 用 `AVSpeechSynthesizer` 落地 TTS v1
  2. 把这些事件接成播报源：
     - heartbeat
     - blocker appeared
     - blocker cleared
     - awaiting authorization
     - completed
  3. 增加 dedupe / cooldown / quiet hours
  4. 输出 `xt.supervisor_voice_tts_job.v1`
  5. 播报内容来自结构化 brief，不直接把内部日志整段念出来
- DoD：
  - Supervisor 可主动播报 blocker / completion / authorization state
  - 不会刷屏
  - UI 可解释播报来源
- 交付物：
  - `build/reports/xt_w3_29_r5_supervisor_tts_autoreport_evidence.v1.json`
- 回归样例：
  - 同一 blocker 每个 heartbeat 都重复播报 -> 失败
  - quiet hours 开启后仍强制朗读 summary -> 失败

### 4.6 `XT-W3-29-R6` Wake Phrase + Persistent Conversation Window

- 目标：把语音入口从“按按钮输入一段文本”升级为会话入口，但保持安全边界。
- Gate 映射：`XT-VOICE-G1`, `XT-VOICE-G5`
- 代码落点：
  - 新增 `x-terminal/Sources/Voice/VoiceWakeRouter.swift`
  - 新增 `x-terminal/Sources/Voice/FunASR/FunASRWakeEventAdapter.swift`
  - 修改 `x-terminal/Sources/UI/VoiceInputView.swift`
  - 修改 `x-terminal/Sources/UI/SupervisorSettingsView.swift`
- 代码级任务：
  1. 支持三种模式：
     - `push_to_talk`
     - `wake_phrase`
     - `prompt_phrase_only`
  2. `FunASR` sidecar 可发 wake 事件时，接为 session opening signal
  3. 没有 wake 引擎时，退回 `prompt_phrase_only`
  4. 增加持续会话窗口：
     - 用户连续追问时复用同一 session
     - 超时后自动结束
  5. 明确边界：
     - wake 不代表授权
     - wake 不代表取消 quiet hours
- DoD：
  - 用户可通过 wake phrase 打开 Supervisor 会话
  - 连续追问不必重复按键
  - 安全边界清晰
- 交付物：
  - `build/reports/xt_w3_29_r6_wake_and_persistent_session_evidence.v1.json`
- 回归样例：
  - wake phrase 直接触发授权 verify -> 失败
  - session 超时后仍吞掉新 turn -> 失败

### 4.7 `XT-W3-29-R7` Runtime UX + Settings + Diagnostics

- 目标：让用户能看见现在语音链路在哪一层坏了，而不是只看到一个麦克风按钮。
- Gate 映射：`XT-VOICE-G5`
- 代码落点：
  - 新增 `x-terminal/Sources/UI/Components/SupervisorVoiceRuntimeCard.swift`
  - 新增 `x-terminal/Sources/UI/Components/SupervisorVoiceTimelineCard.swift`
  - 修改 `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - 修改 `x-terminal/Sources/UI/SupervisorSettingsView.swift`
  - 修改 `x-terminal/Sources/UI/XTSystemSettingsLinks.swift`
- 代码级任务：
  1. 显示 route readiness：
     - pairing
     - model route
     - bridge/tool
     - session runtime
     - voice runtime
  2. 显示具体 route：
     - `funasr_streaming`
     - `whisperkit_local`
     - `manual_text`
  3. 显示 sidecar / local model 健康度
  4. 显示 quiet hours / auto-report / wake mode
  5. 提供：
     - `repair sidecar`
     - `open model settings`
     - `switch to push-to-talk`
     - `mute speech`
- DoD：
  - 用户能知道是 sidecar 坏、模型没装、麦克风拒绝，还是授权桥在等 Hub
  - 所有 runtime blocked 状态都有下一步建议
- 交付物：
  - `build/reports/xt_w3_29_r7_voice_runtime_ux_evidence.v1.json`
- 回归样例：
  - `FunASR` 未连接但 UI 只写“something went wrong” -> 失败
  - runtime 已 fallback 到 local，但 UI 仍显示 streaming -> 失败

### 4.8 `XT-W3-29-R8` 测试矩阵与联调证据

- 目标：把语音 runtime 做成可回归、可追溯，而不是一次性 demo。
- Gate 映射：`XT-VOICE-G1..G5`
- 测试文件建议：
  - 新增 `x-terminal/Tests/Voice/VoiceRoutePolicyTests.swift`
  - 新增 `x-terminal/Tests/Voice/FunASRStreamingClientTests.swift`
  - 新增 `x-terminal/Tests/Voice/WhisperKitTranscriberTests.swift`
  - 新增 `x-terminal/Tests/Voice/VoiceSessionCoordinatorTests.swift`
  - 新增 `x-terminal/Tests/Voice/SupervisorSpeechSynthesizerTests.swift`
  - 修改 `x-terminal/Tests/SupervisorManagerVoiceAuthorizationTests.swift`
  - 修改 `x-terminal/Tests/SupervisorCockpitStateMappingTests.swift`
- 覆盖矩阵：
  1. `FunASR ready -> partial/final -> progress query`
  2. `FunASR unreachable -> WhisperKit fallback`
  3. `WhisperKit model missing -> manual_text`
  4. `heartbeat blocker -> TTS brief`
  5. `wake phrase -> session open -> user query`
  6. `authorization_request -> Hub challenge`
  7. `high-risk voice-only forbidden -> escalated_to_mobile`
  8. `quiet hours -> blocked brief suppressed`
- 交付物：
  - `build/reports/xt_w3_29_r8_voice_runtime_probe_matrix.v1.json`
  - `x-terminal/build/reports/xt_w3_29_voice_runtime_probe_tests.v1.log`
- DoD：
  - 每个 route / fallback / auth 边界至少一条自动化回归
  - 有机读证据，不只靠人工截图

## 5) 执行顺序

推荐顺序：

1. `R1 Voice Runtime Foundation`
2. `R4 VoiceSessionCoordinator + Intent Router`
3. `R5 Supervisor Speech Synthesizer + Auto Report`
4. `R2 FunASR Streaming Sidecar Transport`
5. `R3 WhisperKit Local Fallback`
6. `R6 Wake Phrase + Persistent Conversation`
7. `R7 Runtime UX + Settings + Diagnostics`
8. `R8 测试矩阵与联调证据`

原因：

- 先稳定抽象层与 session 编排，后面换 ASR 引擎不会反复打 UI。
- 先做 TTS 主动播报，用户最快能感知收益。
- `FunASR` / `WhisperKit` 都接在统一 route policy 下，避免双栈分叉。

## 6) 不做的事

- 不把 raw audio 长期写入 Hub 记忆或常规审计
- 不把 `FunASR` 当远端公网服务默认接入
- 不在 v1 就上 TTS 模型切换；先用 `AVSpeechSynthesizer`
- 不让 wake phrase 直接触发任何高风险动作
- 不新增未验证 release claim

## 7) 接案标准

接手这份包的实现者，必须先满足：

- 已理解 `XT-W3-29-E` 已落地语音授权桥，不得重复设计授权协议
- 已理解 `VoiceInputView.swift` 当前是临时实现，目标是重构，不是继续堆逻辑
- 已接受 `FunASR sidecar` 与 `WhisperKit fallback` 的双层设计
- 已接受 fail-closed：任一健康度不明时，route 只能降级，不能假装 ready

## 8) 第一批可直接开工的文件级任务

如果现在立刻开始编码，首批建议直接开这 6 个文件：

1. `x-terminal/Sources/Voice/VoiceRuntimeTypes.swift`
2. `x-terminal/Sources/Voice/VoiceSessionCoordinator.swift`
3. `x-terminal/Sources/Voice/SupervisorSpeechSynthesizer.swift`
4. `x-terminal/Sources/Voice/FunASR/FunASRStreamingClient.swift`
5. `x-terminal/Sources/Voice/WhisperKit/WhisperKitTranscriber.swift`
6. `x-terminal/Tests/Voice/VoiceRoutePolicyTests.swift`

这样能先把架子搭起来，再往 UI 和 sidecar 接。
