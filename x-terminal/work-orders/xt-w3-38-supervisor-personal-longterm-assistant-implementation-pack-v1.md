# XT-W3-38 Supervisor Personal Longterm Assistant Implementation Pack v1

- version: v1.0
- updatedAt: 2026-03-22
- owner: XT-L2（Primary）/ Supervisor / Hub-L5 / QA / Product
- status: active
- scope: `XT-W3-38`（把 Supervisor 从“项目总控”扩成“长期个人助手”，但明确优先复用 OpenClaw 已有能力，不重复造轮子）
- parent:
  - `x-terminal/work-orders/xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-33-supervisor-decision-kernel-routing-and-memory-governance-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-35-supervisor-memory-retrieval-progressive-disclosure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-assistant-runtime-alignment-implementation-pack-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-compatibility-guardrails-v1.md`
  - `x-terminal/work-orders/xt-w3-38-h-supervisor-persona-center-implementation-pack-v1.md`

## Status Notes

- 2026-03-16:
  - `XT-W3-38-A` 已落第一段实现骨架：
    - 新增 `SupervisorPersonalProfile` / `SupervisorPersonalPolicy` 结构，冻结个人助手画像与默认陪跑策略的首版本地配置形状。
    - `XTerminalSettings` 升到 schema v5，新增 `supervisorPersonalProfile` / `supervisorPersonalPolicy` 持久化字段，并保持旧设置缺字段时默认回落。
    - `SupervisorSettingsView` 新增 `Personal Assistant Profile` 配置区，可编辑 preferred name、goals、work style、communication preferences、daily rhythm、review preferences，以及 relationship/briefing/risk/interruption/reminder 等策略档位。
    - `SupervisorSystemPromptBuilder` 新增 `Personal Assistant Context` 段，Supervisor 远端系统提示词开始携带用户长期画像与个人助手策略。
    - 新增 `SupervisorSystemPromptBuilderTests` 与 `XTerminalSettingsSupervisorAssistantTests` 回归，锁定 prompt 注入和旧配置兼容。
  - `XT-W3-38-C` 已落第一段纯调度核：
    - 新增 `SupervisorPersonalReviewScheduler` 与 `SupervisorPersonalReviewCompletionState`，把 `morning_brief / evening_wrap_up / weekly_review` 的触发窗口、完成锚点和 due 判定先冻结为可测试逻辑。
    - 新增 `SupervisorPersonalReviewSchedulerTests`，锁定 morning/evening/weekly review 的时间判定和已完成去重行为。
    - 现已补上 `SupervisorPersonalReviewNoteStore` 首个可用切片：
      - 新增 `SupervisorPersonalReviewNoteStore.swift`，冻结 `xt.supervisor_personal_review_note.v1` 的本地 snapshot/history/completion state/store 形状。
      - 基于 active persona policy、structured personal memory、follow-up ledger、reminder queue 派生当前 due review notes 和 recommended actions。
      - `SupervisorSettingsView` 已新增 `Personal Review Loop` 面板，支持查看 due review / recent notes，并可直接标记 `morning_brief / evening_wrap_up / weekly_review` 为完成。
      - `SupervisorSystemPromptBuilder` 已接入 `## Personal Review Context`，让 Supervisor 在自然对话里知道当前 review 节奏、哪些 review 已到点、最近 review note 在说什么。
      - 新增 `SupervisorPersonalReviewNoteStoreTests`、扩展 `SupervisorSystemPromptBuilderTests`，并回归 `SupervisorPersonalReviewSchedulerTests`。
  - `XT-W3-38-B` 已落第一段结构化 personal memory 主链：
    - 新增 `SupervisorPersonalMemoryStore`，把个人长期记忆冻结成 app-level 的结构化 snapshot/store，而不是继续散落在自由文本 prompt 里。
    - `SupervisorPersonalMemoryRecord` 首版覆盖 `personal_fact / habit / preference / relationship / commitment / recurring_obligation` 六类条目，以及 `status / due_at / person_name / tags / audit_ref`。
    - 新增 `SupervisorPersonalMemorySummaryBuilder`，统一产出 UI 状态行、category counts、overdue commitments、key people 和 prompt-ready summary。
    - `SupervisorSettingsView` 已新增 `Personal Memory` 面板，支持直接新增、编辑、删除、保存 structured memory items。
    - `SupervisorSystemPromptBuilder` 已开始携带 `## Personal Memory Context`，让 Supervisor 在自然聊天、daily planning、follow-up 提醒时拿到这层结构化背景。
    - 新增 `SupervisorPersonalMemoryStoreTests` 与 `SupervisorSystemPromptBuilderTests` 回归，锁定 store 持久化、overdue/people 汇总，以及 prompt 注入。
  - `XT-W3-38-D` 已落第一段 follow-up ledger 闭环：
    - 新增 `SupervisorFollowUpLedger`，从 structured personal memory 派生 `who is waiting / what is overdue / what is due soon / what is on watch`。
    - 新增 `SupervisorReminderQueue`，把 follow-up ledger 进一步压成排序后的提醒队列，后续 `review loop / cockpit / notifications` 可直接复用。
    - `SupervisorSettingsView` 已新增 `Follow-Up Queue` 面板，直接展示 overdue、due soon、people waiting 和推荐下一步。
    - `SupervisorSystemPromptBuilder` 已开始携带 `## Follow-Up Queue Context`，让 Supervisor 在“今天先回谁”“哪些承诺在滑”“谁在等我”这类对话里拿到结构化 follow-up 视角。
    - 新增 `SupervisorFollowUpLedgerTests` 与 `SupervisorSystemPromptBuilderTests` 回归，锁定 urgency classifier、contact-linked commitments、queue 排序与 prompt 注入。
  - `XT-W3-38-G` 已落 cockpit 第一段摘要接入：
    - 新增 `SupervisorPersonalAssistantCockpitPresentation`，把 active persona、due reviews、open follow-ups、people waiting 和 today-style quick prompts 压成 cockpit-ready presentation。
    - 新增 `SupervisorPersonalAssistantSummaryBoard`，把 personal assistant 摘要直接挂进 `SupervisorView`，不再只藏在 settings。
    - cockpit quick actions 已可直接把 `morning brief / who is waiting / personal admin sweep` prompt 注入到 Supervisor 对话输入框。
    - 新增 `SupervisorPersonalAssistantCockpitPresentationTests`，锁定 due review / people waiting / quick actions 的摘要结构。
  - `XT-W3-38-H` 已冻结为单独 persona center 执行包：
    - 目标是把当前分散的 `Prompt Personality / Personal Assistant Profile / Voice Persona` 收口成统一 `Supervisor Persona Center`
    - v1 冻结支持 `5 persona slots + 用户自定义命名 + aliases 点名路由 + 统一 Persona UI + 美化后的 persona cards/edit panel`
    - 详细拆分见 `x-terminal/work-orders/xt-w3-38-h-supervisor-persona-center-implementation-pack-v1.md`
