# X-Hub Coding Mode Fit + Governed Engineering Work Orders v1

- Status: Active
- Updated: 2026-04-02
- Owner: Product / XT-L2 / Hub-L5 / Supervisor / Runtime / Memory / QA / Bench
- Purpose: 把 `xhub-coding-mode-fit-and-governed-engineering-strategy-v1.md` 的判断压成一份可以直接接手、直接拆分、直接验证的正式工单包，避免后续 AI 再回到“到底是 Vibe、BMAD 还是 Agentic”这种抽象讨论。
- Depends on:
  - `docs/memory-new/xhub-coding-mode-fit-and-governed-engineering-strategy-v1.md`
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `docs/memory-new/xhub-la-runtime-handoff-guide-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-a-tier-execution-graduation-work-orders-v1.md`
  - `docs/memory-new/xhub-heartbeat-and-review-evolution-work-orders-v1.md`
  - `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
  - `docs/memory-new/xhub-skill-capability-profiles-and-execution-readiness-contract-v1.md`
  - `docs/memory-new/xhub-product-experience-leapfrog-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`

## 0) How To Use This Pack

如果你是新接手的 AI 或维护者，固定按这个顺序进入：

1. 先读 `README.md`
2. 再读 `X_MEMORY.md`
3. 再读 `docs/WORKING_INDEX.md`
4. 再读 `docs/memory-new/xhub-coding-mode-fit-and-governed-engineering-strategy-v1.md`
5. 再读 `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
6. 再读本文件

固定规则：

- 策略判断以 strategy doc 为准，本文件负责把它拆成可执行工单。
- 不允许把 `A-Tier / S-Tier / Heartbeat / Review / Memory depth` 重新塌回一个模糊开关。
- 不允许为了“看起来像主流 coding agent”而弱化 Hub-first trust、grant、audit、kill-switch。
- 不允许把 `Project Coder` 做成只会等“继续”的被动聊天体。
- 不允许把 `Supervisor` 做回每一步都同步审批的门神。

## 1) Frozen Decisions

### 1.1 System identity is frozen

X-Hub coding 主路线冻结为：

`Harness Engineering base -> Agentic Engineering project flow -> Ralph loop as Project Coder kernel -> SDD for high-risk boundary -> Vibe for spikes only -> Light BMAD for inception only`

### 1.2 A/S axes are not optional add-ons

coding 模式不能脱离治理表面单独谈。

必须继续映射到：

- `A-Tier`
  - 决定执行权和 side effect 边界
- `S-Tier`
  - 决定 Supervisor review 深度和介入强度
- `Heartbeat / Review`
  - 决定 cadence、safe point、review trigger、digest，不与 `A/S` 合并

### 1.3 Memory split is part of coding quality

固定：

- `Supervisor` 默认看得更深、更广、更跨域
- `Project Coder` 默认只看 project-relevant continuity、step context、evidence、guidance、blocker

冻结原则：

`更强的 coding agent != 一次塞给模型更多上下文`

### 1.4 `A4 Agent` is highest governed coding lane

固定：

- `A4 Agent` 就是现有 `A0..A4` 中的最高 A-Tier
- 它不是不受治理的“全自动 root 模式”
- 它仍然必须受 capability bundle、grant、TTL、audit、kill-switch、safe-point guidance 约束

### 1.5 Engineering order is fixed

coding 主链工程顺序冻结为：

1. 先做 `runtime template freeze`
2. 再收 `Project Coder continuous loop`
3. 再收 `verification-first contract`
4. 再收 `scene-based parameter matrix`
5. 最后把 `A4 high-governance lane` 与 runtime readiness 真正闭环

并行线允许做，但不得替代上述主链：

- benchmark/scoring
- symbol/LSP deep retrieval
- prototype lane
- inception lane

## 2) Scenario Matrix

### 2.1 Scenario -> Mode -> A/S Mapping

| 场景 | 推荐模式 | A-Tier | S-Tier | 说明 |
| --- | --- | --- | --- | --- |
| `快速原型 / 小 demo` | `Vibe + 轻 Ralph` | `A1 / A2` | `S1` | 快速出结果，不要过重；默认不进高风险 delivery 面 |
| `单功能开发 / 中型 feature` | `Agentic + Ralph + 轻 SDD` | `A2 / A3` | `S2` | 默认主力模式；有 plan、有 verify、有 blocker |
| `中大型项目持续推进` | `Harness + Agentic + Ralph + SDD` | `A3` | `S2 / S3` | 最适合 X-Hub；强调 continuity、checkpoint、review、recovery |
| `高风险自动执行` | `Harness + Agentic + 强 SDD` | `A4` | `S3` | 只有 `A4 runtime ready` 时才应开放 |
| `从零到一新产品` | `轻 BMAD + Agentic + SDD` | `A1 -> A2 -> A3` | `S2 / S3` | 先产出 goal/scope/constraints/work orders，再切到执行主链 |

### 2.2 Scene -> Operating Defaults To Freeze

这张表不是最后的唯一参数值，而是后续 runtime template 应先冻结的默认起点。

| 场景 | Heartbeat / Review 默认 | 连续性底线 | capability 起点 | pre-done / closeout |
| --- | --- | --- | --- | --- |
| `快速原型 / 小 demo` | `milestone heartbeat`，必要时加轻量 safety pulse | `Supervisor >= 8 recent raw turns`；`Coder >= 6 project turns` | `plan + repo.basic`，默认不放 device/browser side effect | `recommended`，可快速 demo 收口 |
| `单功能开发 / 中型 feature` | `heartbeat 600s`，`pulse review 1200s` | `Supervisor >= 8 recent raw turns`；`Coder >= 8 project turns` | `repo.write + build + test + patch + evidence` | `A3` 时 `required` |
| `中大型项目持续推进` | `heartbeat 300-600s`，`pulse review 900s`，事件触发 review 开启 | `Supervisor >= 12 recent raw turns`；`Coder >= 8-12 focused turns` | `repo.full + governed skills + checkpoint/recovery` | `required`，且必须有 delivery summary |
| `高风险自动执行` | `heartbeat 180-300s`，`pulse review 600-900s`，`pre-high-risk` review 必开 | `Supervisor >= 12 recent raw turns + deeper project brief`；`Coder >= 8-12 focused turns` | `A4 governed capability bundle only`，不允许未就绪 runtime 假放开 | `mandatory`，且必须有 audit-ready evidence |
| `从零到一新产品` | `milestone heartbeat`，`planning pulse review` 偏重 | `Supervisor >= 12 recent raw turns + portfolio/project memory`；`Coder` 先停在 `A1` | `plan/write-memory/docs/work-order generation` | `spec/work-order review required`，之后再进 `A2` |

## 3) Delivery Order And Parallelization

### 3.1 Critical path

建议固定按这个顺序推进：

1. `CM-W1`
   - 先把场景模板和模式映射冻结到 machine-readable truth
2. `CM-W2`
   - 再把 `Project Coder` 真正推进到强 `Ralph loop`
3. `CM-W3`
   - 再把 `verification-first` 合同打进执行主链
4. `CM-W9`
   - 再把 heartbeat/review/continuity/capability/pre-done 参数矩阵收口
5. `CM-W8`
   - 最后把高治理 coding lane 与 `A4 runtime ready` 真正耦合

