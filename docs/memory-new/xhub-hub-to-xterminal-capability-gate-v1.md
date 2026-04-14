# X-Hub -> X-Terminal 能力就绪门禁（XT-Ready Gate）

- version: v1.2
- updatedAt: 2026-02-28
- owner: Hub Runtime / X-Terminal Supervisor / Security / QA
- status: active
- goal: 确保 **x-hub-system 主线“完成”时，X-Terminal 已具备复杂项目自动拆分与多泳道并行托管能力**。
- related:
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
  - `docs/memory-new/xhub-skills-capability-grant-chain-contract-v1.md`
  - `docs/memory-new/xhub-memory-v3-execution-plan.md`
  - `x-terminal/work-orders/xterminal-parallel-work-orders-v1.md`
  - `x-terminal/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md`

## 0) 冻结原则（防“Hub 做完但 Terminal 不可用”）

- 任何“Hub 主线完成”声明，必须同时通过 `XT-Ready Gate`。
- 若 `XT-Ready Gate` 未通过，状态只能是“Hub 核心能力完成，端到端未完成”。
- `XT-Ready Gate` 由 Hub 与 X-Terminal 联合签字，单边不得宣告完成。

## 1) XT-Ready Gate（必须全部通过）

### XT-Ready-G0：拆分提案可用

- Supervisor 对复杂项目可生成拆分提案（DAG + lane + 风险 + 预算 + DoD）。
- 用户可确认/拒绝/局部覆盖（含 hard/soft 拆分策略）。

通过标准：
- 提案生成成功率 `>= 99%`
- DAG 无环错误拦截率 `= 100%`

### XT-Ready-G1：Hybrid 落盘可用（是否建子项目）

- hard split 必须创建子项目并写入 Hub lineage contract。
- soft split 不创建子项目，仅 lane task 落盘，不污染 lineage 树。

通过标准：
- `lineage_visibility_coverage = 100%`
- `hard_split_without_child_project = 0`
- `soft_split_lineage_pollution = 0`

### XT-Ready-G2：PromptFactory + 自动分配可用

- Supervisor 可为每个 lane 生成质量规范 prompt contract。
- 可按任务类型/风险/预算自动分配 AI 并给出可解释原因。

通过标准：
- `lane_prompt_contract_coverage = 100%`
- `child_project_assignment_success_rate >= 98%`

### XT-Ready-G3：Heartbeat 主动托管可用

- Supervisor 对每个 lane 主动 heartbeat 巡检。
- stalled/blocked/failed 状态在 2 秒内可感知。

通过标准：
- `lane_stall_detect_p95_ms <= 2000`
- `supervisor_action_latency_p95_ms <= 1500`

### XT-Ready-G4：异常接管与用户协同可用

- 对 `grant_pending / awaiting_instruction / runtime_error` 统一接管。
- 可按策略自动处理或通知用户确认（高风险默认通知用户）。

通过标准：
- `high_risk_lane_without_grant = 0`
- `unaudited_auto_resolution = 0`
- 阻塞事件漏检率 `< 1%`

### XT-Ready-G5：多泳道收口与回滚可用

- lane 结果合并前有质量门禁。
- 合并失败可回滚到 lane 稳定点。

通过标准：
- `mergeback_first_pass_rate >= 70%`
- `mergeback_rollback_success_rate >= 99%`

## 2) 最小 E2E 验收场景（发布前必须跑）

场景：复杂母项目 -> 4 条泳道（含高风险动作）

必须覆盖：
1. Supervisor 提案 + 用户局部覆盖（hard/soft 混合）
2. 自动分配 3 种 AI profile 并并行启动
3. 运行中注入 3 类异常：
   - `grant_pending`
   - `awaiting_instruction`
   - `runtime_error`
4. Supervisor 在 2 秒内接管并执行策略（自动处理/通知用户）
5. lane 收口通过质量门禁并完成合并

判定：
- 任一高风险旁路执行即失败
- 任一关键事件无审计即失败

### 2.1 机器可判定断言（异常 -> deny_code / event_type）

为避免“文档通过但行为漂移”，最小 E2E 的 3 类异常新增固定断言（machine-readable）：

| incident_code | required event_type | required deny_code | 额外断言 |
| --- | --- | --- | --- |
| `grant_pending` | `supervisor.incident.grant_pending.handled` | `grant_pending` | `takeover_latency_ms <= 2000` 且 `audit_ref` 非空 |
| `awaiting_instruction` | `supervisor.incident.awaiting_instruction.handled` | `awaiting_instruction` | `takeover_latency_ms <= 2000` 且 `audit_ref` 非空 |
| `runtime_error` | `supervisor.incident.runtime_error.handled` | `runtime_error` | `takeover_latency_ms <= 2000` 且 `audit_ref` 非空 |