- 2026-03-17:
  - `XT-W3-38-I` 冻结为 `Supervisor Context Engine / Conversation Continuity v1`：
    - 目标是把 Supervisor 从“有 personal memory 片段”升级为“普通聊天也稳定走 memory-aware continuity”的长期助手。
    - 第一阶段已落地收窄本地 preflight 直答边界：只保留 `/hub`、`/route`、模型路由/最近实际模型这类确定性运行态查询；身份、能力、普通闲聊、项目状态、execution intake 默认改走完整 `MEMORY_V1 + Personal Memory/Follow-Up/Review Context` 远端路径。
    - 对 `build/app/game` 这类 execution intake，现已先静默写入 pending intake，再交给远端回答，保住后续“按默认方案建项目”的连续性。
    - 第二阶段已落第一段 continuity floor：Supervisor chat working set 现已改成稳定 `dialogue message floor`，默认 `16` 条，plan review `24` 条，deep dive `32` 条；system messages 不单独计数，但若落在窗口中会一起带入。
    - 已补 `SupervisorMemoryAwareConversationRoutingTests`，并回归 `SupervisorFailureFormattingTests`、`SupervisorPersonalMemoryAutoCaptureTests`。
    - 已补 `SupervisorMemoryWorkingSetWindowTests`，锁定新的 dialogue-window 口径，不再按 `8 user turns` 近似。
    - 下一阶段再补完整 `bootstrap -> ingest -> assemble -> compact -> afterTurn -> handoff` 生命周期和普通对话 explainability。
  - `XT-W3-38-I6` 已冻结独立执行包：
    - 目标是把新冻结的 `Supervisor Memory Routing And Assembly Protocol v1` 接到 runtime，而不是只停留在协议层
    - 详细执行包：
      - `x-terminal/work-orders/xt-w3-38-i6-supervisor-memory-routing-and-assembly-implementation-pack-v1.md`
    - 首波交付物固定为：
      - `SupervisorTurnRouter`
      - `SupervisorFocusPointerState`
      - `SupervisorTurnContextAssembler`
      - `SupervisorAfterTurnWritebackClassifier`
      - `SupervisorCrossLinkStore`
      - route / assembly / writeback explainability surface
    - 当前进度：
      - `I6-A / SupervisorTurnRouter` 已落第一段实现并接入 `Turn Routing Hint` prompt 注入
      - `I6-B / SupervisorFocusPointerState` 已落第一段实现并接入 runtime persistence + after-turn continuity 回写
      - `I6-C / SupervisorTurnContextAssembler` 已落 first slice，并接入 prompt explainability 与 personal capsule gating
      - `I6-D / SupervisorCrossLinkStore` 已落 first slice，并接入 `cross_link_scope` durable writeback + `[CROSS_LINK_REFS]` memory 回灌
      - `I6-E / After-Turn Writeback Classifier` 已落 first slice，并接入 after-turn lifecycle 结构化分类
      - `I6-F / Prompt-UI Explainability Alignment` 已落 first slice，并接入 Supervisor Memory Board 的 latest turn explainability surface
      - 已补 manager 级回归，锁定 after-turn helper 会同步发布 latest routing / assembly explainability state
      - `I6-G / Regression + Governance Clamp` 已补第一段回归：personal-first 路由不被 portfolio 词误导、ambiguous turn 不 fabricated focus、本地直答与 fallback 仍走统一 after-turn explainability、project coder prompt 继续保持 scope 隔离
  - `XT-W3-38-I7` 已冻结独立执行包：
    - 目标是把“Supervisor 至少看见一段 recent raw dialogue、personal 与 project 记忆自然合流、project AI 拿到可调 context depth”从讨论变成 runtime contract
    - 详细执行包：
      - `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`
    - 兼容护栏：
      - `docs/memory-new/xhub-supervisor-memory-compatibility-guardrails-v1.md`
    - 首波切片固定为：
      - `I7-A / Settings Model + Policy Contract Wiring`
      - `I7-B / Supervisor Hard Continuity Floor Runtime`
      - `I7-C / Low-Signal Filter + Rolling Dialogue Digest`
      - `I7-D / Hub-First Supervisor Assistant Thread`
      - `I7-E / Dual-Plane Assembly Runtime Alignment`
      - `I7-F / Project AI Context Depth Runtime`
      - `I7-G / UI Surface + Doctor + Evidence`
    - 当前状态：
      - 协议已冻结，等待 runtime 顺序落地
      - 默认建议先做 `I7-A -> I7-B`，不要先做纯 UI
  - `XT-W3-38-I7-D2` 已冻结为 `Hub-First Supervisor Durable Memory Handoff` 子切片：
    - 目标不是新开 memory 主线，而是在不打断 `I7-D` / `I6-E` 当前推进节奏的前提下，把 XT after-turn `user_scope / project_scope / cross_link_scope` candidate 平滑镜像到 Hub
    - 当前冻结边界：
      - XT 本地 `personal/cross-link/project` store 继续作为 cache / fallback / edit buffer
      - `I6-E` writeback classification 继续只产 candidate / scope hint，不直写 Hub durable truth
      - Hub 侧先承接 candidate carrier + audit + idempotency，不提前宣称 read-source cutover
    - 并行泳道固定为：
      - Hub 侧 carrier / audit / scope gate
      - XT 侧 shadow write transport / fallback merge / explainability
      - XT local store 降级为 cache-only 的后续收口
      - tests / doctor / release evidence
    - 详细执行切片：
      - `x-terminal/work-orders/xt-w3-38-i7-d2-hub-first-supervisor-durable-memory-handoff-implementation-pack-v1.md`

