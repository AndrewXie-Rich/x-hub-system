# XT-W3-08：发布门禁从 Skeleton 到 Strict（XT-G0..G5）

- workOrder: `XT-W3-08`
- priority: `P0`
- gate: `XT-G5`
- status: `done` (strict integrated)
- owner: `Lane-E (QA/Release)`
- updatedAt: `2026-02-28`

## 1) 目标

把原先 skeleton 版发布门禁升级为 strict 可阻断门禁：
- 新增工单 ID（`XT-W3-08` / `CRK-W1-08` / `CM-W5-20`）进入机器检查。
- 缺项在 `strict` 模式下直接失败（fail-closed），不再 baseline 忽略。
- 报告具备可追溯的“新增工单 ID 覆盖区块”。
- 回滚脚本从 stub 升级为可执行最小流程，并能被 gate 验证。

## 2) 本轮交付

- CI workflow：`.github/workflows/xt-gates.yml`
  - 新增 strict 回归场景：
    1) 缺 doctor 报告 -> 必须失败。
    2) 缺 secrets dry-run 报告 -> 必须失败。
    3) `xt-route-smoke + xt-grant-smoke + xt-supervisor-voice-smoke + 新增静态检查` 同时通过 -> 必须 PASS。
  - 新增 `Split Audit Contract Check` 步骤：
    - 运行 `scripts/ci/xt_split_audit_contract_check.sh`
    - 校验正/负 fixture + `decodeResult` 目标回归用例
- 回归场景使用 `XT_GATE_SKIP_BUILD=1`，避免与 G1 独立编译检查重复计时；`xt-route-smoke`、`xt-grant-smoke` 与 `xt-supervisor-voice-smoke` 仍会执行。
- Gate 入口脚本：`scripts/ci/xt_release_gate.sh`
  - XT-G2/XT-G4/XT-G5 增补安全项与证据检查。
  - strict 模式缺 doctor/secrets 直接 fail。
  - 报告新增“新增工单ID覆盖区块”。
  - 接入 skills ecosystem 回灌扩展检查（`XT-W2-17/18/19`）的留口：上下文溢出、origin-safe fallback、dispatch cleanup。
- 回滚脚本：`scripts/ci/xt_release_rollback_stub.sh`
  - 升级为可执行最小流程（verify-only / apply + report 落盘）。

## 3) Gate 覆盖映射（Strict）

### XT-G2 / Security

- 原有高风险 grant 静态护栏继续保留。
- 新增 `CRK-W1-08` / 入口授权等价静态契约检查：
  - `pre-auth body/key cap`
  - `WS unauthorized flood breaker`
  - `非消息入口`
  - `reaction/pin/member/webhook`

### XT-G3 / Efficiency & Token

- 新增 `XT-W2-17` 指标断言（父会话上下文溢出保护）：
  - `parent_fork_overflow_silent_fail = 0`
  - `parent_fork_overflow_detect_p95_ms <= 1000`
- 新增调度公平性断言（与 `XT-W2-16` 联动）：
  - `retry_starvation_incidents = 0`
  - `queue_wait_p90_ms` 未因 overflow 重试显著劣化（相对基线阈值）

### XT-G4 / Reliability

- 运行 `swift run XTerminal --xt-route-smoke`、`swift run XTerminal --xt-grant-smoke` 与 `swift run XTerminal --xt-supervisor-voice-smoke`。
- 强制组合断言：
  - 仅当 `xt-route-smoke + xt-grant-smoke + xt-supervisor-voice-smoke` 与新增静态检查同时通过，才记为 PASS。
- 新增 `XT-W2-18` 路由边界断言：
  - origin 不可用仅允许同通道回退；
  - 任意跨通道 fallback 直接 fail 并输出违规样本。
- 新增 `XT-W2-19` 完成清理断言：
  - run 结束后必须观察到 dispatch idle/typing cleanup；
  - `dispatch_idle_stuck_incidents = 0`。

### XT-G5 / Release Ready

- 新增 `CM-W5-20` 证据文件检查：
  - `doctor` 报告（含 parity/flood/allowlist/ws-origin/shared-token 等关键符号）
  - `secrets apply --dry-run` 报告（dry-run/target-path/missing-vars/permission-boundary）
