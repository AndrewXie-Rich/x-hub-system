# XT-W3-39 Hub Voice Pack + Supervisor TTS 实现包 v1

- version: v1.0
- updatedAt: 2026-03-20
- owner: XT-L2（Primary）/ Hub-L5 / Voice Runtime / Product / Security / QA
- status: active
- scope: `XT-W3-39`（把当前 Supervisor 的系统朗读器播报升级为 `Hub-first Voice Pack` 播放架构，支持中英文切换、不同音色与语速调节，但不开放克隆音色）
- parent:
  - `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-29-whisperkit-funasr-voice-runtime-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-38-h-supervisor-persona-center-implementation-pack-v1.md`
  - `docs/memory-new/xhub-multimodal-supervisor-control-plane-architecture-memo-v1.md`
  - `docs/xhub-local-provider-runtime-and-transformers-integration-v1.md`

## 0) 为什么单开这份包

当前 Supervisor 的语音输入已经有基础：

- `FunASR / WhisperKit / system speech compatibility` 已经能覆盖唤醒、听写、语音会话入口。
- `Voice Persona` 已经能调节播报节奏和口吻。
- Hub 模型市场已经能下载、登记、路由一部分本地音频相关模型。

但现在的“声音本身”仍然停在系统朗读器：

- XT 侧播报主链还是 `AVSpeechSynthesizer`
- 用户能调说话风格，但不能真正换成更自然的 Hub 托管音色
- 当前市场与本地 runtime 对 `speech_to_text` 已有入口，但对 `text_to_speech` 还没有正式任务面

因此这份包要解决的不是“语音输入”，而是“Supervisor 怎么更自然地说出来”：

- 用户可在 XT 中切换中文 / 英文播报与识别 locale
- 用户可选不同音色
- 用户可调说话速度
- 音色由 Hub 统一下载、管理、运行
- XT 只做播放与真实状态展示
- 失败时诚实回退到 `System Speech`

## 1) 一句话冻结决策

冻结：

- `Voice Pack` 由 `X-Hub` 下载、托管、运行，`X-Terminal` 不直接下载或训练语音模型。
- V1 只支持“选择不同音色”，不支持“克隆音色 / 上传用户声音样本 / 任意第三方未签名声线包”。
- Supervisor 的“说什么”继续由 brief / TTS script 决定；Voice Pack 只决定“怎么说”。
- XT 必须真实展示本轮实际播报来源：`Hub Voice Pack` 或 `System Speech Fallback`。

## 2) 不做什么

V1 明确不做：

- 用户声音克隆
- 名人成色模仿
- 企业环境下的任意第三方声线包自由导入
- 把 voice pack 变成高风险授权因子
- 让 XT 在脱离 Hub 管理时偷偷维持“高级音色”假象

## 3) 完成态用户体验

### 3.1 用户可选音色

用户在 X-Terminal 的 Supervisor 设置里能看到：

- `Playback Source`
  - `Automatic`
  - `Hub Voice Pack`
  - `System Speech`
- `Speech Language`
  - `Chinese`
  - `English`
- `Voice Color`
  - `Neutral`
  - `Warm`
  - `Clear`
  - `Bright`
  - `Calm`
- `Speech Rate`
  - `0.8x -> 1.25x`
- `Preferred Voice Pack`
  - `Warm Chinese`
  - `Calm Executive`
  - `Neutral Operator`
  - `Bright Assistant`

### 3.2 播报真实显示

Supervisor 会清楚显示：

- `Supervisor Voice (Warm Chinese) Online`
- 或 `Supervisor Voice (System Fallback) Online`

不允许界面写着高级音色，实际偷偷用系统 voice。

### 3.3 失败时 fail-soft，但必须可见

如果 Hub voice route 不可用：

- 播报允许自动回退到系统朗读器
- 但 UI / doctor / audit 必须保留：
  - 本次期望的 voice pack
  - 实际命中的 playback source
  - fallback 原因

## 4) 机读契约冻结

### 4.1 `xhub.voice_pack_binding.v1`

```json
{
  "schema_version": "xhub.voice_pack_binding.v1",
  "voice_pack_id": "hub_voice_zh_warm_v1",
  "display_name": "Warm Chinese",
  "task_kinds": ["text_to_speech"],
  "input_modalities": ["text"],
  "output_modalities": ["audio"],
  "languages": ["zh-CN"],
  "persona_hints": ["conversational", "calm"],
  "style_tags": ["warm", "clear", "briefing_safe"],
  "offline_ready": true,
  "signed_source": true,
  "updated_at_ms": 0
}
```

### 4.2 `xt.supervisor_tts_playback_resolution.v1`

```json
{
  "schema_version": "xt.supervisor_tts_playback_resolution.v1",
  "requested_source": "automatic|hub_voice_pack|system_speech",
  "resolved_source": "hub_voice_pack|system_speech",
  "preferred_voice_pack_id": "hub_voice_zh_warm_v1",
  "resolved_voice_pack_id": "hub_voice_zh_warm_v1",
  "reason_code": "preferred_hub_voice_pack_ready",
  "fallback_from": "",
  "audit_ref": "audit-xxxx"
}
```

