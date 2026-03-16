# X-Hub Dynamic Official Agent Skills Governance Work Orders v1

- Status: Active
- Updated: 2026-03-14
- Owner: Hub-L1（Primary）/ Hub-L2 / Hub-L5 / XT-L1 / XT-L2 / Product / Security / QA
- Purpose: 把“默认 baseline 很小、官方 skills 可持续增长、AI 可申请新 skill、Hub 完成安全审核后启用”的能力冻结成正式执行主线，避免把 `official skill list` 永久写死在 X-Terminal 客户端里。
- Depends on:
  - `docs/xhub-skills-discovery-and-import-v1.md`
  - `docs/xhub-skills-signing-distribution-and-runner-v1.md`
  - `docs/memory-new/xhub-official-agent-skills-signing-sync-and-hub-signer-work-orders-v1.md`
  - `docs/memory-new/xhub-agent-skill-vetter-gate-work-orders-v1.md`
  - `docs/memory-new/xhub-skills-capability-grant-chain-contract-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`
  - `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`

## 0) 冻结结论

### 0.1 必须拍板的事情

1. `default baseline` 必须保持极小，只负责冷启动，不负责覆盖所有用户场景。
2. 官方可用 skills 的权威清单必须迁到 `Hub official catalog`，不能继续依赖 XT 代码里固定 skill ID 列表作为长期真相源。
3. `source tree 里有 skill` 不等于 `已正式发布可装`；只有进入官方 dist / 通过信任与 vetter / 进入 resolved snapshot 的 skill，才算可用。
4. AI 可以提出“需要新 skill”的申请，但不能绕过：
   - publisher trust
   - Hub-native vetter
   - capability grant
   - user / admin scope approval
5. 不同用户不应预装同一大包。默认形态应是：
   - `Core baseline` 很小
   - 其余官方 skills 按需发现、按需安装、按 scope 启用
6. 新的官方 skill 上线后，应能在不发布新 XT 客户端的情况下被发现、审核、批准和启用。
7. XT 代码中的固定 baseline 只允许保留为 `offline/bootstrap fallback`，不再作为长期官方 skill 权威。

### 0.2 为什么必须单开这份工单

当前系统已经具备：

- Hub skills store
- official skill dist
- baseline install
- project-scoped skills registry
- Supervisor `CALL_SKILL`
- Hub-native vetter 基础链

但还缺一条真正完整的产品主线：

`AI 发现缺 skill -> 提交 official skill request -> Hub 做 trust + vetter + policy review -> 用户/策略批准 scope -> resolved snapshot 生效 -> 原任务继续执行`

如果不把这条主线单独冻结，团队会继续停留在“当前 4 个 baseline 够不够”的讨论里，最后把 skill list 越写越死、越写越厚。

## 1) 当前基线（2026-03-14）

### 1.1 已正式进入默认 baseline 的 skill

当前 XT 代码里的默认 baseline 只有 4 个：

- `find-skills`
- `agent-browser`
- `self-improving-agent`
- `summarize`

它们当前定义在：

- `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`

这是一个合理的冷启动集合，但它不应该继续承担“官方 skill 全量列表”的职责。

### 1.2 当前官方 skill 的真实发布状态

当前仓库 `official-agent-skills/` 下已经能看到更多 skill 源码目录，但 `dist/index.json` 里真正作为官方发布项暴露的只有部分 skill。

这说明当前已经天然存在两层事实：

1. `source-present`
2. `published-and-installable`

后续产品和 AI 都必须只面向第二层做“可申请 / 可安装 / 可启用”的判断。

### 1.3 当前已经存在的可复用能力

- XT 已能通过 `skills_registry` 决定当前 project 能调用哪些 skill。
- skill 不在当前 project scope 时，XT 已能 fail-closed。
- baseline install 已能走 Hub-governed pin 链。
- Hub-native vetter 已能对 staged agent skill 做静态审查并阻断 promote。

所以这份工单不是从零开始，而是在现有骨架上把“动态官方 skills”补完整。

## 2) 北极星目标

### 2.1 用户体验目标

用户看到的体验应是：

