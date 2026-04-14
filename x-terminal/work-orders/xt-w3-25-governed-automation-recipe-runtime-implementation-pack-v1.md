# XT-W3-25 Governed Automation Recipe Runtime Implementation Pack v1

- version: v1.0
- updatedAt: 2026-03-30
- owner: XT-L2（Primary）/ Hub-L5 / XT-L1 / QA / Security
- status: planned
- scope: `governed automation` 的 goal -> recipe 编译、recipe store、trigger router、run launch gate、state machine / restart recovery、directed takeover guard、timeline / explainability、one-click bootstrap
- parent:
  - `x-terminal/work-orders/xt-w3-25-automation-product-gap-closure-implementation-pack-v1.md`
  - `docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
  - `docs/memory-new/xhub-trusted-automation-mode-implementation-pack-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/xhub-client-modes-and-connectors-v1.md`

## 0) 为什么要单开这份包

当前 `x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift` 与 `x-terminal/Tests/SupervisorAutomationProductGapClosureTests.swift` 已经证明了 `recipe / trigger / run / takeover / timeline / bootstrap` 这条链可以先以 vertical-slice 契约跑通，但它还不是可持续自动运行的真实 runtime：

- 目标输入还没有真正编译成稳定、可版本化的 recipe 资产。
- 触发器还没有形成统一的 dedupe / replay guard / cooldown 主链。
- run launch gate 还没有把 `delivery target / acceptance pack / grant / posture / trusted automation readiness` 编译成单一裁决。
- crash / restart / retry / cancel 的 run identity 还没有形成正式 checkpoint 主链。
- operator timeline 与 first-run bootstrap 还没有收口成“一个入口就能看懂并跑起来”的产品路径。

这份包只解决这一个问题：把“我输入需求，它自己在 guard 下持续跑”的产品链，从 contract skeleton 收口为真实 governed automation runtime。

## 1) 成品目标

完成后，`XT-W3-25` 至少要满足下面事实：

1. 当前 project 可以把自然语言目标或 starter template 编译成 versioned automation recipe。
2. `schedule / webhook / connector_event / manual` 四类触发器都走统一 router，且只能生成单一 run 主链。
3. 每个 run 都有明确 launch decision，先过 gate，再触发 pool / lane / delivery。
4. run 可以跨 crash / restart / retry / cancel 保持稳定 `run_id`，不会重复开跑。
5. blocked run 只允许走 `same_project + scoped dependency + reversible` 的 directed takeover。
6. 用户和 operator 都能从单一入口看到：
   - 现在在跑什么
   - 为什么被卡住
   - 谁是下一步 owner
   - 现在应该做什么
7. 新项目可以通过一个 bootstrap 路径生成模板文件并完成 first run。

## 2) 冻结建议

### 2.1 保留现有 `XTAutomation*` 命名，拆成真实 runtime 模块

推荐路径：

- `x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift` 继续作为 contract / evidence spine
- 新增或扩展：
  - `x-terminal/Sources/Supervisor/XTAutomationRecipeCompiler.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRecipeStore.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationTriggerRouter.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRunCoordinator.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRunCheckpointStore.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationOperatorTimeline.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationBootstrapPlanner.swift`

原因：

- 当前代码和测试已经以 `XTAutomation*` 形成契约骨架，不要在这一步再重命名。
- 先把现有 vertical slice 拉直成真实模块，比重做一套“新名词”更稳。

### 2.2 Governed Automation 不是裸 prompt loop

- recipe 必须是机读配置，不得只是聊天上下文里的“隐式指令”。
- trigger 必须先编译为 Supervisor run graph，再允许执行。
- 联网、connector、paid model、skills、device side effect 继续走 Hub grants / audit 主链。
- 只要 recipe 涉及 `device.*`，就必须同时满足 `trusted_automation` 与设备执行面 ready；不得因为 recipe 已发布就旁路执行。

### 2.3 Recipe 生命周期冻结

- `draft`
- `ready`
- `paused`
- `archived`

规则：

- 只有 `ready` recipe 可以自动触发。
- 编辑已上线 recipe 时必须生成新版本，不允许 silent in-place mutation。
- `paused` recipe 可以保留历史，但不能继续接 schedule / webhook 自动开跑。

### 2.4 Launch Gate 冻结

每个 run 在进入 `queued` 前，至少要通过：

- `project_id / workspace_root` 绑定
- `delivery_targets` 非空
- `acceptance_pack_ref` 非空
- Hub grant / budget / kill-switch / route state 就绪
- 若涉及 `device.*`：
  - trusted automation binding ready
  - permission owner ready
  - remote posture 达标

任一条件缺失都只能 `hold / downgrade / deny`，不能直接开始 side effect。

## 3) 机读契约

### 3.1 `xt.automation_goal_compilation.v1`

```json
{
  "schema_version": "xt.automation_goal_compilation.v1",
  "project_id": "project_alpha",
  "workspace_root": "/Users/andrew.xie/Documents/AX",
  "goal_id": "goal-20260310-001",
  "goal_text": "nightly triage + code review + summary delivery",
  "compiled_recipe_id": "xt-auto-pr-review",
  "recipe_version": 3,
  "normalized_profiles": {
    "execution_profile": "balanced",
    "touch_mode": "guided_touch",
    "innovation_level": "L2",
    "lane_strategy": "adaptive"
  },
  "uses_device_automation": false,
  "acceptance_pack_ref": "build/reports/xt_w3_22_acceptance_pack.v1.json",
  "delivery_targets": [
    "channel://telegram/project-a"
  ],
  "decision": "ready",
  "gaps": [],
  "audit_ref": "audit-xt-auto-goal-001"
}
```

### 3.2 `xt.automation_recipe_runtime_binding.v1`

```json
{
  "schema_version": "xt.automation_recipe_runtime_binding.v1",
  "recipe_id": "xt-auto-pr-review",
  "recipe_version": 3,
  "lifecycle_state": "ready",
  "project_id": "project_alpha",
  "workspace_binding_hash": "sha256:...",
  "trigger_refs": [
    "xt.automation_trigger_envelope.v1:schedule/nightly"
  ],
  "required_tool_groups": [
    "group:full"
  ],
  "requires_trusted_automation": false,
  "trusted_device_id": "",
  "grant_policy_ref": "policy://automation-trigger/project-a",
  "rollout_status": "active",
  "audit_ref": "audit-xt-auto-binding-001"
}
```

### 3.3 `xt.automation_trigger_route_decision.v1`

```json
{
  "schema_version": "xt.automation_trigger_route_decision.v1",
  "trigger_id": "webhook/github_pr",
  "project_id": "project_alpha",
  "dedupe_key": "sha256:webhook-github-pr",
  "route": "run",
  "cooldown_seconds": 30,
  "replay_guard_pass": true,
  "grant_required": true,
  "same_project_scope": true,
  "decision": "allow",
  "deny_code": "",
  "run_id": "run-20260310-001",
  "audit_ref": "audit-xt-auto-trigger-001"
}
```

### 3.4 `xt.automation_run_launch_decision.v1`

```json
{
  "schema_version": "xt.automation_run_launch_decision.v1",
  "run_id": "run-20260310-001",
  "recipe_id": "xt-auto-pr-review",
  "launch_gate": {
    "delivery_target_present": true,
    "acceptance_pack_present": true,
    "grant_binding_pass": true,
    "route_ready": true,
    "budget_ok": true,
    "trusted_automation_ready": true
  },
  "degrade_mode": "",
  "decision": "run",
  "hold_reason": "",
  "operator_ref": "build/reports/xt_w3_25_delivery_card.v1.json",
  "audit_ref": "audit-xt-auto-launch-001"
}
```

### 3.5 `xt.automation_run_checkpoint.v1`

```json
{
  "schema_version": "xt.automation_run_checkpoint.v1",
  "run_id": "run-20260310-001",
  "recipe_id": "xt-auto-pr-review",
  "state": "blocked",
  "attempt": 2,
  "last_transition": "running_to_blocked",
  "retry_after_seconds": 90,
  "resume_token": "resume-20260310-001",
  "checkpoint_ref": "build/reports/xt_w3_25_run_checkpoint_001.v1.json",
  "stable_identity": true,
  "audit_ref": "audit-xt-auto-checkpoint-001"
}
```

恢复语义冻结（latest grounded truth，2026-03-30）：

- `retry_after_seconds` 是 restart recovery 的真实 cooldown，不是展示字段。
- `automatic` recovery 只能在 checkpoint 仍可恢复且 `retry_after_seconds` 已到期时 `resume`。
- 若 checkpoint 仍在 backoff 窗口内，必须 fail-closed 为 `hold`，并写稳定 reason `retry_after_not_elapsed`。
- 只有 operator/manual recover 才允许走 `operator_override`；前提仍是 stable identity 通过，不能绕过 cancel / scavenging / retry budget。

### 3.6 `xt.automation_operator_brief.v1`

```json
{
  "schema_version": "xt.automation_operator_brief.v1",
  "run_id": "run-20260310-001",
  "state": "blocked",
  "top_blocker": "grant_pending",
  "current_owner": "XT-L2",
  "next_action": "approve pending Hub grant",
  "delivery_target": "channel://telegram/project-a",
  "user_explanation": "Run is held at launch gate until the pending grant is approved.",
  "operator_console_ref": "build/reports/xt_w3_24_d_operator_console_evidence.v1.json",
  "audit_ref": "audit-xt-auto-brief-001"
}
```

## 4) 详细工单

### 4.1 `XT-W3-25-G` Goal -> Recipe Compiler

- 目标：把用户目标、starter template、已有 recipe clone 统一编译成稳定 recipe 契约。
- 推荐路径：
  - `x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift`
  - `x-terminal/Sources/Supervisor/PromptFactory.swift`
  - `x-terminal/Sources/Supervisor/IntakeAcceptanceContracts.swift`
  - `x-terminal/Sources/Project/ProjectModel.swift`
  - `x-terminal/Tests/SupervisorAutomationProductGapClosureTests.swift`
- 实施步骤：
  1. 新增 `xt.automation_goal_compilation.v1`。
  2. 把 `execution_profile / touch_mode / innovation_level / lane_strategy` 的归一化收口到编译阶段。
  3. 在编译阶段绑定 `acceptance_pack_ref / delivery_targets / uses_device_automation`。
  4. 缺关键字段时禁止发布为 `ready`。
- DoD：
  - `goal / template / clone` 三类入口输出同一 canonical recipe contract。
  - 自然语言目标不再直接触发“裸 automation”，而是先落 recipe。
  - `uses_device_automation` 可以在 launch 前机判。
- 回归样例：
  - 缺 `delivery_targets` 仍可发布。
  - `webhook` recipe 没有 dedupe policy 仍可发布。
- 证据：
  - `build/reports/xt_w3_25_g_goal_recipe_compiler_evidence.v1.json`

### 4.2 `XT-W3-25-H` Recipe Store / Editor / Version Freeze

- 目标：把 recipe 变成 project 内可版本化、可暂停、可追溯的正式资产。
- 推荐路径：
  - `x-terminal/Sources/Project/AXProjectConfig.swift`
  - `x-terminal/Sources/Project/AXProjectStore.swift`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Sources/UI/Projects/ProjectDetailView.swift`
  - `x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift`