全局约束：
- `high_risk_lane_without_grant = 0`
- `unaudited_auto_resolution = 0`
- `high_risk_bypass_count = 0`
- `non_message_ingress_policy_coverage = 100%`
- `blocked_event_miss_rate < 1%`
- `require-real` 路径禁止 synthetic 证据：`audit_ref` 不得使用 `audit-smoke-*`，且证据源 `source.kind/source.generated_by` 不得为 smoke/synthetic 生成器。

## 2.1) 机器门禁命令（本地/CI 必跑）

```bash
node ./scripts/m3_check_xt_ready_gate.js
```

补充（改了门禁校验脚本本身时必须执行）：

```bash
node ./scripts/m3_check_xt_ready_gate.test.js
```

## 3) 发布口径（对内/对外统一）

- 对内可宣称“Hub 主线完成”的前提：`XT-Ready-G0..G5` 全绿。
- 对外可宣称“复杂项目自动拆分并行能力完成”的前提：
  - Gate 全绿
  - E2E 场景通过
  - 回滚演练通过

## 4) 失败降级策略

若某一 Gate 未通过：
- 默认降级到“单项目/低并发模式”，禁止高风险并行自动执行。
- 阻断 release，生成失败归因与修复清单。

## 5) 可执行门禁命令（must-run）

本门禁要求至少运行一次文档/绑定检查 + 两条 strict-e2e 路径（契约样例 + 真实联测导出）：