### 3.2 Parallel lanes

以下可并行做，但不要阻塞主链：

- `CM-W4`
  - benchmark / scoring spine
- `CM-W5`
  - symbol graph / LSP deep retrieval
- `CM-W6`
  - prototype lane productization
- `CM-W7`
  - inception lane / light BMAD outputs

## 4) Shared Constraints

所有子工单都必须遵守：

- `Hub` 继续是 runtime truth、grant、policy、audit、kill-switch 的主权端。
- `Project Coder` 可以持续执行，但不能扩大自己的权限边界。
- `Supervisor` 可以战略纠偏，但不能重新变成每一步都同步审批。
- `safe-point guidance + guidance ack` 继续保留，不得退回非结构化聊天。
- `Memory` 连续性增强必须保持 role-aware split，不得把 Supervisor 和 Project Coder 的上下文装配重新做成一锅粥。
- `Vibe` 只能是 lane，不得成为系统默认主模式。
- `BMAD` 只能是前置收敛方式，不得成为长期 runtime 行为。
- `SDD` 只用于高风险/跨边界/共享 contract，不得把所有小改动都 spec 化。

## 5) Work Orders

### CM-W1 Coding Mode Matrix -> Runtime Template Freeze

- Progress update:
  - 2026-03-31: 主干代码已开始落地。
  - 已把 `AXProjectGovernanceTemplate` 从旧 `conservative / safe / agent` 三模板升级成 `prototype / feature / large_project / high_governance / inception` 五模板，并保留 hidden `legacyObserve` 兜住旧 `A0/S0` 默认项目。
  - 已把模板默认值扩成 machine-readable truth：`A-Tier / S-Tier / Heartbeat / Review / projectRecentDialogueProfile / projectContextDepthProfile / runtime surface posture`。
  - 已同步切换这些 UI 面：`CreateProjectSheet.swift`、`ProjectSettingsView.swift`、`ProjectDetailView.swift`。
  - 已把新建项目链路接上 `Project Context` 连续性字段写入，避免 scene template 只改 UI、不改 project config。
  - 已开始把 `Supervisor intake / quick access` 接到同一 scene-template 语言：大任务入口会给出默认 lane 提示，并把 `scene_template` 线索写进 one-shot intake prompt / cockpit 默认草稿。
  - 已开始更新相关测试：`AXProjectGovernanceTemplateTests.swift`、`ProjectModelGovernanceBindingTests.swift`、`AppModelMultiProjectGovernanceTests.swift`、`SupervisorPortfolioProjectPresentationTests.swift`。
  - 2026-03-31 晚些时候已继续收口验证尾巴：补齐了 `AppModelMultiProjectGovernanceTests.swift` 和 `SupervisorProjectDrillDownTests.swift` 的兼容性编译断点，避免过滤测试时仍被无关测试文件卡死。
  - 已完成 scene-template 文案扫尾：`ProjectGovernanceBadge.swift`、`XTGovernanceTruthPresentation.swift`、`AXProjectGovernanceTemplate.swift` 的默认来源/收束摘要已从旧“保守基线”表述切成“默认 Observe 起步 / fail-closed 收束回到 Observe 基线”，减少旧三模板语义继续泄漏到治理摘要面。
  - 2026-03-31 当前已通过的定向验证：
    - `swift test --filter SupervisorBigTaskAssistTests`
    - `swift test --filter SupervisorViewActionSupportTests`
    - `swift test --filter SupervisorCockpitActionResolverTests`
    - `swift test --filter AXProjectGovernanceTemplateTests`
    - `swift test --filter ProjectGovernancePresentationSummaryTests`
    - `swift test --filter XTGovernanceTruthPresentationTests`
  - 当前剩余尾巴：
    - 继续做一次 UI smoke，把新建项目 / 项目设置 / 项目详情 / Supervisor intake 的 scene-template 文案和切换路径截图固化到 evidence
- Goal:
  - 把 `prototype / feature / large_project / high_governance / inception` 五种 coding scene 冻结成 machine-readable runtime templates，并挂进项目创建、治理设置、Supervisor intake 的同一真相面。
- Primary landing files / surfaces:
  - `docs/memory-new/xhub-coding-mode-fit-and-governed-engineering-strategy-v1.md`
  - `x-terminal/Sources/Project/AXProjectGovernanceTemplate.swift`
  - `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`
  - `x-terminal/Sources/UI/Projects/CreateProjectSheet.swift`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Sources/UI/Projects/ProjectDetailView.swift`
  - `x-terminal/Sources/UI/ProjectGovernanceEditorPresentation.swift`
- Dependencies:
  - `xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
- Deliverables:
  - 明确 template id、用户可见 label、默认 `A-Tier / S-Tier / heartbeat-review / memory continuity / capability profile`
  - `Create Project` 时可选 scene template，且不会重新塌回旧 `autonomy` 混合表面
  - `Project Settings` / `Project Detail` / governance quick access 显示统一模板说明
  - docs-truth 说明“场景模板是对三轴治理的快捷预设，而不是新的第 4 个拨盘”
- Done when:
  - 新建项目时，用户可以先选 scene template，再按需细调 `A / S / Heartbeat`
  - 模板切换不会覆盖用户后续单独编辑过的三轴配置，除非明确执行 reset/apply-template
  - `Supervisor` intake 可以用同一模板语言解释“为什么这个项目默认是 A2/S2，而不是 A4/S3”
- Validation / evidence:
  - `swift test --filter 'AXProjectGovernanceTemplateTests|CreateProjectGovernanceTransitionTests|ProjectSettingsGovernanceUITests|ProjectGovernanceDocsTruthSyncTests'`
  - UI smoke：新建项目、切换模板、进入治理三页、验证 explainability
- Avoid / non-goals:
  - 不要再造第二套 `mode` 与 `A/S` 组合配置系统
  - 不要让模板覆盖 Hub truth 或绕过 `A0..A4 / S0..S4` contract

### CM-W2 Project Coder Strong Ralph Loop Closure