- 实施步骤：
  1. 在 project config / store 中持久化 recipe manifest、version、lifecycle。
  2. 增加 active recipe pointer、last launch ref、last edit audit ref。
  3. 编辑 live recipe 时强制生成新版本与 diff summary。
  4. `paused / archived` 必须 fail-closed 对 auto trigger 生效。
- DoD：
  - recipe 状态跨 restart 保持一致。
  - 同一 trigger route 默认最多只有一个 `ready` recipe。
  - operator 能准确看到当前 run 来自哪一版 recipe。
- 回归样例：
  - 修改已上线 recipe 直接污染正在运行版本。
  - `paused` recipe 仍被 schedule 拉起。
- 证据：
  - `build/reports/xt_w3_25_h_recipe_store_versioning_evidence.v1.json`

### 4.3 `XT-W3-25-I` Trigger Router / Dedupe / Replay Guard

- 目标：把四类 trigger 收敛到同一条 router 主链。
- 推荐路径：
  - `x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift`
  - `x-terminal/Sources/Supervisor/OneShotReplayHarness.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Tests/SupervisorAutomationProductGapClosureTests.swift`
- 实施步骤：
  1. 新增 `xt.automation_trigger_route_decision.v1`。
  2. 统一 `dedupe_key / cooldown / retry-after / manual retry` 语义。
  3. 在 run 编译前挡住 replay、duplicate、cross-project、grant-unbound trigger。
  4. 对 `drop / hold / run` 三类决策都写 audit。
