# XT-W3-36 Project Autonomy Tier + Supervisor Intervention Implementation Pack v1

- owner: XT-L2（Primary）/ Supervisor / Hub-L5 / Security / QA / Product
- status: in_progress
- last_updated: 2026-03-20
- purpose: 把当前混合在单一 `autonomy` 语义里的“执行权限、supervisor 介入强度、progress heartbeat”三件事拆开，正式落成 `A0..A4` 执行档位、`S0..S4` 介入档位和独立 review/heartbeat 调度，使 project coder 与 supervisor 都能在更清晰、更可审计、更可迁移的治理框架下推进项目。
- depends_on:
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/schema/xhub_project_autonomy_and_supervisor_review_contract.v1.json`
  - `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-33-supervisor-decision-kernel-routing-and-memory-governance-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-35-supervisor-memory-retrieval-progressive-disclosure-implementation-pack-v1.md`
  - `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## Status Notes

- 2026-03-20:
  - `XT-W3-36` project-core 继续把 `runtimeSurface` 固化为主命名：`AXProjectExecutionTier` 新增 `defaultRuntimeSurfacePreset` / `fromRuntimeSurfaceMode(...)`，resolver 主链已改用新入口；`defaultSurfacePreset` / `fromLegacyAutonomyMode(...)` 继续保留为 compat wrapper。
  - `AXProjectConfig` 的存储字段类型与 legacy backfill helper 也已翻正到 `AXProjectRuntimeSurface*` / `fromRuntimeSurfaceMode(...)`；磁盘上仍继续使用既有 `autonomy*` key，不做 schema break。
  - `AXProjectGovernanceSurfaceExplanation` 的主签名现已改为 `AXProjectRuntimeSurfaceMode` / `AXProjectRuntimeSurfaceEffectivePolicy`，解释层与 clamp 解释不再在主入口上挂 `AXProjectAutonomy*` 类型名。
  - `AppModel.setProjectGovernance(...)` 与 `ProjectExecutionTierView` 已跟进改走 `defaultRuntimeSurfacePreset`，避免 project-core 新路径继续把 `defaultSurfacePreset` 当主 API 使用。
  - `ProjectRuntimeSurfaceCompatibilityBoundaryTests` 现已扩展到覆盖 `AppModel`、`AXProjectGovernanceBundle`、`AXProjectGovernanceResolver`、`AXProjectGovernanceSurfaceExplanation`、`AXProjectExecutionTier` 五处边界，明确锁定“`runtimeSurface` 为主、`autonomy` 只在 deprecated wrapper / legacy audit 兼容层存在”。
  - `XTW330RuntimeSurfacePolicyEvidenceTests`、`XTW330PolicyRecoveryEvidenceTests`、`XTW330BrowserRuntimeEvidenceTests`、`ToolExecutorSessionToolsTests` 这批本来就在验证 runtime-surface 主链的测试，已改走 `AXProjectRuntimeSurface*` / `settingRuntimeSurfacePolicy(...)` 主命名，不再继续用旧 compat API 制造主路径噪音。
  - 继续把剩余普通测试里的旧 setter callsite 清到 0：`XTW337BrowserUIObservationTests`、`ToolExecutorDeviceAutomationToolsTests`、`ToolExecutorGovernedReadRootsTests`、`XTToolAuthorizationTests`、`XTAutomationRunExecutorTests`、`SupervisorCommandGuardTests` 已统一改走 `settingRuntimeSurfacePolicy(...)`。
  - 本轮聚焦验证通过：
    - `swift test --filter ProjectRuntimeSurfaceCompatibilityBoundaryTests`
    - `swift test --filter ProjectGovernanceSurfaceExplanationTests`
    - `swift test --filter ProjectGovernanceResolverTests`
    - `swift test --filter ToolExecutorSessionToolsTests`
    - `swift test --filter XTW330PolicyRecoveryEvidenceTests`
    - `swift test --filter XTW330BrowserRuntimeEvidenceTests`
    - `swift test --filter XTW330RuntimeSurfacePolicyEvidenceTests`
    - `swift test --filter XTToolAuthorizationTests`
  - 说明：当前普通测试里的旧 `settingAutonomyPolicy(...)` callsite 已归零，旧 `AXProjectAutonomy*` 类型名也已从 runtime-surface 主链测试里清出；剩余 compat 语义现在主要收敛在显式边界测试与 source-string 断言中，后续如果全量编译再出现同类 warning，应优先视为新的回退信号而不是预期噪音。
- 2026-03-18:
  - `XT-W3-36-B` UI split child pack 已收口完成：project settings、project detail、create flow 三处都已切到独立 `A-Tier`、`S-Tier`、`Heartbeat / Review` 治理页面/编辑器，`A4 Agent` 命名也已对齐文档与产品面。
  - `README`、`WORKING_INDEX`、`work-orders/README` 现在都应把 `XT-W3-36-B` 视为已完成子包，而不是仍在进行中的 active child。
  - 后续继续推进 `XT-W3-36` 时，应以 parent pack 为主真相源；`XT-W3-36-B` 只作为已完成 UI split 证据与回归锚点。
  - `XT-W3-36-E/F` 新增两条回归护栏：`SupervisorGuidanceInjectionStoreTests.latestPendingAckFallsBackToOlderActionableItemWhenNewestIsDeferredOrExpired` 锁定 guidance 队列不会被“更新但不可执行”的项挡住；`SupervisorSafePointCoordinatorTests.immediateGuidanceIsVisibleBeforeBoundaryButPauseWaitsForToolResult` 锁定 immediate guidance 会立刻进入可见上下文，但 batch pause 仍要等真实工具边界。
  - `AppModel` 现在把 `ProjectModel.autonomyLevel` 影子值的透传收口成显式 helper，只在 config 仍声明 `legacyAutonomyLevel / legacyAutonomyMode` compat source 时才喂给 governance resolver / template preview；`ProjectModelGovernanceBindingTests` 也新增 preview 侧回归，锁定 bound project 的治理解释层不会被 card draft 或 stale legacy shadow 带偏。
  - `SupervisorAutoLaunchPolicyTests` 新增反向护栏：即使 project card 上残留 `fullAuto` shadow，只要真实 `executionTier` 仍停在 `A1 Plan`，one-shot auto-launch policy 也必须保持 `directed_safe_only`，不能被旧影子值抬高。
  - `ProjectModel` / `ProjectConfig` 的默认构造已进一步收紧到 conservative baseline（无显式治理、无 legacy 输入时默认落到 `A0 + S0 + milestone-only`）；补充回归后确认 `MultiProjectManager.createProject`、`ProjectModel.init`、`updateGovernance` 都会保留/规范化 `eventReviewTriggers`，不会在双拨盘治理里悄悄丢失 review trigger 集合。
  - 本轮继续验证了默认收紧后的关键 runtime 链路：`DirectedUnblockRouterTests`、`SupervisorMultilaneFlowTests`、`SupervisorRuntimeReliabilityKernelTests`、`SupervisorAutoContinueExecutorTests`、`SupervisorIntakeAcceptanceTests`、`TaskAssignerGovernanceTests`、`DeliveryScopeFreezeTests` 全部通过；production source callsite 也已审过，当前 `ProjectModel / ProjectConfig` 的实际创建路径都显式传入 `executionTier`，legacy `autonomyLevel` 只剩 compat/test 入口。
  - `XT-W3-36-H` 的 governance evidence gate 现已扩到新治理主链：除 resolver / UI / runtime / review/guidance 之外，还会覆盖 `CreateProjectGovernanceTransitionTests`、`ProjectDetailGovernanceSummaryTests`、`ProjectGovernanceDocsTruthSyncTests`、`AppModelMultiProjectGovernanceTests`，把 create flow 三轴切换、detail summary、文档真相源、以及多项目默认保守治理都纳入 release-style 证据。
  - `XT-W3-36-H` 继续收紧 legacy shadow 护栏：evidence gate 现额外覆盖 `SupervisorAutoLaunchPolicyTests`、`SupervisorMultilaneFlowTests`、`DirectedUnblockRouterTests`，把 one-shot auto-launch、lane allocator / child materialization、以及 directed unblock 恢复链路都纳入“不得被旧 `autonomyLevel` 阴影误抬权或放大作用域”的 release 证据。
  - `XT-W3-36-H` 现在也把 `SupervisorRuntimeReliabilityKernelTests`、`SupervisorAutoContinueExecutorTests` 纳入 release-style gate，确保治理护栏不只体现在权限解释上，也体现在 cancel/failure cleanup、fallback 收束、dependency-ready auto-continue 这些实际运行链路里。
  - `XT-W3-36-H` 继续把入口到收口的边界串成一条证据链：`SupervisorIntakeAcceptanceTests`、`DeliveryScopeFreezeTests` 已纳入 governance evidence gate，用来锁定 project intake/bootstrap、acceptance fail-closed、validated scope freeze、以及 replay/auto-continue 前的作用域收束不会脱离治理边界。
  - `XT-W3-36-H` 现已把 `TaskAssignerGovernanceTests` 也纳入 release-style gate，继续锁定 lane / task assignment 评价时优先看 `executionTier + supervisorInterventionTier`，而不是被旧 `autonomyLevel` shadow 误导到更高自治路径。
  - `XT-W3-36-H` 的 evidence report 现已显式输出 `review_guidance_chain` coverage summary，并由 `xt_release_gate.sh` 校验 `review_guidance_covered_dimension_count == review_guidance_total_dimension_count`。这样 release gate 不只知道“相关测试都过了”，还知道 review/guidance 主链已经覆盖了 policy resolution、cadence editing、guidance ack、safe-point delivery、dependency-ready follow-up 这几类治理能力。
  - `XT-W3-36-H` 现也显式输出 `ingress_runtime_chain` coverage summary，并要求 `ingress_runtime_covered_dimension_count == ingress_runtime_total_dimension_count`。这让 release gate 能直接看见 project 从 intake/bootstrap、validated scope freeze、lane/task assignment、到 runtime clamp 的治理覆盖，而不是只从分散测试名间接推断。
  - `XT-W3-36-H` 的 evidence report 现在还会产出 `digest.governance_coverage`，把 `review_guidance` / `ingress_runtime` 两条覆盖链压成可读摘要；`xt_release_gate.sh` 也已升级为同时校验 digest 计数、labels/capabilities 非空、以及 `human_summary_lines` 中必须存在 `review_guidance ...` 与 `ingress_runtime ...` 两条人类可读摘要，这样 release report / report-index 能直接带出可读治理结论，而不是只给原始 JSON。
  - 结合 `X_MEMORY.md` 中补齐的 XT-Ready gate / audit tooling 入口后，`XT_GATE_VALIDATE_PROJECT_GOVERNANCE=1 bash scripts/ci/xt_release_gate.sh` 现已回到 `GO`；当前 release report 观测为 `pass=64, fail=0`，并保留 project governance digest 作为人类可读发布证据。
  - 本轮又收口了一段“已实现但文档/发布索引还没完全对齐”的尾巴：`README` 不再把 XT-W3-36 治理表面写成 “moving toward / preview surfaces”，`X_MEMORY` 已明确记录 `A0..A4 + S0..S4 + A4 Agent + 三页治理编辑器 + release evidence`，`WORKING_INDEX` / `work-orders/README` 也已补进 `xt_w3_36_project_governance_evidence.sh` 与 `xt_release_gate.sh` 入口。
  - `ProjectGovernanceDocsTruthSyncTests` 现已扩展到校验 `X_MEMORY` 与 governance evidence entrypoints，防止以后再出现“runtime 已落地、release gate 已依赖，但记忆/索引文档还停在旧描述”的漂移。
  - 本轮继续收紧了治理模板的外显命名：虽然底层仍保留 `full_autonomy` raw value 作为兼容编码，但产品面与 tests 已统一改成 `Agent` / `A4 Agent` 语义，不再把最高治理模板展示成“完全自治”或 `A4 治理模板`；同时通过 `AXProjectGovernanceTemplateTests` 与 `SupervisorPortfolioProjectPresentationTests` 锁定这层对外表述。
  - 本轮也开始把 XT-W3-36 主链源码中的新调用收口到 `runtimeSurface` 语义：`AXProjectResolvedGovernanceState` 新增 `effectiveRuntimeSurface` 首选访问器、resolver 新增 `effectiveRuntimeSurface` 入口并优先使用 `effectiveRuntimeSurfacePolicy()` / `settingRuntimeSurfacePolicy()`，project governance UI 与核心回归测试已改走新名字；旧 `effectiveAutonomy*` / `settingAutonomyPolicy()` 仍保留为 compat wrapper，避免破坏旧数据与外部调用。
