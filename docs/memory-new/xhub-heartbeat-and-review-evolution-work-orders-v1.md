# X-Hub Heartbeat + Review Evolution Work Orders v1

- Status: Active
- Updated: 2026-03-29
- Owner: XT-L2（Primary）/ Hub-L5 / Supervisor / Memory / QA / Product
- Purpose: 把 `heartbeat` 从“定时状态更新”推进为“证据驱动的治理神经系统”，按可交付切片拆成可直接接手的正式工单包，覆盖 Hub 真相、XT 调度、质量评分、异常升级、用户 digest、恢复逻辑、portfolio 优先级、memory 写回和 release/gate 收口。
- Depends on:
  - `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `docs/memory-new/xhub-supervisor-event-loop-stability-work-orders-v1.md`
  - `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
  - `x-terminal/Sources/Supervisor/SupervisorReviewScheduleStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorHeartbeatPresentation.swift`
  - `x-terminal/Sources/UI/Supervisor/SupervisorHeartbeatFeedView.swift`
  - `x-terminal/Sources/UI/ProjectHeartbeatReviewView.swift`
  - `x-terminal/Sources/Supervisor/LaneHeartbeatController.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`

## 0) Current State

### 0.1 What is already landed

当前不是从零开始。已经落地的基础包括：

- Hub 已持有 project heartbeat truth
- XT 已有 `SupervisorReviewScheduleStore`
- XT 已有 `SupervisorReviewPolicyEngine`
- heartbeat / review / intervention 已分离
- XT 已把 heartbeat governed review semantics 接进 Supervisor memory explainability：
  - heartbeat 触发的 governance review 不再在 memory resolution 上伪装成普通 `user_turn`
  - `trigger_source / governance_review_trigger / governance_review_run_kind` 已进入 Supervisor memory snapshot
  - Memory Board / Doctor 已能看到这组三元治理字段
- brainstorm 已经围绕 `lastObservedProgressAtMs` 计算，不是死定时
- XT 已有 heartbeat feed UI 和 activity presentation
- XT lane 已有内部 heartbeat/stall 检测骨架
- 在并行执行线的归属上，这条主线属于 `LC Heartbeat`；
  - `LE Memory` 只消费 memory explainability 的窄接缝
  - `LF UX / Release` 只消费 doctor / export / release projection 的窄接缝
  - 不允许把 heartbeat 重新升级成 normal chat / project memory 的主拨盘

### 0.2 What is still missing

真正还缺的是：

1. `heartbeat quality` 还没有正式一等对象。
2. `heartbeat anomaly` 还没有正式一等对象。
3. cadence 还缺 `effective` 解释层。
4. user digest 仍然容易混入工程噪音。
5. recovery beat 还没有形成正式主链。
6. portfolio 优先级还没有把 heartbeat 用起来。
7. doctor / evidence / tests 还没有围绕 heartbeat evolution 收口。

## 1) Delivery Sequence

建议固定顺序：

1. `HB-01`
   - 先让 heartbeat “会判断质量和异常”
2. `HB-02`
   - 再让 heartbeat “会决定什么时候更紧/更松”
3. `HB-03`
   - 再让 heartbeat “能对用户说人话”
4. `HB-04`
   - 再让 heartbeat “能触发恢复和续跑”
5. `HB-05`
   - 再让 heartbeat “能帮助 Supervisor 跨项目分配注意力”
6. `HB-06`
   - 最后统一做 memory / doctor / tests / release 收口

原因：

- 先做 quality/anomaly，后面 cadence、digest、recovery 才有可靠输入。
- 先做用户界面而不做质量内核，只会把噪音包装得更好看。

## 2) Shared Constraints

所有子工单都必须遵守：

- Hub authoritative truth 继续是唯一 project heartbeat 真相。
- XT 可以缓存 projection，但不能反向覆盖 Hub truth。
- 不得把 `heartbeat` 和 `review` 重新混在一起。
- 不得把 `Project AI` 和 `Supervisor` 强行收敛到一个 cadence 拨盘。
- 用户视图禁止直接暴露 lane/internal engineering noise。
- heartbeat 写回 memory 仍受 X-Constitution、Writer + Gate、scope、promotion 规则约束。

## 3) Work Orders

