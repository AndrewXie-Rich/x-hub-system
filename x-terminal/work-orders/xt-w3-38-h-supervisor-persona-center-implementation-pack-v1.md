# XT-W3-38-H Supervisor Persona Center Implementation Pack v1

- version: v1.0
- updatedAt: 2026-03-20
- owner: XT-L2（Primary）/ Supervisor / Product / Design / QA
- status: active
- scope: `XT-W3-38-H`（把当前分散的 `Prompt Personality`、`Personal Assistant Profile`、`Voice Persona` 收口成一个统一 `Supervisor Persona Center`，支持 5 个 persona slots、用户自定义命名、名字唤起路由，以及更成体系的美化 UI）
- parent:
  - `x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-assistant-runtime-alignment-implementation-pack-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`

## 0) 为什么单开这份包

当前 X-Terminal 里和“Supervisor 人格/个性”相关的设置已经分散成 3 个入口：

- `Prompt Personality`
- `Personal Assistant Profile`
- `Voice Persona`

这在实现上还能工作，但在用户心智上已经开始混乱：

- 用户想调的是“人格”，系统暴露的是三块不同表单
- 用户想切换的是“谁来回答”，系统只有单套当前配置
- 用户想要 5 个不同人格 slot，但系统目前只有一个 Supervisor 身份

因此这一包的目标不是再加一个开关，而是把人格系统正式收口为：

- 一个统一 Persona Center
- 5 个 persona slots
- 每个 slot 可命名、可配置、可被用户点名调用
- 所有人格共享同一个 Hub-first 记忆/治理真相源，只改变表达风格、陪跑方式和默认陪伴策略

## 1) 一句话冻结决策

冻结：

- `Supervisor Persona` 是 `identity + style + personal assistant policy + optional voice overlay` 的统一配置对象。
- `Persona` 不创建第二套记忆真相源，不创建第二套 grant/policy，不创建第二个 Supervisor runtime。
- 用户显式喊 persona 名称时，运行时只切换 persona 配置，不切换 Hub 宪章、治理边界和记忆真相源。

## 2) 固定决策

### 2.1 只做 5 个 slot，不做无限 persona 列表

原因：

- 5 个 slot 已足够覆盖“默认总控 / 总参谋 / 助手 / 教练 / 轻松陪聊”一类常见人格
- UI 和调用路由更稳定
- 后续如果要扩，再做 `advanced` 档位，而不是 v1 就放开无限列表

### 2.2 persona slot 必须是统一对象

每个 persona slot 至少包含：

- `persona_id`
- `display_name`
- `aliases`
- `enabled`
- `identity_name`
- `role_summary`
- `tone_directives`
- `extra_system_prompt`
- `relationship_mode`
- `briefing_style`
- `risk_tolerance`
- `interruption_tolerance`
- `reminder_aggressiveness`
- `preferred_morning_brief_time`
- `preferred_evening_wrap_up_time`
- `weekly_review_day`
- `voice_persona_override`
- `voice_pack_override_id`
- `accent_color_token`
- `icon_token`

### 2.3 persona 影响范围必须收口

persona 允许影响：

- 回答口吻
- 陪跑风格
- 简报密度
- 提醒强度
- 个人事务 review 倾向
- 语音 persona 覆盖
- Hub Voice Pack overlay

persona 不允许影响：

- X-Constitution
- grant / audit / kill-switch
- project A-Tier / S-Tier
- Hub memory truth
- 设备权限边界

### 2.4 点名切换只改变本轮或当前会话 persona

冻结默认行为：

- 用户消息显式点名时，优先切到该 persona 回答当前轮
- 如果用户表达了“以后都用这个”一类明确偏好，再升级为默认 persona
- 没有显式点名时，使用默认 persona

### 2.5 Persona Center UI 不能只做“表单堆叠”

v1 UI 要求：

