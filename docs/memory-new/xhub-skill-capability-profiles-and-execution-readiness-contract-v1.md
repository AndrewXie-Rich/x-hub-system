# X-Hub / X-Terminal Skills Capability Profiles + Execution Readiness + Approval Delta Contract v1

- version: v1.0
- updatedAt: 2026-03-28
- owner: Hub Runtime / XT-L2 / Supervisor / Security / Product
- status: proposed-freeze
- scope: 在不改变 `Hub-first trust + grant + audit + revoke + kill-switch` 主链的前提下，引入 OpenClaw 风格的 capability profile 抽象层
- machine-readable contract: `docs/memory-new/schema/xhub_skill_profiles_and_execution_readiness_contract.v1.json`
- depends_on:
  - `docs/xhub-skills-placement-and-execution-boundary-v1.md`
  - `docs/xhub-skills-fail-closed-chain-v1.md`
  - `docs/memory-new/xhub-skills-capability-grant-chain-contract-v1.md`
  - `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`

## 0) 目标与边界

目标：

- 把当前分散在 `ToolProfile`、`project governance template`、`Hub governed skill registry` 三处的能力表达收口成一套 canonical vocabulary。
- 让模型和用户先看到低认知负担的 `capability families / capability profiles`，再看到具体 `skill_id / package_sha256 / governed_dispatch`。
- 保持当前生产主链不变：`catalog -> verify -> pin -> resolve -> preflight -> grant/approval -> execute -> audit -> callback`。

本合同明确不做：

- 不把 XT、Supervisor、browser runtime 或 imported skill 变成新的 trust root。
- 不允许 profile activation 代替 package verification、grant 或 revoke。
- 不允许任何 `profile` 绕过 `verifySkillPackageSecurity / setSkillPin / resolveSkillsWithTrace / evaluateSkillExecutionGate`。
- 不把 OpenClaw 的默认宿主权限模型搬进来。

核心决策：

- OpenClaw 风格的 `tools.profile` 只借用“能力暴露抽象”和“用户/模型心智”。
- 真正的 authority 仍然在 Hub package governance 链。
- `profile` 是暴露层。
- `skill package` 是分发层。
- `grant / approval / revoke` 是控制层。

统一执行链冻结为：

`discover -> install/pin -> resolve -> derive profile -> intersect project ceiling -> compute readiness -> grant/approval -> execute -> audit -> callback`

## 1) Canonical Vocabulary Freeze

### 1.1 风险、授权、运行面枚举

风险等级：

- `low`
- `medium`
- `high`
- `critical`

grant floor：

- `none`
- `readonly`
- `privileged`
- `critical`

approval floor：

- `none`
- `local_approval`
- `hub_grant`
- `hub_grant_plus_local_approval`
- `owner_confirmation`

runtime surface families：

- `xt_builtin`
- `project_local_fs`
- `project_local_runtime`
- `hub_bridge_network`
- `managed_browser_runtime`
- `trusted_device_runtime`
- `connector_runtime`
- `supervisor_runtime`

execution readiness：

- `ready`
- `grant_required`
- `local_approval_required`
- `policy_clamped`
- `runtime_unavailable`
- `hub_disconnected`
- `quarantined`
- `revoked`
- `not_installed`
- `unsupported`
- `degraded`

### 1.2 Capability Family Freeze

Capability family 是最小稳定能力单元。Skill package 可以映射到多个 family；profile 由 family 组合得到。

