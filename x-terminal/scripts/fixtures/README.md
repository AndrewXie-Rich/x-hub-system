# Supervisor & Skills Fixtures

This directory contains machine-readable samples for split proposal audit payloads.

- `split_audit_payload_events.sample.json`
  - schema: `xterminal.split_audit_fixture.v1`
  - payload schema: `xterminal.split_audit_payload`
  - includes all current split audit event types:
    - `supervisor.split.proposed`
    - `supervisor.prompt.compiled`
    - `supervisor.split.confirmed`
    - `supervisor.split.overridden`
    - `supervisor.prompt.rejected`
    - `supervisor.split.rejected`
  - `supervisor.split.overridden` payload includes replay/confirmation fields:
    - `blocking_issue_count`, `blocking_issue_codes`
    - `high_risk_hard_to_soft_confirmed_count`, `high_risk_hard_to_soft_confirmed_lane_ids`
    - `is_replay`
- `split_audit_payload_events.invalid.sample.json`
  - intentionally broken sample for negative regression (wrong payload version + mismatched payload event type + missing required event set)
- `split_flow_snapshot.sample.json`
  - schema: `xterminal.split_flow_snapshot_fixture.v1`
  - snapshot schema: `xterminal.split_flow_snapshot`
  - state machine version: `xterminal.split_flow_state_machine.v1`
  - includes baseline `proposed -> overridden -> blocked -> confirmed` transition trace
  - covers prompt states `null/rejected/ready` and override replay fields
- `split_flow_snapshot.invalid.sample.json`
  - intentionally broken sample for negative regression (fixture schema mismatch + state machine version mismatch + invalid transition + invalid datetime)
- `skills_xt_l1_contract.sample.json`
  - schema: `xterminal.skills_xt_l1_contract_fixture.v1`
  - contract schema: `xterminal.skills_xt_l1_contract.v1`
  - covers XT-L1 scope (`SKC-W1-02` 协同 + `SKC-W2-05` + `SKC-W4-11`):
    - 搜索/导入/分层 pin 交互断言
    - preflight（bin/env/config/capability）+ 修复卡片
    - runner 约束（network/path/capability）+ explainable deny_code
    - 热更新失败回退旧 snapshot（当前回合不污染）
- `skills_xt_l1_contract.invalid.sample.json`
  - intentionally broken sample for negative regression (schema drift + gate fail + chain missing stage + secret leak)

Use this fixture as a stable baseline for downstream decoders (for example AI-XT-2 integration tests).

Decoder integration guide (AI-XT-2):

- `split_audit_decode_result_guide.md`
  - recommends `decodeResult(event)` as primary entry.
  - keeps `decode(event)` as backward-compatible fallback.
  - includes error-code handling table for `SplitAuditPayloadDecodeError`.

Quick checks:

```bash
node ./scripts/check_split_audit_fixture_contract.js
node ./scripts/check_split_audit_fixture_contract.test.js
node ./scripts/check_split_audit_fixture_contract.js --out-json ./.axcoder/reports/split-audit-contract-report.json
node ./scripts/check_split_flow_snapshot_fixture_contract.js
node ./scripts/check_split_flow_snapshot_fixture_contract.test.js
node ./scripts/check_split_flow_snapshot_fixture_contract.js --out-json ./.axcoder/reports/split-flow-fixture-contract-report.json
node ./scripts/generate_split_flow_snapshot_fixture.js --out-json ./.axcoder/reports/split_flow_snapshot.runtime.json
node ./scripts/check_split_flow_snapshot_generation_regression.js --generated ./.axcoder/reports/split_flow_snapshot.runtime.json
node ./scripts/check_split_flow_snapshot_generation_regression.test.js
node ./scripts/check_skills_xt_l1_contract.js
node ./scripts/check_skills_xt_l1_contract.test.js
node ./scripts/check_skills_xt_l1_contract.js --out-json ./.axcoder/reports/skills_xt_l1_contract_report.json
bash ./scripts/ci/xt_split_flow_fixture_refresh.sh
bash ./scripts/ci/xt_split_flow_fixture_refresh.sh --copy-to-sample --run-gate-baseline
bash ./scripts/ci/xt_split_flow_fixture_refresh.sh --run-gate-strict
bash ./scripts/ci/xt_split_flow_runtime_policy_regression.sh
```

