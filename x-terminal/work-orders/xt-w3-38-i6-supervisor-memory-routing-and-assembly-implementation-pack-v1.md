# XT-W3-38-I6 Supervisor Memory Routing And Assembly Implementation Pack v1

- version: v1.0
- updatedAt: 2026-03-21
- owner: XT-L2（Primary）/ Supervisor / Hub Memory / QA / Product
- status: active
- scope: `XT-W3-38-I6`（把 `Supervisor Memory Routing And Assembly Protocol v1` 真正接到 X-Terminal runtime，补齐 turn routing、slot-based assembly、cross-link、after-turn writeback classification 与 explainability；本包只做 Supervisor runtime 的消费/装配/候选写回分类，不下放 memory model control-plane）
- parent:
  - `x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`
  - `x-terminal/work-orders/xt-w3-35-supervisor-memory-retrieval-progressive-disclosure-implementation-pack-v1.md`

## Status Notes

- 2026-03-21:
  - 同步 memory control-plane 边界：
    - `XT-W3-38-I6` 只消费上游已解析的 memory route / mode truth
    - turn router / context assembler / writeback classifier 不得在 XT / Supervisor 侧二次选择 memory AI
    - after-turn writeback classification 只产 candidate / scope hint；真正 durable maintenance 继续走 Hub 上游 `Scheduler -> Worker -> Writer + Gate`
  - `XT-W3-38-I6-E` 新增 child mapping：
    - `I6-E` 现作为 `XT-W3-38-I7-D2 Hub-First Supervisor Durable Memory Handoff` 的唯一 XT-side classification source
    - 固定要求：
      - `I6-E` 输出的 `user_scope / project_scope / cross_link_scope / working_set_only / drop_as_noise` 继续只是 candidate truth
      - XT shadow write 只能镜像 machine-readable candidate，不得跳过 Hub Writer + Gate 直接形成 durable promotion
      - Hub 不可要求 `I6-E` 回传第二套 memory route / chooser 结果
- 2026-03-19:
  - `XT-W3-38-I6-E` 继续补深 project writeback lane：
    - `project_scope` 不再只会从 after-turn ordinary conversation 里提 blocker / next-step；现在 goal / done / non-goal / approved tech stack 这组 anchor facts 也能在统一 lane 下被提升
    - 当前已补齐：
      - classifier 会把 `目标先锁成… / 完成标准是… / 先不做… / 只用…` 识别成 `project_goal_or_constraint`
      - question-like turns（如 `亮亮的目标是什么？`）不会再误判成 durable project fact
      - natural patch segment parser 补齐 `目标锁成 / 目标先锁成 / 目标定成 / 目标改成 / 完成标准锁成 / 技术栈锁成 / 只用...` 这类口语 token
      - unified lane 可把这类事实直接落进 `SupervisorProjectSpecCapsule`，供后续 local memory / focused review 继续消费
    - 新增回归：
      - `SupervisorAfterTurnWritebackClassifierTests.classifiesFocusedProjectGoalAndConstraintIntoProjectScope`
      - `SupervisorAfterTurnWritebackClassifierTests.doesNotClassifyProjectQuestionAsDurableFact`
      - `SupervisorProjectScopeWritebackTests.afterTurnWritebackPersistsFocusedProjectGoalDoneAndConstraintsThroughUnifiedLane`
  - `XT-W3-38-I6-E` 继续落第二段统一 writeback lane：
    - `SupervisorManager` 的 after-turn writeback 不再只写 `cross_link_scope`；`user_scope` 现在也会走统一 writeback lane
    - 当前已接入：
      - explicit personal-memory intent（`记一下，我偏好...`）会在 after-turn lane 内统一回写
      - inferred stable first-person context（如 `我通常早上先做深度工作`）会被提升成 durable `habit` / `preference`
      - non-user triggers（如 `heartbeat`）不会把 user_scope 内容误写进长期 personal memory
    - 新增 `SupervisorPersonalMemoryAutoCapture.inferredStableUserContextRecord(...)`
    - 新增回归：
      - `SupervisorPersonalMemoryAutoCaptureTests.afterTurnWritebackPersistsExplicitPreferenceThroughUnifiedLane`
      - `SupervisorPersonalMemoryAutoCaptureTests.afterTurnWritebackPersistsInferredStableHabitThroughUnifiedLane`
      - `SupervisorPersonalMemoryAutoCaptureTests.afterTurnWritebackDoesNotPromoteUserMemoryForNonUserTriggers`
  - `XT-W3-38-I6-E` 同步落第三段 project writeback：
    - `project_scope` 现在也会在 after-turn unified lane 内尝试落到项目记忆，而不是只停在 explainability
    - 当前已接入：
      - focused project blocker / next-step facts 会走统一 writeback，更新 project registry digest
      - colloquial project facts 继续复用自然语言 patch parser，并补齐 `blocker 是` 这类口语 token
      - 已经走过 local direct memory patch 的 turn，不会再被 after-turn 重复写一遍
      - non-user triggers（如 `heartbeat`）不会误改项目长期记忆
    - 新增回归：
      - `SupervisorProjectScopeWritebackTests.afterTurnWritebackPersistsFocusedProjectBlockerAndNextStepThroughUnifiedLane`
      - `SupervisorProjectScopeWritebackTests.afterTurnWritebackDoesNotPromoteProjectMemoryForNonUserTriggers`
      - `SupervisorProjectScopeWritebackTests.afterTurnWritebackSkipsDuplicateProjectPatchAfterLocalDirectAction`
    - 已验证：
      - `swift test --filter SupervisorProjectScopeWritebackTests`
      - `swift test --filter SupervisorPersonalMemoryAutoCaptureTests`
      - `swift test --filter SupervisorAfterTurnWritebackClassifierTests`
      - `swift test --filter SupervisorTurnExplainabilityStateTests`
      - `swift test --filter SupervisorCommandGuardTests`
      - `swift test --filter SupervisorMemoryAwareConversationRoutingTests`

