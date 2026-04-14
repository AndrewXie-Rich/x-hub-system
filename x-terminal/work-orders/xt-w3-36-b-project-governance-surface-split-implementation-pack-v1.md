# XT-W3-36-B Project Governance Surface Split Implementation Pack v1

- version: `v1.0`
- updatedAt: `2026-03-18`
- owner: XT-L2（Primary）/ Product / Design / QA
- status: `completed`
- scope: `XT-W3-36-B1..B7`（把当前“治理 chip -> 同一设置页内滚动定位”的退化实现，收口回协议要求的三根独立拨盘产品面：`A-Tier`、`S-Tier`、`Heartbeat / Review`）
- parent:
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `X_MEMORY.md`

## 0.1) 当前实现进度

- `B1` 已落地：治理入口已从 section-scroll 升级为 destination 路由。
- `B2` 已落地：`A-Tier` 有独立编辑页，并保持 `A0..A4` 完整显示。
- `B3` 已落地：`S-Tier` 有独立编辑页，并保持 `S0..S4` 完整显示。
- `B4` 已落地：`Heartbeat / Review` 独立成页，并复用治理 activity / schedule 时间线。
- `B5` 已落地：`CreateProjectSheet` 改为三轴治理 composer，不再塞进一个 advanced governance 大表单。
- `B6` 已落地：README / WORKING_INDEX / work-order README 已对齐 `A4 Agent` 与三页治理面口径。
- `B7` 已落地：
  - destination 解析与 settings focus 回归已补
  - docs truth-sync 回归已补
  - create flow 档位切换与 trigger 归一化回归已补
  - detail summary 三轴治理展示回归已补
  - create flow 三轴 destination card / 共享 editorCases 回归已补

## 0) 为什么单开这份包

当前 runtime / contract 层其实已经是对的：

- `A-Tier` 仍然是 `A0..A4`
- `S-Tier` 仍然是 `S0..S4`
- `Heartbeat / Review / intervention` 仍然是独立治理轴

但产品表面已经发生了一次明显漂移：

- 项目侧治理 chip 点进去，实际上只是打开同一个 `ProjectSettingsView` 再滚到不同 section
- `A-Tier`、`S-Tier`、`Review cadence` 仍然堆在一个治理块里
- `CreateProjectSheet` 也还是把三根治理轴塞进同一个 advanced disclosure
- README 已经把“治理面已经清晰暴露”说得比当前真实 UX 更早

这会直接造成三个问题：

1. 用户看见的是“好像分开了”，实际上还是一个模糊大设置页。
2. `A-Tier` 和 `S-Tier` 很容易再次被误解成一个组合档位。
3. `Heartbeat / Review`、`review depth`、`guidance` 这些本来应该独立的东西，又会被重新拖回“Autonomy 大杂烩”。

所以这份包的目标不是新增协议，而是把已经冻结的协议，重新做成用户能看懂、能点对、不会误解的治理界面。

## 1) 一句话冻结决策

冻结：

- 项目治理继续是三根独立拨盘，不回退成单一总治理大滑杆。
- `A-Tier` 必须完整显示 `A0..A4`。
- `S-Tier` 必须完整显示 `S0..S4`。
- `A-Tier` 和 `S-Tier` 必须分别进入不同编辑页，不允许继续共享一个 section-scroll 页面。
- `Heartbeat / Review` 必须单独成页，不再只是 `ProjectSettingsView` 里的一个 stepper 区块。
- `A4` 的用户可见命名固定为 `A4 Agent`，不继续使用 `A4 OpenClaw` 或 `A4 Full Surface`。

## 2) v1 产品边界

### 2.1 本包必须做到

- 项目顶部治理条点击 `A?`，进入专门的 `A-Tier` 页面
- 点击 `S?`，进入专门的 `S-Tier` 页面
- 点击 `Heartbeat / Review`，进入专门的 `Heartbeat / Review` 页面
- 三个页面分别解释：
  - 这个拨盘控制什么
  - 不控制什么
  - 当前值
  - 生效值
  - 推荐值 / 最低安全值 / clamp 状态

### 2.2 本包暂不强行扩协议

