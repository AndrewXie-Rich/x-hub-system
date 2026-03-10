# XT-W3-28 配对即设备级信任档案 / 付费模型策略 / 额度可视化 实现子工单包

- version: v1.0
- updatedAt: 2026-03-08
- owner: Hub-L5（Primary）/ XT-L2 / QA / AI-COORD-PRIMARY
- status: planned
- scope: `XT-W3-28`（Paired Terminal Trust Profile + Paid Model Policy + Budget Visibility）+ `XT-W3-28-A/B/C/D/E/F/G/H`
- parent:
  - `x-terminal/work-orders/xt-w3-27-hub-xt-ui-productization-r1-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w1-03-pending-grants-source-of-truth.md`
  - `docs/memory-new/xhub-security-innovation-work-orders-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/memory-new/xhub-internal-pass-lines-v1.md`

## 0) 为什么要有这份包

当前 Hub 已具备配对、设备 capability allowlist、grant、pending grants、设备编辑与审计基础，但用户体验仍停留在“安全底座已具备，产品主路径未合并”：

- 首次配对批准时，还不能一次性明确这台 X-Terminal 是否允许使用付费模型。
- 当前默认能力集只包含 `ai.generate.local`，不包含 `ai.generate.paid`；导致本地模型可用、付费模型却在后续运行时再掉进 `grant_required / permission_denied` 迷雾。
- 付费模型授权当前偏向“逐次请求 grant”，不符合受信任设备的实际心智。
- Hub 还缺少“每台 Terminal 用了哪些模型、今日额度还剩多少、哪台设备在消耗付费预算”的清晰面板。

本包的目标不是放松安全，而是把安全从“逐请求审批”升级为“首次配对建立设备级信任档案，运行时只在越权/超额/高风险时阻断”。

也就是说：

- 首次批准配对时，就明确该 Terminal 的设备名、模型权限、默认联网权限、每日额度。
- 若用户批准“付费模型=允许全部 Hub 侧付费模型”，则之后该设备在预算内直接使用，无需自己再申请自己批准。
- 若用户选择“自定义”，则只允许使用选中的付费模型。
- Hub 必须清楚展示每台 Terminal 的模型使用量、预算消耗、阻断原因与当前策略。

## 1) 产品目标与原则

### 1.1 目标

- 把 X-Hub 的“首次批准配对”升级成“Approve with Policy”，而不只是 `Approve / Deny`。
- 在批准时支持：
  - 设备自命名
  - 是否允许付费模型
  - `全部付费模型` 或 `自定义特定付费模型`
  - 默认联网权限（v1 默认开，但仍可后续修改）
  - 每日 token 额度上限
- 让 X-Terminal 在设备级授权范围内直接使用模型，不再为正常主路径反复触发 grant。
- 让 Hub 可按设备与按模型查看额度使用和剩余额度。
- 保留 fail-closed：未授权模型、超预算、联网被禁、越 scope 调用必须 machine-readable 拒绝。

### 1.2 原则

- 设备级策略优先：受信任边界在 pairing 时建立，不在每次生成时重新猜。
- 正常主路径无二次审批：已授权设备 + 已授权模型 + 预算内，应直接可用。
- 越界才审批或阻断：仅当超出模型白名单、预算、联网或高风险边界时，才回到 grant / fail-closed。
- 预算与消耗必须可见：所有付费模型消耗按 `device_id + device_name + model_id` 入账。
- 向后兼容：旧 paired device 若没有 trust profile，继续走旧 capability/grant 路径，不冒然改变现网行为。

## 2) 机读契约冻结

### 2.1 `hub.paired_terminal_trust_profile.v1`

```json
{
  "schema_version": "hub.paired_terminal_trust_profile.v1",
  "device_id": "device_xxx",
  "device_name": "Andrew-MBP-XT",
  "trust_mode": "trusted_daily",
  "capabilities": [
    "models",
    "events",
    "memory",
    "skills",
    "ai.generate.local",
    "ai.generate.paid",
    "web.fetch"
  ],
  "paid_model_policy": {
    "mode": "all_paid_models",
    "allowed_model_ids": []
  },
  "network_policy": {
    "default_web_fetch_enabled": true
  },
  "budget_policy": {
    "daily_token_limit": 500000,
    "single_request_token_limit": 12000
  },
  "audit_ref": "audit-xxxx"
}
```

