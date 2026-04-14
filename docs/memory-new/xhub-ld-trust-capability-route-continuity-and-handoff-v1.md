# X-Hub LD Trust / Capability / Route Continuity And Handoff v1

- Status: Active
- Updated: 2026-03-29
- Owner: Hub Runtime / XT Pairing / XT-L2 / Supervisor / QA
- Purpose: 把 `LD Trust / Capability / Route` 这条线和既有 `XT-W3-34` / `XT-W3-41` 实现之间的连续性、边界和禁止回归点正式冻结，避免后续 AI 只看 lane 名称就误拆、误并或回退已落地语义。
- Parent:
  - `docs/memory-new/xhub-parallel-control-plane-roadmap-v1.md`
  - `docs/memory-new/xhub-parallel-control-plane-lane-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-41-skill-capability-profiles-and-readiness-surface-implementation-pack-v1.md`

## 0) Conclusion First

`LD` 的主职责不是“继续做 skill 内容”，而是把系统关于以下问题的 truth source 收口：

- 这次动作现在为什么能做 / 不能做
- 缺的是 grant、approval、runtime surface 还是 package/install truth
- official skill、imported skill、XT builtin wrapper 到底在 capability/readiness 上是什么
- route / pairing / doctor / readiness 为什么给出当前解释

按旧工单映射，当前最适合持续推进的 ownership 是：

- Primary:
  - `XT-W3-41-C Typed Readiness + Supervisor Preflight Cutover`
  - `XT-W3-41-H Approval / Grant / Memory Evidence Harmonization`
- Secondary / additive:
  - `XT-W3-41-I Import Normalizer Profile Mapping`
  - `XT-W3-41-A` 中直接影响 canonical capability derivation 的 seam

当前不应作为 `LD` 主 owner 直接展开：

- `XT-W3-41-D`、`XT-W3-41-E`
  - 这些主要是 `LF UX / Release` 面
- `XT-W3-41-G`
  - truth 在 `LD`，但 bundle/product 表面不在 `LD`
- `XT-W3-41-F`
  - 必须排在 `B/C/H` 语义稳定之后

## 1) How LD Continues Earlier Work

### 1.1 `XT-W3-34` 是执行面基底

`XT-W3-34` 回答的是：

- imported skill 怎么 normalize / preflight / vetter / quarantine
- governed skill 怎么 pin / resolve / cache / route
- baseline / bundle / uploadable package 的真实安装链怎么走
- structured skill result evidence 如何写回

这条线已经把“skill 作为 governed execution surface”立起来了。

### 1.2 `XT-W3-41` 是语义真相层

`XT-W3-41` 叠加回答的是：

- capability family / profile / intent family 的 canonical truth 是什么
- skill 当前是 `discoverable / installable / requestable / runnable_now` 中哪一态
- pending 的到底是 Hub grant、local approval、policy clamp 还是 runtime unavailable
- approval 应该批准“这次 profile delta”而不只是“这次工具名”

这条线不是重做 `XT-W3-34`，而是把 `XT-W3-34` 上的执行面提升成统一 capability/readiness truth。

### 1.3 新 lane 体系下的准确归属

在 `xhub-parallel-control-plane-lane-work-orders-v1.md` 冻结后的体系里：

- `LD-2` 对应 `Capability / Grant / Runtime Readiness`
- `LD-4` 对应 `Skills Readiness Surface`

所以当前连续推进应描述为：

- 在 `LD` 下继续做 `XT-W3-41` 的 capability/readiness/profile truth
- 以 `XT-W3-34` 的 import/governed execution substrate 为前提

## 2) Branch Reality Already Landed

当前分支上已经有几条必须被继承的行为，不允许后续 AI 无意回退：

### 2.1 Request-scoped grant semantics 已补强

- Supervisor pending skill call 会单独记录 `grantRequestId`
- pending `grantRequestId` 不应再被直接当作“已批准可执行 grant”
- resume / approval resolution 路径必须把“请求号”和“执行期 grant token”分开处理

### 2.2 Import canonical mapping 已落地第一段

- XT import normalizer 已产出 `intent_families` / `capability_profile_hints`
- Hub promote path 已保留 canonical derivation 与 upstream hint 的差异
- 对 high-risk / official-like mismatch 已要求 quarantine / fail-closed

### 2.3 Official governed network wrapper semantics 已对齐

- `web_fetch / web_search / browser_read` 这一类 governed network wrapper
- 即使静态 profile/readiness 上推导出 `policy_clamped`
- 在 Supervisor 里也不总是终态 deny
- 对显式 Hub grant 的 request-scoped 路径，必须能继续进入 `grant_required -> ready`