- 2026-03-17:
  - 协议与 runtime resolver 仍保持 `A0..A4 + S0..S4 + Heartbeat / Review` 三轴分离，但当前产品表面确认仍有一段 UI 漂移：治理 chip 虽然分成三枚，点击后却仍然落到同一个 `ProjectSettingsView` 内部 section。
  - 因此 `XT-W3-36-B` 被继续拆成专门的 UI 回正子包：`x-terminal/work-orders/xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md`。
  - `XT-W3-36-B` 现在按“两段完成”理解：
    - 已完成：双拨盘 contract、governance badge/inspector、runtime surface 解释层、主治理字段迁移
    - 未完成：独立治理页面、destination-based 路由、Create flow 三轴编辑器、README/产品面真相对齐
  - 在子包完成前，`README` 里 “already exposes” 一类说法应视为架构方向，不应再作为当前 UI 已完全对齐的证据。
- 2026-03-15:
  - `XT-W3-36-B/C` 继续把旧 `autonomy_*` 外显层向新 `runtime_surface` 协议迁移：runtime deny summary 现已补齐结构化 `runtime_surface` / `autonomy_policy` 对象、surface arrays、TTL/kill-switch/updated-at 字段，同时保留旧 top-level 兼容键不删。
  - `AppModel` 写入的模板应用 raw log 现以 `project_governance_template` 为主事件名，并保留 `legacy_type=project_autonomy_profile`；连同 `project_autonomy_policy` / `project_governance_bundle` 一起双写 `runtime_surface_configured/effective/...` 审计字段，证据测试会同时校验新旧命名，方便后续导出层切换。
  - `XTGuardrailMessagePresentation` 已兼容 `runtime_surface_effective=guided` 等新 reason alias，避免 deny reason 逐步迁移时 guardrail 文案退回默认提示。
  - `project_snapshot` 现已补齐结构化 `governance` 对象和 `execution_tier / supervisor_intervention_tier / review_policy_mode` 顶层字段；文本 body 也改为优先展示 `A-Tier / S-Tier / Heartbeat / Review cadence + runtime_surface`，不再把旧 `autonomy_*` 行直接暴露给用户。
  - runtime deny summary 现已新增 `runtime_surface_policy_reason` 规范化别名；guardrail 展示层会优先使用新字段，同时继续保留旧 `policy_reason` 作为兼容证据键。
  - `XT-W3-36-B` 已把 project UI 主路径切到 `A-Tier / S-Tier / Heartbeat / Review cadence`，并修复 create flow 在切换 A-Tier 时误重置 review 轴的问题。
  - `XT-W3-36-B` 已补齐治理解释层：`ProjectGovernanceBadge` / inspector 现在会明确标出当前治理来源是 `A/S 档位显式配置`、`兼容旧项目卡片档位`、还是 `兼容旧执行面预设`；保守默认项目也会明确提示当前是 conservative baseline。
  - `XT-W3-36-B` 已把设置页里旧 `执行面策略` 文案收口为 `运行时 Surface`，避免把 `autonomyMode` 误读成 project 总治理档位；supervisor 本地记忆摘要也同步改用 `runtime_surface`，与 `execution_tier / supervisor_tier` 分层表达。
  - `XT-W3-36-B` 已继续把治理模板开发入口切到 `settingGovernanceTemplate / selectableTemplates / xtProjectGovernanceTemplatePresentation`，旧 switchboard helper 退到 compat wrapper，方便后续把残留 `autonomy profile` 命名继续收口到兼容层。
  - `XT-W3-36-B` 已把治理模板主类型名翻正为 `AXProjectGovernanceTemplate / AXProjectGovernanceTemplatePreview`；旧 `AXProjectAutonomyProfile / AXProjectAutonomySwitchboardPresentation` 与 `applyProjectAutonomyProfile / autonomySwitchboardPresentation` 继续保留，但仅作为显式 compat alias / wrapper。
  - `XT-W3-36-B` 已把 switchboard 内部私有实现名同步收口到 governance 语义：`TemplateSpec / TemplateSnapshot / configured/effective template matcher` 取代旧 `AutonomyProfile*` 私有 helper，减少后续新代码继续挂到旧命名上的概率。
  - `XT-W3-36-B` 已把主源码文件和测试套件名翻到 governance 语义：`AXProjectGovernanceTemplate.swift` / `AXProjectGovernanceTemplateTests.swift` 成为主路径，旧 `AutonomySwitchboard` 仅继续存在于 compat API 名称中。
  - `XT-W3-36-B` 已把 runtime surface 解释层主入口翻正为 `AXProjectGovernanceSurfaceExplanation.swift`、`xtProjectRuntimeSurfaceExplanation`、`xtProjectGovernanceClampExplanation` 和 `ProjectGovernanceSurfaceExplanationTests`；设置页、badge、guardrail、runtime policy 已切到新入口，旧 `AutonomyExplanation` 仅保留 deprecated compat wrapper。
  - `XT-W3-36-B` 已把 runtime surface policy 主文件与主 API 翻正为 `AXProjectRuntimeSurfacePolicy.swift`、`AXProjectRuntimeSurface*`、`settingRuntimeSurfacePolicy`、`effectiveRuntimeSurfacePolicy`、`resolvedProjectRuntimeSurfacePolicy`；设置页与工具授权主路径开始改走新命名，旧 `AutonomyPolicy` API 仅保留 compat wrapper。
  - `XT-W3-36-B` 已新增 `ProjectGovernancePresentationSummaryTests.governanceSourceHintSurfacesCompatAndConservativeProjects`，并在隔离快照中通过 `ProjectGovernancePresentationSummaryTests / ProjectSettingsGovernanceUITests / ProjectGovernanceResolverTests / ProjectModelGovernanceBindingTests` 共 26 条回归。
  - `XT-W3-36-C` 已新增共享 `XTGovernedRepoCommandPolicy`，统一 supervisor skill mapping、runtime capability 分类与 tool authorization 的 governed repo build/test 命令判定。
  - `run_command` 现在会把受治理命令细分成 `repo_build` / `repo_test` / `repo_build_test` deny reason；只有 allowlist 内的 repo build/test 命令可走 governed auto-approval，普通 shell 仍保留本地人工确认。
  - `XT-W3-36-D` 已把 `brainstorm review` 的窗口基准改成“上次观察到的真实项目进展”，并通过 `SupervisorReviewScheduleStore` 回写 `last_observed_progress_at_ms`；heartbeat 不会再把 brainstorm 当成单纯定时器，而是只在 no-progress window 真正到期后触发。
  - `XT-W3-36-D` 已把 `skill callback` follow-up 从泛化 `periodic_pulse` 升级成按 workflow 实态发出显式 `review_trigger / review_level_hint / review_run_kind`：失败/阻塞回调会走 `blocker_detected`，终态完成回调会走 `pre_done_summary`，普通中间完成仍保持 `periodic_pulse`。
  - `XT-W3-36-D` 已补齐 event-loop structured-only follow-up 的 `ReviewNote` 审计闭环：即使当前 policy 不允许把这轮 follow-up 投递成 guidance，也会落一条 audit-only review note；只有真正允许投递时才写 guidance injection。
  - `XT-W3-36-G/H` 继续收口：lane allocator、task assigner、one-shot auto-launch、child project materialization、one-shot anchor project 初始化已改为直接看 `executionTier / supervisorInterventionTier`，旧 `autonomyLevel` 只保留为 compat shadow 与 resolver 输入，不再主导新建 project 的运行调度判断。
  - `XT-W3-36-G/H` 进一步收紧 compat bridge：`AppModel` 现在只会在 `legacyAutonomyMode / legacyAutonomyLevel` 配置下把 project card 的旧 `autonomyLevel` shadow 传给 governance resolver；`defaultConservative` 与 `explicitDualDial` 都会忽略这类旧影子输入，保持 fail-closed 或显式双档位配置为准。
  - 新增 `AppModelMultiProjectGovernanceTests`，覆盖 `MultiProjectManager.createProject` 与 `AppModel.createMultiProject` 的显式治理透传、绑定 project root、legacy shadow 对齐，防止后续把多项目创建入口重新接回旧 `autonomyLevel` 驱动路径。
  - 新增 `SupervisorManagerVoiceAuthorizationTests` 的 one-shot anchor governance 回归，以及 `TaskAssignerGovernanceTests`，分别锁定 supervisor 起 Root project 的 A/S 档位映射、以及 task capability 评估优先看新治理字段而不是被 legacy shadow 误导。
  - 新增 `ProjectGovernanceResolverTests.legacyAutonomyShadowIsOnlyConsumedForCompatSources` 和 `ProjectModelGovernanceBindingTests.boundProjectKeepsDefaultConservativeGovernanceInsteadOfProjectCardShadow`，锁定 compat bridge 收口行为，防止绑定 project 在 schema v10 conservative 配置下被旧 project card 阴影值重新抬升到高自治档位。