1. 默认安装一个很小的 `Core baseline`
2. AI 在需要时自动识别“当前缺某类 skill”
3. AI 发起 skill 申请，而不是直接胡乱执行不存在的能力
4. Hub 自动完成：
   - official catalog 搜索
   - package / publisher / hash 校验
   - vetter 审查
   - capability / risk / scope 审查
5. 用户只需要批准：
   - 要不要装
   - 装到当前 project 还是 global
   - 是否允许高风险能力
6. 批准后 skill 进入 resolved snapshot，原本被阻塞的任务自动继续

### 2.2 架构目标

- XT 不再把“官方可用 skills 全量列表”写死在代码里
- Hub 成为 official catalog / profile / approval / review 的唯一真相源
- XT 只保留：
  - 小型 bootstrap fallback
  - UI 展示
  - local resolved cache
  - governed execution

### 2.3 安全目标

- 新官方 skill 不能因为“来自官方目录”就自动跳过 vetter
- 新官方 skill 不能因为“AI 推荐了”就直接 install
- 高风险 official skill 默认仍需要 grant / approval / review
- 任何 scope 变更、pin 变更、review 结果都必须可审计

## 3) 目标产品模型

### 3.1 技能分层

冻结为四层：

1. `Core baseline`
   - 极小、稳定、默认安装
   - 仅承担冷启动和自发现能力
2. `Recommended packs`
   - `dev`
   - `admin`
   - `ops`
   - `research`
3. `Dynamic official catalog`
   - 由 Hub 发布
   - 可持续增长
   - 不要求 XT 发版
4. `Local / imported / dev publisher skills`
   - 继续走现有 import / vetter / pin 流

### 3.2 推荐的初始包策略

- `Core baseline`
  - `find-skills`
  - `agent-browser`
  - `self-improving-agent`
  - `summarize`
- `Dev pack`
  - `code-review`
  - `tavily-websearch`
- `Admin pack`
  - `skill-vetter`
  - `skill-creator`
- `Ops pack`
  - `agent-backup`

说明：

- 这些 pack 是 Hub 可变配置，不是 XT 内部硬编码常量。
- 当前尚未正式进入 `dist/index.json` 的 skill，不可假装“已发布可装”。

### 3.3 AI 侧行为规则

AI 在执行中发现缺 skill 时，优先顺序必须是：

1. 查看当前 project `skills_registry`
2. 若已有 skill 可完成任务，直接用现有 skill
3. 若当前 skill 不足，先使用 `find-skills` 或内置 catalog search 获得候选
4. 生成 `official skill request`
5. 等待 Hub review + user/admin approval
6. skill 生效后重试原步骤

禁止行为：

- 直接假装某个 skill 已安装
- 直接发起不在 registry 中的 `CALL_SKILL`
- 因为 source tree 里有目录就认为可安装
- 自动把 skill 安装到 `global` scope，除非策略明确允许

## 4) 机读契约冻结

### 4.1 `xhub.official_skill_catalog_snapshot.v1`

```json
{
  "schema_version": "xhub.official_skill_catalog_snapshot.v1",
  "updated_at_ms": 1773500000000,
  "publisher_id": "xhub.official",
  "profiles": [
    {
      "profile_id": "core",
      "display_name": "Core Baseline",
      "default_for_new_projects": true,
      "skill_ids": ["find-skills", "agent-browser", "self-improving-agent", "summarize"]
    }
  ],
  "skills": [
    {
      "skill_id": "tavily-websearch",
      "name": "Tavily Websearch",
      "release_channel": "stable",
      "published": true,
      "install_tier": "dev",
      "risk_level": "medium",
      "requires_grant": true,
      "package_sha256": "sha256...",
      "canonical_manifest_sha256": "sha256...",
      "publisher_trusted": true,
      "vetter_required": true,
      "deprecated": false
    }
  ]
}
```

冻结要求：

- `profiles` 与 `skills` 都由 Hub 返回
- XT 只消费，不维护第二份权威列表

### 4.2 `xt.official_skill_request_proposal.v1`

