# X-Hub / X-Terminal 内部发布硬指标通过线（v1）

- version: v1.0
- updatedAt: 2026-02-28
- owner: Hub Runtime / X-Terminal Supervisor / Security / QA
- status: active
- scope: internal release decision only（仅内部裁决，不用于对外竞品表达）
- related:
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
  - `docs/memory-new/xhub-connector-reliability-kernel-work-orders-v1.md`
  - `scripts/m3_check_internal_pass_lines.js`
  - `x-terminal/work-orders/xterminal-parallel-work-orders-v1.md`
  - `x-terminal/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w3-08-release-gate-skeleton.md`

## 0) 使用原则

- 本文件用于统一“是否可发布/是否可宣称主线完成”的硬门槛。
- 任何指标未过线，结论必须是 `NO-GO`，不得口头豁免。
- 本文件明确禁止“对外超越叙述”作为发布条件；发布只看可验证证据。

## 1) 总判定规则（GO / NO-GO）

`GO` 必须同时满足：
1. Gate 全绿（Hub + XT + XT-Ready）。
2. P0 硬指标全过线（效率/安全/Token/可靠性）。
3. 证据文件齐全且来源合规（release 必须 real audit）。

出现以下任一项即 `NO-GO`：
- 任一 P0 指标未达标。
- 任一必需证据缺失。
- `XT_READY_REQUIRE_REAL_AUDIT=1` 路径未通过。
- 出现 fail-open 或无审计高风险执行。

## 2) 样本有效性门槛（防“少量样本假达标”）

发布窗口内（建议最近 7 天滚动）最小样本要求：
- `lane_event_count >= 1000`
- `high_risk_request_count >= 300`
- `mergeback_runs >= 100`

若样本不足：
- 判定状态为 `INSUFFICIENT_EVIDENCE`，视同 `NO-GO`。

## 3) P0 硬指标通过线（必须全部通过）

### HL-01 Gate 完整性

- `Gate-M3-0..4 = PASS`
- `XT-Ready-G0..G5 = PASS`
- `XT-G0..G5 (strict) = PASS`
- `XT-W3-08/CRK-W1-08/CM-W5-20/XT-W2-17/XT-W2-18/XT-W2-19 = PASS`

### HL-02 证据来源真实性

- `XT_READY_REQUIRE_REAL_AUDIT=1` 流程通过。
- `--require-real-audit-source` 校验通过。
- connector gate 快照在 require-real 模式下必须 `source_used=audit`。

### HL-03 效率（并行执行）

- `queue_wait_p90_ms <= 3200`
- `split_to_parallel_start_p95_ms <= 8000`
- `proposal_ready_p95_ms <= 4000`
- `lane_stall_detect_p95_ms <= 2000`
- `supervisor_action_latency_p95_ms <= 1500`
- `child_project_assignment_success_rate >= 98%`
- `mergeback_first_pass_rate >= 70%`
- `mean_time_to_root_cause <= 30min`

### HL-04 安全（授权主链）

- `high_risk_lane_without_grant = 0`
- `bypass_grant_execution = 0`
- `high_risk_bypass_count = 0`
- `unaudited_auto_resolution = 0`
- `unsigned_high_risk_skill_exec = 0`
- `credential_finding_block_rate = 100%`

### HL-05 安全（入口与预鉴权）

- `non_message_ingress_policy_coverage = 100%`
- `blocked_event_miss_rate < 1%`
- `preauth_memory_growth_unbounded = 0`
- `webhook_replay_accept_count = 0`
- `cross_channel_fallback_blocked = 100%`

### HL-06 Token 与成本

- `token_per_task_delta <= -20%`
- `token_budget_overrun_rate <= 3%`
- `cross_session_dedup_hit_rate >= 60%`
- `cross_lane_context_dedup_hit_rate >= 60%`
- `parent_fork_overflow_silent_fail = 0`
- `parent_fork_overflow_detect_p95_ms <= 1000`

### HL-07 可靠性（重启/重试/排空）

- `enqueue_during_drain_silent_drop = 0`
- `retry_starvation_incidents = 0`
- `restart_recovery_success_rate >= 99%`
- `dispatch_idle_stuck_incidents = 0`
- `route_origin_fallback_violations = 0`

### HL-08 谱系一致性