### 2.2 `hub.paired_terminal_paid_model_policy.v1`

```json
{
  "schema_version": "hub.paired_terminal_paid_model_policy.v1",
  "modes": [
    "off",
    "all_paid_models",
    "custom_selected_models"
  ],
  "required_fields": [
    "mode",
    "allowed_model_ids"
  ],
  "rules": {
    "off": "deny_any_paid_model",
    "all_paid_models": "allow_any_hub_paid_model",
    "custom_selected_models": "allow_only_allowed_model_ids"
  },
  "deny_codes": [
    "device_paid_model_disabled",
    "device_paid_model_not_allowed",
    "device_paid_model_policy_missing"
  ],
  "audit_ref": "audit-xxxx"
}
```

### 2.3 `hub.paired_terminal_budget_policy.v1`

```json
{
  "schema_version": "hub.paired_terminal_budget_policy.v1",
  "fields": {
    "daily_token_limit": "integer>=0",
    "single_request_token_limit": "integer>=1",
    "warn_threshold_ratio": "0..1"
  },
  "deny_codes": [
    "device_daily_token_budget_exceeded",
    "device_single_request_token_exceeded"
  ],
  "defaults": {
    "daily_token_limit": 500000,
    "single_request_token_limit": 12000,
    "warn_threshold_ratio": 0.8
  },
  "audit_ref": "audit-xxxx"
}
```

### 2.4 `hub.terminal_usage_snapshot.v1`

```json
{
  "schema_version": "hub.terminal_usage_snapshot.v1",
  "updated_at_ms": 0,
  "devices": [
    {
      "device_id": "device_xxx",
      "device_name": "Andrew-MBP-XT",
      "paid_model_policy_mode": "all_paid_models",
      "daily_token_limit": 500000,
      "daily_token_used": 128400,
      "daily_token_remaining": 371600,
      "requests_today": 42,
      "blocked_today": 1,
      "top_models": [
        {
          "model_id": "openai/gpt-4.1",
          "tokens_today": 84000,
          "requests_today": 21,
          "last_used_at_ms": 0
        }
      ]
    }
  ]
}
```

### 2.5 `xt.paid_model_access_resolution.v1`

```json
{
  "schema_version": "xt.paid_model_access_resolution.v1",
  "states": [
    "allowed_by_device_policy",
    "blocked_paid_model_disabled",
    "blocked_model_not_in_custom_allowlist",
    "blocked_daily_budget_exceeded",
    "blocked_single_request_budget_exceeded",
    "legacy_grant_flow_required"
  ],
  "required_outputs": [
    "headline",
    "why_it_happened",
    "next_action",
    "device_name",
    "model_id",
    "policy_ref"
  ],
  "must_not_emit_for_new_profile": [
    "grant_required_without_policy_context"
  ]
}
```

### 2.6 `hub.pairing_approval_form.v1`

```json
{
  "schema_version": "hub.pairing_approval_form.v1",
  "required_fields": [
    "device_name",
    "paid_model_enabled",
    "paid_model_selection_mode",
    "default_web_fetch_enabled",
    "daily_token_limit"
  ],
  "selection_modes": [
    "off",
    "all_paid_models",
    "custom_selected_models"
  ],
  "default_values": {
    "paid_model_enabled": false,
    "paid_model_selection_mode": "off",
    "default_web_fetch_enabled": true,
    "daily_token_limit": 500000
  },
  "audit_ref": "audit-xxxx"
}
```

## 3) Gate / KPI

### 3.1 Gate

- `XT-TP-G0`：`trust_profile / paid_model_policy / budget_policy / usage_snapshot / access_resolution / pairing_form` 六份契约冻结并机读落盘。
- `XT-TP-G1`：首次配对批准页可完成设备名、付费模型模式、默认联网、每日额度设置；保存后可在 Hub 设备设置页复现同一配置。
- `XT-TP-G2`：运行时付费模型访问决策正确；`off / all_paid_models / custom_selected_models` 三档都能命中正确 allow/deny 路径。
- `XT-TP-G3`：预算计量与可视化正确；Hub 可按设备和按模型查看当日 token 使用、剩余额度、阻断次数。
- `XT-TP-G4`：旧设备兼容与迁移正确；未配置 trust profile 的旧设备仍走 legacy 路径，不影响已验证主链。
- `XT-TP-G5`：XT 提示语义、Hub 设置编辑、pairing 首用路径与 require-real 样本全绿；禁止出现“无 pending grant 但无法定位原因”的死角状态。