| family_id | 典型来源 | risk_floor | grant_floor | approval_floor | runtime_surface_families | 说明 |
| --- | --- | --- | --- | --- | --- | --- |
| `skills.discover` | `find-skills`, `skills.search` | `low` | `none` | `none` | `xt_builtin`, `hub_bridge_network` | 搜索、发现、读取安装信息 |
| `skills.manage` | `skills.pin`, baseline install, import enable | `medium` | `none` | `local_approval` | `xt_builtin`, `hub_bridge_network` | 改变 skill 可用性或 pin 状态 |
| `repo.read` | `read_file`, `list_dir`, `search`, `git_status`, `git_diff` | `low` | `none` | `none` | `xt_builtin`, `project_local_fs` | 仅读项目与只读 git 观察 |
| `repo.mutate` | `write_file`, `move_path`, `delete_path`, `git_apply` | `high` | `none` | `local_approval` | `xt_builtin`, `project_local_fs` | 改动 repo 内容 |
| `repo.verify` | `run_command`, `repo.test.run`, `repo.build.run` | `high` | `none` | `local_approval` | `xt_builtin`, `project_local_runtime` | 受治理验证、测试、构建 |
| `repo.delivery` | `git_push`, `pr_create`, `ci_trigger` | `high` | `privileged` | `hub_grant_plus_local_approval` | `xt_builtin`, `project_local_runtime`, `hub_bridge_network` | 向外部系统交付代码结果 |
| `memory.inspect` | `memory_snapshot`, project memory diagnostics | `low` | `none` | `none` | `xt_builtin`, `supervisor_runtime` | 读取当前可见记忆状态 |
| `web.live` | `web_fetch`, `web_search`, `browser_read`, `tavily-websearch` | `high` | `privileged` | `none` | `hub_bridge_network`, `managed_browser_runtime` | 实时联网获取外部信息 |
| `browser.observe` | `agent-browser` read/snapshot/extract | `high` | `privileged` | `none` | `managed_browser_runtime` | 观察网页、抓取 DOM、截图、抽取 |
| `browser.interact` | `agent-browser` open/click/type/upload | `high` | `privileged` | `local_approval` | `managed_browser_runtime` | 在网页执行交互 |
| `browser.secret_fill` | `agent-browser` + secret vault fill | `critical` | `privileged` | `owner_confirmation` | `managed_browser_runtime` | 在网页中使用受保护凭据 |
| `device.observe` | `device.ui.observe`, `device.screen.capture` | `high` | `none` | `local_approval` | `trusted_device_runtime` | 观察本机受治理设备面 |
| `device.act` | `device.ui.act`, `device.ui.step`, `device.applescript` | `critical` | `none` | `owner_confirmation` | `trusted_device_runtime` | 对本机受治理设备面做动作 |
| `connector.deliver` | email/channel send/reply | `critical` | `privileged` | `hub_grant_plus_local_approval` | `connector_runtime` | 外部消息、邮件、channel side effect |
| `voice.playback` | `supervisor.voice.playback` | `low` | `none` | `none` | `xt_builtin`, `supervisor_runtime` | Supervisor 播放、preview、stop |
| `supervisor.orchestrate` | callback follow-up, automated retries | `medium` | `none` | `none` | `supervisor_runtime` | 编排、重试、诊断、事件循环 |

### 1.3 Capability Profile Freeze

Capability profile 是模型和用户直接消费的 bundle 语义；它不是 permission grant，只是暴露层。

说明：

- 下表 `composition` 列允许引用更低一级 profile 以减少重复。
- 真正的原子展开结果，以 machine-readable contract JSON 中的 `capability_profiles[].families` 为准。

| profile_id | composition | 说明 |
| --- | --- | --- |
| `observe_only` | `skills.discover`, `repo.read`, `memory.inspect`, `voice.playback` | 最保守的观察档 |
| `skill_management` | `skills.discover`, `skills.manage` | 安装、pin、enable、import review 相关管理能力 |
| `coding_execute` | `observe_only`, `repo.mutate`, `repo.verify` | 代码改写与本地验证 |
| `browser_research` | `observe_only`, `web.live`, `browser.observe` | 联网研究与网页观察 |
| `browser_operator` | `browser_research`, `browser.interact` | 网页交互但不含 secret fill |
| `browser_operator_with_secrets` | `browser_operator`, `browser.secret_fill` | 网页交互且允许 secret vault 参与 |
| `delivery` | `coding_execute`, `repo.delivery`, `connector.deliver` | 外部交付与外发 side effect |
| `device_governed` | `browser_operator`, `device.observe`, `device.act` | 受治理设备自动化 |
| `supervisor_full` | `device_governed`, `delivery`, `supervisor.orchestrate`, `skill_management` | 仅在高治理项目中可形成完整编排面 |