## 0) 为什么要单开这份包

当前系统里已经同时存在三类看起来相近、但本质不同的控制面：

- project 能不能自主做事
- supervisor 该不该主动 review / brainstorm / 纠偏
- heartbeat 多久回报一次进度

问题在于，这三件事目前没有被显式拆开：

1. `manual/guided/trusted_openclaw_mode` 更像 execution surface preset，不足以表达“执行能力强，但 supervisor 仍需周期 review”。
2. heartbeat 只能说明“多久看一次进度”，不能说明“多久做一次深入 review”或“什么时候插入方向建议”。
3. `AutonomyLevel(1..5)` 与 `AXProjectAutonomyMode` 同时存在，但二者都不是正式 project governance contract。
4. Supervisor 已经有 portfolio、project capsule、memory drilldown 和 job/plan action 能力，但还缺一套正式的“何时介入、如何介入、何时要求 ack”的运行合同。
5. A4 / OpenClaw 类项目如果没有单独的介入强度定义，容易在两个极端之间摇摆：
   - 要么 supervisor 过度介入，反而拖慢执行
   - 要么 supervisor 基本失联，项目跑偏后很晚才发现

所以 `XT-W3-36` 不是再发明一个新 slider，而是把系统中已经存在、但仍混在一起的控制面拆成三根独立拨盘，并冻结为可执行主链。

## 1) 北极星模型

### 1.1 三个独立控制面

每个 project 以后都按三组设置解析：

1. `A-Tier`
   - 决定 project AI 能做什么。
   - 只讨论执行权限和执行面。

2. `S-Tier`
   - 决定 supervisor 多频繁 review、多主动 brainstorm、多深地介入方向。
   - 只讨论 review / guidance / replan / interrupt 的强度。

3. `Heartbeat / Review Schedule`
   - 决定多久汇报进度、多久做 pulse review、多久做 strategic brainstorm review。
   - 是时序调度，不是权限。

冻结规则：

- `A-Tier` 只管 execution rights，不再混入 supervisor 行为。
- `S-Tier` 只管 intervention strength，不再暗含 device/repo 权限。
- `Heartbeat / Review` 保持独立，不再用“心跳时间”替代 review policy。

### 1.2 对用户和运行时的呈现

用户可见层：

- project 顶部显示一个 `A?` 和一个 `S?`
- 点击后可看：
  - 当前 capability bundle
  - 当前 memory ceiling
  - 当前 Heartbeat / Review cadence
  - 当前 Hub clamp / TTL / kill-switch 状态

运行时真相源：

- 以 machine-readable `Project Governance Bundle` 为准
- UI 只是一层编辑器和解释层

### 1.3 和记忆系统的关系

本包同时冻结一条很关键的解释链：

- `A-Tier` 决定 project coder 的默认背景信息 ceiling
- `S-Tier` 决定 supervisor review 时可使用的默认 review memory ceiling
- `XT-W3-35` 的渐进检索能力为这两个 ceiling 提供“按需展开”通道

也就是说：

- 高档位 project coder 确实可以拿到更完整的 project 背景
- 高介入 supervisor 也可以在 review 时拿到更完整的项目上下文
- 但两者都仍受 `memory profile`、scope、audit 和 fail-closed 约束

## 2) 固定决策

### 2.1 `A0..A4` 只表示执行权限

冻结：

- `A0 Observe`
- `A1 Plan`
- `A2 Repo Auto`
- `A3 Deliver Auto`
- `A4 Agent`

`A-Tier` 不能再直接表达：

- review 频率
- review 是否 brainstorm
- supervisor 是否旁路纠偏

这些语义全部移到 `S-Tier`。

### 2.2 `S0..S4` 只表示 supervisor 介入强度

冻结：

- `S0 Silent Audit`
- `S1 Milestone Review`
- `S2 Periodic Review`
- `S3 Strategic Coach`
- `S4 Tight Supervision`

`S-Tier` 不能再直接放权给 repo / device / connector / extension。

### 2.3 Heartbeat 单独保留

冻结：

- `progress_heartbeat_sec`
- `review_pulse_sec`
- `brainstorm_review_sec`
- `event_driven_review_enabled`
- `event_review_triggers`

### 2.4 A4 仍然有 supervisor，只是 supervisor 换到旁路治理位

`A4` 的目标不是去掉 supervisor，而是把 supervisor 从“每一步审批者”改成：

- 旁路观察者
- 战略复盘者
- 方向纠偏者
- 高风险动作前的仲裁者

### 2.5 Guidance 必须结构化

supervisor 的 review 结果不能只靠自然语言漂在聊天里。

必须落成：

- `Review Note`
- `Guidance Queue Item`
- `Ack Status`