`split-audit-contract-report.json` now includes `summary` with:

- `event_type_counts`
- `split_overridden.event_count`
- `split_overridden.override_count_total`
- `split_overridden.blocking_issue_total`
- `split_overridden.high_risk_hard_to_soft_confirmed_total`
- `split_overridden.replay_event_count`

`split-flow-fixture-contract-report.json` includes:

- `summary.snapshot_count`
- `summary.flow_state_counts`
- `summary.prompt_status_counts`
- `summary.override_total`
- `summary.unique_override_lane_id_count`

`split_flow_snapshot.runtime.json` can be generated from real `SupervisorOrchestrator`
flow via `--xt-split-flow-fixture-smoke`; then
`check_split_flow_snapshot_generation_regression.js` compares its normalized
shape against the canonical sample fixture to catch behavior drift.

`skills_xt_l1_contract_report.json` includes:

- `summary.case_count`
- `summary.pass_case_count`
- `summary.blocked_case_count`
- `summary.rollback_case_count`
- `summary.import_to_first_run_p95_ms`
- `summary.skill_first_run_success_rate`
- `summary.preflight_false_positive_rate`
- `kpi_snapshot.import_to_first_run_p95_ms`
- `kpi_snapshot.skill_first_run_success_rate`
- `kpi_snapshot.preflight_false_positive_rate`

Gate runtime regression switches (`scripts/ci/xt_release_gate.sh`):

- `XT_GATE_SPLIT_FLOW_RUNTIME_REGRESSION=1`
- `XT_GATE_SPLIT_FLOW_GENERATE_RUNTIME_FIXTURE=1|0`
- `XT_SPLIT_FLOW_RUNTIME_FIXTURE=<path>`
- `XT_GATE_VALIDATE_SPLIT_FLOW_RUNTIME_POLICY=1`（可选：执行策略回归脚本并写 gate 证据）

Default policy:

- `XT_GATE_MODE=baseline`: runtime regression default `off`
- `XT_GATE_MODE=strict`: runtime regression default `on`（auto-generate runtime fixture unless explicitly disabled）
- `XT_GATE_RELEASE_PRESET=1`: runtime regression is mandatory (`XT_GATE_SPLIT_FLOW_RUNTIME_REGRESSION=1`)
- `XT_GATE_RELEASE_PRESET=1`: split-flow runtime policy regression gate is enabled by default (`XT_GATE_VALIDATE_SPLIT_FLOW_RUNTIME_POLICY=1`)

Example:

```bash
XT_GATE_MODE=baseline \
XT_GATE_SPLIT_FLOW_RUNTIME_REGRESSION=1 \
XT_GATE_SPLIT_FLOW_GENERATE_RUNTIME_FIXTURE=1 \
bash ./scripts/ci/xt_release_gate.sh

XT_GATE_MODE=baseline \
XT_GATE_VALIDATE_SPLIT_FLOW_RUNTIME_POLICY=1 \
bash ./scripts/ci/xt_release_gate.sh
```

Expected report/index evidence keys:

- `evidence.split_flow_contract_report`
- `evidence.split_flow_fixture_contract_report`
- `evidence.split_flow_fixture.snapshot_count`
- `evidence.split_flow_runtime_fixture`
- `evidence.split_flow_runtime_regression`
- `evidence.split_flow_runtime_policy_regression`
- `evidence.split_flow_runtime_policy_regression_log`
- `split_flow_contract_summary.snapshot_schema`
- `split_flow_contract_summary.snapshot_version`
- `split_flow_contract_summary.state_machine_version`
- `split_flow_fixture_summary.snapshot_count`
- `split_flow_runtime_regression.status`
- `split_flow_runtime_policy_regression.status`