当前协议里已有：

- `projectMemoryCeiling`
- `supervisorReviewMemoryCeiling`
- `progressHeartbeatSeconds`
- `reviewPulseSeconds`
- `brainstormReviewSeconds`

但还没有单独冻结一个“heartbeat view depth override”配置键。

因此本包先做：

- 在 `Heartbeat / Review` 页清晰展示当前 effective depth：
  - `coder context depth`
  - `supervisor review depth`
- 默认深度仍然跟随 `A-Tier / S-Tier`

如果后续产品确认要把“深度”也变成独立可编辑拨盘，再单开后续包扩 schema；本包不抢跑协议。

## 3) 当前偏差点

当前需要被显式纠正的偏差：

- `XTProjectSettingsFocusRequest` 还是 `sectionId` 语义，不是 destination 语义
- `ProjectSidebarView` 的治理 chip 还是用 `requestProjectSettingsFocus(... sectionId: ...)`
- `ProjectSettingsView` 仍然把 `A-Tier`、`S-Tier`、`Review Policy`、Heartbeat / Review steppers 堆在一个 `Project Governance` block
- `CreateProjectSheet` 的 advanced governance 仍是同一块表单
- README 里 “already exposes” 的口径比当前 UI 更超前

## 4) 详细执行拆分

### XT-W3-36-B1 Governance Destination Routing