- Progress update:
  - 2026-03-31: 已先落一刀 step-aware checkpoint，把 `XTAutomationRunCheckpoint` 从只知道 run-level `queued/running/blocked/...`，扩成还能携带 `current_step_id / current_step_title / current_step_state / current_step_summary`。
  - `XTAutomationRunCheckpointStore.swift` 现在会在没有显式 step-state 时，按 run-state 自动推导 `pending / in_progress / retry_wait / done`，并在 blocked/retry/delivered 之间保留同一 step identity，避免恢复时只剩“run blocked”这种粗粒度状态。
  - `XTAutomationRunCoordinator.swift` 与 `XTAutomationRuntimePersistence.swift` 已同步持久化/回放这些 step 字段；raw log checkpoint 现在可以作为真正的恢复点携带“卡在哪一步、是在执行还是等待重试”的 truth。
  - `SupervisorAutomationRuntimePresentation.swift` 已开始展示 step-aware checkpoint：runtime 面板除了 run checkpoint，还会单独显示“当前步骤：标题 / 状态 / 摘要”。
  - `AXProjectResumeBriefBuilder.swift` 已接入最新 automation checkpoint，项目接续摘要现在可以直接说出当前 automation 停在哪个 step、是不是等待重试，而不是只剩宽泛的当前状态。
  - 2026-03-31: executor 侧已继续收口 step truth，`XTAutomationRunExecutor.swift` 现在会把 action failure / verification failure / delivered completion 的当前步骤写进 completed execution row 与 handoff artifact；`XTAutomationRuntimePersistence.swift` 的 checkpoint reconstruction 也会重放 step context，不再在跨实例 recovery 后退化成只有 run-level state。
  - 2026-03-31: 已把 structured blocker / retry truth 正式打进 runtime artifacts。`XTAutomationRunExecutor.swift`、`XTAutomationRetryPackage.swift`、`XTAutomationRuntimePersistence.swift`、`SupervisorManager.swift` 现在会共同产出并保留 `XTAutomationBlockerDescriptor` 与 `XTAutomationRetryReasonDescriptor`，字段覆盖 `code / summary / stage / detail / next_safe_action / retry_eligible / current_step_*` 与 `category / strategy / planning_mode / blocker_code / current_step_*`，不再只剩自由文本或 UI 二次猜测。
  - 2026-03-31: 项目治理活动页已接上 automation runtime 真相。`ProjectGovernanceActivityView.swift` 新增 `最新自动推进 / 最近自动推进`，数据源来自 runtime raw log 与 persisted checkpoint/report/retry package，可直接显示当前 step、blocker、retry reason、handoff、recovery，而不再只看到 review / guidance。
  - 2026-03-31: 已完成一轮干净隔离验证，`XTAutomationRuntimePersistenceTests`、`ProjectGovernanceActivityPresentationTests`、`SupervisorAutomationRuntimePresentationTests`、`XTAutomationRunExecutorTests`、`XTAutomationRunCoordinatorTests` 共 `71` 个测试全部通过。
  - 2026-03-31 当前已通过的定向验证：
    - `swift test --filter XTAutomationRunCheckpointStoreTests`
    - `swift test --filter XTAutomationRunExecutorTests`
    - `swift test --filter XTAutomationRuntimePersistenceTests`
    - `swift test --filter SupervisorAutomationRuntimePresentationTests`
    - `swift test --filter AXProjectResumeBriefBuilderTests`
    - `swift test --filter XTAutomationRunCoordinatorTests`
- Goal:
  - 把 `Project Coder` 从“会执行一些步骤”推进到“默认按 `choose next step -> execute -> verify -> evidence -> continue / retry / block / done` 持续循环”的强执行内核。
- Primary landing files / surfaces:
  - `x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRunCheckpointStore.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRunExecutor.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRetryPackage.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRuntimePersistence.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorAutomationRuntimePresentation.swift`
  - `x-terminal/Sources/Project/AXProjectResumeBriefBuilder.swift`
  - `x-terminal/Sources/UI/ProjectGovernanceActivityView.swift`
