# XT-W3-26 / XT-W3-27 四 AI 并行派发包

- version: v1.0
- updatedAt: 2026-03-07
- owner: AI-COORD-PRIMARY（Dispatch）/ XT-L2 / Hub-L5 / QA
- status: active
- scope: `XT-W3-26` + `XT-W3-27` 的 4 AI 并行派发与低冲突收口
- parent:
  - `x-terminal/work-orders/xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-27-hub-xt-ui-productization-r1-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-28-jamless-anti-congestion-protocol-implementation-pack-v1.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`

## 0) 目标

把以下两份实现包拆成 4 个 AI 可并行执行的派发版，同时尽量降低以下风险：

- 多 AI 同改一批文件导致冲突
- A 等 B、B 等 C 的串行阻塞
- UI AI 等待后端完全落地才敢开工
- 后端 AI 为了等 UI 合入才推进状态机与证据

本派发包的原则是：

- 先按冻结契约并行，不等代码落地再开工。
- 用“文件写入边界 + 契约边界 + directed handoff”控冲突。
- 所有 AI 都只 claim 自己这一包，不并行 formal claim 第二包。
- 优先形成 4 份可合并的增量，而不是 1 份大而全的串行改动。

## 1) 四 AI 切分总览

### 1.1 AI-1 `XT-OS-CORE`

- 负责范围：`XT-W3-26-A/B/C/D`
- 角色：一次性接案主链的核心契约、规划器、并发治理、运行状态机
- 主输出：`one-shot intake + adaptive pool planner + seat governor + run state`

### 1.2 AI-2 `XT-OS-RUNTIME`

- 负责范围：`XT-W3-26-E/F/G/H`
- 角色：安全自动启动、定向解阻、交付冻结、回放证据
- 主输出：`safe auto-launch + directed unblock baton + delivery freeze + replay harness`

### 1.3 AI-3 `XT-UI-PRIMARY`

- 负责范围：`XT-W3-27-A/B/C/D`
- 角色：XT 主信息架构、设计 tokens、Global Home、Supervisor Cockpit
- 主输出：`XT 端主路径 UI`

### 1.4 AI-4 `HUB-UI-INTEGRATION`

- 负责范围：`XT-W3-27-E/F/G/H`
- 角色：Hub Setup Wizard、XT Settings Center、Hub Settings Center、UI 回归与 telemetry
- 主输出：`Hub/XT 设置与首用路径 + UI 机读回归`

## 2) 文件写入边界

### 2.1 AI-1 可写文件

- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- `x-terminal/Sources/Supervisor/TaskDecomposition/TaskDecomposer.swift`
- `x-terminal/Sources/Supervisor/IntakeAcceptanceContracts.swift`
- `x-terminal/Sources/Supervisor/PoolIntegrationOrchestrator.swift`
- `x-terminal/Sources/Supervisor/CriticalPathSeatAllocator.swift`
- 新增：
  - `x-terminal/Sources/Supervisor/OneShotIntakeCoordinator.swift`
  - `x-terminal/Sources/Supervisor/AdaptivePoolPlanner.swift`
  - `x-terminal/Sources/Supervisor/OneShotRunStateStore.swift`
- 测试建议落点：
  - `x-terminal/Tests/SupervisorOneShotIntakeTests.swift`
  - `x-terminal/Tests/AdaptivePoolPlannerTests.swift`

### 2.2 AI-2 可写文件