## 0) 为什么单开这份包

当前 Supervisor 已经很像：

- 项目编排器
- portfolio 控制台
- 受治理 review / guidance / intervention 核心
- 会自然聊天的总控角色

但还不像“懂用户本人、能长期陪跑、能主动帮你管理生活与工作交界事务”的个人助手。

当前系统已经有这些底子：

- `SupervisorIdentityProfile` / `SupervisorPromptPreferences` 可以定义角色与口吻
- Supervisor 已有 portfolio / project capsule / decision track / memory serving / notification / voice
- X-Hub 已有 memory 真相源、治理真相源、通知与 connector 演进方向

但还缺：

- 用户长期画像
- 个人偏好与习惯记忆
- 关系/联系人记忆
- 个人事务与 follow-up 闭环
- daily/weekly review
- 个人级 reminders / calendar / email / inbox 行动闭环

这部分如果完全重写，容易重复造 OpenClaw 已经验证过的通用骨架。

所以本包冻结一个原则：

- 凡是 OpenClaw 已经有成熟骨架的，优先吸收接口形状、配置模型、插件槽、cron/heartbeat 心智、channel/node 能力面
- 凡是 X-Hub 明确不同的信任边界与治理真相源，继续保留 X-Hub 主链，不照搬 OpenClaw runtime

一句话：

- 复用 OpenClaw 的“可插拔能力面”
- 保留 X-Hub 的“Hub-first 治理真相源”

## 1) 固定决策

### 1.1 个人助手不是第二套 OpenClaw runtime

不做：

- 在 X-Terminal 内再造一套独立的 terminal-first personal assistant runtime
- 在 Supervisor 旁边再挂一个无治理的 life-agent
- 把个人长期记忆做成 XT 本地真相源

继续保持：

- Hub 仍是 memory / policy / audit / grants / kill-switch 真相源
- Supervisor 是用户的长期助手入口
- XT 只负责交互面、局部缓存、设备权限宿主与执行面