- Dependencies:
  - `xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
- Deliverables:
  - step-level state machine：`pending / in_progress / verifying / blocked / retry_wait / done`
  - 有界重试预算和 retry reason 结构
  - checkpoint / resume 从“有存储”升级成“有明确恢复点和 next-step truth”
  - blocker 标准化，不再只留自由文本
  - 项目时间线和 activity 视图能看懂当前执行到了哪一步
- Done when:
  - `A2/A3` 项目不再靠用户反复说“继续”才能推进
  - step 失败时会先走 bounded retry，再进入 structured blocker，而不是静默停住
  - resume 后能恢复到 step 边界，而不是重新从模糊聊天上下文猜下一步
- Validation / evidence:
  - `swift test --filter 'XTAutomationRunExecutorTests|XTAutomationRunCheckpointStoreTests|XTAutomationRunCoordinatorTests|XTAutomationRuntimePersistenceTests|SupervisorAutomationRuntimePresentationTests|ProjectGovernanceActivityPresentationTests|SupervisorAutomationProductGapClosureTests|ProjectCoderExecutionStatusPresentationTests|SupervisorManagerAutomationRuntimeTests'`
  - evidence：生成一份 run timeline，至少包含 step 进入、verify、retry、block、resume
- Avoid / non-goals:
  - 不要做无限循环
  - 不要做 prompt-only “继续干下去” 伪循环
  - 不要让 `Project Coder` 绕过 grant / route / policy 边界

### CM-W3 Verification-First Step Contract

- Progress update:
  - 2026-03-31: `ProjectGovernanceActivityView.swift` 已开始把 verification truth 直接投影到治理活动页。`最新自动推进 / 最近自动推进` 现在会显示 `automation_verification`，区分 `验证通过 / 验证失败 / 未执行 / 未要求`，不再只能从 blocker 或 retry 文案间接猜测 verify 状态。
  - 2026-03-31: `ProjectGovernanceActivityPresentationTests.swift` 已补 execution row + standalone `automation_verification` event 覆盖，验证 execution/retry/event timeline 三处都能保留 verify 结果。
  - 2026-03-31: 已顺手修复一处无关但会卡住全量测试编译的基线问题：`XTUnifiedDoctorReportTests.swift` 中缺失 `throws` 的测试签名，避免后续 `swift test` 在进入所选 suite 前就因无关文件失败。
  - 2026-04-01: `XTAutomationVerificationContract` 已正式进入 runtime artifact / raw log / persistence / presentation 主链。`XTAutomationRunExecutor.swift` 会写出 machine-readable `verification_contract`；`XTAutomationRuntimePersistence.swift` 能回放；`SupervisorAutomationRuntimePresentation.swift` 会显示“验证合同”行，而不再只剩自由文本结果。
  - 2026-04-01: `AXAutomationRecipeAction.swift` 已从旧 `requires_verification` 布尔位升级到兼容旧字段的 `verification_contract` authoring spec。recipe action 现在可在上游显式携带 `expected_state / verify_method / retry_policy / hold_policy / evidence_required / verify_commands` 这套 vocabulary，同时继续兼容历史 recipe JSON。
  - 2026-04-01: `XTAutomationRunExecutor.swift` 已改成优先消费 action-scoped verification contract，再与 project verify defaults 合并成 run-level contract；因此 action graph 不再把验证语义丢到执行前现推，`recipe_action_verify_commands / mixed_verify_commands` 也已进入 runtime explainability。
  - 2026-04-01: 为了让完整编译链恢复可跑，已顺手修复 `XTAutomationRuntimePersistence.swift` 中悬空的 execution report helper 引用，改回现有 `xtAutomationLoadExecutionReport(...)` 真入口。
  - 2026-04-01: planning/prompt/materialize 主链已继续收口。`SplitProposalEngine.swift` 现在会给每条 lane 生成结构化 `verificationContract`；`PromptFactory.swift` 会把它编译进 `[Verification Contract]`；`ProjectMaterializer.swift` 会把 `verification_expected_state / verification_method / verification_retry_policy / verification_hold_policy / verification_evidence_required / verification_checklist` 写入并回读 task metadata。
  - 2026-04-01: retry/recovery 主链已继续接上同一份 machine-readable truth。`XTAutomationRetryPackage.swift`、`XTAutomationRuntimePatchOverlay.swift`、`SupervisorManager.swift`、`XTAutomationRuntimePersistence.swift` 现在会在保留旧 `revised/proposedVerifyCommands` 兼容的同时，额外携带 `revised/proposedVerificationContract`；retry overlay 也新增 `verification_contract`，恢复链路优先吃结构化合同再回退到命令数组。
  - 2026-04-01: `XTAutomationRunExecutor.swift` 已支持 `verificationContractOverride`，因此 retry / recover / self-iterate 不再只能靠 verify command 列表重建验证语义；`SupervisorAutomationRuntimePresentation.swift` 与 `/automation status` 也会显示 retry verification contract 的关键 truth。
  - 2026-04-01: governance activity / timeline 也已切到同一份结构化 truth。`ProjectGovernanceActivityView.swift` 现在会在 `最新自动推进 / 最近自动推进` 中单独显示 `验证合同` 与 `重试验证合同`；`SupervisorManager.swift` 写 retry raw log 时也会补上 `revised_verification_contract`，`XTAutomationRuntimePersistence.swift` 则支持在没有 planning/proposal artifact 时直接从 raw log 回放 revised contract，避免 activity timeline 退化回旧 verify 文本。
  - 2026-04-01: Doctor / diagnostics 也已接上同一份结构化合同真值。`ChatSessionModel.swift` 会把 `project_memory_automation_verification_contract / project_memory_automation_retry_verification_contract` 写进 project memory usage；`AXProjectContextAssemblyDiagnostics.swift` 会把两份合同投影成 machine-readable detail lines；`XHubDoctorOutput.swift` 与 `XTUnifiedDoctor.swift` 现在都能展示并导出 `验证合同 / 重试验证合同`，而不再只剩 `verification_present=true` 这类粗粒度布尔位。
  - 2026-04-01: persistence 真相链又补了一刀。`XTAutomationRuntimePersistence.swift` 现在会在“retry package 已准备、但 retry run 尚未真正启动”时，把 continuity 的 `effective_run / delivery_closure_source` 解析到 `retry_package`，避免 Project Coder 继续盯着旧 source run；同时 execution row 只带 verify 摘要时，也会继续从 handoff artifact 合并回结构化 `verification_contract`，不再把合同静默丢掉。
  - 2026-04-01: `SupervisorManagerAutomationRuntimeTests.swift` 的 continuity 回归缺口已补齐验证。`automationStatusContinuityDoesNotReuseSourceExecutionWhenRetryChildIsQueued` 已确认在“retry child 已排队、但尚未真正起跑”时，不会回退复用 source execution truth。
  - 2026-04-01 当前已通过的定向验证：
    - `swift test --filter 'AXProjectConfigAutomationRecipeTests|XTAutomationRunExecutorTests|XTAutomationRuntimePersistenceTests|SupervisorAutomationRuntimePresentationTests'`
    - 结果：`58` tests in `4` suites passed
    - `swift test --filter 'LaneAllocatorRouteTruthTests|SupervisorMultilaneFlowTests|SupervisorProposalPromptTests|AXProjectConfigAutomationRecipeTests|XTAutomationRunExecutorTests|XTAutomationRuntimePersistenceTests|SupervisorAutomationRuntimePresentationTests'`
    - 结果：`92` tests in `9` suites passed
    - `swift test --filter 'SupervisorManagerAutomationRuntimeTests|XTAutomationRuntimePersistenceTests|SupervisorAutomationRuntimePresentationTests|XTAutomationRunExecutorTests'`
    - 结果：`123` tests in `4` suites passed
    - 在隔离副本 `/tmp/xt_verify_contract` 中运行：`swift test --filter 'ProjectGovernanceActivityPresentationTests|XTAutomationRuntimePersistenceTests|SupervisorAutomationRuntimePresentationTests|XTAutomationRunExecutorTests'`
    - 结果：`57` tests in `4` suites passed
    - 在隔离副本 `/tmp/xt_verify_contract` 中运行：`swift test --build-path /tmp/xt_verify_contract_build --skip-build --filter projectsProjectAutomationContinuitySnapshotFromRecoveryAwareDetailLines`
    - 结果：`1` test in `1` suite passed
    - 在隔离副本 `/tmp/xt_verify_contract` 中运行：`swift test --build-path /tmp/xt_verify_contract_build --skip-build --filter summarizesProjectAutomationVerificationContractsForDoctorCard`
    - 结果：`1` test in `1` suite passed
    - 在隔离副本 `/tmp/xt_verify_contract` 中运行：`swift test --build-path /tmp/xt_verify_contract_build --skip-build --filter doctorSummaryCarriesAutomationContinuityFieldsFromRuntimeUsage`
    - 结果：`1` test in `1` suite passed
    - 主仓运行：`swift test --package-path x-terminal --filter latestProjectContinuitySnapshotPrefersPreparedRetryChildBeforeRetryRunStarts`
    - 结果：`1` test in `1` suite passed
    - 主仓运行：`swift test --package-path x-terminal --skip-build --filter loadExecutionReportPreservesVerificationContractFromHandoffArtifactWhenRowOnlyHasSummary`
    - 结果：`1` test in `1` suite passed
    - 主仓运行：`swift test --package-path x-terminal --skip-build --filter projectMemoryUsageFieldsExposeAutomationContinuityExecutionState`
    - 结果：`1` test in `1` suite passed
    - 主仓运行：`swift test --package-path x-terminal --skip-build --filter doctorSummaryCarriesAutomationContinuityFieldsFromRuntimeUsage`
    - 结果：`1` test in `1` suite passed
    - 主仓运行：`swift test --package-path x-terminal --skip-build --filter projectsProjectAutomationContinuitySnapshotFromRecoveryAwareDetailLines`
    - 结果：`1` test in `1` suite passed
    - 主仓运行：`swift test --package-path x-terminal --skip-build --filter summarizesProjectAutomationVerificationContractsForDoctorCard`
    - 结果：`1` test in `1` suite passed
    - 主仓运行：`swift test --package-path x-terminal --skip-build --filter XTAutomationRunExecutorTests`
    - 结果：`17` tests in `1` suite passed
    - 主仓运行：`swift test --package-path x-terminal --skip-build --filter ProjectGovernanceActivityPresentationTests`
    - 结果：`10` tests in `1` suite passed
    - 主仓运行：`swift test --package-path x-terminal --skip-build --filter SupervisorSystemPromptBuilderTests`
    - 结果：`15` tests in `1` suite passed
    - 主仓运行：`swift test --package-path x-terminal --skip-build --filter 'automationRecoverSchedulesRetryRunFromVerificationHandoff|automationStatusHydratesExecutionAndRetryFromDiskAfterRestart|retryPackageHydratesRecipeProposalArtifactWithoutPlanningArtifact'`
    - 结果：`3` tests in `1` suite passed
    - 主仓运行：`swift test --package-path x-terminal --skip-build --filter 'XTerminalTests\.SupervisorManagerAutomationRuntimeTests/automationStatusContinuityDoesNotReuseSourceExecutionWhenRetryChildIsQueued'`
    - 结果：`1` test in `1` suite passed
    - 主仓运行：`node x-hub/grpc-server/hub_grpc_server/src/local_task_policy.test.js`
    - 结果：`3` policy checks passed
- Goal:
  - 让 coding step 的完成条件从“工具返回成功”升级成“目标状态 + verify predicate + failure policy + retry budget”的正式合同。
- Primary landing files / surfaces:
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `x-terminal/Sources/Supervisor/PromptContract.swift`
  - `x-terminal/Sources/Supervisor/SupervisorSystemPromptBuilder.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRetryPackage.swift`
  - `x-terminal/Sources/Project/AXProjectResumeBriefBuilder.swift`
  - `x-terminal/Sources/UI/ProjectGovernanceActivityView.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/local_task_policy.js`
- Dependencies:
  - `CM-W2`
  - `xhub-a-tier-execution-graduation-work-orders-v1.md`
- Deliverables:
  - step contract 结构：`expected_state / verify_method / retry_policy / hold_policy / evidence_required`
  - plan/upsert/job generation 时默认带 verify thinking，不再只是 action list
  - `pre-done` 判断和 ordinary step verify 走同一 contract vocabulary
  - doctor / activity presentation 至少能显示 verify failure 的原因分类
- Done when:
  - step 完成不再只看 shell exit code 或模型自述
  - `done` 结论默认要求对应 evidence 或 verify result
  - blocker / retry / hold 能明确指出是 action failed、verify failed 还是 policy hold
- Validation / evidence:
  - `swift test --filter 'XTAutomationRunExecutorTests|SupervisorManagerAutomationRuntimeTests|ProjectGovernanceActivityPresentationTests|SupervisorSystemPromptBuilderTests'`
  - `node x-hub/grpc-server/hub_grpc_server/src/local_task_policy.test.js`
- Avoid / non-goals:
  - 不要把所有 verify 都做成昂贵的 full regression
  - 不要让 verify contract 只存在 prompt 文本里，没有 machine-readable 结构

### CM-W4 Coding Benchmark And Scoring Spine

- Goal:
  - 给这套 governed coding system 建一条稳定 benchmark spine，不再只靠“感觉上更会写代码了”来判断进展。
- Primary landing files / surfaces:
  - `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
  - `docs/repo-inventory/FEATURE_VALIDATION_CHECKLIST.md`
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-terminal/Sources/UI/XHubDoctorOutput.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_audit_events.js`
  - `x-terminal/Tests/`
- Dependencies:
  - `CM-W2`
  - `CM-W3`
- Deliverables:
  - coding benchmark task family：
    - single-file patch
    - cross-file refactor
    - failing-test repair
    - governed high-risk change
    - interruption + resume
  - score dimensions：
    - first-pass success
    - regression escape
    - verify discipline
    - blocker quality
    - checkpoint/resume success
    - unsafe action count
  - 至少一份 machine-readable result snapshot，供 doc/release 使用
- Done when:
  - 新能力上线后可以回放同一组任务进行前后对比
  - benchmark 能反映 governance、resume、verify，而不是只测“写代码速度”
  - doctor / evidence 可以输出最近一次 benchmark 结果摘要
- Validation / evidence:
  - 文档化 benchmark protocol
  - 最少一轮 baseline capture
  - 如补了机读 contract，同步补 docs-truth 或 report contract 测试
- Avoid / non-goals:
  - 不要只做模型排行榜
  - 不要把 benchmark 退化成纯 UI screenshot 或单一 happy-path demo

### CM-W5 Symbol Graph / LSP Deep Retrieval

- Goal:
  - 提高跨文件修改和深代码库修改的正确率，让 `Project Coder` 在需要时能拿到 symbol-aware 或 LSP-aware 的深检索结果，而不是只靠关键词上下文。
- Primary landing files / surfaces:
  - `x-terminal/Sources/Project/AXProjectContext.swift`
  - `x-terminal/Sources/Project/AXProjectContextAssemblyDiagnostics.swift`
  - `x-terminal/Sources/Project/AXProjectModelRouteMemory.swift`
  - `x-terminal/Sources/Project/ProjectModelRouteTruthSupport.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.js`
- Dependencies:
  - `xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
  - `CM-W3`
