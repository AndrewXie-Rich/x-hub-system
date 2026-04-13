# X-Hub Parallel Control-Plane Lane Work Orders v1

- Status: Active
- Updated: 2026-03-29
- Owner: Product / Hub Runtime / X-Terminal / Supervisor / Memory / QA
- Purpose: 把 `xhub-parallel-control-plane-roadmap-v1.md` 里的 6 条执行线，拆成后续 AI 可以直接接力的详细可执行工单包。
- Parent:
  - `docs/memory-new/xhub-parallel-control-plane-roadmap-v1.md`
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `docs/memory-new/xhub-heartbeat-and-review-evolution-work-orders-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`

## 0) How To Use

- 这不是“一个人顺着做完”的串行大文档。
- 这是给后续多 AI 并行接力的 lane pack。
- 默认先选一条线，不要同时 claim 多条。
- 如果一条线需要跨到别的线的主写文件，优先补 contract / seam，而不是顺手把别人的线一起做了。

## 1) Lane Matrix

| Line | Priority | Owns | Default owner | Suggested status |
| --- | --- | --- | --- | --- |
| `LA` | `P0` | Runtime | XT Runtime / Supervisor | hot |
| `LB` | `P0/P1` | Governance | Governance / Policy | warm |
| `LC` | `P0` | Heartbeat | Supervisor / XT Runtime | hot |
| `LD` | `P0` | Trust / Capability / Route | Hub Runtime / XT Pairing / Skills | hot |
| `LE` | `P1` | Memory | Hub Memory / Supervisor Memory | warm |
| `LF` | `P1` | UX / Release | XT UI / Release / QA | warm |

## 2) Lane A `Runtime`

- Line ID: `LA`
- Priority: `P0`
- Covers:
  - `CP-05` Dual-Loop Role Split
  - `CP-07` Run Scheduler / Agent Runtime
- Objective:
  - 把“Supervisor 负责治理、Coder 负责执行”从角色定义推进到 durable run engine，使 project AI 能在受治理前提下持续执行、checkpoint、resume、retry、recover。