### 3.2 KPI

- `paid_model_first_use_after_pairing_extra_approval_steps = 0`（在设备策略已允许且预算内）
- `pending_grant_dead_end_incidents = 0`
- `device_policy_resolution_accuracy = 1.0`
- `terminal_usage_visibility_gap = 0`
- `device_name_missing_in_operator_views = 0`
- `unauthorized_paid_model_bypass = 0`
- `budget_overrun_without_block = 0`
- `legacy_device_breakage = 0`

## 4) 子工单分解

### 4.1 `XT-W3-28-A` Pairing Approval Form 升级

- 目标：把 Hub 首次批准页升级为 `Approve with Policy`。
- 具体要求：
  - 设备名为一等字段，默认带建议名，但允许自定义。
  - `付费模型` 三态：`关闭` / `允许全部 Hub 端付费模型` / `自定义选择模型`。
  - `默认联网权限` v1 默认打开，但用户可在首次批准时关闭。
  - 提供 `每日 token 额度` 输入框和默认值。
- 交付物：`build/reports/xt_w3_28_a_pairing_approval_form_evidence.v1.json`

### 4.2 `XT-W3-28-B` Trust Profile 持久化与编辑

- 目标：把 pairing 审批结果持久化为设备级 trust profile，并可在 Hub 设备设置页编辑。
- 具体要求：
  - 扩展 pairing request / approved device 存储结构。
  - 新增 `approved_trust_profile_json` 或等价结构化存储。
  - Hub 设备编辑页支持修改：设备名、付费模型模式、模型白名单、默认联网、每日额度。
- 交付物：`build/reports/xt_w3_28_b_trust_profile_store_evidence.v1.json`

### 4.3 `XT-W3-28-C` 运行时访问决策器

- 目标：把付费模型准入决策从“只有 grant 视角”升级为“设备策略 + 预算 + legacy fallback”。
- 具体要求：
  - 对新 trust profile：优先命中设备策略。
  - 允许全部付费模型时，任何 Hub paid model 直接可用。
  - 自定义模式只允许命中 `allowed_model_ids`。
  - 不满足策略时返回明确 deny_code，不再只给 `grant_required` 模糊提示。
- 交付物：`build/reports/xt_w3_28_c_runtime_policy_resolution_evidence.v1.json`

### 4.4 `XT-W3-28-D` 预算计量与阻断

- 目标：按设备与模型统计 token 消耗，并在超额时 fail-closed。
- 具体要求：
  - 记录 `daily_token_used`、`single_request_token_used`、`blocked_today`。
  - 超额度返回 `device_daily_token_budget_exceeded` / `device_single_request_token_exceeded`。
  - 允许 `warn_threshold_ratio` 触发 Hub UI 黄色提醒。
- 交付物：`build/reports/xt_w3_28_d_budget_metering_evidence.v1.json`

### 4.5 `XT-W3-28-E` Hub 设备用量面板

- 目标：Hub 能清晰看到每个 Terminal 使用的模型额度。
- 具体要求：
  - 设备列表展示：设备名、今日总 token、剩余额度、已授权模式、默认联网、最近阻断原因。
  - 设备详情展示：按模型分解的 token 使用、请求数、最后使用时间。
  - 支持 operator 快速定位“哪台 XT 在消耗付费预算”。
- 交付物：`build/reports/xt_w3_28_e_terminal_usage_dashboard_evidence.v1.json`

### 4.6 `XT-W3-28-F` XT 侧访问解释与诊断

- 目标：XT 在无法使用付费模型时，明确告诉用户是“设备没授权 / 模型不在白名单 / 额度超额 / legacy grant 路径”。
- 具体要求：
  - 文案必须包含 `device_name + model_id + next_action`。
  - 新 trust profile 路径下，不得再出现无上下文的“去 Global Home 批准 pending grant”。
  - 仅旧设备或 legacy 模式保留 grant 兼容提示。
- 交付物：`build/reports/xt_w3_28_f_xt_access_explainability_evidence.v1.json`

### 4.7 `XT-W3-28-G` 旧设备迁移与兼容