- Deliverables:
  - retrieval policy：何时触发 symbol/LSP deep retrieval，何时继续用普通 working set
  - context slot：symbol graph / definition chain / caller set / impacted files
  - diagnostics：能解释这轮为什么走深检索，以及取回了哪些代码关系
  - budget 规则：深检索不能默认每轮都跑
- Done when:
  - 跨多文件修改时，`Project Coder` 默认能拿到更靠谱的 definition/reference/impact context
  - doctor / diagnostics 能说明“这轮拿到的是普通 working set 还是 symbol-aware retrieval”
  - 深检索是按需触发，而不是无脑塞更多上下文
- Validation / evidence:
  - `swift test --filter 'AXProjectContextAssemblyDiagnosticsTests|AXProjectContextAssemblyPresentationTests|AXProjectModelRouteMemoryTests|ProjectRemotePromptSanitizerTests'`
  - `node x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.test.js`
- Avoid / non-goals:
  - 不要把 deep retrieval 做成新的 durable memory truth
  - 不要为了深检索破坏 prompt export gate 或 memory governance

### CM-W6 Prototype Lane / Vibe Lane Productization

- Goal:
  - 把 `Vibe + 轻 Ralph` 做成一个明确、低摩擦但不破坏治理主链的 prototype lane。
- Primary landing files / surfaces:
  - `x-terminal/Sources/Project/AXProjectGovernanceTemplate.swift`
  - `x-terminal/Sources/UI/Projects/CreateProjectSheet.swift`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Sources/UI/ProjectGovernanceThreeAxisOverviewView.swift`
  - `x-terminal/Sources/UI/ProjectGovernanceSurfaceExplanation.swift`
  - `x-terminal/Sources/Supervisor/SupervisorTurnRouter.swift`
- Dependencies:
  - `CM-W1`
- Deliverables:
  - prototype lane 模板和说明文案
  - 明确 prototype lane 的默认边界：轻文档、轻 review、禁止默认高风险外部 side effect
  - 支持一键升级为 `feature lane`，继承已有项目上下文和计划
  - 用户可见文案要说人话，不要把内部治理术语直接甩给用户
- Done when:
  - 做小 demo / 小游戏 / UI 草图 时，用户能用一个低摩擦入口进来
  - prototype 项目后续可以升级到 `A2/A3` 正常主链，而不是重建项目
  - product surface 保持“轻”，但 runtime 仍然保留最小治理护栏
- Validation / evidence:
  - `swift test --filter 'CreateProjectGovernanceTransitionTests|ProjectSettingsGovernanceUITests|ProjectGovernanceThreeAxisOverviewPresentationTests|ProjectDetailGovernanceSummaryTests'`
  - UI smoke：创建 prototype 项目、查看模板说明、执行升级
- Avoid / non-goals:
  - 不要把 prototype lane 包装成系统默认唯一模式
  - 不要让 `Vibe` lane 默认启用 `A4`

### CM-W7 Inception Lane / Light BMAD Outputs

- Goal:
  - 把 `轻 BMAD + Agentic` 的价值收敛到前置产物层，不把长期 runtime 变成角色扮演系统。
- Primary landing files / surfaces:
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorTurnRouter.swift`
  - `x-terminal/Sources/Supervisor/SupervisorSystemPromptBuilder.swift`
  - `x-terminal/Sources/Supervisor/SupervisorProjectWorkflowCanonicalSync.swift`
  - `x-terminal/Sources/Project/AXProjectResumeBriefBuilder.swift`