- DoD：
  - 同一 trigger 不会双开 run。
  - `hold / drop` 都有稳定 machine-readable reason。
  - manual retry 可以复用 recipe，但会生成新的 route decision。
- 回归样例：
  - 同一 webhook 重放两次造成双执行。
  - connector event 缺 `policy_ref` 仍被路由。
- 证据：
  - `build/reports/xt_w3_25_i_trigger_router_evidence.v1.json`

### 4.4 `XT-W3-25-J` Run Compiler / Launch Gate / Downgrade Policy

- 目标：把 accepted trigger 编译成唯一的 launch decision 与 run graph。
- 推荐路径：
  - `x-terminal/Sources/Supervisor/SupervisorOrchestrator.swift`
  - `x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift`
  - `x-terminal/Sources/Supervisor/AdaptivePoolPlanner.swift`
  - `x-terminal/Sources/Supervisor/OneShotRunStateStore.swift`
  - `x-terminal/Sources/Hub/HubRouteStateMachine.swift`
- 实施步骤：
  1. 新增 `xt.automation_run_launch_decision.v1`。
  2. 编译 `run_id + pool/lane plan + initial owner + downgrade candidates`。
  3. 在 launch gate 中统一检查：
     - acceptance pack
     - delivery target
     - grant binding
     - route readiness
     - budget / kill switch
     - device recipe 对应的 trusted automation readiness
  4. 决策只能是 `run / hold / downgrade / deny` 四选一。
