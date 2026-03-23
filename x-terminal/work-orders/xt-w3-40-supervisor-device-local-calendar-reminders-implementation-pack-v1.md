# XT-W3-40 Supervisor Device-Local Calendar Reminders Implementation Pack v1

- version: v1.0
- updatedAt: 2026-03-21
- owner: XT-L2（Primary）/ Supervisor / Voice / Product / Security / QA
- status: active（Hub cut-off 已落地；XT 本地 reminder 链路已落地；真机 smoke 待补）
- scope: `XT-W3-40`（把个人日历从 `X-Hub` 迁到 `X-Terminal` 设备本地，由 Supervisor 基于 XT 本机日历做即时语音提醒，且不再让 Hub 在启动时申请日历权限）
- parent:
  - `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-39-hub-voice-pack-and-supervisor-tts-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md`

## 0) 为什么单开这份包

当前日历能力放在 Hub 上，会带来两个明确问题：

- `X-Hub` 启动时会出现 Calendar 权限弹窗，破坏首次体验和低打扰目标。
- Hub 更适合做“家里常驻设备 / 后台协调面”，但个人会议提醒本质上是“跟着人走”的设备能力。

因此这份包冻结一个新的设备边界：

- `X-Hub` 不再读取个人日历，也不再承担会议提醒入口。
- `X-Terminal` 作为用户随身设备，持有 EventKit 日历读取权限。
- `Supervisor` 在 XT 本地基于真实设备日历做即时语音提醒，必要时再落本地通知兜底。

这不是要把整套 personal assistant 扩张重新拉回主线，而是先完成一个产品边界修正：

- 去掉 Hub 上不合适的权限申请
- 把“会议提醒”放回真正贴近用户的设备侧

## 1) 一句话冻结决策

冻结：

- `X-Hub` 不再申请、读取、轮询、展示用户个人日历。
- `X-Terminal` 成为个人日历能力的唯一默认宿主。
- 原始 calendar event 默认只留在 XT 本机，不上传 Hub。
- Hub 如需感知日历，只允许接收最小派生信号，不接原始事件正文。
- `Supervisor` 的 meeting reminder 必须支持“即时语音提醒 + 本地通知兜底”双通道。

## 2) 不做什么

本包第一阶段明确不做：

- 不在 Hub 上保留“可选 Calendar toggle”
- 不把 XT 日历完整同步到 Hub
- 不做跨设备全量 calendar 镜像
- 不开放任意 skill 直接拿原始 calendar 明细
- 不在第一阶段支持复杂写操作（创建 / 修改 / 删除日历事件）
- 不把这件事扩成完整的 travel / inbox / reminders 全域个人运营平台

## 3) 完成态用户体验

### 3.1 Hub 侧体验

用户打开 `X-Hub` 时：

- 不再弹出 Calendar 权限窗口
- Settings 里只看到“Calendar moved to X-Terminal”的说明
- Hub 不再显示 Hub-side meeting reminder 控件

### 3.2 XT 侧体验

用户在 `X-Terminal` 中：

- 只在明确开启“Supervisor Calendar Reminders”时申请 Calendar 权限
- Supervisor 可读取 XT 本机日历中的近期会议
- 在会议临近时，Supervisor 直接进行语音提醒
- 若语音链路当前不可用或被静音，仍会落本地通知兜底

### 3.3 语音提醒体验

默认 reminder phase 冻结为三段：

- `heads_up`: 会前 `15m`
- `final_call`: 会前 `3m`
- `start_now`: 开始时或开始后 `0-1m`

第一阶段语音文案要求：

- 短
- 明确指出会议标题
- 明确指出剩余时间或“已经开始”
- 不自动朗读完整参会人 / notes / location 原文

示例：

- `10:45 的 Phoenix weekly sync 还有 15 分钟开始。`
- `Phoenix weekly sync 还有 3 分钟开始，记得切到会议窗口。`
- `Phoenix weekly sync 已经开始。`

## 4) 权限与数据边界冻结

### 4.1 权限归属

- `Hub`
  - 不持有 calendar permission
  - 不弹 Calendar TCC prompt
