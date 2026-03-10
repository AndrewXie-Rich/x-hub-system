# XT-W3-27 Hub / X-Terminal UI 产品化 R1 实现子工单包

- version: v1.0
- updatedAt: 2026-03-07
- owner: XT-L2（Primary）/ Hub-L5 / QA / AI-COORD-PRIMARY
- status: active
- scope: `XT-W3-27`（Hub / XT UI Productization R1）+ `XT-W3-27-A/B/C/D/E/F/G/H`
- parent:
  - `x-terminal/work-orders/xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-25-automation-product-gap-closure-implementation-pack-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/memory-new/xhub-internal-pass-lines-v1.md`

## 0) 为什么要有这份包

当前 Hub 与 X-Terminal 的核心能力已经逐步成型，但 UI 仍主要是工程控制面板：信息密度高、入口层级重、设置与诊断混在一起、付费模型授权路径不够直观、Supervisor 的主价值没有被放到首页最优先位置。

当前基线锚点：

- `x-terminal/Sources/UI/GlobalHomeView.swift`
  - 当前首页更像状态总览，不像“从这里开始完成一个任务”的产品首页。
- `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - 已有大量功能入口，但认知负担高，缺乏明确主路径和解释区。
- `x-terminal/Sources/UI/HubSetupWizardView.swift`
  - 已有 Hub 配对向导，但与后续模型授权、grant 排障衔接仍不够顺。
- `x-terminal/Sources/UI/SettingsView.swift`
  - 当前设置项偏工程细节堆叠，缺少任务导向的信息架构。
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - 当前为大型 grouped form，配对、模型、授权、诊断、运营设置混杂。

本包的目标不是只“换皮”，而是把现有主链变成新用户能顺着走、老用户能快速排障、Supervisor 能清晰展现自动化价值的 R1 产品化界面。

## 1) 目标与设计原则

### 1.1 目标

- 把 X-Terminal 首页变成清晰的任务入口，而不是工程状态面板。
- 把 Supervisor 变成“我交给你一个大任务，你告诉我现在如何推进”的驾驶舱。
- 把 Hub 设置中心重构成任务导向的信息架构，特别是：
  - Hub 配对
  - 本地模型
  - 付费模型权限与 grant
  - 诊断与日志
  - 安全边界
- 让 `permission_denied`、`grant_required` 这类高频问题可在 3 步内被定位。
- 让 validated-mainline-only 的产品边界在 UI 中可见，避免误导用户以为“所有能力都已发布完成”。

### 1.2 设计原则

- 主路径优先：把“开始一个任务”“继续当前任务”“排查为什么模型不可用”放到最前面。
- 状态可解释：每个关键状态都带 `what happened / why / next action`。
- 安全不隐身：授权未通过、风险边界、remote secret 限制必须可见，不做“看起来顺滑但实际偷跑”的假体验。
- 信息分层：首用、日常执行、排障、专家设置分层而不是堆在一个页面。
- 产品一致性：Hub 与 XT 的视觉状态语义、badge、action rail、empty state、error state 要统一。

## 2) 机读契约冻结

### 2.1 `xt.ui_information_architecture.v1`

```json
{
  "schema_version": "xt.ui_information_architecture.v1",
  "surfaces": [
    "xt.global_home",
    "xt.supervisor_cockpit",
    "xt.hub_setup_wizard",
    "xt.settings_center",
    "hub.settings_center"
  ],
  "primary_actions": {
    "xt.global_home": ["start_big_task", "resume_project", "pair_hub"],
    "xt.supervisor_cockpit": ["submit_intake", "approve_risk", "review_delivery"],
    "hub.settings_center": ["pair_terminal", "configure_models", "review_grants", "run_diagnostics"]
  },
  "diagnostic_entrypoints": ["grant_center", "model_status", "pairing_health", "audit_logs"],
  "audit_ref": "audit-xxxx"
}
```

### 2.2 `xt.ui_design_token_bundle.v1`

```json
{
  "schema_version": "xt.ui_design_token_bundle.v1",
  "color_semantics": {
    "success": "verified_green",
    "warning": "grant_amber",
    "danger": "fail_closed_red",
    "info": "hub_blue"
  },
  "surface_tokens": {
    "card_radius": 18,
    "section_spacing": 20,
    "primary_button_style": "solid_prominent",
    "diagnostic_chip_style": "outlined_dense"
  },
  "type_scale": {
    "hero": "32/40",
    "section": "20/26",
    "body": "14/20",
    "mono": "12/16"
  },
  "motion_policy": "subtle_stateful_only",
  "audit_ref": "audit-xxxx"
}
```

### 2.3 `xt.ui_surface_state_contract.v1`

```json
{
  "schema_version": "xt.ui_surface_state_contract.v1",
  "state_types": [
    "ready",
    "in_progress",
    "grant_required",
    "permission_denied",
    "blocked_waiting_upstream",
    "release_frozen",
    "diagnostic_required"
  ],
  "required_fields": [
    "headline",
    "why_it_happened",
    "user_action",
    "machine_status_ref"
  ],
  "must_not_hide": [
    "grant_fail_closed",
    "scope_not_validated",
    "remote_secret_blocked"
  ]
}
```

### 2.4 `xt.ui_troubleshooting_path.v1`

```json
{
  "schema_version": "xt.ui_troubleshooting_path.v1",
  "issue_types": [
    "hub_unreachable",
    "grant_required",
    "permission_denied",
    "model_not_ready",
    "connector_scope_blocked"
  ],
  "max_steps_to_primary_fix": 3,
  "required_outputs": [
    "root_cause_hint",
    "fix_suggestion",
    "open_correct_screen_action",
    "copyable_diagnostic_ref"
  ],
  "audit_ref": "audit-xxxx"
}
```

### 2.5 `xt.ui_first_run_journey.v1`

```json
{
  "schema_version": "xt.ui_first_run_journey.v1",
  "journey": [
    "launch_xt",
    "pair_hub",
    "choose_model_source",
    "resolve_grant_if_needed",
    "submit_first_big_task",
    "observe_supervisor_progress",
    "review_delivery_scope"
  ],
  "must_show_progress_steps": true,
  "must_show_fallback_help": true,
  "audit_ref": "audit-xxxx"
}
```

### 2.6 `xt.ui_release_scope_badge.v1`

```json
{
  "schema_version": "xt.ui_release_scope_badge.v1",
  "current_release_scope": "validated-mainline-only",
  "validated_paths": ["XT-W3-23", "XT-W3-24", "XT-W3-25"],
  "must_warn_for_unvalidated_surfaces": true,
  "badge_text": "Validated mainline only",
  "audit_ref": "audit-xxxx"
}
```

## 3) 专项 Gate / KPI

### 3.1 Gate

- `XT-UI-G0`：信息架构、状态语义、设计 token、排障路径契约冻结完成。
- `XT-UI-G1`：首用路径通过，用户可在最少步骤内完成 `pair Hub -> choose model -> resolve grant -> start first task`。
- `XT-UI-G2`：`permission_denied / grant_required / hub_unreachable` 三大问题可在 3 步内定位到正确页面与修复动作。
- `XT-UI-G3`：Supervisor cockpit 把 one-shot intake 作为主 CTA，且能展示规划解释、阻塞原因、下一步与已验证范围。
- `XT-UI-G4`：Hub / XT 核心已验证主链无回归，包括配对、模型切换、grant 流程、release scope 显示。
- `XT-UI-G5`：视觉一致性、响应式、可访问性、空态/错态/加载态与 telemetry 证据完整。

### 3.2 KPI

- `time_to_pair_hub_p95_ms <= 180000`
- `grant_troubleshoot_primary_fix_steps <= 3`
- `first_use_big_task_success_rate >= 0.90`
- `supervisor_primary_cta_discoverability >= 0.95`
- `settings_navigation_success_rate >= 0.90`
- `state_explainability_missing = 0`
- `ui_visual_semantics_mismatch = 0`
- `validated_scope_badge_missing = 0`

## 4) 子工单分解

### 4.1 `XT-W3-27-A` IA Freeze + Navigation Model

- 目标：重构 Hub / XT 的一级入口与导航模型，区分首用、执行、排障、专家设置。
- 交付物：`build/reports/xt_w3_27_a_ia_freeze_evidence.v1.json`

### 4.2 `XT-W3-27-B` Design Tokens + Status Semantics

- 目标：冻结视觉 token、状态 badge、错误语义、空态与 action rail 一致性。
- 交付物：`build/reports/xt_w3_27_b_design_tokens_evidence.v1.json`

### 4.3 `XT-W3-27-C` Global Home Redesign

- 目标：首页突出“开始大任务 / 继续当前项目 / 查看 Hub 状态 / 快速排障”。
- 交付物：`build/reports/xt_w3_27_c_global_home_evidence.v1.json`

### 4.4 `XT-W3-27-D` Supervisor Cockpit Redesign

- 目标：把 one-shot intake、pool/lane explain、blocker、release scope freeze 做成可读驾驶舱。
- 交付物：`build/reports/xt_w3_27_d_supervisor_cockpit_evidence.v1.json`

### 4.5 `XT-W3-27-E` Hub Setup Wizard Redesign

- 目标：把配对、模型源、grant 排障、首次 smoke 连成一条首用路径。
- 交付物：`build/reports/xt_w3_27_e_hub_setup_wizard_evidence.v1.json`

### 4.6 `XT-W3-27-F` X-Terminal Settings Center Redesign

- 目标：把 XT 设置改造成任务导向设置中心，减少一次性暴露的低频工程选项。
- 交付物：`build/reports/xt_w3_27_f_xt_settings_center_evidence.v1.json`

### 4.7 `XT-W3-27-G` Hub Settings Center Restructure

- 目标：重构 Hub 设置，把配对、模型、grant、安全、诊断分区，降低认知负担。
- 交付物：`build/reports/xt_w3_27_g_hub_settings_center_evidence.v1.json`

### 4.8 `XT-W3-27-H` Usability Telemetry + Regression Harness

- 目标：建立可机判的 UI 成功率、排障路径与关键场景回归证据。
- 交付物：`build/reports/xt_w3_27_h_ui_regression_evidence.v1.json`

## 5) 任务级执行包

### 5.1 `XT-W3-27` 总任务

- 目标：把 Hub 与 X-Terminal 的产品表层做成“新用户能上手、老用户能排障、复杂编排能被看懂”的 R1 界面系统。

#### DoR

- `XT-W3-23/24/25` 已形成 validated mainline 产品能力。
- `XT-W3-26` 已定义 one-shot intake 与 adaptive pool planner 主链。
- 当前高频问题已明确：`permission_denied`、`grant_required`、Hub 配对路径、设置中心过重、Supervisor 入口不够主路径化。

#### 实施子步骤

1. 冻结 Hub / XT 共同的信息架构与状态语义契约。
2. 建立共用视觉 token、状态 badge、primary action rail、diagnostic chips、scope badge。
3. 重做 `Global Home`，把“开始复杂任务”作为第一主入口。
4. 重做 `Supervisor Cockpit`，把 one-shot intake、explain、blocker、scope freeze 一屏可见。
5. 重做 `Hub Setup Wizard`，让配对、模型、grant、smoke 连成最短路径。
6. 重构 `SettingsView` 与 `SettingsSheetView`，把设置按任务目标而不是底层技术分组。
7. 补齐 `permission_denied / grant_required / hub_unreachable` 的定向排障面板。
8. 产出 UI telemetry、截图基线、回归矩阵、回滚点与发布证据。

#### DoD

- 新用户可以在清晰导航下完成首次接入与首次复杂任务提交。
- 付费模型授权相关问题可以被快速定位，不再需要到多个页面猜测原因。
- Supervisor 的自动化价值在 UI 中是主入口与主叙事，而不是隐藏在工程细节后面。
- Hub 与 XT 的视觉语义一致，用户能从颜色、badge、提示语上理解状态差异。
- validated-mainline-only 边界在 UI 中清楚呈现，避免范围误判。

#### Gate

- `XT-UI-G0/G1/G2/G3/G4/G5`
- `XT-OS-G1/G5`
- `XT-READY-G0/G1/G4/G5`

#### KPI

- `grant_troubleshoot_primary_fix_steps <= 3`
- `first_use_big_task_success_rate >= 0.90`
- `supervisor_primary_cta_discoverability >= 0.95`
- `settings_navigation_success_rate >= 0.90`
- `state_explainability_missing = 0`

## 6) 实现热点

- `x-terminal/Sources/UI/GlobalHomeView.swift`
  - 首页主信息架构与首屏 CTA 重做。
- `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - 驾驶舱布局、one-shot intake、plan explain、blocker、scope freeze 面板。
- `x-terminal/Sources/UI/HubSetupWizardView.swift`
  - 配对、模型、grant、smoke 的首用主路径。