- priority: `P0`
- 目标：把“section 滚动定位”升级成“治理子页面路由”。
- 代码落点：
  - `x-terminal/Sources/XTProjectSettingsFocusRequest.swift`
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/ContentView.swift`
  - `x-terminal/Sources/UI/ProjectSidebarView.swift`
  - `x-terminal/Sources/UI/Projects/ProjectDetailView.swift`
- 具体任务：
  1. 新增 `XTProjectGovernanceDestination`：
     - `overview`
     - `executionTier`
     - `supervisorTier`
     - `heartbeatReview`
  2. 把 `XTProjectSettingsFocusRequest` 从 `sectionId` 升级为 `destination`。
  3. `ContentView` 打开治理设置时，按 `destination` 进入对应页面，而不是只打开一个总表单。
  4. `ProjectSidebarView` 的三个治理 chip 分别改路由到三个独立 destination。
  5. `ProjectDetailView` 顶部治理摘要补齐同样的点击入口，不再只有文本概览。
- DoD：
  - 治理 chip 的点击不再依赖 `ScrollViewProxy.scrollTo(...)`
  - 任意入口进来的目标页都和用户点击的拨盘一致

### XT-W3-36-B2 A-Tier Dedicated Editor

- priority: `P0`
- 目标：做一个只编辑 `A0..A4` 的页面，不再混入 `S-Tier` 和 cadence。
- 代码落点：
  - 新增 `x-terminal/Sources/UI/ProjectExecutionTierView.swift`
  - `x-terminal/Sources/Project/AXProjectExecutionTier.swift`
  - `x-terminal/Sources/UI/ProjectGovernanceBadge.swift`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
- 具体任务：
  1. 用卡片或分段列表清晰展示 `A0..A4`：
     - 名称
     - 一句话说明
     - 默认 coder memory ceiling
     - 核心 capability bundle
     - 不允许的动作
     - 推荐 `S-Tier`
     - 最低安全 `S-Tier`
  2. 选中某个 `A-Tier` 时：
     - 更新 `executionTier`
     - 保留 review 轴已有设置
     - 如低于最低安全监督，给出即时 warning / clamp 解释
  3. 收口为 `A4 Agent` 命名。
  4. 页面内明确写出：
     - `A-Tier` 控制“能做什么”
     - 不控制 supervisor 盯多紧
- DoD：
  - 页面上完整可见 `A0..A4`
  - 用户不会在这个页面看到 `S-Tier` picker
  - `A4` 文案显示为 `Agent`

### XT-W3-36-B3 S-Tier Dedicated Editor

- priority: `P0`
- 目标：做一个只编辑 `S0..S4` 的页面，不再混入 repo/device 权限描述。
- 代码落点：
  - 新增 `x-terminal/Sources/UI/ProjectSupervisorTierView.swift`
  - `x-terminal/Sources/Project/AXProjectSupervisorInterventionTier.swift`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
- 具体任务：
  1. 用卡片或分段列表清晰展示 `S0..S4`：
     - 名称
     - 一句话说明
     - 默认 review memory ceiling
     - 默认 intervention mode
     - 是否要求 ack
     - 典型适用场景
  2. 选中某个 `S-Tier` 时：
     - 更新 `supervisorInterventionTier`
     - 如果低于当前 `A-Tier` 的最低安全值，页面上明确提示为什么不安全
  3. 页面内明确写出：
     - `S-Tier` 控制“supervisor 管多深”
     - 不控制 repo/device/browser 权限
- DoD：
  - 页面上完整可见 `S0..S4`
  - 用户不会把 `S-Tier` 误读成执行权限档位

### XT-W3-36-B4 Heartbeat / Review Dedicated Editor

- priority: `P0`
- 目标：把 `Heartbeat / Review cadence / brainstorm / triggers / guidance delivery context` 收口成单独页面。
- 代码落点：
  - 新增 `x-terminal/Sources/UI/ProjectHeartbeatReviewView.swift`
  - `x-terminal/Sources/UI/ProjectGovernanceActivityView.swift`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
- 具体任务：
  1. 页面拆成三组：
     - `Progress Heartbeat`
     - `Supervisor Review`
     - `Guidance & Safe Point`
  2. `Progress Heartbeat` 至少允许设置：
     - `progressHeartbeatSeconds`
     - heartbeat 展示说明
     - 当前 last/next heartbeat 状态
  3. `Supervisor Review` 至少允许设置：
     - `reviewPolicyMode`
     - `reviewPulseSeconds`
     - `brainstormReviewSeconds`
     - `eventDrivenReviewEnabled`
     - `eventReviewTriggers`
     - 当前 last/next pulse review / brainstorm review
  4. 页面显式展示当前 effective depth：
     - `coder context depth = projectMemoryCeiling`
     - `supervisor review depth = supervisorReviewMemoryCeiling`
  5. 页面显式展示 guidance 相关说明：
     - 当前 intervention mode
     - 是否 ack required
     - safe-point delivery 基线
  6. 复用 `ProjectGovernanceActivityView` 的时间线信息，避免 schedule 和 activity 两套 truth 分叉。
- DoD：
  - 用户不会再把 “heartbeat” 理解成 “supervisor review”
  - 页面上能清楚看到 cadence 和 depth 是两件事

### XT-W3-36-B5 Create Project Governance Composer

- priority: `P1`
- 目标：把 `CreateProjectSheet` 里的治理配置也恢复成三轴，不再塞成一个 advanced 大表单。
- 代码落点：
  - `x-terminal/Sources/UI/Projects/CreateProjectSheet.swift`
  - 复用：
    - `ProjectExecutionTierView` 的轻量卡片解释层
    - `ProjectSupervisorTierView` 的轻量卡片解释层
    - `ProjectHeartbeatReviewView` 的轻量 schedule form
- 具体任务：
  1. 创建项目页显示三个独立治理卡：
     - `A-Tier`
     - `S-Tier`
     - `Heartbeat / Review`
  2. 三张卡分别可进入各自的子编辑器，而不是展开同一段表单。
  3. 保留 governance template / bound project 逻辑，但不让 template 再把 A/S/Review 混成一个模糊“自治档位”。
  4. 明确显示初始默认值：
     - `A0..A4`
     - `S0..S4`
     - cadence summary
- DoD：
  - 创建项目时，A/S/review 三轴都能分别理解和分别设置
  - 切换 `A-Tier` 不会误重置 `S-Tier` 或 cadence

### XT-W3-36-B6 Copy, Naming, And Docs Truth Alignment

- priority: `P1`
- 目标：把产品文案、README 说法和当前真实治理面重新对齐。
- 代码落点：
  - `x-terminal/Sources/Project/AXProjectExecutionTier.swift`
  - `x-hub-system/README.md`
  - `x-hub-system/docs/WORKING_INDEX.md`
  - `x-hub-system/x-terminal/work-orders/README.md`
- 具体任务：
  1. 把 `A4 Full Surface` / `A4 OpenClaw` 统一改成 `A4 Agent`。
  2. 所有 UI 统一用：
     - `A-Tier`
     - `S-Tier`
     - `Heartbeat / Review`
  3. README 在 dedicated editors 落地前，避免继续使用 “already exposes” 这种比现状更超前的表述。
  4. 工作索引里把这份子包挂进 `XT-W3-36` 主线。
- DoD：
  - 文档口径不再超前于真实 UI
  - `A0/S0`、`A4 Agent` 的命名在产品和文档里一致

### XT-W3-36-B7 Regression, Snapshot, And UX Gates

- priority: `P0`
- 目标：防止治理 UI 再次退回“同页滚动 + 模糊大表单”。
- 代码落点：
  - `x-terminal/Tests/`
- 具体任务：
  1. 新增路由回归：
     - `A-Tier chip -> execution destination`
     - `S-Tier chip -> supervisor destination`
     - `Heartbeat chip -> heartbeatReview destination`
  2. 新增文案回归：
     - `A0..A4` 全可见
     - `S0..S4` 全可见
     - `A4 Agent` 可见
  3. 新增创建流程回归：
     - A/S/review 三轴独立
     - 修改一轴不误改另外两轴
  4. 新增快照/渲染回归：
     - 主页 governance badge
     - Execution editor
     - Supervisor editor
     - Heartbeat / Review editor
  5. 新增 README / index truth-sync 检查，防止文档再次跑到实现前面。
- DoD：
  - `swift test` 覆盖三条治理路由和三张治理编辑页
  - 后续任何人想把三页再并回一个表单，测试会先红

## 5) 实施顺序

1. `B1` 先改路由契约
2. `B2/B3/B4` 并行做三张治理编辑页
3. `B5` 把 Create flow 接到同一治理模型
4. `B6` 收口命名和 README
5. `B7` 补回归并关门

## 6) 交付验收清单

- 项目治理条存在三个独立入口，而不是一个共享设置页
- `A-Tier` 页面只讲 `A0..A4`
- `S-Tier` 页面只讲 `S0..S4`
- `Heartbeat / Review` 页面只讲 cadence / triggers / depth / guidance context
- `CreateProjectSheet` 同样按三轴配置
- `A4 Agent` 命名完成收口
- README 不再超前描述未完成的治理表面

## 7) 不在本包范围内

- 新增独立的 `heartbeat view depth override` schema
- 把 `projectMemoryCeiling` / `supervisorReviewMemoryCeiling` 从 tier 默认值扩成可自由覆盖字段
- 改动 capability gate 主逻辑
- 改动 safe-point protocol 本身

这些如果要做，再作为 `XT-W3-36-B8+` 后续包推进，不和这次 UI 回正混在一起。

## 8) Home & Supervisor UX Trim

- priority: `P1`
- goal: keep the governance chip strip as the single source of truth for A/S/Heartbeat while keeping the Supervisor/Project AI chat window easy to select and copy via the normal drag gesture.
- code sightlines:
  - `x-terminal/Sources/UI/GlobalHomeView.swift`
  - `x-terminal/Sources/UI/ProjectGovernanceBadge.swift`
  - `x-terminal/Sources/UI/ProjectGovernanceQuickAccessStrip.swift`
  - `x-terminal/Sources/UI/Supervisor/SupervisorConversationPanel.swift`
- deliverables:
  1. Drop the duplicate “A 执行 / S 监督 / 心跳审查” rows on each Home card; the top governance strip now alone explains each axis, and its chips use the new tier-specific palette so the colors stay consistent with dedicated editors.
  2. Supervisor / Project AI / user chat history renders as cohesive background blocks (Supervisor light blue, Project AI pale yellow, user neutral) that wrap blank lines and role labels so a single drag covers a whole statement and copying retains the role prefix.
  3. The compact governance strip still routes to the three dedicated governance pages.

DoD: Home cards show only the colored strip at the top, the chat view uses the new background block style, and the Quick Access strip chips respect the refreshed colors.