### HB-01 Heartbeat Quality + Anomaly Kernel

- Goal:
  - 给每条 project heartbeat 加上一等 `quality snapshot` 和 `anomaly note`，让系统能区分“有价值推进”和“假活跃/空转”。
- Primary code entry points:
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorHeartbeatPresentation.swift`
- Tasks:
  - 定义 `HeartbeatQualitySnapshot` 结构和 band 规则。
  - 定义 `HeartbeatAnomalyNote` 结构和 anomaly taxonomy。
  - 在 Hub heartbeat truth projection 中挂上 quality/anomaly 派生位。
  - 在 XT review candidate 计算前先读取 quality/anomaly。
  - 为 `hollow_progress / stale_repeat / weak_done_claim / queue_stall` 建立第一批规则。
- Current runtime slice (2026-03-29):
  - XT 已落地 heartbeat quality/anomaly 内核，并收口到 heartbeat-specific support files，而不是继续把规则散落在 UI 或普通聊天逻辑里。
  - XT review candidate 现在会在 pulse / brainstorm / pre-done 判断前读取 latest quality band 和 open anomalies。
  - `stale_repeat / hollow_progress / weak_done_claim / queue_stall` 已有第一批规则和测试覆盖。
  - `SupervisorReviewScheduleStore` 已持久化 latest quality snapshot、open anomalies，以及 XT 派生的 `project_phase / execution_status / risk_tier`，供 HB-02 cadence resolver 继续消费。
  - doctor/export 已至少能承载 latest quality band、open anomalies 和 machine-readable heartbeat governance lines。
  - Hub authoritative heartbeat truth projection seam 仍待补齐；XT 当前是 projection / explainability carrier，不得反向覆盖 Hub truth。
- Done when:
  - 系统不再只依据“有没有 heartbeat”来判断健康。
  - 同一个项目连续重复 heartbeat 能被识别为 `stale_repeat` 或 `hollow_progress`。
  - `done_candidate` 无证据时能被识别为 `weak_done_claim`。
- Evidence:
  - 新增 unit tests 覆盖 quality band 和 anomaly detection。
  - doctor/export 至少能看到 latest quality band 和 open anomaly count。
- Suggested test files:
  - `x-terminal/Tests/SupervisorReviewPolicyEngineTests.swift`
  - `x-terminal/Tests/ProjectGovernanceActivityPresentationTests.swift`
  - 新增 `x-terminal/Tests/HeartbeatQualityPolicyTests.swift`

### HB-02 Adaptive Cadence + Effective Cadence Explainability

- Goal:
  - 让 cadence 从固定间隔升级为 `configured / recommended / effective` 三层，并能解释为什么当前更紧或更松。
- Primary code entry points:
  - `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
  - `x-terminal/Sources/Supervisor/SupervisorReviewScheduleStore.swift`
  - `x-terminal/Sources/UI/ProjectHeartbeatReviewView.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- Tasks:
  - 在 schedule 层加入 effective cadence 计算。
  - 引入 phase/risk/quality/anomaly/A-tier/S-tier 对 cadence 的影响。
  - 在 UI 与 doctor 中区分：
    - 用户配置值
    - 系统建议值
    - 当前实际值
  - 把 `lastObservedProgressAtMs` 与 quality/anomaly 一起用于 brainstorm/review rebase。
- Current runtime slice (2026-03-29):
  - XT 已落地 `configured / recommended / effective` cadence resolver，并把 quality/anomaly、S-tier、work-order depth 接入 `effective` 计算。
  - `heartbeatCandidate` 与 governance activity/review UI 现在优先使用 effective due，而不是盲信存储里的静态 `next_*_due_at_ms`。
  - `ProjectHeartbeatReviewView` 与 `ProjectGovernanceActivityView` 已能看到 cadence triples 和 due reason。
  - `ProjectGovernanceBadge`、project detail/settings/grid 以及 Supervisor project drill-down 已接入 cadence explainability，通用治理展示不再只暴露单个静态 cadence。
  - `SupervisorProjectDrillDownSnapshot` 与 `XTProjectHeartbeatGovernanceDoctorSnapshot` 已具备 cadence explainability / next-review-due 的 machine-readable 承载面，供 doctor 继续收口。
  - `phase / risk / execution_status` 已接入 XT 本轮 resolver；不要再把这三项当成未落地缺口重复实现。
  - `route health / readiness health / model cost pressure` 仍未接入本轮 resolver，后续继续在 HB-02 / HB-04 通过 Hub truth / LD seam 补齐，而不是在 XT 本地另造第二套健康真相。
  - doctor/export 的 heartbeat cadence explainability 承载面已经存在，但后续 surface 扩写应按 lane pack 交给 `LF`，不要把 HB-02 继续扩成“heartbeat 线吞掉所有 explainability UI”。
- Done when:
  - 项目 phase/risk 变化时，effective cadence 能变化。
  - UI 不再只显示一个静态 heartbeat/review 时间。
  - doctor/export 能解释“为什么 review 现在 due / not due”。
- Evidence:
  - `ProjectHeartbeatReviewView` 能展示 configured/recommended/effective。
  - 新增 cadence explainability 测试。
  - 定向验证命令：
    - `swift test --scratch-path /tmp/xt_heartbeat_cadence_build --filter 'SupervisorReviewPolicyEngineTests|ProjectGovernanceActivityPresentationTests'`
    - `swift test --scratch-path /tmp/xt_heartbeat_cadence_build_v4 --filter 'ProjectGovernancePresentationSummaryTests|SupervisorProjectDrillDownTests|SupervisorProjectDrillDownPresentationTests'`
- Suggested test files:
  - `x-terminal/Tests/SupervisorReviewPolicyEngineTests.swift`
  - `x-terminal/Tests/ProjectGovernanceActivityPresentationTests.swift`
  - 新增 `x-terminal/Tests/HeartbeatCadenceResolverTests.swift`

### HB-03 User Digest Beat + Notification Cleanup

- Goal:
  - 把 heartbeat 用户可见面改成 digest 视图，只说用户需要知道的变化，不再展示工程噪音。
- Primary code entry points:
  - `x-terminal/Sources/Supervisor/SupervisorHeartbeatPresentation.swift`
  - `x-terminal/Sources/UI/Supervisor/SupervisorHeartbeatFeedView.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/ContentView.swift`
- Tasks:
  - 定义 `HeartbeatDigest` 结构。
  - 把现有 heartbeat feed 分为：
    - internal/runtime entries
    - user-facing digest entries
  - 重写通知标题/正文模板，默认输出：
    - 发生了什么
    - 为什么重要
    - 系统下一步
  - 修正 `Open` 行为，打开对应项目/治理视图，而不是工程噪音面板。
  - 对 `grant_pending`、lane/infrastructure 等内部类通知做用户面抑制或翻译。
- Done when:
  - 用户不再在通知区直接看到 `grant_pending`、`lane=...` 这类内部术语。
  - Supervisor heartbeat feed 能清楚区分“对用户可见”和“仅内部调试”。
- Evidence:
  - UI snapshot/manual smoke
  - 新增 notification wording tests
  - 新增 routing/open-target tests
- Suggested test files:
  - `x-terminal/Tests/SupervisorHeartbeatVoiceTests.swift`
  - 新增 `x-terminal/Tests/SupervisorHeartbeatDigestPresentationTests.swift`

### HB-04 Recovery Beat + Automation Kickstart

- Goal:
  - 让 heartbeat 不只“报状态”，还能识别并触发 recover/resume/route repair/request review。
- Primary code entry points:
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/LaneHeartbeatController.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift`
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
- Tasks:
  - 定义 `HeartbeatRecoveryDecision`。
  - 让 lane vitality、route health、project heartbeat 联合决定 recover candidate。
  - 支持：
    - resume prepared run
    - rehydrate context
    - repair route
    - queue strategic review
    - hold for grant/user
  - 让 recovery 仍然受治理边界约束，而不是无脑自恢复。