### 4.3 `xhub.local_tts_generate.request.v1`

```json
{
  "schema_version": "xhub.local_tts_generate.request.v1",
  "task_kind": "text_to_speech",
  "model_id": "hub_voice_zh_warm_v1",
  "input": {
    "text": "Phoenix 项目目前卡在远端模型授权。",
    "locale": "zh-CN",
    "persona": "calm",
    "voice_color": "warm",
    "speech_rate": 1.0,
    "priority": "normal"
  }
}
```

### 4.4 `xhub.local_tts_generate.response.v1`

```json
{
  "schema_version": "xhub.local_tts_generate.response.v1",
  "ok": true,
  "model_id": "hub_voice_zh_warm_v1",
  "audio_format": "wav",
  "audio_clip_ref": "hub://audio/clip/abc123",
  "duration_ms": 2460,
  "usage": {
    "input_chars": 18
  }
}
```

## 5) 架构冻结

### 5.1 `ASR / Wake` 与 `TTS / Playback` 必须拆开

当前 `VoiceRouteMode` 解决的是输入链路：

- FunASR streaming
- WhisperKit local
- system speech compatibility

这和输出链路不是一回事。

V1 必须正式拆成两套：

- `input route`
- `playback source`

否则后面一接 Hub Voice Pack，会把“听用户说话”和“Supervisor 发声”硬绑在一起，配置会越来越乱。

### 5.2 播报层必须可插拔

XT 播报层应固定支持：

- `Hub Voice Pack`
- `System Speech`

其中：

- `Hub Voice Pack` 是首选高级路径
- `System Speech` 是兼容回退路径

### 5.3 Hub 是唯一 Voice Pack 管理面

Hub 固定持有：

- 语音包下载
- 语音包 manifest / allowlist / signature
- 运行与 warmup
- 审计
- kill-switch / capability gate

XT 不持有：

- 模型下载器
- 语音包来源真相
- 克隆训练入口

## 6) 详细执行拆分

### XT-W3-39-A 当前已落地切片（2026-03-19）

- XT 设置面已经补上：
  - `Speech Language`
  - `Voice Color`
  - `Speech Rate`
- 当前系统 fallback 已支持：
  - 中文 / 英文 locale 切换
  - best-effort 音色偏好排序
  - 语速倍率调节
- 当前兼容保证：
  - 旧 `settings.json` 缺失新字段时自动回退默认值
  - `System Speech Compatibility` 的 locale 会随设置更新，不再卡在旧 locale
- 已验证：
  - `SupervisorSpeechSynthesizerTests`
  - `XTerminalSettingsSupervisorAssistantTests`

### XT-W3-39-A 播报源抽象 + 设置持久化地基

- 目标：把 XT 从“只有系统朗读器”改成“可解析播放源”
- 代码落点：
  - `x-terminal/Sources/Voice/VoiceRuntimeTypes.swift`
  - `x-terminal/Sources/Voice/SupervisorSpeechSynthesizer.swift`
  - `x-terminal/Sources/UI/SupervisorSettingsView.swift`
  - `x-terminal/Tests/SupervisorSpeechSynthesizerTests.swift`
- 具体任务：
  - 新增 `VoicePlaybackPreference`
  - 新增 `VoicePlaybackResolution`
  - 给 `VoiceRuntimePreferences` 增加：
    - `playbackPreference`
    - `preferredHubVoicePackID`
    - `timbre`
    - `speechRateMultiplier`
  - 给 `SupervisorSpeechSynthesizer` 增加 playback resolver
  - 给 XT 设置页增加：
    - `Speech Language`
    - `Voice Color`
    - `Speech Rate`
  - 允许未来注入 `Hub Voice Pack speak sink`
  - 保留 system speech 作为默认 fallback
- DoD：
  - 旧设置文件 decode 不崩
  - 用户可明确选择 `Automatic / Hub Voice Pack / System Speech`
  - 用户可明确切换 `Chinese / English`
  - 用户可明确切换 `Voice Color / Speech Rate`
  - 当 Hub Voice Pack 未接通时，解析结果必须诚实回到 `System Speech`

### HUB-VP-W1 `text_to_speech` 本地任务面 + manifest 扩展