## 3) No-Regression Invariants

以下不变量是 handoff 时必须显式告诉下一位 AI 的；它们不一定都能从高层 lane 文档直接看出来，但属于当前实现真相的一部分。

### 3.1 `grantRequestId != grant_id`

- `grantRequestId` 是审批、follow-up、callback、deep-link、activity timeline 用的 request token
- 执行工具时允许通过 gate 的，必须是 `grant_id`
- 如果 Hub 只返回了 request id，XT 本地执行层应生成独立 execution grant token，再把它写到 `grant_id`
- 不允许把 `grant_request_id` 直接当执行期 capability token

### 3.2 Official wrapper 的 `policy_clamped` 不是总是终态 deny

- official governed wrapper skill 通常比 builtin wrapper 带有更丰富的 capability/grant/profile 元数据
- 对 governed network wrapper，Supervisor 需要把一部分静态 `policy_clamped` 解释为“当前需 grant 的 requestable 候选”
- 不能因为 XT 的原始 tool policy deny，就把显式 Hub grant 后的恢复路径也一起封死
- 这条放开必须保持窄：
  - action-scoped preflight 只对真实映射出的 `web_fetch / web_search / browser_read` 生效
  - generic skills surface / snapshot 只对 pure governed network wrapper 生效
  - 不允许把所有 `policy_clamped` skill 一律降成 `grant_required`
- mixed skill 例如 `agent-browser`：
  - action-aware preflight 在本次映射已收敛到 `browser_read` 时，可以进入 request-scoped grant 语义
  - generic governance surface / profile snapshot 仍应保持保守，除非 registry 真能证明它是 pure wrapper

### 3.3 `XT-W3-41-I` 只能 additive，不能取代 import trust chain

- canonical mapping 只是补 capability/profile truth
- provenance、vetter、quarantine、promote fail-closed 仍然由 `XT-W3-34-A/J` 主链负责
- 不允许为了统一词表，把上游差异或 vetter evidence 抹掉

### 3.4 `XT-W3-41-G` 不得假装 bundle ready

- `XT-W3-34-K` 已经锁定：
  - builtin catalog 但没有 uploadable package 的 baseline skill 不能假安装
- profile-aware bundle productization 必须继承这个真相
- UI / doctor / release wording 不得把“catalog 可见”说成“当前可执行”

### 3.5 `XT-W3-41-F` 不能跑在 readiness truth 前面

- intent-family router selection 依赖稳定的 runnable/requestable truth
- 如果 `B/C/H` 没稳定，`F` 只会把旧字符串判断的问题隐藏到 deterministic routing 里

## 4) Recommended Next Slice Order

当前推荐继续顺序：

1. 继续收口 `LD-2`
   - grant / approval / runtime ready 的 request-scoped 语义
   - execution token 与 request token 分离
   - deny reason normalization
2. 继续收口 `LD-4`
   - skills readiness surface 统一消费 typed readiness
   - doctor / settings / governance surface 不再发明第二套 blocked 词表
3. 然后才考虑：
   - `XT-W3-41-F`
   - 更宽的 route / context budget / cost governor 收口

## 5) Write Roots And Avoids

当前优先 write roots：

- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- `x-terminal/Sources/Supervisor/SupervisorSkillPreflightGate.swift`
- `x-terminal/Sources/Supervisor/SupervisorSkillRegistrySnapshot.swift`
- `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`
- `x-terminal/Sources/Project/XTAgentSkillImportNormalizer.swift`
- `x-terminal/Sources/Project/XTProjectSkillRouter.swift`
- `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
- `x-terminal/Sources/Tools/ToolExecutor.swift`

当前默认 avoid：

- 大面积 memory assembly 文件
- `LA` run lifecycle 主状态机
- `LF` 主 UI 视图和 release wording 文件
- `LB` effective governance resolver 主实现

## 6) Minimum Regression Set

后续继续 `LD` 时，至少要守住这些回归：

- `x-terminal/Tests/ToolExecutorWebSearchGrantGateTests.swift`
  - `webSearchFailsClosedWithoutGrantAndKeepsStructuredHeader`
  - `browserReadRejectsMissingURLWithStructuredFailure`
  - `grantRequestIdIsNotAcceptedAsExecutableGrantToken`
    - `grant_request_id` 不得被当作可执行 `grant_id`
    - 合法 execution grant token 在无 bridge 环境下也应先通过 token 语义校验，再因为 bridge 不可用而失败
- `x-terminal/Tests/SupervisorCommandGuardTests.swift`
  - official governed wrapper without grant waits for Hub grant
  - approved grant resumes awaiting official wrapper skill
  - approved Hub grant without explicit `grantId` uses synthetic execution grant token
  - approved Hub grant without explicit `grantId` uses synthetic execution grant token for builtin `web.search`
- `x-terminal/Tests/XTAgentSkillImportNormalizerTests.swift`
  - canonical profile hint mapping / mismatch quarantine
- `x-terminal/Tests/AXSkillsCompatibilityTests.swift`
  - readiness snapshot / resolved cache epoch / governance surface truth
- `x-hub/grpc-server/hub_grpc_server/src/*test.js`
  - profile derivation / catalog security / official channel compat

### 6.1 Verified On 2026-03-29

本轮已经实际跑过并通过：

- `swift test --filter ToolExecutorWebSearchGrantGateTests`
- `swift test --filter officialTavilyWebsearchWithoutGrantWaitsForHubGrant`
- `swift test --filter approvedHubGrantResumesAwaitingOfficialTavilyWebsearchSkill`
- `swift test --filter approvedHubGrantWithoutGrantIdUsesSyntheticExecutionGrantToken`
- `swift test --filter approvedHubGrantWithoutGrantIdUsesSyntheticExecutionGrantTokenForBuiltinWebSearch`
- `swift test --filter supervisorSkillPreflightGatePromotesPolicyClampedAgentBrowserReadActionIntoGrantRequired`
- `swift test --filter projectAwareGovernanceSurfaceTreatsPureGovernedWebSearchWrapperAsGrantRequestable`
- `swift test --filter projectEffectiveSkillProfileSnapshotPromotesPureGovernedWebSearchWrapperIntoGrantRequiredProfiles`
- `swift test --filter projectSkillRouterIntentFallbackTreatsPureGovernedWebSearchWrapperAsRequestable`
- `swift test --filter chatSessionProjectSkillActivityReadinessUsesEffectiveGrantRequiredTruthForPureGovernedWebWrapper`
- `swift test --filter blockedGrantRequiredBodyUsesHubAuthorizationGuidance`
- `swift test --filter displayTimelineDetailLocalizesGrantRequiredDenyCode`
- `swift test --filter fullRecordUsesPersistedRequiredCapabilityFromProjectActivityRawLog`

### 6.2 New Freeze Added On 2026-03-29

- `SupervisorSkillPreflightGate`
  - 对 action-scoped `browser_read` / `web_search` / `web_fetch`，允许把 mixed governed skill 的静态 `policy_clamped` 提升成 `grant_required`
  - 这里的提升只改变 effective readiness / preflight 解释，不改变 `grantRequestId != grant_id` 的执行 token 不变量
- `AXSkillGovernanceSurface` / `XTProjectEffectiveSkillProfileSnapshot`
  - 只对 pure governed network wrapper，把静态 `policy_clamped` 显示为 `grant_required` / `requestable`
  - pure wrapper 的判断依赖 registry dispatch truth，不能靠 skill 名字模糊猜测
- `XTProjectSkillRouter`
  - intent-family fallback 也必须消费同一套 effective readiness
  - 不允许出现 surface / snapshot 已把 pure wrapper 视为 `requestable`，router 却仍按原始 `policy_clamped` 把候选当 blocked
- `ChatSessionModel`
  - project skill activity / timeline 写回的 readiness 也必须消费同一套 effective readiness
  - 不允许 surface / snapshot / router 已显示 pure wrapper 为 `grant_required`，但 project activity 事件仍回写原始 `policy_clamped`
  - `awaiting_approval` 类事件应尽量保留 readiness 导出的 `deny_code`，这样 timeline 能区分“等待 Hub grant”与“等待本地审批”
- `ProjectSkillActivityPresentation`
  - project timeline / full-record / detail 本地化也必须把 `grant_required` 显示成 “等待 / 继续前需 Hub 授权”
  - 不允许 raw activity 已写回 `grant_required`，但用户可见的 project timeline 仍退回“本地审批”文案
- `AXProjectSkillActivityStore` / project activity raw log
  - 对 governed network wrapper，project skill activity 事件应尽量保留 `required_capability`
  - 这样 full-record / timeline detail / detail localization 可以显示“到底缺哪类 Hub 授权”，而不只是泛化成 grant 文案
- `XTSkillCapabilityProfileSupport`
  - 现在持有统一 helper，用来判断 request-scoped governed network override eligibility
  - 下一位 AI 如果继续收 `LD-4`，默认应复用这套 helper，不要再在 `SupervisorManager`、surface、snapshot 各写一份平行分支

如果当前任务是“新的 AI 要快速接 `LD` 并且不想重翻聊天记录”，先读本文档，再回到 lane pack 和 `XT-W3-41` / `XT-W3-34` 父包。