并且继续遵守协议里已冻结的枚举：

- `target_role`: `coder | supervisor | project_chat`
- `delivery_mode`: `context_append | priority_insert | replan_request | stop_signal`
- `ack_status`: `pending | accepted | deferred | rejected`

### 2.6 默认 soft intervention 走 safe point

除以下情况外，不允许立即打断：

- `kill_switch`
- `policy_denied`
- `pre_high_risk_action`
- `wrong_direction` 且高置信

其它建议默认走：

- `next_tool_boundary`
- `next_step_boundary`
- `checkpoint_boundary`

## 3) 档位冻结

### 3.1 A-Tier

| Tier | 名称 | 默认 project memory ceiling | 核心能力 | 不允许 |
| --- | --- | --- | --- | --- |
| `a0_observe` | Observe | `m2_plan_review` | 读记忆、读项目状态、给建议 | 创建 job、改 repo、跑 side effect |
| `a1_plan` | Plan | `m2_plan_review` | 自动建 `job/plan`、写 project memory、产出执行方案 | repo side effect、device side effect |
| `a2_repo_auto` | Repo Auto | `m3_deep_dive` | project root 内改文件、跑 build/test、做 patch、更新计划 | device/browser/connector 高风险执行 |
| `a3_deliver_auto` | Deliver Auto | `m3_deep_dive` | 多 step 连续推进到交付完成、自动收口、汇总通知 | 未授权 device-level side effect |
| `a4_openclaw` | Agent | `m4_full_scan` | 在受治理前提下使用 browser/device/connector/extension 完整执行面 | 绕过 trusted automation、Hub grant、kill-switch |

### 3.2 S-Tier

| Tier | 名称 | 默认 review memory ceiling | 触发语义 | 默认注入动作 |
| --- | --- | --- | --- | --- |
| `s0_silent_audit` | Silent Audit | `m2_plan_review` | 只看、不主动插入 guidance；仅保留 incident / kill-switch 审计 | `observe_only` |
| `s1_milestone_review` | Milestone Review | `m2_plan_review` | milestone / pre-done / manual request review | `suggest_next_safe_point` |
| `s2_periodic_review` | Periodic Review | `m3_deep_dive` | 周期 pulse + blocker / pre-done review | `suggest_next_safe_point` |
| `s3_strategic_coach` | Strategic Coach | `m4_full_scan` | 周期 pulse + strategic brainstorm + drift / blocker / rescue review | `replan_next_safe_point` |
| `s4_tight_supervision` | Tight Supervision | `m4_full_scan` | 高频 review + 高风险前 gate + 必要时 pre-step hold | `replan_next_safe_point` 或 `stop_immediately` |

### 3.3 Heartbeat / Review Schedule

冻结为独立调度对象，不再塞进 `A-Tier` 或 `S-Tier`：

- `progress_heartbeat_sec`
- `review_pulse_sec`
- `brainstorm_review_sec`
- `event_driven_review_enabled`
- `event_review_triggers`
- `interrupt_rate_limit_per_hour`

## 4) 组合规则

### 4.1 推荐默认组合

| Execution | Supervisor | 说明 |
| --- | --- | --- |
| `A0` | `S0` | 观察为主，不自动推进 |
| `A1` | `S1` | 自动梳理计划，但不直接动 repo |
| `A2` | `S2` | repo 内自主推进，supervisor 周期 review |
| `A3` | `S3` | 持续推进到交付，supervisor 做战略纠偏 |
| `A4` | `S3` | 高自治执行面 + 旁路战略 review，是推荐主档 |

### 4.2 合法但更严格的组合

- `A1 + S2`
- `A2 + S3`
- `A3 + S4`
- `A4 + S4`

这些组合用于：

- 高风险仓库
- 复杂长期项目
- 明确希望 supervisor 更强势跟进的场景

### 4.3 高风险但允许用户选择的组合

以下组合默认标记为高风险，允许保存，但 UI / 审计 / Supervisor 都必须显著提示风险：

- `A2 + S0`
- `A3 + S0`
- `A4 + S0`
- `A4 + S1`

原因：

- repo 及以上自主执行在“几乎无 review”下更容易放大 drift / rescue 窗口
- device-level / Agent 面只靠 milestone review 时，更容易把高风险动作前的纠偏做得过晚

补充：

- 这是一组产品治理强警告，不是“物理不可能”的矩阵。
- 真正的 fail-closed 仍只来自 runtime readiness、trusted automation、tool policy、Hub grant、TTL、kill-switch、scope / binding 等实证边界。

### 4.4 警告组合

以下组合允许保存，但 UI 与运行时都要给出风险提示：

- `A2 + S1`
- `A3 + S1`
- `A3 + S2`
- `A4 + S2`

这些组合不是错误，但意味着：

- supervisor 介入强度低于推荐值
- drift / rescue 发现窗口会变大

## 5) 机读契约冻结

### 5.1 `xt.project_execution_tier.v1`

```json
{
  "schema_version": "xt.project_execution_tier.v1",
  "project_id": "proj_alpha",
  "tier": "a3_deliver_auto",
  "project_memory_ceiling": "m3_deep_dive",
  "surface_preset": "guided",
  "allowed_capabilities": [
    "job.create",
    "plan.upsert",
    "repo.read",
    "repo.write",
    "repo.build",
    "repo.test"
  ],
  "ttl_sec": 3600,
  "audit_ref": "audit_exec_001"
}
```

### 5.2 `xt.supervisor_intervention_tier.v1`

```json
{
  "schema_version": "xt.supervisor_intervention_tier.v1",
  "project_id": "proj_alpha",
  "tier": "s3_strategic_coach",
  "review_memory_ceiling": "m4_full_scan",
  "default_intervention_mode": "replan_next_safe_point",
  "safe_point_policy": "next_step_boundary",
  "coder_ack_required": true,
  "audit_ref": "audit_sup_001"
}
```

### 5.3 `xt.project_governance_combo.v1`

```json
{
  "schema_version": "xt.project_governance_combo.v1",
  "project_id": "proj_alpha",
  "execution_tier": "a4_openclaw",
  "supervisor_intervention_tier": "s3_strategic_coach",
  "surface_preset": "trusted_openclaw_mode",
  "progress_heartbeat_sec": 600,
  "review_pulse_sec": 1200,
  "brainstorm_review_sec": 2400,
  "event_driven_review_enabled": true,
  "event_review_triggers": [
    "blocker_detected",
    "plan_drift",
    "pre_high_risk_action",
    "pre_done_summary"
  ],
  "clamp_state": "none",
  "compat_source": "explicit_dual_dial",
  "audit_ref": "audit_combo_001"
}
```

### 5.4 `xt.supervisor_review_note.v1`

```json
{
  "schema_version": "xt.supervisor_review_note.v1",
  "review_id": "review_001",
  "project_id": "proj_alpha",
  "trigger": "plan_drift",
  "review_level": "r2_strategic",
  "verdict": "replan_recommended",
  "confidence": 0.89,
  "recommended_actions": [
    "shrink active scope",
    "switch to safer integration order"
  ],
  "intervention_mode": "replan_next_safe_point",
  "target_role": "coder",
  "delivery_mode": "replan_request",
  "ack_required": true,
  "audit_ref": "audit_review_001"
}
```

### 5.5 `xt.supervisor_guidance_queue_item.v1`

```json
{
  "schema_version": "xt.supervisor_guidance_queue_item.v1",
  "guidance_id": "guide_001",
  "project_id": "proj_alpha",
  "review_id": "review_001",
  "target_role": "coder",
  "delivery_mode": "priority_insert",
  "safe_point_policy": "next_step_boundary",
  "intervention_mode": "replan_next_safe_point",
  "ack_status": "pending",
  "expires_at_ms": 1760000000000,
  "audit_ref": "audit_guide_001"
}
```

## 6) 代码落点

### 6.1 Project Config / Compatibility

- `x-terminal/Sources/Project/AXProjectConfig.swift`
- `x-terminal/Sources/Project/AXProjectRuntimeSurfacePolicy.swift`
- `x-terminal/Sources/Project/ProjectModel.swift`
- `x-terminal/Sources/Project/AXProjectRegistry.swift`
- 新增：
  - `x-terminal/Sources/Project/AXProjectExecutionTier.swift`
  - `x-terminal/Sources/Project/AXProjectSupervisorInterventionTier.swift`
  - `x-terminal/Sources/Project/AXProjectGovernanceBundle.swift`
  - `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`

### 6.2 UI

- `x-terminal/Sources/UI/ProjectSettingsView.swift`
- `x-terminal/Sources/UI/Projects/CreateProjectSheet.swift`
- `x-terminal/Sources/UI/Projects/ProjectDetailView.swift`
- `x-terminal/Sources/UI/GlobalHomeView.swift`
- 需要时新增：
  - `x-terminal/Sources/UI/ProjectGovernanceBadge.swift`
  - `x-terminal/Sources/UI/ProjectGovernanceInspector.swift`