- 目标：让 Hub 模型目录能正式承认 TTS 模型
- 代码落点：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/LocalModelManifest.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelModels.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/ModelStore.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift`
- 具体任务：
  - 新增 `task_kind=text_to_speech`
  - 新增 `output_modality=audio`
  - 新增 voice-pack style metadata：
    - `languages`
    - `persona_hints`
    - `style_tags`
  - 让模型市场 / Library / 搜索过滤里能识别 Voice Pack
- DoD：
  - 本地 manifest 可声明 TTS
  - UI 可把 TTS 模型识别成 `audio -> speech out`

当前已落地切片（2026-03-19）：

- `text_to_speech` 已加入 Hub 本地能力默认值：
  - input `text`
  - output `audio`
- Hub 本地任务目录已识别 `Text to Speech`
- Model Library / Discover Market 的 `Audio / Speech` 分组已把 TTS 归进去
- Transformers 文件夹导入已能识别 `kokoro / melo / parler / bark / vits / tts` 这类 TTS 信号
- 仍未完成：
  - 真正的 Hub `text_to_speech` runtime 执行
  - Voice Pack metadata（`languages / persona_hints / style_tags`）正式入库

### HUB-VP-W2 Hub 本地 TTS runtime 适配

- 目标：Hub 能真正把文本合成音频片段
- 代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/python-runtime/python_service/providers/base.py`
  - `x-hub/python-runtime/python_service/providers/transformers_provider.py`
  - `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
- 具体任务：
  - 新增 `text_to_speech` request/response contract
  - 新增本地 runtime 任务分发
  - 支持短句合成，输出 `wav` 或 `opus`
  - 支持 duration / input_chars usage 回传
  - 对超长文本 fail-closed
- DoD：
  - Hub 本地 runtime 能对一条短句生成音频 clip
  - usage / deny_code / fallback 语义完整

### HUB-VP-W3 模型市场下载、登记、删除与 allowlist

- 目标：用户能在 Hub 中下载 / 删除 Voice Pack
- 代码落点：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/LMStudioMarketBridge.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/AddModelSheet.swift`
- 具体任务：
  - 让市场入口支持 Voice Pack discover
  - 下载后自动导入 Model Library
  - 为 Voice Pack 单独展示：
    - style
    - language
    - signed/offline status
  - 支持一键删除
- DoD：
  - Voice Pack 可像本地模型一样下载、导入、删除
  - 删除后 XT 下次解析不得继续假装可用

### XT-W3-39-B XT <-> Hub TTS IPC + clip playback

- 目标：XT 能请求 Hub 合成音频并播放
- 代码落点：
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - `x-terminal/Sources/Voice/`
- 具体任务：
  - 新增 `requestSupervisorTTSClip(...)`
  - 支持本地 socket IPC / remote gRPC
  - XT 拿到 `audio_clip_ref` 后拉取并本地播放
  - 播放失败时自动回退到系统朗读器
- DoD：
  - XT 可对一段 `tts_script` 请求 Hub clip 并播放
  - fallback 路径稳定

### XT-W3-39-C Supervisor 播报主链升级

- 目标：现有 heartbeat / query reply / authorization reply 都能走 Hub Voice Pack
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Voice/SupervisorSpeechSynthesizer.swift`
  - `x-terminal/Sources/UI/Supervisor/SupervisorConversationPanel.swift`
- 具体任务：
  - 统一 `tts_script -> playback resolution -> clip or fallback`
  - 记住最近一次 resolved playback source
  - UI 顶栏显示当前 Supervisor Voice 来源
- DoD：
  - heartbeat reply 与主动播报共享同一播放链
  - 用户能看见当前真实音源

### XT-W3-39-D Persona Center 与 Voice Pack 映射

- 状态：`completed_v1`
- 目标：Persona 选项能绑定默认音色
- 代码落点：
  - `x-terminal/Sources/UI/Supervisor/SupervisorPersonaCenterView.swift`
  - `x-terminal/Sources/LLM/XTerminalSettings.swift`
  - `x-terminal/Sources/Voice/SupervisorVoicePreferenceOverlay.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Tests/SupervisorPersonaRegistryTests.swift`
  - `x-terminal/Tests/SupervisorVoicePreferenceOverlayTests.swift`
- 具体任务：
  - 在 persona slot 中新增可选 `voicePackOverrideID`
  - active persona 生效时覆盖全局默认 voice pack
  - 未覆盖时回退到全局播放偏好
- DoD：
  - 人格和音色可绑定但不耦死
- 本轮已落地：
  - `SupervisorPersonaSlot` 已新增 `voicePackOverrideID`
  - active persona 已通过 `xtVoicePreferencesApplyingPersonaOverlay(...)` 覆盖：
    - `voice persona`
    - `preferredHubVoicePackID`
  - Persona Center 已新增 `Hub Voice Pack` picker，并显示当前 slot 的 overlay 说明
  - Supervisor Settings 已区分：
    - requested hub voice pack
    - effective hub voice pack
    - active persona voice pack overlay
  - 兼容测试已覆盖：
    - legacy persona slot decode 缺少 `voice_pack_override_id`
    - overlay 覆盖与 fallback 行为
  - 已验证：
    - `swift test --filter SupervisorPersonaRegistryTests`
    - `swift test --filter SupervisorVoicePreferenceOverlayTests`
    - `swift test --filter XTerminalSettingsSupervisorAssistantTests`
    - `swift test --filter SupervisorSpeechSynthesizerTests`

### XT-W3-39-E Doctor / Readiness / Audit 透明化

- 状态：`completed_v1`
- 目标：语音输出路径必须可诊断
- 代码落点：
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-terminal/Sources/Voice/VoiceReadinessAggregator.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/UI/XHubDoctorOutput.swift`
  - `x-terminal/Tests/XTUnifiedDoctorReportTests.swift`
  - `x-terminal/Tests/XHubDoctorOutputTests.swift`
  - `x-terminal/Tests/SupervisorPersonaRoutingTests.swift`