- 目标：现有 paired device 可平滑升级，不影响主链已验证功能。
- 具体要求：
  - 旧设备无 trust profile 时，继续沿用当前 capability/grant 逻辑。
  - Hub 设置页提供“升级为设备策略模式”入口。
  - 迁移前后审计口径可区分，避免 operator 混淆。
- 交付物：`build/reports/xt_w3_28_g_legacy_migration_evidence.v1.json`

### 4.8 `XT-W3-28-H` QA / Require-Real 回归矩阵

- 目标：建立首配对、特定模型白名单、预算耗尽、旧设备兼容的 require-real 回归。
- 交付物：`build/reports/xt_w3_28_h_require_real_regression_evidence.v1.json`

## 5) 任务级执行包

### 5.1 `XT-W3-28-A` 执行要求

- Hub UI：首次批准配对弹窗或 sheet 必须新增：
  - `device_name`
  - `paid_model_enabled`
  - `paid_model_selection_mode`
  - `allowed_paid_models[]`（仅 custom 模式显示）
  - `default_web_fetch_enabled`
  - `daily_token_limit`
- 若选择 `允许全部付费模型`：存储为 `mode=all_paid_models`，不写具体 model ids。
- 若选择 `自定义`：候选列表只允许展示当前 Hub 端已登记的 paid models。
- 禁止空 custom 列表冒充 enabled。

### 5.2 `XT-W3-28-B` 执行要求

- 持久化层建议优先保存为结构化 JSON，再视需要拆表。
- `device_name` 必须在：
  - Pairing 审批页
  - Hub 设备列表
  - Hub 设备详情
  - XT 诊断与错误提示
  - 审计导出
  中保持一致。
- 设备级 trust profile 修改要产生日志与 machine-readable 审计。

### 5.3 `XT-W3-28-C` 执行要求

- 运行时判定顺序：
  1. 读取 paired device trust profile
  2. 检查 `ai.generate.paid` capability / paid_model_policy.mode
  3. 检查模型是否在允许范围
  4. 检查预算
  5. 新 profile 命中则直接 allow；未命中新 profile 才决定 deny 或 legacy fallback
- v1 不允许“设备已配置 all_paid_models，却仍让用户自己再审批同类 paid model”这类重复交互。

### 5.4 `XT-W3-28-D` 执行要求

- 计量维度至少包含：
  - `device_id`
  - `device_name`
  - `model_id`
  - `day_bucket`
  - `prompt_tokens`
  - `completion_tokens`
  - `total_tokens`
  - `request_count`
  - `blocked_count`
- 若暂时没有精确成本模型，v1 可先以 token 额度为硬门槛；成本字段可留可空但 schema 预留。

### 5.5 `XT-W3-28-E` 执行要求

- Hub 设备列表最少字段：
  - `device_name`
  - `device_id`
  - `paid_model_policy_mode`
  - `daily_token_used / daily_token_limit`
  - `default_web_fetch_enabled`
  - `top_model`
  - `last_blocked_reason`
- 设备详情至少包含：
  - 按模型 breakdown
  - 今日请求数
  - 今日阻断数
  - 最近一次使用时间
  - 最近一次 deny_code

### 5.6 `XT-W3-28-F` 执行要求

- deny 文案统一：
  - `device_paid_model_disabled`
  - `device_paid_model_not_allowed`
  - `device_daily_token_budget_exceeded`
  - `device_single_request_token_exceeded`
  - `legacy_grant_flow_required`
- 每个 deny 必须给出明确下一步，不允许只输出“permission denied”。

### 5.7 `XT-W3-28-G` 执行要求

- 迁移策略必须 fail-closed：
  - 没有 trust profile 的旧设备，不默认提升为 all-paid。
  - 需要 operator 在 Hub 中明确升级。
- 若旧设备 capability 已包含 `ai.generate.paid`，但未升级 trust profile，可继续 legacy grant 路径，不强制改旧行为。

### 5.8 `XT-W3-28-H` 执行要求

- require-real 回归最少覆盖：
  1. 新配对，选择 `off`，付费模型被拒绝。
  2. 新配对，选择 `all_paid_models`，预算内首次付费模型直接可用。
  3. 新配对，选择 `custom_selected_models`，白名单模型可用，非白名单模型被拒绝。
  4. 默认联网开启，`web.fetch` 正常；关闭后被正确拒绝。
  5. 达到每日 token 上限后，后续付费模型请求被阻断。
  6. 旧设备未升级 trust profile，仍走 legacy 流程且不回归本地模型主链。