- 顶部要有清晰的 5 张 persona cards
- 当前默认 persona 要明显高亮
- 每张卡要能快速看出：
  - 名字
  - 核心风格
  - 提醒强度
  - 简报密度
  - 语音 persona
- 编辑面板要分组，不要把 15+ 字段扔成一长列
- 美化方向必须明确，不做纯系统表单感

## 3) 机读契约冻结

### 3.1 `xt.supervisor_persona_slot.v1`

```json
{
  "schema_version": "xt.supervisor_persona_slot.v1",
  "persona_id": "persona_slot_1",
  "display_name": "Atlas",
  "aliases": ["atlas", "阿特拉斯"],
  "enabled": true,
  "identity_name": "Atlas Supervisor",
  "role_summary": "Strategic chief-of-staff style partner.",
  "tone_directives": [
    "Lead with the answer.",
    "Point out tradeoffs directly."
  ],
  "extra_system_prompt": "",
  "relationship_mode": "chief_of_staff",
  "briefing_style": "proactive",
  "risk_tolerance": "balanced",
  "interruption_tolerance": "high",
  "reminder_aggressiveness": "assertive",
  "preferred_morning_brief_time": "08:30",
  "preferred_evening_wrap_up_time": "18:30",
  "weekly_review_day": "Friday",
  "voice_persona_override": "conversational",
  "voice_pack_override_id": "",
  "icon_token": "sparkles.rectangle.stack.fill",
  "accent_color_token": "persona_amber",
  "updated_at_ms": 0
}
```

### 3.2 `xt.supervisor_persona_registry.v1`

```json
{
  "schema_version": "xt.supervisor_persona_registry.v1",
  "default_persona_id": "persona_slot_1",
  "active_persona_id": "persona_slot_1",
  "slots": [],
  "updated_at_ms": 0
}
```

### 3.3 `xt.supervisor_persona_invocation.v1`

```json
{
  "schema_version": "xt.supervisor_persona_invocation.v1",
  "matched_persona_id": "persona_slot_2",
  "matched_alias": "atlas",
  "match_source": "explicit_name|at_mention|wake_phrase|default_fallback",
  "apply_scope": "turn|session|persisted_default",
  "confidence": 0.99,
  "updated_at_ms": 0
}
```

## 4) 详细执行拆分

### XT-W3-38-H1 Persona Registry + Settings Storage

- 目标：把单套 `supervisorPrompt + personalProfile + personalPolicy` 收口成 `persona registry`
- 代码落点：
  - `x-terminal/Sources/Supervisor/`
  - `x-terminal/Sources/LLM/XTerminalSettings.swift`
- 具体任务：
  - 新增 `SupervisorPersonaSlot`
  - 新增 `SupervisorPersonaRegistry`
  - 提供 5 个默认 slot seed
  - 增加 `default_persona_id / active_persona_id`
  - 兼容旧设置自动迁移：
    - 原 `supervisorPrompt`
    - 原 `supervisorPersonalProfile`
    - 原 `supervisorPersonalPolicy`
    - 原 `voice.persona`
    - 迁入 slot 1
- 当前实现：
  - 已新增 `SupervisorPersonaSlot / SupervisorPersonaRegistry`
  - 已提供 5 个默认 slot seed
  - 已把 `XTerminalSettings` 升级为 `registry + legacy shadow fields` 双轨兼容
  - 已支持旧设置自动迁移到 primary slot
  - 已支持 registry 反向回填 legacy `supervisorPrompt / personalProfile / personalPolicy / voice.persona`
  - 已补 `XTerminalSettingsSupervisorAssistantTests`
  - 已验证 `swift test --filter XTerminalSettingsSupervisorAssistantTests`
  - 已验证 `swift test --filter SupervisorSystemPromptBuilderTests`
- DoD：
  - 老设置升级后不丢现有 persona 配置
  - 新设置文件可稳定 encode/decode
  - 缺字段时 fail-soft 回落到默认 5 slots

