# XT-W3-41 Skill Capability Profiles + Readiness Surface Implementation Pack v1

- owner: XT-L2（Primary）/ Hub Runtime / Supervisor / Security / QA / Product
- status: planned
- last_updated: 2026-03-28
- purpose: 在不削弱 `Hub-first governance` 的前提下，把当前 governed skill system 补上一层 OpenClaw 风格但更安全的 capability profile / readiness / approval-delta 抽象，并把它统一接到 Hub、XT、Supervisor、UI。
- depends_on:
  - `docs/memory-new/xhub-skill-capability-profiles-and-execution-readiness-contract-v1.md`
  - `docs/memory-new/xhub-skills-capability-grant-chain-contract-v1.md`
  - `docs/xhub-skills-fail-closed-chain-v1.md`
  - `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`

## 0) 先看这份包在解决什么

当前系统已经具备：

- Hub package verify / pin / resolve / revoke / vetter / doctor 主链
- XT resolved cache / governed routing / local approval / activity feed
- Supervisor callback follow-up / pending approvals / recent activity / audit writeback

真正缺口不在底层治理，而在三件事：

1. 模型和用户看到的能力语言仍然分散在 `ToolProfile`、A-Tier、skill registry 三层。
2. readiness 仍有一部分靠字符串和 UI 文案推断，不够稳。
3. 审批仍偏向“批准这次工具调用”，而不是“批准这次 profile delta”。

本包的目标就是把这三件事正式产品化。

## 1) 总交付物

本包毕业时，必须同时交付以下对象：

1. `xt.project_effective_skill_profile.v1`
2. `xhub.skill_execution_readiness.v1`
3. `xt.skill_profile_delta_approval.v1`
4. capability family / capability profile / intent family 冻结词表
5. legacy `ToolProfile` -> new profile 的兼容映射

必须落到真实代码与证据，而不是只停在文档：

- Hub index / search / pin / resolve / doctor surface 出现 canonical profile/readiness truth
- XT cache / settings / slash tools / prompt surface 统一消费 profile truth
- Supervisor preflight / routing / approval board 不再依赖字符串判断
- UI 能稳定区分 `discoverable / installable / requestable / runnable_now`

## 2) 当前文件触点总表

Hub 主触点：

- `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
- `x-hub/grpc-server/hub_grpc_server/src/skills_client.js`
- `x-hub/grpc-server/hub_grpc_server/src/official_skill_channel_sync.js`
- `x-hub/grpc-server/hub_grpc_server/src/official_skill_channel_maintenance.js`
- `x-hub/grpc-server/hub_grpc_server/src/agent_skill_vetter.js`

XT / Project 主触点：

- `x-terminal/Sources/Tools/ToolProtocol.swift`
- `x-terminal/Sources/Project/AXProjectConfig.swift`
- `x-terminal/Sources/Project/AXProjectGovernanceTemplate.swift`
- `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`
- `x-terminal/Sources/Project/XTResolvedSkillsCacheStore.swift`
- `x-terminal/Sources/Project/XTProjectSkillRouter.swift`

Supervisor 主触点：

- `x-terminal/Sources/Supervisor/SupervisorSkillRegistrySnapshot.swift`
- `x-terminal/Sources/Supervisor/SupervisorSkillPreflightGate.swift`
- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- `x-terminal/Sources/Supervisor/SupervisorPendingSkillApprovalPresentation.swift`

UI 主触点：

- `x-terminal/Sources/UI/ProjectSettingsView.swift`
- `x-terminal/Sources/UI/XTSkillGovernanceSurfaceView.swift`
- `x-terminal/Sources/UI/XTOfficialSkillsBlockerListView.swift`
- `x-terminal/Sources/UI/XTBuiltinGovernedSkillsListView.swift`
- `x-terminal/Sources/UI/MessageTimeline/ProjectSkillActivityPresentation.swift`
- `x-terminal/Sources/UI/MessageTimeline/PendingToolApprovalView.swift`
- `x-terminal/Sources/Tools/XTPendingApprovalPresentation.swift`
- `x-terminal/Sources/ContentView.swift`

Official package samples that must被 backfill：

- `official-agent-skills/find-skills/skill.json`
- `official-agent-skills/agent-browser/skill.json`
- `official-agent-skills/tavily-websearch/skill.json`
- `official-agent-skills/default_agent_baseline.v1.json`

## 3) P0 Work Orders

### XT-W3-41-A Hub Canonical Capability Derivation + Registry Surface

- priority: `P0`
- goal: 让 Hub 成为 capability family / capability profile / intent family / grant floor / approval floor 的 canonical derivation source。

实施要求：

1. 在 `skills_store.js` 中新增 canonical derivation：
   - 输入：`governed_dispatch`, `governed_dispatch_variants`, `capabilities_required`, `risk_level`, `requires_grant`, `skill_id`
   - 输出：
     - `intent_families`
     - `capability_families`
     - `capability_profiles`
     - `grant_floor`
     - `approval_floor`
2. official skill 或 high-risk skill 的 manual hint 与 canonical derivation 冲突时 fail-closed：
   - `deny_code=profile_hint_mismatch`
3. 这些字段必须写进：
   - `skills_store_index.json`
   - `searchSkills()` 返回值
   - resolved package meta
4. official channel sync 后生成的 snapshot 也必须带这些字段。

目标文件：

- `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
- `x-hub/grpc-server/hub_grpc_server/src/official_skill_channel_sync.js`
- `x-hub/grpc-server/hub_grpc_server/src/agent_skill_vetter.js`