- `x-terminal/Sources/Supervisor/SupervisorOrchestrator.swift`
- `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
- 新增：
  - `x-terminal/Sources/Supervisor/DirectedUnblockRouter.swift`
  - `x-terminal/Sources/Supervisor/DeliveryScopeFreezeStore.swift`
  - `x-terminal/Sources/Supervisor/OneShotReplayHarness.swift`
- 测试建议落点：
  - `x-terminal/Tests/SupervisorAutoLaunchPolicyTests.swift`
  - `x-terminal/Tests/DirectedUnblockRouterTests.swift`
  - `x-terminal/Tests/DeliveryScopeFreezeTests.swift`

### 2.3 AI-3 可写文件

- `x-terminal/Sources/UI/GlobalHomeView.swift`
- `x-terminal/Sources/Supervisor/SupervisorView.swift`
- 新增：
  - `x-terminal/Sources/UI/Components/PrimaryActionRail.swift`
  - `x-terminal/Sources/UI/Components/StatusExplanationCard.swift`
  - `x-terminal/Sources/UI/Components/ValidatedScopeBadge.swift`
  - `x-terminal/Sources/UI/Design/UIThemeTokens.swift`
- 测试建议落点：
  - `x-terminal/Tests/GlobalHomeViewModelTests.swift`
  - `x-terminal/Tests/SupervisorCockpitStateMappingTests.swift`

### 2.4 AI-4 可写文件

- `x-terminal/Sources/UI/HubSetupWizardView.swift`
- `x-terminal/Sources/UI/SettingsView.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
- 新增：
  - `x-terminal/Sources/UI/Components/TroubleshootPanel.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/UI/HubSectionCard.swift`
  - `x-terminal/Tests/UIFirstRunJourneyTests.swift`
  - `x-terminal/Tests/UITroubleshootingPathTests.swift`
- 机读证据落点：
  - `build/reports/xt_w3_27_h_ui_regression_evidence.v1.json`
  - `build/reports/xt_w3_27_first_run_journey_evidence.v1.json`

### 2.5 硬规则

- AI-1 不写 `SupervisorView.swift`。
- AI-2 不写 `GlobalHomeView.swift`、`HubSetupWizardView.swift`、`SettingsView.swift`。
- AI-3 不写 `SupervisorManager.swift`、`SupervisorOrchestrator.swift`。
- AI-4 不写 `SupervisorManager.swift`、`SupervisorOrchestrator.swift`、`SupervisorView.swift`。
- 任何 AI 如需跨边界修改，先回 `blocked_by_write_boundary`，由总控裁决，不可擅自覆盖。

## 3) 依赖与去阻塞规则

### 3.1 默认规则

- 4 个 AI 都可以立刻开工，不需要等待别的 AI 先把代码落地。
- 统一以以下冻结契约为开工基线：
  - `xt.supervisor_one_shot_intake_request.v1`
  - `xt.adaptive_pool_plan_decision.v1`
  - `xt.one_shot_autonomy_policy.v1`
  - `xt.one_shot_run_state.v1`
  - `xt.unblock_baton.v1`
  - `xt.delivery_scope_freeze.v1`
  - `xt.ui_information_architecture.v1`
  - `xt.ui_design_token_bundle.v1`
  - `xt.ui_surface_state_contract.v1`
  - `xt.ui_troubleshooting_path.v1`
  - `xt.ui_first_run_journey.v1`
  - `xt.ui_release_scope_badge.v1`

### 3.2 真正的最小依赖边

- AI-1 -> AI-2
  - 提供：`run state` 字段、planner decision 字段、seat governor 输出字段。
  - AI-2 在这些字段未全部落地前，仍可先做 policy/router/freeze/harness 框架，不等待实现完成。
- AI-1 -> AI-3
  - 提供：Supervisor cockpit 需要读取的 `state / explain / next action / active pools / blockers` 字段。
  - AI-3 可先做 mock state mapping，不等待后端完成。
- AI-2 -> AI-3
  - 提供：`delivery_scope_freeze`、`grant_required`、`blocked/resuming` 的状态语义。
  - AI-3 先按冻结契约做 UI，占位映射即可。
- AI-3 -> AI-4
  - 提供：XT 侧 IA/token/state badge 语义。
  - AI-4 在 token 最终落地前可先推进 Hub Setup / Settings 信息架构和排障路径。

### 3.3 禁止的阻塞理由

以下理由不构成 allowed blocker：

- “等别的 AI 先把代码写完我再开始”
- “等 UI 全定了我再写状态机”
- “等状态机全落地我再做 UI”
- “等 Hub 那边全改完我再做 XT 设置页”

只允许以下 blocker：

- 缺冻结契约字段，且无法通过本派发包与父包推断
- 写入边界冲突
- 关键测试/编译入口因外部环境不可达而无法继续
- 发现父包与代码现状存在 hard contradiction

## 4) 并行执行顺序

### 4.1 Wave-1 立即开工