- 2026-03-17:
  - `XT-W3-38-I6-A` 已落第一段实现：
    - 新增 `SupervisorTurnRouter`、`SupervisorTurnRoutingInput`、`SupervisorTurnRoutingDecision`、`SupervisorTurnMode`
    - 当前已支持 4 类 turn mode 判路：
      - `personal_first`
      - `project_first`
      - `hybrid`
      - `portfolio_review`
    - 当前 signal 已覆盖：
      - explicit project mention
      - explicit person mention（来自 structured personal memory）
      - explicit person mention（来自 durable cross-link store）
      - current project pointer
      - personal planning language
      - project planning language
      - portfolio review language
    - `SupervisorManager.buildSupervisorSystemPrompt(...)` 已开始注入 `Turn Routing Hint`
      - 会把 dominant mode、主记忆域、辅助记忆域、focused project/person 和 routing reasons 带进系统提示词
    - 新增 `SupervisorTurnRouterTests`
    - 已验证：
      - `swift test --filter SupervisorTurnRouterTests`
      - `swift test --filter SupervisorSystemPromptBuilderTests`
      - `swift test --filter SupervisorMemoryAwareConversationRoutingTests`
      - `swift test --filter SupervisorPersonalMemoryAutoCaptureTests`
  - `XT-W3-38-I6-B` 已落第一段实现：
    - 新增 `SupervisorFocusPointerState`、`SupervisorFocusPointerUpdater`
    - `SupervisorManager` 已开始持有并持久化 short-term focus pointers
      - 当前接入字段：
        - `currentProjectId`
        - `currentProjectAliases`
        - `currentPersonName`
        - `currentCommitmentId`
        - `currentTopicDigest`
        - `lastTurnMode`
        - `lastSeenDeltaCursor`
    - `SupervisorTurnRouter` 已开始消费 focus pointers：
      - current project pointer
      - current person pointer
      - current commitment pointer
    - `SupervisorManager.buildSupervisorSystemPrompt(...)` 已改成优先使用 fresh focus pointer，再回落到 UI selected project / current task
    - after-turn lifecycle 已开始回写 focus pointers，保证 `这个项目 / 他 / 按这个继续 / 这件事` 这类续接在 2 到 3 轮内稳定成立
    - 新增 `SupervisorFocusPointerStateTests`
    - 已验证：
      - `swift test --filter SupervisorFocusPointerStateTests`
      - `swift test --filter SupervisorTurnRouterTests`
      - `swift test --filter SupervisorSystemPromptBuilderTests`
      - `swift test --filter SupervisorMemoryAwareConversationRoutingTests`
      - `swift test --filter SupervisorPersonalMemoryAutoCaptureTests`
  - `XT-W3-38-I6-C` 已落 first slice：
    - 新增 `SupervisorTurnContextAssemblyRequest`、`SupervisorTurnContextAssemblyResult`、`SupervisorTurnContextAssembler`
    - 当前已把 turn routing 收口成固定 slot 选择结果：
      - `dialogue_window`
      - `personal_capsule`
      - `focused_project_capsule`
      - `portfolio_brief`
      - `cross_link_refs`
      - `evidence_pack`
    - `SupervisorManager.buildSupervisorSystemPrompt(...)` 已开始注入 `turnContextAssembly`
    - `SupervisorSystemPromptBuilder` 已新增 `Turn Context Assembly` explainability section
      - 会暴露 selected slots
      - omitted slots
      - selected refs
      - focus pointers
      - assembly reasons
    - 当前 prompt 已开始按 assembly result gate personal capsule sections，避免无条件散落注入
    - 新增 `SupervisorTurnContextAssemblerTests`
    - 已验证：
      - `swift test --filter SupervisorTurnContextAssemblerTests`
      - `swift test --filter SupervisorSystemPromptBuilderTests`
      - `swift test --filter SupervisorTurnRouterTests`
  - `XT-W3-38-I6-D` 已落 first slice：
    - 新增 `SupervisorCrossLinkRecord`、`SupervisorCrossLinkSnapshot`、`SupervisorCrossLinkStore`、`SupervisorCrossLinkSummaryBuilder`
    - `SupervisorManager` 的 after-turn lifecycle 已开始把 `cross_link_scope` durable 回写到独立 cross-link store
    - `SupervisorManager.composeSupervisorMemoryV1(...)` 已开始把 relevant cross-links 注入 `[CROSS_LINK_REFS]`
    - `SupervisorTurnRouter` 已开始消费 durable cross-link store 里的 person names，补足“人名不在 personal memory、但在 project dependency 里”的识别
    - 当前 first-pass durable link kind 已覆盖：
      - `person_waiting_on_project`
      - `commitment_depends_on_project`
    - 新增 `SupervisorCrossLinkStoreTests`
    - 已验证：
      - `swift test --filter SupervisorCrossLinkStoreTests`
      - `swift test --filter SupervisorTurnRouterTests`
      - `swift test --filter SupervisorTurnContextAssemblerTests`
      - `swift test --filter SupervisorSystemPromptBuilderTests`
  - `XT-W3-38-I6-E` 已落 first slice：
    - 新增 `SupervisorAfterTurnWritebackClassification`
    - 新增 `SupervisorAfterTurnWritebackClassifier`
    - `SupervisorManager` 的 after-turn lifecycle 已开始产出结构化 writeback classification
      - 当前 scope 已覆盖：
        - `user_scope`
        - `project_scope`
        - `cross_link_scope`
        - `working_set_only`
        - `drop_as_noise`
    - 当前 classifier 已覆盖的 first-pass durable 信号：
      - preferred name / explicit personal memory intent
      - stable first-person preference statement
      - focused project blocker / goal-constraint / plan-change
      - person-project / commitment-project dependency
    - 新增 `SupervisorAfterTurnWritebackClassifierTests`
    - 已验证：
      - `swift test --filter SupervisorAfterTurnWritebackClassifierTests`
    - 备注：
      - 尝试补跑 `swift test --filter SupervisorPersonalMemoryAutoCaptureTests` 时命中仓库内一组与本工单无关的既有编译错误（`SupervisorPortfolioBoardPresentationTests` / `SupervisorProjectDrillDownScope.workflow`），本轮未越界修 unrelated 测试线
  - `XT-W3-38-I6-F` 已落 first slice：
    - 新增 `SupervisorTurnMemoryExplainabilityPresentation`
    - `SupervisorManager` 已开始持有 latest turn routing / turn context assembly explainability state
    - `SupervisorMemoryBoardPresentationMapper` 已开始把 route + assembly + writeback 收口成轻量 `Latest Turn Memory` 卡片
    - `SupervisorMemoryBoardSection` / `SupervisorView` 已接入该 explainability surface
    - `syncSupervisorAfterTurnWritebackClassificationForTesting(...)` 现已同步刷新 latest routing / assembly explainability state，避免 after-turn 测试只验证 writeback、不验证 explainability 发布
    - 当前已暴露的最少字段：
      - `primary_memory_domain`
      - `supporting_memory_domains`
      - `focused_project_label`
      - `focused_person_label`
      - `writeback_summary`
      - `selected_slots`
      - `selected_refs`
    - 新增 `SupervisorMemoryBoardPresentationTests` 覆盖 explainability 映射
    - 新增 `SupervisorTurnExplainabilityStateTests`，锁定 after-turn helper 会发布 latest routing / assembly explainability state
    - 已验证：
      - `swift test --filter SupervisorMemoryBoardPresentationTests`
      - `swift test --filter SupervisorTurnRouterTests`
      - `swift test --filter SupervisorCrossLinkStoreTests`
      - `swift test --filter SupervisorTurnExplainabilityStateTests`
  - `XT-W3-38-I6-G` 已落第一段 regression clamp：
    - 新增 router regression，锁定 `帮我看下今天最重要的事` 仍走 `personal_first`，不因 `最重要` 误退化成 `portfolio_review`
    - 新增 router regression，锁定 ambiguous turn（如 `接下来呢？`）不会 fabricated project/person focus
    - 新增 local direct reply regression，锁定 `sendMessage("我叫 Andrew")` 这类本地直答仍会走统一 after-turn，并发布 latest routing / assembly explainability state
    - 新增 fallback regression，锁定 `local_fallback_after_remote_error` 仍保留 latest routing / assembly explainability 与失败路由诊断
    - 新增 project-memory scope regression，锁定 project coder 的 `MEMORY_V1` block 不带 `Personal Memory / Follow-Up / Personal Review / CROSS_LINK_REFS`
    - 新增 Memory Board regression，锁定 `local_fallback_after_remote_error` 下 `Latest Turn Memory` 卡片仍可见
    - 本轮未放松任何 scope 边界：
      - project focus 仍需 explicit signal / active pointer
      - personal memory 仍只在 Supervisor 自身回合装配，不默认透传给 project coder
    - 已验证：
      - `swift test --filter SupervisorTurnRouterTests`
      - `swift test --filter SupervisorPersonalMemoryAutoCaptureTests`
      - `swift test --filter SupervisorFailureFormattingTests`
      - `swift test --filter ProjectMemoryUIReviewPromptTests`
      - `swift test --filter SupervisorMemoryBoardPresentationTests`