### XT-W3-38-H2 Persona Resolution + Invocation Router

- 目标：支持“用户喊谁的名字就由谁来回答”
- 代码落点：
  - `x-terminal/Sources/Supervisor/`
  - `x-terminal/Sources/Chat/`
- 具体任务：
  - 新增 `SupervisorPersonaResolver`
  - 支持 `display_name + aliases` 匹配
  - 支持中英文、大小写、空白标准化
  - 定义 `apply_scope`：
    - `turn`
    - `session`
    - `persisted_default`
  - 给 `SupervisorManager` 增加当前 persona 解析入口
  - 当前 persona 要进入 system prompt 和本地直答
- 当前实现：
  - 已新增 `SupervisorPersonaResolver`
  - 已支持 `display_name + aliases` 匹配
  - 已支持中英文、大小写、空白归一化
  - 已支持 `turn / session / persisted_default` 三种 scope 解析
  - 已把 persona 路由接到 `SupervisorManager` 的用户消息入口
  - 已把当前 persona 接到本地直答模板与远端 system prompt 组装
  - 已补 `SupervisorPersonaResolverTests`
  - 已补 `SupervisorPersonaRoutingTests`
  - 已验证 `swift test --filter SupervisorPersona`
  - 已验证 `swift test --filter SupervisorSystemPromptBuilderTests`
- DoD：
  - 明确点名 persona 时，本轮使用对应 persona
  - 未点名时稳定走默认 persona
  - 匹配冲突时 fail-closed 到默认 persona，并留下调试理由

### XT-W3-38-H3 Unified Persona Prompt Assembly

- 目标：把 prompt/personality/personal-assistant/voice overlay 的散装读取收口成单一路径
- 代码落点：
  - `SupervisorManager.swift`
  - `SupervisorSystemPromptParams.swift`
  - `SupervisorSystemPromptBuilder.swift`
- 具体任务：
  - 不再分别读 `supervisorPrompt`、`supervisorPersonalProfile`、`supervisorPersonalPolicy`
  - 统一从 `active persona slot` 编译：
    - identity
    - style
    - personal policy
    - optional voice overlay
  - 本地直答模板也要使用当前 persona 的 `identity_name`
- 当前实现：
  - `SupervisorManager` 已改为从当前 resolved persona slot 读取 `identity / prompt / personal profile / policy`
  - 远端 system prompt 已支持按 turn/session/default persona 注入
  - 本地直答模板已支持按当前 persona 输出 identity
  - 语音回复已支持按当前 persona 应用 `voice_persona_override`
  - 已补 runtime 回归：legacy shadow fields 变旧时，runtime 仍以 persona slot 为准
  - 已验证 `swift test --filter SupervisorPersonaRoutingTests`
  - 已验证 `swift test --filter SupervisorSystemPromptBuilderTests`
- DoD：
  - 远端 prompt 和本地直答都能体现当前 persona
  - persona 切换不会影响 Hub 宪章和治理链

### XT-W3-38-H4 Persona Center UI

- 目标：做出一个真正可用的 `Supervisor Persona Center`
- 代码落点：
  - `x-terminal/Sources/UI/SupervisorSettingsView.swift`
  - 如有必要新增 `x-terminal/Sources/UI/Supervisor/`
- 具体任务：
  - 顶部做 5 张 persona cards
  - 卡片字段：
    - 名字
    - 一句话风格
    - tone tags
    - reminder intensity
    - briefing density
    - voice persona
  - 右侧或下方做编辑面板，分成 4 组：
    - Identity
    - Style
    - Personal Assistant Policy
    - Voice Overlay
  - 增加：
    - 设为默认
    - 临时试用
    - 重置 slot
    - 复制 slot 配置
- UI 美化要求：
  - 明确视觉方向，不要停留在系统原生表单堆叠
  - 颜色由 `accent_color_token` 驱动
  - persona 卡要有明显层级、留白和状态高亮
  - 桌面和窄宽度都要可读
  - 不允许出现“一屏全是文本框”的管理后台感