回归要求：

- `skills_store_manifest_compat.test.js`
- `skills_store_official_agent_catalog.test.js`
- `skills_store_security.test.js`
- 新增 `skills_store_profile_derivation.test.js`

验收点：

- search / pin / resolve 不丢 profile fields
- revoked / quarantined skill 永不输出为 runnable candidate
- official skills 全量带 canonical families / profiles

### XT-W3-41-B XT Effective Profile Snapshot + Legacy Hardening

- priority: `P0`
- goal: 让 XT 生成项目级 `xt.project_effective_skill_profile.v1`，并收掉旧 `ToolProfile` 的 fail-open 行为。

实施要求：

1. `ToolProtocol.swift`
   - `invalid/unknown` profile 不再 fallback 到 `full`
   - fallback 统一改为 `observe_only`
   - `full` 只作为 legacy alias 输入
2. `AXProjectConfig.swift`
   - 保留 `toolProfile/toolAllow/toolDeny`
   - 新增 `profileEpoch` 所需的输入摘要
3. `AXProjectGovernanceTemplate.swift`
   - 固化 A-Tier -> max profile ceiling 映射
4. `AXSkillsLibrary+HubCompatibility.swift`
   - 新增 `projectEffectiveSkillProfileSnapshot(...)`
   - 同时算出：
     - `discoverable_profiles`
     - `installable_profiles`
     - `requestable_profiles`
     - `runnable_now_profiles`
5. `XTResolvedSkillsCacheStore.swift`
   - cache 里加：
     - `profile_epoch`
     - `trust_root_set_hash`
     - `revocation_epoch`
     - `official_channel_snapshot_id`
     - `runtime_surface_hash`

目标文件：

- `x-terminal/Sources/Tools/ToolProtocol.swift`
- `x-terminal/Sources/Project/AXProjectConfig.swift`
- `x-terminal/Sources/Project/AXProjectGovernanceTemplate.swift`
- `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`
- `x-terminal/Sources/Project/XTResolvedSkillsCacheStore.swift`

验收点：

- 任何未知 `toolProfile` 都不会把项目扩成 `full`
- `a0Observe -> observe_only`
- `a4OpenClaw` 只是 ceiling，不是自动 runnable
- cache epoch 变更会立刻让旧 resolved snapshot 失效

### XT-W3-41-C Typed Readiness + Supervisor Preflight Cutover