### 6.3 Supervisor Runtime / Review Loop

- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- `x-terminal/Sources/Supervisor/XTAutomationRuntimePolicy.swift`
- `x-terminal/Sources/Supervisor/XTAutomationRunCoordinator.swift`
- `x-terminal/Sources/Supervisor/SupervisorPortfolioSnapshot.swift`
- 新增：
  - `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
  - `x-terminal/Sources/Supervisor/SupervisorReviewScheduleStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorReviewNoteStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorGuidanceInjectionStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorSafePointCoordinator.swift`

### 6.4 Tool / Capability Gate

- `x-terminal/Sources/Tools/XTToolRuntimePolicy.swift`
- `x-terminal/Sources/Tools/ToolExecutor.swift`
- `x-terminal/Sources/Hub/HubIPCClient.swift`

## 7) 迁移策略

### 7.1 schema 升级

- `AXProjectConfig.currentSchemaVersion` 升到下一版
- 新增字段：
  - `executionTier`
  - `supervisorInterventionTier`
  - `progressHeartbeatSeconds`
  - `reviewPulseSeconds`
  - `brainstormReviewSeconds`
  - `eventDrivenReviewEnabled`
  - `eventReviewTriggers`

### 7.2 旧字段定位

旧字段继续保留，但只作为 compatibility input：

- `AXProjectAutonomyMode`
  - 只表示 `surface preset`
- `AutonomyLevel`
  - 只表示 legacy execution intent

二者都不再是最终运行时真相源。

### 7.3 迁移优先级

第一次解析 project governance 时按以下优先级：

1. 若已存在新双拨盘字段，直接使用
2. 否则若存在 `AutonomyLevel`，按 `1..5 -> A0..A4` 映射
3. 否则按 `AXProjectAutonomyMode` 保守推断：
   - `manual -> A0`
   - `guided -> A1`
   - `trusted_openclaw_mode -> A4`
4. 若仍无法确定，则默认 `A0 + S0`
5. `S-Tier` 默认取推荐配对值

### 7.4 旧 surface preset 的兼容

迁移后仍保留：

- `manual`
- `guided`
- `trusted_openclaw_mode`

但它们只负责决定：

- browser / device / connector / extension surface preset
- Hub clamp 对这些 surface 的压制方式

真正是否执行，继续由：

- `executionTier`
- `supervisorInterventionTier`
- trusted automation readiness
- tool runtime policy
- Hub grant / clamp / kill-switch

共同决策。

### 7.5 clamp 与 kill-switch 对齐

冻结：

- `kill_switch` 总是最高优先级
- `clamp_manual` 与 `clamp_guided` 继续压制 surface preset
- 当 `effective governance` 低于参考监督线时，不能只因 `A/S` 组合本身直接 fail-closed。
- 这时系统必须：
  - 把组合标成高风险
  - 在 UI / 审计 / Supervisor brief 中持续提示
  - 继续只按真实 runtime 权限、grant、TTL、kill-switch、scope / binding 做执行放行或拒绝

本包推荐第一版实现为：

- UI 不阻止保存高风险组合，但必须给显著风险提示
- 运行时对真实越权、未授权、未就绪、TTL 过期、Hub 收束路径继续 fail-closed

## 8) 可执行粒度工单

### 8.1 `XT-W3-36-A` Dual-Dial Contract + Config Schema

- priority: `P0`
- 目标：把双拨盘治理写成正式的 config / contract / resolver，而不是散落在 UI 和 prompt 文本里。
- 推荐落点：
  - `x-terminal/Sources/Project/AXProjectConfig.swift`
  - `x-terminal/Sources/Project/AXProjectRuntimeSurfacePolicy.swift`
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/AppModel+MultiProject.swift`
  - 新增 `AXProjectExecutionTier.swift`
  - 新增 `AXProjectSupervisorInterventionTier.swift`
  - 新增 `AXProjectGovernanceResolver.swift`
- 实施步骤：
  1. 冻结 `A-Tier`、`S-Tier`、schedule 字段和组合 guidance 规则。
  2. 新增 `effective governance resolution`：
     - configured combo
     - legacy compat source
     - hub clamp
     - ttl
     - trusted automation readiness
  3. 输出统一的 `AXProjectResolvedGovernanceState`。
  4. 为 resolver 补 machine-readable debug snapshot。
- DoD：
  - 不再需要在 UI、tool gate、supervisor runtime 三处各自重复推断 governance。
  - 旧项目可无 crash 地被解析成保守双拨盘状态。

### 8.2 `XT-W3-36-B` Project Top Bar + Settings UI

- priority: `P0`
- 目标：把 project 顶部与设置页升级为双拨盘治理面。
- active_child_pack:
  - `x-terminal/work-orders/xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md`
- progress_update_2026_03_15:
  - `GlobalHomeView` 项目卡片已改为展示 `A-Tier / S-Tier / Heartbeat / Review` 治理拨盘摘要，不再沿用旧 `Autonomy` 单拨盘标题。
  - `ProjectSettingsView` 已切到 `A-Tier / S-Tier / review policy / cadence / clamp / guidance ack` 展示。
  - `CreateProjectSheet` 已切到新治理拨盘；切 `A-Tier` 时不再重置独立的 review policy / cadence。
  - `ProjectDetailView` 顶部与详情卡已突出显示 `A-Tier / S-Tier / Heartbeat / Review` 摘要，不再依赖旧 `autonomy level` 语义。
  - `ProjectGovernanceBadge` / `ProjectGovernanceInspector` 已补上治理来源解释，能明确区分 `显式双拨盘`、`legacy card compat`、`legacy surface compat`、`default conservative`。
  - `ProjectSettingsView` 已把旧 `执行面策略` 标签降级成 `运行时 Surface`，强调它只是 runtime preset，不是 project 治理主档位。
  - 相关解释层回归已覆盖 compat / conservative 提示，避免 UI 重新把旧 `autonomy` 语义抬回主路径。
- 推荐落点：
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Sources/UI/Projects/CreateProjectSheet.swift`
  - `x-terminal/Sources/UI/Projects/ProjectDetailView.swift`
  - `x-terminal/Sources/UI/GlobalHomeView.swift`
- 实施步骤：
  1. 顶部显示 `A? / S? / clamp / ttl / Heartbeat / Review` 摘要。
  2. 设置页新增：
     - A-Tier picker
     - S-Tier picker
     - Progress Heartbeat 输入
     - Review Pulse 输入
     - Brainstorm Review 输入
  3. `ProjectDetailView` 与 project header 共用同一份治理 badge / inspector，不再继续展示旧 `AutonomyLevel` 星级语义。
  4. 对高风险组合给出即时强警告，但不阻止保存。
  5. 对偏保守组合给出风险说明。
  6. 展示“当前 effective 值”与“被 clamp 后的值”。
- DoD：
  - 用户能一眼区分“权限档位”和“supervisor 盯得多紧”。
  - 不再把 review 配置误解成 heartbeat 配置。
  - 不再把三个治理入口重新折回到同一个 settings section-scroll 页面；详见子包 `XT-W3-36-B1..B7`。

### 8.3 `XT-W3-36-C` Execution Capability Resolver

- priority: `P0`
- 目标：让 repo/device/browser/connector/extension 等执行面只从统一 governance resolver 取最终 verdict。
- 推荐落点：
  - `x-terminal/Sources/Project/AXProjectRuntimeSurfacePolicy.swift`
  - `x-terminal/Sources/Tools/XTToolRuntimePolicy.swift`
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
- 实施步骤：
  1. 把 `A-Tier` 映射到 capability bundle。
  2. 把旧 `surface preset` 保留为 surface clamp，而不是主权来源。
  3. 接入 trusted automation / Hub grant / clamp / TTL 复核。
  4. 为 deny path 统一 reason code。
- DoD：
  - `A2/A3/A4` 的区别能在运行时真实体现，而不是只停留在 UI 文案。
  - device-level surface 继续只有 `A4 + trusted automation + grant` 才会放行。

### 8.4 `XT-W3-36-D` Supervisor Intervention Resolver + Review Scheduler

- priority: `P0`
- 目标：让 supervisor 的 review 与 brainstorm 调度从“零散 heartbeat”升级为正式 intervention engine。
- 推荐落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRunCoordinator.swift`
  - 新增 `SupervisorReviewPolicyEngine.swift`
  - 新增 `SupervisorReviewScheduleStore.swift`