- AI-1：落 `XT-W3-26-A/B/C/D`
- AI-2：落 `XT-W3-26-E/F/G/H` 框架与测试壳
- AI-3：落 `XT-W3-27-A/B/C/D`
- AI-4：落 `XT-W3-27-E/F/G/H` 的 IA/排障/测试框架

### 4.2 Wave-2 交叉绑定

- AI-2 消费 AI-1 的 state/planner 字段实现实际 runtime 绑定
- AI-3 消费 AI-1/AI-2 的 state 语义，绑定真实 cockpit 数据
- AI-4 消费 AI-3 的 token/status 组件，对齐 Hub/XT 视觉与排障路径

### 4.3 Wave-3 收口

- AI-1/AI-2 合并 one-shot 主链与 delivery freeze
- AI-3/AI-4 合并首用路径、设置中心、release scope badge
- QA / 总控只在此时做跨包验收，不要在 Wave-1 打断

## 5) 每个 AI 的任务明细

### 5.1 AI-1 `XT-OS-CORE`

#### Claim

- `XT-W3-26-A`
- `XT-W3-26-B`
- `XT-W3-26-C`
- `XT-W3-26-D`

#### 必做

1. 落 `one-shot intake request` 归一化入口。
2. 落 `adaptive pool planner` 与 explain 字段。
3. 落 `seat/lane cap` 治理，不允许 lane explosion。
4. 落显式 `one-shot run state machine`。
5. 补 tests 与机读 evidence。

#### DoD

- 同输入同配置规划可复现。
- `cross_pool_cycle_allowed = 0`
- `lane_cap_violations = 0`
- `run state` 字段足够给 UI 与 runtime 消费。

#### 交接给谁

- To: AI-2, AI-3
- 交接内容：字段冻结、状态枚举、planner explain 示例、测试结果、evidence refs

### 5.2 AI-2 `XT-OS-RUNTIME`

#### Claim

- `XT-W3-26-E`
- `XT-W3-26-F`
- `XT-W3-26-G`
- `XT-W3-26-H`

#### 必做

1. 落 `safe auto-confirm + auto-launch` 策略层。
2. 落 `directed unblock baton`，禁止广播式续推。
3. 落 `delivery scope freeze` 与对外表述约束。
4. 落 replay / regression harness。
5. 补 tests 与机读 evidence。

#### DoD

- `unsafe_auto_launch = 0`
- `blocked_to_directed_resume_p95_ms <= 3000`
- `delivery_scope_expansion_without_replan = 0`
- replay harness 可覆盖 `grant_required / permission_denied / runtime_error / scope_expansion`

#### 交接给谁

- To: AI-3, AI-4
- CC: AI-1
- 交接内容：状态语义、blocker/resume/freeze 数据面、测试结果、evidence refs

### 5.3 AI-3 `XT-UI-PRIMARY`

#### Claim

- `XT-W3-27-A`
- `XT-W3-27-B`
- `XT-W3-27-C`
- `XT-W3-27-D`

#### 必做

1. 冻结 XT 主信息架构与 design tokens。
2. 重做 `Global Home` 主入口。
3. 重做 `Supervisor Cockpit`，把 `one-shot intake + explain + blocker + scope freeze` 做成主叙事。
4. 补状态卡、主操作栏、validated scope badge。
5. 补 tests 与机读 evidence。

#### DoD

- 首页主 CTA 清晰指向“开始大任务”。
- Supervisor cockpit 能显示 `what happened / why / next action`。
- `validated scope badge` 不缺失。
- 视觉语义能给 AI-4 复用。

#### 交接给谁

- To: AI-4
- CC: AI-1, AI-2
- 交接内容：tokens、badge/state 语义、公共组件、截图或 evidence refs

### 5.4 AI-4 `HUB-UI-INTEGRATION`

#### Claim

- `XT-W3-27-E`
- `XT-W3-27-F`
- `XT-W3-27-G`
- `XT-W3-27-H`

#### 必做

1. 重做 `Hub Setup Wizard`，打通配对 -> 模型源 -> grant -> smoke。
2. 重做 XT 设置中心。
3. 重构 Hub 设置中心，把配对、模型、grant、安全、诊断分区。
4. 落 `grant_required / permission_denied / hub_unreachable` 三大排障路径。
5. 补 telemetry / regression harness / 机读 evidence。