- 当前实现：
  - 已新增 `SupervisorPersonaCenterView`
  - 已在 `SupervisorSettingsView` 顶部接入 Persona Center，替代旧的 `Prompt Personality / Personal Assistant Profile` 分散入口
  - 已实现 5 张 persona cards、default / active 状态标签、accent tint、role / briefing / voice chips
  - 已实现分组编辑面板：
    - `Identity`
    - `Execution Style`
    - `Personal Context`
    - `Communication Rhythm`
  - 已支持按 slot 配置：
    - `Voice Overlay`
    - `Hub Voice Pack`
    - overlay 说明文案
  - 已实现 `设为默认 / 设为当前 / 复制默认槽 / 重置当前槽`
  - 已实现 slot `enabled` 开关、draft unsaved 状态提示、save / restore 控制
  - 已把设置页 header 和 voice runtime 文案改为以 persona 为中心，而不是继续暴露旧单套 prompt/profile 心智
  - 已验证 `swift build`
  - 已验证 `swift test --filter XTerminalSettingsSupervisorAssistantTests`
  - 已验证 `swift test --filter SupervisorPersonaRoutingTests`
- DoD：
  - 用户一眼能看懂 5 个 persona 的区别
  - 默认 persona 状态明确
  - 编辑和切换路径不超过 2 次点击

### XT-W3-38-H5 Voice / Wake Phrase Alignment

- 目标：把语音 persona 和点名 persona 对齐，但不把 voice runtime 绑死
- 代码落点：
  - `x-terminal/Sources/Voice/`
  - `SupervisorSettingsView.swift`
- 具体任务：
  - 给 persona slot 增加可选 `voice_persona_override`
  - 定义优先级：
    - active persona override
    - global voice default
  - 预留 wake phrase / voice route 后续接 persona router 的挂点
- 当前实现：
  - runtime 已支持 `active persona voice_persona_override > voice.persona shadow` 的覆盖路径
  - runtime 已支持 `active persona voicePackOverrideID > global preferredHubVoicePackID` 的覆盖路径
  - `Supervisor Persona Center` 已支持按 slot 编辑 `Voice Overlay`
  - `Supervisor Persona Center` 已支持按 slot 编辑 `Hub Voice Pack`
  - `SupervisorSettingsView` 的 `Voice Runtime` 已改为显示当前 `active persona / default persona / active overlay`
  - `Voice Persona` picker 已改成 `Active Persona Voice` 语义，避免继续误导为独立旧设置
  - 已新增 `wake phrase -> persona router` 挂点：
    - 当命中的 wake phrase 直接等于 persona `display_name / alias` 时，按 `wake_phrase + session` scope 切到对应 persona
    - `x hub / supervisor` 这类 generic wake 词保持只唤醒不切 persona，避免默认唤醒词把会话错误切回 slot 1
  - 已在设置页 wake trigger 文案里显式说明这条行为
  - 已在 `Voice Runtime` 里增加 `Persona Wake Suggestions` quick-add 区，按当前 persona registry 推荐可直接加入 wake 草稿的 persona 名字/别名
  - 已验证 `swift test --filter SupervisorPersonaResolverTests`
  - 已验证 `swift test --filter wakePhraseRoutesSessionPersonaWhenAliasMatchesSlot`
  - 已验证 `swift test --filter genericWakePhraseDoesNotOverrideCurrentPersona`
  - 已验证 `swift test --filter SupervisorWakePhraseSuggestionTests`
  - 已验证 `swift test --filter SupervisorPersonaRoutingTests`
- DoD：
  - persona 可以覆盖 voice persona
  - 不配置 override 时不影响全局 voice 设置

### XT-W3-38-H6 Regression + UX Evidence