- 具体任务：
  - 在 Unified Doctor 新增 `Voice Playback Readiness`
  - 诊断输入使用 persona overlay 之后的 effective voice prefs，而不是裸全局配置
  - `XTUnifiedDoctor.swift` 产出的 XT 原生 source truth 继续受 `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json` 约束；导出的 generic doctor bundle 才走 `docs/memory-new/schema/xhub_doctor_output_contract.v1.json`
  - 若 voice playback 诊断既有结构化 source report 字段又有 detail lines，export 必须优先复用结构化 source truth，不得反向回退成文本解析优先
  - 导出 diagnostics 时保留：
    - requested source
    - resolved source
    - preferred voice pack
    - last fallback reason
- DoD：
  - 用户能看见“为什么没用上 Hub Voice Pack”
  - Doctor / export / persona overlay 三处诊断语义一致
- 本轮已落地：
  - `VoiceReadinessCheck.ttsReadiness` 已映射到 Unified Doctor 新 section：`voice_playback_readiness`
  - Unified Doctor 现在会把播放降级原因直接带进 section detail lines
  - AppModel / Supervisor diagnostics 已统一使用 `effectiveVoicePreferencesForDiagnostics()`
  - 当前 execution persona 的 `voice persona` / `voicePackOverrideID` 会真实影响 doctor/readiness 结果
  - Generic doctor bundle 已保留 voice playback 细节，不会在导出时丢掉 fallback 证据
  - 顺手拆分了 `SupervisorAuditDrillDownResolver.refreshFingerprint(...)`，修掉 Swift 编译器 type-check 超时，避免验证阶段卡死
- 已验证：
  - `swift test --filter XTUnifiedDoctorReportTests`
  - `swift test --filter "XHubDoctorOutputTests|SupervisorPersonaRoutingTests|VoiceReadinessAggregatorTests|XTerminalSettingsSupervisorAssistantTests"`
  - `swift test --filter "SupervisorManagerVoicePlaybackRuntimeTests|SupervisorVoicePreferenceOverlayTests"`

### XT-W3-39-F 安全边界 + allowlist + kill-switch

