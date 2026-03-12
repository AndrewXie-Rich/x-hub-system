# XT-W3-33 Supervisor Decision Kernel + Routing + Memory Governance 实施包

- version: v1.0
- updatedAt: 2026-03-11
- owner: XT-L2（Primary）/ Hub-L5 / QA / Product / Security
- status: planned
- scope: `XT-W3-33`（把 Supervisor 从“能看 portfolio、能做编排建议”的控制台，升级成“有正式决策轨、角色化模型路由、动作优先 dashboard、低风险默认建议、可解释记忆压缩”的受治理控制面）
- parent:
  - `x-terminal/work-orders/xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-supervisor-rhythm-user-explainability-implementation-pack-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/xhub-memory-system-spec-v2.md`
  - `docs/xhub-multi-model-orchestration-and-supervisor-v1.md`
  - `docs/xhub-agent-efficiency-and-safety-governance-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## 0) 为什么要单独开这份包

`XT-W3-31` 已经把 Supervisor 的“看见什么”做出来了：

- portfolio
- project capsule
- current action
- blocker / next step
- event delta
- scope-safe drill-down

`XT-W3-32` 已经在补 Supervisor 的“如何调度执行面”：

- skills
- job / plan
- callback event loop
- governed dispatch

但在真实使用中，还存在一个中间层缺口：

1. 哪些信息算“正式决策”，哪些只是“背景偏好”，目前还不够结构化。
2. 项目规格（goal / MVP / non-goals / tech stack / milestones）仍偏分散，Supervisor 经常要临时推导下一步。
3. 模型路由目前更像“项目级偏好”，还不是 `planner/coder/reviewer/doc/ops` 角色级策略。
4. Dashboard 还偏“状态可见”，不够“动作优先”。
5. 决策型 blocker 还没有受治理的默认建议机制。
6. L2/L3 还缺项目完成后的结构化压缩与归档规则。

所以 `XT-W3-33` 的目标不是再造第三套记忆系统，而是把现有 Hub truth-source 之上再补一层“Supervisor 决策内核”：

- 正式决策与背景偏好分轨
- 项目规格胶囊化
- 角色化模型路由
- 动作优先 Dashboard
- 低风险默认建议
- 可解释的记忆压缩

这样 Supervisor 才能做到：

- 更少扫全文
- 更少误把随口一说当正式要求
- 更稳定地判断“下一步该插手谁、建议谁、路由给谁”

## 1) 固定决策

### 1.1 真相源不变

- 项目长期真相源继续在 Hub。
- XT 继续只负责：
  - 控制面 UI
  - 短 TTL cache
  - 交互式判断与提示
- 不新增第二套 XT 侧长期项目真相源。

### 1.2 正式决策与背景偏好必须分轨

- `decision_track`：正式要求、冻结边界、审批结果、技术栈定案、风险口径。
- `background_preference_track`：风格偏好、体验倾向、弱约束习惯。

原则：

- `decision_track` 是强约束。
- `background_preference_track` 只能弱参考。
- 背景偏好不得静默覆盖正式决策。

### 1.3 Role Routing 的职责边界

- XT Supervisor 负责输出“意图”：
  - `planner`
  - `coder`
  - `reviewer`
  - `doc`
  - `ops`
- Hub 继续负责：
  - AI registry
  - grant / paid-model gate
  - budget / quota
  - trust / authorization

换句话说：

- XT 决定“该找哪类 AI”
- Hub 决定“具体能不能用、能用哪个、额度够不够”

### 1.4 决策型 blocker 只能做受治理默认建议

Supervisor 允许给出默认建议，但必须分级：

- `proposal_only`
- `proposal_with_timeout_escalation`
- `auto_adopt_if_policy_allows`

硬限制：

- 不可逆决策禁止自动采纳
- 高风险 / 安全 / release scope / 对外副作用决策禁止自动采纳
- 未经用户或 Hub 授权的正式决策不得自动变成 `approved`

### 1.5 记忆压缩必须可解释、可回放

允许压缩：

- 老 observation
- 已完成项目的细碎 action log
- 长期不再参与当前路由的历史片段

不允许压缩掉：

- 正式决策节点
- 审批节点
- 里程碑节点
- release / rollback / gate 证据 refs

### 1.6 对外口径不扩 scope

`XT-W3-33` 是内部控制面增强，不改变当前 GitHub validated-mainline-only 对外口径。

## 2) 产品目标

### 2.1 用户视角

用户打开 Supervisor 时，不只是看到状态，还应该自然知道：

- 哪些项目缺正式规格
- 哪些项目卡在“纯决策 blocker”
- 哪些项目有下一步但长期没动
- 哪些项目已经适合归档
- 当前该优先处理哪一件事

### 2.2 Supervisor 视角

Supervisor 应该能稳定回答：

- 这个要求是不是正式决策
- 这条项目应该路由给哪类 AI
- 这个 blocker 是外部阻塞还是可给默认方案的决策阻塞
- 这个项目还值不值得继续保活
- 哪些历史 observation 应该 rollup / archive

### 2.3 Hub 协同视角

Hub 应能继续保持：

- paid / grant / risk / kill-switch 主权不下放
- memory governance 与 canonical refs 不丢
- 所有自动建议 / 自动采纳 / 压缩动作可审计

## 3) 机读契约冻结

### 3.1 `xt.supervisor_project_spec_capsule.v1`

用途：

- 冻结项目规格，不再把 goal / MVP / non-goals / tech stack / milestones 混在聊天里。

```json
{
  "schema_version": "xt.supervisor_project_spec_capsule.v1",
  "project_id": "proj_demo",
  "goal": "Ship a governed desktop supervisor workflow for one-shot intake and portfolio control.",
  "mvp_definition": "User can submit one large task and observe governed pool/lane progress with actionable next step.",
  "non_goals": [
    "Cross-tenant reporting",
    "Full enterprise BI dashboard"
  ],
  "approved_tech_stack": [
    "SwiftUI",
    "Hub canonical memory",
    "governed local+paid model routing"
  ],
  "tech_stack_blacklist": [
    "unapproved remote secret export"
  ],
  "module_map": [
    {
      "module_id": "portfolio",
      "title": "Supervisor portfolio",
      "status": "active",
      "depends_on": []
    }
  ],
  "milestone_map": [
    {
      "milestone_id": "mvp",
      "title": "Validated mainline",
      "status": "active"
    }
  ],
  "decision_defaults": {
    "tech_stack": "proposal_with_timeout_escalation",
    "ui_style": "proposal_only"
  },
  "risk_profile": "medium",
  "updated_at_ms": 1760000000000,
  "source_refs": [
    "x-terminal/work-orders/xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md"
  ]
}
```

### 3.2 `xt.supervisor_decision_track_event.v1`

用途：

- 把正式决策从聊天文本中剥离出来，作为单独事实轨。

```json
{
  "schema_version": "xt.supervisor_decision_track_event.v1",
  "decision_id": "dec_001",
  "project_id": "proj_demo",
  "category": "tech_stack",
  "status": "approved",
  "statement": "Use SwiftUI + Hub canonical memory + role-based routing.",
  "source": "user",
  "reversible": true,
  "approval_required": false,
  "approved_by": "user",
  "audit_ref": "audit_decision_001",
  "evidence_refs": [
    "docs/memory-new/xhub-lane-command-board-v2.md"
  ],
  "created_at_ms": 1760000000100,
  "updated_at_ms": 1760000000100
}
```

### 3.3 `xt.supervisor_background_preference_note.v1`

用途：

- 记录偏好，但明确其不等于正式决策。

```json
{
  "schema_version": "xt.supervisor_background_preference_note.v1",
  "note_id": "pref_001",
  "project_id": "proj_demo",
  "domain": "ux_style",
  "strength": "weak",
  "statement": "Prefer concise action-first updates over long narrative status dumps.",
  "must_not_promote_without_decision": true,
  "created_at_ms": 1760000000200
}
```

### 3.4 `xt.supervisor_model_route_policy.v1`

用途：

- 让 `planner/coder/reviewer/doc/ops` 成为一等路由对象。

```json
{
  "schema_version": "xt.supervisor_model_route_policy.v1",
  "project_id": "proj_demo",
  "role_routes": [
    {
      "role": "planner",
      "task_tags": ["scope_freeze", "spec_capsule", "decision_blocker"],
      "preferred_model_classes": ["local_reasoner", "paid_planner"],
      "fallback_order": ["local_reasoner", "paid_general"],
      "grant_policy": "low_risk_ok"
    },
    {
      "role": "coder",
      "task_tags": ["codegen", "refactor", "runtime_fix"],
      "preferred_model_classes": ["paid_coder", "local_codegen"],
      "fallback_order": ["paid_coder", "local_reasoner"],
      "grant_policy": "project_policy_required"
    }
  ],
  "updated_at_ms": 1760000000300
}
```

### 3.5 `xt.supervisor_portfolio_actionability_snapshot.v1`

用途：

- 从“看状态”升级到“看下一步动作”。

```json
{
  "schema_version": "xt.supervisor_portfolio_actionability_snapshot.v1",
  "supervisor_id": "supervisor-main",
  "projects_total": 7,
  "projects_changed_last_24h": 4,
  "blocked_projects_count": 2,
  "decision_blocker_projects_count": 1,
  "projects_missing_next_step": ["proj_demo"],
  "stalled_projects": ["proj_old"],
  "zombie_projects": ["proj_archive_candidate"],
  "actionable_today": [
    {
      "project_id": "proj_demo",
      "reason_code": "missing_formal_tech_stack_decision",
      "recommended_next_action": "review_decision_proposal"
    }
  ],
  "updated_at_ms": 1760000000400
}
```

### 3.6 `xt.supervisor_rhythm_recommendation.v1`

用途：

- 把通知节奏从“纯播报”改成“动作优先建议”。

```json
{
  "schema_version": "xt.supervisor_rhythm_recommendation.v1",
  "target_type": "project",
  "target_id": "proj_demo",
  "reason_code": "stalled_with_next_step_defined",
  "surface": "brief_card",
  "recommended_next_action": "resume_runtime_probe",
  "why_it_matters": "The project has a valid next step but has been idle for 48h.",
  "silence_until_ms": 1760003600000,
  "generated_at_ms": 1760000000500
}
```

### 3.7 `xt.supervisor_decision_blocker_assist.v1`

用途：

- 让“决策型 blocker”变成结构化建议，而不是一直挂死。

```json
{
  "schema_version": "xt.supervisor_decision_blocker_assist.v1",
  "project_id": "proj_demo",
  "blocker_id": "blk_tech_stack",
  "blocker_type": "decision",
  "template_candidates": [
    "swiftui_hub_first_default",
    "cross_platform_web_default"
  ],
  "recommended_option": "swiftui_hub_first_default",
  "reversible": true,
  "auto_adopt_allowed": false,
  "requires_user_decision": true,
  "timeout_policy": "proposal_with_timeout_escalation",
  "audit_ref": "audit_blocker_assist_001"
}
```

### 3.8 `xt.supervisor_memory_compaction_rollup.v1`

用途：

- 让 L2/L3 长期运行后仍保持低噪音和可解释。

```json
{
  "schema_version": "xt.supervisor_memory_compaction_rollup.v1",
  "project_id": "proj_demo",
  "period_start_ms": 1759900000000,
  "period_end_ms": 1760000000600,
  "rollup_summary": "Completed MVP milestone and archived detailed probe chatter; kept decisions and release refs.",
  "kept_decision_ids": ["dec_001"],
  "kept_milestone_ids": ["mvp"],
  "archived_refs": [
    "build/reports/xt_w3_31_h_require_real_evidence.v1.json"
  ],
  "decision_node_loss": 0,
  "updated_at_ms": 1760000000600
}
```

## 4) Gate 设计

- `XT-SDK-G0 / Contract Freeze`
  - 所有 8 个 schema 冻结，字段说明、默认值、fail-closed 口径齐全
- `XT-SDK-G1 / Project Spec + Decision Rails`
  - `spec capsule + decision track + background track` 落地并可机读消费
- `XT-SDK-G2 / Role Routing`
  - `planner/coder/reviewer/doc/ops` 路由可解释、可回放、受 Hub gate 约束
- `XT-SDK-G3 / Actionability Dashboard`
  - Dashboard 能直接回答“谁该推进、谁缺下一步、谁该归档”
- `XT-SDK-G4 / Rhythm v2`
  - 通知从状态播报升级为动作建议，且不过度刷屏
- `XT-SDK-G5 / Decision-Blocker Assist`
  - 低风险模板建议闭环，高风险保持 fail-closed
- `XT-SDK-G6 / Memory Compaction`
  - 决策/里程碑/审计 refs 不丢
- `XT-SDK-G7 / Require-real Governance`
  - 真机运行下决策轨、路由、建议、压缩不越界

## 5) KPI 与硬线

### 5.1 KPI

- `project_spec_capsule_coverage = managed_projects_with_spec_capsule / managed_projects_total`
- `decision_track_write_coverage = formal_decisions_with_track_record / formal_decisions_total`
- `background_note_promoted_as_decision = 0`
- `role_route_policy_coverage = 1.0`
- `projects_missing_next_step_not_visible_on_dashboard = 0`
- `unreversible_auto_adopt_without_approval = 0`
- `decision_node_loss_after_compaction = 0`
- `zombie_project_detection_visible = 1.0`

### 5.2 硬线

- 背景偏好不得静默升级成正式决策
- 不可逆决策不得自动采纳
- 高风险决策不得绕过 Hub grant / authorization
- 任何压缩不得丢失正式决策节点
- Dashboard 不得退化成“状态很多、动作不清楚”的 BI 面板

## 6) 详细实施拆分

### 6.1 `XT-W3-33-A` Project Spec Capsule

- 目标：给每个项目补上稳定的规格胶囊。
- 重点：
  1. 冻结 `xt.supervisor_project_spec_capsule.v1`
  2. 从现有项目配置、work order、decision track 回填 `goal / mvp / non_goals / tech_stack / milestones`
  3. 在 portfolio card / project sheet 提供“规格缺口”标记
  4. 缺字段项目自动列入 `actionable_today`
- 建议代码面：
  - `x-terminal/Sources/Supervisor/SupervisorProjectSpecCapsule.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/UI/SupervisorView.swift`
  - `x-terminal/Tests/SupervisorProjectSpecCapsuleTests.swift`
- 交付物：
  - `build/reports/xt_w3_33_a_project_spec_capsule_evidence.v1.json`
- DoD：
  - 受辖项目可机读地回答 `goal / mvp / non_goals / approved_tech_stack / milestones`

### 6.2 `XT-W3-33-B` Decision Track + Background Preference Track

- 目标：正式决策与背景偏好彻底分轨。
- 重点：
  1. 冻结 `decision_track` / `background_preference_track`
  2. 所有正式定案写 `decision_track`
  3. Background 只作弱参考，默认不进入 routing hard constraint
  4. 冲突时总是以 `decision_track` 为准
- 建议代码面：
  - `x-terminal/Sources/Supervisor/SupervisorDecisionTrack.swift`
  - `x-terminal/Sources/Supervisor/SupervisorBackgroundPreferenceTrack.swift`
  - `x-terminal/Tests/SupervisorDecisionTrackTests.swift`
- 交付物：
  - `build/reports/xt_w3_33_b_decision_background_tracks_evidence.v1.json`
- DoD：
  - 至少覆盖技术栈、scope freeze、risk posture、approval result 四类正式决策

### 6.3 `XT-W3-33-C` Role-Based Model Routing

- 目标：把项目级默认模型升级为角色级路由。
- 重点：
  1. 冻结 `xt.supervisor_model_route_policy.v1`
  2. 定义 `planner/coder/reviewer/doc/ops`
  3. 对接 Hub AI registry、grant、budget
  4. 路由输出必须可解释：为什么选这类 role、为什么落到这个 model class
- 建议代码面：
  - `x-terminal/Sources/Supervisor/SupervisorModelRoutePolicy.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Tests/SupervisorModelRoutePolicyTests.swift`
- 交付物：
  - `build/reports/xt_w3_33_c_role_route_policy_evidence.v1.json`
- DoD：
  - 任务标签变化能稳定改变路由角色，且不绕过 Hub gate

### 6.4 `XT-W3-33-D` Portfolio Actionability Metrics + Dashboard

- 目标：让 Supervisor 首屏从“状态面板”升级成“动作面板”。
- 重点：
  1. 冻结 `xt.supervisor_portfolio_actionability_snapshot.v1`
  2. 新增：
     - `projects_changed_last_24h`
     - `decision_blocker_projects_count`
     - `projects_missing_next_step`
     - `stalled_projects`
     - `zombie_projects`
     - `actionable_today`
  3. 首页优先展示“当前建议动作”
  4. 项目缺规格 / 缺下一步 / 长期 stalled 必须显式浮现
- 建议代码面：
  - `x-terminal/Sources/Supervisor/SupervisorPortfolioActionabilitySnapshot.swift`
  - `x-terminal/Sources/UI/SupervisorView.swift`
  - `x-terminal/Tests/SupervisorPortfolioActionabilitySnapshotTests.swift`
- 交付物：
  - `build/reports/xt_w3_33_d_actionability_dashboard_evidence.v1.json`
- DoD：
  - 打开首页即可知道“今天该处理什么”

### 6.5 `XT-W3-33-E` Notification Rhythm v2

- 目标：让节奏系统把重点放在“建议动作”，不是重复播报状态。
- 重点：
  1. 冻结 `xt.supervisor_rhythm_recommendation.v1`
  2. 无实质变化时降低噪音
  3. 有实质变化时优先给 `recommended_next_action`
  4. 对长期 blocked / stalled 项目提供提议式提醒
  5. 和 quiet hours / dedupe / severity 继续兼容
- 建议代码面：
  - `x-terminal/Sources/Supervisor/SupervisorRhythmRecommendationEngine.swift`
  - `x-terminal/Sources/Supervisor/SupervisorProjectNotificationPolicy.swift`
  - `x-terminal/Tests/SupervisorRhythmRecommendationTests.swift`
- 交付物：
  - `build/reports/xt_w3_33_e_rhythm_v2_evidence.v1.json`
- DoD：
  - 状态无变化时不刷屏，有变化时能给可执行下一步

### 6.6 `XT-W3-33-F` Decision-Blocker Assist

- 目标：把“纯思考型 blocker”变成结构化默认建议，不再长期挂死。
- 重点：
  1. 冻结 `xt.supervisor_decision_blocker_assist.v1`
  2. 建立可复用模板：
     - tech stack default
     - scaffold default
     - testing stack default
     - documentation template default
  3. 只对可逆、低风险 blocker 允许 `auto_adopt_if_policy_allows`
  4. 其余一律保持 `proposal_only` 或 `proposal_with_timeout_escalation`
  5. 所有采纳动作产出 audit refs
- 建议代码面：
  - `x-terminal/Sources/Supervisor/SupervisorDecisionBlockerAssist.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Tests/SupervisorDecisionBlockerAssistTests.swift`
- 交付物：
  - `build/reports/xt_w3_33_f_decision_blocker_assist_evidence.v1.json`
- DoD：
  - 决策型 blocker 不再只能无限期 `blocked`，但高风险仍 fail-closed

### 6.7 `XT-W3-33-G` Memory Compaction + Rollup + Archive

- 目标：让长期项目不会被历史 observation 淹没。
- 重点：
  1. 冻结 `xt.supervisor_memory_compaction_rollup.v1`
  2. L2 老 observation 压缩成阶段 summary
  3. 已完成项目进入 archive 模式，只保留关键决策/里程碑/证据 refs
  4. `stale noise -> rollup`，`active facts -> keep`
  5. 压缩结果必须可回放
- 建议代码面：
  - `x-terminal/Sources/Supervisor/SupervisorMemoryCompactionPolicy.swift`
  - `x-terminal/Sources/Supervisor/SupervisorProjectCapsuleCanonicalSync.swift`
  - `x-terminal/Tests/SupervisorMemoryCompactionPolicyTests.swift`
- 交付物：
  - `build/reports/xt_w3_33_g_memory_compaction_evidence.v1.json`
- DoD：
  - 压缩后仍能追溯关键决策与 release/gate 证据

### 6.8 `XT-W3-33-H` Require-real Governance Regression

- 目标：在真实运行中验证“建议更积极，但治理不变形”。
- require-real 最小样本：
  1. 正式技术栈定案写入 decision track
  2. 风格偏好写 background track，但不覆盖正式决策
  3. 相同任务类型在 `planner/coder/reviewer/doc/ops` 间路由可解释
  4. 决策 blocker 超时后生成默认建议，但不静默改成 approved
  5. 不可逆决策命中用户授权要求时必须阻断自动采纳
  6. Dashboard 正确浮出 `missing_next_step / stalled / zombie`
  7. 完成项目压缩后决策 refs 不丢
- 交付物：
  - `build/reports/xt_w3_33_h_require_real_evidence.v1.json`
- DoD：
  - `XT-SDK-G7` 转绿前不得对外宣称该切片可发布

## 7) 回归样例

### 7.1 背景偏好不得冒充正式决策

- 场景：用户说“我偏好简洁 UI”，但没有正式冻结 UI 方案
- 断言：
  - 写入 `background_preference_track`
  - 不得覆盖 `decision_track`

### 7.2 正式技术栈定案

- 场景：用户明确批准一套技术栈
- 断言：
  - 生成 `decision_track_event`
  - `spec capsule` 同步更新

### 7.3 Role Routing 可解释

- 场景：同一项目分别触发 `scope_freeze`、`codegen`、`review`
- 断言：
  - 分别路由到 `planner`、`coder`、`reviewer`
  - 均有 explainability 字段

### 7.4 Dashboard 动作优先

- 场景：一个项目缺 `next_step`，一个项目 stalled，一个项目 blocked
- 断言：
  - 首页能直接给出 `actionable_today`

### 7.5 低风险建议可生成但不越权

- 场景：项目卡在“选默认测试框架”
- 断言：
  - 允许生成 proposal
  - 未经政策允许不得自动定案

### 7.6 不可逆决策 fail-closed

- 场景：项目请求改变 release scope 或删除重要数据
- 断言：
  - 必须要求用户 / Hub 授权
  - 不得自动采纳

### 7.7 压缩后关键节点不丢

- 场景：已完成项目执行 rollup / archive
- 断言：
  - 决策 ID、milestone ID、release/gate evidence refs 仍可追溯

## 8) 风险与 fail-closed

### 8.1 风险

- 把“更主动的建议”做成“偷偷替用户拍板”
- 把 background preference 误升级成正式决策
- 把 dashboard 做成指标堆砌，而不是动作面板
- 压缩策略错误导致关键审计信息丢失
- 角色路由可解释性不足，导致用户无法理解为什么用了某个模型

### 8.2 Fail-closed

- 形式化决策字段不全 -> 不得写入 `approved`
- 自动采纳条件不满足 -> 保持 `proposal_only`
- Hub gate 不通过 -> 不得发起 paid/high-risk route
- 压缩结果无法保留 decision/audit refs -> 禁止落盘
- Dashboard 无法得出推荐动作 -> 至少明确标出“缺 formal next step”

## 9) 不在本包范围内

- 不把 Supervisor 变成跨项目全文搜索器
- 不下放 Hub 的 grant / paid-model / trust / authorization 主权
- 不做 enterprise BI / billing / cross-tenant reporting
- 不把当前 validated-mainline-only 对外 scope 扩写成全平台 ready

## 10) 一句话推进顺序

1. 先做 `XT-W3-33-A`
2. 再做 `XT-W3-33-B`
3. 立即接 `XT-W3-33-C`
4. 然后做 `XT-W3-33-D/E`
5. 最后补 `XT-W3-33-F/G/H`

原因：

- 没有规格胶囊，Supervisor 仍要临时推导项目结构。
- 没有决策分轨，任何路由与建议都会持续混淆。
- 没有 role routing，就无法真正提升模型使用效率。
- Dashboard 与 rhythm 应建立在规格与决策轨之上。
- blocker assist / compaction / require-real 必须在主链成立后再收口。