- priority: `P0`
- goal: 用 `xhub.skill_execution_readiness.v1` 取代 Supervisor 对字符串 readiness 的推断。

实施要求：

1. `AXSkillsLibrary+HubCompatibility.swift`
   - 新增 per-skill readiness 生成函数
2. `SupervisorSkillRegistrySnapshot.swift`
   - registry item 增加：
     - `intentFamilies`
     - `capabilityFamilies`
     - `capabilityProfiles`
     - `grantFloor`
     - `approvalFloor`
3. `SupervisorSkillPreflightGate.swift`
   - 不再做 `contains("grant required") / contains("quarantined") / contains("blocked")`
   - 改为消费 typed readiness
4. `SupervisorManager.swift`
   - dispatch / retry / approval resume 路径全部改读 typed readiness
5. `XTProjectSkillRouter.swift`
   - 保留 `skill_id` 主路由
   - additive 支持 `intent_families`

目标文件：

- `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`
- `x-terminal/Sources/Supervisor/SupervisorSkillRegistrySnapshot.swift`
- `x-terminal/Sources/Supervisor/SupervisorSkillPreflightGate.swift`
- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- `x-terminal/Sources/Project/XTProjectSkillRouter.swift`

验收点：

- `string_contains_preflight_logic = 0`
- blocked/grant/local approval/runtime unavailable 能被稳定地区分
- retry path、approval resume path、callback path 全部沿用同一 readiness enum

### XT-W3-41-D Approval Delta Surface + Unified UX Copy

- priority: `P0`
- goal: 让审批从“这次 tool 是什么”升级到“这次放开的 profile delta 是什么”。

实施要求：

1. 新增 `xt.skill_profile_delta_approval.v1`
2. `PendingToolApprovalView.swift`
   - 展示：
     - 当前 runnable profiles
     - 本次请求 profiles
     - delta profiles
     - grant floor / approval floor
3. `XTPendingApprovalPresentation.swift`
   - 统一拼装 summary / next step / supplementary reason
4. `SupervisorPendingSkillApprovalPresentation.swift`
   - 直接展示 routing + profile delta
5. `ProjectSkillActivityPresentation.swift`
   - blocked/awaiting_approval/result timeline 统一显示 typed readiness + delta approval summary

目标文件：

- `x-terminal/Sources/UI/MessageTimeline/PendingToolApprovalView.swift`
- `x-terminal/Sources/Tools/XTPendingApprovalPresentation.swift`
- `x-terminal/Sources/Supervisor/SupervisorPendingSkillApprovalPresentation.swift`
- `x-terminal/Sources/UI/MessageTimeline/ProjectSkillActivityPresentation.swift`
- `x-terminal/Sources/Supervisor/SupervisorManager.swift`

验收点：

- 用户能看到“当前项目已有能力”和“这次额外放开了什么”
- local approval 与 Hub grant 的关系能被清楚区分
- timeline、approval board、system message 使用同一套 reason code

## 4) P1 Work Orders

### XT-W3-41-E Search / Settings / Governance Surface 四态统一

- priority: `P1`
- goal: 让 `discoverable / installable / requestable / runnable_now` 在所有 UI 面一致可见。

实施要求：

1. `XTSkillGovernanceSurfaceView.swift`
   - 从“专家卡片”升级成四态展示
2. `XTOfficialSkillsBlockerListView.swift`
   - blocked item 必须带 `why_not_runnable + unblock_actions`
3. `ProjectSettingsView.swift`
   - 增加 profile summary 卡
4. `ContentView.swift`
   - baseline / import / enable 入口根据四态调整按钮文案

验收点：

- Settings、toolbar、blocker list、timeline 四态语义一致
- 任一 blocked item 都能回答“为什么现在不能跑”“怎么解锁”

### XT-W3-41-F Intent-Family Router Upgrade

- priority: `P1`
- goal: 降低模型对具体 `skill_id` 的记忆负担，允许 Router 逐步转向 `intent_families`。