### 1.4 Legacy Alias Mapping Freeze

现有对象继续保留，但只作为 compatibility input，不再是新的 canonical truth。

`ToolProfile` 兼容映射：

- `minimal -> observe_only`
- `coding -> coding_execute`
- `full -> legacy alias only`

`full` 的新语义：

- 不再表示“所有工具无条件暴露”。
- 表示 `coding_execute + browser_research + delivery` 的 legacy bundle 请求。
- 实际暴露结果必须再与 `project A-Tier ceiling + runtime surface readiness + hub clamp + resolved skills` 取交集。

无效或未知 `toolProfile` 处理：

- 不允许 fallback 到 `full`
- 必须 fallback 到 `observe_only`
- 需要产生日志 `reason_code=invalid_legacy_tool_profile_fallback`

### 1.5 A-Tier -> Max Profile Ceiling Freeze

| A-Tier | max profile ceiling |
| --- | --- |
| `a0Observe` | `observe_only` |
| `a1Plan` | `observe_only`, `skill_management` |
| `a2RepoAuto` | `observe_only`, `skill_management`, `coding_execute` |
| `a3DeliverAuto` | `observe_only`, `skill_management`, `coding_execute`, `browser_research`, `delivery` |
| `a4OpenClaw` | `observe_only`, `skill_management`, `coding_execute`, `browser_operator`, `delivery`, `device_governed`, `supervisor_full` |

补充约束：

- `a4OpenClaw` 是 ceiling，不是默认直接 runnable。
- `browser_operator_with_secrets` 只有在 `managed_browser_runtime` ready 且 `owner_confirmation` 路径完整时才允许进入 `requestable_profiles`。
- `device_governed` 只有 `trustedAutomationReady=true` 才能进入 `runnable_now_profiles`。

## 2) Machine-Readable Objects

### 2.1 Object-A: `xt.project_effective_skill_profile.v1`

用途：

- 作为 XT 对项目当前“能力暴露结果”的唯一快照。
- 供 Project AI、Supervisor、Project Settings、approval UI、slash tools 共同消费。

authority：

- XT 是此对象的 source-of-truth。
- Hub 不直接产出此对象，但提供组成它所需的 package truth、grant truth、revocation truth、official channel truth。

必填字段：

| field | type | 说明 |
| --- | --- | --- |
| `schema_version` | string | 固定为 `xt.project_effective_skill_profile.v1` |
| `project_id` | string | project scope |
| `project_name` | string | 可选展示名 |
| `source` | string | 例如 `xt_project_governance+hub_skill_registry` |
| `execution_tier` | string | 当前项目执行档 |
| `runtime_surface_mode` | string | `manual | guided | trusted_openclaw_mode` |
| `hub_override_mode` | string | `none | clamp_guided | clamp_manual | kill_switch` |
| `legacy_tool_profile` | string | `minimal | coding | full | unknown` |
| `discoverable_profiles` | array | 当前项目可看到的 profile |
| `installable_profiles` | array | 有 uploadable / pinnable package 的 profile |
| `requestable_profiles` | array | 已安装且允许模型请求，但可能仍需 grant/approval |
| `runnable_now_profiles` | array | 可立即执行，无待处理 grant/local approval |
| `grant_required_profiles` | array | 当前仍需 Hub grant 才能执行的 profile |
| `approval_required_profiles` | array | 当前仍需本地审批的 profile |
| `blocked_profiles` | array | 结构化 blocked 项 |
| `ceiling_capability_families` | array | governance ceiling 允许的 families |
| `runnable_capability_families` | array | 当前真正 runnable 的 families |
| `local_auto_approve_enabled` | bool | 项目是否允许局部自动审批 |
| `trusted_automation_ready` | bool | 设备面 readiness |
| `profile_epoch` | string | XT 侧 profile 快照版本 |
| `trust_root_set_hash` | string | 来自 Hub trusted publisher 集 |
| `revocation_epoch` | string | 来自 revocation truth |
| `official_channel_snapshot_id` | string | 官方 channel 状态版本 |
| `runtime_surface_hash` | string | runtime surface readiness 摘要 |
| `audit_ref` | string | 审计引用 |

