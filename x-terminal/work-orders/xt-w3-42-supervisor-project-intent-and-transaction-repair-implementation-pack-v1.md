# XT-W3-42 Supervisor Project Intent And Transaction Repair Implementation Pack v1

- version: `v1.0`
- updatedAt: `2026-03-30`
- owner: XT-L2（Primary）/ Product / QA
- status: `planned`
- scope: `XT-W3-42-A1..A6`（把 Supervisor 的项目创建/改名/删除从“关键词直触发”修到“先理解意图，再走受治理事务执行”，并补齐多轮纠错闭环）
- parent:
  - `x-terminal/work-orders/xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-33-supervisor-decision-kernel-routing-and-memory-governance-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `X_MEMORY.md`
  - `docs/WORKING_INDEX.md`

## 0) 为什么单开这份包

当前 Supervisor 在“项目动作”这条线上已经出现了一个典型且严重的产品失败模式：

1. 用户先问能力/权限问题：
   - “你诚实说，你现在有权限或能力建一个project了吗？”
2. Supervisor 没把这句话当成诊断或状态询问，而是误走了本地 project-create 流程。
3. 它回了一个看起来像执行承诺、实际上来自默认 intake 恢复路径的话：
   - “我会按上一轮默认方案创建《你诚实说，你现在有权限或能力建一个project了》。”
4. 错项目被真的创建出来以后，用户继续说：
   - “我要建的project名叫‘坦克大战’。前面建错的project你删掉吧。”
5. Supervisor 没有完成删除。
6. 用户退一步说：
   - “那你把前面的项目名称改成‘坦克大战’也可以。”
7. Supervisor 又退化成假的“记住了/记下了”型回复，没有执行真实改名事务。

这不是单点文案问题，而是一个系统性事务缺口：

- 项目创建的触发太早、太机械。
- 问句/诊断句没有被 fail-closed 地挡住副作用。
- pending intake / recovered proposal 在多轮里会把后续句子过度吸进“继续建项目”路径。
- 项目创建之后没有“纠错窗口”。
- `rename_project` / `delete_project` / `undo_last_project_creation` 没有作为 Supervisor 自然语言事务闭环落地。
- 对带副作用的请求，Supervisor 还允许输出“我记下了”这种假确认。

因此这份包的目标不是“再补几个关键词”，而是把项目动作修成一个正式受治理的事务链：

- 先理解意图
- 再决定是否允许副作用
- 最后由 deterministic executor 真执行或真拒绝

## 1) 当前代码偏差点

本包以当前已存在的真实代码路径为基准，不做空中设计。

### 1.1 过早的本地 create 触发

`x-terminal/Sources/Supervisor/SupervisorManager.swift`

当前项目创建会很早进入本地直通逻辑：

- `directSupervisorPendingExecutionIntakeProjectCreationIfApplicable(...)`
- `directSupervisorPendingExecutionIntakeProjectCreationConfirmationIfApplicable(...)`
- `isExplicitProjectCreationRequest(...)`

问题不是“有 create 能力”，而是 create 路径在意图未充分消歧之前就能被命中。

### 1.2 诊断句识别过窄

`isProjectCreationDiagnosticQuestion(...)` 目前偏向识别：

- “为什么创建不了项目”
- “为什么建不了项目”
- “创建失败”

但像下面这类能力/权限询问并不会被稳定挡住：

- “你现在有权限或能力建一个project了吗？”
- “你现在能不能建项目？”
- “你现在只是会说，还是能真的创建？”

### 1.3 pending goal follow-up 吞句过度

`directSupervisorPendingProjectCreationGoalFollowUpIfApplicable(...)`
`normalizedPendingProjectCreationGoalClarification(...)`

当系统处于 “awaitingGoal” 或 pending intake 状态时，后续用户话语会被过度当成：

- goal clarification
- project name clarification
- recovered proposal confirmation

这就是为什么能力问题、纠错问题、改名请求，会被错误继续推进到创建逻辑里。

### 1.4 recovered proposal 恢复链可以误拉起 create

`recentSupervisorProjectCreationProposal(...)`
`parseSupervisorProjectCreationProposal(...)`

这些恢复逻辑本身是有价值的，但当前缺少一层更高优先级的“这句是不是在问问题/纠错/删除/改名”判断，导致 recovered proposal 会抢占真实用户意图。

### 1.5 create 执行层本身是可复用的

`createProject(_:)`
`AppModel.ensureRegisteredProjectBoundary(...)`

低层项目边界初始化能力是存在的，且总体方向是对的：

- 能创建真实 project boundary
- 能初始化 registry + config + memory boundary

所以这份包不重写 create executor，只修上层事务入口和纠错闭环。

### 1.6 rename / delete 底层有能力，但 Supervisor 没有事务化暴露

现有可复用能力包括：

- `AppModel.ensureRegisteredProjectBoundary(... preferredDisplayName:)`
  - 可用于“只改显示名，不搬磁盘根目录”的 rename v1
- `AppModel.removeProject(_:)`
  - 可用于 registry 级删除
- `AppModel+MultiProject.rollbackMaterializedProjectBoundary(...)`
  - 提供了“删 registry 并可选 removeRoot”的实现参考
- `MultiProjectManager.deleteProject(_:)`
  - 多项目模型侧已有 delete 思路

缺的是 Supervisor 自然语言事务层，不是底层完全没有 delete/rename 能力。

## 2) 固定决策

### 2.1 先理解意图，再执行动作

冻结：

- 项目创建/改名/删除不再由机械关键词直接触发。
- Supervisor 必须先产出结构化 `project action intent`，再决定是否执行 side effect。
- semantic layer 可以是本地 typed resolver，不强依赖远端模型；但无论实现方式如何，都必须先过意图解析层。

### 2.2 问句默认不执行副作用

任何带副作用语义的消息，只要主意图更像：

- 能力询问
- 权限询问
- 状态询问
- 失败诊断
- 是否可做的确认

就默认 `non-executing`。

典型信号包括但不限于：

- `?`
- `？`
- `吗`
- `么`
- `能不能`
- `可不可以`
- `有没有权限`
- `有没有能力`
- `你现在能不能`
- `你诚实说`
- `为什么创建不了`

规则：

- `question > side effect`
- 只要句子主意图仍是问，不准直接 create / rename / delete

### 2.3 用户显式项目名永远覆盖推断名

冻结：

- 一旦用户明确说出：
  - “项目名叫坦克大战”
  - “我要建的 project 名叫坦克大战”
  - “把前面的项目改名为坦克大战”
- 该显式名字优先级高于：
  - pending intake 的 `suggestedProjectName`
  - recovered proposal 的默认项目名
  - 从 goalSummary 推断出来的默认名

### 2.4 create 变成两阶段事务

允许两种 create 入口，但都必须经过事务层：

1. 明确 imperative 且槽位完整：
   - 例：`创建项目 坦克大战`
   - 例：`现在帮我创建一个叫坦克大战的项目`
   - 可以直接进入 execute，但仍要先形成结构化 intent 和 transaction record
2. 依赖上下文恢复或默认方案：
   - 例：`就按这个建`
   - 例：`按默认方案建项目`
   - 必须先确认当前恢复目标是谁，再执行

禁止：

- 把能力问题当成立即创建
- 把模糊 follow-up 当成立即创建

### 2.5 create 后必须进入纠错窗口

成功创建项目后，Supervisor 必须保留一个短时、可审计、可引用的 correction window。

在这个窗口里，用户可以直接说：

- “删掉前面建错的项目”
- “撤销刚才创建的项目”
- “把前面的项目名称改成坦克大战”

系统应优先绑定到：

- `last_created_project_id`
- `last_project_transaction_id`
- `last_created_display_name`

而不是让用户重复描述 projectId。

### 2.6 对副作用请求禁止假确认

冻结：

- 带副作用的用户请求，Assistant 不允许只回复：
  - “我记下了”
  - “我已经记住了”
  - “这条关键路径决策我已经记下了”
- 对 `create / rename / delete / undo`：
  - 要么返回成功执行结果
  - 要么返回明确未执行原因
  - 要么返回明确澄清问题

### 2.7 rename v1 只改 display name

本包第一阶段不做：

- 项目根目录 rename / move
- 全量磁盘重命名迁移
- 外部引用 rewrite

`rename_project` v1 只保证：

- registry displayName 更新
- project memory / summary 中的项目名保持一致
- 用户可见项目标题正确

## 3) 机读契约冻结

### 3.1 `xt.supervisor_project_action_intent.v1`

用途：

- 在执行任何项目副作用前，先把当前句子解析成结构化意图。

```json
{
  "schema_version": "xt.supervisor_project_action_intent.v1",
  "message_id": "msg_001",
  "action_kind": "ask_capability",
  "side_effect_allowed": false,
  "requires_clarification": false,
  "confidence": "high",
  "target_resolution": {
    "binding_mode": "none",
    "project_id": null,
    "project_name": null,
    "source": "none"
  },
  "slots": {
    "explicit_project_name": null,
    "goal_summary": null,
    "rename_to": null,
    "delete_scope": null,
    "references_last_created_project": false
  },
  "reason_code": "question_non_executing",
  "source_refs": [
    "current_user_message",
    "recent_supervisor_state"
  ]
}
```

`action_kind` 最低要求支持：

- `ask_capability`
- `ask_status`
- `create_project`
- `rename_project`
- `delete_project`
- `undo_last_project_creation`
- `clarify_project_name`
- `clarify_goal`
- `none`

### 3.2 `xt.supervisor_project_transaction_state.v1`

用途：

- 让 create / rename / delete 成为可追踪的事务，而不是散落在文案里的隐式动作。

```json
{
  "schema_version": "xt.supervisor_project_transaction_state.v1",
  "transaction_id": "proj_txn_001",
  "kind": "create_project",
  "status": "confirmed",
  "created_at_ms": 1774800000000,
  "updated_at_ms": 1774800000000,
  "project_id": null,
  "project_name_before": null,
  "project_name_after": "坦克大战",
  "goal_summary": "创建一个坦克大战项目骨架",
  "trigger_message": "现在帮我创建一个叫坦克大战的项目",
  "confirmation_mode": "direct_imperative",
  "reason_code": "ready_to_execute",
  "execution_result": null
}
```

最低状态集合：

- `draft`
- `awaiting_confirmation`
- `confirmed`
- `executing`
- `succeeded`
- `failed`
- `canceled`

### 3.3 `xt.supervisor_project_correction_window.v1`

用途：

- 支撑 “删掉前面建错的项目 / 把前面的项目改名” 这种自然多轮纠错。

```json
{
  "schema_version": "xt.supervisor_project_correction_window.v1",
  "window_id": "proj_fix_001",
  "opened_by_transaction_id": "proj_txn_001",
  "project_id": "proj_tank_demo",
  "display_name_at_open": "你诚实说，你现在有权限或能力建一个project了",
  "opened_at_ms": 1774800005000,
  "expires_at_ms": 1774800605000,
  "allowed_actions": [
    "rename_project",
    "delete_project",
    "undo_last_project_creation"
  ],
  "is_active": true
}
```

窗口规则冻结：

- 默认短时有效；建议实现值 `10 分钟`
- 仅绑定最近一次成功的 `create_project`
- 后续成功的 create 会覆盖前一窗口

## 4) 产品边界

### 4.1 本包必须做到

- 能力/权限/状态问题不会触发 create
- 用户显式项目名能覆盖默认推断名
- create 后可直接 delete / rename / undo
- side-effect 请求不再出现假的“记下了”型答复
- recovered proposal 仍可继续用，但不再压过更高优先级的纠错/问句意图

### 4.2 本包明确不做

- 不重写全部 Supervisor NL 系统
- 不引入全新的大型 LLM control plane 依赖
- 不做项目根目录 rename/move
- 不把 dashboard/voice/UI 外观一起混进本包
- 不扩展为“任意历史项目都能自然语言删除”的通用搜索系统

v1 先闭合最近一次 project transaction 的多轮修复。

## 5) 详细执行拆分

### XT-W3-42-A1 Project Action Intent Resolver

- priority: `P0`
- 目标：在任何项目副作用之前，先做统一意图解析。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 新增建议：
    - `x-terminal/Sources/Supervisor/SupervisorProjectActionIntent.swift`
    - `x-terminal/Sources/Supervisor/SupervisorProjectActionResolver.swift`
- 具体任务：
  1. 抽出 `resolveProjectActionIntent(...)` 纯函数或纯 helper，统一返回 `xt.supervisor_project_action_intent.v1` 对应结构。
  2. 在 resolver 中区分：
     - 问句
     - 诊断句
     - create imperative
     - rename imperative
     - delete imperative
     - undo imperative
     - 目标/项目名澄清句
  3. `pending goal`、`recovered proposal`、`recent action` 只作为 resolver 的上下文输入，不能直接跳过 resolver。
  4. `isProjectCreationDiagnosticQuestion(...)` 扩成更通用的 non-executing 问句判别，不再只盯 “为什么创建不了项目”。
- DoD：
  - 没有任何项目副作用入口可以绕过 `resolveProjectActionIntent(...)`
  - “你现在有权限或能力建一个project了吗？” 被稳定解析为 `ask_capability`
  - `side_effect_allowed == false`

### XT-W3-42-A2 Create Transaction Gate And Confirmation

- priority: `P0`
- 目标：把项目创建升级成正式事务，而不是一句话直通。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 新增建议：
    - `x-terminal/Sources/Supervisor/SupervisorProjectTransactionState.swift`
- 具体任务：
  1. 任何 create 都先写 transaction state，再执行 create。
  2. 对 `recovered proposal` / `default plan` 这类上下文 create，必须保留明确确认状态。
  3. 让显式项目名覆盖 `intake.suggestedProjectName`。
  4. 移除 “我会按上一轮默认方案创建《...》” 这种在目标未明确、意图未消歧前就承诺执行的路径。
  5. 当句子更像 `clarify_project_name` 而不是 `create_project` 时，只更新 draft transaction，不直接执行。
- DoD：
  - 项目名叫“坦克大战”时，不会再继续沿用旧的推断名
  - create 的回复与 transaction status 一致
  - pending intake 不会吞掉能力问句

### XT-W3-42-A3 Correction Window And Last-Created Binding

- priority: `P0`
- 目标：支持“前面建错了”的自然多轮修复。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 新增建议：
    - `x-terminal/Sources/Supervisor/SupervisorProjectCorrectionWindow.swift`
- 具体任务：
  1. create 成功后记录：
     - `last_created_project_id`
     - `last_created_display_name`
     - `last_project_transaction_id`
     - `opened_at / expires_at`
  2. 让以下表达自动指向 correction window target：
     - “前面建错的项目”
     - “刚才创建的项目”
     - “上一个项目”
  3. 如果 correction window 过期或 target 丢失，必须明确说“我找不到刚才那个 project target”，而不是静默失败。
  4. 后续 rename / delete / undo 都优先绑定 correction window target。
- DoD：
  - 用户不必重复输入 projectId
  - 最近一次 create 后，紧接着说“删掉前面建错的项目”能找到目标

### XT-W3-42-A4 Rename / Delete / Undo Transaction Executors

- priority: `P0`
- 目标：补齐项目纠错最小闭环。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/AppModel+MultiProject.swift`
  - `x-terminal/Sources/Project/AXProjectRegistry.swift`