- `x-terminal/Sources/UI/SettingsView.swift`
  - XT 设置中心重构与任务导向分区。
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - Hub 设置中心分区重构，重点覆盖配对、模型、授权、诊断、安全边界。

建议新增共用 UI 组件：

- `x-terminal/Sources/UI/Components/PrimaryActionRail.swift`
- `x-terminal/Sources/UI/Components/StatusExplanationCard.swift`
- `x-terminal/Sources/UI/Components/TroubleshootPanel.swift`
- `x-terminal/Sources/UI/Components/ValidatedScopeBadge.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/UI/HubSectionCard.swift`

## 7) 回归样例

- `first_run_pair_hub_local_model`
  - 首次配对并使用 Hub 本地模型，必须可顺利完成。
- `paid_model_permission_denied`
  - 付费模型权限不足时，必须把用户带到正确修复入口，而不是只显示原始错误。
- `grant_required_from_xt`
  - 从 XT 发起需要授权的动作时，界面必须解释原因、指出去哪里授权、授权后如何继续。
- `hub_unreachable_recovery`
  - Hub 不可达时，界面必须提供连接诊断、重试与复制诊断引用。
- `start_big_task_from_home`
  - 首页必须能清晰发起复杂任务，并进入 Supervisor 驾驶舱主链。
- `validated_scope_badge_visible`
  - 所有对外 release 相关界面必须显示 validated-mainline-only 边界。
- `settings_findability`
  - 用户必须能在可接受步骤内找到模型、grant、安全、日志四类设置。

## 8) 回滚点

- XT 首页回滚：`x-terminal/Sources/UI/GlobalHomeView.swift`
- Supervisor UI 回滚：`x-terminal/Sources/Supervisor/SupervisorView.swift`
- XT 配对向导回滚：`x-terminal/Sources/UI/HubSetupWizardView.swift`
- XT 设置中心回滚：`x-terminal/Sources/UI/SettingsView.swift`
- Hub 设置中心回滚：`x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`

## 9) 发布判定

只有同时满足以下条件，才允许宣告“Hub / XT UI 已达到 R1 产品化标准”：

- `XT-UI-G0..G5` 全绿。
- 首用路径与排障路径均有真实用户或真实操作样本证据。
- `permission_denied / grant_required / hub_unreachable` 三类高频问题具备明确 fix suggestion 与直达入口。
- UI 未扩写 validated scope，未以视觉包装掩盖 fail-closed 状态。