## 0) 为什么单开这份包

`XT-W3-38` 目前已经把个人助理的几块基础拼出来了：

- `SupervisorPersonalMemoryStore`
- `SupervisorPersonalReviewNoteStore`
- `SupervisorFollowUpLedger`
- conversation continuity floor
- after-turn lifecycle
- first-pass explainability surface

但还缺一层把这些东西“丝滑接起来”的运行核。

现在的主要缺口已经从“有没有”转成“够不够完整”：

1. turn router / focus pointer / slot assembler / writeback classifier / cross-link store 都已落 first slice，但仍需继续补完 UI explainability 和更深的 durable promotion 策略。
2. `cross-link` 现在已经能独立 durable 保存并回灌进 `[CROSS_LINK_REFS]`，但目前 link kind 还只覆盖第一批高价值连接。
3. `afterTurn` 现在已经能给出 `user / project / cross-link / working_set_only / drop_as_noise` 分类，但 user/project 的 durable promotion 还没有完全统一到单一 writeback lane。
4. explainability surface 还没把“这轮主用哪类记忆、写回了哪类记忆”完整暴露到 Memory Board / UI。

所以这一包不再讨论理念，只解决 runtime 落地。

## 1) 一句话冻结决策

冻结：

- `Supervisor` 每轮先产出 `turn mode + focus pointers`
- 再按固定 slots 装配 `dialogue / personal / project / portfolio / cross-link`
- 回答后再按 scope 做 writeback classification
- 同时在 UI / debug surface 暴露“这轮主要用了哪类记忆、写回了哪类记忆”
- 本包消费上游已解析完成的 memory route / mode truth，不在 XT / Supervisor 侧二次选择 memory AI