```bash
# 1) 文档与绑定硬检查（G0..G5 挂载 + 索引可发现性）
node ./scripts/m3_check_xt_ready_gate.js \
  --out-json ./build/xt_ready_gate_doc_report.json

# 2) strict-e2e（契约样例基线：canonical incident 回放样例 -> contract 证据）
node ./scripts/m3_generate_xt_ready_e2e_evidence.js \
  --strict \
  --events-json ./scripts/fixtures/xt_ready_incident_events.sample.json \
  --out-json ./build/xt_ready_e2e_evidence.contract.json

node ./scripts/m3_check_xt_ready_gate.js \
  --strict-e2e \
  --e2e-evidence ./build/xt_ready_e2e_evidence.contract.json \
  --out-json ./build/xt_ready_gate_e2e_contract_report.json

# 3) strict-e2e（release 真实联测导出优先：audit export -> incident events -> 证据校验）
# 输出路径约定：
# - 默认 current gate：`build/xt_ready_evidence_source.json` + `build/connector_ingress_gate_snapshot.json` + `build/xt_ready_gate_e2e_report.json`
# - release require-real：`build/xt_ready_evidence_source.require_real.json` + `build/connector_ingress_gate_snapshot.require_real.json` + `build/xt_ready_gate_e2e_require_real_report.json`
# - DB-real replay：`build/xt_ready_evidence_source.db_real.json` + `build/connector_ingress_gate_snapshot.db_real.json` + `build/xt_ready_gate_e2e_db_real_report.json`
# release/report/refresh helper 现统一按 `require_real -> db_real -> current` 优先级选取 XT-ready report/source/connector snapshot。
XT_READY_EVIDENCE_SOURCE_JSON="./build/xt_ready_evidence_source.json"
XT_READY_CONNECTOR_GATE_JSON="./build/connector_ingress_gate_snapshot.json"
XT_READY_GATE_REPORT_JSON="./build/xt_ready_gate_e2e_report.json"
# 若本次跑的是 release require-real，请改成：
# XT_READY_EVIDENCE_SOURCE_JSON="./build/xt_ready_evidence_source.require_real.json"
# XT_READY_CONNECTOR_GATE_JSON="./build/connector_ingress_gate_snapshot.require_real.json"
# XT_READY_GATE_REPORT_JSON="./build/xt_ready_gate_e2e_require_real_report.json"
# 若本次跑的是 DB-real replay，请改成：
# XT_READY_EVIDENCE_SOURCE_JSON="./build/xt_ready_evidence_source.db_real.json"
# XT_READY_CONNECTOR_GATE_JSON="./build/connector_ingress_gate_snapshot.db_real.json"
# XT_READY_GATE_REPORT_JSON="./build/xt_ready_gate_e2e_db_real_report.json"

# 3.0 选择审计输入（优先真实联测导出；缺失时回退到 sample fixture）
# release 硬门禁建议开启：`XT_READY_REQUIRE_REAL_AUDIT=1`，若仍回退 sample 则应直接 fail。
# 额外约束：require-real 不接受 synthetic runtime 证据（例如 `audit-smoke-*` / `source.kind=synthetic_runtime`）。
# CI workflow_dispatch 可直接开启：`xt_ready_require_real_audit=true`（等价于 `XT_READY_REQUIRE_REAL_AUDIT=1`）。
# sample fallback 固定路径：`scripts/fixtures/xt_ready_audit_events.sample.json`。
# 若本地仅有 Hub sqlite，可先导出：`node ./scripts/m3_export_xt_ready_audit_from_db.js --db-path ./data/hub.sqlite3 --out-json ./build/xt_ready_audit_export.json`
if [ "${XT_READY_REQUIRE_REAL_AUDIT:-0}" = "1" ]; then
  node ./scripts/m3_resolve_xt_ready_audit_input.js \
    --require-real \
    --out-json "${XT_READY_EVIDENCE_SOURCE_JSON}"
else
  node ./scripts/m3_resolve_xt_ready_audit_input.js \
    --out-json "${XT_READY_EVIDENCE_SOURCE_JSON}"
fi
XT_READY_AUDIT_JSON="$(node -e 'const fs=require(\"node:fs\");const p=process.argv[1];const x=JSON.parse(fs.readFileSync(p,\"utf8\"));process.stdout.write(String(x.selected_audit_json||\"\"));' "${XT_READY_EVIDENCE_SOURCE_JSON}")"

# 3.0a（可选但推荐）从 Hub Admin 接口抓取 connector ingress gate 快照，
# 并把 blocked_event_miss_rate 注入 XT-Ready 证据链（audit 优先，scan 兜底）
# 若未显式传 `HUB_ADMIN_TOKEN`，脚本会优先尝试从本机 Hub 状态目录安全解密读取 admin token。
# 无 Hub Admin 可用时，可回退 sample：`scripts/fixtures/connector_ingress_gate_snapshot.sample.json`
node ./scripts/m3_fetch_connector_ingress_gate_snapshot.js \
  --base-url "${XT_READY_HUB_PAIRING_BASE_URL:-http://127.0.0.1:50053}" \
  --source auto \
  --out-json "${XT_READY_CONNECTOR_GATE_JSON}"

# 3.1 从 Hub/Supervisor 审计导出抽取 XT-Ready incident 事件
node ./scripts/m3_extract_xt_ready_incident_events_from_audit.js \
  --strict \
  --audit-json "${XT_READY_AUDIT_JSON}" \
  --connector-gate-json "${XT_READY_CONNECTOR_GATE_JSON}" \
  --out-json ./build/xt_ready_incident_events.effective.json

# 3.2 由 incident 事件生成 E2E 证据
node ./scripts/m3_generate_xt_ready_e2e_evidence.js \
  --strict \
  --events-json ./build/xt_ready_incident_events.effective.json \
  --out-json ./build/xt_ready_e2e_evidence.json

# 3.3 strict-e2e 校验（严格要求 incident_code 集合与数量完全匹配）
node ./scripts/m3_check_xt_ready_gate.js \
  --strict-e2e \
  --e2e-evidence ./build/xt_ready_e2e_evidence.json \
  --evidence-source "${XT_READY_EVIDENCE_SOURCE_JSON}" \
  --out-json "${XT_READY_GATE_REPORT_JSON}"

# 若 release 强制真实审计导出（禁止 sample fallback），追加：
# --require-real-audit-source
```

补充（改动脚本本身时必须执行）：

```bash
node ./scripts/m3_check_xt_ready_gate.test.js
node ./scripts/m3_generate_xt_ready_e2e_evidence.test.js
node ./scripts/m3_extract_xt_ready_incident_events_from_audit.test.js
node ./scripts/m3_fetch_connector_ingress_gate_snapshot.test.js
node ./scripts/m3_resolve_xt_ready_audit_input.test.js
node ./scripts/m3_export_xt_ready_audit_from_db.test.js
```

## 6) E2E 证据文件格式（`xt_ready_e2e.v1`）

示例（最小字段）：

```json
{
  "schema_version": "xt_ready_e2e.v1",
  "run_id": "xt_ready_run_001",
  "summary": {
    "high_risk_lane_without_grant": 0,
    "unaudited_auto_resolution": 0,
    "high_risk_bypass_count": 0,
    "blocked_event_miss_rate": 0,
    "non_message_ingress_policy_coverage": 1
  },
  "incidents": [
    {
      "incident_code": "grant_pending",
      "lane_id": "lane-2",
      "detected_at_ms": 1730000000100,
      "handled_at_ms": 1730000001200,
      "event_type": "supervisor.incident.grant_pending.handled",
      "deny_code": "grant_pending",
      "audit_event_type": "supervisor.incident.handled",
      "audit_ref": "audit-evt-1"
    }
  ]
}
```
