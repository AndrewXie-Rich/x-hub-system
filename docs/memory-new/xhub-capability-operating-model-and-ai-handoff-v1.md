# X-Hub Capability Operating Model And AI Handoff v1

- Status: Active
- Updated: 2026-03-30
- Owner: Hub Runtime / XT-L2 / Supervisor / Security / Product
- Purpose: 给继续推进 `grant / readiness / capability bundles / action denial / doctor truth / route truth` 的 AI 和维护者一份运行说明，明确这套系统的能力语义是如何定义、如何配合、哪些文件是各层真相源、哪些不变量不能回退。
- Complements:
  - `docs/memory-new/xhub-skill-capability-profiles-and-execution-readiness-contract-v1.md`
  - `docs/memory-new/xhub-skills-capability-grant-chain-contract-v1.md`
  - `docs/memory-new/xhub-project-governance-three-axis-overview-v1.md`
  - `docs/memory-new/xhub-ld-trust-capability-route-continuity-and-handoff-v1.md`

## 0. Conclusion First

这套系统里的 `Capability` 不是“工具白名单”。

它是一条分层链路：

`skill/package metadata -> intent families -> capability families -> capability profiles -> grant/approval floor -> project capability bundle ceiling -> runtime surface clamp -> skill readiness -> supervisor preflight -> tool runtime deny -> governance truth / doctor truth / route truth`

核心判断原则：

- `Hub` 管 package / manifest / grant / revocation / catalog / resolved registry 的真相。
- `XT` 管 project A-Tier、runtime surface、trusted automation、本地审批姿态、最终 runnable truth。
- `Supervisor` 不发明第三套语义，只消费 typed readiness，再决定 `pass / grantRequired / blocked`。
- `Tool runtime policy` 是最后一道硬门，不允许 preflight 通过后在实际工具调用层无解释地放飞。

## 1. Canonical Layers

### 1.1 Intent Family

`intent family` 是输入层语义，用来描述 skill 想做什么。它可能来自：

- manifest 显式声明
- governed dispatch tool 推断
- governed dispatch variants 推断
- capabilities_required 推断
- skill_id 兜底推断

主要入口：

- `x-hub/grpc-server/hub_grpc_server/src/skill_capability_derivation.js`
- `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`

### 1.2 Capability Family

`capability family` 是最小稳定能力单元，是后续 grant、approval、runtime surface 和 readiness 的共同基础。

典型 family：

- `repo.read`
- `repo.mutate`
- `repo.verify`
- `repo.delivery`
- `web.live`
- `browser.observe`
- `browser.interact`
- `browser.secret_fill`
- `device.observe`
- `device.act`
- `memory.inspect`
- `supervisor.orchestrate`

每个 family 都带三类元数据：

- `grant_floor`
- `approval_floor`
- `runtime_surface_families`

Hub canonical entry:

- `x-hub/grpc-server/hub_grpc_server/src/skill_capability_derivation.js`

XT canonical entry:

- `x-terminal/Sources/Project/XTSkillCapabilityProfileSupport.swift`

### 1.3 Capability Profile

`capability profile` 不是 authority，本质是给模型、UI、审批和治理使用的 bundle 语义。

当前 canonical profile：

- `observe_only`
- `skill_management`
- `coding_execute`
- `browser_research`
- `browser_operator`
- `browser_operator_with_secrets`
- `delivery`
- `device_governed`
- `supervisor_full`

注意：

- profile 由 family 推导，不是手工配置主真相。
- profile 有闭包关系，不是平铺集合。
- 高级 profile 会自动包含低级 profile。

典型闭包：

- `browser_operator_with_secrets -> browser_operator -> browser_research -> observe_only`
- `delivery -> coding_execute -> observe_only`
- `supervisor_full -> device_governed + delivery + skill_management`

### 1.4 Grant Floor And Approval Floor

`grant_floor` 回答的是“Hub 至少要给什么级别授权”。