- 状态：`in_progress`
- 目标：把 Voice Pack 纳入 Hub 安全治理
- 代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_task_policy.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_tts.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_task_policy.test.js`
- 具体任务：
  - 新增 `ai.audio.tts.local` 或等价 capability
  - 支持 allowlist / kill-switch
  - 默认禁用“voice cloning”
  - 审计每次 TTS 使用的 `model_id / source / fallback`
- DoD：
  - 企业/政府模式下可关闭第三方 voice pack
- 本轮已落地：
  - `text_to_speech` 任务现在走独立 capability alias：`ai.audio.tts.local`
  - 该 alias 会向后兼容映射到既有 proto capability：`CAPABILITY_AI_AUDIO_LOCAL`
  - kill-switch 现在同时接受：
    - `ai.audio.tts.local`
    - 旧别名 `ai.audio.local`
    这样不会打断已有配置
- `local_tts.js` 现在会为每次 TTS 返回结构化 `tts_audit`
- `tts_audit` 会固定记录：
    - `model_id / resolved_model_id`
    - `route_source`
    - `source_kind / output_ref_kind`
    - `engine_name / speaker_id`
    - `fallback_mode / fallback_reason_code`
    - `deny_code / raw_deny_code`
- 同时补了一条稳定的 `tts_audit_line`，方便后续直接挂到 Hub 审计事件或诊断日志

2026-03-20 继续推进

- 已把同一套 `tts_audit` / `tts_audit_line` 语义补到 XT 当前真实走的 macOS RELFlowHub IPC 主路径：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/HubModels.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubVoiceTTSSynthesisService.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
- RELFlowHub 现在会在每次 `voice_tts_synthesize` 返回时：
  - 生成结构化 `tts_audit`
  - 生成稳定 `tts_audit_line`
  - 追加写入 Hub 侧 `voice_tts_audit.log`
- XT 现在会把 IPC 返回的 `tts_audit` / `tts_audit_line` 解码到 `HubIPCClient.VoiceTTSResult`
- Supervisor 的真实播放路径现在会把 `tts_audit_line` 继续带入 runtime activity，避免“播了但看不到真实 TTS 审计线”的黑箱
- Hub diagnostics bundle 现在额外导出 `voice_tts_audit.log`

验证记录

- 通过：
  - `cd x-hub/macos/RELFlowHub && swift test --filter HubVoiceTTSSynthesisServiceTests`
  - `cd /tmp/<xt_snapshot> && swift test --filter "HubIPCClientVoiceTTSTests|SupervisorSpeechSynthesizerTests|SupervisorManagerVoicePlaybackRuntimeTests"`
- 说明：
  - 直接在活跃工作区跑 `x-terminal` build/test 时，源文件会被并发改动导致 SwiftPM 报 `input file was modified during the build`
  - 用最小 package snapshot（`Package.swift + Sources + Tests`）做隔离验证后，TTS 相关 15 个测试已全部通过
- 已验证：
  - `node src/local_task_policy.test.js`
  - `node src/local_tts.test.js`
  - `node src/local_audio.test.js`

### XT-W3-39-G 回归、证据与 release gate

- 目标：防止“表面是高级音色，实际退回系统 voice”变成不可见回归
- 测试落点：
  - `x-terminal/Tests/SupervisorSpeechSynthesizerTests.swift`
  - `x-terminal/Tests/VoiceWakeProfileStoreTests.swift`
  - `x-hub/.../LocalProviderRuntimeSchemaTests.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/local_audio.test.js`
- 具体任务：
  - decode 兼容测试
  - playback resolution 测试
  - Hub TTS contract 测试
  - fallback visibility 测试
- DoD：
  - 新增 contract 被测试覆盖
  - `XT-G4 / Reliability` 会实际执行 `--xt-supervisor-voice-smoke`，并把 `.axcoder/reports/xt_supervisor_voice_smoke.runtime.json` 纳入 release evidence

## 7) 本轮推进顺序

当前建议顺序：

1. `XT-W3-39-A`
2. `HUB-VP-W1`
3. `XT-W3-39-B`
4. `XT-W3-39-C`
5. `XT-W3-39-D`
6. `XT-W3-39-E/F/G`

## 8) 当前已开始的内容

已开始：

- `XT-W3-39-A` 基础地基
  - 将语音设置从“只管输入 route”扩成“输入 route + 输出 playback source”
  - 给 XT 播报层预留 `Hub Voice Pack` 播放入口，但当前默认仍走 `System Speech`

未开始：

- Hub `text_to_speech` 正式 runtime
- Voice Pack 市场下载与导入
- Persona 与 Voice Pack 绑定的后续 polish
  - persona 卡面更强的音色标识
  - per-persona playback diagnostics drill-down

## 9) 当前进度快照（2026-03-19 PM）

### 9.1 已完成

- `XT-W3-39-A` 已不再只是“地基”，而是已经进入可用原型：
  - XT 设置面已有：
    - `Playback Source`
    - `Speech Language`
    - `Voice Color`
    - `Speech Rate`
    - `Preferred Hub Voice Pack`
  - XT 播报层已能区分：
    - `requested output`
    - `resolved output`
    - `actual playback result`
- `HUB-VP-W1` 已部分完成：
  - Hub / XT 共享模型结构已支持 `voiceProfile`
  - `voiceProfile` 已结构化承载：
    - `languageHints`
    - `styleHints`
    - `engineHints`
  - `voiceProfile` 已沿着：
    - Market import
    - Manual import
    - Catalog
    - State
    - State 回填 Catalog
    保留，不会中途丢失
- `XT-W3-39-B` 已部分完成：
  - XT 已能经由 `HubIPCClient.synthesizeVoiceViaLocalHub(...)` 请求 Hub 生成音频
  - XT 已支持本地 clip 播放
  - 失败时会诚实回退到 `System Speech`
- `XT-W3-39-C` 已部分完成：
  - `Preview Voice`
  - `heartbeat`
  - `query reply`
  已共享同一条 playback resolution 主链
- `XT-W3-39-D` 已完成 v1：
  - Persona slot 可独立绑定：
    - `Voice Overlay`
    - `Hub Voice Pack`
  - active persona 现在不只覆盖 prompt / 说话风格，也会覆盖生效中的 voice pack 选择
  - 旧 registry decode 已兼容：
    - 缺失 `voice_pack_override_id` 时自动回填为空，不会把已有 persona 配置打爆
  - 关键回归已补：
    - `SupervisorVoicePreferenceOverlayTests`
    - `SupervisorPersonaRegistryTests`
    - `XTerminalSettingsSupervisorAssistantTests`
- `XT-W3-39-E` 已明显推进：
  - Unified Doctor 新增 `Voice Playback Readiness`
  - Doctor 现在会直接展示：
    - `requested_playback_source`
    - `resolved_playback_source`
    - `preferred_voice_pack_id`
    - `resolved_voice_pack_id`
    - `fallback_from`
  - doctor/readiness 已改为读取 persona overlay 后的 effective voice prefs
  - diagnostics export 也会保留同一组 playback 证据，不再只停留在设置页
- 新增能力：
  - Automatic 模式现在不再是空壳
  - XT 会根据当前：
    - `Speech Language`
    - `Voice Color`
    自动推荐最合适的 voice pack
  - 这套推荐结果已经接到真实播放链路，不只是 UI 文案

### 9.2 仍未完成

- `HUB-VP-W2` 只完成了“兼容回退可播”，还没完成“原生 TTS 模型推理可播”
- 当前大量实际播报仍然会落到：
  - `deviceBackend=system_voice_compatibility`
  - `fallbackMode=system_voice_compatibility`
- 也就是说：
  - “Hub-first Voice Pack 路由与状态面”已经成型
  - “下载的语音模型真正自己发声”还没有完成

### 9.3 当前阶段判断

- 当前成熟度：`prototype_working`
- 不应再对外表述成“原生语音模型已全面接通”
- 可以表述成：
  - Supervisor 语音播报控制面已完成主要闭环
  - Hub Voice Pack 已支持识别、推荐、选择、状态展示与真实回退
  - 原生 TTS 引擎执行仍在主线收口中

## 10) 下一阶段主线：XT-W3-39-H 原生 TTS 模型执行闭环

### 10.1 目标

把当前“Hub 兼容回退能播”推进为“至少一类下载的 voice pack 能原生本地推理发声”，并且让 XT 能明确区分：

- 原生语音模型发声
- 系统兼容回退发声

V1 主线只要求先打通一个引擎。

建议顺序：

1. `Kokoro`
2. `MeloTTS`
3. `CosyVoice`

### 10.2 切片 H1：运行时契约冻结

- 编号：`XT-W3-39-H1`
- 状态：`completed`
- owner: `Hub-L5 / Runtime`
- 优先级：`P0`
- 目标：把原生 TTS 结果的 contract 补成可区分 native / fallback 的形式
- 代码落点：
  - `x-hub/python-runtime/python_service/providers/transformers_provider.py`
  - `x-hub/grpc-server/hub_grpc_server/src/local_tts.js`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubVoiceTTSSynthesisService.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/HubModels.swift`
