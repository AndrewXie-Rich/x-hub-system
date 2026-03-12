# XT-W3-29 Supervisor Conversation Window + Wake Persistent Session 详细实施包

- version: v1.0
- updatedAt: 2026-03-11
- owner: XT-L2（Primary）/ XT-L1 / QA / AI-COORD-PRIMARY
- status: active
- scope: `XT-W3-29-A/F` window/session integration support pack
- parent:
  - `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-29-whisperkit-funasr-voice-runtime-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-27-hub-xt-ui-productization-r1-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md`

## 0) 为什么要单独补这份包

当前仓库里已经同时存在两条 Supervisor UI 路径：

- 真实主链：
  - `SupervisorView`
  - `SupervisorManager`
  - `VoiceInputButton`
  - `VoiceSessionCoordinator`
- 旧窗口壳：
  - `SupervisorChatWindow`
  - `SupervisorStatusBar -> sheet`
  - `SupervisorModel`

其中只有第一条主链真正接上了：

- 真实消息流
- `fromVoice=true` 语音输入
- heartbeat / blocker / authorization TTS
- fail-closed 语音运行时诊断

而第二条旧窗口壳仍然是占位实现：

- timeline 还是 placeholder
- 消息发送仍走 `SupervisorModel.sendMessage()`
- 没接 `SupervisorManager.messages`
- 没接 wake / short-lived persistent conversation

如果继续在旧窗口壳上直接堆语音逻辑，会把 Supervisor 分成两套真相源。后续 wake phrase、短时常驻、主动播报、授权桥、voice timeline 都会分叉。

本包的目标，就是把“状态栏弹出的 Supervisor 聊天窗口”改造成真实的 Supervisor 会话窗口，并把“唤醒后进入短时常驻会话”绑定到同一条主链上。

## 1) 现状审计与结论

### 1.1 已有真相源

- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 真实消息、心跳、授权、TTS、voice reply 全在这里
- `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - 已有真实输入区、`VoiceInputButton`、`fromVoice=true`
- `x-terminal/Sources/UI/VoiceInputView.swift`
  - 已经走统一 `VoiceSessionCoordinator`
- `x-terminal/Sources/Voice/VoiceSessionCoordinator.swift`
  - 已有转写生命周期、route decision、引擎健康度

### 1.2 现有缺口

- `x-terminal/Sources/UI/Supervisor/SupervisorChatWindow.swift`
  - 还是旧式静态聊天壳
  - 不能展示真实 Supervisor timeline
  - 不能承接 wake 打开窗口
- `x-terminal/Sources/UI/Supervisor/SupervisorStatusBar.swift`
  - 现在打开的是旧壳，不是主链窗口
- `VoiceSessionCoordinator`
  - 负责“本次录音/识别”
  - 但还不负责“短时常驻会话 TTL / wake 后窗口驻留”
- `SupervisorManager`
  - 已经能处理 voice input / TTS
  - 但还没有 conversation window / session presence 的统一状态

### 1.3 架构结论

- 不再扩展旧 `SupervisorModel` 路径。
- `SupervisorChatWindow` 只保留为 window shell，不再承载独立业务逻辑。
- 新增一个共享的 `SupervisorConversationPanel`，同时供：
  - 主 `SupervisorView`
  - 状态栏弹出窗口
  使用。
- 新增一个专门的 `SupervisorConversationSessionController`，负责：
  - wake hit
  - open window
  - short-lived persistent session TTL
  - auto-close / re-arm
- `VoiceSessionCoordinator` 继续只负责：
  - 录音
  - 转写
  - route / engine health
- `SupervisorManager` 继续只负责：
  - 发消息
  - 收回复
  - TTS
  - authorization / heartbeat / audit

## 2) 产品与交互结论

### 2.1 Supervisor 窗口不再只是“聊天框”

它应当升级为一个轻量 Supervisor 会话控制台，最少包含：

- 真实消息 timeline
- 文本输入
- 语音输入
- 当前 voice route / wake / fail-closed 状态
- 当前短时会话剩余时间
- 手动结束会话按钮

### 2.2 三态模型

- `hidden`
  - 窗口关闭
  - 不显示 active conversation UI
- `armed`
  - wake 已启用
  - 仅保持最小唤醒能力
  - 不进入长时间主动录音
- `conversing`
  - 窗口已打开
  - 当前处于短时常驻语音会话
  - 用户连续追问时复用同一 session

### 2.3 默认常驻规则

- 默认会话 TTL：`45s`
- 以下事件重置 TTL：
  - wake hit
  - 用户语音提交
  - 用户文本发送
  - assistant 开始播报
  - assistant 回复落地
- 以下事件立即结束：
  - 用户点击 `End Voice Session`
  - voice route fail-closed 且无 fallback
  - 用户关闭 wake / push-to-talk 入口
- 以下事件只降级，不结束窗口：
  - tool route blocked
  - bridge heartbeat missing
  - pairing / model route 有诊断缺口

### 2.4 明确安全边界

- wake phrase 只表示“打开会话”，不表示授权。
- short-lived persistent session 不表示“持续免确认”。
- quiet hours 不因 wake 自动失效。
- 高风险动作仍必须走当前 Hub voice authorization bridge。

## 3) 机读契约冻结

### 3.1 `xt.supervisor_conversation_window_state.v1`

```json
{
  "schema_version": "xt.supervisor_conversation_window_state.v1",
  "window_state": "hidden|armed|conversing",
  "conversation_id": "uuid",
  "opened_by": "manual_button|wake_phrase|prompt_phrase|voice_reply_followup",
  "wake_mode": "push_to_talk|wake_phrase|prompt_phrase_only",
  "route": "funasr_streaming|whisperkit_local|system_speech_compatibility|manual_text|fail_closed",
  "expires_at_ms": 0,
  "remaining_ttl_sec": 45,
  "keep_open_override": false,
  "reason_code": "none|wake_detected|manual_open|route_fail_closed|ttl_expired",
  "audit_ref": "audit-xxxx"
}
```

### 3.2 `xt.supervisor_conversation_window_event.v1`

```json
{
  "schema_version": "xt.supervisor_conversation_window_event.v1",
  "conversation_id": "uuid",
  "event": "open|extend|auto_close|manual_close|wake_hit|reply_spoken",
  "trigger": "wake_phrase|voice_input|text_input|tts_reply|heartbeat_brief|operator_action",
  "route": "funasr_streaming",
  "ttl_before_sec": 30,
  "ttl_after_sec": 45,
  "reason_code": "none|wake_detected|user_turn|assistant_turn|timeout",
  "audit_ref": "audit-xxxx"
}
```

### 3.3 `xt.supervisor_conversation_window_policy.v1`

```json
{
  "schema_version": "xt.supervisor_conversation_window_policy.v1",
  "enabled": true,
  "auto_open_on_wake": true,
  "default_ttl_sec": 45,
  "max_ttl_sec": 180,
  "extend_on_user_turn": true,
  "extend_on_assistant_turn": true,
  "allow_hidden_armed_mode": true,
  "allow_background_wake_when_window_closed": true,
  "quiet_hours_respected": true,
  "wake_does_not_imply_authorization": true,
  "audit_ref": "audit-xxxx"
}
```

## 4) 文件级架构改造

### 4.1 新增

- `x-terminal/Sources/UI/Supervisor/SupervisorConversationPanel.swift`
  - 统一 timeline + input + voice state rail
- `x-terminal/Sources/Supervisor/SupervisorConversationSessionController.swift`
  - 统一 `hidden|armed|conversing` 与 TTL
- `x-terminal/Sources/Supervisor/SupervisorConversationWindowBridge.swift`
  - 负责 `wake/open/close/focus` 事件桥接
- `x-terminal/Tests/SupervisorConversationSessionControllerTests.swift`
- `x-terminal/Tests/SupervisorConversationWindowIntegrationTests.swift`

### 4.2 修改

- `x-terminal/Sources/UI/Supervisor/SupervisorChatWindow.swift`
  - 从独立聊天实现改为 window shell
- `x-terminal/Sources/UI/Supervisor/SupervisorStatusBar.swift`
  - sheet 改为真实会话窗口入口
- `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - 抽取可复用 conversation panel
- `x-terminal/Sources/UI/VoiceInputView.swift`
  - 增加会话打开/延长钩子