- Primary refs:
  - `docs/memory-new/xhub-la-runtime-handoff-guide-v1.md`
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `x-terminal/work-orders/xt-w3-25-automation-product-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
- Primary write roots:
  - `x-terminal/Sources/Supervisor/XTAutomation*`
  - `x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift` with narrow runtime-only changes
  - `x-terminal/Sources/Supervisor/XTAutomationRuntimePolicy.swift`
- Avoid:
  - `x-terminal/Sources/UI/ProjectHeartbeatReviewView.swift`
  - `x-terminal/Sources/UI/Supervisor/`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - memory assembly files under `x-terminal/Sources/Supervisor/*Memory*`

### LA-1 Run Truth Contract

- Goal:
  - 冻结 `prepared_run / active_run / blocked_run / completed_run / recovery_run` 的 authoritative truth。
- Deliver:
  - run state object
  - state transition rules
  - correlation IDs to heartbeat/audit/evidence
- Done when:
  - 任一 run 都能回答“现在在哪个状态、为什么、下一步是什么”。

### LA-2 Checkpoint + Resume

- Goal:
  - 让 run 在 XT 重启、超时或 route 波动后能恢复。
- Deliver:
  - checkpoint schema
  - resume entry
  - stale checkpoint policy
- Done when:
  - 失败后不需要重新从用户自然语言入口再建一遍项目上下文。

### LA-3 Bounded Retry + Recovery Handoff

- Goal:
  - 让 runtime 自己知道什么时候重试、什么时候交给 heartbeat/review/recovery beat。
- Deliver:
  - bounded retry policy
  - backoff semantics
  - escalation handoff to `LC`
- Done when:
  - 不会无限重试，也不会一次失败就完全停死。

### LA-4 Prepared Run -> Active Run -> Delivery Closure

- Goal:
  - 让 run 生命周期和交付收口清楚闭环。
- Deliver:
  - prepared->active launch gate
  - blocked->resume path
  - completion evidence bundle
- Done when:
  - “项目真的推进了”在 runtime 上有单一闭环，而不再依赖聊天文本猜状态。

### LA Evidence / Tests

- Suggested tests:
  - `x-terminal/Tests/SupervisorManagerAutomationRuntimeTests.swift`
  - `x-terminal/Tests/SupervisorEventLoopFollowUpTests.swift`
  - new `x-terminal/Tests/XTAutomationRunLifecycleTests.swift`
- Handoff outputs:
  - run truth vocabulary
  - checkpoint contract
  - retry/escalation reason codes

### LA Handoff Rule

- 新 AI 如果是第一次接这条线，先读 `docs/memory-new/xhub-la-runtime-handoff-guide-v1.md`，不要直接从 `SupervisorManager.swift` 或 runtime board UI 开始改。
- 默认先判定当前问题属于：
  - `run truth`
  - `checkpoint/resume`
  - `gate/clamp/readiness`
  - `recovery handoff`
  - `presentation/explainability`
- 只有确认问题类别后，才进入对应源码组；避免把 LA 问题做成 UI patch 或 prompt patch。

## 3) Lane B `Governance`

- Line ID: `LB`
- Priority: `P0/P1`
- Covers:
  - `CP-03` Governance Tiering
  - `CP-04` 中的 review / guidance / safe-point / ack semantics
- Objective:
  - 把 `A0..A4`、`S0..S4`、review policy、safe-point 和 guidance ack 继续收口成单一治理真相，确保 runtime clamp、review trigger、guidance 注入和用户可见 policy 不打架。
- Primary refs:
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-project-governance-three-axis-overview-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
- Primary write roots:
  - `x-terminal/Sources/Project/AXProjectAutonomyPolicy.swift`
  - `x-terminal/Sources/Project/AXProjectConfig.swift`
  - `x-terminal/Sources/Project/AXProjectGovernance*`
  - `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
  - `x-terminal/Sources/Supervisor/SupervisorGuidance*`
- Avoid:
  - broad `SupervisorManager.swift` edits unless integrating resolved policy outputs
  - notification/feed UI files
  - Hub pairing/runtime files

### LB-1 Effective Governance Resolver

- Goal:
  - 冻结 `configured / recommended / effective` governance truth。
- Deliver:
  - one effective governance projection
  - one source-of-truth resolver path
- Done when:
  - project detail、doctor、runtime summary 不再各说各话。

### LB-2 Mandatory Trigger + Clamp Matrix

- Goal:
  - 把 A/S 档位与 mandatory review triggers、clamp posture 对齐。
- Deliver:
  - trigger matrix
  - clamp reason vocabulary
  - deny reason mapping
- Done when:
  - 同一项目不会出现 UI 允许、runtime 却 silently deny 的漂移。

### LB-3 Guidance Ack Closure

- Goal:
  - 把 `accept / defer / reject` 从聊天语气，升级成结构化治理闭环。
- Deliver:
  - ack contract
  - defer reason schema
  - reject-with-rationale schema
- Done when:
  - 后续能回答“Supervisor 明明提醒过，为什么 coder 还是这么做”。

### LB-4 Safe-Point Semantics

- Goal:
  - 冻结什么时候 next tool、next step、checkpoint、immediate。
- Deliver:
  - safe-point contract
  - review->guidance injection rules
  - stop / replan boundaries
- Done when:
  - guidance 注入不再既打断执行又太迟。

### LB Evidence / Tests

- Suggested tests:
  - `x-terminal/Tests/ProjectGovernanceResolverTests.swift`
  - `x-terminal/Tests/SupervisorSafePointCoordinatorTests.swift`
  - `x-terminal/Tests/ProjectSettingsGovernanceUITests.swift`
- Handoff outputs:
  - effective governance snapshot
  - trigger/clamp matrix
  - ack reason vocabulary

## 4) Lane C `Heartbeat`

- Line ID: `LC`
- Priority: `P0`
- Covers:
  - `CP-04` Heartbeat / Review / Recovery
  - `CP-09` Portfolio / Attention Allocation
- Objective:
  - 把 heartbeat 从“定时状态更新”推进成“证据驱动治理神经系统”，支持 quality/anomaly、adaptive cadence、recovery beat 和 portfolio priority。
- Primary refs:
  - `docs/memory-new/xhub-heartbeat-system-overview-v1.md`
  - `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
  - `docs/memory-new/xhub-heartbeat-and-review-evolution-work-orders-v1.md`
  - `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
- Primary write roots:
  - `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
  - `x-terminal/Sources/Supervisor/SupervisorReviewScheduleStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorHeartbeatPresentation.swift`
  - new heartbeat-specific support files under `x-terminal/Sources/Supervisor/Heartbeat*`
  - Hub heartbeat truth projection seam in `x-hub/grpc-server/hub_grpc_server/src/services.js`
- Avoid:
  - broad runtime lifecycle edits under `XTAutomation*`
  - persona / memory assembly files as a primary ownership area
  - release gate shell scripts unless `LF` asks for projection fields
  - 把 heartbeat / cadence 变成 normal chat、normal project memory 的总拨盘

### LC Boundary Notes

- Main ownership:
  - `LC` 拥有 heartbeat truth、quality/anomaly、adaptive cadence、recovery beat 以及 heartbeat-governed review semantics 的 vocabulary。
- Allowed narrow seams:
  - memory explainability carrier
  - doctor / export structured projection
  - common governance surfaces 对 cadence triples 和 due reason 的消费
- Already-landed vocabulary:
  - heartbeat 触发的 governance review 不得再伪装成普通 `user_turn`
  - `trigger_source`
  - `governance_review_trigger`
  - `governance_review_run_kind`
- Forbidden shortcuts:
  - 不得让 heartbeat 直接决定 Supervisor 正常聊天的 recent raw context 深度
  - 不得让 heartbeat 直接决定 Project AI 的 project context depth
  - 不得用 cadence 替代 personal / project / cross-link 的 role-aware memory assembly
  - 不得把 doctor/export 的 explainability 反向升级成 runtime truth source

### LC Current Compatibility Slice (2026-03-29)

- 已落地：
  - XT 侧 `LC-1` 已有可用内核：
    - heartbeat quality/anomaly taxonomy
    - `stale_repeat / hollow_progress / weak_done_claim / queue_stall` 第一批规则
    - schedule persistence for latest quality/anomaly and XT-derived `project_phase / execution_status / risk_tier`
  - XT 侧 `LC-2` 已有大部分核心：
    - `configured / recommended / effective` cadence resolver
    - `phase / risk / execution_status / quality / anomaly / S-tier / work-order depth` 进入 effective cadence
    - heartbeat due / next-review-due explainability
  - machine-readable heartbeat governance projection 已有窄 seam：
    - doctor/export carrier
    - common governance surfaces 对 cadence triples / due reason 的消费
  - `LC -> LF` 的 release/evidence seam 已落地：
    - `xhub_doctor_source_gate_summary.v1.json` 已冻结 `heartbeat_governance_support`
    - XT source / all-source smoke 已对 `xt_source_heartbeat_governance_snapshot` 与 `all_source_heartbeat_governance_snapshot` 留证
    - `xt_release_gate`、OSS release readiness、OSS secret scrub、Hub R1 OSS boundary、product exit packet 已消费同一组字段
  - 这条 seam 的固定语义已写死：
    - 仅用于 `heartbeat -> governance review` explainability / doctor / export / release evidence
    - 不回写成 normal chat、normal project memory 或 grant/policy truth
- 未落地：
  - Hub authoritative heartbeat truth projection seam 仍待补齐
  - `LC-3` recovery beat 尚未正式开始
  - `LC-4` portfolio priority 尚未正式开始
  - route/readiness/cost pressure inputs 尚未通过 `LD` seam 接入 effective cadence
- 接手规则：
  - 新 AI 如果 claim `LC`，默认不要重做 XT 侧 `phase / risk / execution_status` cadence 工作。
  - 默认从 `LC-3 Recovery Beat` 起手；若需要补 `LC-2`，优先补 Hub truth / LD seam，而不是重复本地 heuristic 扩写。
  - 默认不要再回头重做 doctor/export/release 的 carrier 命名；优先沿既有 `heartbeat_governance_support` 往 recovery beat、portfolio priority 和 Hub truth seam 延伸。

### LC Cross-Line Conflict Guardrails

- With `LB`:
  - `LC` 可以消费 `A/S tier`、safe-point、ack、review mode 的治理输出。
  - `LC` 不拥有这些对象的定义权，不应顺手重写 governance resolver、ack contract 或 safe-point semantics。
- With `LA`:
  - `LC-3` 只拥有 `recovery decision`、lane vitality handoff、recover candidate vocabulary。
  - prepared/active/blocked/completed 的 run lifecycle 仍归 `LA`，不得把 recovery 线扩成 runtime state machine 重构。
- With `LD`:
  - `LC` 可以在 `services.js` 增加 heartbeat truth projection seam，并消费 route/readiness/cost inputs。
  - `LC` 不拥有 grant / capability / route 主 vocabulary，不应把 LD 主链改造成 heartbeat 私有状态。
- With `LF`:
  - `LC` 可以输出 machine-readable heartbeat truth、cadence explainability 和 recovery decision projection。
  - 用户 digest wording、doctor cards、release wording、notification suppression 仍由 `LF` 拥有；`LC` 不应继续把 explainability surface 扩成自己的主线。

### LC-1 Heartbeat Quality + Anomaly Kernel

- Goal:
  - 定义 `quality snapshot` 和 `anomaly note`。
- Deliver:
  - strong/usable/weak/hollow bands
  - stale/empty/weak-done/queue-stall anomaly rules
- Done when:
  - 系统能区分“在动”和“有价值地推进”。

### LC-2 Adaptive Cadence

- Goal:
  - 让 cadence 从固定间隔升级为 `configured / recommended / effective`。
- Deliver:
  - cadence resolver
  - explainability string/projection
  - phase/risk/quality inputs
- Done when:
  - review 不再只是盲定时。

### LC-3 Recovery Beat

- Goal:
  - 让 heartbeat 能驱动 `resume / repair route / rehydrate / hold`。
- Deliver:
  - recovery decision object
  - lane vitality handoff
  - route fault integration seam
- Done when:
  - 遇到静默或 route 异常时，系统先尝试恢复，而不是只报 stale。

### LC-4 Portfolio Priority

- Goal:
  - 让 Supervisor 能按 priority 看项目，而不是平均轮询。
- Deliver:
  - priority score
  - factor model
  - feed ordering policy
- Done when:
  - 多项目下能回答“为什么先看这个项目”。

### LC Evidence / Tests

- Suggested tests:
  - `x-terminal/Tests/SupervisorReviewPolicyEngineTests.swift`
  - `x-terminal/Tests/ProjectGovernanceActivityPresentationTests.swift`
  - new `x-terminal/Tests/HeartbeatQualityPolicyTests.swift`
  - new `x-terminal/Tests/HeartbeatRecoveryDecisionTests.swift`
  - new `x-terminal/Tests/SupervisorPortfolioPriorityTests.swift`
- Handoff outputs:
  - quality/anomaly vocabulary
  - effective cadence projection
  - recovery decision contract
  - heartbeat-governed review vocabulary and explainability fields

## 5) Lane D `Trust / Capability / Route`

- Line ID: `LD`
- Priority: `P0`
- Covers:
  - `CP-02` Pairing / Discovery / Doctor / Self-Heal
  - `CP-06` Skills / Packages / Workflow
  - `CP-08` Capability / Grant / Runtime Readiness
  - `CP-11` Model Route / Context Budget / Cost Governor
- Objective:
  - 让系统能稳定回答“现在为什么能做 / 不能做 / 应该走哪条路 / 缺什么 readiness / 下一步该修什么”，并把 pairing、route、grant、skills、model budget 的 vocabulary 收口。
- Primary refs:
  - `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`
  - `docs/xhub-runtime-stability-and-launch-recovery-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/memory-new/xhub-skill-capability-profiles-and-execution-readiness-contract-v1.md`
  - `x-terminal/work-orders/xt-w3-41-skill-capability-profiles-and-readiness-surface-implementation-pack-v1.md`
- Primary write roots:
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - `x-terminal/Sources/Hub/HubAIClient.swift`
  - `x-terminal/Sources/Project/XTRouteTruthPresentation.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_*`
- Avoid:
  - memory assembly files
  - governance resolver core
  - large Supervisor UI surface

### LD-1 Pairing / Doctor / Self-Heal Closure

- Goal:
  - 收口 pairing、discover、repair、doctor 的主链 vocabulary。
- Deliver:
  - one blocked reason vocabulary
  - one repair next-step vocabulary
  - route / pairing / stale profile explanation chain
- Done when:
  - 用户不再只看到 spinner 或 vague error。

### LD-2 Capability / Grant / Runtime Readiness

- Goal:
  - 把 capability bundle、grant dependency、runtime ready 收成一等状态。
- Deliver:
  - capability readiness snapshot
  - policy configured vs runtime ready distinction
  - deny reason normalization
- Done when:
  - 系统能说清“想做”和“现在真能做”之间差在哪。

### LD-3 Model Route / Context Budget / Cost Governor

- Goal:
  - 收口模型路由、上下文预算、fallback、downgrade、token/cost posture。
- Deliver:
  - route truth projection
  - context budget policy seam
  - single request limit / fallback handling
- Done when:
  - paid/local/fallback 不再在多个地方各说各话。

### LD-4 Skills Readiness Surface

- Goal:
  - 让 skills 也进入 capability/readiness/doctor 链，而不是孤立 workflow。
- Deliver:
  - skill capability profile
  - preflight readiness truth
  - skill doctor output normalization
- Done when:
  - skills surface 能和 route / capability / grant truth 讲同一种语言。

### LD Evidence / Tests

- Suggested tests:
  - `x-terminal/Tests/ToolExecutorWebSearchGrantGateTests.swift`
  - `x-terminal/Tests/XTHubGrantPresentationTests.swift`
  - `x-terminal/Tests/HubIPCClientRequestFailureDiagnosticsTests.swift`
  - `x-terminal/Tests/SupervisorPendingHubGrantPresentationTests.swift`
  - skills readiness / compat tests under `x-terminal/Tests/` and Hub `src/*test.js`
- Handoff outputs:
  - deny reason vocabulary
  - readiness snapshot contract
  - route/cost/context truth projection

### LD Continuity / No-Regression Freeze

- `LD` 不是泛泛的“skill 线”，它是 `XT-W3-34` 执行面之上的 truth layer，主要承接：
  - `XT-W3-41-A/B/C/H/I`
  - `XT-W3-34-A/I/J/K` 中直接影响 capability/readiness/import canonicalization 的部分
- 当前推荐主 ownership：
  - `LD-2 Capability / Grant / Runtime Readiness`
  - `LD-4 Skills Readiness Surface`
- 当前只做 additive seam，不应主导：
  - `XT-W3-41-D/E` 的 UI surface
  - `XT-W3-41-G` 的 bundle/product wording
  - `XT-W3-41-F` 在 `B/C/H` 稳定前的 router 扩张
- 必须冻结的运行时不变量：
  - `grantRequestId` 是审批/回调相关 request token，不是可执行 `grant_id`
  - official governed wrapper skill 静态导出的 `policy_clamped` 在 Supervisor 中不总是终态 deny；对 `web_fetch / web_search / browser_read` 一类 governed network wrapper，必须还能进入 `grant_required` / request-scoped override 链
  - 这条 override 必须保持窄：
    - action-aware preflight 可对 mixed skill 的实际映射动作生效
    - generic surface / profile snapshot 只对 pure governed network wrapper 生效
    - 不允许把所有 `policy_clamped` skill 扁平降成 `grant_required`
  - builtin wrapper 与 official wrapper 不能简单视作同一物；official package manifest 带来的 capability/grant/profile truth 不得在 XT 被降级回旧 tool-only 语义
  - `XT-W3-41-I` 是加在 `XT-W3-34-A/J` 之上的 canonical mapping，不得绕开 provenance / vetter / quarantine 主链
  - `XT-W3-41-G` 不得回退 `XT-W3-34-K` 已锁定的 baseline truth；没有 uploadable package 的 bundle 不得假装 ready
- 当前已锁住的最小回归锚点：
  - `ToolExecutorWebSearchGrantGateTests.grantRequestIdIsNotAcceptedAsExecutableGrantToken`
    - `grant_request_id` 单独存在时，应表现为缺少可执行 `grant_id`
    - 合法 execution grant token 即使在无 bridge 环境下仍应穿过 token 语义校验，随后才落到 `bridge_disabled`
  - `SupervisorCommandGuardTests.approvedHubGrantWithoutGrantIdUsesSyntheticExecutionGrantToken`
    - Hub 只回 request token 时，Supervisor 必须生成并写回独立 execution grant token，且不得回写 request token 作为 `grant_id`
  - `SupervisorCommandGuardTests.approvedHubGrantWithoutGrantIdUsesSyntheticExecutionGrantTokenForBuiltinWebSearch`
    - builtin `web.search` wrapper 也必须继承同样的 request-token / execution-token 分离语义，不得只在 official wrapper 上成立
  - `AXSkillsCompatibilityTests.supervisorSkillPreflightGatePromotesPolicyClampedAgentBrowserReadActionIntoGrantRequired`
    - mixed governed skill 的 action-scoped `browser_read` preflight 可以提升成 `grant_required`
  - `AXSkillsCompatibilityTests.projectAwareGovernanceSurfaceTreatsPureGovernedWebSearchWrapperAsGrantRequestable`
    - pure governed network wrapper 在 generic governance surface 上必须显示为 `requestable` / `grant_required`
  - `AXSkillsCompatibilityTests.projectEffectiveSkillProfileSnapshotPromotesPureGovernedWebSearchWrapperIntoGrantRequiredProfiles`
    - pure governed network wrapper 不得再把可发现的 `observe_only` profile 打成 `policy_clamped` blocked
  - `AXSkillsCompatibilityTests.projectSkillRouterIntentFallbackTreatsPureGovernedWebSearchWrapperAsRequestable`
    - intent-family router 也必须继承 pure governed network wrapper 的 requestable truth，不能继续按原始 `policy_clamped` 丢弃候选
  - `AXSkillsCompatibilityTests.chatSessionProjectSkillActivityReadinessUsesEffectiveGrantRequiredTruthForPureGovernedWebWrapper`
    - project activity / timeline 写回的 readiness 也必须继承 pure governed network wrapper 的 `grant_required` truth，不能回退成原始 `policy_clamped`
  - `ProjectSkillActivityPresentationTests.blockedGrantRequiredBodyUsesHubAuthorizationGuidance`
    - project skill activity 在 `grant_required` 阻断下的用户可见文案必须继续指向 Hub 授权，而不是退回本地审批话术
  - `ProjectSkillActivityPresentationTests.displayTimelineDetailLocalizesGrantRequiredDenyCode`
    - project timeline detail / full-record 对 `grant_required` 的本地化必须稳定，不能只在 raw JSON 里保留真相
  - `ProjectSkillActivityPresentationTests.fullRecordUsesPersistedRequiredCapabilityFromProjectActivityRawLog`
    - project activity raw log 对 governed network wrapper 写回的 `required_capability` 必须能进入 full-record / detail 展示，不能在 parse / projection 时丢失
- 详细 handoff 和 continuity 说明见：
  - `docs/memory-new/xhub-ld-trust-capability-route-continuity-and-handoff-v1.md`

## 6) Lane E `Memory`

- Line ID: `LE`
- Priority: `P1`
- Covers:
  - `CP-01` Memory Core & Serving
  - `CP-10` Supervisor Personal Assistant Plane
- Objective:
  - 保持 Hub-first、Writer + Gate、5-layer memory 不变，同时把 project memory 和 personal assistant memory 的双平面装配继续收口成丝滑可用的系统。
- Primary refs:
  - `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
  - `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
  - `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`
- Primary write roots:
  - `x-terminal/Sources/Supervisor/*Memory*`
  - `x-terminal/Sources/Project/AXProjectModelRouteMemory.swift`
  - memory projection / doctor seams with narrow touches
  - Hub memory service and schema files only when truly necessary
- Avoid:
  - pairing / route files
  - governance UI surfaces
  - runtime run lifecycle files
  - heartbeat cadence / anomaly logic，除非只是消费 `LC` 已冻结的 explainability seam

### LE-1 Role-Aware Memory Assembly Closure

- Goal:
  - 把 Supervisor 与 Project AI 的记忆供给正式区分。
- Deliver:
  - role-aware assembly rules
  - recent raw context floor
  - project context depth floor
- Done when:
  - Supervisor 和 coder 不再吃同一套 context。

### LE-2 Personal / Project Memory Bridge

- Goal:
  - 让两类记忆自然桥接，但不互相污染 durable truth。
- Deliver:
  - bridge rules
  - scope filters
  - promotion/rejection guards
- Done when:
  - Supervisor 既能懂用户，也能懂项目，而不是二选一。

### LE-3 Persona / Follow-Up / Long-Term Assistant Plane

- Goal:
  - 把 persona slot、personal review、follow-up ledger、长期助理 continuity 收口成独立平面。
- Deliver:
  - persona registry truth
  - follow-up writeback rules
  - personal review lifecycle
- Done when:
  - 个人助理能力是第一等平面，不再只是 project side effect。

### LE-4 Memory Explainability

- Goal:
  - 让 doctor/export 能解释“这轮为什么喂了这些记忆、没喂那些记忆”。
- Deliver:
  - assembly report
  - source badges
  - local vs hub overlay explanation
- Done when:
  - 后续 AI 能从 doctor 看明白 memory feeding，而不是猜。

### LE Evidence / Tests

- Suggested tests:
  - `x-terminal/Tests/MemoryControlPlaneDocsSyncTests.swift`
  - memory routing / assembly tests under `x-terminal/Tests/`
  - doctor truth projection tests
- Handoff outputs:
  - role-aware memory contract
  - bridge policy
  - explainability projection

## 7) Lane F `UX / Release`

- Line ID: `LF`
- Priority: `P1`
- Covers:
  - `CP-12` User-Facing Governance UX
  - `CP-13` Evidence / Release Truth Spine
- Objective:
  - 把底层治理、heartbeat、grant、route、memory 真相变成用户能理解、release 能证明、doctor 能解释的产品表面。
- Primary refs:
  - `docs/memory-new/xhub-heartbeat-system-overview-v1.md`
  - `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
  - `docs/memory-new/xhub-project-governance-three-axis-overview-v1.md`
  - `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
  - `x-terminal/scripts/ci/xt_release_gate.sh`
- Primary write roots:
  - `x-terminal/Sources/UI/ProjectHeartbeatReviewView.swift`
  - `x-terminal/Sources/UI/Supervisor/SupervisorHeartbeatFeedView.swift`
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - narrow notification presentation files
  - docs / release evidence scripts
- Avoid:
  - core runtime state machines
  - Hub services / grant chain
  - deep memory routing logic
  - 在 UI / doctor 层重新定义 heartbeat 或 memory 的核心 semantics

### LF Current Compatibility Slice (2026-03-29)

- 已落地：
  - `LF` 已可直接消费 `heartbeat_governance_support`
  - source-gate summary、XT release gate、release/readiness/support 报告已经对齐到同一组 heartbeat governance 字段
  - docs-truth / contract sync 已覆盖 heartbeat governance projection 的 schema-level 漂移
- 接手规则：
  - 新 AI 如果 claim `LF`，默认不要再发明 heartbeat 的新 vocabulary；优先复用 `heartbeat_governance_support`
  - 用户 digest wording、doctor card、release wording 可以继续做，但不得把 explainability seam 反向升级成 runtime authority
  - 如果需要更深的 cadence / anomaly / review 语义，先回 `LC` 协议与 contract，再决定是否扩字段

### LF-1 Governance UX Surface

- Goal:
  - 让 A/S-tier、heartbeat/review、digest、Open 行为变得直观。
- Deliver:
  - cleaner governance cards
  - digest-first notification surface
  - useful open-target behavior
- Done when:
  - 用户看到的是项目变化和建议，而不是工程噪音。

### LF-2 Doctor / Explainability Surface

- Goal:
  - 把 runtime truth 变成结构化解释，而不是 raw detail lines。
- Deliver:
  - doctor cards for heartbeat/readiness/memory
  - configured vs effective snapshots
  - recovery / route / grant explainability
- Done when:
  - doctor 能成为真正的 truth viewer，而不是 debug dump。

### LF-3 Release Truth Spine

- Goal:
  - 把 docs-truth、capability matrix、release gate、evidence report 收口。
- Deliver:
  - new evidence hooks
  - docs-truth sync tests
  - release wording alignment
- Done when:
  - 文档、doctor、UI、release claim 不再互相漂移。

### LF-4 User Noise Suppression

- Goal:
  - 明确哪些信息只给 Supervisor/doctor，哪些才给用户。
- Deliver:
  - user-facing digest policy
  - internal-only notification suppression
  - fallback wording standards
- Done when:
  - `grant_pending`、`lane=...` 这类词默认不会直接打到用户面板。

### LF Evidence / Tests

- Suggested tests:
  - `x-terminal/Tests/XTUnifiedDoctorReportTests.swift`
  - `x-terminal/Tests/XHubDoctorOutputTests.swift`
  - UI snapshot/manual smoke for heartbeat and governance surfaces
  - release gate evidence scripts
- Handoff outputs:
  - user digest wording contract
  - doctor truth projection
  - release evidence checklist

## 8) Cross-Line Dependency Rules

### 8.1 `LA` depends on `LB` and `LD`

原因：

- runtime 需要 governance clamp
- runtime 需要 capability/readiness truth

### 8.2 `LC` depends on `LA` and `LB`

原因：

- heartbeat 要看真实 run 状态
- heartbeat 的升级策略要受 governance 驱动

### 8.3 `LE` depends on `LB` and `LD`

原因：

- memory feeding 要知道 role/tier/readiness
- 不能给无权 runtime 喂不该给的上下文

### 8.4 `LF` depends on everybody, but should not invent truth

原因：

- UX/doctor/release 最后都要消费别的线产物
- 但它们不能反向制造 runtime truth

## 9) Recommended Parallel Activation

如果只有 2 个 AI：

- 先开 `LA`
- 再开 `LD`

如果有 3 个 AI：

- 开 `LA`
- 开 `LC`
- 开 `LD`

如果有 4 到 6 个 AI：

- `LA`
- `LB`
- `LC`
- `LD`
- `LE`
- `LF`

规则：

- 先热启动 `LA / LC / LD`
- `LB` 作为治理收口线并行跟进
- `LE / LF` 默认 warm，不要压过主执行闭环

## 10) Final Handoff Summary

后续 AI 如果只想知道“拿哪条线”：

- 想把 A4 真正跑起来：拿 `LA`
- 想把治理做稳：拿 `LB`
- 想把 heartbeat 变聪明：拿 `LC`
- 想把 pairing / grant / route / skills 说真话：拿 `LD`
- 想把个人助手和项目记忆做丝滑：拿 `LE`
- 想把用户体验和 release 口径做对：拿 `LF`