## 2) 固定决策

### 2.1 不新增第二套 truth source

- 不引入 XT 本地新的 personal/project canonical 真相源
- 只新增 runtime 组装器、短期 pointer、cross-link durable store 和 writeback classifier
- 不在 XT / Supervisor 侧解析 `memory_model_preferences`
- 不把 turn router / context assembler / writeback lane 做成第二个 memory 控制面

### 2.2 先做 `Supervisor`，不扩到 `project coder`

本包只覆盖：

- Supervisor 普通聊天
- Supervisor personal assistant turn
- Supervisor project review / portfolio review

不在本包内扩到：

- project coder prompt assembly
- subagent spawn context contract
- external operator channel memory assembly

### 2.3 `cross-link` 是第一等对象，不是副产物

`人 <-> 项目 <-> 承诺` 的连接事实必须可存、可查、可解释。

### 2.4 explainability 必须跟 runtime 一起交付

不接受“先做 route/assembly，后面再补 explainability”。

## 3) 实施拆分

### XT-W3-38-I6-A Supervisor Turn Router

- 目标：每轮先产出结构化 `turn mode`
- turn router 只判断本轮主语、主记忆域与 focus，不决定 memory maintenance AI
- 新增对象：
  - `SupervisorTurnMode`
  - `SupervisorTurnRoutingDecision`
  - `SupervisorTurnRouter`