- `XT`
  - 持有 EventKit `.event` 读取权限
  - 在 XT 设置或 Supervisor reminder 开启路径里触发授权

### 4.2 数据边界

原始事件字段默认只留在 XT 本地：

- title
- start / end
- location
- join URL
- organizer / attendees
- notes

Hub 默认不能看到上面这些字段。

### 4.3 允许上传的最小派生信号

如果后续确实需要让 Hub 感知“用户当前可能在会议中”，只允许发送最小派生信号，例如：

- `meeting_starting_soon`
- `meeting_in_progress`
- `busy_window`
- `calendar_focus_block`
- `follow_up_candidate`

这些派生信号必须满足：

- 不带原始标题正文，或只带用户明确允许的最小标签
- 不带 notes / attendees / description
- 可按 user policy 整体关闭

## 5) XT 侧架构冻结

### 5.1 新增能力层

第一阶段新增 4 个 XT 本地组件：

1. `XTCalendarAccessController`
   - 负责 EventKit 授权状态读取与授权请求
   - 只暴露 XT 侧状态，不穿透到 Hub

2. `XTCalendarEventStore`
   - 拉取近期会议快照
   - 负责 event normalization、join URL 提取、会议识别

3. `SupervisorCalendarReminderScheduler`
   - 负责 phase 计算、去重、防重放、提醒窗口滚动刷新

4. `SupervisorCalendarVoiceBridge`
   - 把 reminder event 接到现有 `SupervisorSpeechSynthesizer`
   - 在语音不可用时降级到 `UNUserNotificationCenter`

### 5.2 推荐落点

建议首波文件路径冻结为：

- `x-terminal/Sources/Supervisor/XTCalendarAccessController.swift`
- `x-terminal/Sources/Supervisor/XTCalendarEventStore.swift`
- `x-terminal/Sources/Supervisor/SupervisorCalendarReminderScheduler.swift`
- `x-terminal/Sources/Supervisor/SupervisorCalendarVoiceBridge.swift`
- `x-terminal/Sources/UI/SupervisorSettingsView.swift`
- `x-terminal/Sources/UI/XTSystemSettingsLinks.swift`
- `x-terminal/Tests/XTCalendarAccessControllerTests.swift`
- `x-terminal/Tests/XTCalendarEventStoreTests.swift`
- `x-terminal/Tests/SupervisorCalendarReminderSchedulerTests.swift`
- `x-terminal/Tests/SupervisorCalendarVoiceBridgeTests.swift`

### 5.3 现有能力复用

这条链路必须复用已有 XT 能力，而不是重做一套：

- 语音播报：
  - `x-terminal/Sources/Voice/SupervisorSpeechSynthesizer.swift`