### 1.1.1 Personal Assistant 仍沿用同一 Memory Control Plane

这份包虽然把 Supervisor 扩成长期个人助手，但它不会创建第二套 memory chooser，也不会把 `personal assistant` 变成独立记忆系统。

固定边界：

- `assistant_personal` 与 `project_code` 仍属于同一个 memory control plane，只是 `mode + scope + policy` 不同。
- 用户选择哪个 AI 执行 memory jobs，仍由 X-Hub 中的 `memory_model_preferences` 决定；Supervisor persona / personal profile / review cadence 不能替代这条控制面。
- 产品层若继续显示 `Memory-Core Skill`，这里也应理解为 governed recipe asset / rule layer，而不是一个直接管理个人记忆的普通 skill 包。
- Supervisor personal memory、project memory、cross-link memory 的 durable truth 继续只能由 `Writer + Gate` 落库；XT 本地 personal stores 只允许作为 cache / edit buffer / fallback。
- 如果问题是“像不像长期助手、最近对话 continuity 是否足够、personal/project 是否自然合流”，优先看本包与 `I6/I7`；如果问题是“memory 用了哪个 AI、为什么 fallback、为什么写坏”，优先看上游 control-plane docs。

### 1.2 优先复用 OpenClaw 的 5 类能力

优先复用对象：

1. Memory plugin / context engine 插槽
   - 参考：
     - `Opensource/openclaw-main/VISION.md`
     - `Opensource/openclaw-main/docs/tools/plugin.md`
     - `Opensource/openclaw-main/src/context-engine/*`
     - `Opensource/openclaw-main/src/memory/*`

2. Cron / heartbeat / session reset 心智
   - 参考：
     - `Opensource/openclaw-main/src/config/types.base.ts`
     - `Opensource/openclaw-main/src/cli/cron-cli/*`
     - `Opensource/openclaw-main/docs/automation/cron-jobs`
     - `Opensource/openclaw-main/docs/automation/cron-vs-heartbeat`

3. Agent identity / per-agent config 形状
   - 参考：
     - `Opensource/openclaw-main/src/config/types.agents.ts`
     - `Opensource/openclaw-main/src/config/types.base.ts`

4. Channel / node / notification / calendar 能力面
   - 参考：
     - `Opensource/openclaw-main/docs/nodes/index.md`
     - `Opensource/openclaw-main/docs/tools/index.md`
     - `Opensource/openclaw-main/extensions/voice-call/*`

5. Plugin / extension 装配方式
   - 参考：
     - `Opensource/openclaw-main/docs/tools/plugin.md`

### 1.3 不照搬的边界

这些不能直接搬：

- OpenClaw terminal-first / gateway-in-process 的默认信任边界
- OpenClaw memory plugin 直接成为长期真相源的路径
- OpenClaw cron 直接写本地 session / transcript 的路径
- OpenClaw node / calendar / notifications 直接作为高权限无额外治理入口的路径

X-Hub 里必须继续走：

- Hub truth
- project / user scope 分层
- capability gate
- grant / audit / kill-switch
- safe-point / review / guidance ack

## 2) 产品目标

### 2.1 用户视角

Supervisor 应能自然做到：

- 记住用户是谁、长期目标是什么、习惯是什么
- 理解“项目事务”和“个人事务”是两条不同但相关的主线
- 主动提醒真正重要的 follow-up，而不是只提醒项目 blocker
- 做 daily / weekly review
- 帮用户处理 calendar / email / reminders / follow-up / meeting prep 等个人运营事务

### 2.2 系统视角

系统要能区分：

- `project governance`
- `user life governance`

也就是说：

- 项目有 `A-tier / S-tier / review policy`
- 用户本人也要有 `personal assistant policy`

### 2.3 体验目标

Supervisor 不应只会说：

- “哪个项目 blocked 了”

还应能自然说：

- “你今天最重要的 3 件事是什么”
- “你答应谁的 follow-up 已经过期”
- “这周你在项目上投入过多，个人行政事务积压了”
- “明早会议前我建议先完成这 2 个准备动作”

## 3) 复用映射

### 3.1 Memory / Context Engine

OpenClaw 可复用：

- `ContextEngine` 插槽思想
- memory backend / search manager / hybrid / temporal decay
- “可替换 context engine，而不是把 compaction 硬编码在 core” 的结构

X-Hub 落地方式：

- 不把 OpenClaw memory runtime 直接移进来
- 吸收成 `Supervisor Personal Context Engine` 的接口设计
- 用于：
  - 用户画像组装
  - 个人事务上下文组装
  - daily/weekly review context 组装
  - relationship / people memory 组装

### 3.2 Cron / Heartbeat / Reset

OpenClaw 可复用：

- `cron` 与 `heartbeat` 分离的心智
- `daily` / `idle` reset
- isolated session vs main session
- scheduled wake / system event

X-Hub 落地方式：