`blocked_profiles[]` 结构：

```json
{
  "profile_id": "browser_operator",
  "reason_code": "runtime_surface_not_ready",
  "state": "blocked",
  "source": "trusted_device_runtime",
  "unblock_actions": [
    "open_project_settings",
    "open_trusted_automation_doctor"
  ]
}
```

### 2.2 Object-B: `xhub.skill_execution_readiness.v1`

用途：

- 这是每个 `skill_id + package_sha256 + project_id` 的结构化运行真相。
- 它替代当前 XT/Supervisor 中“用字符串 contains 判断 preflight/readiness”的逻辑。

authority：

- Hub 提供 package truth、pin truth、resolved truth、doctor truth、revocation truth、grant floor。
- XT 负责补齐 project runtime surface、local approval posture、Hub connectivity 这些本地执行面真相。
- 最终对象可以由 XT 组合生成，但字段来源必须可追溯。

必填字段：

| field | type | 说明 |
| --- | --- | --- |
| `schema_version` | string | 固定为 `xhub.skill_execution_readiness.v1` |
| `project_id` | string | project scope |
| `skill_id` | string | canonical skill id |
| `package_sha256` | string | 当前候选包 |
| `publisher_id` | string | publisher |
| `policy_scope` | string | `xt_builtin | project | global | memory_core` |
| `intent_families` | array | 例如 `browser.observe`, `repo.verify`, `skills.discover` |
| `capability_families` | array | canonical families |
| `capability_profiles` | array | 命中的 profiles |
| `discoverability_state` | string | `discoverable | hidden | revoked` |
| `installability_state` | string | `installable | not_uploadable | doctor_blocked | vetter_blocked | unsupported` |
| `pin_state` | string | `unpinned | pinned_global | pinned_project | shadowed | pin_blocked` |
| `resolution_state` | string | `resolved | blocked | missing_package | stale | revoked` |
| `execution_readiness` | string | readiness 主状态 |
| `runnable_now` | bool | 是否可立即执行 |
| `deny_code` | string | 结构化阻断码 |
| `reason_code` | string | 更细粒度原因 |
| `grant_floor` | string | `none | readonly | privileged | critical` |
| `approval_floor` | string | approval floor |
| `required_grant_capabilities` | array | 运行前所需 grant capability |
| `required_runtime_surfaces` | array | 需要哪些 surface ready |
| `state_label` | string | UI 短标签 |
| `install_hint` | string | 安装提示 |
| `unblock_actions` | array | 下一步动作 |
| `audit_ref` | string | audit ref |
| `doctor_audit_ref` | string | 可选 |
| `vetter_audit_ref` | string | 可选 |
| `resolved_snapshot_id` | string | 可选 |
| `grant_snapshot_ref` | string | 可选 |

readiness 计算优先级冻结为：

1. `revoked`
2. `quarantined`
3. `unsupported`
4. `not_installed`
5. `policy_clamped`
6. `runtime_unavailable`
7. `hub_disconnected`
8. `grant_required`
9. `local_approval_required`
10. `degraded`
11. `ready`

解释：

- 一旦命中更高优先级状态，不允许 fallback 到低优先级 ready。
- 若同时缺 grant 与 local approval，主状态取 `grant_required`，`approval_floor` 继续保留，用于后续审批展示。

### 2.3 Object-C: `xt.skill_profile_delta_approval.v1`

用途：

- 这是“本次批准到底是在放开什么能力”的结构化审批对象。
- 它不替代 Hub grant request，而是给本地审批、Supervisor approval board、timeline 统一解释。

authority：

- XT / Supervisor 共同生成。
- 只在需要本地审批时创建。

必填字段：