- 本地通知兜底：
  - `x-terminal/Sources/UI/HistoryPanelView.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- 系统设置跳转：
  - `x-terminal/Sources/UI/XTSystemSettingsLinks.swift`

## 6) 事件模型冻结

### 6.1 `xt.supervisor_calendar_event.v1`

```json
{
  "schema_version": "xt.supervisor_calendar_event.v1",
  "event_id": "evt_123",
  "source": "eventkit",
  "title": "Phoenix weekly sync",
  "start_at_ms": 0,
  "end_at_ms": 0,
  "location": "Zoom",
  "join_url": "https://...",
  "is_meeting": true,
  "is_all_day": false,
  "visibility": "device_local"
}
```

### 6.2 `xt.supervisor_calendar_reminder.v1`

```json
{
  "schema_version": "xt.supervisor_calendar_reminder.v1",
  "event_id": "evt_123",
  "phase": "heads_up|final_call|start_now",
  "fire_at_ms": 0,
  "spoken": false,
  "notification_fallback_sent": false,
  "dedupe_key": "evt_123:heads_up:1742451000000"
}
```

### 6.3 `xt.supervisor_calendar_signal.v1`

```json
{
  "schema_version": "xt.supervisor_calendar_signal.v1",
  "signal_type": "meeting_starting_soon",
  "starts_in_minutes": 3,
  "busy_until_ms": 0,
  "privacy_level": "derived_only",
  "source_device": "xt_local"
}
```

## 7) Reminder 调度规则冻结

### 7.1 只提醒“像会议”的事件

第一阶段 `is_meeting` 判定建议沿用 Hub 现有经验，但在 XT 本地实现：

- 有 join URL
- 有 attendees
- 或标题 / location / notes 中命中 Zoom / Meet / Teams / Webex 等会议特征

普通 calendar block 在第一阶段可只进入“派生 busy window”，不必强制语音播报。

### 7.2 防打扰规则

第一阶段固定规则：

- 同一事件、同一 phase 只播报一次
- 已结束事件不再补播
- all-day event 不播报
- 如果用户正在进行 active voice conversation，优先延迟到安全窗口或落通知兜底
- 如果 XT 在 quiet hours，默认压低为通知兜底；后续再做可配置策略

### 7.3 去重键

去重键固定为：

- `event_id + normalized_start_at + phase`

如果 EventKit event identifier 变化，但标题和开始时间保持一致，可在第二阶段增加 secondary heuristic，第一阶段先不做复杂补偿。

## 8) Supervisor 语音接入冻结

### 8.1 触发链路

`SupervisorCalendarReminderScheduler` 触发时：

1. 产出 reminder payload
2. 交给 `SupervisorCalendarVoiceBridge`
3. bridge 调用 `SupervisorSpeechSynthesizer`
4. 播报成功则写本地 reminder ledger
5. 播报失败或被 suppress，则发送本地通知兜底

### 8.2 语音策略

第一阶段语音提醒不要求走远端推理生成文案。

默认做法：

- 本地模板化脚本
- 支持中英文 locale
- 使用当前 Supervisor playback source

这样可保证：

- 快
- 不依赖 Hub 可达性
- 不因为模型路由问题错过提醒时机

### 8.3 与 Voice Pack 的关系

如果 `Hub Voice Pack` 可用：

- reminder 直接走当前已解析出的 playback source

如果 `Hub Voice Pack` 不可用：

- 自动回退 `System Speech`

不允许为了“等更好声音”而错过 meeting reminder。

## 9) UI 方案冻结

### 9.1 XT 设置入口

`SupervisorSettingsView` 新增一个窄入口即可，不要第一阶段做大面板：

- `Calendar Reminders`
  - `Off / On`
  - `Authorization Status`
  - `Open System Settings`
  - `Preview Voice Reminder`
  - `Test Notification Fallback`
  - `Simulate Live Delivery`
  - `Preview Phase`：`Heads Up / Final Call / Start Now`
  - `Upcoming Meeting Snapshot`（可选）

说明冻结：

- preview 必须复用真实 `SupervisorCalendarVoiceBridge` 文案模板，不允许 settings 页面手写一套近似文案。
- preview 必须沿用当前 XT 的有效 voice route / locale / speech rate，避免 smoke 结果和真实提醒路径不一致。
- preview 不依赖真实日历事件到时，也不依赖 Hub 在线；它是 XT 本机语音链路的即时自检入口。
- notification fallback test 必须走同一条本地通知 payload 路径，用于在不制造 quiet hours / 真实到时会议的情况下验证兜底支路。
- live delivery simulation 必须直接走 `deliver(...)` 的真实路由决策，用于验证 quiet hours、conversation defer、notification fallback、voice success 这些运行时分支。

### 9.2 Hub 设置入口

Hub 只保留只读说明：

- `Calendar moved to X-Terminal`
- `Hub no longer requests Calendar permission`

不再保留：

- Hub calendar toggle
- Hub calendar enable button
- Hub reminder minute steppers

### 9.3 XT 手工 smoke 路径

冻结一条最短手工验证路径：

1. 打开 `Supervisor Settings -> Calendar Reminders`，开启 reminder。
2. 先依次切换 `Preview Phase = Heads Up / Final Call / Start Now`，每个 phase 都执行一次 `Preview Voice Reminder`。
3. 再对至少一个 phase 执行一次 `Test Notification Fallback`，确认本地通知兜底可以独立触发。
4. 再对至少一个 phase 执行一次 `Simulate Live Delivery`，确认 real route decision 会把当前 XT 运行时状态反映到 smoke 结果里。
5. 确认 preview 实际走的是当前 XT voice backend，而不是单独的测试 TTS 分支。
6. 再授予 Calendar 权限并执行 `Refresh Meetings`，确认 `Upcoming Meeting Snapshot` 能出现本机近期会议。
7. 最后创建一个近时测试会议，确认真实调度链路能分别命中 `heads_up`、`final_call`、`start_now`，且 active conversation / quiet hours 时能按设计延迟或回退通知。

## 10) 与主线边界的关系

这件事虽然来自 personal assistant 方向，但这里明确收窄为一个产品边界修正包：

- 目的是去掉 Hub 侧错误的权限宿主
- 不是把整个 `XT-W3-38` 重新抬成第一优先级

因此本包优先级应理解为：

- `Hub calendar de-scope`：立即执行
- `XT local reminder skeleton`：尽快落
- `更大 personal assistant 扩展`：仍按主线节奏推进，不借本包扩 scope

## 11) 具体执行项

### 11.1 Phase A - Hub cut-off（立即）

- 切掉 Hub 启动时所有 calendar permission 路径
- 移除 Hub UI 中的 calendar enable / reminder 控件
- 从 Hub app template 中移除 calendar usage strings 与 entitlement
- 保留只读状态文案：`Calendar moved to X-Terminal`

### 11.2 Phase B - XT capability skeleton

- 新增 XT EventKit 授权控制器
- 新增 XT 近期会议 snapshot store
- 新增 settings 中的 reminder 开关与授权状态展示
- 新增 system settings deep link：Calendars

### 11.3 Phase C - Reminder scheduler

- 新增 phase 计算
- 新增本地 dedupe ledger
- 新增 active / ended / dismissed filtering
- 锁定 `15m / 3m / start_now` 默认窗口

### 11.4 Phase D - Supervisor voice bridge

- 接 `SupervisorSpeechSynthesizer`
- 接 playback source resolution
- 失败自动走本地通知
- 加 preview / debug evidence

### 11.5 Phase E - Optional derived signal export

- 仅在确有需要时，把 `meeting_starting_soon / busy_window` 等最小派生信号输出给 Hub
- 默认关闭
- 必须单独受 policy / capability gate 控制

## 12) 测试与证据冻结

第一阶段至少补这些测试：

- EventKit 授权状态映射测试
- calendar event normalization 测试
- reminder phase 计算测试
- dedupe / repeat suppression 测试
- quiet hours / active voice fallback 测试
- playback source fallback 测试
- Hub no-calendar-permission docs truth / surface truth 测试

建议证据项：

- XT 打开 reminder 开关后的授权路径录屏
- 临近会议时的语音提醒录屏
- Voice Pack 不可用时的 System Speech fallback 证据
- Hub 启动不再弹 Calendar 权限的录屏

## 13) 当前建议推进顺序

本包建议按下面顺序落，不要倒着做：

1. `Hub cut-off`
2. `XT EventKit skeleton`
3. `reminder scheduler`
4. `Supervisor voice bridge`
5. `derived signal export`（若需要）

如果只完成了前两步，就已经明显改善用户体验：

- Hub 不再乱弹权限
- 日历能力的设备边界回到正确位置

## 14) 当前工单完成定义

这个工单第一轮完成定义不是“XT 日历全功能上线”，而是：

- Hub 侧 calendar 已彻底降级为只读说明
- Hub 构建产物不再声明 calendar entitlement / usage strings
- XT 有明确、可执行、可拆分的本地 calendar reminder 实施包
- 后续可以直接按 `Phase B -> Phase D` 往下推，不再反复争论边界

## 15) 当前落地状态（2026-03-21）

### 15.1 已完成

- `Hub cut-off` 已完成
- Hub 启动路径不再申请 Calendar 权限
- Hub 设置面板只保留 `Calendar moved to X-Terminal` 的只读说明
- Hub app template 已移除 calendar usage strings 与 calendar entitlement
- XT 侧日历提醒骨架已完成
- 已落地 `XTCalendarAccessController`
- 已落地 `XTCalendarEventStore`
- 已落地 `SupervisorCalendarReminderScheduler`
- 已落地 `SupervisorCalendarVoiceBridge`
- `SupervisorSettingsView` 已提供 `Preview Voice Reminder / Test Notification Fallback / Simulate Live Delivery / Preview Phase`
- XT 打包产物已恢复，当前可用产物路径为 `build/X-Terminal.app`

### 15.2 最新验证证据

- `swift build`（`x-terminal/`）通过
- `swift test --skip-build --filter SupervisorCalendarReminderSchedulerTests` 通过，`5/5`
- `swift test --skip-build --filter SupervisorCalendarVoiceBridgeTests` 通过，`11/11`
- `swift test --filter XTCalendarBoundaryDocsTruthSyncTests` 通过，`4/4`
- `bash x-terminal/tools/build_xterminal_app.command` 通过
- `bash x-terminal/scripts/ci/xt_w3_40_calendar_boundary_evidence.sh` 通过
- `bash x-terminal/scripts/ci/xt_w3_40_real_device_smoke_template.sh` 可生成真机 smoke 报告模板
- `bash x-terminal/scripts/ci/xt_w3_40_real_device_smoke_validate.sh <report.json>` 可校验已填写的真机 smoke 报告
- 打包产物 `build/X-Terminal.app/Contents/Info.plist` 已确认包含：
  - `NSCalendarsFullAccessUsageDescription`
  - `NSCalendarsUsageDescription`
- `XT-W3-40` 自动化 evidence 报告路径：
  - `x-terminal/build/reports/xt_w3_40_calendar_boundary_evidence.v1.json`
  - `x-terminal/build/reports/xt_w3_40_calendar_boundary_logs/`
- `XT-W3-40` 真机 smoke 目标报告路径：
  - `x-terminal/build/reports/xt_w3_40_real_device_smoke_evidence.v1.json`
  - 模板默认输出：`x-terminal/build/reports/xt_w3_40_real_device_smoke_evidence.template.v1.json`
- 当前打包脚本默认以 `App sandbox disabled` 方式签名，用于 direct-copy 分发；这一路径下 Calendar 权限依赖 XT usage strings + TCC，而不是启用沙箱 entitlement

### 15.3 当前仍待补的验证

- 真机手工 smoke 还未补齐
- 仍需按 `9.3 XT 手工 smoke 路径` 实跑：
  - `Preview Phase` 三档语音预览
  - `Test Notification Fallback`
  - `Simulate Live Delivery`
  - Calendar 授权后 `Refresh Meetings`
  - 一次真实近时会议的 `heads_up / final_call / start_now`
- 实跑后需把结果填写进：
  - `x-terminal/build/reports/xt_w3_40_real_device_smoke_evidence.v1.json`
  - 可先运行：`bash x-terminal/scripts/ci/xt_w3_40_real_device_smoke_template.sh`
  - 填完后校验：`bash x-terminal/scripts/ci/xt_w3_40_real_device_smoke_validate.sh x-terminal/build/reports/xt_w3_40_real_device_smoke_evidence.v1.json`
  - 若要把它纳入 release gate：`XT_GATE_VALIDATE_CALENDAR_REAL_DEVICE_SMOKE=1 bash x-terminal/scripts/ci/xt_release_gate.sh`
- 如后续要切到 sandbox 分发，还需要单独以 `XTERMINAL_ENABLE_APP_SANDBOX=1` 重新签名并验证 calendar entitlement 路径

### 15.4 这轮额外修复

- 修复了 XT header 侧旧接口漂移，去掉已废弃的 heartbeat popover 组装参数，恢复 `swift build` 与 release packaging
- 修复了 `SupervisorSystemPromptParamsBuilder.build(...)` 调整后遗留的测试调用顺序问题，避免日历提醒定向测试被无关测试源码错误阻塞