- 不直接用 OpenClaw cron runtime
- 吸收成 `Supervisor Personal Review Scheduler`
- 用于：
  - morning brief
  - evening wrap-up
  - weekly review
  - follow-up reminder
  - delayed callback

### 3.3 Agent Identity / Profiles

OpenClaw 可复用：

- per-agent `identity`
- per-agent heartbeat
- per-agent tools / runtime / skills / workspace

X-Hub 落地方式：

- 扩展现有 `SupervisorIdentityProfile` / `SupervisorPromptPreferences`
- 增加：
  - relationship mode
  - personal briefing style
  - interruption tolerance
  - reminder aggressiveness
  - preferred daily review windows

### 3.4 Nodes / Notifications / Calendar

OpenClaw 可复用：

- `notifications.*`
- `calendar.events`
- `calendar.add`
- 节点能力面和 invoke 心智

X-Hub 落地方式：

- 不直接暴露为 unrestricted device power
- 把它们映射进：
  - `device.notifications.read`
  - `device.notifications.act`
  - `device.calendar.read`
  - `device.calendar.write`
- 并纳入现有 project / user governance clamp

### 3.5 Extensions / Plugins

OpenClaw 可复用：

- plugin slot / manifest / config path / runtime helper 分层

X-Hub 落地方式：

- 给 `personal assistant` 留 extension slot
- 但 extension 只能扩 capability，不持有最终治理权

## 4) 主链拆分

### XT-W3-38-A User Profile v1

- 目标：建立 Supervisor 的长期用户画像
- 结构：
  - `identity`
  - `goals`
  - `work style`
  - `communication preferences`
  - `risk tolerance`
  - `interruption tolerance`
  - `daily rhythm`
  - `review preferences`
- 建议落点：
  - `x-terminal/Sources/Supervisor/SupervisorIdentityProfile.swift`
  - `x-terminal/Sources/Supervisor/SupervisorPromptPreferences.swift`
  - 新增 `SupervisorPersonalProfile.swift`
  - 新增 `SupervisorPersonalPolicy.swift`

### XT-W3-38-B Personal Memory v1

- 目标：把“个人长期记忆”从通用 memory 容器提升为结构化主链
- 结构：
  - personal facts
  - habits
  - preferences
  - people / relationships
  - commitments
  - recurring obligations
- 参考 OpenClaw：
  - `src/context-engine/*`
  - `src/memory/*`
- 建议落点：
  - `x-terminal/Sources/Supervisor/`
  - `docs/memory-new/`
  - Hub memory canonical schema 扩展
- 当前实现：
  - 已新增 `SupervisorPersonalMemoryStore.swift`
    - `SupervisorPersonalMemoryRecord / Snapshot / Summary`
    - app-level `supervisor_personal_memory.json` 持久化
    - normalized upsert/delete/load
  - 已支持 6 类结构化条目：
    - `personal_fact`
    - `habit`
    - `preference`
    - `relationship`
    - `commitment`
    - `recurring_obligation`
  - 已新增 `SupervisorPersonalMemoryCenterView.swift`
    - summary strip
    - item list
    - editor panel
    - due date / tags / person / category / status 编辑
  - `SupervisorSettingsView.swift` 已接入 `Personal Memory` 主面板
  - `SupervisorSystemPromptBuilder` 已接入 `Personal Memory Context`
  - 已新增 `SupervisorPersonalMemoryAutoCapture.swift`
    - 高置信自动捕获自然对话里的 `preferred_name`
    - 首版覆盖：`我叫 X` / `叫我 X` / `我的名字是 X` / `my name is X` / `call me X`
    - 对混合句式支持“前半句捕获，后半句继续执行”
  - `SupervisorManager.swift` 已接入自动 capture 主链
    - 每轮用户消息先尝试自动提取 durable personal fact
    - 纯称呼声明走本地直答：`记住了，我会叫你 X`
    - 本地直答新增 `我叫什么名字` / `what's my name` 这类 recall
  - prompt 装配现已优先读取结构化 personal memory 中的 `preferred_name`
    - 避免旧 persona/profile 里的过期称呼压过新聊天事实
  - 已验证 `swift test --filter SupervisorPersonalMemoryStoreTests`
  - 已验证 `swift test --filter SupervisorPersonalMemoryAutoCaptureTests`
  - 已验证 `swift test --filter SupervisorSystemPromptBuilderTests`
  - 已验证 `swift build`

### XT-W3-38-C Personal Review Loop v1

- 目标：给用户本人建立 daily / weekly review loop
- 类型：
  - morning brief
  - end-of-day wrap-up
  - weekly review
  - overdue follow-up sweep
  - focus drift detection
- 参考 OpenClaw：
  - cron / heartbeat / isolated session
- 建议落点：
  - 新增 `SupervisorPersonalReviewScheduler.swift`
  - 新增 `SupervisorPersonalReviewNoteStore.swift`