- `lineage_visibility_coverage = 100%`
- `hard_split_without_child_project = 0`
- `soft_split_lineage_pollution = 0`
- `lineage_cycle_incidents = 0`

### HL-09 回滚与恢复

- `mergeback_rollback_success_rate >= 99%`
- 回滚演练证据存在且可复核（`status=pass` + manifest 对齐）。

### HL-10 契约稳定性

- `contract_test_drift_incidents = 0`
- `missing_deny_code_coverage = 0`
- deny_code 字典、contract test、实现三方一致。

## 4) 发布必需证据（缺一项即 NO-GO）

- `.axcoder/reports/xt-gate-report.md`
- `.axcoder/reports/xt-report-index.json`
- `.axcoder/reports/xt-overflow-fairness-report.json`
- `.axcoder/reports/xt-origin-fallback-report.json`
- `.axcoder/reports/xt-dispatch-cleanup-report.json`
- `.axcoder/reports/doctor-report.json`
- `.axcoder/reports/secrets-dry-run-report.json`
- `.axcoder/reports/xt-rollback-last.json`
- `build/xt_ready_gate_e2e_require_real_report.json` or `build/xt_ready_gate_e2e_db_real_report.json` or `build/xt_ready_gate_e2e_report.json`
- `build/xt_ready_evidence_source.require_real.json` or `build/xt_ready_evidence_source.db_real.json` or `build/xt_ready_evidence_source.json`
- `build/connector_ingress_gate_snapshot.require_real.json` or `build/connector_ingress_gate_snapshot.db_real.json` or `build/connector_ingress_gate_snapshot.json`

## 5) 必跑命令（发布前）

```bash
# 1) XT strict gate
cd x-hub-system/x-terminal
XT_GATE_MODE=strict bash scripts/ci/xt_release_gate.sh

# 2) XT-Ready doc + strict-e2e（契约样例 + 真实审计）
cd x-hub-system
node ./scripts/m3_check_xt_ready_gate.js --out-json ./build/xt_ready_gate_doc_report.json

node ./scripts/m3_generate_xt_ready_e2e_evidence.js \
  --strict \
  --events-json ./scripts/fixtures/xt_ready_incident_events.sample.json \
  --out-json ./build/xt_ready_e2e_evidence.contract.json

node ./scripts/m3_check_xt_ready_gate.js \
  --strict-e2e \
  --e2e-evidence ./build/xt_ready_e2e_evidence.contract.json \
  --out-json ./build/xt_ready_gate_e2e_contract_report.json

XT_READY_REQUIRE_REAL_AUDIT=1 node ./scripts/m3_resolve_xt_ready_audit_input.js \
  --require-real \
  --out-json ./build/xt_ready_evidence_source.require_real.json

# 3) 内部通过线裁决（输出 GO / NO-GO / INSUFFICIENT_EVIDENCE）
node ./scripts/m3_check_internal_pass_lines.js \
  --window "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --out-json ./build/internal_pass_lines_report.json
```

默认路径选择现在会优先读取 `require_real -> db_real -> current` 这三档 XT-ready report/source；只有在你显式传 `--xt-ready-gate-report` 或 `--xt-ready-evidence-source` 时才会覆盖这个优先级。
同一优先级也适用于 connector snapshot；如果你显式改的是标准 `require_real / db_real / current` 路径，脚本会自动补齐同链 connector snapshot；如果你传的是自定义非标准路径，仍建议同时传 `--connector-gate-snapshot`，避免把不同链路的证据混读。

若修改了通过线裁决脚本本身，补跑：

```bash
node ./scripts/m3_check_internal_pass_lines.test.js
```

## 6) 裁决输出模板（供 Orchestrator/值班使用）

```text
release_decision: GO|NO-GO|INSUFFICIENT_EVIDENCE
window: <start_utc>..<end_utc>
failed_hard_lines: [HL-xx, ...]
missing_evidence: [path, ...]
sample_summary:
  lane_event_count: <n>
  high_risk_request_count: <n>
  mergeback_runs: <n>
notes: <one-line>
```

## 7) 变更规则

- 调整任何硬指标阈值，必须：
  1) 先更新本文件版本（`v1 -> v2`）；
  2) 同步更新对应 Gate 文档和脚本；
  3) 增加回归样例并在 CI 中验证。
- 未完成以上步骤，不得修改通过线。