- 具体任务：
  1. `rename_project`
     - v1 只改 `displayName`
     - 复用 `ensureRegisteredProjectBoundary(... preferredDisplayName:)` 或等价 upsert 路径
     - 同步刷新可见 memory/project summary 名称
  2. `delete_project`
     - 对 correction window 内“刚创建且无后续实质工作”的项目，优先走 undo/delete boundary
     - 最低要求先从 registry 正确移除
     - 如果实现可安全删除空边界目录，允许同时 remove root
  3. `undo_last_project_creation`
     - 绑定最近一次成功 create
     - 成功后关闭 correction window
  4. 所有 executor 都必须返回 machine-readable result，再转成用户答复。
- DoD：
  - “删掉前面建错的 project” 真删除或真失败，不再假确认
  - “把前面的项目名称改成坦克大战” 真改名或真失败
  - `undo_last_project_creation` 有单独 reason code

### XT-W3-42-A5 Side-Effect Reply Contract And No-Fake-Ack Enforcement

- priority: `P0`
- 目标：彻底禁止带副作用请求落到“我记下了”的假执行口径。
- 代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 新增建议：
    - `x-terminal/Sources/Supervisor/SupervisorProjectActionResult.swift`
- 具体任务：
  1. 为 create / rename / delete / undo 建立统一结果类型：
     - `executed_success`
     - `executed_failure`
     - `not_executed_clarification_required`
     - `not_executed_policy_denied`
     - `not_executed_target_missing`
  2. 任何 side-effect intent 都只能走结果驱动回复，不允许旁路到 memory-like acknowledgement。
  3. 如果动作没执行，答复里必须显式说明：
     - 没执行
     - 为什么
     - 用户下一句应该怎么说