- 实施步骤：
  1. 把 `S-Tier` 映射到：
     - review depth
     - review triggers
     - default intervention mode
     - ack requirement
  2. 引入三类调度：
     - progress heartbeat
     - pulse review
     - brainstorm review
  3. 事件触发 review 至少覆盖：
     - `blocker_detected`
     - `plan_drift`
     - `failure_streak`
     - `pre_high_risk_action`
     - `pre_done_summary`
  4. 为每次 review 组装统一 `review input ladder`：
     - `L0/L1 anchor pack`
     - `L2 progress pack`
     - `L3 working set`
     - 按需展开 `L4 raw evidence`
  5. 为每次 review 生成结构化 `Review Note`。
  6. `r2_strategic / r3_rescue` 默认应支持 option scan，但保留 supervisor 自由度：
     - 默认比较 `keep_current_path` 与 `proposed_better_path`
     - 必要时再展开 `higher_cost_higher_upside_path`
     - 若证据非常明确支持继续当前路径，可只做轻量 option sanity check
  7. 若建议改 plan，必须同时写明：
     - 更好在哪里
     - 切换成本
     - 风险
     - 对原始目标/约束的影响
  8. policy engine 只校验：
     - 是否完成 re-anchor
     - 是否引用足够证据
     - 是否输出可执行 guidance
     不校验固定推理顺序或固定文风
- DoD：
  - `继续` 这种人工 nudging 不再是 supervisor 复盘的唯一入口。
  - `A4` 项目可以定时被 review，但不必每一步被卡住。
  - review 不是只看 heartbeat 文本，而是按最小记忆梯度和证据梯度做判断。
  - brainstorm 只在触发条件满足时运行，不制造无谓 churn。
  - 实现出来的是“有护栏的自由 review”，不是僵硬 checklist agent。

### 8.5 `XT-W3-36-E` Review Note + Guidance Injection + Ack Loop

