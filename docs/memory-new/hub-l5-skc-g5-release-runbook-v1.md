# Hub-L5 SKC-G5 一键门禁与回滚演练 Runbook（v1）

- version: `v1.0`
- updatedAt: `2026-03-01`
- owner: `Hub-L5 (SKC-W3-08 / SKC-W3-09 / SKC-W3-10)`
- scope: `require-real 证据链 + SKC-G3 真实性能采样 + release evidence matrix + internal pass-lines + rollback verify`

## 1) 前置输入（必须）

1. 真实审计导出（禁止 sample 冒充）：
   - 示例：`build/xt_ready_audit_export.db_real.json`
2. connector ingress gate 快照（require-real 模式必须 `source_used=audit`）：
   - 示例：`build/connector_ingress_gate_snapshot.db_real.json`
3. SKC-G3 真实采样 sqlite（禁止 sample 伪造）：
   - 示例：`x-hub/grpc-server/hub_grpc_server/data/hub.sqlite3`

## 2) 一键执行（机器可判）

```bash
bash scripts/m3_run_hub_l5_skc_g5_gate.sh \
  --audit-json ./build/xt_ready_audit_export.db_real.json \
  --connector-gate-json ./build/connector_ingress_gate_snapshot.db_real.json \
  --g3-db-path ./x-hub/grpc-server/hub_grpc_server/data/hub.sqlite3 \
  --out-prefix ./build/hub_l5_release
```

返回码：
- `0`: require-real + SKC-G3 + matrix + internal pass-lines 全部达到 GO/PASS
- `2`: 门禁链路可执行，但 internal pass-lines 非 GO 或 SKC-G3 非 PASS
- `1`: fail-closed（输入缺失或门禁脚本失败）

## 3) 核心产物（证据路径）

- `*_xt_ready_evidence_source.require_real.json`
- `*_xt_ready_incident_events.require_real.json`
- `*_xt_ready_e2e_evidence.require_real.json`
- `*_xt_ready_gate_e2e_require_real_report.json`
- `*_release_evidence_matrix.log`
- `*_release_evidence_matrix.summary.json`
- `*_release_evidence_matrix.validator_regression.log`
- `*_skc_g3_real_sampling.json`
- `*_internal_pass_lines_report.json`
- `*_skc_g5_summary.json`

## 4) 回归断言（必须覆盖）

### 4.1 synthetic 证据输入 -> fail-closed

```bash
node ./scripts/m3_check_xt_ready_gate.js \
  --strict-e2e \
  --e2e-evidence ./build/hub_l5_xt_ready_e2e_evidence.synthetic_attempt.json \
  --evidence-source ./build/hub_l5_xt_ready_evidence_source.synthetic_attempt.json \
  --require-real-audit-source
```

预期：退出码非 `0`。

### 4.2 缺失证据文件 -> Gate 阻断

```bash
node ./scripts/m3_check_xt_ready_gate.js \
  --strict-e2e \
  --e2e-evidence ./build/DOES_NOT_EXIST.json \
  --evidence-source ./build/hub_l5_xt_ready_evidence_source.require_real.json \
  --require-real-audit-source
```

预期：退出码非 `0`。

### 4.3 schema 漂移 -> validator 准确失败

```bash
node x-terminal/scripts/ci/xt_release_evidence_matrix_validator_regression.js
```

预期：退出码 `0`（包含负例失败断言）。

## 5) 回滚演练（最小闭环）

```bash
cd x-terminal
bash scripts/ci/xt_release_rollback_stub.sh --verify-only --report-file .axcoder/reports/xt-rollback-verify.json
bash scripts/ci/xt_release_rollback_stub.sh --report-file .axcoder/reports/xt-rollback-last.json
```

验证：

```bash
rg -n '"status": "pass"|"copied_previous_to_current": 1' .axcoder/reports/xt-rollback-last.json -S
```

## 6) 裁决口径

- 若 `*_internal_pass_lines_report.json.release_decision = GO`：可进入 release 候选。
- 若为 `NO-GO` 或 `INSUFFICIENT_EVIDENCE`：必须按报告里的 `failed_hard_lines` / `missing_evidence` 补齐后重跑。