- DoD：
  - 第一笔 side effect 前必有 launch decision。
  - downgrade path 显式且有审计。
  - device recipe 不能绕过 trusted automation gate。
- 回归样例：
  - grant 未决时 run 已启动。
  - 缺 acceptance pack 仍进入 `running`。
  - 设备动作 recipe 在 permission owner 缺失时仍给绿牌。
- 证据：
  - `build/reports/xt_w3_25_j_run_launch_gate_evidence.v1.json`

### 4.5 `XT-W3-25-K` Run State Machine / Checkpoint / Restart Recovery

- 目标：保证一个自动化 run 在 crash / restart / cancel / retry 下都只有一个稳定身份。
- 推荐路径：
  - `x-terminal/Sources/Supervisor/OneShotRunStateStore.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Tests/SupervisorAutomationProductGapClosureTests.swift`
- 实施步骤：
  1. 新增 `xt.automation_run_checkpoint.v1`。
  2. 为每个状态迁移写 checkpoint ref、retry-after、attempt。
  3. 进程重启后恢复 `blocked / takeover / downgraded` 状态，不得漂移 `run_id`。
  4. 支持 manual cancel、bounded retry、stale-run scavenging。
  5. 区分 `automatic` 与 `operator_override` recovery：
     - `automatic` 必须尊重 checkpoint `retry_after_seconds`
     - backoff 未到期时返回 `hold(reason=retry_after_not_elapsed)`
     - operator/manual recover 只在 stable identity 仍成立时才可 override cooldown
- DoD：
  - 重启恢复后 `run_id` 与最后安全状态保持不变。
  - cancel 后不能静默复活。
  - checkpoint export 可以重建 state path。
  - heartbeat 自动恢复不会越过 pending backoff 提前 resume。
- 回归样例：
  - crash 导致同一 trigger 再次开出新 run。
  - `retry_after_seconds` 丢失。
  - cancel flag 在 restart 后被忽略。
  - heartbeat automatic recovery 在 `retry_after_seconds` 未到时直接恢复执行。
- 证据：
  - `build/reports/xt_w3_25_k_run_checkpoint_recovery_evidence.v1.json`

### 4.6 `XT-W3-25-L` Directed Takeover Guard / Escalation Policy

- 目标：把现有 directed unblock 原语升级成 automation-safe takeover policy。
- 推荐路径：
  - `x-terminal/Sources/Supervisor/DirectedUnblockRouter.swift`
  - `x-terminal/Sources/Supervisor/IncidentArbiter.swift`
  - `x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`
  - `x-terminal/Sources/Supervisor/OneShotReplayHarness.swift`
  - `x-terminal/Tests/DirectedUnblockRouterTests.swift`
- 实施步骤：
  1. 固化 takeover guard：
     - same project
     - critical path
     - idle timeout exceeded
     - reversible
  2. 输出 `claim_upstream / minimal_microtask / wait_only` 三选一裁决。
  3. 自动生成 `top_blocker / next_owner / unblock checklist / rollback_ref`。
  4. 任何 cross-scope 或高风险情况一律退回 `wait_only`。
- DoD：
  - blocked run 总有单一下一动作或显式等待理由。
  - 不发生 cross-project takeover。
  - takeover 记录可以审计重放。
- 回归样例：
  - 已解决依赖仍触发 takeover。
  - 没有 `rollback_ref` 仍允许 claim。
  - 越 scope lane 被自动接管。