- strict 模式：任一报告缺失即失败。
- 调用回滚脚本 `--verify-only`，要求可执行且能产出验证报告。
- skills ecosystem 扩展证据（新增）：
  - `.axcoder/reports/xt-overflow-fairness-report.json`
  - `.axcoder/reports/xt-origin-fallback-report.json`
  - `.axcoder/reports/xt-dispatch-cleanup-report.json`
  - strict 模式下三者缺失任一项均失败（可通过 `XT_GATE_SKIP_SKILL_EXT=1` 临时降级，仅限独立演示环境）。

## 4) 报告与追溯

`xt_release_gate.sh` 输出 `.axcoder/reports/xt-gate-report.md`，新增区块：
- `XT-W3-08`
- `CRK-W1-08`
- `CM-W5-20`
- `XT-W2-17`
- `XT-W2-18`
- `XT-W2-19`
- 以及 doctor/secrets/rollback/split-audit-contract 证据文件路径。
- 新增 `evidence.release_evidence_matrix_log`（用于追踪 release preset × auto prepare 的四象限回归日志）。
- 新增 `evidence.release_evidence_matrix_summary`（矩阵日志结构化校验产物，schema=`xt_release_evidence_matrix.v1`）。
- 新增 `evidence.release_evidence_matrix_validator_regression_log`（validator 负例回归执行日志）。
- 新增 `evidence.split_flow_runtime_policy_regression` / `evidence.split_flow_runtime_policy_regression_log`（split-flow 策略回归结果与日志）。
- 同步输出聚合索引：`.axcoder/reports/xt-report-index.json`（机器可直接读取）。

## 5) 运行方式

```bash
cd x-hub-system/x-terminal
bash scripts/ci/xt_release_gate.sh
```

严格模式：

```bash
cd x-hub-system/x-terminal
XT_GATE_MODE=strict bash scripts/ci/xt_release_gate.sh
```

若在独立仓 CI 运行（不需要 XT-Ready 外部文档联动），可显式跳过外部合同检查：

```bash
XT_GATE_SKIP_XT_READY_CONTRACT=1 XT_GATE_SKIP_XT_READY_EXECUTABLE=1 XT_GATE_MODE=strict bash scripts/ci/xt_release_gate.sh
```

发布预设演练（release preset fail-closed + 自动准备证据）：

```bash
XT_GATE_MODE=strict \
XT_GATE_RELEASE_PRESET=1 \
XT_GATE_AUTO_PREPARE_RELEASE_EVIDENCE=1 \
bash scripts/ci/xt_release_gate.sh
```

四象限回归（release_preset × auto_prepare）：

```bash
XT_GATE_MODE=baseline \
XT_GATE_VALIDATE_RELEASE_EVIDENCE_MATRIX=1 \
bash scripts/ci/xt_release_gate.sh
```

Hub-L5 一键机判入口（require-real + matrix + pass-lines）：

```bash
cd x-hub-system
bash scripts/m3_run_hub_l5_skc_g5_gate.sh \
  --audit-json ./build/xt_ready_audit_export.db_real.json \
  --connector-gate-json ./build/connector_ingress_gate_snapshot.db_real.json \
  --out-prefix ./build/hub_l5_release
```

说明：矩阵回归现已覆盖 split-flow runtime policy 默认策略断言（release preset 下默认启用、非 release preset 默认跳过）。

CI 提前失败单元（不依赖 gate 主流程）：

```bash
node scripts/ci/xt_release_evidence_matrix_validator_regression.js
node scripts/ci/xt_fast_check_trend_append_regression.js
```

本地一键快速自检（提交前建议）：

```bash
bash scripts/ci/xt_gate_fast_checks.sh
```

默认行为：执行 validator 回归（matrix + fast-check trend，最快路径）。可通过 `XT_FAST_CHECK_*` 系列环境变量开启 `swift build` 与 baseline matrix gate。
若开启 `swift build` 且本地存在 sandbox/toolchain 限制，脚本会在 `XT_FAST_CHECK_ALLOW_BUILD_SANDBOX_FAILURE=1`（默认）时将 build 降级为 warning 并继续执行其余快检。
快检会落盘结构化摘要：`.axcoder/reports/xt-fast-check-summary.json`（schema=`xt_fast_checks.v1`，可通过 `XT_FAST_CHECK_REPORT_FILE` 覆盖），并默认追加趋势历史到 `.axcoder/reports/xt-fast-check-history.json`（schema=`xt_fast_check_history.v1`，保留最近 `XT_FAST_CHECK_HISTORY_LIMIT` 条，默认 20）。
若仅需摘要不留历史，可设置：`XT_FAST_CHECK_APPEND_HISTORY=0`。