- `x-terminal/Sources/Voice/VoiceSessionCoordinator.swift`
  - 暴露 wake / speaking / idle 辅助状态给会话控制器
- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 统一 user turn / assistant turn 与 TTS turn 对会话 TTL 的延长

### 4.3 明确不做

- 不在 `SupervisorChatWindow` 内继续沿 `SupervisorModel` 扩展业务逻辑。
- 不新增第二套 `messages / voice runtime / authorization` 状态源。
- 不把 raw audio、wake 命中原始片段写进常规 Hub 长期记忆。

## 5) 代码级任务包

### 5.1 `CW-1` Legacy Window 壳收口

- 目标：把 `SupervisorChatWindow` 从旧 placeholder 改成 window shell。
- 代码落点：
  - `x-terminal/Sources/UI/Supervisor/SupervisorChatWindow.swift`
  - `x-terminal/Sources/UI/Supervisor/SupervisorStatusBar.swift`
- 实施步骤：
  1. 移除 `SupervisorModel` 依赖。
  2. 改为直接依赖 `SupervisorManager.shared` 或 `SupervisorConversationPanel`。
  3. 保留 title bar / dismiss / size 控制。
  4. sheet 打开时同步当前 conversation state。
- DoD：
  - 窗口展示真实 Supervisor timeline
  - 状态栏入口与主 Supervisor 使用同一数据源
- 回归样例：
  - 状态栏窗口和主 Supervisor 显示两套不同消息 -> 失败

### 5.2 `CW-2` 抽取共享 Conversation Panel

- 目标：让主 `SupervisorView` 与弹出窗口共用输入/消息/语音面板。
- 代码落点：
  - 新增 `x-terminal/Sources/UI/Supervisor/SupervisorConversationPanel.swift`
  - 修改 `x-terminal/Sources/Supervisor/SupervisorView.swift`
- 实施步骤：
  1. 抽 timeline。
  2. 抽 input bar。
  3. 抽 voice preview / fail-closed rail。
  4. 保留 `autoSendVoice`、文本发送、voice commit。
- DoD：
  - conversation panel 可在主视图和窗口中复用
  - 没有 duplicated voice send path
- 回归样例：
  - 主视图能发语音但弹窗不能 -> 失败

### 5.3 `CW-3` Conversation Session Controller

- 目标：把“短时常驻会话”从录音逻辑里分离出来。
- 代码落点：
  - 新增 `x-terminal/Sources/Supervisor/SupervisorConversationSessionController.swift`
  - 修改 `x-terminal/Sources/Voice/VoiceSessionCoordinator.swift`
  - 修改 `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- 实施步骤：
  1. 落地 `hidden|armed|conversing` 状态机。
  2. 引入 `default_ttl_sec=45` 与延长规则。
  3. 统一事件：
     - `wake_hit`
     - `user_turn`
     - `assistant_turn`
     - `tts_spoken`
     - `timeout`
  4. 对外发布 `remaining_ttl_sec` 与 `reason_code`。
- DoD：
  - 用户连续追问不必重复唤醒
  - 超时会自动退出会话
  - 录音结束不等于 conversation 结束
- Gate/KPI：
  - Gate: `XT-VOICE-G1`, `XT-VOICE-G5`
  - KPI: `user_interrupt_recovery_p95_ms <= 1000`
- 回归样例：
  - 用户刚听完回复就立即失去会话上下文 -> 失败
  - conversation 已过期但 UI 仍显示 active -> 失败

### 5.4 `CW-4` Wake -> Window Bridge

- 目标：wake phrase 命中后自动打开 Supervisor 会话窗口，并进入短时常驻。
- 代码落点：
  - 新增 `x-terminal/Sources/Supervisor/SupervisorConversationWindowBridge.swift`
  - 修改 `x-terminal/Sources/UI/Supervisor/SupervisorStatusBar.swift`
  - 修改 `x-terminal/Sources/UI/VoiceInputView.swift`
- 实施步骤：
  1. 订阅 wake 事件或 wake-like transcript。
  2. 判断当前 policy：
     - `wake_phrase`
     - `prompt_phrase_only`
     - `push_to_talk`
  3. 自动打开窗口并聚焦输入区。
  4. 写入 conversation open 事件审计。
- DoD：
  - wake 命中后窗口可自动打开
  - 没有 wake 引擎时退回 `prompt_phrase_only`
- 回归样例：
  - wake 命中但打开的是旧 placeholder 窗口 -> 失败
  - wake 命中直接触发高风险动作 -> 失败

### 5.5 `CW-5` Voice State Rail + Fail-Closed UX

- 目标：让窗口内清楚展示语音链路在哪一层坏了。
- 代码落点：
  - `x-terminal/Sources/UI/Supervisor/SupervisorConversationPanel.swift`
  - `x-terminal/Sources/Voice/VoiceSessionCoordinator.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- 实施步骤：
  1. 展示：
     - current route
     - authorization status
     - wake capability
     - active reason code
     - remaining TTL
  2. 展示当前会话状态：
     - armed
     - listening
     - transcribing
     - speaking
     - fail_closed
  3. 给出 operator guidance，而不是只写 “blocked”。