- DoD：
  - 对副作用请求，回复文本和执行状态不会分叉
  - 不再出现“关键路径决策我已经记下了”替代 rename/delete 结果

### XT-W3-42-A6 Regression Tests

- priority: `P0`
- 目标：把这次“坦克大战”事故固化成回归测试。
- 代码落点：
  - `x-terminal/Tests/SupervisorCommandGuardTests.swift`
  - 新增建议：
    - `x-terminal/Tests/SupervisorProjectTransactionRepairTests.swift`
- 具体任务：
  1. 覆盖能力/权限问句 fail-closed。
  2. 覆盖 pending goal follow-up 不吞问句。
  3. 覆盖显式项目名覆盖默认推断名。
  4. 覆盖 correction window 的 rename/delete/undo。
  5. 覆盖 side-effect reply 不能退化成 fake ack。
- 最低测试集建议：
  - `capabilityQuestionDoesNotCreateProjectOrInstallWrongName`
  - `pendingProjectCreationQuestionDoesNotBecomeGoalClarification`
  - `explicitProjectNameOverridesRecoveredProposalSuggestedName`
  - `renameLastCreatedProjectWithinCorrectionWindow`
  - `deleteLastCreatedProjectWithinCorrectionWindow`
  - `undoLastProjectCreationRemovesRecentBoundary`
  - `sideEffectRequestCannotFallBackToMemoryAcknowledgement`