全量快检示例：

```bash
XT_FAST_CHECK_RUN_BUILD=1 \
XT_FAST_CHECK_RUN_MATRIX=1 \
bash scripts/ci/xt_gate_fast_checks.sh
```

可手动追加/回放历史（用于离线留痕）：

```bash
node scripts/ci/xt_fast_check_trend_append.js \
  --summary .axcoder/reports/xt-fast-check-summary.json \
  --history .axcoder/reports/xt-fast-check-history.json \
  --limit 20
```

快检摘要关键字段（`xt_fast_checks.v1`）：
- `overall_status`: `pass|fail`
- `config.run_*`: 本次执行开关（0/1）
- `steps.*.status`: `pass|fail|warn|skipped|pending`

快检历史关键字段（`xt_fast_check_history.v1`）：
- `limit`: 保留窗口
- `total_entries`: 当前历史条数
- `overview.pass_count / fail_count / warn_step_runs / pass_rate`: 窗口聚合
- `latest_entry`: 最近一次快检结果（`generated_at` / `overall_status` / `exit_code`）
- `step_status_counts.<step>.{pass|fail|warn|skipped|pending|unknown}`: 各步骤状态分布
- `entries[].overall_status / entries[].exit_code / entries[].steps.*.status`: 趋势对比最小集

## 6) DoD（Strict 阶段）

- `XT-G5` 达到可执行、可阻断、可追溯。
- strict 模式下 doctor/secrets 报告缺失均可稳定阻断。
- `xt-route-smoke + xt-grant-smoke + xt-supervisor-voice-smoke + 新增静态检查` 同时通过时 gate 才可 PASS。
- rollback 从 stub 升级为最小可验证流程，且 gate 可自动验证并留痕。
- `XT-W2-17/18/19` 的证据报告在 strict 下默认必需，确保 overflow/fallback/cleanup 行为被持续回归。

## 7) 验收证据模板（CI Artifact）

建议在 PR/发布审查中附上以下文件（`xt-gates.yml` 已上传）：
- `.axcoder/reports/xt-gate-report.md`
- `.axcoder/reports/xt-report-index.json`
- `.axcoder/reports/doctor-report.json`
- `.axcoder/reports/secrets-dry-run-report.json`
- `.axcoder/reports/split-audit-contract-report.json`
- `.axcoder/reports/supervisor_doctor_report.json`
- `.axcoder/reports/xt-overflow-fairness-report.json`
- `.axcoder/reports/xt-origin-fallback-report.json`
- `.axcoder/reports/xt-dispatch-cleanup-report.json`
- `.axcoder/reports/xt-rollback-verify.json`
- `.axcoder/reports/xt-rollback-last.json`
- `.axcoder/reports/xt-gate-release-evidence-matrix.log`
- `.axcoder/reports/xt-gate-release-evidence-matrix.summary.json`
- `.axcoder/reports/xt-gate-release-evidence-matrix.validator-regression.log`
- `.axcoder/reports/xt-fast-check-summary.json`（本地快检产物，非发布硬门禁）
- `.axcoder/reports/xt-fast-check-history.json`（本地快检趋势留痕，非发布硬门禁）
- `.axcoder/release/current.manifest.json`
- `.axcoder/release/previous.manifest.json`

最小核对语句：
- `xt-gate-report.md` 包含：`## 新增工单ID覆盖区块`
- `xt-gate-report.md` 包含：`## Release Decision` 与 `decision: GO`
- `xt-gate-report.md` 包含：`XT-W3-08: PASS` / `CRK-W1-08: PASS` / `CM-W5-20: PASS`
- `xt-gate-report.md` 包含：`XT-W2-17: PASS` / `XT-W2-18: PASS` / `XT-W2-19: PASS`
- `xt-gate-report.md` 包含：`xt-route-smoke + xt-grant-smoke + xt-supervisor-voice-smoke + 新增静态检查同时通过`
- `xt-gate-report.md` 包含：`evidence.split_audit_contract_report`
- `xt-report-index.json` 包含：`"schema_version": "xt_report_index.v1"`、`"release_decision": "GO"`、覆盖项 `XT-W3-08/CRK-W1-08/CM-W5-20/XT-W2-17/XT-W2-18/XT-W2-19 = PASS`
- `xt-rollback-last.json` 包含：`"status": "pass"`、`"copied_previous_to_current": 1`