#### DoD

- `grant_troubleshoot_primary_fix_steps <= 3`
- 首用路径可跑通 `pair -> choose model -> resolve grant -> start first task`
- Hub/XT settings 分区明确，用户能找到模型、grant、安全、日志四类设置
- UI regression evidence 可机判

#### 交接给谁

- To: QA / AI-COORD-PRIMARY
- CC: AI-3
- 交接内容：首用路径结果、排障路径结果、settings 重构结果、evidence refs

## 6) 合并顺序

1. 先合 AI-1，再合 AI-2
2. 再合 AI-3，再合 AI-4
3. 之后跑一次跨包 smoke：
   - one-shot intake
   - grant_required
   - permission_denied
   - hub_unreachable
   - validated-mainline-only release scope

原因：

- `XT-W3-26` 是 `XT-W3-27` 的数据与状态基础。
- AI-3 的 tokens / state components 是 AI-4 对齐 Hub/XT 视觉的基础。
- 先合后端主链，再合表层 UI，能减少返工。

## 7) 回复格式要求

每个 AI 的回复顶部必须包含：

- `To:`
- `CC:`
- `不用发给:`
- `原因:`

正文统一用 `full_7piece` 或 `delta_3line`，且必须包含：

- `status`
- `scope`
- `changes`
- `verification`
- `blockers`
- `next_action`
- `evidence_refs`

## 8) 四条可直接派发的首条提示词

### 8.1 发给 AI-1

```text
To: AI-1 (XT-OS-CORE)
CC: none
不用发给: AI-2, AI-3, AI-4
原因: 你负责 XT-W3-26 的核心主链，先把 one-shot intake / adaptive pool planner / seat governor / run state 落稳，给后续 runtime 和 UI 提供稳定数据面。

请严格按以下工单执行，不要扩 scope：
- x-terminal/work-orders/xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md
- x-terminal/work-orders/xt-w3-26-w3-27-4ai-parallel-dispatch-pack-v1.md
- docs/memory-new/xhub-lane-command-board-v2.md

你的 claim 仅限：XT-W3-26-A/B/C/D。
你的可写文件仅限：
- x-terminal/Sources/Supervisor/SupervisorManager.swift
- x-terminal/Sources/Supervisor/TaskDecomposition/TaskDecomposer.swift
- x-terminal/Sources/Supervisor/IntakeAcceptanceContracts.swift
- x-terminal/Sources/Supervisor/PoolIntegrationOrchestrator.swift
- x-terminal/Sources/Supervisor/CriticalPathSeatAllocator.swift
- 以及派发包允许新增的 AI-1 自有文件。

硬要求：
- 先按冻结契约并行开工，不等待别的 AI 代码落地。
- 不要写 SupervisorView.swift / GlobalHomeView.swift / HubSetupWizardView.swift。
- fail-closed；不允许 lane explosion；不允许 cross-pool cycle 放行。
- 输出必须带 To/CC/不用发给/原因。

本轮目标：完成 XT-W3-26-A/B/C/D 的首个可编译增量、tests、machine-readable evidence，并向 AI-2 + AI-3 定向交接字段冻结和 evidence refs。
```

### 8.2 发给 AI-2

```text
To: AI-2 (XT-OS-RUNTIME)
CC: none
不用发给: AI-1, AI-3, AI-4
原因: 你负责 XT-W3-26 的 runtime 主链，先把 safe auto-launch / directed unblock / delivery freeze / replay harness 落稳，避免继续依赖广播式续推。

请严格按以下工单执行，不要扩 scope：
- x-terminal/work-orders/xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md
- x-terminal/work-orders/xt-w3-26-w3-27-4ai-parallel-dispatch-pack-v1.md
- docs/memory-new/xhub-lane-command-board-v2.md

你的 claim 仅限：XT-W3-26-E/F/G/H。
你的可写文件仅限：
- x-terminal/Sources/Supervisor/SupervisorOrchestrator.swift
- x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift
- 以及派发包允许新增的 AI-2 自有文件。

硬要求：
- 先按冻结契约开工，不等待 AI-1 全部代码落地；可先做 policy/router/freeze/harness 框架。
- 不要写 GlobalHomeView.swift / SupervisorView.swift / HubSetupWizardView.swift / SettingsView.swift。
- 禁止广播式续推；必须 directed unblock baton。
- delivery scope 必须 freeze；不允许 scope expansion。
- 输出必须带 To/CC/不用发给/原因。

本轮目标：完成 XT-W3-26-E/F/G/H 的首个可编译增量、tests、machine-readable evidence，并向 AI-3 + AI-4 定向交接状态语义和 evidence refs。
```