- DoD：
  - 用户提供的真实失败脚本被完整覆盖

## 6) 真实场景验收矩阵

### 6.1 能力询问不执行

用户：

- “你诚实说，你现在有权限或能力建一个project了吗？”

期望：

- 返回 capability/status answer
- 不创建项目
- 不安装 pending create transaction
- 不把整句话变成项目名

### 6.2 显式命名覆盖默认名

前置：

- 系统有一个 pending intake 或 recovered proposal

用户：

- “我要建的project名叫坦克大战。”

期望：

- 当前 draft transaction 的 project name 更新为 `坦克大战`
- 不再使用旧推断名
- 如仍缺 goal，可澄清 goal；但不得直接回到旧项目名

### 6.3 删除前一个误建项目

前置：

- 刚刚误建了一个项目，correction window 仍有效

用户：

- “前面建错的project你删掉吧。”

期望：

- 解析为 `delete_project` 或 `undo_last_project_creation`
- target 指向 correction window 内最后一次 create
- 回复为真执行结果，例如：
  - `已删除刚才误建的项目《X》。`
  - 或 `我没删，因为 correction window 已过期。`

### 6.4 把前一个项目改名为坦克大战

前置：

- 刚创建过一个名字错误的项目

用户：

- “那你把前面的项目名称改成‘坦克大战’也可以。”

