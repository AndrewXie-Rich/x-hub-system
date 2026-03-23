# XT-L1：Skills 导入体验 / Preflight / Runner 约束契约（SKC-W1-02 协同 + SKC-W2-05 + SKC-W4-11）

- workOrder: `SKC-W1-02`（XT 协同部分）, `SKC-W2-05`, `SKC-W4-11`
- priority: `P0 + P1`
- gate: `SKC-G1`, `SKC-G3`, `SKC-G4`
- status: `in_progress`
- owner: `XT-L1`
- updatedAt: `2026-03-01`

## 1) 目标与边界

目标：让 skill 在 X-Terminal 中做到“可搜索、可导入、可预检、可执行、可解释”，并以 fail-closed + machine-readable 证据交付。

本轮只做 XT-L1 边界（不跨泳道）：

- Skills 搜索/导入/分层 pin 体验规范与交互断言
- preflight 诊断（bin/env/config/capabilities）+ 一键修复建议卡片
- runner 执行约束（网络/目录/能力）+ 可解释错误输出
- 热更新稳态化（watcher 去抖 + snapshot 刷新边界 + 失败回退）

明确不在本工单改动：

- Hub 核心签名算法（`Ed25519 + SHA-256` 语义不改）
- 门禁阈值（`SKC-G1/G3/G4` KPI 阈值不改）

## 2) Skills 搜索 / 导入 / 分层 Pin 体验规范

### 2.1 搜索（Discover）

- UI 必须展示：`skill_id/version/description/publisher/capabilities_required/install_hint/source_id`
- 搜索结果必须支持风险提示（高风险 capability 标记）
- 搜索行为必须产生审计：`skills.search.performed`

交互断言（must）：

- `skills.search.result.visible`：结果包含来源、版本、能力需求
- `skills.search.empty.explainable`：空结果时给出可执行下一步（换关键词/换 source）
- `skills.search.audit.recorded`：每次搜索都能在审计侧按 event_type 检索

### 2.2 导入（Import）

- 导入流程固定：`client pull -> upload -> pin`
- 向导必须显式选择 scope：`global | project`（默认 `project`）
- 导入失败必须给修复建议，不允许仅返回抽象错误
- 导入成功必须写审计：`skills.package.imported`

交互断言（must）：

- `skills.import.scope.selector`
- `skills.import.fail.actionable_repair`
- `skills.import.audit.recorded`

### 2.3 分层 Pin（Layered Pin）

- pin 层级必须可见：保留系统层 `Memory-Core` + 普通 pin 层 `Global > Project`
- pin 变更必须可回放（旧值/新值 + scope）
- pin 操作必须写审计：`skills.pin.updated`

交互断言（must）：

- `skills.pin.layer.explainable`
- `skills.pin.rollback.entry.visible`
- `skills.pin.audit.recorded`

## 3) Preflight 诊断 + 一键修复建议卡片（SKC-W2-05）

### 3.1 Preflight 检查面

- `bin`：关键可执行文件可用（如 `node`, `python3`）
- `env`：运行所需环境变量存在且格式合法（不展示明文 secrets）
- `config`：runner policy/scope 配置存在且可解析
- `capabilities_required`：能力需求是否已授权（缺失高风险能力 -> `grant_pending`）

### 3.2 Fail-Closed 语义

- 首次执行前必须先跑 preflight
- preflight 失败时 `execute` 必须阻断
- 高风险 capability 缺失必须输出 `deny_code=grant_pending` 且进入可追踪流程

### 3.3 修复建议卡片（Fix Cards）规范

每个失败检查项必须给出 machine-readable 卡片：

- `id`, `kind(bin|env|config|capability)`, `title`
- `shell_command`（最小可执行）
- `expected_exit_codes`
- `requires_secret_input`
- `redaction_policy=mask_secrets`

回归断言：

- 缺 `bin/env/config` -> 返回可执行修复步骤
- 缺 capability -> `grant_pending` + 引导授权

## 4) Runner 执行约束与错误可解释输出

### 4.1 执行约束

- 网络：`hub_only`（禁止 skill 直连高风险外网）
- 目录：仅允许 `allowed_workdirs`，路径越界 fail-closed
- 能力：`capability_mode=enforced`，不允许绕过 grant

### 4.2 可解释错误

每个阻断必须同时输出：

- `deny_code`（机读）
- `user_message`（人类可执行）
- `machine_reason`（聚类与审计）
- `suggested_action`（下一步动作）

标准错误示例：

- `preflight_failed`
- `grant_pending`
- `direct_network_forbidden`
- `path_not_allowed`
- `runner_policy_violation`
- `hot_reload_rollback_applied`（告知已回退旧快照）

## 5) 热更新稳态化（SKC-W4-11）

- watcher 必须去抖（避免重复刷新）
- snapshot 刷新必须有一致性边界（新快照未通过校验不得替换活动快照）
- 热更新失败必须自动回退旧快照，当前回合不污染

回归断言（must）：

- `skills.hot_reload.failure.rollback`
- `skills.hot_reload.audit.visible`
- `stale_skill_snapshot_incidents = 0`

## 6) Machine-Readable 契约与证据

本工单落地为 XT-L1 contract fixture：

- fixture（正样本）：`scripts/fixtures/skills_xt_l1_contract.sample.json`
- fixture（负样本）：`scripts/fixtures/skills_xt_l1_contract.invalid.sample.json`
- contract checker：`scripts/check_skills_xt_l1_contract.js`
- checker regression：`scripts/check_skills_xt_l1_contract.test.js`

运行方式：

```bash
node ./scripts/check_skills_xt_l1_contract.js
node ./scripts/check_skills_xt_l1_contract.test.js
node ./scripts/check_skills_xt_l1_contract.js --out-json ./.axcoder/reports/skills_xt_l1_contract_report.json
```

报告 schema 关键字段：

- `summary.case_count/pass_case_count/blocked_case_count/rollback_case_count`
- `summary.import_to_first_run_p95_ms`
- `summary.skill_first_run_success_rate`
- `summary.preflight_false_positive_rate`
- `kpi_snapshot.*`（发布口径）
- `errors[]`（fail-closed 诊断）

## 7) Gate / KPI 绑定口径

对应 Gate：

- `SKC-G1`：兼容正确性（搜索/导入/preflight/执行语义一致）
- `SKC-G3`：效率指标（`import_to_first_run_p95_ms <= 12000`, `skill_first_run_success_rate >= 95%`, `preflight_false_positive_rate < 3%`）
- `SKC-G4`：可靠性（热更新失败回退、无脏快照污染）

发布证据要求（XT-L1）：

- `.axcoder/reports/skills_xt_l1_contract_report.json` 必须存在且 `ok=true`
- Gate 任一断言失败即 fail-closed
- 未附 rollback point 与 policy snapshot 的变更不得标记完成