- 当前实现：
  - 已新增 `SupervisorPersonalReviewNoteStore.swift`
    - review note schema / snapshot / completion state persistence
    - due review preview builder
    - `markCompleted` 闭环
    - prompt-ready summary builder
  - 已新增 `SupervisorPersonalReviewCenterView.swift`
    - active persona review schedule strip
    - due review cards
    - recent review notes
    - mark-done action
  - `SupervisorSettingsView.swift` 已接入 `Personal Review Loop` 面板
  - `SupervisorSystemPromptBuilder` 已接入 `Personal Review Context`
  - 已验证 `swift test --filter SupervisorPersonalReviewNoteStoreTests`
  - 已验证 `swift test --filter SupervisorPersonalReviewSchedulerTests`
  - 已验证 `swift test --filter SupervisorSystemPromptBuilderTests`
  - 已验证 `swift build`

### XT-W3-38-D Personal Inbox / Follow-up v1

- 目标：把“你答应了什么”“谁在等你”“哪些事该回了”做成闭环
- 包含：
  - reminder queue
  - follow-up ledger
  - due / overdue classifier
  - contact-linked commitments
- 建议落点：
  - 新增 `SupervisorFollowUpLedger.swift`
  - 新增 `SupervisorReminderQueue.swift`
- 当前实现：
  - 已新增 `SupervisorFollowUpLedger.swift`
    - 从 `commitment / recurring_obligation / relationship` 派生 follow-up items
    - 覆盖 `overdue / due_soon / watch / stable` urgency classifier
    - 输出 `recommended_next_action`
  - 已新增 `SupervisorReminderQueue.swift`
    - 把 follow-up ledger 压成提醒队列
    - 固定优先级为 `overdue > due soon > watch > stable`
  - 已新增 `SupervisorFollowUpQueueView.swift`
    - overview badges
    - highlighted follow-ups
    - top reminder cards
  - `SupervisorSettingsView.swift` 已接入 `Follow-Up Queue` 面板
  - `SupervisorSystemPromptBuilder` 已接入 `Follow-Up Queue Context`
  - 已验证 `swift test --filter SupervisorFollowUpLedgerTests`
  - 已验证 `swift test --filter SupervisorSystemPromptBuilderTests`
  - 已验证 `swift build`

### XT-W3-38-E Calendar / Notifications Capability v1

- 目标：在 X-Hub 治理边界内吸收 OpenClaw node calendar / notification 能力面
- 能力：
  - read upcoming events
  - create low-risk reminders
  - inspect notifications
  - surface actionable system reminders
- 参考 OpenClaw：
  - `docs/nodes/index.md`
- 建议落点：
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `x-terminal/Sources/Tools/`
  - Hub capability contract

### XT-W3-38-F Email / Life Admin v1

- 目标：把 email 从“connector”提升为“长期助手的日常工作台”
- 首波：
  - inbox triage
  - urgent mail detection
  - draft reply
  - reply reminder
  - meeting prep extraction
- 注意：
  - 不新造 mail runtime
  - 直接承接你们现有 connectors 路线

### XT-W3-38-G Personal Assistant Cockpit v1

- 目标：在 Supervisor UI 里给用户本人一层“个人运营视图”
- 面板：
  - today
  - follow-ups
  - people waiting on you
  - upcoming meetings
  - personal review
  - life admin queue
- 当前实现：
  - 已新增 `SupervisorPersonalAssistantCockpitPresentation.swift`
    - 聚合 active persona、personal memory、follow-up ledger、review preview
    - 产出 badges / highlights / quick actions
  - 已新增 `SupervisorPersonalAssistantSummaryBoard.swift`
    - 在 `SupervisorView` dashboard 里直接展示 personal assistant summary
    - 当前支持：
      - due reviews
      - open follow-ups
      - people waiting
      - quick prompt injection
  - 已验证 `swift test --filter SupervisorPersonalAssistantCockpitPresentationTests`
  - 已验证 `swift build`

### XT-W3-38-H Persona Center v1

- 目标：把当前分散的 `Prompt Personality`、`Personal Assistant Profile`、`Voice Persona` 合并成统一 `Supervisor Persona Center`
- 能力：
  - 5 个 persona slots
  - 每个 slot 可用户命名
  - `display_name + aliases` 点名路由
  - 单一 persona object 同时承载：
    - prompt identity
    - style/tone
    - personal assistant policy
    - optional voice persona override
  - 统一 persona cards + 编辑面板 UI
- 注意：
  - 不创建第二套记忆真相源
  - 不影响 grant / audit / kill-switch / A-tier / S-tier
  - UI 要求明确美化，不接受“系统表单堆叠”
- 详细执行包：
  - `x-terminal/work-orders/xt-w3-38-h-supervisor-persona-center-implementation-pack-v1.md`

### XT-W3-38-I Supervisor Context Engine / Conversation Continuity v1