```json
{
  "schema_version": "xt.official_skill_request_proposal.v1",
  "request_id": "skillreq-20260314-001",
  "project_id": "project_alpha",
  "project_name": "Project Alpha",
  "requested_by": "project_ai|supervisor|user",
  "scope": "project",
  "goal": "联网搜索最新 Swift 宏资料",
  "missing_capabilities": ["web.search"],
  "candidate_skill_ids": ["tavily-websearch"],
  "reason": "current skills_registry has no governed web search surface for this project",
  "policy_ref": "policy://project_alpha/official_skill_request"
}
```

冻结要求：

- AI 最多一次提 3 个候选 skill
- 必须附 `missing_capabilities` 与 `reason`
- 不允许空理由的 install proposal

### 4.3 `xhub.skill_intake_review_record.v1`

```json
{
  "schema_version": "xhub.skill_intake_review_record.v1",
  "review_id": "review-20260314-001",
  "request_id": "skillreq-20260314-001",
  "skill_id": "tavily-websearch",
  "scope": "project",
  "publisher_id": "xhub.official",
  "publisher_trusted": true,
  "package_sha256": "sha256...",
  "canonical_manifest_sha256": "sha256...",
  "vetter_status": "passed|warn_only|critical|scan_error",
  "risk_level": "medium",
  "requires_grant": true,
  "approval_state": "pending|approved|denied|auto_approved",
  "resolved_state": "staged|pinned|enabled|blocked",
  "blocked_reason": ""
}
```

### 4.4 `xt.official_skill_request_policy.v1`

```json
{
  "schema_version": "xt.official_skill_request_policy.v1",
  "mode": "suggest_only|manual_approval|auto_approve_low_risk_official",
  "allow_global_scope": false,
  "max_candidates_per_request": 3,
  "auto_approve_publishers": ["xhub.official"],
  "auto_approve_install_tiers": ["core"],
  "manual_review_required_risk_levels": ["high", "critical"]
}
```

冻结要求：

- 默认策略必须保守：
  - `manual_approval`
  - `allow_global_scope=false`
- 只有低风险官方 skill 才允许进入自动批准试点

## 5) 正式主流程

### 5.1 正向主流程

`task blocked by missing skill -> AI request proposal -> Hub catalog search -> trust + vetter + policy review -> user/admin approval -> pin -> resolved refresh -> retry blocked step`

### 5.2 具体分步

1. AI 判断当前 task 缺 skill，生成 `official skill request proposal`
2. XT 将 proposal 提交给 Hub review API
3. Hub 校验：
   - skill 是否在 official published catalog
   - publisher 是否受信
   - package / manifest hash 是否完整
   - vetter verdict 是否允许继续
4. Hub 合并：
   - risk
   - requires_grant
   - scope policy
   - install tier
5. 如果满足自动批准策略：
   - 直接 pin 到对应 scope
   - 产出审计
6. 如果不满足：
   - 进入 `pending approval`
   - XT / Hub UI 展示申请卡片
7. 批准后：
   - 刷新 resolved snapshot
   - 更新 `skills_registry`
   - 自动 retry 原本被阻塞的 step / job

### 5.3 失败主流程

- `skill not published`
  - 返回“源码存在但未正式发布”
- `publisher not trusted`
  - 进入 review blocked
- `vetter critical`
  - fail-closed
- `missing uploadable package`
  - fail-closed
- `scope denied`
  - 仅保留建议，不执行 install

## 6) 可执行粒度工单

### 6.1 `SKD-W1-01` Core Baseline 与 Dynamic Official Catalog 边界冻结

- Priority: `P0`
- Goal: 把“默认 baseline 很小”和“官方 catalog 动态增长”明确拆开，结束“固定 baseline = 官方 skill 全量列表”的做法。
- Recommended code:
  - `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
- Steps:
  1. 冻结 `Core baseline` 只作为 bootstrap 集合。
  2. 把 `official catalog` 与 `recommended profiles` 从 XT 固定数组迁到 Hub 快照。
  3. XT 仅在 Hub 不可用时回退到内置 `Core baseline`。
  4. Doctor / baseline install / UI 统一读同一份 Hub profile snapshot。
- DoD:
  - 新 official skill 加入 catalog 后，不需要 XT 发版即可被发现
  - XT 中除 fallback 外无第二份长期官方列表
- Acceptance:
  - Hub 新增一个 `official skill` 后，XT 仅刷新 catalog 即可看到
  - Hub 离线时 XT 仍可使用内置 `Core baseline`

### 6.2 `SKD-W1-02` Hub Official Skill Profile Publishing

- Priority: `P0`
- Goal: 让 Hub 能发布 `core/dev/admin/ops` 这类官方推荐 profiles，而不是 XT 手工推断。
- Recommended code:
  - `official-agent-skills/dist/index.json`
  - `scripts/build_official_agent_skills.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