| field | type | 说明 |
| --- | --- | --- |
| `schema_version` | string | 固定为 `xt.skill_profile_delta_approval.v1` |
| `request_id` | string | 关联技能调用 request_id |
| `project_id` | string | project scope |
| `project_name` | string | 展示名 |
| `requested_skill_id` | string | 原请求 skill |
| `effective_skill_id` | string | 实际映射 skill |
| `tool_name` | string | 最终 governed dispatch tool |
| `current_runnable_profiles` | array | 当前项目已 runnable 的 profile |
| `requested_profiles` | array | 本次调用需要的 profile |
| `delta_profiles` | array | 本次审批真正新增或触发的 profile |
| `current_runnable_capability_families` | array | 当前 family |
| `requested_capability_families` | array | 本次 family |
| `delta_capability_families` | array | 本次增量 family |
| `grant_floor` | string | 本次最小 grant floor |
| `approval_floor` | string | 本次审批要求 |
| `requested_ttl_sec` | int | 审批建议 TTL |
| `reason` | string | 触发原因 |
| `summary` | string | 用户可读摘要 |
| `disposition` | string | `pending | approved | denied | expired | executed` |
| `audit_ref` | string | 审计引用 |

生成规则：

- 若 `delta_profiles` 与 `delta_capability_families` 都为空，则不创建本对象。
- 审批对象不得把项目 ceiling 之外的 profile 写入 `requested_profiles`。
- `summary` 必须显式说明“当前项目已有能力”和“本次额外放开的能力”。

## 3) Intent Family Freeze

为减少模型对具体 `skill_id` 的记忆负担，引入 intent family 作为 Router 的长期演进方向。

冻结值：

- `skills.discover`
- `skills.manage`
- `repo.read`
- `repo.modify`
- `repo.verify`
- `repo.deliver`
- `web.search_live`
- `web.fetch_live`
- `browser.observe`
- `browser.interact`
- `browser.secret_fill`
- `device.observe`
- `device.act`
- `memory.inspect`
- `voice.playback`
- `supervisor.orchestrate`

兼容规则：

- 当前阶段 `skill_id` 仍是一级路由键。
- `intent_families` 是 additive field，用于 prompt、future router、fallback routing。
- 不允许因为加入 `intent_families` 而删除 `governed_dispatch`。

## 4) Derivation Rules Freeze

### 4.1 Skill Package -> Capability Families / Profiles

Hub 必须从下列信息 derivation，不允许只信任 skill 包自报：

1. `governed_dispatch / governed_dispatch_variants`
2. `capabilities_required`
3. `side_effect_class`
4. `risk_level`
5. `requires_grant`
6. `skill_id`

package 可选 hint 字段：

- `intent_families`
- `capability_profile_hints`
- `approval_floor_hint`

但 hint 只做建议，不是 authority。规则冻结：

- official skill 或 high-risk skill 的 hint 与系统 derivation 冲突 -> fail-closed，`deny_code=profile_hint_mismatch`
- imported low-risk skill 冲突 -> Hub 忽略 hint，使用 canonical derivation，并写 vetter warning

### 4.2 Project Effective Profile Derivation

XT 必须按下列顺序计算 effective profile：

1. 读取 `AXProjectConfig` 中的 legacy tool profile、A-Tier、runtime surface mode、auto-approve posture。
2. 依据 A-Tier 生成 max profile ceiling。
3. 应用 `hub_override_mode` clamp。
4. 加入 Hub registry / resolved skills / revocation truth / official channel truth。
5. 加入本地 runtime surface readiness：
   - Hub 连接
   - managed browser runtime ready
   - trusted automation ready
   - connector runtime ready
6. 生成：
   - `discoverable_profiles`
   - `installable_profiles`
   - `requestable_profiles`
   - `runnable_now_profiles`

### 4.3 Search / Install / Run 三态冻结

所有面向模型或用户的 skill 能力呈现都必须同时支持：

- `discoverable`
- `installable`
- `requestable`
- `runnable_now`

解释：