- 目标：让 Supervisor 的“长期个人助手连续性”成为一等运行时，而不是只靠 prompt 片段和少量本地快捷回复拼出来
- 背景问题：
  - 当前 `5-layer truth + serving plane` 已存在，但不少普通会话在进入 `MEMORY_V1` 前就被本地直答分流截走
  - 用户体感会变成“明明有记忆结构，但对话像没吃到上下文”
  - `preferred_name / personal memory / follow-up / review` 已入 prompt，但缺少统一的普通对话 continuity contract
- 参考 OpenClaw：
  - `ContextEngine` 生命周期与 personal assistant session continuity
- 固定决策：
  - 不替换 `5-layer memory`
  - 不新增第二套长期真相源
  - 继续保留 Hub-first governance / grants / audit / kill-switch
  - 新增的是 `Supervisor Context Engine` 装配与 conversation continuity contract
- 子任务：
  - `XT-W3-38-I1` Preflight Boundary Narrowing
    - 本地 preflight 只保留确定性运行态查询：
      - slash commands
      - route/model verification
      - last actual model lookup
    - 身份/能力/普通聊天/项目状态/execution intake 默认走远端 memory-aware 路径
    - 远端失败时，仍允许 current local fallback 接管
  - `XT-W3-38-I2` Conversation Continuity Floor
    - 冻结 Supervisor 普通聊天最小 continuity 口径：
      - recent dialogue floor
        - 当前实现口径：默认至少保留最近 `16` 条 dialogue messages
        - strategic / plan review 可扩到 `24 / 32` 条 dialogue messages
        - system messages不单独计数，但如果落在这段窗口里会一起带入
      - personal memory
      - follow-up queue
      - personal review state
      - project/global memory brief（有项目时）
    - 明确“普通闲聊”和“项目纠偏”共享同一 continuity 装配主链，只是 serving profile 深度不同
  - `XT-W3-38-I3` Pending Intake Continuity
    - 对 `build/app/game/tool` 这类 execution intake，允许在远端回答前先写入 pending intake
    - 后续 `按默认方案建项目` / `就按这个推进` 可继续承接，而不是只在本地模板回复链里生效
  - `XT-W3-38-I4` Context Engine Lifecycle
    - 冻结 `bootstrap -> ingest -> assemble -> compact -> afterTurn -> prepareHandoff -> onHandoffReturn`
    - `afterTurn` 负责 durable memory writeback / follow-up update / review progression
  - `XT-W3-38-I5` Explainability + Debug Surface
    - 用户与开发态都能看到：
      - 这轮是否走了 remote memory-aware 路径
      - 哪些 personal/project context 被装进 prompt
      - 为什么这轮还是本地 fallback
- 当前实现：
  - 第一阶段已完成：
    - 收窄 preflight 本地直答边界
    - execution intake 在 remote path 前先做 pending continuity priming
    - 为后续 context-engine 生命周期预留测试钩子
    - 已验证：
      - `swift test --filter SupervisorMemoryAwareConversationRoutingTests`
      - `swift test --filter SupervisorFailureFormattingTests`
      - `swift test --filter SupervisorPersonalMemoryAutoCaptureTests`
  - 第二阶段进行中：
    - 已把普通聊天 working set 收口为稳定 `dialogue message floor`
    - 已验证：
      - `swift test --filter SupervisorMemoryWorkingSetWindowTests`
  - 第三阶段已起步：
    - `XT-W3-38-I4` 已补第一版统一 `afterTurn` 生命周期入口
      - 用户轮 assistant reply 现在统一走同一条收尾链路：
        - append assistant message
        - capture project review note
        - sync derived personal review notes
        - update after-turn runtime activity
        - register talk-loop / voice follow-up continuation
      - 不再把这些步骤散落在各个本地直答 / preflight / remote reply 分支里
      - 现已继续扩到剩余的非标准回复分支：
        - event-loop assistant reply 走同一 after-turn 链，但不额外打开对话窗口
        - pending grant / pending skill approval 语音播报走同一 after-turn 链，但不误记 project review
        - pending grant voice follow-up 与 voice authorization cancel / repeat / mobile-confirm / verification reply 走同一 after-turn 链
      - after-turn 现在支持“统一入口 + 可配置副作用”：
        - 哪些分支要 capture review note
        - 哪些分支只做 personal review / follow-up 衍生同步
        - 哪些分支允许 proactive talk-loop resume
    - `XT-W3-38-I5` 已补第一版 explainability surface
      - `Supervisor Memory` 面板现在会显示：
        - 这轮是 `remote memory-aware`、`local direct reply`、`local direct action` 还是 `local fallback after remote attempt`
        - 这轮 prompt 是否真正用了 memory context
        - 若用了 memory-aware prompt，显示 `resolved profile` 与 `selected sections`
        - 若发生 fallback，显示 `requested model / actual model / failure reason`
      - 现已继续补上 `afterTurn` 派生上下文 explainability：
        - `SupervisorManager` 在每轮 reply 收尾后，会把 `due personal reviews / open follow-ups / overdue counts` 组装成结构化 `afterTurn` summary
        - 该 summary 会对比上一轮状态，显式标出 backlog 是 `initialized / increased / reduced / cleared / stable`
        - runtime activity 仍保留兼容字段 `reviews_due / reviews_overdue / follow_ups / follow_ups_overdue`，同时追加结构化 delta debug line，便于审计和回归
      - `Supervisor Memory` 面板现已新增 `Latest After-Turn` 卡片：
        - 用一条状态行总结这轮收尾后个人上下文是否变多、变少、还是清空
        - 最多显示 4 条细节，覆盖 `new / cleared reviews` 与 `new / cleared follow-ups`
        - 若存在 overdue personal items，会切到更强提醒色，避免“看起来记住了，但用户看不见变化”
    - `SupervisorManager.setAppModel(...)` 现已同步绑定 `HubModelManager`
      - 避免 Supervisor 拿不到当前全局模型配置，导致 continuity / explainability 与真实配置脱节
    - `SupervisorPersonalMemoryAutoCaptureTests` 已改为稳定验证：
      - 先完成 durable personal capture
      - 再验证同轮 prompt context 已吃到新 personal memory
    - 已验证：
      - `swift test --filter SupervisorPersonalMemoryAutoCaptureTests`
      - `swift test --filter SupervisorMemoryBoardPresentationTests`
      - `swift test --filter SupervisorMemoryAwareConversationRoutingTests`
      - `swift test --filter SupervisorFailureFormattingTests`
      - 其中新增覆盖：
        - event-loop reply after-turn continuity
        - voice authorization cancel after-turn continuity
        - after-turn derived summary trend / detail mapping
        - memory board `Latest After-Turn` presentation