- Dependencies:
  - `CM-W1`
  - `xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
- Deliverables:
  - inception 输出模板：
    - goal
    - scope
    - constraints
    - architecture notes
    - milestones
    - work orders
    - done contract
  - 完成前置收敛后，自动引导进入 `A1 Plan -> A2 Repo Auto -> A3 Deliver Auto`
  - workflow canonical memory 保留这些产物，不依赖继续角色对话才能执行
- Done when:
  - 从零到一新项目可以先稳定生成可执行产物，而不是只生成一段空泛 brainstorm
  - 收敛完成后能平滑切回正常 `Supervisor + Project Coder` 双环
  - 后续执行不再需要继续扮演 analyst/PM/architect
- Validation / evidence:
  - `swift test --filter 'SupervisorProjectWorkflowCanonicalSyncTests|SupervisorTurnRouterTests|SupervisorMemoryAwareConversationRoutingTests|SupervisorSystemPromptBuilderTests'`
  - 手工验证：从“新产品想法”起步，产出 work order，再切换到执行
- Avoid / non-goals:
  - 不要做长期 multi-persona runtime
  - 不要把 BMAD 输出和正式 project governance truth 分离成两套存储

### CM-W8 High-Governance Coding Lane / A4 Readiness Coupling

- Progress update:
  - 2026-04-02: `SupervisorAutomationRuntimeAction.swift` 已接入 `A4 runtime ready` fail-closed 行为。`SupervisorAutomationRuntimeActionResolver` 现在会把 `AXProjectGovernanceRuntimeReadinessSnapshot` 纳入 action gating；当项目配置为 `A4 Agent` 但 `runtime ready` 仍未完成时，`start / recover / advance` 会直接收束为 disabled，而 `cancel / status` 继续保留，避免高治理 lane 在未 ready 时黑箱继续推进。
  - 2026-04-02: `SupervisorAutomationRuntimePresentation.swift` 与 `SupervisorViewRuntimePresentationSupport.swift` 已把同一份 runtime readiness 真相带进 Supervisor 自动化执行面。面板现在会直接显示 `A4 Agent 已配置，但 runtime ready 还没完成。` 与 `缺口：...`，同时 guidance contract 会把这类场景识别成 runtime hold，而不是误判成“没有 recipe”或普通 blocked run。
  - 2026-04-02: `SupervisorAutomationRuntimeBoardSection.swift` 已把 action help text 改成来自 resolver 的真因说明，因此按钮灰掉时不再只是无提示；hover 会直接解释当前是 `A4 runtime ready` 缺口、缺 recipe，还是缺 last launch ref。
  - 2026-04-02: `AXProjectGovernanceBundle.swift` 已把 `A4 runtime ready` 从单个 blocked/ready 状态扩成五维 readiness component truth：`route ready`、`capability ready`、`grant ready`、`checkpoint/recovery ready`、`evidence/export ready`。其中此前占位的 `checkpoint/recovery` 与 `evidence/export` 已接上真实治理预算判定，不再停留在 `not_reported`。
  - 2026-04-02: `XTToolRuntimePolicy.swift` 已把同一份 readiness component truth 写进 tool deny summary / governance evidence；`HubModelRoutingTruthBuilder.swift`、`ModelSettingsRouteTruthPresentation.swift` 以及项目 / Supervisor 模型设置入口也开始显示 `A4 Runtime Ready`、五维矩阵与当前缺口，因此 Doctor、route truth、tool deny 不再各说各话。
  - 2026-04-02: Hub 侧 `services.js` 与 `local_task_policy.js` 已开始原生生成同一套五维 `governance_runtime_readiness` 证据。paired terminal 的 `Generate` deny/audit 现在会把 blocker 明确挂到 `route / capability / grant / checkpoint_recovery / evidence_export` 之一，`legacy_grant_flow_required`、`trusted_automation_project_not_bound`、kill-switch 与本地 capability deny 不再只剩一个扁平 deny code。
  - 2026-04-02: 同一套五维 readiness 已继续接到 `ResolveSupervisorRoute`。Hub 现在会在 `supervisor.route.resolved / supervisor.route.denied` audit ext 中附带 `governance_runtime_readiness`，把 `preferred_device_offline` 归到 `route`，把 `device_permission_owner_missing` 归到 `grant`，同时保留 `capability / checkpoint_recovery / evidence_export` 的独立状态，避免 Supervisor 路由 deny 继续退化成单一 deny code。
  - 2026-04-02: `XTDoctorProjectionPresentation.swift`、`XTUnifiedDoctor.swift`、`XHubDoctorOutput.swift` 与相关测试已补齐对这套 component truth 的消费。当前定向验证在隔离副本 `/tmp/xt_cmw8_snapshot_next/x-terminal` 中通过：`HOME=/tmp/xt_cmw8_snapshot_next/home CLANG_MODULE_CACHE_PATH=/tmp/xt_cmw8_snapshot_next/module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/xt_cmw8_snapshot_next/module-cache swift test --package-path /tmp/xt_cmw8_snapshot_next/x-terminal --build-path /tmp/xt_cmw8_snapshot_next/build --filter "a4RuntimeReadinessHoldBlocksStartRecoverAndAdvanceButNotCancel|mapSurfacesA4RuntimeReadinessHoldAndDisablesExecutionAdvancers|governanceRuntimeReadinessSummaryMakesConfiguredAndRuntimeReadySplitExplicit|sessionRuntimeSectionIncludesGovernanceRuntimeReadinessWhenAvailable|mapsMachineReadableProjectAndSupervisorMemoryPoliciesFromDetailLines|prefersStructuredMemoryPolicyProjectionsOverDetailLineFallback"`；结果 `6` tests in `5` suites passed。
  - 2026-04-02: Hub deny explainability 继续收口。新增 `x-hub/grpc-server/hub_grpc_server/src/governance_runtime_readiness_projection.js`，把现有 `governance_runtime_readiness` 从只会报 `grant:trusted_automation_project_not_bound` 这类 blocker，升级成同时携带 `state / blocked_component_keys / missing_reason_codes / components_by_xt_key / summary_line` 的 XT 风格投影；`appendDeniedAudit` 与 `agent_tool_request` 的 trusted-automation deny audit 也已开始复用同一套映射，因此非 `Generate` 的 deny 面不再只能看到裸 deny code。
  - 2026-04-02: `supervisor_channel_route_facade.js` 与 `ResolveSupervisorRoute` 也已改为复用同一套 supervisor-route governance readiness helper。现在不只是 control-plane audit，连 facade 直接返回的 route 对象也会携带 `governance_runtime_readiness`；`preferred_device_offline` 会明确落到 `route_ready`，`device_permission_owner_missing` 会明确落到 `grant_ready`，因此 Supervisor 设备路由、service audit 与 A4 readiness 不再分家。
  - 2026-04-02: `supervisor_channel_session_store.js` 也已补齐同一份 readiness 证据透传。`channel.session_route.upserted` audit 的 `ext_json` 现在会在 route facade 已给出 `governance_runtime_readiness` 时一并落盘，因此 session-route 持久化链路不再把这份 A4 readiness 真相截断在 route facade 之前。
  - 2026-04-02: `supervisor_channel_route_facade.test.js` 已进一步补到集成层断言：`evaluateSupervisorChannelRouteWithStore` 产出的 `channel.session_route.upserted` audit 现在被直接校验必须带上 `governance_runtime_readiness`，因此不只是 session-store 单体，连 facade -> store -> audit 的真实链路也有证据覆盖。
  - 2026-04-02: `evaluateSupervisorChannelRouteWithStore` 返回的 persisted route 语义也已和直接 facade 路径对齐。现在即使 route 经过 `session store` 落盘再回读，返回给调用方的 `route.governance_runtime_readiness` 也不会被 `parseSessionRouteRow()` 静默吃掉，避免“有 store 时 route truth 变浅、无 store 时 route truth 完整”的行为分叉。
  - 2026-04-02: `ResolveSupervisorRoute` 的 gRPC 响应面也已补齐同一份真相。`services.js` 现在不仅在 audit ext 中写 `governance_runtime_readiness`，还会把它直接回在 response 顶层，并挂进 `route` 对象本身；这样 connector client、operator orchestrator 和其它下游消费面不必额外回看 audit 才知道当前 route 的 A4 readiness。
  - 2026-04-02: `supervisor_control_plane_service_api.test.js` 已补齐响应面断言，`channel_adapters/slack/SlackHubConnectorClient.test.js` 已补齐 connector passthrough 断言，因此当前证据已覆盖 `service response -> connector client` 这一段，而不只覆盖 Hub 内部 audit。
  - 2026-04-02: `channel_adapters/slack/SlackCommandOrchestrator.test.js` 也已补到消费层断言。当前 `Hub ResolveSupervisorRoute -> SlackHubConnectorClient -> SlackCommandOrchestrator` 这条 route 传递链会继续保留 `route.governance_runtime_readiness`，因此 command dispatch 层后续如果要做 route-aware repair hints / degraded UX，不必重新回 Hub audit 查原因。
  - 2026-04-02: operator-channel 侧的 `ResolveSupervisorChannelRoute` 也已对齐同一语义。`makeProtoSupervisorChannelRoute()` 不再裁掉 `governance_runtime_readiness`；`operator_channels_service_api.test.js` 现在直接断言 HubRuntime 路由响应里的 `route.governance_runtime_readiness`，`channel_adapters/slack/SlackHubConnectorClient.test.js` 也断言 connector client 会原样透传这份字段，因此 channel adapter 的 `gate -> route -> dispatch` 主链已经能直接消费相同的 route readiness truth。
  - 2026-04-02: XT 侧 `ResolveSupervisorRoute` 消费也已开始收口。`HubPairingCoordinator.swift` 新增远端 wrapper，会通过 paired client kit 直接复用 Hub 的 `governance_runtime_readiness_projection.js` 生成同口径 readiness；`HubIPCClient.swift` 新增 `requestSupervisorRouteDecision(...)` 与结构化 snapshot；`ChatSessionModel.swift` 的项目 `/route diagnose` 现已带出 `Hub supervisor route 真相`、deny code、audit ref、五维 readiness summary、blocked planes 和 next action，因此 XT 不再只能靠本地 route event 猜 Supervisor 路由是否 ready。
  - 2026-04-02: XT Doctor 也已接入这组 supervisor-route plane truth。`XTUnifiedDoctor.swift` 会把 `preferred_device_offline`、`preferred_device_missing`、`xt_route_ambiguous` 这类 deny 归为 `Supervisor route 还没就绪`，把 `device_permission_owner_missing` 这类治理宿主缺口归为 `Supervisor grant / governance 还没就绪`；`AXProjectGovernanceBundle.swift` 也已补齐对应的人话 reason text，避免 route diagnose / doctor / project governance 三处继续各说各话。
  - 2026-04-02: XT 侧定向验证当前以对话链路为主已通过：`swift test --filter ChatSessionModelDirectReplyTests`，其中包含 `routeDiagnoseIncludesHubSupervisorRouteTruthWhenGrantPlaneBlocked`。`XTUnifiedDoctorReportTests` 里的新断言已补上，但整组 suite 目前在运行首条测试时会触发既有 `signal 10` 级崩溃，所以剩余尾巴已经明确收敛成 `doctor suite runtime stabilization + route repair explainability`，而不是 supervisor-route truth 还没接入。
  - 2026-04-02: Hub JS 定向验证已通过：
    - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/governance_runtime_readiness_projection.test.js`
    - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/paired_terminal_policy_usage.test.js`
    - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/supervisor_channel_route_facade.test.js`
    - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/supervisor_control_plane_service_api.test.js`
    - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/supervisor_channel_session_store.test.js`
    - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/channel_adapters/slack/SlackHubConnectorClient.test.js`
    - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/channel_adapters/slack/SlackCommandOrchestrator.test.js`
    - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/operator_channels_service_api.test.js`
- Goal:
  - 把 `高风险自动执行` coding lane 真正绑定到 `A4 runtime ready`，确保高治理 coding 不是“策略上设成 A4 就算 ready”。
- Primary landing files / surfaces:
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `x-terminal/Sources/Supervisor/SupervisorSkillPreflightGate.swift`
  - `x-terminal/Sources/Hub/HubRouteStateMachine.swift`
  - `x-terminal/Sources/Project/XTRouteTruthPresentation.swift`
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/governance_runtime_readiness_projection.js`
  - `x-hub/grpc-server/hub_grpc_server/src/local_task_policy.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skill_capability_derivation.js`
  - `x-hub/grpc-server/hub_grpc_server/src/supervisor_channel_route_facade.js`