- DoD：
  - 用户可直接看懂为什么现在不能继续语音
  - `wake/route/auth/tool` 阻塞可区分
- 回归样例：
  - bridge 不通但窗口只显示空白 mic -> 失败

### 5.6 `CW-6` User Turn / Assistant Turn 会话续期

- 目标：把文字输入、语音输入、TTS 回复都统一接入会话续期。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/UI/VoiceInputView.swift`
- 实施步骤：
  1. 文本发送后延长 conversation TTL。
  2. `fromVoice=true` 后延长 TTL。
  3. assistant 回复落地和 TTS 播报后延长 TTL。
  4. 用户手动结束会话时立即归零 TTL。
- DoD：
  - “问一句 -> 回一句 -> 再追问一句” 在同一短会话内完成
- 回归样例：
  - `blockers_only` 下用户主动语音提问却听不到回复 -> 失败

### 5.7 `CW-7` 证据与测试矩阵

- 目标：把窗口集成与短时常驻会话做成可回归能力，而不是一次性 UI 演示。
- 证据件：
  - `build/reports/xt_w3_29_conversation_window_session_integration_evidence.v1.json`
- 必测用例：
  1. `manual open -> text send -> reply -> auto-close after ttl`
  2. `wake hit -> window open -> voice query -> spoken reply`
  3. `voice reply extends ttl`
  4. `blockers_only suppresses stable heartbeat but not explicit voice reply`
  5. `fail_closed route still opens window with diagnostics`
  6. `quiet hours does not grant authorization bypass`
  7. `window close returns to armed or hidden according to policy`

## 6) 执行顺序

1. `CW-1` Legacy Window 壳收口
2. `CW-2` 抽取共享 Conversation Panel
3. `CW-3` Conversation Session Controller
4. `CW-6` User / Assistant Turn 会话续期
5. `CW-4` Wake -> Window Bridge
6. `CW-5` Voice State Rail + Fail-Closed UX
7. `CW-7` 证据与回归

## 7) 风险与反例

- 风险：继续沿 `SupervisorModel` 增量修改
  - 后果：形成第二套消息和语音状态源
- 风险：把 persistent session 逻辑塞进 `VoiceInputButton`
  - 后果：录音逻辑和会话生命周期耦合，后续难测
- 风险：wake 自动打开窗口但不展示 fail-closed 原因
  - 后果：用户误以为系统“听到了但不工作”
- 风险：assistant 回复播报整段长 Markdown
  - 后果：可听性差，且更容易误导为已执行动作

## 8) 接案标准

- 已接受 `SupervisorChatWindow` 不再作为独立业务实现，只作为 window shell。
- 已接受“短时常驻会话”是独立状态机，不等同于单次录音。
- 已接受 wake 不等于授权、不等于 quiet-hours override。
- 已接受状态栏窗口与主 `SupervisorView` 必须共用同一 conversation core。