- Steps:
  1. 为 official dist 增加 `profiles` 元数据。
  2. 在构建脚本中生成 `official_skill_catalog_snapshot`。
  3. Hub search / list / resolved API 暴露 profile 信息。
  4. XT baseline install UI 改成读取 Hub 返回的 profile。
- DoD:
  - Hub 能返回 `core/dev/admin/ops` profiles
  - XT 可以安装指定 profile，不必只认识一个 baseline
- Acceptance:
  - `Install Core`
  - `Install Dev Pack`
  - `Install Admin Pack`
  - `Install Ops Pack`

### 6.3 `SKD-W1-03` AI Missing-Skill Detector + Request Proposal

- Priority: `P0`
- Goal: 让 AI 知道什么时候应该申请新 skill，而不是只会报错或乱调用。
- Recommended code:
  - `x-terminal/Sources/Supervisor/SupervisorSystemPromptBuilder.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
- Steps:
  1. 冻结 `缺 skill` 的判断规则：
     - registry 无对应 skill
     - registry 可用但无满足 capability 的 governed surface
     - 当前任务多次因 `skill_not_registered` / `skill_mapping_missing` 阻塞
  2. 增加 `REQUEST_OFFICIAL_SKILL` 动作协议或等价 request API。
  3. AI 生成 proposal 时必须附：
     - goal
     - missing_capabilities
     - candidate_skill_ids
     - scope
     - reason
  4. 限制一次最多 3 个候选 skill。
- DoD:
  - AI 能提出 skill request，而不是直接失败
  - 无 registry 时不会伪造 install
- Acceptance:
  - `web search` 任务缺 `tavily-websearch` 时能提出 request
  - `code review` 场景缺 `code-review` 时能提出 request

### 6.4 `SKD-W1-04` Hub Official Skill Review Chain

- Priority: `P0`
- Goal: 对 AI 提交的官方 skill 申请执行完整 review，而不是“查到 catalog 就直接 pin”。
- Recommended code:
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
  - `x-hub/grpc-server/hub_grpc_server/src/agent_skill_vetter.js`
- Steps:
  1. 新增 Hub review 记录：
     - request
     - selected candidate
     - trust status
     - vetter status
     - risk
     - required grants
     - blocked reason
  2. official skill 也必须复用 vetter 与 trust chain。
  3. 若 skill 在 source tree 中但不在 dist published list，必须返回 `not_published`。
  4. 若 skill 无 uploadable package，必须返回 `missing_package`。
- DoD:
  - review 记录结构化、可审计
  - `official` 不等于跳过审查
- Acceptance:
  - published official skill -> passed/warn_only -> 可进入 approval
  - source-only skill -> blocked(not_published)

### 6.5 `SKD-W1-05` Scope Approval 与 Auto-Approval Policy

- Priority: `P0`
- Goal: 把“申请 skill”和“批准 skill”解耦，并让低风险官方 skill 有自动批准路径，高风险仍保留人工控制。
- Recommended code:
  - `x-terminal/Sources/UI/`
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/Supervisor/SupervisorView.swift`
- Steps:
  1. 增加 skill request approval card：
     - skill
     - reason
     - publisher
     - risk
     - required capabilities
     - scope
  2. 默认 scope 选 `project`
  3. `global` 必须明确选择
  4. policy 增加：
     - `suggest_only`
     - `manual_approval`
     - `auto_approve_low_risk_official`
  5. `high/critical` 或需高风险 grant 的 skill 默认仍需人工批准
- DoD:
  - skill 申请不再混在普通 alert 里
  - 用户能明确看见 scope / risk / publisher / review verdict