- `none`
- `readonly`
- `privileged`
- `critical`

`approval_floor` 回答的是“XT 本地至少要多强确认”。

- `none`
- `local_approval`
- `hub_grant`
- `hub_grant_plus_local_approval`
- `owner_confirmation`

这两层都从 family 汇总向上取最大值，不从 profile 反推。

### 1.5 Capability Bundle

`capability bundle` 是 project A-Tier 的基础能力上限，不是 skill 侧元数据。

它回答的是：

- 当前 project 从治理上原则上允许哪些能力
- 哪些工具能力就算 skill 想要、grant 也批了，project 仍然不应放行

关键点：

- `capability bundle` 是 A-Tier base capability，不等于 runtime surface。
- runtime surface 是动态收束层。
- trusted automation readiness 又是另一层动态收束。

这三层必须分开理解，不能混成一层。

## 2. Sources Of Truth By Layer

### 2.1 Hub Package / Skill Truth

Hub 侧负责把 package 输入归一化成 canonical capability semantics。

关键文件：

- `x-hub/grpc-server/hub_grpc_server/src/skill_capability_derivation.js`
  - canonical family/profile/floor/runtime-surface derivation
- `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
  - package entry normalize
  - manifest/catalog/registry merge
  - derived semantics 写回 normalized package entry

Hub 侧输出重点：

- `intent_families`
- `capability_families`
- `capability_profiles`
- `grant_floor`
- `approval_floor`
- `runtime_surface_families`
- `requires_grant`

### 2.2 XT Project Governance Truth

XT 侧负责 project A-Tier、S-Tier、Heartbeat / Review cadence、runtime surface、trusted automation 状态。

关键文件：

- `x-terminal/Sources/Project/AXProjectExecutionTier.swift`
- `x-terminal/Sources/Project/AXProjectGovernanceBundle.swift`
- `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`

A-Tier 到 base capability bundle 的当前冻结语义：

- `A0`: 只观察
- `A1`: 可自动建计划，但不改 repo
- `A2`: 可改 repo、build、test，不交付、不 browser、不 device
- `A3`: 可 commit / PR / CI read，但不 push、不 browser、不 device
- `A4`: 才具备 browser / device / connector / extension 的基础 ceiling

### 2.3 XT Capability Semantics Helper

XT 侧的语义 helper 负责：

- tool -> capability families
- families -> profiles
- profiles -> ceiling families
- families -> required runtime surfaces
- families -> grant/approval floors
- readiness override eligibility
- unblock actions
- approval delta

关键文件：

- `x-terminal/Sources/Project/XTSkillCapabilityProfileSupport.swift`

### 2.4 XT Skill Readiness Truth

XT 侧最终把 Hub skill truth 和 project runtime truth 组合成：

- `xhub.skill_execution_readiness.v1`
- `xt.project_effective_skill_profile.v1`

关键文件：

- `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`

这是回答“这个 skill 在这个 project 里现在能不能跑”的主真相层。

### 2.5 Supervisor Preflight Truth

Supervisor 不直接判断 capability families / profile ceiling，而是消费 typed readiness，再做最小决策：

- `pass`
- `grantRequired`
- `blocked`

关键文件：

- `x-terminal/Sources/Supervisor/SupervisorSkillPreflightGate.swift`

### 2.6 Tool Runtime Truth

即使 preflight 通过，实际工具调用仍必须再过 runtime gate。

关键文件：

- `x-terminal/Sources/Tools/XTToolRuntimePolicy.swift`

deny 顺序冻结为：

1. `project_governance` capability deny
2. `project_autonomy_policy` runtime surface deny
3. project tool policy allow/deny

### 2.7 Human Explanation Truth

机器字段不是直接给用户读的。需要 presentation 层做人类解释。

关键文件：

- `x-terminal/Sources/Tools/XTGuardrailMessagePresentation.swift`
- `x-terminal/Sources/Tools/XTHubGrantPresentation.swift`
- `x-terminal/Sources/Project/ProjectGovernanceInterceptionPresentation.swift`
- `x-terminal/Sources/Project/XTRouteTruthPresentation.swift`

## 3. End-To-End Flow

### 3.1 Skill / Package Side

执行链：

1. Hub 读取 manifest / catalog / governed dispatch / capability hints
2. Hub 推导 canonical `intent_families`
3. Hub 推导 canonical `capability_families`
4. Hub 推导 canonical `capability_profiles`
5. Hub 汇总 `grant_floor`、`approval_floor`、`runtime_surface_families`
6. XT 读取 resolved registry / cache / doctor snapshot / installed skill
7. XT 结合 project governance ceiling 与 runtime surface readiness
8. XT 生成 `skillExecutionReadiness`
9. Supervisor preflight 基于 readiness 决定 pass / grant / blocked
10. 实际工具执行时再过 runtime deny
11. deny summary 再被转成 governance truth / repair action / route truth

### 3.2 Project Side

除了单个 skill readiness，XT 还会聚合成 project 级快照：

- `discoverable_profiles`
- `installable_profiles`
- `requestable_profiles`
- `runnable_now_profiles`
- `grant_required_profiles`
- `approval_required_profiles`
- `blocked_profiles`

这层真相的作用不是执行，而是：

- 给 project settings / governance surface 用
- 给 supervisor / AI 解释“当前这个项目具备什么能力带宽”
- 给 approval delta 计算当前与请求之间的差值

## 4. How The Main Concepts Work Together

### 4.1 Grant

grant 不是“技能开关”，而是对 capability floor 的 Hub 侧放行。

它解决的是：

- 这次请求是否被 Hub 授权
- 这类高风险能力是否允许进入执行路径
- 作用域和风险等级是否匹配

grant 不能替代：

- package verification
- project ceiling
- runtime surface readiness
- local approval

### 4.2 Readiness

readiness 是当前时刻的综合 verdict。

它至少叠加了这些维度：

- discoverability
- installability
- resolution
- package trust / quarantine / revoke
- project ceiling
- runtime surfaces
- hub connectivity
- grant requirement
- local approval requirement
- degraded 状态

也就是说，`grant_required` 只是 readiness 的一种结果，不是唯一门。

### 4.3 Capability Bundle

bundle 决定的是项目从治理上能走到哪一步。

例子：

- 一个 skill 就算有 `repo.delivery`，A2 项目仍不能交付
- 一个 skill 就算声明 `browser.interact`，A3 项目仍不能 browser runtime
- 一个 skill 就算声明 `device.act`，只有 A4 才可能进入后续 readiness 计算

### 4.4 Action Denial

deny 不是一个布尔值，而是一组证据：

- `deny_code`
- `policy_source`
- `policy_reason`
- `runtime_surface_policy_reason`
- `governance_truth`
- `blocked_summary`
- `repair_action`

这套设计的好处是：

- UI 可以解释
- audit 可以记录
- doctor 可以消费
- timeline 可以保留
- AI 可以根据 deny 选择下一步修复动作

### 4.5 Doctor Truth

doctor truth 主要回答：

- 包是不是可信
- 是不是被 quarantine / revoke
- compatibility 是不是 degraded / unsupported
- resolved snapshot 是否一致
- 当前 install / pin / preflight 有没有断层

doctor truth 不该直接替代 project runtime truth，但它是 readiness 的组成部分。

### 4.6 Route Truth

route truth 回答的是：

- 请求原本想走哪条模型/运行路径
- 实际走到了哪条路径
- fallback reason 是什么
- deny code 是什么
- audit ref 是什么

route truth 不是 capability truth，但它和 capability truth 是互补关系。

典型场景：

- capability 明明允许，但 route fallback 失败
- route 没问题，但 capability 被 clamp
- 医生说 package 正常，但 runtime surface 没 ready

## 5. Concrete Examples

### 5.1 `deviceBrowserControl`

这是最典型的 profile 升级链。

基础观察动作：

- family: `web.live + browser.observe`
- profile: `browser_research`

交互动作如 `click / type / fill / upload`：

- 追加 family: `browser.interact`
- profile 升到 `browser_operator`

如果参数中带 secret 标识：

- 再追加 family: `browser.secret_fill`
- profile 升到 `browser_operator_with_secrets`
- approval floor 会升到 `owner_confirmation`

这说明：

- tool 名相同，不代表 capability level 相同
- action args 会改变 capability families
- secret 参数会进一步抬高 profile 和审批要求

### 5.2 `repo.delivery`

这是典型高阶 side effect。

它通常意味着：

- profile 至少包含 `delivery`
- 闭包包含 `coding_execute`
- grant floor 到 `privileged`
- approval floor 到 `hub_grant_plus_local_approval`

所以它不是普通 repo write，而是“本地改动 + 验证 + 外部交付”的组合面。

### 5.3 Request-Scoped Grant Override

这是当前分支里非常重要的设计点。

对一部分 governed network wrapper：

- 静态 readiness 可能先算成 `policy_clamped`
- 但如果它属于 request-scoped governed network override 范围
- 那么显式 grant 到位后，它可以变成 `grant_required`、`local_approval_required`，甚至 `ready`

这套语义避免了两个错误：

- 把所有 `policy_clamped` 都放宽
- 把所有 governed network wrapper 永久硬拦死

## 6. Current File Map For AI Collaborators

如果下一位 AI 要继续推进 capability 这条线，优先读这些文件。

### 6.1 Canonical Capability Definition

- `docs/memory-new/xhub-skill-capability-profiles-and-execution-readiness-contract-v1.md`
- `docs/memory-new/xhub-skills-capability-grant-chain-contract-v1.md`
- `x-terminal/Sources/Project/XTSkillCapabilityProfileSupport.swift`
- `x-hub/grpc-server/hub_grpc_server/src/skill_capability_derivation.js`

### 6.2 XT Effective Readiness And Project Surface

- `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`
- `x-terminal/Sources/Project/XTProjectSkillRouter.swift`
- `x-terminal/Sources/UI/XTSkillGovernanceSurfaceView.swift`

### 6.3 Supervisor Consumption

- `x-terminal/Sources/Supervisor/SupervisorSkillPreflightGate.swift`
- `x-terminal/Sources/Supervisor/SupervisorManager.swift`

### 6.4 Runtime Enforcement And Explanation

- `x-terminal/Sources/Tools/XTToolRuntimePolicy.swift`
- `x-terminal/Sources/Tools/XTGuardrailMessagePresentation.swift`
- `x-terminal/Sources/Tools/XTHubGrantPresentation.swift`
- `x-terminal/Sources/Project/ProjectGovernanceInterceptionPresentation.swift`

### 6.5 Governance Bundle / Ceiling

- `x-terminal/Sources/Project/AXProjectExecutionTier.swift`
- `x-terminal/Sources/Project/AXProjectGovernanceBundle.swift`
- `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`

### 6.6 Route / Doctor / Evidence

- `x-terminal/Sources/Project/AXModelRouteDiagnostics.swift`
- `x-terminal/Sources/Project/XTRouteTruthPresentation.swift`
- `x-hub/grpc-server/hub_grpc_server/src/channel_onboarding_delivery_readiness.js`
- `x-hub/grpc-server/hub_grpc_server/src/channel_command_gate.js`

## 7. No-Regression Rules

继续做这条线时，默认必须守住这些规则。

### 7.1 不要把 Capability Bundle 和 Runtime Surface 混为一层

- A-Tier base bundle 是治理 ceiling
- runtime surface 是动态运行面 clamp
- trusted automation readiness 是设备态真相

三者不可互相替代。

### 7.2 不要让 Profile 代替 Authority

- profile 是暴露层语义
- package verify / pin / revoke / grant / approval 才是 authority
- 任何 profile 都不能绕过 Hub-first trust chain

### 7.3 不要再发明第二套 Blocked Vocabulary

如果要解释 blocked，优先复用：

- typed readiness
- runtime deny evidence
- guardrail presentation

不要在 timeline、settings、doctor、supervisor chat 各自再造一套半兼容词表。

### 7.4 不要把 `grantRequestId` 当成执行 token

审批 request token 和真正执行期 capability token 不是同一件事。

### 7.5 不要把 Pure Wrapper 和 Mixed Skill 的 Override 语义放宽成一刀切

request-scoped grant override 必须保持窄口径。

### 7.6 不要只改 XT 不改 Hub 语义检查

Hub JS 与 XT Swift 都持有 capability derivation 逻辑。
当前体系允许双端实现，但不允许双端语义无意漂移。

## 8. Recommended Next Improvements

### 8.1 Single Capability Contract Source

把 family/profile/floor/runtime-surface 映射收口成一个 versioned contract，再生成到 Swift/JS 两侧。

这是最高优先级的结构优化。

### 8.2 Multi-Axis Readiness

把当前单一 readiness state 进一步拆成：

- structural readiness
- trust readiness
- policy readiness
- surface readiness
- temporal readiness

现在的 enum 足够执行，但不够解释复杂问题。

### 8.3 First-Class Capability Delta Approval

把 `XTProjectEffectiveSkillProfileSnapshot + XTSkillProfileDeltaApproval` 真正变成主流程。

目标不是只告诉用户“被拦了”，而是告诉用户：

- 当前能跑什么
- 这次想新增什么
- 需要什么 grant / approval
- 有效期多久

### 8.4 Capability Lease

建议在 grant / local approval 之上补一层 capability lease：

- project-scoped
- family/profile-scoped
- TTL-bound
- target/domain-bound
- secret-class-bound

这会比今天的 static grant 更适合受治理自动化。

### 8.5 Evidence Ledger

建议把以下字段收口成统一 capability evidence ledger：

- package sha
- trust root hash
- resolved snapshot id
- grant snapshot ref
- governance truth
- route truth
- doctor/vetter refs
- runtime surface truth

这样 doctor 和排障才能回答“为什么昨天能跑，今天不能跑”。

## 9. Recommended Read Order For A New AI

如果新的 AI 要继续这一条线，建议按这个顺序读：

1. `docs/memory-new/xhub-capability-operating-model-and-ai-handoff-v1.md`
2. `docs/memory-new/xhub-skill-capability-profiles-and-execution-readiness-contract-v1.md`
3. `docs/memory-new/xhub-skills-capability-grant-chain-contract-v1.md`
4. `docs/memory-new/xhub-ld-trust-capability-route-continuity-and-handoff-v1.md`
5. `x-terminal/Sources/Project/XTSkillCapabilityProfileSupport.swift`
6. `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`
7. `x-terminal/Sources/Supervisor/SupervisorSkillPreflightGate.swift`
8. `x-terminal/Sources/Tools/XTToolRuntimePolicy.swift`
9. `x-hub/grpc-server/hub_grpc_server/src/skill_capability_derivation.js`

如果任务偏 product UI / why blocked / repair action，再补：

- `x-terminal/Sources/UI/XTSkillGovernanceSurfaceView.swift`
- `x-terminal/Sources/Tools/XTGuardrailMessagePresentation.swift`
- `x-terminal/Sources/Project/ProjectGovernanceInterceptionPresentation.swift`

如果任务偏模型为什么这样路由、doctor 为什么这样解释，再补：

- `x-terminal/Sources/Project/AXModelRouteDiagnostics.swift`
- `x-terminal/Sources/Project/XTRouteTruthPresentation.swift`

## 10. Scope Guard

这份文档的定位不是替代现有 contract，也不是重复实现 pack。

它只负责三件事：

- 解释这套 capability 运行模型到底怎么分层
- 指明每一层当前代码真相在哪
- 告诉下一位 AI 哪些边界不能被误改