## 5) 机读契约冻结

### 5.1 `xt.supervisor_personal_profile.v1`

```json
{
  "schema_version": "xt.supervisor_personal_profile.v1",
  "user_id": "user_main",
  "display_name": "Andrew",
  "timezone": "Asia/Shanghai",
  "primary_language": "zh-CN",
  "work_style_tags": ["maker_schedule", "deep_work"],
  "interruption_tolerance": "low",
  "review_preferences": {
    "morning_brief_enabled": true,
    "evening_wrap_enabled": true,
    "weekly_review_enabled": true
  },
  "updated_at_ms": 0
}
```

### 5.2 `xt.supervisor_personal_followup_item.v1`

```json
{
  "schema_version": "xt.supervisor_personal_followup_item.v1",
  "followup_id": "fu_123",
  "title": "Reply to Alex about partnership draft",
  "person_id": "person_alex",
  "source": "email",
  "status": "open",
  "due_at_ms": 0,
  "priority": "high",
  "suggested_next_action": "Send short acknowledgement today, full reply tomorrow morning",
  "audit_ref": "audit-xxxx"
}
```

### 5.3 `xt.supervisor_personal_review_note.v1`

```json
{
  "schema_version": "xt.supervisor_personal_review_note.v1",
  "review_id": "pr_123",
  "review_type": "morning_brief|evening_wrap|weekly_review|followup_sweep",
  "summary": "You have 2 overdue replies and 1 meeting in 90 minutes.",
  "recommended_actions": [
    "Reply to Alex",
    "Review partnership agenda"
  ],
  "generated_at_ms": 0,
  "audit_ref": "audit-xxxx"
}
```

## 6) Release 原则

必须满足：

- 个人层记忆仍受治理，不得变成“无限记忆黑箱”
- 用户能看到、修正、删除个人长期记忆
- 个人提醒与项目提醒必须分层，不可互相污染
- calendar / notifications / email 等 connector 动作继续走 grant / audit / fail-closed
- OpenClaw 只作为能力与接口复用源，不成为新的真相源

## 7) 本包的第一步建议

不要一口气把“完整人生助手”全做了。

建议按这个顺序落：

1. `XT-W3-38-A User Profile v1`
2. `XT-W3-38-H Persona Center v1`
3. `XT-W3-38-B Personal Memory v1`
4. `XT-W3-38-C Personal Review Loop v1`
5. `XT-W3-38-D Follow-up Ledger v1`
6. 再接 `Calendar / Notifications / Email`

原因：

- 没有用户画像和个人记忆，后面的提醒与日程只会变成机械通知器
- 没有 review loop，长期助手就不会主动
- 没有 follow-up ledger，关系与承诺就沉不下来

一句话结论：

- 这条线值得做，而且必须做
- 但不要重新发明 OpenClaw 已经有的插件槽、cron/heartbeat、node 能力面和 context engine 结构
- 直接把这些吸收到 X-Hub 的 Hub-first 治理框架里，做成 `Supervisor Personal Longterm Assistant` 主链