- Acceptance:
  - `core` 低风险官方 skill 可在试点策略下自动批准
  - `admin` / `high risk` skill 必须人工批准

### 6.6 `SKD-W1-06` Enable, Resolved Refresh, Auto-Retry

- Priority: `P0`
- Goal: skill 被批准后，系统要真的“马上能用”，而不是还要手工刷新和重试。
- Recommended code:
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Project/AXDefaultAgentBaselineInstaller.swift`
- Steps:
  1. review approved -> set pin
  2. refresh resolved skills snapshot
  3. refresh current project `skills_registry`
  4. 自动恢复被阻塞的 job / plan / step
  5. 写入审计与 skill activity
- DoD:
  - skill 批准后无需用户再次手工打开列表刷新
  - 原 task 能自动 resume 或明确进入 retry 队列
- Acceptance:
  - missing skill request 批准后，原 step 自动重试
  - snapshot 与 UI 在同一次链路中更新

### 6.7 `SKD-W2-07` Dynamic Recommended Packs

- Priority: `P1`
- Goal: 让不同用户群体按需装包，而不是把所有 skill 都塞进 baseline。
- Steps:
  1. Hub 发布 profile：
     - `core`
     - `dev`
     - `admin`
     - `ops`
     - `research`
  2. XT 提供按 profile 安装入口
  3. AI 可推荐“更适合装某个 pack”而不是一项项装
- DoD:
  - 不同用户无需面对同一大杂烩列表
  - baseline 保持小而稳

### 6.8 `SKD-W2-08` Official Skill Update / Deprecation / Revocation Lifecycle

- Priority: `P1`
- Goal: 新官方 skill 上线、旧 skill 废弃、风险 skill 撤销，都能动态生效。
- Steps:
  1. official catalog 支持 `release_channel / deprecated / revoke_reason`
  2. XT skills doctor 和 registry view 展示：
     - update available
     - deprecated
     - revoked
  3. 已批准 skill 被 revoke 后，resolved snapshot 与 execution 双侧 fail-closed
- DoD:
  - 新 skill 上线无需 XT 发版
  - 旧 skill 下线可立即生效

### 6.9 `SKD-W2-09` Metrics, Gates, and Rollout

- Priority: `P1`
- Goal: 给“动态 official skills”主线建立可机判指标，防止功能可用但体验臃肿。
- KPI:
  - `core_baseline_skill_count <= 5`
  - `official_skill_additions_requiring_xt_release = 0`
  - `skill_request_to_review_ready_p95_ms <= 3000`
  - `review_ready_to_enabled_p95_ms <= 8000`
  - `improper_auto_install_incidents = 0`
  - `source_only_skill_false_install = 0`
  - `new_official_skill_discovery_success_rate >= 99%`
- Gate:
  - `SKD-G0` Contract freeze
  - `SKD-G1` Review correctness
  - `SKD-G2` Security fail-closed
  - `SKD-G3` Enable/resume correctness
  - `SKD-G4` Dynamic catalog rollout

## 7) 发布与回滚策略

### 7.1 发布策略

先后顺序固定为：

1. `Hub official catalog snapshot`
2. `review record + request proposal`
3. `approval card + manual flow`
4. `auto-refresh + auto-retry`
5. `auto-approve low-risk official` 试点

### 7.2 回滚策略

若动态链路不稳定：

- XT 回退到当前 `Core baseline` fallback
- Hub 暂时关闭 `REQUEST_OFFICIAL_SKILL`
- review 入口保持只读，不允许新 install
- 已安装 skill 继续按 resolved snapshot 运行，不做批量卸载

## 8) Definition of Done

以下条件同时满足，才算这条主线完成：

1. XT 不再依赖固定代码列表作为长期官方 skill 权威
2. AI 能提出 official skill request，而不是只能报缺失
3. Hub 能对 official skill 做完整 review，并产出结构化记录
4. 用户能在 UI 上方便地批准 `project/global` scope
5. skill 批准后能自动刷新 registry 并恢复原任务
6. 新官方 skill 上线不需要 XT 发版
7. baseline 仍保持极小，不因“怕缺能力”而变成大杂烩