- 最少输出：
  - `mode`
  - `focusedProjectId`
  - `focusedPersonName`
  - `focusedCommitmentId`
  - `confidence`
  - `routingReasons`
- routing 目标模式：
  - `personal_first`
  - `project_first`
  - `hybrid`
  - `portfolio_review`
- 输入信号至少包括：
  - explicit project name / alias
  - explicit person name
  - execution / planning / follow-up verbs
  - current project pointer
  - due personal reviews / follow-ups
  - portfolio recommended focus
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorTurnRouter.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Tests/SupervisorTurnRouterTests.swift`
- DoD：
  - `我今天先做什么` 默认进 `personal_first`
  - `亮亮下一步怎么推进` 默认进 `project_first`
  - `Alex 还在等亮亮 demo，我今天怎么安排` 默认进 `hybrid`
  - `现在整体先抓什么` 默认进 `portfolio_review`

### XT-W3-38-I6-B Focus Pointer State

- 目标：让 `这个 / 他 / 刚才那个 / 按这个继续` 有稳定承接
- 新增对象：
  - `SupervisorFocusPointerState`
  - `SupervisorFocusPointerUpdater`
- 最少字段：
  - `currentProjectId`
  - `currentPersonName`
  - `currentCommitmentId`
  - `currentTopicDigest`
  - `lastTurnMode`
  - `lastSeenDeltaCursor`
- 设计要求：
  - pointer 是 continuity helper，不是 durable truth
  - pointer 过期后要允许自然回落重判
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorFocusPointerState.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Tests/SupervisorFocusPointerStateTests.swift`
- DoD：
  - 连续 2 到 3 轮代词引用可稳定落到正确项目/人物
  - 过期 pointer 不会强行错误绑定

### XT-W3-38-I6-C Supervisor Turn Context Assembler

- 目标：把 route 结果收口成固定 slot 装配，而不是临时拼 prompt
- 新增对象：
  - `SupervisorTurnContextAssemblyRequest`
  - `SupervisorTurnContextAssemblyResult`
  - `SupervisorTurnContextAssembler`
- 固定 slots：
  - `dialogueWindow`
  - `personalCapsule`
  - `focusedProjectCapsule`
  - `portfolioBrief`
  - `crossLinkRefs`
- 最少输出：
  - `turnMode`
  - `selectedSlots`
  - `omittedSlots`
  - `selectedRefs`
  - `assemblyReason`
- 要求：
  - `project_first` 仍保留 light personal capsule
  - `personal_first` 仍保留 light portfolio brief
  - `hybrid` 必须带 `crossLinkRefs`
  - `portfolio_review` 默认不 full dump 单项目
  - assembler 只消费上游已授予的 scope / serving profile / retrieval result，不在装配时自行重解 `memory_model_preferences` 或升降 maintenance model
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorTurnContextAssembler.swift`
  - `x-terminal/Sources/Supervisor/SupervisorSystemPromptBuilder.swift`
  - `x-terminal/Tests/SupervisorTurnContextAssemblerTests.swift`
- DoD：
  - prompt builder 不再直接散落拼 personal/project pieces
  - assembly result 可单测、可调试、可回放

### XT-W3-38-I6-D Supervisor Cross-Link Store

- 目标：把 `人和项目的连接事实` 从 prose 中解耦出来
- 新增对象：
  - `SupervisorCrossLinkRecord`
  - `SupervisorCrossLinkStore`
  - `SupervisorCrossLinkSummaryBuilder`
- 最少支持的 link kind：
  - `person_waiting_on_project`
  - `commitment_depends_on_project`
  - `meeting_about_project`
  - `follow_up_triggered_by_project`
  - `user_priority_constrained_by_project`
- 最少字段：
  - `linkId`
  - `linkKind`
  - `projectId`
  - `personName`
  - `summary`
  - `backingRecordRefs`
  - `status`
  - `updatedAt`
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorCrossLinkStore.swift`
  - `x-terminal/Tests/SupervisorCrossLinkStoreTests.swift`
- DoD：
  - `Alex 在等亮亮 demo` 这类事实可 durable 保存
  - `hybrid` turn 能明确读出这类 link