### 8.3 发给 AI-3

```text
To: AI-3 (XT-UI-PRIMARY)
CC: none
不用发给: AI-1, AI-2, AI-4
原因: 你负责 XT 主路径 UI，先把 Global Home / Supervisor Cockpit / IA / design tokens 做成产品入口，不等后端全部完成再动手。

请严格按以下工单执行，不要扩 scope：
- x-terminal/work-orders/xt-w3-27-hub-xt-ui-productization-r1-implementation-pack-v1.md
- x-terminal/work-orders/xt-w3-26-w3-27-4ai-parallel-dispatch-pack-v1.md
- docs/memory-new/xhub-lane-command-board-v2.md

你的 claim 仅限：XT-W3-27-A/B/C/D。
你的可写文件仅限：
- x-terminal/Sources/UI/GlobalHomeView.swift
- x-terminal/Sources/Supervisor/SupervisorView.swift
- 以及派发包允许新增的 AI-3 自有文件。

硬要求：
- 先按冻结契约和 mock state mapping 开工，不等待 AI-1/AI-2 完全落地。
- 不要写 SupervisorManager.swift / SupervisorOrchestrator.swift / HubSetupWizardView.swift / SettingsView.swift / Hub SettingsSheetView.swift。
- UI 必须清楚表达 what happened / why / next action。
- 必须显示 validated-mainline-only / validated scope badge。
- 输出必须带 To/CC/不用发给/原因。

本轮目标：完成 XT-W3-27-A/B/C/D 的首个可运行 UI 增量、tests、machine-readable evidence，并向 AI-4 定向交接 tokens / state components / evidence refs。
```

### 8.4 发给 AI-4

```text
To: AI-4 (HUB-UI-INTEGRATION)
CC: none
不用发给: AI-1, AI-2, AI-3
原因: 你负责首用路径、设置中心和 Hub UI 收口，先把 pairing / model / grant / troubleshooting / settings IA 做成可用主链，并补 UI regression evidence。

请严格按以下工单执行，不要扩 scope：
- x-terminal/work-orders/xt-w3-27-hub-xt-ui-productization-r1-implementation-pack-v1.md
- x-terminal/work-orders/xt-w3-26-w3-27-4ai-parallel-dispatch-pack-v1.md
- docs/memory-new/xhub-lane-command-board-v2.md

你的 claim 仅限：XT-W3-27-E/F/G/H。
你的可写文件仅限：
- x-terminal/Sources/UI/HubSetupWizardView.swift
- x-terminal/Sources/UI/SettingsView.swift
- x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift
- 以及派发包允许新增的 AI-4 自有文件。

硬要求：
- 先按冻结契约开工，不等待 AI-3 token 完全落地；可先推进信息架构、排障路径、测试框架。
- 不要写 SupervisorManager.swift / SupervisorOrchestrator.swift / SupervisorView.swift / GlobalHomeView.swift。
- grant_required / permission_denied / hub_unreachable 必须 3 步内可定位到修复入口。
- 输出必须带 To/CC/不用发给/原因。

本轮目标：完成 XT-W3-27-E/F/G/H 的首个可运行 UI/设置增量、tests、machine-readable evidence，并向 QA / 总控交接首用路径、排障路径和 settings evidence refs。
```

## 9) 发布判定

这 4 个 AI 的增量只有在以下条件同时满足时，才算本派发包完成：

- `XT-W3-26` 与 `XT-W3-27` 两个父包的子工单都已有 claim owner 与机读证据。
- 4 个 AI 的写入边界没有互相覆盖。
- one-shot 主链与 UI 主路径至少各有一轮真实可运行 smoke。
- 关键失败场景 `grant_required / permission_denied / hub_unreachable / scope_expansion` 全部 fail-closed 或正确指引修复。