期望：

- 解析为 `rename_project`
- target 绑定 correction window target
- rename_to = `坦克大战`
- 回复为真执行结果，不准是记忆式应答

## 7) 文件级实施边界

### 7.1 本包主写域

- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- 新增 `x-terminal/Sources/Supervisor/SupervisorProjectActionIntent.swift`
- 新增 `x-terminal/Sources/Supervisor/SupervisorProjectActionResolver.swift`
- 新增 `x-terminal/Sources/Supervisor/SupervisorProjectTransactionState.swift`
- 新增 `x-terminal/Sources/Supervisor/SupervisorProjectCorrectionWindow.swift`
- 新增 `x-terminal/Sources/Supervisor/SupervisorProjectActionResult.swift`
- `x-terminal/Tests/SupervisorCommandGuardTests.swift`
- 新增 `x-terminal/Tests/SupervisorProjectTransactionRepairTests.swift`

### 7.2 可复用但不要大改的相邻文件

- `x-terminal/Sources/AppModel.swift`
- `x-terminal/Sources/AppModel+MultiProject.swift`
- `x-terminal/Sources/Project/AXProjectRegistry.swift`

原则：

- 尽量只加最小 helper，不把这些文件拖进大重构。

### 7.3 本包避免触碰

- broad `x-terminal/Sources/UI/` 重排
- dashboard 视觉层
- voice/TTS
- repo 级 release gate
- Hub JS runtime