- 目标：把 persona center 做成稳定主链，不靠人工记忆回归
- 测试落点：
  - `x-terminal/Tests/`
- 具体任务：
  - `SupervisorPersonaRegistryTests`
  - `SupervisorPersonaResolverTests`
  - `SupervisorPersonaPromptAssemblyTests`
  - `SupervisorSettingsPersonaCenterUITests`
  - 旧设置迁移回归
  - 名字冲突 / alias 冲突 / disabled persona 回归
- 证据要求：
  - 至少 1 组老设置迁移 fixture
  - 至少 1 组 persona name invocation fixture
  - 至少 1 组 UI snapshot / presentation evidence
- 当前实现：
  - 已补 `SupervisorPersonaRegistryTests`
    - 归一化会修复无效 `default / active persona id`
    - slots 乱序输入时仍保持固定 seed 顺序
  - 已补 `SupervisorPersonaResolverTests` 的 disabled persona 回归
  - 已有 `XTerminalSettingsSupervisorAssistantTests` 覆盖老设置迁移与 legacy shadow 同步
  - 已有 `SupervisorPersonaRoutingTests` 覆盖 turn / session / persisted default 路由
  - 已新增 `SupervisorPersonaCenterPresentation.swift`
    - 统一计算 persona card 状态、selected/default/active/disabled badge、draft synced/unsaved、runtime voice summary、wake suggestion 列表
  - `SupervisorPersonaCenterView.swift` 已切到 `SupervisorPersonaCenterPresentation`
  - `SupervisorSettingsView.swift` 的 `Voice Runtime / Persona Wake Suggestions` 已切到 presentation summary
  - 已补 `SupervisorPersonaCenterPresentationTests`
    - selected fallback 到 active persona
    - default / active / disabled card state
    - unsaved draft gating
    - runtime voice summary
    - wake suggestion presentation evidence
  - 已验证 `swift test --filter SupervisorPersonaCenterPresentationTests`
  - 已验证 `swift test --filter SupervisorWakePhraseSuggestionTests`
  - 已验证 `swift test --filter SupervisorPersonaResolverTests`
  - 已验证 `swift build`

## 5) UI 视觉要求冻结

### 5.1 设计方向

- 关键词：`control room + character board + editorial clarity`
- 避免：
  - 通用系统表单感
  - 紫白渐变 AI 套皮
  - 过多边框和弱层级

### 5.2 具体要求

- persona cards 至少支持：
  - 图标
  - accent tint
  - 默认标签
  - 当前激活标签
  - 3 个短特征 chips
- 编辑区使用清晰 section cards，不用长表单
- tone/style 类字段尽量转为 chips / pickers / segmented controls
- 多行 prompt 字段保留文本编辑器，但必须和结构化字段分开
- 需要保留一套简洁、偏专业的视觉语言，不做花哨插画

### 5.3 验收标准

- 第一次进入设置页时，用户能在 5 秒内理解：
  - 有 5 个 persona
  - 哪个是默认
  - 如何切换
  - 每个 persona 大概什么风格
- 切换 persona 时，视觉反馈必须即时
- 窄窗口下不能崩成难读表单

## 6) 风险与边界

- 不允许 persona 成为第二套记忆真相源
- 不允许 persona 影响 `A-Tier / S-Tier / grants / kill-switch`
- 不允许 voice overlay 反向污染 text persona registry
- 不允许名字路由误匹配后静默切错 persona；要可解释、可调试

## 7) 推荐推进顺序

1. `XT-W3-38-H1`
2. `XT-W3-38-H2`
3. `XT-W3-38-H3`
4. `XT-W3-38-H4`
5. `XT-W3-38-H5`
6. `XT-W3-38-H6`

一句话结论：

- 这不是“再加一点语气设置”
- 这是把 Supervisor 的人格系统正式产品化
- v1 要求做到：`5 persona slots + named invocation + unified persona center + visibly better UI`