- Dependencies:
  - `CM-W2`
  - `CM-W3`
  - `CM-W9`
- Deliverables:
  - `A4 coding readiness` 一等 truth：
    - route ready
    - capability ready
    - grant ready
    - checkpoint/recovery ready
    - evidence/export ready
  - `pre-high-risk` hold / review / explanation
  - route degraded / grant missing / capability denied 时的 fail-closed 降级路径
  - doctor / user-facing explainability：为什么当前是 `A4 configured but not runtime-ready`
- Done when:
  - `A4` 项目在未满足 readiness 时会明确 hold 或降级，不会黑箱空转
  - 一旦满足 readiness，可以在治理范围内持续推进高风险 coding 任务
  - 用户、Supervisor、doctor 三者看到的是同一条 readiness 真相
- Validation / evidence:
  - `swift test --filter 'XTToolRuntimePolicyGovernanceClampTests|HubRouteStateMachineTests|XTRouteTruthPresentationTests|XTUnifiedDoctorReportTests|SupervisorAutomationRuntimeActionResolverTests'`
  - 在隔离副本 `/tmp/xt_cmw8_snapshot.8izl2J/x-terminal` 中运行：`swift test --package-path /tmp/xt_cmw8_snapshot.8izl2J/x-terminal --build-path /tmp/xt_cmw8_snapshot.8izl2J/build --filter 'SupervisorAutomationRuntimeActionResolverTests|SupervisorAutomationRuntimePresentationTests'`
  - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/governance_runtime_readiness_projection.test.js`
  - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/paired_terminal_policy_usage.test.js`
  - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/supervisor_channel_route_facade.test.js`
  - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/supervisor_channel_session_store.test.js`
  - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/supervisor_control_plane_service_api.test.js`
  - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/channel_adapters/slack/SlackHubConnectorClient.test.js`
  - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/channel_adapters/slack/SlackCommandOrchestrator.test.js`
  - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/operator_channels_service_api.test.js`
  - 前两条 Node 验证结果：`11` tests in `2` suites passed
  - `supervisor_control_plane_service_api.test.js` 结果：`15` tests passed
  - 在隔离副本 `/tmp/xt_cmw8_followup2.Xq1KOY/x-terminal` 中运行：`swift test --package-path /tmp/xt_cmw8_followup2.Xq1KOY/x-terminal --build-path /tmp/xt_cmw8_followup2.Xq1KOY/build --filter 'buildSurfacesA4RuntimeReadinessTruthForProjectScope|projectScopeTruthCarriesA4RuntimeReadinessMatrixWhenConfigured|sessionRuntimeSectionIncludesGovernanceRuntimeReadinessWhenAvailable|governanceRuntimeReadinessSummaryMakesConfiguredAndRuntimeReadySplitExplicit|explicitDualDialOpenClawGovernanceStillFailsClosedAtToolPolicy'`
  - 结果：`5` tests in `5` suites passed
  - `node x-hub/grpc-server/hub_grpc_server/src/local_task_policy.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/paired_terminal_policy_usage.test.js`