PR 评审可直接贴这句：
`GO when xt-gate-report.md has decision: GO and all IDs (XT-W3-08/CRK-W1-08/CM-W5-20/XT-W2-17/XT-W2-18/XT-W2-19) are PASS, with rollback apply evidence present.`

## 8) PR 描述粘贴模板（可直接复制）

```markdown
## 验收结论（XT-W3-08 / CRK-W1-08 / CM-W5-20）

本 PR 已将发布门禁从 skeleton 升级为 strict 可阻断形态，并接入新增安全项检查与证据化输出。  
**Gate 判定规则：仅当 `xt-gate-report.md` 中 `decision: GO`，且 `XT-W3-08/CRK-W1-08/CM-W5-20/XT-W2-17/XT-W2-18/XT-W2-19` 全部为 `PASS` 时允许发布。**

### Gate 判定语句（机器可判定）

`GO when xt-gate-report.md has decision: GO and all IDs (XT-W3-08/CRK-W1-08/CM-W5-20/XT-W2-17/XT-W2-18/XT-W2-19) are PASS, with rollback apply evidence present.`

### Artifact 列表（CI 上传证据包）

- `.axcoder/reports/xt-gate-report.md`
- `.axcoder/reports/xt-report-index.json`
- `.axcoder/reports/doctor-report.json`
- `.axcoder/reports/secrets-dry-run-report.json`
- `.axcoder/reports/split-audit-contract-report.json`
- `.axcoder/reports/supervisor_doctor_report.json`
- `.axcoder/reports/xt-overflow-fairness-report.json`
- `.axcoder/reports/xt-origin-fallback-report.json`
- `.axcoder/reports/xt-dispatch-cleanup-report.json`
- `.axcoder/reports/xt-rollback-verify.json`
- `.axcoder/reports/xt-rollback-last.json`
- `.axcoder/release/current.manifest.json`
- `.axcoder/release/previous.manifest.json`

### 失败回滚指令（Fail -> Rollback）

1) 先做回滚可执行性校验（不改当前版本）  
```bash
bash scripts/ci/xt_release_rollback_stub.sh --verify-only --report-file .axcoder/reports/xt-rollback-verify.json
```

2) 执行最小回滚（将 previous 覆盖到 current，并落盘回滚报告）  
```bash
bash scripts/ci/xt_release_rollback_stub.sh --report-file .axcoder/reports/xt-rollback-last.json
```

3) 回滚后复核关键证据  
```bash
rg -n '"status": "pass"|"copied_previous_to_current": 1|"release_id"' .axcoder/reports/xt-rollback-last.json -S
rg -n '"release_id"' .axcoder/release/current.manifest.json -S
```

4) 重新跑 strict gate 复核（与 CI 严格回归口径一致）  
```bash
XT_GATE_MODE=strict \
XT_GATE_SKIP_BUILD=1 \
XT_GATE_SKIP_XT_READY_CONTRACT=1 \
XT_GATE_SKIP_XT_READY_EXECUTABLE=1 \
XT_DOCTOR_REPORT=.axcoder/reports/doctor-report.json \
XT_SECRETS_DRY_RUN_REPORT=.axcoder/reports/secrets-dry-run-report.json \
bash scripts/ci/xt_release_gate.sh
```

## 9) 上线前人工复核清单（5条）

1. `xt-gate-report.md` 中 `Release Decision` 为 `decision: GO`，且 `fail: 0`。  
2. `新增工单ID覆盖区块` 中 `XT-W3-08 / CRK-W1-08 / CM-W5-20 / XT-W2-17 / XT-W2-18 / XT-W2-19` 均为 `PASS`。  
3. 报告中存在 `xt-route-smoke + xt-grant-smoke + xt-supervisor-voice-smoke + 新增静态检查同时通过`，确认运行时 smoke 与静态规则同时生效。
4. `xt-report-index.json` 里 `schema_version=xt_report_index.v1`、`release_decision=GO`、六项覆盖均为 `PASS`。  
5. 回滚证据齐全：`xt-rollback-last.json` 包含 `"status": "pass"` 与 `"copied_previous_to_current": 1`，且 `current.manifest.json` 的 `release_id` 已对齐稳定版本。  