### XT-W3-38-I6-E After-Turn Writeback Classifier

- 目标：把每轮新事实按 scope 分类，不再靠各分支临时判断
- writeback classification 只产生 candidate / scope hint；真正 durable maintenance 仍走 Hub 上游 `Scheduler -> Worker -> Writer + Gate`
- 新增对象：
  - `SupervisorAfterTurnWritebackClassification`
  - `SupervisorAfterTurnWritebackClassifier`
- 最少分类：
  - `user_scope`
  - `project_scope`
  - `cross_link_scope`
  - `working_set_only`
  - `drop_as_noise`
- 每条 candidate 最少字段：
  - `scope`
  - `recordType`
  - `confidence`
  - `whyPromoted`
  - `sourceRef`
  - `auditRef`
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorAfterTurnWritebackClassifier.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Tests/SupervisorAfterTurnWritebackClassifierTests.swift`
- DoD：
  - “我喜欢简洁直接” -> `user_scope`
  - “亮亮现在 blocker 是 grant pending” -> `project_scope`
  - “Alex 在等亮亮 demo” -> `cross_link_scope`
  - 无证据寒暄 -> `drop_as_noise`
  - 不会把 XT 侧 classification 误当最终 durable write order

### XT-W3-38-I6-F Prompt / UI Explainability Alignment

- 目标：把 route + assembly + writeback 结果暴露给开发态和用户态
- 新增对象：
  - `SupervisorTurnMemoryExplainability`
  - `SupervisorMemoryBoard` 补充 route/assembly/writeback 行
- 最少可见字段：
  - `primary_memory_domain`
  - `supporting_memory_domains`
  - `focused_project_label`
  - `focused_person_label`
  - `writeback_summary`
- UI 目标：
  - 轻量，不打断聊天
  - 让用户知道“这轮主用哪类记忆”
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorMemoryBoardPresentation.swift`
  - `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - `x-terminal/Tests/SupervisorMemoryBoardPresentationTests.swift`
- DoD：
  - 能显示：
    - `本轮主用：项目记忆（亮亮）；辅助：个人 follow-up`
    - 或 `本轮主用：个人记忆；辅助：项目摘要`

### XT-W3-38-I6-G Regression + Governance Clamp

- 目标：保证新 route/assembly 不绕开现有 Hub-first 边界
- 必测：
  - `X-Constitution` 不退化
  - personal memory 不被 project coder 默认透传
  - ambiguous turn 不 fabricated focus
  - fallback 路径仍保留 explainability
  - event-loop / voice / direct reply 仍走统一 after-turn
  - XT / Supervisor 不因 local fallback、assembly 或 writeback classification 而变成 memory model chooser
- 回归集：
  - `SupervisorMemoryAwareConversationRoutingTests`
  - `SupervisorPersonalMemoryAutoCaptureTests`
  - `SupervisorFailureFormattingTests`
  - 新增：
    - `SupervisorTurnRouterTests`
    - `SupervisorTurnContextAssemblerTests`
    - `SupervisorAfterTurnWritebackClassifierTests`
    - `SupervisorCrossLinkStoreTests`

## 4) 执行顺序

推荐顺序固定为：

1. `I6-A` Turn Router
2. `I6-B` Focus Pointer State
3. `I6-C` Context Assembler
4. `I6-E` After-Turn Writeback Classifier
5. `I6-D` Cross-Link Store
6. `I6-F` Explainability Alignment
7. `I6-G` Regression / clamp

原因：

- 没有 route，就没有稳定 assembly
- 没有 assembly，就没有可靠 writeback classification
- cross-link store 要等前两者稳定后再接，不然会先把错误 link durable 化

## 5) Release Condition

本包完成前，至少要满足：

- `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
- `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`
- `x-terminal/work-orders/xt-w3-35-supervisor-memory-retrieval-progressive-disclosure-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md`

同时必须达成：

- Supervisor 普通对话、个人助理对话、项目 review 三类回合都走统一 route + assembly 主线
- 新增 durable writeback 都带 explainability / audit refs
- 不因为支持 personal + project 混合记忆，就让 scope 边界变糊
- route / assembly / writeback explainability 中展示的是上游已解析 route truth，而不是 XT 本地臆造的模型选择结果

## 6) One-Sentence Conclusion

`XT-W3-38-I6` 的目标不是“让 Supervisor 看到更多记忆”，而是：

`让 Supervisor 每轮都能稳定判断该以谁为主语、该喂哪几块记忆、该把新事实写回哪个 scope。`