- 证据：
  - `build/reports/xt_w3_25_l_directed_takeover_guard_evidence.v1.json`

### 4.7 `XT-W3-25-M` Run Timeline / Operator Explainability / Delivery Card

- 目标：让 operator 与用户都能在不读原始日志的情况下理解自动化状态。
- 推荐路径：
  - `x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift`
  - `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - `x-terminal/Sources/UI/GlobalHomeView.swift`
  - `x-terminal/Sources/UI/Supervisor/SupervisorStatusBar.swift`
  - `x-terminal/Sources/Supervisor/DeliveryNotifier.swift`
- 实施步骤：
  1. 新增 `xt.automation_operator_brief.v1`。
  2. 把 timeline、operator console、notification summary 对齐到同一字段集。
  3. 至少显示：
     - state
     - top blocker
     - current owner
     - next action
     - retry-after
     - delivery target
     - latest delta
  4. 严禁暴露 raw hidden reasoning，只允许 approved summary fields。
- DoD：
  - 单一入口可回答 `what / why / next`。
  - visible fields coverage = 100%。
  - log tail / restart / heartbeat 都能对齐当前 `run_id`。
- 回归样例：
  - `blocked` 但看不到 blocker。
  - run 恢复后 timeline 仍显示旧状态。
  - UI 泄漏 raw reasoning。
- 证据：
  - `build/reports/xt_w3_25_m_operator_timeline_evidence.v1.json`

### 4.8 `XT-W3-25-N` One-Click Bootstrap / Starter Templates / First-Run Path

- 目标：让 governed automation 的 first run 不需要先读完整架构文档。
- 推荐路径：
  - `x-terminal/Sources/UI/Projects/CreateProjectSheet.swift`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Sources/UI/SettingsView.swift`
  - `x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift`
  - `docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md`
- 实施步骤：
  1. 生成 starter template、`AUTOMATION.md`、config template、first-run checklist。
  2. 模板必须绑定推荐 `touch_mode` 与风险等级。
  3. 若模板包含 `device.*`，自动把 trusted automation prerequisites 写入 checklist。
  4. 量化 `recipe_to_first_run`，纳入 pass line。
- DoD：
  - 新项目可以从一个入口完成 first run。
  - 高风险模板默认不得是 `zero_touch`。
  - checklist 至少覆盖 hub route、grant、delivery target、device prerequisites。
- 回归样例：
  - template 缺 acceptance pack 或 delivery target。
  - 设备模板没有 trusted automation 提示。
  - bootstrap 生成文件与 recipe contract 不一致。
- 证据：
  - `build/reports/xt_w3_25_n_bootstrap_first_run_evidence.v1.json`

## 5) 关键路径顺序

1. `XT-W3-25-G`
2. `XT-W3-25-H`
3. `XT-W3-25-I`
4. `XT-W3-25-J`
5. `XT-W3-25-K`
6. `XT-W3-25-L`
7. `XT-W3-25-M`
8. `XT-W3-25-N`

原因：

- 没有 canonical recipe，就没有稳定 trigger / launch 语义。
- 没有 launch decision，就不该进入自动运行。
- 没有 checkpoint / recovery，就谈不上“持续自迭代”。
- 没有 operator timeline 和 bootstrap，产品层仍然不可用。

## 6) 通过标准

- `goal_to_recipe_contract_coverage = 100%`
- `recipe_version_mutated_in_place = 0`
- `recipe_without_delivery_target_published = 0`
- `trigger_replay_double_execution = 0`
- `run_identity_restart_drift = 0`
- `blocked_run_without_directed_action = 0`
- `raw_cot_leak_count = 0`
- `device_action_recipe_without_trusted_automation_gate = 0`
- `bootstrap_first_run_success_rate >= 0.95`

## 7) 与“自动运行 OpenClaw 能力”的关系

这份包完成后，补齐的是“持续自动运行”的 recipe / trigger / run runtime 主链。

它和 `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md` 是并列缺口：

- 前者解决“能不能在 guard 下持续自己跑”
- 后者解决“能不能安全地动本地设备能力”

两份包都完成后，离你要的“像 OpenClaw 那样我给需求它自己持续推进”就不再是架构未知问题，剩下主要是：

- 真机 require-real 证据
- 真项目 release gate
- UI / operator polish 与发布收口

也就是说，距离还在，但会从“能力链不完整”收敛成“实现与验收闭环”。