- 具体任务：
  - 在 TTS 响应里增加：
    - `engineName`
    - `speakerId`
    - `nativeTTSUsed`
    - `fallbackMode`
    - `fallbackReasonCode`
  - 约定：
    - 如果走系统兼容回退：
      - `nativeTTSUsed=false`
      - `fallbackMode=system_voice_compatibility`
    - 如果走原生模型：
      - `nativeTTSUsed=true`
      - `fallbackMode=""`
- DoD：
  - Hub 返回结果可以被 XT 一眼判断“这次是不是原生语音模型”
  - 不允许只有 `ok=true`，却看不出是不是 fallback
- 本轮已落地：
  - Hub shared model / XT IPC mirror 已增加：
    - `engineName`
    - `speakerId`
    - `nativeTTSUsed`
    - `fallbackReasonCode`
  - Hub service / Node local_tts / XT ACK 已完成透传
  - 兼容测试已覆盖字段解码与映射

### 10.3 切片 H2：Hub TTS provider 执行路径拆分

- 编号：`XT-W3-39-H2`
- 状态：`completed_v1`
- owner: `Hub-L5 / Runtime`
- 优先级：`P0`
- 目标：把 `text_to_speech` 从单一 fallback 逻辑拆成：
  - native provider path
  - fallback path
- 代码落点：
  - `x-hub/python-runtime/python_service/providers/transformers_provider.py`
  - `x-hub/python-runtime/python_service/providers/base.py`
  - `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
- 具体任务：
  - 新增 `_run_tts_task_native_or_fallback(...)`
  - 新增 provider 内部判断：
    - 当前模型是否支持 native TTS
    - 当前 runtime 依赖是否齐备
    - 当前 speaker / locale / style 是否可满足
  - 只有 native 失败且 policy 允许时，才进入 system fallback
  - fail-closed 条件：
    - policy 不允许 fallback
    - native 依赖缺失且 fallback 也禁用
    - 模型不支持当前 locale / speaker
- DoD：
  - `text_to_speech` 执行主函数不再默认直接走系统兼容回退
  - native path 和 fallback path 在日志与返回值上可区分
- 本轮已落地：
  - `transformers_provider.py` 已新增：
    - `_run_tts_task_native(...)`
    - `_run_tts_task_native_or_fallback(...)`
    - `_decorate_tts_result(...)`
  - 当前执行顺序已变成：
    - 先判定/尝试 native path
    - native 失败后才进入 system fallback
  - 当前 generic voice pack 若没有明确 engine hint，会 fail-closed 为：
    - `reasonCode=tts_native_engine_not_supported`
  - 若允许 fallback 且系统语音可用，则会返回：
    - `engineName=system_voice_compatibility`
    - `nativeTTSUsed=false`
    - `fallbackMode=system_voice_compatibility`
    - `fallbackReasonCode=<native 失败原因>`
  - 说明：
    - 这一步只是把执行路径和真相拆开
    - 真实 native 引擎推理仍待 `H3`

### 10.4 切片 H3：Kokoro 原生执行适配

- 编号：`XT-W3-39-H3`
- 状态：`completed_v1`
- owner: `Hub-L5 / Runtime`
- 优先级：`P0`
- 目标：先把 `Kokoro` 打通，作为第一个真实可用 voice pack 引擎
- 代码落点：
  - `x-hub/python-runtime/python_service/providers/transformers_provider.py`
  - 允许新增：
    - `x-hub/python-runtime/python_service/providers/tts_kokoro_adapter.py`
  - 相关测试：
    - `x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