- Done when:
  - coder 静默但 lane 可恢复时，系统能提出恢复动作而不是只报 stale。
  - route 抖动能进入 route repair / hold，而不是一直 spinner。
  - recovery decision 可审计、可解释。
- Evidence:
  - automation runtime tests 覆盖 resume/recover path
  - doctor/export 暴露 latest recovery decision
- Suggested test files:
  - `x-terminal/Tests/SupervisorEventLoopFollowUpTests.swift`
  - `x-terminal/Tests/SupervisorManagerAutomationRuntimeTests.swift`
  - 新增 `x-terminal/Tests/HeartbeatRecoveryDecisionTests.swift`

### HB-05 Portfolio Priority Heartbeat

- Goal:
  - 让 Supervisor 用 heartbeat 进行跨项目注意力分配，而不是平均轮询。
- Primary code entry points:
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorPortfolioSnapshot.swift`
  - `x-terminal/Sources/Supervisor/SupervisorViewStateSupportAssembly.swift`
- Tasks:
  - 定义 `PortfolioPrioritySnapshot`。
  - 把 risk/staleness/blocker/evidence weakness/deadline 等因子纳入 priority score。
  - 让 review budget 优先给高风险、高价值、最需要纠偏的项目。
  - 为 portfolio digest 增加“为什么先看这个项目”的解释线。
- Done when:
  - 多项目下，Supervisor review 顺序不再只是 round-robin。
  - 用户能在 portfolio 层看见“当前最值得注意的项目”。
- Evidence:
  - portfolio ordering tests
  - UI presentation tests
- Suggested test files:
  - `x-terminal/Tests/SupervisorGovernanceDigestIntegrationTests.swift`
  - 新增 `x-terminal/Tests/SupervisorPortfolioPriorityTests.swift`

### HB-06 Memory Projection + Doctor + Release Gate Closure

- Goal:
  - 把 heartbeat evolution 正式接进 memory、doctor、release 证据和 docs-truth，而不是只停留在 runtime 内存对象。
- Primary code entry points:
  - `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-terminal/Tests/ProjectGovernanceDocsTruthSyncTests.swift`
  - `x-terminal/scripts/ci/xt_release_gate.sh`
- Tasks:
  - 明确 heartbeat 到 Raw Vault / Observations / Canonical / Working Set 的映射。
  - 在 doctor 中增加：
    - latest heartbeat quality
    - open anomalies
    - effective cadence
    - latest recovery decision
  - 为 docs-truth 增加新协议/工单的同步校验。
  - 让 release gate 至少能检测：
    - quality/anomaly support
    - effective cadence explainability support
    - digest/user-noise suppression support
- Done when:
  - 下一位 AI 从 doctor/export 就能看出 heartbeat evolution 是否真的落地。
  - release/gate 能阻止“代码做了一半、文档还说已经完整”的漂移。
- Evidence:
  - docs sync tests
  - doctor snapshot evidence
  - release gate evidence script output

## 4) Recommended Delivery Ownership

推荐分工：

- XT-L2
  - `HB-01`, `HB-02`, `HB-03`, `HB-04`, `HB-05`
- Hub-L5
  - `HB-01` Hub truth projection
  - `HB-06` doctor/export contract touchpoints
- Memory
  - `HB-06` layer mapping and writeback discipline
- QA
  - regression tests, manual smoke, wording audit
- Product/Docs
  - digest wording, glossary, release claims

## 5) Recommended Execution Order For Another AI

如果下一位 AI 接手，推荐读序：

1. `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
2. `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
3. `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
4. `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
5. `x-terminal/Sources/Supervisor/SupervisorReviewScheduleStore.swift`
6. `x-terminal/Sources/Supervisor/SupervisorManager.swift`
7. `x-terminal/Sources/UI/ProjectHeartbeatReviewView.swift`
8. `x-terminal/Sources/UI/Supervisor/SupervisorHeartbeatFeedView.swift`
9. `x-hub/grpc-server/hub_grpc_server/src/services.js`

推荐开工顺序：

1. 先做 `HB-01`
2. 再做 `HB-02`
3. 然后 `HB-03`
4. 再做 `HB-04`
5. 之后 `HB-05`
6. 最后 `HB-06`

## 6) Done Criteria For The Whole Pack

整包收口时，至少满足：

1. 系统能区分 `weak/hollow` heartbeat，而不是一律当健康。
2. 系统能识别缺失 heartbeat 之外的“空转类异常”。
3. 用户侧 heartbeat 已去工程噪音。
4. Supervisor 能解释为什么 review 触发、为什么没触发。
5. heartbeat 能驱动 recover/resume，而不是只做展示。
6. 多项目时，heartbeat 已用于优先级分配。
7. doctor/export/release gate 能证明以上能力存在。