## 8) 建议实现顺序

1. 先落 `A1`：
   - 先把问句/能力/删除/改名从 create 直通链中剥离出来。
2. 再落 `A2`：
   - create 改成 transaction gate。
3. 再落 `A3` + `A4`：
   - 补 correction window 和 rename/delete/undo。
4. 最后补 `A5` + `A6`：
   - 封口假确认，并把真实事故写成回归测试。

不要反过来做。
如果先补 delete/rename executor，但 create 入口仍旧机械误触发，问题只会继续制造坏数据。

## 9) 多 AI 派工建议

如果要并行分给多个 AI，按不冲突功能拆成下面 4 条线：

### Lane 1: Intent Resolver

- own:
  - `SupervisorManager.swift`
  - `SupervisorProjectActionIntent.swift`
  - `SupervisorProjectActionResolver.swift`
- goal:
  - 完成 `A1`
- avoid:
  - `AppModel.swift`
  - `AppModel+MultiProject.swift`
  - tests 以外的 project registry 文件

### Lane 2: Create Transaction + Correction Window

- own:
  - `SupervisorManager.swift`
  - `SupervisorProjectTransactionState.swift`
  - `SupervisorProjectCorrectionWindow.swift`
- goal:
  - 完成 `A2` + `A3`
- avoid:
  - broad UI
  - Hub

### Lane 3: Rename / Delete / Undo Executors

- own:
  - `AppModel.swift`
  - `AppModel+MultiProject.swift`
  - narrow `SupervisorManager.swift` call sites
- goal:
  - 完成 `A4`
- avoid:
  - route truth / voice / dashboard

### Lane 4: Reply Contract + Regression Tests

- own:
  - `SupervisorProjectActionResult.swift`
  - `SupervisorCommandGuardTests.swift`
  - `SupervisorProjectTransactionRepairTests.swift`
- goal:
  - 完成 `A5` + `A6`
- avoid:
  - 底层 project materialization 大改

如果并行时担心 `SupervisorManager.swift` 冲突，优先顺序改为：

1. Lane 1 先落纯 resolver 类型和接口
2. Lane 3 单独补 AppModel helper
3. Lane 4 先写 failing tests
4. Lane 2 最后串接主事务链

## 10) 最终验收标准

只有同时满足下面 6 条，这个包才算完成：

1. 能力/权限/诊断问句不会创建项目。
2. 用户显式项目名覆盖旧推断名。
3. create 变成可追踪事务，不再是隐式文案动作。
4. 最近一次 create 后，rename/delete/undo 能自然语言纠错。
5. 对副作用请求不再出现 fake acknowledgement。
6. “坦克大战”事故脚本被 automated tests 固化。

## 11) 给下一位 AI 的接手提示

把下面这段直接给下一位 AI：

```text
你在接 XT-W3-42：Supervisor Project Intent And Transaction Repair。

先读：
1. X_MEMORY.md
2. docs/WORKING_INDEX.md
3. x-terminal/work-orders/README.md
4. x-terminal/work-orders/xt-w3-42-supervisor-project-intent-and-transaction-repair-implementation-pack-v1.md

固定原则：
- 先理解项目动作意图，再决定是否执行
- question > side effect
- 用户显式项目名覆盖默认推断名
- create 必须进入 transaction state
- create 后必须打开 correction window
- create / rename / delete / undo 禁止 fake acknowledgement
- rename v1 只改 displayName，不搬根目录

优先实现：
1. Project action intent resolver
2. Create transaction gate
3. Correction window
4. Rename / delete / undo executors
5. Regression tests

最低要覆盖的真实事故：
- “你诚实说，你现在有权限或能力建一个project了吗？” 不能触发 create
- “我要建的project名叫坦克大战” 必须覆盖默认名
- “前面建错的project你删掉吧” 必须真执行 delete/undo 或真失败
- “把前面的项目名称改成坦克大战也可以” 必须真 rename 或真失败
```