## 6) 回归样例（必须机读落盘）

### 6.1 Regression A: all-paid happy path

- 前置：新配对设备，`paid_model_policy.mode=all_paid_models`，`daily_token_limit` 足够。
- 动作：XT 选择任一 Hub paid model 并发起首个请求。
- 期望：直接成功；无 `grant_required`；使用量计入该 device/model。

### 6.2 Regression B: custom allowlist deny

- 前置：新配对设备，`paid_model_policy.mode=custom_selected_models`，仅允许 `model_A`。
- 动作：XT 选择 `model_B`。
- 期望：返回 `device_paid_model_not_allowed`；Hub 用量面板不增加成功调用计数。

### 6.3 Regression C: budget exhausted

- 前置：设备 `daily_token_limit` 已被打满。
- 动作：再次调用 paid model。
- 期望：返回 `device_daily_token_budget_exceeded`；Hub 面板显示阻断次数 +1。

### 6.4 Regression D: legacy compatibility

- 前置：旧 paired device，未升级 trust profile。
- 动作：调用 local model 与 paid model。
- 期望：local 主链不回归；paid model 继续沿用 legacy capability/grant 语义。

### 6.5 Regression E: device naming consistency

- 前置：设备名设为 `Andrew-MBP-XT`。
- 动作：查看 pairing 审批结果、设备列表、XT 错误提示、审计导出。
- 期望：所有 operator/user 视图统一显示该设备名。

## 7) DoD

- [ ] 首次配对批准页支持 `付费模型关闭 / 全开 / 自定义白名单` 三态。
- [ ] 首次配对批准页支持设备名、默认联网、每日 token 额度。
- [ ] 新 trust profile 设备在授权范围内使用 paid model 不再额外走人工 grant。
- [ ] Hub 可按设备和按模型查看当日额度使用与剩余额度。
- [ ] XT 错误提示从“模糊 grant_required”升级为“设备策略 / 白名单 / 额度”可解释原因。
- [ ] 旧 paired device 保持兼容，不破坏已验证主链。
- [ ] require-real 回归矩阵与 machine-readable evidence 齐全。

## 8) 非目标（v1 不做）

- 不做 provider 级复杂层级授权（如按 OpenAI/Anthropic provider group 批量规则）；v1 只支持 `off / all paid models / custom exact model ids`。
- 不把费用结算作为 v1 硬门槛；v1 先以 token 额度为主。
- 不绕过 Hub 作为模型、授权、审计、预算真相源。
- 不把本包扩成“所有 connector / automation / payment”总治理；只覆盖 paired Terminal 的 paid model / web.fetch / budget 主路径。

## 9) 风险与回滚

- 风险 1：新旧逻辑并存，容易产生“为什么这台走设备策略，那台还走 grant”的认知分裂。
  - 处理：UI 必须显式显示 `policy_mode=new_profile|legacy_grant`。
- 风险 2：若把 `all_paid_models` 做成默认勾选，会放大误配成本。
  - 处理：v1 默认仍为 `off`，但可一键切到 `all_paid_models`。
- 风险 3：预算计量若只在成功路径记账，阻断与预估不准。
  - 处理：成功/阻断都要单独计数，严格区分。
- 风险 4：设备名未统一透传，会继续造成 operator 混淆。
  - 处理：把 `device_name` 纳入所有 operator-facing 输出的必填字段。

回滚点：

- UI 回滚：退回当前 pairing approve + device editor 形式。
- 决策回滚：将新 trust profile 判定器 behind flag，回退到 legacy capability/grant 路径。
- 统计回滚：隐藏新 usage 面板，但保留底层审计字段。

## 10) Handoff 顺序

1. `Hub-L5`
- 先冻结 pairing form / trust profile / budget / usage snapshot 契约。
- 再做 Hub 侧持久化、决策器、用量面板。

2. `XT-L2`
- 消费 Hub 新契约，补 XT 侧访问解释、状态语义与 pairing 成功后首用主路径。

3. `QA`
- 只接受 machine-readable + require-real 证据；禁止用 synthetic 冒充 all-paid happy path。

4. `AI-COORD-PRIMARY`
- 仅做边界审计：防 scope 扩张、防把 v1 扩写成 provider group / billing system / enterprise console 全家桶。