实施要求：

1. registry snapshot 暴露 `intentFamilies`
2. Router 支持：
   - `skill_id` 命中时按现状运行
   - `intent_families` 命中时从 runnable/requestable skills 中做 deterministic selection
3. selection 规则必须固定：
   - project scope pin 优先
   - lower approval/grant burden 优先
   - official package 优先
   - package sha256 字典序兜底

验收点：

- 同一输入多次 selection 结果 deterministic
- `intent_families` 缺失时不破坏老行为

### XT-W3-41-G Bundle / Baseline Productization

- priority: `P1`
- goal: 把 baseline 从“skill 列表”升级成“profile-aware bundle”。

实施要求：

1. `default_agent_baseline.v1.json`
   - 增加 bundle 级 profile 元数据
2. 支持至少三类 bundle：
   - `coding-core`
   - `browser-research`
   - `supervisor-retrospective`
3. install flow 必须显示：
   - bundle 将带来哪些 profiles
   - 当前哪些 profiles 仍会 blocked

验收点：

- 用户安装 bundle 前就能看到 profile delta
- builtin catalog 但无 uploadable package 的 bundle 不得假装 ready

## 5) P2 Work Orders

### XT-W3-41-H Approval / Grant / Memory Evidence Harmonization

- priority: `P2`
- goal: 把 profile delta 进一步写进 recent activity、memory、audit evidence，支持 Supervisor 后续诊断。

实施要求：

1. `SupervisorProjectSkillCallStore`
   - 持久化 profile delta refs
2. `SupervisorSkillResultEvidenceStore`
   - 写入最终 readiness / delta / unblock action snapshot
3. recent activity 与 memory digest 统一使用 profile nouns，而不是裸 `tool_name`

### XT-W3-41-I Import Normalizer Profile Mapping

- priority: `P2`
- goal: imported skill 在进入主链前必须被归并到 canonical profiles / families，而不是直接沿用上游词表。

实施要求：

1. `XTAgentSkillImportNormalizer`
   - 产出 `intent_families`, `capability_profile_hints`
2. Hub promote path
   - 记录 canonical derivation 与 upstream hint 的差异
3. critical mismatch -> quarantine / fail-closed

## 6) 测试与证据

最低证据文件：

- `build/reports/xt_w3_35_skill_profiles_contract_report.v1.json`
- `build/reports/xt_w3_35_readiness_surface_report.v1.json`
- `build/reports/xt_w3_35_approval_delta_report.v1.json`

最低回归集：

- Hub:
  - `skills_store_profile_derivation.test.js`
  - `skills_store_manifest_compat.test.js`
  - `skills_store_official_agent_catalog.test.js`
- XT / Supervisor:
  - `SupervisorSkillPreflightGate` typed readiness tests
  - resolved cache epoch invalidation tests
  - approval delta presentation tests
  - router deterministic intent-family tests

## 7) Gate / DoD

本包 DoD：

- contract doc、JSON contract、code、tests、UI copy、evidence 全部同步完成
- `ToolProfile full` 不再是实际 authority
- typed readiness 在 XT / Supervisor / UI 全链路成立
- profile delta 审批成立
- baseline / import / settings / timeline 四态语义一致

本包 Gate：

- `legacy_full_profile_fail_open = 0`
- `string_contains_preflight_logic = 0`
- `runnable_now_false_positive = 0`
- `blocked_without_unblock_actions = 0`
- `profile_state_mismatch_across_surfaces = 0`

## 8) 回滚点

- `RB-XTW335-001`：只回滚 UI / prompt exposure，保留 Hub canonical derivation 字段。
- `RB-XTW335-002`：若 typed readiness 误判，可在短期内双读旧字符串字段，但不得回退 Hub revocation / pin / resolve 主链。
- `RB-XTW335-003`：若 approval delta surface 影响审批体验，可回退到旧审批卡 UI，但审批对象落盘格式不得删除。