- priority: `P0`
- 目标：把 review 产物变成可追踪的 guidance 队列，而不是散落消息。
- 推荐落点：
  - 新增 `SupervisorReviewNoteStore.swift`
  - 新增 `SupervisorGuidanceInjectionStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- 实施步骤：
  1. Review 完成后写 `Review Note`。
  2. 根据 verdict 生成 `Guidance Queue Item`。
  3. 支持协议中已冻结的：
     - `target_role`
     - `delivery_mode`
     - `ack_status`
  4. `coder` 接到 guidance 后必须回写：
     - `accepted`
     - `deferred`
     - `rejected`
  5. `rejected` 必须附带原因。
- DoD：
  - supervisor 说过什么、project AI 是否接收、是否执行过，都能 audit。
  - `ack_status=pending` 的 guidance 不能被误当成已执行。

### 8.6 `XT-W3-36-F` Safe Point Coordinator

- priority: `P1`
- 目标：把 guidance 注入切到安全边界，避免粗暴打断执行链。
- 推荐落点：
  - 新增 `SupervisorSafePointCoordinator.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRunCoordinator.swift`
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
- 实施步骤：
  1. 冻结四类 safe point：
     - `next_tool_boundary`
     - `next_step_boundary`
     - `checkpoint_boundary`
     - `immediate`
  2. soft guidance 默认排队到下一个 safe point。
  3. `kill_switch / policy_denied / pre_high_risk_action` 允许升级到更强注入策略。
  4. 对被延期的 guidance 保留过期与重试策略。
- DoD：
  - project AI 不会因为轻量建议被频繁打断。
  - supervisor 又能在真正高风险时立即止损。

### 8.7 `XT-W3-36-G` Migration + Clamp + Kill-Switch Alignment

- priority: `P1`
- 目标：让新治理模型可以平滑吃掉旧项目、旧 slider、旧 autonomy mode，而不制造错误放权。
- 推荐落点：
  - `x-terminal/Sources/Project/AXProjectConfig.swift`
  - `x-terminal/Sources/Project/ProjectModel.swift`
  - `x-terminal/Sources/Project/AXProjectRegistry.swift`
  - `x-terminal/Sources/Project/AXProjectRuntimeSurfacePolicy.swift`
- 实施步骤：
  1. 保守迁移 legacy project。
  2. 统一 `AutonomyLevel` 与 `AXProjectAutonomyMode` 的 compat path。
  3. Hub clamp 与 local override 写入统一 effective snapshot。
  4. 为 kill-switch / clamp / expired TTL 给出可解释文案和 reason code。
- DoD：
  - 没有 project 因 schema 升级被静默放到更高自治档。
  - 所有 clamp 都能在 UI 和 runtime 上看到同一解释。

### 8.8 `XT-W3-36-H` Require-Real Regression + Metrics

- priority: `P1`
- 目标：把这套治理包做成可回归、可度量、可发布判断的主链。
- 推荐落点：
  - `x-terminal/Tests/`
  - `x-terminal/scripts/ci/`
  - `build/reports/`
- 需要补的测试族：
  - `ProjectGovernanceResolverTests`
  - `SupervisorInterventionPolicyEngineTests`
  - `SupervisorGuidanceInjectionStoreTests`
  - `SupervisorSafePointCoordinatorTests`
  - `XTToolRuntimePolicyGovernanceClampTests`
  - `ProjectSettingsGovernanceUITests`
- 关键指标：
  - `invalid_governance_combo_execution_count = 0`
  - `guidance_without_ack_tracking = 0`
  - `device_action_under_subminimum_supervision = 0`
  - `legacy_project_overgrant_after_migration = 0`
- 交付物：
  - `build/reports/xt_w3_36_project_governance_evidence.v1.json`
  - `digest.governance_coverage.review_guidance`
  - `digest.governance_coverage.ingress_runtime`
  - `digest.governance_coverage.human_summary_lines`

## 9) 实施顺序

推荐推进顺序：

1. `XT-W3-36-A`
2. `XT-W3-36-B`
3. `XT-W3-36-C`
4. `XT-W3-36-D`
5. `XT-W3-36-E`
6. `XT-W3-36-F`
7. `XT-W3-36-G`
8. `XT-W3-36-H`

原因：

- 先冻结 contract 和 resolver，后面的 UI / runtime / guidance 才不会各写一套解释
- guidance / safe point 必须建立在 review scheduler 之后
- migration 与 require-real regression 放在后半段，避免前面 contract 仍在变化时反复改 fixture

## 10) 完成标准

本包完成后，系统应能稳定回答下面这些过去经常说不清的问题：

1. 这个 project 到底能自主做到哪一步，是 `A1` 还是 `A4`？
2. supervisor 是只观察，还是会定期 brainstorm 和纠偏？
3. heartbeat 只是看进度，还是也会触发正式 review？
4. project coder 和 supervisor 各自能拿到多深的背景信息？
5. guidance 是不是已经注入、是否被接受、为什么被拒绝？
6. 旧项目迁移后有没有被错误放权？

如果这 6 个问题都能由统一的 governance resolver、UI 解释层和审计对象给出一致答案，`XT-W3-36` 才算真正完成。

## 11) 最新推进记录

### 2026-03-15

- 已完成一轮 supervisor/runtime 回归收口：
  - `SupervisorManager.makeForTesting()` 不再读取或写回持久化 `supervisor_jurisdiction_registry` / `action_ledger`，同时禁用测试态下对全局 project registry 的 fallback，避免测试被机器本地遗留项目污染。
  - `SupervisorCommandGuardTests` 里依赖 `trustedOpenClawMode` 的 `updatedAt` 已改成相对当前时间，避免 TTL 过期后误退回 `manual`。
  - `directSupervisorActionIfApplicable` 已优先处理自然语言模型切换，再处理 memory patch，修复“把项目模型换成 5.3”被误记成决策语句的问题。
  - governed repo command policy 新增官方本地备份命令白名单，`agent-backup create` 现在能作为受治理本地备份动作自动通过，而不会误报 `command_outside_governed_repo_allowlist`。
  - runtime surface 解释层已统一：`AXProjectGovernanceSurfaceExplanation` 新增共享 `runtime surface` 文案，`ProjectSettingsView` 和 `XTGuardrailMessagePresentation` 不再回退到 `Manual / Guided / autonomy policy` 旧说法。
  - `ToolExecutor` / `XTToolRuntimePolicy` / `AppModel` 的对外输出开始补发 `runtime_surface_*` 新字段；旧 `autonomy_*` 字段继续保留作为 compat alias，方便外部消费者平滑迁移。
- 已补充回归：
  - `XTToolAuthorizationTests.governedAutoApprovalAllowsGovernedLocalBackupCommandWhenProjectAuthorityIsActive`
  - `ProjectGovernanceSurfaceExplanationTests.runtimeSurfaceExplanationUsesSurfaceLanguageInsteadOfLegacyAutonomyCopy`
  - `XTGuardrailMessagePresentationTests.blockedBodyUsesRuntimeSurfaceLanguageForGuidedSurfaceBlock`
  - `ToolExecutorSessionToolsTests` / `ToolExecutorRuntimePolicyTests` / `XTToolRuntimePolicyGovernanceClampTests` 新增 `runtime_surface_*` 断言
- 本轮验证结果：
  - `swift test --filter SupervisorCommandGuardTests` 通过，96 tests passed。
  - `swift test --filter XTToolAuthorizationTests` 通过，11 tests passed。
  - `swift test --skip-build --filter ProjectGovernanceSurfaceExplanationTests` 通过，2 tests passed。
  - `swift test --skip-build --filter XTGuardrailMessagePresentationTests` 通过，5 tests passed。
  - `swift test --skip-build --filter ProjectSettingsGovernanceUITests` 通过，3 tests passed。

### 2026-03-18

- 已继续收口 XT-W3-36 的 runtime surface 命名迁移尾巴：
  - `XTToolAuthorization` 现在以 `runtimeEffectiveSurface` 为主存储 denied context，并保留 `runtimeEffectiveAutonomy` 兼容访问口，避免外部调用一次性断裂。
  - `XTToolRuntimePolicy` 新增 `effectiveRuntimeSurface` 优先入口，`effectiveAutonomy` 旧标签只作为 compat wrapper 保留；deny summary 仍继续双发 `runtime_surface_*` 与 `autonomy_*` 字段。
  - `XTAutomationRuntimePolicy`、`ToolExecutor`、`SupervisorManager` 已切到 `xtResolveProjectRuntimeSurfacePolicy(...)` / `effectiveRuntimeSurface` / `runtimeSurfaceMode` 路径，project snapshot、tool deny、supervisor focused context 不再继续扩散旧 `effectiveAutonomy` 命名。
  - 本轮目标不是做 schema break，而是把 XT-W3-36 主链代码改成 `runtimeSurface-first, autonomy-compatible`，继续保持 release gate / docs truth / 老项目磁盘兼容并存。

### 2026-03-19

- 已继续收口 project-core 治理层的 compat 尾巴：
  - `AXProjectResolvedGovernanceState` 现在以 `effectiveRuntimeSurface` 作为主存储字段，`effectiveAutonomy` 退为 compat alias，避免 project-core 继续向外扩散旧名。
  - `AXProjectGovernanceResolver` 的主路径已统一写回 `effectiveRuntimeSurface`，并优先按 `config.runtimeSurfaceMode` 推导 legacy autonomy-mode 兼容映射。
  - `AXProjectGovernanceTemplate` 内部 spec/snapshot 已切到 `runtimeSurfaceMode` / `runtimeSurfaceClamp`，模板匹配、configured/effective posture 解释、runtime summary 全部改为 runtime surface 语义；`xtAutonomy*` 旧 helper 继续保留为 deprecated alias。
  - `debugSnapshot()` 已补发 `runtime_surface_*` 主字段，同时继续保留 `effective_autonomy_mode` / `autonomy_*` 兼容字段，方便外部消费者渐进迁移。
- 本轮验证结果：
  - `swift test --filter ProjectGovernanceResolverTests` 通过，9 tests passed。
  - `swift test --skip-build --filter AXProjectGovernanceTemplateTests` 通过，11 tests passed。
  - `swift test --skip-build --filter ProjectGovernancePresentationSummaryTests` 通过，6 tests passed。
  - `swift test --skip-build --filter ProjectGovernanceDocsTruthSyncTests` 通过，3 tests passed。

- 已继续收口 Hub/AppModel 边界层的 runtime-surface-first 迁移：
  - `HubIPCClient` 新增 `RuntimeSurfaceOverrideItem` / `RuntimeSurfaceOverridesSnapshot`、`requestRuntimeSurfaceOverrides(...)`、`requestProjectRuntimeSurfaceOverride(...)`，同时保留 `AutonomyPolicy*` compat alias，避免远端 override IPC 一次性断线。
  - `AppModel` 已切到 `projectRemoteRuntimeSurfaceOverride` / `refreshProjectRemoteRuntimeSurfaceOverride(...)` / `nextProjectRuntimeSurfaceOverrideRefreshAt` 主路径；project raw log 也优先写 `cfg.runtimeSurfaceMode`、`cfg.runtimeSurfaceTTLSeconds`、`cfg.runtimeSurfaceHubOverrideMode` 与 `resolved.effectiveRuntimeSurface`。
  - `xtResolveProjectRuntimeSurfacePolicy(...)`、`xtResolveProjectGovernance(...)` 与 `HubRemoteAutonomyPolicyOverrideCache` 的内部 snapshot/storage 已对齐 runtime surface 命名，保持 on-disk `autonomy_policy_overrides_status.json` 与老桥接字段继续兼容。
  - `XTW330RuntimeSurfacePolicyEvidenceTests` 已改用新的 runtime surface override API，避免 compat wrapper 在全量测试编译时持续刷 deprecated 警告。
  - `work-orders/README.md` 已补齐 `XT-W3-39` 索引项，release gate 的 contract freeze 再次恢复通过。
- 本轮验证结果：
  - `swift test --filter HubIPCClientRuntimeSurfaceOverrideSnapshotTests` 通过，1 test passed。
  - `swift test --filter AppModelMultiProjectGovernanceTests` 通过，4 tests passed。
  - `swift test --filter ProjectModelGovernanceBindingTests` 通过，13 tests passed。
  - `swift test --filter ProjectGovernanceResolverTests` 通过，9 tests passed。
  - `swift test --filter AXProjectGovernanceTemplateTests` 通过，11 tests passed。
  - `swift test --filter ProjectGovernancePresentationSummaryTests` 通过，6 tests passed。
  - `swift test --filter ProjectGovernanceDocsTruthSyncTests` 通过，3 tests passed。
  - `XT_GATE_VALIDATE_PROJECT_GOVERNANCE=1 bash scripts/ci/xt_release_gate.sh` 通过，0 warning。

- 已继续收口 XT-W3-36 的测试名 / 文档语义尾巴：
  - `x-terminal/README.md` 已把该节主标题与正文切到 `Project Governance` / `A-Tier` / `S-Tier` / `Heartbeat / Review` 语义，不再把 project 总治理继续描述成单一 autonomy 表述。
  - `ProjectGovernanceDocsTruthSyncTests` 现额外锁定 `x-terminal/README.md` 的治理文案，防止后续再把旧 `Project Autonomy` 章节标题带回主路径。
  - `HubIPCClientRuntimeSurfaceOverrideSnapshotTests`、`XTToolRuntimePolicyGovernanceClampTests`、`ToolExecutorRuntimePolicyTests`、`ProjectDetailGovernanceSummaryTests`、`AXProjectGovernedAuthorityPresentationTests` 已优先改用 `runtimeSurface` 命名与 `settingRuntimeSurfacePolicy(...)`，仅在需要兼容断言的地方继续校验旧 `autonomy_*` 字段。
  - `AXProjectGovernanceSurfaceExplanation` 的英文 TTL 文案也已收口到 `runtime-surface window`，避免用户侧继续看到 `autonomy window` 这类旧语义。

- 已继续收口 Hub pairing / remote bridge 的 runtime-surface-first 命名尾巴：
  - `HubPairingCoordinator` 新增 `HubRemoteRuntimeSurfaceOverrideItem` / `HubRemoteRuntimeSurfaceOverridesResult` 与 `fetchRemoteRuntimeSurfaceOverrides(...)` 主路径；旧 `HubRemoteAutonomyPolicy*` 类型和 `fetchRemoteAutonomyPolicyOverrides(...)` 继续保留为 deprecated compat alias。
  - 远端脚本生成器已切到 `remoteRuntimeSurfaceOverridesScriptSource()`，并优先读取 `XTERMINAL_RUNTIME_SURFACE_OVERRIDE_PROJECT_ID` / `XTERMINAL_RUNTIME_SURFACE_OVERRIDE_LIMIT`；同时保留旧 `XTERMINAL_AUTONOMY_OVERRIDE_*` fallback，避免桥接脚本与旧环境变量断裂。
  - `HubIPCClient.requestRuntimeSurfaceOverrides(...)` 已改为调用新的 pairing coordinator 主路径，因此 XT 当前从 Hub pairing、IPC cache、resolver 到 AppModel 的 override 拉取链路已经 runtime-surface-first。
  - `HubRemoteRuntimeSurfaceOverrideCache` 也已成为主类型，`HubRemoteAutonomyPolicyOverrideCache` 退为 compat alias，XT 侧 cache key / snapshot 存储链路不再继续扩散旧 autonomy 命名。
  - 这轮没有去改 Hub gRPC 方法名、落盘文件名、reason code 文本；`GetAutonomyPolicyOverrides`、`autonomy_policy_overrides_status.json`、`remote_autonomy_policy_overrides_failed` 仍继续保留，避免误做 on-wire / evidence schema break。
- 本轮验证结果补充：
  - `swift test --filter HubIPCClientRuntimeSurfaceOverrideSnapshotTests` 通过，1 test passed。
  - `XT_GATE_VALIDATE_PROJECT_GOVERNANCE=1 bash scripts/ci/xt_release_gate.sh` 再次通过，0 warning。

- 已继续收口 XT-W3-36 最后一段 release/doc 尾巴：
  - `AXProjectConfigAutomationRecipeTests` 已随 runtime-surface-first API 命名完成收口，`runtimeSurfacePresetPersistsAndClampTakesEffect` 与 `runtimeSurfaceTTLExpiryFailsClosedToManual` 现在直接覆盖 `effectiveRuntimeSurfacePolicy(...)` 主路径，避免新测试继续反向放大旧 `effectiveAutonomyPolicy(...)` 命名。
  - `docs/WORKING_INDEX.md` 已补回 `xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md`、`A-Tier` / `S-Tier` / `Heartbeat / Review` / `A4 Agent` 产品真相，以及 `xt_w3_36_project_governance_evidence.sh`、`xt_release_gate.sh`、`ProjectGovernanceDocsTruthSyncTests.swift` 三个发布/对齐入口。
  - `x-terminal/work-orders/README.md` 现已明确 `XT-W3-36-B` 是 `Completed child pack`，并把 `A0..A4`、`S0..S4`、`A4 Agent`、治理 evidence hook 写回主入口；同时补回缺失的 `xt-w3-08-release-gate-skeleton.md` 与 `xt-w3-29-whisperkit-funasr-voice-runtime-implementation-pack-v1.md` 索引项，修复 contract freeze 对 work-order index 的 NO_GO。
  - 经过这轮修复后，当前 XT-W3-36 主链剩余的旧 `autonomy_*` 命名已主要收束到有意保留的 compat wrapper / on-wire / on-disk 证据字段，不再是主路径 UI、resolver、runtime policy 或 release 索引的事实来源。
- 已继续收口 Hub pairing / IPC 链路中的旧 autonomy 散点：
  - `HubIPCClient` 现已把本地 runtime-surface override 的兼容边界集中到 `RuntimeSurfaceOverrideCompatContract`，并统一由 `readLocalRuntimeSurfaceOverrides(...)` 使用；兼容文件名 `autonomy_policy_overrides_status.json` 与兼容 source `hub_autonomy_policy_overrides_file` 仍保留，但不再在主路径里散落硬编码。
  - `HubPairingCoordinator` 现已把远端 runtime-surface override 的 compat token 收口到 `HubRemoteRuntimeSurfaceCompatContract`；兼容 failure reason、旧环境变量 `XTERMINAL_AUTONOMY_OVERRIDE_*`、以及 gRPC 方法 `GetAutonomyPolicyOverrides` 仍保留，但只作为协议边界存在，不再作为业务语义命名继续扩散。
  - 这轮没有改变远端脚本兼容行为：旧 env fallback、旧 RPC 方法名、旧 reason code 仍继续工作，因此 pairing / file-IPC / report evidence 不需要迁移。
- 验证过程中顺手修掉一个现有编译挡板：
  - `AXSkillsLibrary+HubCompatibility.swift` 的 `renderCompatibilityExplainability(...)` 调用少传了 `builtinGovernedSkills`，已补齐，避免 unrelated compile error 挡住 XT-W3-36 的聚焦验证。
- 本轮验证结果再补充：
  - `swift test --filter AXProjectConfigAutomationRecipeTests` 通过，13 tests passed。
  - `swift test --filter ProjectGovernanceResolverTests` 通过，9 tests passed。
  - `swift test --filter XTToolRuntimePolicyGovernanceClampTests` 通过，5 tests passed。
  - `swift test --filter HubIPCClientRuntimeSurfaceOverrideSnapshotTests` 通过，1 test passed。
  - `swift test --filter ProjectGovernanceDocsTruthSyncTests` 通过，3 tests passed。
  - `XT_GATE_VALIDATE_PROJECT_GOVERNANCE=1 bash scripts/ci/xt_release_gate.sh` 通过，0 warning。
  - 再次验证：`swift test --filter HubIPCClientRuntimeSurfaceOverrideSnapshotTests`、`swift test --filter ProjectGovernanceResolverTests`、`swift test --filter XTToolRuntimePolicyGovernanceClampTests` 与 `XT_GATE_VALIDATE_PROJECT_GOVERNANCE=1 bash scripts/ci/xt_release_gate.sh` 均通过，0 warning。

- 已继续收口 Hub 接入链路里的 runtime-surface-first compat 边界：
  - `HubIPCClient` 内部私有落盘结构已从 `LocalAutonomyPolicyOverride*` 翻正为 `LocalRuntimeSurfaceOverride*`，主路径不再让新的本地 file-IPC 解析逻辑继续扩散旧 autonomy 语义；但 `autonomy_policy_overrides_status.json` 与 `hub_autonomy_policy_overrides_file` 仍刻意保留，避免打破现有 on-disk evidence / IPC contract。
  - 新增 `HubRuntimeSurfaceCompatibilityBoundaryTests`，静态锁定当前边界：
    - 主路径名称必须是 `RuntimeSurfaceOverride*` / `fetchRemoteRuntimeSurfaceOverrides(...)`
    - 旧 `AutonomyPolicy*` 只能继续作为 deprecated wrapper / compat alias
    - `GetAutonomyPolicyOverrides`、`autonomy_policy_overrides_status.json`、`remote_autonomy_policy_overrides_failed` 这类 wire / file / reason code 兼容信号必须保留
- 本轮验证结果继续补充：
  - `swift test --filter HubRuntimeSurfaceCompatibilityBoundaryTests` 通过，2 tests passed。
  - `swift test --filter HubIPCClientRuntimeSurfaceOverrideSnapshotTests` 通过，1 test passed。
  - `swift test --filter ProjectGovernanceDocsTruthSyncTests` 通过，3 tests passed。
  - `XT_GATE_VALIDATE_PROJECT_GOVERNANCE=1 bash scripts/ci/xt_release_gate.sh` 通过，0 warning。

- 已继续收口 XT-W3-36 的 project-core runtime-surface compat 边界：
  - `AppModel` 现已把 `setProjectAutonomyPolicy(...)` 与 `resolvedProjectAutonomyPolicy(...)` 明确标记为 deprecated compat wrapper，主入口保持为 `setProjectRuntimeSurfacePolicy(...)` / `resolvedProjectRuntimeSurfacePolicy(...)`；`projectRemoteAutonomyOverride`、`applyProjectAutonomyProfile(...)`、`autonomySwitchboardPresentation(...)` 继续只作为兼容壳存在。
  - `AXProjectRuntimeSurfacePolicy.swift` 现已把 `configuredAutonomySurfaceLabels`、`settingAutonomyPolicy(...)`、`autonomyUpdatedAtDate`、`xtResolveProjectAutonomyPolicy(...)` 与整组 `AXProjectAutonomy*` typealias 显式降级为 deprecated compat API，避免新的项目核心调用继续把旧 autonomy 命名当成主路径。
  - `XTW330RuntimeSurfacePolicyEvidenceTests` 与 `AXProjectConfigAutomationRecipeTests` 已切到 `setProjectRuntimeSurfacePolicy(...)` / `settingRuntimeSurfacePolicy(...)` / `effectiveRuntimeSurfacePolicy(...)` 主链，避免主测试继续依赖 compat wrapper。
  - 新增 `ProjectRuntimeSurfaceCompatibilityBoundaryTests`，静态锁定项目核心当前边界：
    - `AppModel` 主入口必须是 runtime-surface 命名
    - `AXProjectRuntimeSurfacePolicy.swift` 主 API 必须是 `settingRuntimeSurfacePolicy(...)` / `effectiveRuntimeSurfacePolicy(...)` / `xtResolveProjectRuntimeSurfacePolicy(...)`
    - 旧 `autonomy` 入口只能继续以 deprecated compat wrapper / typealias 形式存在
- 本轮验证结果再补充：
  - `swift test --filter ProjectRuntimeSurfaceCompatibilityBoundaryTests` 通过，2 tests passed。
  - `swift test --filter XTW330RuntimeSurfacePolicyEvidenceTests` 通过，1 test passed。
  - `swift test --filter AXProjectConfigAutomationRecipeTests` 通过，13 tests passed。
  - `swift test --filter ProjectGovernanceDocsTruthSyncTests` 通过，3 tests passed。
  - `XT_GATE_VALIDATE_PROJECT_GOVERNANCE=1 bash scripts/ci/xt_release_gate.sh` 通过，0 warning。