- 具体任务：
  - 新增 `Kokoro` 检测逻辑：
    - 从 `model_id / model_path / config / voiceProfile.engineHints` 识别
  - 新增 Kokoro adapter：
    - 文本输入
    - locale 选择
    - speaker / style 选择
    - 生成 wav/aiff
  - 把输出统一映射回 Hub TTS contract
- DoD：
  - 指向 Kokoro voice pack 的 TTS 请求，在依赖齐备时不再返回 `text_to_speech_runtime_unavailable`
  - 返回结果中：
    - `nativeTTSUsed=true`
    - `engineName=kokoro`
  - 生成音频文件真实存在且可播放
- 本轮已落地：
  - 新增：
    - `x-hub/python-runtime/python_service/providers/tts_kokoro_adapter.py`
  - `transformers_provider.py` 已接入 Kokoro native path
  - 当前已支持：
    - 通过 `voiceProfile.engineHints=["kokoro"]`
    - 或 `model_id / model_path` 命中 `kokoro`
    - 识别为 Kokoro voice pack
  - 当前 native 成功路径会返回：
    - `engineName=kokoro`
    - `nativeTTSUsed=true`
    - `audioFormat=wav`
    - `speakerId=<config / filesystem 推断结果或 default>`
  - 当前 speaker 选择仍是最小实现：
    - 优先读模型目录 `config.json`
    - 再读 `voices/` 等文件系统线索
    - 复杂 locale/style speaker 映射仍留给 `H4`

### 10.5 切片 H4：Voice Color / Locale -> 引擎 speaker 映射

- 编号：`XT-W3-39-H4`
- 状态：`completed_v1`
- owner: `Voice Runtime / Product`
- 优先级：`P0`
- 目标：让 XT 的抽象偏好真正落到引擎内部 speaker/preset，而不是只传一个宽泛字符串
- 代码落点：
  - `x-hub/python-runtime/python_service/providers/transformers_provider.py`
  - `x-terminal/Sources/Voice/HubVoicePackCatalog.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelModels.swift`
- 具体任务：
  - 设计映射层：
    - `zh-CN + warm`
    - `zh-CN + clear`
    - `en-US + warm`
    - `en-US + calm`
  - 为 `Kokoro` 先落一套最小可行 speaker map
  - 若模型没有对应 speaker：
    - 返回明确原因
    - 决定是否 fallback
- DoD：
  - 同一个引擎下切换 `Warm / Clear` 能听出差异
  - 切换中英文能优先命中合适 speaker 或 preset
- 本轮已落地：
  - `tts_kokoro_adapter.py` 已补上最小可行 route map：
    - `zh-CN + warm`
    - `zh-CN + clear`
    - `en-US + warm`
    - `en-US + calm`
  - `bright -> clear`、`soft/gentle/soothing -> calm`、`studio/crisp -> clear` 已纳入 route/style 归一化
  - speaker 发现已支持：
    - `config.json` voices 列表
    - `voices/` / `speaker/` 文件系统线索
    - 并跳过 `voices/` 目录名本身这类伪 token
  - 已验证：
    - `zh-CN + bright` 会命中 `zh_clear_f1`
    - `en-US + calm` 会命中 `bf_emma`
  - XT Automatic 推荐已对 Kokoro 可原生支持的 route 提升优先级，减少明知会回退的包被优先选中

### 10.6 切片 H5：XT 播放结果真相展示