- `discoverable`：能搜索到或能被模型知道有这类能力。
- `installable`：至少存在一个 uploadable / pinnable / doctor-passed package。
- `requestable`：已经处在项目当前 skill registry 中，允许模型请求，但可能仍需 grant/approval。
- `runnable_now`：当前可以直接执行，无等待 grant、等待 local approval、runtime unready 等阻断。

### 4.4 Unblock Action Freeze

结构化 `unblock_actions` 只允许下列 action id：

- `open_project_settings`
- `open_skill_governance_surface`
- `install_baseline`
- `pin_package_project`
- `pin_package_global`
- `request_hub_grant`
- `request_local_approval`
- `open_trusted_automation_doctor`
- `reconnect_hub`
- `repair_official_channel`
- `review_import`
- `enable_import`
- `refresh_resolved_cache`
- `retry_dispatch`

## 5) Source-of-Truth Matrix

| truth area | authority |
| --- | --- |
| package signature / trusted publisher / hash / revocation | Hub |
| installability / doctor / vetter / official channel lifecycle | Hub |
| pin / resolved package selection | Hub |
| local runtime surface readiness | XT |
| local approval posture | XT |
| project execution ceiling | XT |
| effective profile exposure | XT |
| approval delta record | XT / Supervisor |
| callback follow-up and recent activity | Supervisor / XT |

## 6) Prompt / UX Exposure Rules

Project AI / Supervisor 默认 prompt 暴露顺序冻结为：

1. `runnable_now_profiles`
2. `requestable_profiles`
3. `grant_required_profiles`
4. `approval_required_profiles`
5. 每个 profile 下的最多 3 个 representative skill

默认不做的事：

- 默认不把所有 installed skills 的低层 manifest 一股脑注入 prompt。
- 默认不让模型直接记忆几十个 `skill_id` 后自行猜可用性。

UI 必须遵守的统一规则：

- Settings / timeline / approval board / baseline install / doctor 页面必须用相同的 `readiness` enum 和 `unblock_actions`。
- 不允许某个页面写 “blocked”，另一个页面写 “grant required”，第三个页面只给自然语言解释但没有结构化 reason code。

## 7) Compatibility + Migration Rules

兼容期内保留：

- `ToolProfile minimal|coding|full`
- `governed_dispatch`
- `governed_dispatch_variants`
- `AXSkillGovernanceSurfaceEntry.preflightResultValue`
- `SupervisorSkillRegistryItem` 旧字段

迁移要求：

- 所有新增字段必须 additive。
- 不允许一次性删除旧字段。
- `SupervisorSkillPreflightGate` 在过渡期内可先双读：
  - 优先读 typed readiness
  - typed readiness 缺失时临时回退旧字符串判断
- 但本合同要求在毕业前删掉旧的字符串 contains 判断。

## 8) Gate / DoD

完成条件：

- `ToolProfile` 无效值不再 fallback 到 `full`
- XT / Supervisor / UI 全部消费统一 readiness enum
- profile summary 出现在 prompt / settings / approval board / activity stream
- `discoverable/installable/requestable/runnable_now` 四态在 UI 与日志中可见
- `approval delta` 记录能解释“本次额外放开了什么”
- resolve cache 支持 `profile_epoch / trust_root_set_hash / revocation_epoch / official_channel_snapshot_id / runtime_surface_hash`

关键 KPI：

- `string_contains_preflight_logic = 0`
- `invalid_legacy_tool_profile_fallback_to_full = 0`
- `profile_state_mismatch_across_ui_surfaces = 0`
- `runnable_now_false_positive_rate < 2%`
- `revoked_or_quarantined_profile_runnable_now = 0`

## 9) 回滚点

- `RB-SPR-001`：只回滚 prompt exposure，不回滚 Hub governance fields。
- `RB-SPR-002`：保留旧 `ToolProfile` 输入，但撤回新的 XT effective profile 生成逻辑。
- `RB-SPR-003`：若 UI 侧 profile surface 有误，可回退到旧 governance surface 展示，但不允许回退 typed readiness 真相。