- Avoid / non-goals:
  - 不要把 `A4` 解释成 unrestricted mode
  - 不要让 XT 本地单方面判定高风险动作已 ready，而 Hub 不知情

### CM-W9 Scene-Based Default Parameter Matrix

- Progress update:
  - 2026-04-01: `AXProjectGovernanceTemplate.swift` 已补出 scene 默认参数真值辅助层。新增 `AXProjectGovernanceTemplateDefaults`、`xtGovernanceTemplateDefaults(for:)`、`xtRecommendedGovernanceTemplateDefaults(executionTier:supervisorInterventionTier:)`，把 scene default 与 A/S-tier 推荐值收口成可复用的 machine-readable 默认矩阵，而不是散落在 UI 文案里。
  - 2026-04-01: `ProjectGovernanceEditorPresentation.swift` 已新增 scene 参数矩阵 presentation。`ProjectHeartbeatReviewEditorPresentation` 现在会分开构建 cadence、coder continuity、supervisor continuity、capability/budget、closeout 五组 rows，并明确标记每项来自 `scene default / user override / runtime capability clamp / Supervisor settings + privacy clamp / S-tier trigger auto resolution`。
  - 2026-04-01: `ProjectHeartbeatReviewView.swift` 已落地 `Scene 参数矩阵` 区块，UI 直接展示 `已配置 / 建议值 / 生效值` 三列，让用户能看懂当前 heartbeat / review / continuity / capability / closeout 到底是模板建议、用户手改，还是 runtime 收束后的 effective truth。
  - 2026-04-01: `CreateProjectSheet.swift` 与 `ProjectSettingsView.swift` 已把真实 project config 与 Supervisor settings 接进同一页，包括 `supervisor recent raw profile / supervisor review memory depth / supervisor privacy mode`，因此项目连续性与 Supervisor 连续性不再被混成一个黑箱“上下文深度”。
- Goal:
  - 把 scene-based coding defaults 正式收口为 machine-readable 参数矩阵，覆盖 `heartbeat/review cadence`、`recent raw continuity floor`、`capability profile`、`retry budget`、`pre-done review` 和 `summary requirement`。
- Primary landing files / surfaces:
  - `x-terminal/Sources/Project/AXProjectGovernanceTemplate.swift`
  - `x-terminal/Sources/Project/AXProjectGovernanceSchedulingSupport.swift`
  - `x-terminal/Sources/UI/ProjectHeartbeatReviewView.swift`
  - `x-terminal/Sources/UI/ProjectGovernanceEditorPresentation.swift`
  - `x-terminal/Sources/Project/AXProjectContext.swift`
  - `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
  - `docs/memory-new/schema/xhub_project_autonomy_and_supervisor_review_contract.v1.json`
- Dependencies:
  - `CM-W1`
  - `xhub-heartbeat-and-review-evolution-work-orders-v1.md`
  - `xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
- Deliverables:
  - 参数矩阵 schema 和默认值解释
  - `configured / recommended / effective` 与 template defaults 的挂接
  - `Supervisor` continuity floor 与 `Project Coder` continuity floor 的分离配置
  - UI 中可解释“当前参数来自模板默认、用户手改、还是 runtime effective 调整”
- Done when:
  - 每个 coding scene 都有清晰默认参数，不靠 prompt 想象
  - `Heartbeat / Review` 与 `A/S` 仍保持独立，但可以被模板一键初始化
  - memory continuity floor 不会被模板、memory serving profile 或 route fallback 静默压掉
- Validation / evidence:
  - `swift test --filter 'AXProjectGovernanceTemplateTests|ProjectGovernanceResolverTests|SupervisorReviewPolicyEngineTests|AXProjectContextAssemblyPresentationTests|HeartbeatGovernanceDocsTruthSyncTests'`
  - 主仓运行：`swift test --package-path x-terminal --filter 'ProjectGovernanceEditorPresentationTests|AXProjectGovernanceTemplateTests'`
  - 结果：`18` tests in `2` suites passed
  - 独立 build-path 运行：`swift test --package-path x-hub-system/x-terminal --build-path /tmp/xt_cmw9_suite_build --filter 'ProjectGovernanceEditorPresentationTests|AXProjectGovernanceTemplateTests|CreateProjectGovernanceTransitionTests'`
  - 结果：`21` tests in `3` suites passed
  - 独立 build-path 运行：`swift test --package-path x-hub-system/x-terminal --build-path /tmp/xt_cmw9_ui_build --filter 'ProjectSettingsGovernanceUITests/resolvedHighRiskComboKeepsConfiguredGovernanceAndShowsWarning'`
  - 结果：`1` test in `1` suite passed
  - docs / contract 同步验证
- Avoid / non-goals:
  - 不要重新造一个“mode slider”
  - 不要把 scene defaults 变成不可解释的 magic numbers

## 6) Suggested Owner Split

为了方便多 AI 并行，建议这样拆：

- `CM-W1 / CM-W6 / CM-W9`
  - XT governance UI + template + presentation 线
- `CM-W2 / CM-W3`
  - XT automation runtime / Project Coder loop 线
- `CM-W5`
  - Project context assembly + Hub retrieval 线
- `CM-W8`
  - Hub policy / route truth / doctor / readiness 线
- `CM-W4`
  - QA / benchmark / release-evidence 线
- `CM-W7`
  - Supervisor planning / workflow canonical sync 线

## 7) Minimum Handoff Block For Another AI

```text
You are taking the X-Hub coding work-order slice.

Read in order:
1. README.md
2. X_MEMORY.md
3. docs/WORKING_INDEX.md
4. docs/memory-new/xhub-coding-mode-fit-and-governed-engineering-strategy-v1.md
5. docs/memory-new/xhub-coding-mode-fit-and-governed-engineering-work-orders-v1.md
6. docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md
7. docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md
8. docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md
9. docs/memory-new/xhub-heartbeat-and-review-evolution-work-orders-v1.md

Treat X-Hub as a governed coding system:
Harness base
-> Agentic project flow
-> Ralph loop as Project Coder kernel
-> SDD only for high-risk/shared-boundary work
-> Vibe only for prototype lane
-> Light BMAD only for inception outputs

Do not reopen the strategy argument.
Pick one CM-W slice.
State:
- chosen scene
- chosen mode stack
- A-tier / S-tier expectation
- target files
- validate plan
- non-goals
```