- 编号：`XT-W3-39-H5`
- 状态：`in_progress`
- owner: `XT-L2`
- 优先级：`P1`
- 目标：让 XT 的播放状态明确写出“本次到底是谁在说”
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Voice/VoiceRuntimeTypes.swift`
  - `x-terminal/Sources/UI/SupervisorSettingsView.swift`
  - `x-terminal/Sources/UI/Supervisor/SupervisorConversationPanel.swift`
  - `x-terminal/Sources/Supervisor/SupervisorRuntimeActivityPresentation.swift`
- 具体任务：
  - 展示：
    - `engine`
    - `speaker`
    - `native / fallback`
    - `fallback reason`
  - 如果本次 Automatic 选中 `Kokoro Warm Chinese`，且最终回退系统语音：
    - UI 要同时显示：
      - 想选谁
      - 实际用了谁
      - 为什么没用上
- 本轮已落地：
  - Hub TTS 返回的以下字段已接入 XT 播放活动状态：
    - `engineName`
    - `speakerId`
    - `nativeTTSUsed`
    - `fallbackReasonCode`
  - Supervisor 设置页的 `Last Playback` 卡片现在会显示：
    - `Engine`
    - `Speaker`
    - `Execution`
    - `Fallback Reason`
  - Supervisor 聊天面板顶部 `voice rail` 现在会显示紧凑真相 token：
    - 例如 `tts=kokoro spk=bf_emma mode=native_tts`
    - 例如 `tts=system mode=system_speech_fallback why=hub_voice_pack_runtime_failed`
  - `supervisor.voice.playback` tool 的结构化结果与自然语言摘要，已经带出上述真相字段
  - `System Log` 现在会记录每次真实播放的后端真相，包含：
    - `state`
    - `output`
    - `tts`
    - `speaker`
    - `mode`
    - `fallback_from`
    - `why`
  - 当前 `summaryLine` 已能区分：
    - native synthesis
    - compatibility fallback
  - 已验证：
    - `SupervisorManagerVoicePlaybackRuntimeTests`
    - `SupervisorSpeechSynthesizerTests`
    - `SupervisorRuntimeActivityPresentationTests`
    - `ToolExecutorSkillsAndSummarizeTests`
    - `swift build`
- 剩余：
  - 继续压缩文案，把 `engine / speaker / native/fallback` 显示得更短更直观
  - 评估是否要把播放真相进一步带到更多 project 侧 runtime 板块，而不是只停留在 Supervisor 侧
- DoD：
  - 用户不需要读日志，也能看懂这次是不是“模型自己发声”

### 10.7 切片 H6：Hub 与 XT 回归测试

- 编号：`XT-W3-39-H6`
- owner: `QA / XT-L2 / Hub-L5`
- 优先级：`P1`
- 目标：把“原生 TTS 可用”和“fallback 真相可见”纳入回归
- 测试落点：
  - `x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py`
  - `x-hub/grpc-server/hub_grpc_server/src/local_tts.test.js`
  - `x-terminal/Tests/SupervisorSpeechSynthesizerTests.swift`
  - `x-terminal/Tests/HubIPCClientVoiceTTSTests.swift`
- 具体任务：
  - 增加：
    - Kokoro native success case
    - native dependency missing -> fallback visible case
    - fallback disabled -> fail-closed case
    - XT automatic pick -> native engine display case
- DoD：
  - 不能出现“native 失效却静默变成 system voice 且 UI 不知道”的回归

## 11) 下一阶段主线：XT-W3-39-I 音色映射产品化

### 11.1 目标

把当前抽象的 `Voice Color` 从“提示词级偏好”升级成“引擎内可复现的人声 preset”。

### 11.2 代码级任务

- 编号：`XT-W3-39-I1`
  - 建立 `engine -> speaker capability manifest`
  - 文件：
    - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelModels.swift`
    - 允许新增 `voice speaker manifest` 结构
- 编号：`XT-W3-39-I2`
  - Hub 市场导入时写入更细的 speaker/style metadata
  - 文件：
    - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/LMStudioMarketBridge.swift`
- 编号：`XT-W3-39-I3`
  - XT picker 增加更可读的 secondary labels
  - 文件：
    - `x-terminal/Sources/Voice/HubVoicePackCatalog.swift`
    - `x-terminal/Sources/UI/SupervisorSettingsView.swift`

### 11.3 DoD

- 用户不只看到 `Warm / Clear`
- 还会看到更可理解的 pack 说明，例如：
  - `Chinese Warm · Kokoro`
  - `English Calm · MeloTTS`

## 12) 下一阶段主线：XT-W3-39-J/K/L 体验完成度收口

### XT-W3-39-J 播放结果 explainability

- 目标：把 `reasonCode` 翻译成用户能一眼看懂的话
- 代码落点：
  - `x-terminal/Sources/UI/SupervisorSettingsView.swift`
  - `x-terminal/Sources/Voice/VoiceRuntimeTypes.swift`
- DoD：
  - 可直接看到：
    - “因为你选的是 Chinese + Warm，所以 Automatic 推荐了 Kokoro Warm Chinese”
    - “该 pack 未 ready，已回退到 System Speech”

### XT-W3-39-K 流式 TTS

- 目标：降低首包延迟，支持边生成边播
- 代码落点：
  - `x-hub/grpc-server/hub_grpc_server/src/local_tts.js`
  - `x-hub/python-runtime/python_service/providers/transformers_provider.py`
  - `x-terminal/Sources/Voice/HubVoicePackAudioPlayback.swift`
- DoD：
  - 长句不必等整段生成完再播
  - 打断响应更快

### XT-W3-39-L 唤醒 + 常驻语音会话收口

- 目标：播报与输入会话合流
- 代码落点：
  - `x-terminal/Sources/Voice/VoiceSessionCoordinator.swift`
  - `x-terminal/Sources/Voice/VoiceReadinessAggregator.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- DoD：
  - 唤醒后进入短时常驻会话
  - 用户插话时能中断播报并继续对话

## 13) 当前默认执行顺序（更新）

1. `XT-W3-39-H1`
2. `XT-W3-39-H2`
3. `XT-W3-39-H3`
4. `XT-W3-39-H4`
5. `XT-W3-39-H5`
6. `XT-W3-39-H6`
7. `XT-W3-39-I1/I2/I3`
8. `XT-W3-39-J`
9. `XT-W3-39-K`
10. `XT-W3-39-L`

## 14) 对外表述边界（当前版本）

当前可以对外说：

- Supervisor voice playback routing is working end-to-end.
- Hub voice packs can now be discovered, selected, recommended, and truthfully surfaced in XT.
- Automatic pack selection already considers language and timbre.

当前不要对外说：

- downloaded TTS voice models are fully running natively in production
- all Hub market voice packs already synthesize with their own engines
- streaming low-latency voice playback is finished
