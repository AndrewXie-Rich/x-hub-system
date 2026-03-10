#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_DIR="${XT_GATE_REPORT_DIR:-${ROOT_DIR}/.axcoder/reports}"
REPORT_FILE="${XT_GATE_REPORT_FILE:-${REPORT_DIR}/xt-gate-report.md}"
REPORT_INDEX_FILE="${XT_GATE_REPORT_INDEX_FILE:-${REPORT_DIR}/xt-report-index.json}"
MODE="${XT_GATE_MODE:-baseline}" # baseline | strict

case "${MODE}" in
  baseline|strict) ;;
  *)
    echo "[xt-gate] invalid XT_GATE_MODE=${MODE} (expected baseline|strict)" >&2
    exit 2
    ;;
esac

pass_count=0
warn_count=0
fail_count=0

pass_lines=()
warn_lines=()
fail_lines=()

coverage_xt_w3_08_status="PASS"
coverage_crk_w1_08_status="PASS"
coverage_cm_w5_20_status="PASS"
coverage_doctor_report_path="(not checked)"
coverage_secrets_report_path="(not checked)"
coverage_rollback_report_path="(not checked)"
coverage_split_audit_contract_report_path="(not checked)"
release_evidence_prepare_attempted=0
release_evidence_prepare_succeeded=0
release_evidence_prepare_log="/tmp/xt_gate_release_evidence_prepare.log"
coverage_split_audit_overridden_events="(not checked)"
coverage_split_audit_override_total="(not checked)"
coverage_split_audit_blocking_total="(not checked)"
coverage_split_audit_high_risk_confirmed_total="(not checked)"
coverage_split_audit_replay_events="(not checked)"
coverage_split_flow_contract_report_path="(not checked)"
coverage_split_flow_snapshot_schema="(not checked)"
coverage_split_flow_snapshot_version="(not checked)"
coverage_split_flow_state_machine_version="(not checked)"
coverage_split_flow_fixture_contract_report_path="(not checked)"
coverage_split_flow_fixture_snapshot_count="(not checked)"
coverage_split_flow_runtime_fixture_path="(not checked)"
coverage_split_flow_runtime_regression_status="(not checked)"
coverage_split_flow_runtime_policy_regression_status="(not checked)"
coverage_split_flow_runtime_policy_regression_log_path="(not checked)"
coverage_release_evidence_matrix_log_path="(not checked)"
coverage_release_evidence_matrix_summary_path="(not checked)"
coverage_release_evidence_matrix_validator_regression_log_path="(not checked)"

note_pass() {
  pass_count=$((pass_count + 1))
  pass_lines+=("- PASS: $1")
}

note_warn() {
  warn_count=$((warn_count + 1))
  warn_lines+=("- WARN: $1")
}

note_fail() {
  fail_count=$((fail_count + 1))
  fail_lines+=("- FAIL: $1")
}

mark_status_warn() {
  local var_name="$1"
  local current="${!var_name:-PASS}"
  if [[ "${current}" == "PASS" ]]; then
    printf -v "${var_name}" "%s" "WARN"
  fi
}

mark_status_fail() {
  local var_name="$1"
  printf -v "${var_name}" "%s" "FAIL"
}

resolve_first_existing_file() {
  local preferred="$1"
  shift || true
  if [[ -f "${preferred}" ]]; then
    echo "${preferred}"
    return
  fi
  local candidate
  for candidate in "$@"; do
    if [[ -f "${candidate}" ]]; then
      echo "${candidate}"
      return
    fi
  done
  echo "${preferred}"
}

resolve_xt_cli_binary() {
  local candidates=(
    "${ROOT_DIR}/.build/debug/XTerminal"
    "${ROOT_DIR}/.build/arm64-apple-macosx/debug/XTerminal"
    "${ROOT_DIR}/.build/x86_64-apple-macosx/debug/XTerminal"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done
  return 1
}

is_xt_cli_binary_fresh() {
  local binary_path="$1"
  [[ -x "${binary_path}" ]] || return 1

  if [[ -f "${ROOT_DIR}/Package.swift" ]] && [[ "${ROOT_DIR}/Package.swift" -nt "${binary_path}" ]]; then
    return 1
  fi

  if [[ -d "${ROOT_DIR}/Sources" ]]; then
    local newer_source=""
    newer_source="$(find "${ROOT_DIR}/Sources" -type f -name "*.swift" -newer "${binary_path}" -print -quit 2>/dev/null || true)"
    if [[ -n "${newer_source}" ]]; then
      return 1
    fi
  fi

  return 0
}

is_fixture_path() {
  local raw="${1:-}"
  local normalized="${raw//\\//}"
  [[ "${normalized}" == *"/scripts/fixtures/"* ]] \
    || [[ "${normalized}" == *.sample.json ]] \
    || [[ "${normalized}" == *_sample.json ]]
}

prepare_release_evidence_if_needed() {
  local gate_name="$1"
  local release_preset="${XT_GATE_RELEASE_PRESET:-0}"
  local auto_prepare="${XT_GATE_AUTO_PREPARE_RELEASE_EVIDENCE:-0}"

  if [[ "${release_preset}" != "1" || "${auto_prepare}" != "1" ]]; then
    return 1
  fi

  if [[ "${release_evidence_prepare_attempted}" == "1" ]]; then
    [[ "${release_evidence_prepare_succeeded}" == "1" ]]
    return $?
  fi

  release_evidence_prepare_attempted=1
  local xt_cli_binary=""
  xt_cli_binary="$(resolve_xt_cli_binary || true)"

  if [[ -n "${xt_cli_binary}" ]]; then
    if (cd "${ROOT_DIR}" \
      && "${xt_cli_binary}" --xt-release-evidence-smoke --project-root "${ROOT_DIR}" \
      >"${release_evidence_prepare_log}" 2>&1); then
      release_evidence_prepare_succeeded=1
      note_pass "${gate_name}: auto-prepared release evidence via XTerminal smoke (${release_evidence_prepare_log})"
      return 0
    fi
  else
    if (cd "${ROOT_DIR}" \
      && swift run XTerminal --xt-release-evidence-smoke --project-root "${ROOT_DIR}" \
      >"${release_evidence_prepare_log}" 2>&1); then
      release_evidence_prepare_succeeded=1
      note_pass "${gate_name}: auto-prepared release evidence via XTerminal smoke (${release_evidence_prepare_log})"
      return 0
    fi
  fi

  note_warn "${gate_name}: auto-prepare release evidence failed (see ${release_evidence_prepare_log})"
  return 1
}

json_has_non_message_ingress_coverage() {
  local file="$1"
  if [[ ! -f "${file}" ]]; then
    return 1
  fi
  node -e '
const fs = require("fs");
const payload = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const value = Number(payload?.summary?.non_message_ingress_policy_coverage);
process.exit(Number.isFinite(value) && value >= 1 ? 0 : 1);
' "${file}" >/dev/null 2>&1
}

check_pattern_fixed() {
  local file="$1"
  local pattern="$2"
  local gate_name="$3"
  local check_name="$4"

  if [[ ! -f "${file}" ]]; then
    note_fail "${gate_name}: missing file for ${check_name} (${file})"
    return 1
  fi

  if rg -q --fixed-strings "${pattern}" "${file}"; then
    note_pass "${gate_name}: ${check_name}"
    return 0
  fi

  note_fail "${gate_name}: ${check_name} missing pattern ${pattern}"
  return 1
}

check_pattern_regex() {
  local file="$1"
  local pattern="$2"
  local gate_name="$3"
  local check_name="$4"

  if [[ ! -f "${file}" ]]; then
    note_fail "${gate_name}: missing file for ${check_name} (${file})"
    return 1
  fi

  if rg -q -e "${pattern}" "${file}"; then
    note_pass "${gate_name}: ${check_name}"
    return 0
  fi

  note_fail "${gate_name}: ${check_name} missing regex ${pattern}"
  return 1
}

run_gate_g0() {
  local gate_name="XT-G0 / Contract Freeze"
  local misplaced=()
  while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    if [[ "${file}" != work-orders/* ]]; then
      misplaced+=("${file}")
    fi
  done < <(cd "${ROOT_DIR}" && rg --files -g "*.md" | rg -i "xt-w[0-9]+-[a-z0-9-]+\\.md$")

  if (( ${#misplaced[@]} > 0 )); then
    note_fail "${gate_name}: found XT work-orders outside work-orders/: ${misplaced[*]}"
  else
    note_pass "${gate_name}: all XT work-orders are under work-orders/"
  fi

  local missing_index=()
  while IFS= read -r wo; do
    [[ -z "${wo}" ]] && continue
    local name
    name="$(basename "${wo}")"
    if ! rg -Fq "${name}" "${ROOT_DIR}/work-orders/README.md"; then
      missing_index+=("${name}")
    fi
  done < <(cd "${ROOT_DIR}" && rg --files -g "work-orders/xt-w*.md")

  if (( ${#missing_index[@]} > 0 )); then
    note_fail "${gate_name}: work-orders/README.md missing index entries: ${missing_index[*]}"
  else
    note_pass "${gate_name}: work-orders/README.md indexes all xt-w docs"
  fi
}

run_gate_g1() {
  local gate_name="XT-G1 / Correctness"
  local xt_cli_binary=""
  xt_cli_binary="$(resolve_xt_cli_binary || true)"
  if [[ "${XT_GATE_SKIP_BUILD:-0}" == "1" ]]; then
    note_warn "${gate_name}: skipped by XT_GATE_SKIP_BUILD=1"
    return
  fi

  if [[ "${MODE}" == "baseline" ]] && [[ -n "${xt_cli_binary}" ]] && is_xt_cli_binary_fresh "${xt_cli_binary}"; then
    note_pass "${gate_name}: prebuilt XTerminal binary is fresh (${xt_cli_binary})"
    return
  fi

  if (cd "${ROOT_DIR}" && swift build >/tmp/xt_gate_swift_build.log 2>&1); then
    note_pass "${gate_name}: swift build passed"
  else
    if rg -q "Operation not permitted|sandbox_apply: Operation not permitted" /tmp/xt_gate_swift_build.log; then
      if [[ -n "${xt_cli_binary}" ]] && is_xt_cli_binary_fresh "${xt_cli_binary}"; then
        note_pass "${gate_name}: swift build blocked by sandbox, using fresh prebuilt binary (${xt_cli_binary})"
        return
      fi
      if [[ "${MODE}" == "strict" ]]; then
        note_fail "${gate_name}: swift build hit sandbox restriction in strict mode (see /tmp/xt_gate_swift_build.log)"
      else
        note_warn "${gate_name}: swift build hit local sandbox restriction (baseline mode allows this)"
      fi
    else
      note_fail "${gate_name}: swift build failed (see /tmp/xt_gate_swift_build.log)"
    fi
  fi
}

require_pattern() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if rg -q --fixed-strings "${pattern}" "${file}"; then
    note_pass "${label}: ${pattern}"
  else
    note_fail "${label}: missing pattern ${pattern}"
  fi
}

require_external_pattern() {
  local file="$1"
  local pattern="$2"
  local gate_name="$3"
  local check_name="$4"

  if [[ ! -f "${file}" ]]; then
    if [[ "${MODE}" == "strict" ]]; then
      note_fail "${gate_name}: missing external file for ${check_name} (${file})"
    else
      note_warn "${gate_name}: external file missing for ${check_name} (${file})"
    fi
    return
  fi

  if rg -q --fixed-strings "${pattern}" "${file}"; then
    note_pass "${gate_name}: ${check_name}"
  else
    note_fail "${gate_name}: ${check_name} missing pattern ${pattern}"
  fi
}

run_gate_g2() {
  local gate_name="XT-G2 / Security"
  local tool_exec="${ROOT_DIR}/Sources/Tools/ToolExecutor.swift"
  local chat_model="${ROOT_DIR}/Sources/Chat/ChatSessionModel.swift"
  local tool_protocol="${ROOT_DIR}/Sources/Tools/ToolProtocol.swift"
  local xt_parallel_doc="${ROOT_DIR}/work-orders/xterminal-parallel-work-orders-v1.md"

  require_pattern "${tool_exec}" "high_risk_grant_missing" "${gate_name}"
  require_pattern "${tool_exec}" "high_risk_grant_invalid" "${gate_name}"
  require_pattern "${tool_exec}" "high_risk_grant_expired" "${gate_name}"
  require_pattern "${tool_exec}" "high_risk_bridge_disabled" "${gate_name}"
  require_pattern "${tool_exec}" "gateHighRiskWebFetch(call: call, projectRoot: projectRoot)" "${gate_name}"
  require_pattern "${tool_exec}" "high_risk_denied (code=" "${gate_name}"

  require_pattern "${chat_model}" "/grant status" "${gate_name}"
  require_pattern "${chat_model}" "/grant scan" "${gate_name}"
  require_pattern "${chat_model}" "/grant selftest" "${gate_name}"

  require_pattern "${tool_protocol}" "web_fetch {url, grant_id" "${gate_name}"

  local crk_static_ok=1
  if ! check_pattern_fixed "${xt_parallel_doc}" "pre-auth body/key cap" "${gate_name}" "CRK-W1-08 pre-auth cap contract"; then
    crk_static_ok=0
  fi
  if ! check_pattern_fixed "${xt_parallel_doc}" "WS unauthorized flood breaker" "${gate_name}" "CRK-W1-08 flood breaker contract"; then
    crk_static_ok=0
  fi
  if ! check_pattern_fixed "${xt_parallel_doc}" "非消息入口" "${gate_name}" "non-message ingress auth parity contract"; then
    crk_static_ok=0
  fi
  if ! check_pattern_fixed "${xt_parallel_doc}" "reaction/pin/member/webhook" "${gate_name}" "non-message ingress event coverage symbols"; then
    crk_static_ok=0
  fi

  if (( crk_static_ok == 0 )); then
    mark_status_fail coverage_crk_w1_08_status
    mark_status_fail coverage_xt_w3_08_status
  fi
}

run_gate_g3() {
  local gate_name="XT-G3 / Performance"
  local metrics_file="${XT_GATE_METRICS_FILE:-${ROOT_DIR}/.axcoder/metrics/xt-kpi-latest.json}"
  if [[ -f "${metrics_file}" ]]; then
    note_pass "${gate_name}: metrics file found (${metrics_file})"
    return
  fi

  if [[ "${MODE}" == "strict" ]]; then
    note_fail "${gate_name}: missing metrics file (${metrics_file}) in strict mode"
  else
    note_warn "${gate_name}: metrics file not found yet (baseline mode allows this)"
  fi
}

run_gate_split_audit_contract() {
  local gate_name="XT-W2-09/XT-W2-11 / Split Audit Contract"

  if [[ "${XT_GATE_SKIP_SPLIT_AUDIT_CONTRACT:-0}" == "1" ]]; then
    note_warn "${gate_name}: skipped by XT_GATE_SKIP_SPLIT_AUDIT_CONTRACT=1"
    return
  fi

  local checker="${ROOT_DIR}/scripts/check_split_audit_fixture_contract.js"
  local valid_fixture="${XT_SPLIT_AUDIT_FIXTURE:-${ROOT_DIR}/scripts/fixtures/split_audit_payload_events.sample.json}"
  local invalid_fixture="${XT_SPLIT_AUDIT_INVALID_FIXTURE:-${ROOT_DIR}/scripts/fixtures/split_audit_payload_events.invalid.sample.json}"
  local report_json="${XT_SPLIT_AUDIT_CONTRACT_REPORT:-${REPORT_DIR}/split-audit-contract-report.json}"
  coverage_split_audit_contract_report_path="${report_json}"

  if [[ ! -f "${checker}" ]]; then
    if [[ "${MODE}" == "strict" ]]; then
      note_fail "${gate_name}: checker script missing (${checker})"
    else
      note_warn "${gate_name}: checker script missing (${checker})"
    fi
    return
  fi

  if [[ ! -f "${valid_fixture}" ]]; then
    if [[ "${MODE}" == "strict" ]]; then
      note_fail "${gate_name}: valid fixture missing (${valid_fixture})"
    else
      note_warn "${gate_name}: valid fixture missing (${valid_fixture})"
    fi
    return
  fi

  if node "${checker}" --fixture "${valid_fixture}" --out-json "${report_json}" >/tmp/xt_gate_split_audit_valid.log 2>&1; then
    note_pass "${gate_name}: valid fixture contract passed (${valid_fixture})"
  else
    note_fail "${gate_name}: valid fixture contract failed (see /tmp/xt_gate_split_audit_valid.log)"
  fi

  if [[ -f "${report_json}" ]]; then
    local split_summary_line=""
    split_summary_line="$(
      node -e '
const fs = require("fs");
const path = process.argv[1];
try {
  const doc = JSON.parse(fs.readFileSync(path, "utf8"));
  const summary = (((doc || {}).summary || {}).split_overridden) || {};
  const values = [
    summary.event_count ?? "",
    summary.override_count_total ?? "",
    summary.blocking_issue_total ?? "",
    summary.high_risk_hard_to_soft_confirmed_total ?? "",
    summary.replay_event_count ?? ""
  ];
  process.stdout.write(values.join("\t"));
} catch (_) {
  process.stdout.write("");
}
' "${report_json}"
    )"

    if [[ -n "${split_summary_line}" ]]; then
      local parsed_overridden_events=""
      local parsed_override_total=""
      local parsed_blocking_total=""
      local parsed_high_risk_confirmed_total=""
      local parsed_replay_events=""
      IFS=$'\t' read -r \
        parsed_overridden_events \
        parsed_override_total \
        parsed_blocking_total \
        parsed_high_risk_confirmed_total \
        parsed_replay_events <<< "${split_summary_line}"

      coverage_split_audit_overridden_events="${parsed_overridden_events:-0}"
      coverage_split_audit_override_total="${parsed_override_total:-0}"
      coverage_split_audit_blocking_total="${parsed_blocking_total:-0}"
      coverage_split_audit_high_risk_confirmed_total="${parsed_high_risk_confirmed_total:-0}"
      coverage_split_audit_replay_events="${parsed_replay_events:-0}"
    fi
  fi

  if [[ ! -f "${invalid_fixture}" ]]; then
    if [[ "${MODE}" == "strict" ]]; then
      note_fail "${gate_name}: invalid fixture missing (${invalid_fixture})"
    else
      note_warn "${gate_name}: invalid fixture missing (${invalid_fixture}); negative check skipped"
    fi
    return
  fi

  if node "${checker}" --fixture "${invalid_fixture}" >/tmp/xt_gate_split_audit_invalid.log 2>&1; then
    note_fail "${gate_name}: invalid fixture unexpectedly passed (${invalid_fixture})"
  else
    if rg -q --fixed-strings "fixture invalid" /tmp/xt_gate_split_audit_invalid.log; then
      note_pass "${gate_name}: invalid fixture rejected as expected (${invalid_fixture})"
    else
      note_fail "${gate_name}: invalid fixture check failed unexpectedly (see /tmp/xt_gate_split_audit_invalid.log)"
    fi
  fi
}

run_gate_split_flow_contract() {
  local gate_name="XT-W2-09/XT-W2-11 / Split Flow Contract"
  local release_preset="${XT_GATE_RELEASE_PRESET:-0}"

  if [[ "${XT_GATE_SKIP_SPLIT_FLOW_CONTRACT:-0}" == "1" ]]; then
    note_warn "${gate_name}: skipped by XT_GATE_SKIP_SPLIT_FLOW_CONTRACT=1"
    return
  fi

  if [[ "${release_preset}" != "0" && "${release_preset}" != "1" ]]; then
    note_fail "${gate_name}: invalid XT_GATE_RELEASE_PRESET=${release_preset} (expected 0|1)"
    return
  fi

  local checker="${ROOT_DIR}/scripts/check_split_flow_contract.js"
  local report_json="${XT_SPLIT_FLOW_CONTRACT_REPORT:-${REPORT_DIR}/split-flow-contract-report.json}"
  coverage_split_flow_contract_report_path="${report_json}"

  if [[ ! -f "${checker}" ]]; then
    if [[ "${MODE}" == "strict" ]]; then
      note_fail "${gate_name}: checker script missing (${checker})"
    else
      note_warn "${gate_name}: checker script missing (${checker})"
    fi
    return
  fi

  if node "${checker}" --out-json "${report_json}" >/tmp/xt_gate_split_flow_contract.log 2>&1; then
    note_pass "${gate_name}: split flow contract check passed (${report_json})"
  else
    note_fail "${gate_name}: split flow contract check failed (see /tmp/xt_gate_split_flow_contract.log)"
  fi

  if [[ -f "${report_json}" ]]; then
    local split_flow_summary_line=""
    split_flow_summary_line="$(
      node -e '
const fs = require("fs");
const path = process.argv[1];
try {
  const doc = JSON.parse(fs.readFileSync(path, "utf8"));
  const summary = (doc && doc.summary) || {};
  const values = [
    summary.snapshot_schema ?? "",
    summary.snapshot_version ?? "",
    summary.state_machine_version ?? ""
  ];
  process.stdout.write(values.join("\t"));
} catch (_) {
  process.stdout.write("");
}
' "${report_json}"
    )"

    if [[ -n "${split_flow_summary_line}" ]]; then
      local parsed_snapshot_schema=""
      local parsed_snapshot_version=""
      local parsed_state_machine_version=""
      IFS=$'\t' read -r \
        parsed_snapshot_schema \
        parsed_snapshot_version \
        parsed_state_machine_version <<< "${split_flow_summary_line}"

      coverage_split_flow_snapshot_schema="${parsed_snapshot_schema:-unknown}"
      coverage_split_flow_snapshot_version="${parsed_snapshot_version:-unknown}"
      coverage_split_flow_state_machine_version="${parsed_state_machine_version:-unknown}"
    fi
  fi

  local fixture_checker="${ROOT_DIR}/scripts/check_split_flow_snapshot_fixture_contract.js"
  local fixture_path="${XT_SPLIT_FLOW_FIXTURE:-${ROOT_DIR}/scripts/fixtures/split_flow_snapshot.sample.json}"
  local fixture_report_json="${XT_SPLIT_FLOW_FIXTURE_CONTRACT_REPORT:-${REPORT_DIR}/split-flow-fixture-contract-report.json}"
  coverage_split_flow_fixture_contract_report_path="${fixture_report_json}"

  if [[ ! -f "${fixture_checker}" ]]; then
    if [[ "${MODE}" == "strict" ]]; then
      note_fail "${gate_name}: split-flow fixture checker missing (${fixture_checker})"
    else
      note_warn "${gate_name}: split-flow fixture checker missing (${fixture_checker})"
    fi
    return
  fi

  if [[ ! -f "${fixture_path}" ]]; then
    if [[ "${MODE}" == "strict" ]]; then
      note_fail "${gate_name}: split-flow fixture missing (${fixture_path})"
    else
      note_warn "${gate_name}: split-flow fixture missing (${fixture_path})"
    fi
    return
  fi

  if node "${fixture_checker}" --fixture "${fixture_path}" --out-json "${fixture_report_json}" >/tmp/xt_gate_split_flow_fixture_contract.log 2>&1; then
    note_pass "${gate_name}: split-flow snapshot fixture contract passed (${fixture_path})"
  else
    note_fail "${gate_name}: split-flow snapshot fixture contract failed (see /tmp/xt_gate_split_flow_fixture_contract.log)"
  fi

  if [[ -f "${fixture_report_json}" ]]; then
    local split_flow_fixture_summary_line=""
    split_flow_fixture_summary_line="$(
      node -e '
const fs = require("fs");
const path = process.argv[1];
try {
  const doc = JSON.parse(fs.readFileSync(path, "utf8"));
  const summary = (doc && doc.summary) || {};
  const values = [summary.snapshot_count ?? ""];
  process.stdout.write(values.join("\t"));
} catch (_) {
  process.stdout.write("");
}
' "${fixture_report_json}"
    )"

    if [[ -n "${split_flow_fixture_summary_line}" ]]; then
      local parsed_snapshot_count=""
      IFS=$'\t' read -r parsed_snapshot_count <<< "${split_flow_fixture_summary_line}"
      coverage_split_flow_fixture_snapshot_count="${parsed_snapshot_count:-0}"
    fi
  fi

  coverage_split_flow_runtime_regression_status="skipped"

  local runtime_regression_default="0"
  if [[ "${MODE}" == "strict" || "${release_preset}" == "1" ]]; then
    runtime_regression_default="1"
  fi

  local runtime_regression_enabled="${XT_GATE_SPLIT_FLOW_RUNTIME_REGRESSION:-${runtime_regression_default}}"
  if [[ "${runtime_regression_enabled}" != "0" && "${runtime_regression_enabled}" != "1" ]]; then
    note_fail "${gate_name}: invalid XT_GATE_SPLIT_FLOW_RUNTIME_REGRESSION=${runtime_regression_enabled} (expected 0|1)"
    return
  fi

  if [[ "${release_preset}" == "1" && "${runtime_regression_enabled}" != "1" ]]; then
    note_fail "${gate_name}: release preset requires runtime regression (set XT_GATE_SPLIT_FLOW_RUNTIME_REGRESSION=1)"
    coverage_split_flow_runtime_regression_status="fail"
    return
  fi

  if [[ -z "${XT_GATE_SPLIT_FLOW_RUNTIME_REGRESSION+x}" && "${runtime_regression_enabled}" == "1" ]]; then
    note_pass "${gate_name}: runtime regression enabled by default (mode=${MODE}, release_preset=${release_preset})"
  fi

  if [[ "${runtime_regression_enabled}" == "1" ]]; then
    local runtime_generate_default="1"
    local runtime_generate="${XT_GATE_SPLIT_FLOW_GENERATE_RUNTIME_FIXTURE:-${runtime_generate_default}}"
    if [[ "${runtime_generate}" != "0" && "${runtime_generate}" != "1" ]]; then
      note_fail "${gate_name}: invalid XT_GATE_SPLIT_FLOW_GENERATE_RUNTIME_FIXTURE=${runtime_generate} (expected 0|1)"
      return
    fi

    local runtime_fixture="${XT_SPLIT_FLOW_RUNTIME_FIXTURE:-${REPORT_DIR}/split_flow_snapshot.runtime.json}"
    local runtime_regression_checker="${ROOT_DIR}/scripts/check_split_flow_snapshot_generation_regression.js"
    local runtime_generator="${ROOT_DIR}/scripts/generate_split_flow_snapshot_fixture.js"
    coverage_split_flow_runtime_fixture_path="${runtime_fixture}"

    if [[ "${runtime_generate}" == "1" ]]; then
      if [[ ! -f "${runtime_generator}" ]]; then
        note_fail "${gate_name}: split-flow runtime generator missing (${runtime_generator})"
        coverage_split_flow_runtime_regression_status="fail"
        return
      fi
      if node "${runtime_generator}" --project-root "${ROOT_DIR}" --out-json "${runtime_fixture}" >/tmp/xt_gate_split_flow_runtime_generate.log 2>&1; then
        note_pass "${gate_name}: generated split-flow runtime fixture (${runtime_fixture})"
      else
        note_fail "${gate_name}: failed to generate split-flow runtime fixture (see /tmp/xt_gate_split_flow_runtime_generate.log)"
        coverage_split_flow_runtime_regression_status="fail"
        return
      fi
    fi

    if [[ ! -f "${runtime_fixture}" ]]; then
      if [[ "${MODE}" == "strict" ]]; then
        note_fail "${gate_name}: runtime fixture missing for regression (${runtime_fixture})"
        coverage_split_flow_runtime_regression_status="fail"
      else
        note_warn "${gate_name}: runtime fixture missing for regression (${runtime_fixture}); baseline allows skip"
        coverage_split_flow_runtime_regression_status="missing"
      fi
      return
    fi

    if [[ ! -f "${runtime_regression_checker}" ]]; then
      note_fail "${gate_name}: runtime regression checker missing (${runtime_regression_checker})"
      coverage_split_flow_runtime_regression_status="fail"
      return
    fi

    if node "${runtime_regression_checker}" --generated "${runtime_fixture}" --sample "${fixture_path}" >/tmp/xt_gate_split_flow_runtime_regression.log 2>&1; then
      note_pass "${gate_name}: runtime fixture regression matched canonical sample"
      coverage_split_flow_runtime_regression_status="pass"
    else
      note_fail "${gate_name}: runtime fixture regression mismatch (see /tmp/xt_gate_split_flow_runtime_regression.log)"
      coverage_split_flow_runtime_regression_status="fail"
    fi
  fi
}

run_gate_xt_ready_contract() {
  local gate_name="XT-Ready / Hub->X-Terminal Contract"

  if [[ "${XT_GATE_SKIP_XT_READY_CONTRACT:-0}" == "1" ]]; then
    note_warn "${gate_name}: skipped by XT_GATE_SKIP_XT_READY_CONTRACT=1"
    return
  fi

  local xt_ready_doc="${ROOT_DIR}/../docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md"
  local m3_doc="${ROOT_DIR}/../docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md"
  local exec_plan_doc="${ROOT_DIR}/../docs/memory-new/xhub-memory-v3-execution-plan.md"
  local working_index_doc="${ROOT_DIR}/../docs/WORKING_INDEX.md"
  local x_memory_doc="${ROOT_DIR}/../X_MEMORY.md"
  local xt_parallel_doc="${ROOT_DIR}/work-orders/xterminal-parallel-work-orders-v1.md"
  local xt_supervisor_doc="${ROOT_DIR}/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md"

  require_external_pattern "${xt_ready_doc}" "XT-Ready-G0" "${gate_name}" "xt-ready gate doc has G0"
  require_external_pattern "${xt_ready_doc}" "XT-Ready-G5" "${gate_name}" "xt-ready gate doc has G5"
  require_external_pattern "${xt_ready_doc}" "grant_pending" "${gate_name}" "xt-ready doc includes grant_pending"
  require_external_pattern "${xt_ready_doc}" "awaiting_instruction" "${gate_name}" "xt-ready doc includes awaiting_instruction"
  require_external_pattern "${xt_ready_doc}" "runtime_error" "${gate_name}" "xt-ready doc includes runtime_error"

  require_external_pattern "${m3_doc}" "Gate-M3-XT-Ready" "${gate_name}" "M3 work-orders bind XT-Ready gate"
  require_external_pattern "${exec_plan_doc}" "XT-Ready-G0..G5" "${gate_name}" "execution plan DoD binds XT-Ready"
  require_external_pattern "${working_index_doc}" "xhub-hub-to-xterminal-capability-gate-v1.md" "${gate_name}" "global working index links XT-Ready doc"
  require_external_pattern "${x_memory_doc}" "xhub-hub-to-xterminal-capability-gate-v1.md" "${gate_name}" "X_MEMORY links XT-Ready doc"

  require_pattern "${xt_parallel_doc}" "xhub-hub-to-xterminal-capability-gate-v1.md" "${gate_name}"
  require_pattern "${xt_supervisor_doc}" "XT-Ready-G0..G5" "${gate_name}"
}

run_gate_xt_ready_executable() {
  local gate_name="XT-Ready / Executable Gate"

  if [[ "${XT_GATE_SKIP_XT_READY_EXECUTABLE:-0}" == "1" ]]; then
    note_warn "${gate_name}: skipped by XT_GATE_SKIP_XT_READY_EXECUTABLE=1"
    return
  fi

  local checker="${ROOT_DIR}/../scripts/m3_check_xt_ready_gate.js"
  local report_doc="${ROOT_DIR}/../build/xt_ready_gate_doc_report.json"
  local report_e2e="${ROOT_DIR}/../build/xt_ready_gate_e2e_report.json"
  local evidence="${XT_READY_E2E_EVIDENCE:-${ROOT_DIR}/../build/xt_ready_e2e_evidence.json}"
  local generator="${ROOT_DIR}/../scripts/m3_generate_xt_ready_e2e_evidence.js"
  local runtime_events="${XT_READY_INCIDENT_EVENTS_JSON:-${ROOT_DIR}/.axcoder/reports/xt_ready_incident_events.runtime.json}"
  local runtime_events_from_sample="${ROOT_DIR}/../build/xt_ready_incident_events.from_sample.json"
  local runtime_events_fixture="${ROOT_DIR}/../scripts/fixtures/xt_ready_incident_events.sample.json"
  local generated_evidence="${XT_READY_RUNTIME_E2E_EVIDENCE:-${ROOT_DIR}/../build/xt_ready_e2e_evidence.runtime.generated.json}"
  local require_runtime_incident_evidence="${XT_READY_REQUIRE_RUNTIME_INCIDENT_EVIDENCE:-0}"
  local forbid_fixture_runtime_evidence="${XT_READY_FORBID_FIXTURE_RUNTIME_EVIDENCE:-0}"
  local release_preset="${XT_GATE_RELEASE_PRESET:-0}"
  local xt_ready_doc="${ROOT_DIR}/../docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md"
  local m3_doc="${ROOT_DIR}/../docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md"
  local exec_plan_doc="${ROOT_DIR}/../docs/memory-new/xhub-memory-v3-execution-plan.md"
  local working_index_doc="${ROOT_DIR}/../docs/WORKING_INDEX.md"
  local x_memory_doc="${ROOT_DIR}/../X_MEMORY.md"
  local xt_parallel_doc="${ROOT_DIR}/work-orders/xterminal-parallel-work-orders-v1.md"
  local xt_supervisor_doc="${ROOT_DIR}/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md"
  local generated_from_runtime=0
  local runtime_events_candidate="${runtime_events}"
  local -a runtime_events_candidates=()

  prepare_release_evidence_if_needed "${gate_name}" || true

  if [[ "${release_preset}" != "0" && "${release_preset}" != "1" ]]; then
    note_fail "${gate_name}: invalid XT_GATE_RELEASE_PRESET=${release_preset} (expected 0|1)"
    return
  fi
  if [[ "${release_preset}" == "1" ]]; then
    if [[ -z "${XT_READY_REQUIRE_RUNTIME_INCIDENT_EVIDENCE+x}" ]]; then
      require_runtime_incident_evidence=1
    fi
    if [[ -z "${XT_READY_FORBID_FIXTURE_RUNTIME_EVIDENCE+x}" ]]; then
      forbid_fixture_runtime_evidence=1
    fi
    note_pass "${gate_name}: release preset enabled (require_runtime=${require_runtime_incident_evidence}, forbid_fixture_runtime=${forbid_fixture_runtime_evidence})"
  fi

  if [[ ! -f "${checker}" ]]; then
    if [[ "${MODE}" == "strict" ]]; then
      note_fail "${gate_name}: checker script missing (${checker})"
    else
      note_warn "${gate_name}: checker script missing (${checker})"
    fi
    return
  fi

  if node "${checker}" \
    --xt-ready-doc "${xt_ready_doc}" \
    --m3-doc "${m3_doc}" \
    --exec-plan-doc "${exec_plan_doc}" \
    --working-index-doc "${working_index_doc}" \
    --x-memory-doc "${x_memory_doc}" \
    --xt-parallel-doc "${xt_parallel_doc}" \
    --xt-supervisor-doc "${xt_supervisor_doc}" \
    --out-json "${report_doc}" >/tmp/xt_gate_xt_ready_doc.log 2>&1; then
    note_pass "${gate_name}: doc checker passed (${report_doc})"
  else
    note_fail "${gate_name}: doc checker failed (see /tmp/xt_gate_xt_ready_doc.log)"
  fi

  if [[ "${require_runtime_incident_evidence}" != "0" && "${require_runtime_incident_evidence}" != "1" ]]; then
    note_fail "${gate_name}: invalid XT_READY_REQUIRE_RUNTIME_INCIDENT_EVIDENCE=${require_runtime_incident_evidence} (expected 0|1)"
  elif [[ "${forbid_fixture_runtime_evidence}" != "0" && "${forbid_fixture_runtime_evidence}" != "1" ]]; then
    note_fail "${gate_name}: invalid XT_READY_FORBID_FIXTURE_RUNTIME_EVIDENCE=${forbid_fixture_runtime_evidence} (expected 0|1)"
  elif [[ "${require_runtime_incident_evidence}" != "1" ]]; then
    if [[ "${forbid_fixture_runtime_evidence}" == "1" ]]; then
      runtime_events_candidate="$(resolve_first_existing_file "${runtime_events}")"
    else
      runtime_events_candidate="$(resolve_first_existing_file "${runtime_events}" "${runtime_events_from_sample}" "${runtime_events_fixture}")"
    fi
    if [[ "${forbid_fixture_runtime_evidence}" == "1" ]]; then
      if [[ -n "${runtime_events_candidate}" ]]; then
        runtime_events_candidates=("${runtime_events_candidate}")
      fi
    else
      local candidate_path=""
      for candidate_path in "${runtime_events}" "${runtime_events_from_sample}" "${runtime_events_fixture}"; do
        if [[ -f "${candidate_path}" ]]; then
          runtime_events_candidates+=("${candidate_path}")
        fi
      done
    fi
  fi

  if [[ "${require_runtime_incident_evidence}" != "0" && "${require_runtime_incident_evidence}" != "1" ]]; then
    :
  elif [[ "${forbid_fixture_runtime_evidence}" != "0" && "${forbid_fixture_runtime_evidence}" != "1" ]]; then
    :
  elif [[ "${require_runtime_incident_evidence}" == "1" ]]; then
    if [[ ! -f "${generator}" ]]; then
      note_fail "${gate_name}: required runtime incident evidence generator missing (${generator})"
    elif [[ ! -f "${runtime_events}" ]]; then
      note_fail "${gate_name}: required runtime incident events file missing (${runtime_events})"
    elif [[ "${forbid_fixture_runtime_evidence}" == "1" ]] && is_fixture_path "${runtime_events}"; then
      note_fail "${gate_name}: required runtime incident events cannot use fixture path (${runtime_events})"
    elif node "${generator}" \
      --strict \
      --events-json "${runtime_events}" \
      --out-json "${generated_evidence}" >/tmp/xt_gate_xt_ready_generate.log 2>&1; then
      evidence="${generated_evidence}"
      generated_from_runtime=1
      note_pass "${gate_name}: required runtime incident evidence generated (${runtime_events})"
    else
      note_fail "${gate_name}: required runtime incident evidence generation failed (see /tmp/xt_gate_xt_ready_generate.log)"
    fi
  elif [[ ! -f "${evidence}" && -f "${generator}" && ${#runtime_events_candidates[@]} -gt 0 ]]; then
    local generated_ok=0
    local generated_candidate=""
    local candidate_path=""
    for candidate_path in "${runtime_events_candidates[@]}"; do
      if node "${generator}" \
        --strict \
        --events-json "${candidate_path}" \
        --out-json "${generated_evidence}" >/tmp/xt_gate_xt_ready_generate.log 2>&1; then
        generated_ok=1
        generated_candidate="${candidate_path}"
        break
      fi
    done
    if [[ "${generated_ok}" == "1" ]]; then
      evidence="${generated_evidence}"
      generated_from_runtime=1
      note_pass "${gate_name}: generated strict e2e evidence from runtime incidents (${generated_candidate})"
    else
      if [[ "${MODE}" == "strict" ]]; then
        note_fail "${gate_name}: runtime incident evidence generation failed (see /tmp/xt_gate_xt_ready_generate.log)"
      else
        note_warn "${gate_name}: runtime incident evidence generation failed (baseline allows fallback; see /tmp/xt_gate_xt_ready_generate.log)"
      fi
    fi
  elif [[ "${release_preset}" != "1" && -f "${evidence}" && -f "${runtime_events_candidate}" && -f "${generator}" ]] \
    && ! json_has_non_message_ingress_coverage "${evidence}"; then
    if [[ "${forbid_fixture_runtime_evidence}" == "1" ]] && is_fixture_path "${runtime_events_candidate}"; then
      note_warn "${gate_name}: fallback regeneration skipped because fixture runtime evidence is forbidden (${runtime_events_candidate})"
    else
      local regenerated_ok=0
      local regenerated_candidate=""
      local candidate_path=""
      if [[ ${#runtime_events_candidates[@]} -eq 0 && -f "${runtime_events_candidate}" ]]; then
        runtime_events_candidates=("${runtime_events_candidate}")
      fi
      for candidate_path in "${runtime_events_candidates[@]}"; do
        if node "${generator}" \
          --strict \
          --events-json "${candidate_path}" \
          --out-json "${generated_evidence}" >/tmp/xt_gate_xt_ready_generate.log 2>&1; then
          regenerated_ok=1
          regenerated_candidate="${candidate_path}"
          break
        fi
      done
      if [[ "${regenerated_ok}" == "1" ]]; then
        evidence="${generated_evidence}"
        generated_from_runtime=1
        if is_fixture_path "${regenerated_candidate}"; then
          note_pass "${gate_name}: regenerated e2e evidence from fixture-derived incidents to restore ingress coverage (${regenerated_candidate})"
        else
          note_pass "${gate_name}: regenerated e2e evidence from runtime incidents to restore ingress coverage (${regenerated_candidate})"
        fi
      else
        note_warn "${gate_name}: failed to regenerate e2e evidence fallback (see /tmp/xt_gate_xt_ready_generate.log)"
      fi
    fi
  fi

  if [[ -f "${evidence}" ]]; then
    if node "${checker}" \
      --xt-ready-doc "${xt_ready_doc}" \
      --m3-doc "${m3_doc}" \
      --exec-plan-doc "${exec_plan_doc}" \
      --working-index-doc "${working_index_doc}" \
      --x-memory-doc "${x_memory_doc}" \
      --xt-parallel-doc "${xt_parallel_doc}" \
      --xt-supervisor-doc "${xt_supervisor_doc}" \
      --strict-e2e \
      --e2e-evidence "${evidence}" \
      --out-json "${report_e2e}" >/tmp/xt_gate_xt_ready_e2e.log 2>&1; then
      if (( generated_from_runtime == 1 )); then
        if [[ "${require_runtime_incident_evidence}" == "1" ]]; then
          note_pass "${gate_name}: strict e2e checker passed with required runtime-generated evidence (${report_e2e})"
        else
          note_pass "${gate_name}: strict e2e checker passed with runtime-generated evidence (${report_e2e})"
        fi
      else
        note_pass "${gate_name}: strict e2e checker passed (${report_e2e})"
      fi
    else
      note_fail "${gate_name}: strict e2e checker failed (see /tmp/xt_gate_xt_ready_e2e.log)"
    fi
  else
    if [[ "${MODE}" == "strict" ]]; then
      note_fail "${gate_name}: missing e2e evidence in strict mode (${evidence})"
    else
      note_warn "${gate_name}: e2e evidence not found yet (${evidence}); run strict checker after e2e is ready"
    fi
  fi
}

run_gate_supervisor_doctor() {
  local gate_name="XT-G2/XT-G5 / Supervisor Doctor"
  local report_file="${ROOT_DIR}/.axcoder/reports/supervisor_doctor_report.json"
  local refresh_log="/tmp/xt_gate_supervisor_doctor_refresh.log"
  local default_secrets_plan="${ROOT_DIR}/scripts/fixtures/secrets_apply_dry_run.baseline.sample.json"
  local runtime_secrets_plan="${ROOT_DIR}/.axcoder/secrets/secrets_apply_dry_run.json"
  local refresh_used_baseline_fixture=0
  local release_preset="${XT_GATE_RELEASE_PRESET:-0}"
  local xt_cli_binary=""
  xt_cli_binary="$(resolve_xt_cli_binary || true)"

  prepare_release_evidence_if_needed "${gate_name}" || true

  if [[ "${MODE}" == "baseline" || "${release_preset}" != "1" ]] \
    && [[ -z "${XTERMINAL_SUPERVISOR_SECRETS_DRY_RUN_PLAN:-}" ]] \
    && [[ ! -f "${runtime_secrets_plan}" ]] \
    && [[ -f "${default_secrets_plan}" ]]; then
    refresh_used_baseline_fixture=1
    if [[ -n "${xt_cli_binary}" ]]; then
      if (cd "${ROOT_DIR}" \
        && XTERMINAL_SUPERVISOR_SECRETS_DRY_RUN_PLAN="${default_secrets_plan}" \
        "${xt_cli_binary}" --xt-supervisor-doctor-refresh --project-root "${ROOT_DIR}" \
        >"${refresh_log}" 2>&1); then
        note_pass "${gate_name}: fallback used sample secrets dry-run plan (${default_secrets_plan})"
      else
        note_warn "${gate_name}: doctor refresh with baseline sample plan failed (see ${refresh_log})"
      fi
    else
      if (cd "${ROOT_DIR}" \
        && XTERMINAL_SUPERVISOR_SECRETS_DRY_RUN_PLAN="${default_secrets_plan}" \
        swift run XTerminal --xt-supervisor-doctor-refresh --project-root "${ROOT_DIR}" \
        >"${refresh_log}" 2>&1); then
        note_pass "${gate_name}: fallback used sample secrets dry-run plan (${default_secrets_plan})"
      else
        note_warn "${gate_name}: doctor refresh with baseline sample plan failed (see ${refresh_log})"
      fi
    fi
  else
    if [[ -n "${xt_cli_binary}" ]]; then
      if (cd "${ROOT_DIR}" \
        && "${xt_cli_binary}" --xt-supervisor-doctor-refresh --project-root "${ROOT_DIR}" \
        >"${refresh_log}" 2>&1); then
        note_pass "${gate_name}: doctor report refreshed (${report_file})"
      else
        note_warn "${gate_name}: doctor refresh failed, fallback to existing report (see ${refresh_log})"
      fi
    else
      if (cd "${ROOT_DIR}" \
        && swift run XTerminal --xt-supervisor-doctor-refresh --project-root "${ROOT_DIR}" \
        >"${refresh_log}" 2>&1); then
        note_pass "${gate_name}: doctor report refreshed (${report_file})"
      else
        note_warn "${gate_name}: doctor refresh failed, fallback to existing report (see ${refresh_log})"
      fi
    fi
  fi

  if [[ ! -f "${report_file}" ]]; then
    if [[ "${refresh_used_baseline_fixture}" == "1" ]]; then
      note_fail "${gate_name}: missing doctor report after baseline refresh attempt (${report_file})"
    else
      note_fail "${gate_name}: missing doctor report (${report_file})"
    fi
    return
  fi

  if node -e '
const fs = require("fs");
const reportPath = process.argv[1];
const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
const schema = report.schemaVersion || report.schema_version || "";
if (schema !== "supervisor_doctor.v1") {
  throw new Error(`invalid schema version: ${schema || "(empty)"}`);
}
const summary = (report && typeof report.summary === "object" && report.summary) ? report.summary : {};
const releaseBlockedByMissingReport = Number(summary.releaseBlockedByDoctorWithoutReport ?? summary.release_blocked_by_doctor_without_report ?? NaN);
if (!Number.isFinite(releaseBlockedByMissingReport) || releaseBlockedByMissingReport !== 0) {
  throw new Error(`release_blocked_by_doctor_without_report must be 0, got ${summary.releaseBlockedByDoctorWithoutReport ?? summary.release_blocked_by_doctor_without_report}`);
}
const doctorReportPresent = Number(summary.doctorReportPresent ?? summary.doctor_report_present ?? NaN);
if (!Number.isFinite(doctorReportPresent) || doctorReportPresent !== 1) {
  throw new Error(`doctor_report_present must be 1, got ${summary.doctorReportPresent ?? summary.doctor_report_present}`);
}
const blockingCount = Number(summary.blockingCount ?? summary.blocking_count ?? NaN);
if (!Number.isFinite(blockingCount) || blockingCount < 0) {
  throw new Error(`invalid blocking_count: ${summary.blockingCount ?? summary.blocking_count}`);
}
if (blockingCount > 0 || report.ok === false) {
  throw new Error(`doctor has blocking findings (blocking_count=${blockingCount})`);
}
' "${report_file}" >/tmp/xt_gate_supervisor_doctor.log 2>&1; then
    note_pass "${gate_name}: doctor report present and release-safe (${report_file})"
  else
    if [[ "${MODE}" == "baseline" || "${release_preset}" != "1" ]] \
      && [[ "${refresh_used_baseline_fixture}" == "1" ]] \
      && [[ -f "${refresh_log}" ]] \
      && rg -q "Operation not permitted|not accessible or not writable|Invalid manifest|failed to build module 'Swift'" "${refresh_log}"; then
      note_warn "${gate_name}: doctor refresh blocked by local sandbox/toolchain; baseline keeps warning (see /tmp/xt_gate_supervisor_doctor.log)"
    else
      note_fail "${gate_name}: doctor report check failed (see /tmp/xt_gate_supervisor_doctor.log)"
    fi
  fi
}

run_gate_release_evidence_matrix_regression() {
  local gate_name="XT-Ready / Release Evidence Matrix Regression"
  local enabled="${XT_GATE_VALIDATE_RELEASE_EVIDENCE_MATRIX:-0}"
  local checker="${ROOT_DIR}/scripts/ci/xt_release_evidence_matrix_regression.sh"
  local validator="${ROOT_DIR}/scripts/ci/xt_release_evidence_matrix_log_validator.js"
  local validator_regression="${ROOT_DIR}/scripts/ci/xt_release_evidence_matrix_validator_regression.js"
  local log_file="/tmp/xt_gate_release_evidence_matrix.log"
  local report_log="${REPORT_DIR}/xt-gate-release-evidence-matrix.log"
  local report_summary="${REPORT_DIR}/xt-gate-release-evidence-matrix.summary.json"
  local validate_log="/tmp/xt_gate_release_evidence_matrix_validate.log"
  local log_to_validate="${log_file}"
  local validator_regression_log="/tmp/xt_gate_release_evidence_matrix_validator_regression.log"
  local report_validator_regression_log="${REPORT_DIR}/xt-gate-release-evidence-matrix.validator-regression.log"

  if [[ "${enabled}" != "0" && "${enabled}" != "1" ]]; then
    note_fail "${gate_name}: invalid XT_GATE_VALIDATE_RELEASE_EVIDENCE_MATRIX=${enabled} (expected 0|1)"
    return
  fi

  if [[ "${enabled}" != "1" ]]; then
    return
  fi

  if [[ ! -f "${checker}" ]]; then
    note_fail "${gate_name}: checker script missing (${checker})"
    return
  fi

  if (cd "${ROOT_DIR}" \
    && XT_GATE_VALIDATE_RELEASE_EVIDENCE_MATRIX=0 \
      bash "${checker}" >"${log_file}" 2>&1); then
    note_pass "${gate_name}: regression matrix passed (${log_file})"
  else
    note_fail "${gate_name}: regression matrix failed (see ${log_file})"
  fi

  if [[ -f "${log_file}" ]]; then
    mkdir -p "${REPORT_DIR}"
    if cp "${log_file}" "${report_log}" 2>/dev/null; then
      coverage_release_evidence_matrix_log_path="${report_log}"
      log_to_validate="${report_log}"
      note_pass "${gate_name}: matrix log archived (${report_log})"
    else
      coverage_release_evidence_matrix_log_path="${log_file}"
      note_warn "${gate_name}: failed to archive matrix log; using source path (${log_file})"
    fi
  else
    note_warn "${gate_name}: matrix log missing (${log_file})"
  fi

  if [[ ! -f "${validator}" ]]; then
    note_fail "${gate_name}: validator script missing (${validator})"
    return
  fi

  if node "${validator}" --log "${log_to_validate}" --out-json "${report_summary}" >"${validate_log}" 2>&1; then
    coverage_release_evidence_matrix_summary_path="${report_summary}"
    note_pass "${gate_name}: matrix log schema validated (${report_summary})"
  else
    note_fail "${gate_name}: matrix log schema invalid (see ${validate_log})"
  fi

  if [[ ! -f "${validator_regression}" ]]; then
    note_fail "${gate_name}: validator regression script missing (${validator_regression})"
    return
  fi

  if node "${validator_regression}" >"${validator_regression_log}" 2>&1; then
    note_pass "${gate_name}: validator regression passed (${validator_regression_log})"
  else
    note_fail "${gate_name}: validator regression failed (see ${validator_regression_log})"
  fi

  if [[ -f "${validator_regression_log}" ]]; then
    mkdir -p "${REPORT_DIR}"
    if cp "${validator_regression_log}" "${report_validator_regression_log}" 2>/dev/null; then
      coverage_release_evidence_matrix_validator_regression_log_path="${report_validator_regression_log}"
      note_pass "${gate_name}: validator regression log archived (${report_validator_regression_log})"
    else
      coverage_release_evidence_matrix_validator_regression_log_path="${validator_regression_log}"
      note_warn "${gate_name}: failed to archive validator regression log; using source path (${validator_regression_log})"
    fi
  else
    note_warn "${gate_name}: validator regression log missing (${validator_regression_log})"
  fi
}

run_gate_split_flow_runtime_policy_regression() {
  local gate_name="XT-W2-09/XT-W2-11 / Split Flow Runtime Policy Regression"
  local release_preset="${XT_GATE_RELEASE_PRESET:-0}"
  local enabled_default="0"
  if [[ "${release_preset}" == "1" ]]; then
    enabled_default="1"
  fi
  local enabled="${XT_GATE_VALIDATE_SPLIT_FLOW_RUNTIME_POLICY:-${enabled_default}}"
  local checker="${ROOT_DIR}/scripts/ci/xt_split_flow_runtime_policy_regression.sh"
  local log_file="/tmp/xt_gate_split_flow_runtime_policy.log"
  local report_log="${REPORT_DIR}/xt-gate-split-flow-runtime-policy.log"

  if [[ "${release_preset}" != "0" && "${release_preset}" != "1" ]]; then
    note_fail "${gate_name}: invalid XT_GATE_RELEASE_PRESET=${release_preset} (expected 0|1)"
    coverage_split_flow_runtime_policy_regression_status="fail"
    return
  fi

  if [[ "${enabled}" != "0" && "${enabled}" != "1" ]]; then
    note_fail "${gate_name}: invalid XT_GATE_VALIDATE_SPLIT_FLOW_RUNTIME_POLICY=${enabled} (expected 0|1)"
    coverage_split_flow_runtime_policy_regression_status="fail"
    return
  fi

  if [[ -z "${XT_GATE_VALIDATE_SPLIT_FLOW_RUNTIME_POLICY+x}" && "${enabled}" == "1" ]]; then
    note_pass "${gate_name}: enabled by default (release_preset=${release_preset})"
  fi

  if [[ "${enabled}" != "1" ]]; then
    coverage_split_flow_runtime_policy_regression_status="skipped"
    return
  fi

  if [[ ! -f "${checker}" ]]; then
    note_fail "${gate_name}: checker script missing (${checker})"
    coverage_split_flow_runtime_policy_regression_status="fail"
    return
  fi

  if (cd "${ROOT_DIR}" && bash "${checker}" >"${log_file}" 2>&1); then
    note_pass "${gate_name}: policy regression passed (${log_file})"
    coverage_split_flow_runtime_policy_regression_status="pass"
  else
    note_fail "${gate_name}: policy regression failed (see ${log_file})"
    coverage_split_flow_runtime_policy_regression_status="fail"
  fi

  if [[ -f "${log_file}" ]]; then
    mkdir -p "${REPORT_DIR}"
    if cp "${log_file}" "${report_log}" 2>/dev/null; then
      coverage_split_flow_runtime_policy_regression_log_path="${report_log}"
      note_pass "${gate_name}: policy regression log archived (${report_log})"
    else
      coverage_split_flow_runtime_policy_regression_log_path="${log_file}"
      note_warn "${gate_name}: failed to archive policy regression log; using source path (${log_file})"
    fi
  else
    note_warn "${gate_name}: policy regression log missing (${log_file})"
  fi
}

run_gate_g4() {
  local gate_name="XT-G4 / Reliability"
  local tool_exec="${ROOT_DIR}/Sources/Tools/ToolExecutor.swift"
  local chat_model="${ROOT_DIR}/Sources/Chat/ChatSessionModel.swift"
  local xt_parallel_doc="${ROOT_DIR}/work-orders/xterminal-parallel-work-orders-v1.md"
  local smoke_log="/tmp/xt_gate_grant_smoke.log"
  local xt_cli_binary=""
  xt_cli_binary="$(resolve_xt_cli_binary || true)"

  local smoke_state="pass"
  if [[ -n "${xt_cli_binary}" ]]; then
    if (cd "${ROOT_DIR}" && "${xt_cli_binary}" --xt-grant-smoke >"${smoke_log}" 2>&1); then
      note_pass "${gate_name}: xt-grant-smoke runtime check passed"
    else
      if rg -q "Operation not permitted|sandbox_apply: Operation not permitted" "${smoke_log}"; then
        if [[ "${MODE}" == "strict" ]]; then
          note_fail "${gate_name}: runtime smoke hit sandbox restriction in strict mode (see ${smoke_log})"
          smoke_state="fail"
        else
          note_warn "${gate_name}: runtime smoke hit local sandbox restriction (baseline mode allows this)"
          smoke_state="warn"
        fi
      else
        note_fail "${gate_name}: xt-grant-smoke failed (see ${smoke_log})"
        smoke_state="fail"
      fi
    fi
  elif (cd "${ROOT_DIR}" && swift run XTerminal --xt-grant-smoke >"${smoke_log}" 2>&1); then
    note_pass "${gate_name}: xt-grant-smoke runtime check passed"
  else
    if rg -q "Operation not permitted|sandbox_apply: Operation not permitted" "${smoke_log}"; then
      if [[ "${MODE}" == "strict" ]]; then
        note_fail "${gate_name}: runtime smoke hit sandbox restriction in strict mode (see ${smoke_log})"
        smoke_state="fail"
      else
        note_warn "${gate_name}: runtime smoke hit local sandbox restriction (baseline mode allows this)"
        smoke_state="warn"
      fi
    else
      note_fail "${gate_name}: xt-grant-smoke failed (see ${smoke_log})"
      smoke_state="fail"
    fi
  fi

  local static_ok=1
  if ! check_pattern_fixed "${tool_exec}" "scanHighRiskGrantBypass(" "${gate_name}" "grant bypass scan hook"; then
    static_ok=0
  fi
  if ! check_pattern_fixed "${tool_exec}" "runHighRiskGrantSelfChecks(" "${gate_name}" "grant self-check hook"; then
    static_ok=0
  fi
  if ! check_pattern_fixed "${chat_model}" "performSlashGrantCommand(" "${gate_name}" "slash grant command hook"; then
    static_ok=0
  fi
  if ! check_pattern_fixed "${xt_parallel_doc}" "WS unauthorized flood breaker" "${gate_name}" "CRK-W1-08 flood breaker static contract"; then
    static_ok=0
  fi
  if ! check_pattern_fixed "${xt_parallel_doc}" "reaction/pin/member/webhook" "${gate_name}" "non-message ingress parity static symbol"; then
    static_ok=0
  fi

  if [[ "${smoke_state}" == "pass" && ${static_ok} -eq 1 ]]; then
    note_pass "${gate_name}: xt-grant-smoke + 新增静态检查同时通过"
  elif [[ "${smoke_state}" == "warn" && ${static_ok} -eq 1 && "${MODE}" != "strict" ]]; then
    note_warn "${gate_name}: xt-grant-smoke blocked by local sandbox but static checks passed (baseline mode)"
    mark_status_warn coverage_xt_w3_08_status
  else
    note_fail "${gate_name}: xt-grant-smoke + 新增静态检查未同时通过"
    mark_status_fail coverage_xt_w3_08_status
  fi
}

run_gate_g5() {
  local gate_name="XT-G5 / Release Ready"
  local rollback_script="${XT_ROLLBACK_SCRIPT:-${ROOT_DIR}/scripts/ci/xt_release_rollback_stub.sh}"
  local rollback_verify_report="${XT_ROLLBACK_VERIFY_REPORT:-${REPORT_DIR}/xt-rollback-verify.json}"
  local supervisor_doctor_report="${XT_SUPERVISOR_DOCTOR_REPORT:-${REPORT_DIR}/supervisor_doctor_report.json}"
  local cm_validator="${ROOT_DIR}/scripts/ci/cm_w5_20_report_validator.js"
  local cm_regression_script="${ROOT_DIR}/scripts/ci/cm_w5_20_gate_regression.js"

  local doctor_report
  doctor_report="$(resolve_first_existing_file "${XT_DOCTOR_REPORT:-${REPORT_DIR}/doctor-report.json}" \
    "${REPORT_DIR}/doctor-risk-report.json" \
    "${REPORT_DIR}/xt-doctor-report.json")"
  local secrets_report
  secrets_report="$(resolve_first_existing_file "${XT_SECRETS_DRY_RUN_REPORT:-${REPORT_DIR}/secrets-dry-run-report.json}" \
    "${REPORT_DIR}/secrets-apply-dry-run-report.json" \
    "${REPORT_DIR}/xt-secrets-dry-run-report.json")"

  coverage_doctor_report_path="${doctor_report}"
  coverage_secrets_report_path="${secrets_report}"
  coverage_rollback_report_path="${rollback_verify_report}"

  local cm_fail=0
  local cm_warn=0
  local crk_fail=0
  local crk_warn=0

  if [[ -f "${doctor_report}" ]]; then
    note_pass "${gate_name}: CM-W5-20 doctor report found (${doctor_report})"

    if ! check_pattern_regex "${doctor_report}" "authz_parity_for_all_ingress|non_message_ingress_policy_coverage" "${gate_name}" "doctor report non-message ingress auth parity symbols"; then
      cm_fail=1
      crk_fail=1
    fi
    if ! check_pattern_fixed "${doctor_report}" "unauthorized_flood_drop_count" "${gate_name}" "doctor report flood-breaker observability metric"; then
      cm_fail=1
      crk_fail=1
    fi
    if ! check_pattern_regex "${doctor_report}" "dmPolicy|dm_policy" "${gate_name}" "doctor report dm/group policy signal"; then
      cm_fail=1
    fi
    if ! check_pattern_regex "${doctor_report}" "allowFrom|allow_from" "${gate_name}" "doctor report allowlist signal"; then
      cm_fail=1
    fi
    if ! check_pattern_regex "${doctor_report}" "ws[_ -]?origin" "${gate_name}" "doctor report ws origin signal"; then
      cm_fail=1
    fi
    if ! check_pattern_regex "${doctor_report}" "shared[_ -]?token[_ -]?auth|gateway[_ -]?auth" "${gate_name}" "doctor report gateway/shared-token auth signal"; then
      cm_fail=1
    fi
    if [[ -f "${cm_validator}" ]]; then
      if node "${cm_validator}" --kind doctor --file "${doctor_report}" >/tmp/xt_gate_doctor_schema.log 2>&1; then
        note_pass "${gate_name}: doctor report structured fields are valid"
      else
        note_fail "${gate_name}: doctor report has invalid/missing structured fields (see /tmp/xt_gate_doctor_schema.log)"
        cm_fail=1
        crk_fail=1
      fi
    else
      note_fail "${gate_name}: validator script missing (${cm_validator})"
      cm_fail=1
      crk_fail=1
    fi
  else
    if [[ "${MODE}" == "strict" ]]; then
      note_fail "${gate_name}: CM-W5-20 doctor report missing (${doctor_report})"
      cm_fail=1
      crk_fail=1
    else
      note_warn "${gate_name}: CM-W5-20 doctor report missing (${doctor_report}); baseline mode allows warning"
      cm_warn=1
      crk_warn=1
    fi
  fi

  if [[ -f "${secrets_report}" ]]; then
    note_pass "${gate_name}: CM-W5-20 secrets dry-run report found (${secrets_report})"

    if ! check_pattern_regex "${secrets_report}" "dry[_ -]?run" "${gate_name}" "secrets report dry-run marker"; then
      cm_fail=1
    fi
    if ! check_pattern_regex "${secrets_report}" "target[_ -]?path|targetPath" "${gate_name}" "secrets report target path signal"; then
      cm_fail=1
    fi
    if ! check_pattern_regex "${secrets_report}" "missing[_ -]?variables|missingVars" "${gate_name}" "secrets report missing-variable signal"; then
      cm_fail=1
    fi
    if ! check_pattern_regex "${secrets_report}" "permission[_ -]?boundary|out[_ -]?of[_ -]?scope|scope[_ -]?boundary" "${gate_name}" "secrets report permission boundary signal"; then
      cm_fail=1
    fi
    if [[ -f "${cm_validator}" ]]; then
      if node "${cm_validator}" --kind secrets --file "${secrets_report}" >/tmp/xt_gate_secrets_schema.log 2>&1; then
        note_pass "${gate_name}: secrets report structured fields are valid"
      else
        note_fail "${gate_name}: secrets report has invalid/missing structured fields (see /tmp/xt_gate_secrets_schema.log)"
        cm_fail=1
      fi
    else
      note_fail "${gate_name}: validator script missing (${cm_validator})"
      cm_fail=1
    fi
  else
    if [[ "${MODE}" == "strict" ]]; then
      note_fail "${gate_name}: CM-W5-20 secrets dry-run report missing (${secrets_report})"
      cm_fail=1
    else
      note_warn "${gate_name}: CM-W5-20 secrets dry-run report missing (${secrets_report}); baseline mode allows warning"
      cm_warn=1
      if [[ -f "${supervisor_doctor_report}" ]]; then
        note_pass "${gate_name}: supervisor doctor report present (${supervisor_doctor_report}) but does not replace dedicated secrets dry-run report"
      fi
    fi
  fi

  if [[ -f "${cm_regression_script}" ]]; then
    if node "${cm_regression_script}" >/tmp/xt_gate_cm_w5_20_regression.log 2>&1; then
      note_pass "${gate_name}: CM-W5-20 regression samples passed"
    else
      note_fail "${gate_name}: CM-W5-20 regression samples failed (see /tmp/xt_gate_cm_w5_20_regression.log)"
      cm_fail=1
    fi
  else
    note_fail "${gate_name}: regression script missing (${cm_regression_script})"
    cm_fail=1
  fi

  if (( cm_fail == 1 )); then
    mark_status_fail coverage_cm_w5_20_status
    mark_status_fail coverage_xt_w3_08_status
  elif (( cm_warn == 1 )); then
    mark_status_warn coverage_cm_w5_20_status
    mark_status_warn coverage_xt_w3_08_status
  fi

  if (( crk_fail == 1 )); then
    mark_status_fail coverage_crk_w1_08_status
    mark_status_fail coverage_xt_w3_08_status
  elif (( crk_warn == 1 )); then
    mark_status_warn coverage_crk_w1_08_status
    mark_status_warn coverage_xt_w3_08_status
  fi

  if [[ -x "${rollback_script}" ]]; then
    note_pass "${gate_name}: rollback script is present and executable (${rollback_script})"

    mkdir -p "$(dirname "${rollback_verify_report}")"
    if "${rollback_script}" --verify-only --report-file "${rollback_verify_report}" >/tmp/xt_gate_rollback_verify.log 2>&1; then
      note_pass "${gate_name}: rollback verify-only flow passed (${rollback_verify_report})"
    else
      if [[ "${MODE}" == "strict" ]]; then
        note_fail "${gate_name}: rollback verify-only flow failed in strict mode (see /tmp/xt_gate_rollback_verify.log)"
        mark_status_fail coverage_xt_w3_08_status
      else
        note_warn "${gate_name}: rollback verify-only flow failed; baseline mode keeps warning (see /tmp/xt_gate_rollback_verify.log)"
        mark_status_warn coverage_xt_w3_08_status
      fi
    fi
  else
    note_fail "${gate_name}: rollback script missing or not executable (${rollback_script})"
    mark_status_fail coverage_xt_w3_08_status
  fi
}

render_report() {
  local release_decision="NO_GO"
  local generated_at
  generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  if (( fail_count == 0 )) && [[ "${coverage_xt_w3_08_status}" == "PASS" ]] && [[ "${coverage_crk_w1_08_status}" == "PASS" ]] && [[ "${coverage_cm_w5_20_status}" == "PASS" ]]; then
    release_decision="GO"
  elif (( fail_count == 0 )); then
    release_decision="GO_WITH_RISK"
  fi

  mkdir -p "${REPORT_DIR}"
  {
    echo "# XT Gate Report"
    echo
    echo "- generated_at: ${generated_at}"
    echo "- mode: ${MODE}"
    echo "- root: ${ROOT_DIR}"
    echo
    echo "## Summary"
    echo
    echo "- pass: ${pass_count}"
    echo "- warn: ${warn_count}"
    echo "- fail: ${fail_count}"
    echo
    echo "## Release Decision"
    echo
    echo "- decision: ${release_decision}"
    echo "- criteria: fail_count=0 and XT-W3-08/CRK-W1-08/CM-W5-20 all PASS"
    echo "- observed: fail_count=${fail_count}, XT-W3-08=${coverage_xt_w3_08_status}, CRK-W1-08=${coverage_crk_w1_08_status}, CM-W5-20=${coverage_cm_w5_20_status}"
    echo
    echo "## 新增工单ID覆盖区块"
    echo
    echo "- XT-W3-08: ${coverage_xt_w3_08_status}"
    echo "- CRK-W1-08: ${coverage_crk_w1_08_status}"
    echo "- CM-W5-20: ${coverage_cm_w5_20_status}"
    echo "- evidence.doctor_report: ${coverage_doctor_report_path}"
    echo "- evidence.secrets_dry_run_report: ${coverage_secrets_report_path}"
    echo "- evidence.rollback_verify_report: ${coverage_rollback_report_path}"
    echo "- evidence.split_audit_contract_report: ${coverage_split_audit_contract_report_path}"
    echo "- evidence.split_audit_summary.overridden_events: ${coverage_split_audit_overridden_events}"
    echo "- evidence.split_audit_summary.override_total: ${coverage_split_audit_override_total}"
    echo "- evidence.split_audit_summary.blocking_total: ${coverage_split_audit_blocking_total}"
    echo "- evidence.split_audit_summary.high_risk_confirmed_total: ${coverage_split_audit_high_risk_confirmed_total}"
    echo "- evidence.split_audit_summary.replay_events: ${coverage_split_audit_replay_events}"
    echo "- evidence.split_flow_contract_report: ${coverage_split_flow_contract_report_path}"
    echo "- evidence.split_flow_contract.snapshot_schema: ${coverage_split_flow_snapshot_schema}"
    echo "- evidence.split_flow_contract.snapshot_version: ${coverage_split_flow_snapshot_version}"
    echo "- evidence.split_flow_contract.state_machine_version: ${coverage_split_flow_state_machine_version}"
    echo "- evidence.split_flow_fixture_contract_report: ${coverage_split_flow_fixture_contract_report_path}"
    echo "- evidence.split_flow_fixture.snapshot_count: ${coverage_split_flow_fixture_snapshot_count}"
    echo "- evidence.split_flow_runtime_fixture: ${coverage_split_flow_runtime_fixture_path}"
    echo "- evidence.split_flow_runtime_regression: ${coverage_split_flow_runtime_regression_status}"
    echo "- evidence.split_flow_runtime_policy_regression: ${coverage_split_flow_runtime_policy_regression_status}"
    echo "- evidence.split_flow_runtime_policy_regression_log: ${coverage_split_flow_runtime_policy_regression_log_path}"
    echo "- evidence.release_evidence_matrix_log: ${coverage_release_evidence_matrix_log_path}"
    echo "- evidence.release_evidence_matrix_summary: ${coverage_release_evidence_matrix_summary_path}"
    echo "- evidence.release_evidence_matrix_validator_regression_log: ${coverage_release_evidence_matrix_validator_regression_log_path}"
    echo "- evidence.report_index: ${REPORT_INDEX_FILE}"
    echo
    if (( ${#fail_lines[@]} > 0 )); then
      echo "## Fails"
      printf "%s\n" "${fail_lines[@]}"
      echo
    fi
    if (( ${#warn_lines[@]} > 0 )); then
      echo "## Warnings"
      printf "%s\n" "${warn_lines[@]}"
      echo
    fi
    if (( ${#pass_lines[@]} > 0 )); then
      echo "## Passes"
      printf "%s\n" "${pass_lines[@]}"
      echo
    fi
  } > "${REPORT_FILE}"

  REPORT_INDEX_FILE="${REPORT_INDEX_FILE}" \
  REPORT_FILE="${REPORT_FILE}" \
  GENERATED_AT="${generated_at}" \
  MODE="${MODE}" \
  ROOT_DIR="${ROOT_DIR}" \
  RELEASE_DECISION="${release_decision}" \
  PASS_COUNT="${pass_count}" \
  WARN_COUNT="${warn_count}" \
  FAIL_COUNT="${fail_count}" \
  COVERAGE_XT_W3_08="${coverage_xt_w3_08_status}" \
  COVERAGE_CRK_W1_08="${coverage_crk_w1_08_status}" \
  COVERAGE_CM_W5_20="${coverage_cm_w5_20_status}" \
  EVIDENCE_DOCTOR_REPORT="${coverage_doctor_report_path}" \
  EVIDENCE_SECRETS_REPORT="${coverage_secrets_report_path}" \
  EVIDENCE_ROLLBACK_REPORT="${coverage_rollback_report_path}" \
  EVIDENCE_SPLIT_AUDIT_REPORT="${coverage_split_audit_contract_report_path}" \
  EVIDENCE_SPLIT_AUDIT_OVERRIDDEN_EVENTS="${coverage_split_audit_overridden_events}" \
  EVIDENCE_SPLIT_AUDIT_OVERRIDE_TOTAL="${coverage_split_audit_override_total}" \
  EVIDENCE_SPLIT_AUDIT_BLOCKING_TOTAL="${coverage_split_audit_blocking_total}" \
  EVIDENCE_SPLIT_AUDIT_HIGH_RISK_CONFIRMED_TOTAL="${coverage_split_audit_high_risk_confirmed_total}" \
  EVIDENCE_SPLIT_AUDIT_REPLAY_EVENTS="${coverage_split_audit_replay_events}" \
  EVIDENCE_SPLIT_FLOW_CONTRACT_REPORT="${coverage_split_flow_contract_report_path}" \
  EVIDENCE_SPLIT_FLOW_SNAPSHOT_SCHEMA="${coverage_split_flow_snapshot_schema}" \
  EVIDENCE_SPLIT_FLOW_SNAPSHOT_VERSION="${coverage_split_flow_snapshot_version}" \
  EVIDENCE_SPLIT_FLOW_STATE_MACHINE_VERSION="${coverage_split_flow_state_machine_version}" \
  EVIDENCE_SPLIT_FLOW_FIXTURE_CONTRACT_REPORT="${coverage_split_flow_fixture_contract_report_path}" \
  EVIDENCE_SPLIT_FLOW_FIXTURE_SNAPSHOT_COUNT="${coverage_split_flow_fixture_snapshot_count}" \
  EVIDENCE_SPLIT_FLOW_RUNTIME_FIXTURE="${coverage_split_flow_runtime_fixture_path}" \
  EVIDENCE_SPLIT_FLOW_RUNTIME_REGRESSION_STATUS="${coverage_split_flow_runtime_regression_status}" \
  EVIDENCE_SPLIT_FLOW_RUNTIME_POLICY_REGRESSION_STATUS="${coverage_split_flow_runtime_policy_regression_status}" \
  EVIDENCE_SPLIT_FLOW_RUNTIME_POLICY_REGRESSION_LOG="${coverage_split_flow_runtime_policy_regression_log_path}" \
  EVIDENCE_RELEASE_EVIDENCE_MATRIX_LOG="${coverage_release_evidence_matrix_log_path}" \
  EVIDENCE_RELEASE_EVIDENCE_MATRIX_SUMMARY="${coverage_release_evidence_matrix_summary_path}" \
  EVIDENCE_RELEASE_EVIDENCE_MATRIX_VALIDATOR_REGRESSION_LOG="${coverage_release_evidence_matrix_validator_regression_log_path}" \
  node - <<'NODE'
const fs = require("fs");
const path = require("path");

const outputPath = process.env.REPORT_INDEX_FILE;
const report = {
  schema_version: "xt_report_index.v1",
  generated_at: process.env.GENERATED_AT || "",
  mode: process.env.MODE || "",
  root: process.env.ROOT_DIR || "",
  release_decision: process.env.RELEASE_DECISION || "",
  summary: {
    pass: Number(process.env.PASS_COUNT || "0"),
    warn: Number(process.env.WARN_COUNT || "0"),
    fail: Number(process.env.FAIL_COUNT || "0")
  },
  coverage: {
    "XT-W3-08": process.env.COVERAGE_XT_W3_08 || "",
    "CRK-W1-08": process.env.COVERAGE_CRK_W1_08 || "",
    "CM-W5-20": process.env.COVERAGE_CM_W5_20 || ""
  },
  evidence: {
    xt_gate_report: process.env.REPORT_FILE || "",
    doctor_report: process.env.EVIDENCE_DOCTOR_REPORT || "",
    secrets_dry_run_report: process.env.EVIDENCE_SECRETS_REPORT || "",
    rollback_verify_report: process.env.EVIDENCE_ROLLBACK_REPORT || "",
    split_audit_contract_report: process.env.EVIDENCE_SPLIT_AUDIT_REPORT || "",
    split_flow_contract_report: process.env.EVIDENCE_SPLIT_FLOW_CONTRACT_REPORT || "",
    split_flow_fixture_contract_report: process.env.EVIDENCE_SPLIT_FLOW_FIXTURE_CONTRACT_REPORT || "",
    split_flow_runtime_fixture: process.env.EVIDENCE_SPLIT_FLOW_RUNTIME_FIXTURE || "",
    split_flow_runtime_policy_regression_log:
      process.env.EVIDENCE_SPLIT_FLOW_RUNTIME_POLICY_REGRESSION_LOG || "",
    release_evidence_matrix_log: process.env.EVIDENCE_RELEASE_EVIDENCE_MATRIX_LOG || "",
    release_evidence_matrix_summary: process.env.EVIDENCE_RELEASE_EVIDENCE_MATRIX_SUMMARY || "",
    release_evidence_matrix_validator_regression_log:
      process.env.EVIDENCE_RELEASE_EVIDENCE_MATRIX_VALIDATOR_REGRESSION_LOG || ""
  },
  split_audit_summary: {
    overridden_events: Number(process.env.EVIDENCE_SPLIT_AUDIT_OVERRIDDEN_EVENTS || "0"),
    override_total: Number(process.env.EVIDENCE_SPLIT_AUDIT_OVERRIDE_TOTAL || "0"),
    blocking_total: Number(process.env.EVIDENCE_SPLIT_AUDIT_BLOCKING_TOTAL || "0"),
    high_risk_confirmed_total: Number(process.env.EVIDENCE_SPLIT_AUDIT_HIGH_RISK_CONFIRMED_TOTAL || "0"),
    replay_events: Number(process.env.EVIDENCE_SPLIT_AUDIT_REPLAY_EVENTS || "0")
  },
  split_flow_contract_summary: {
    snapshot_schema: process.env.EVIDENCE_SPLIT_FLOW_SNAPSHOT_SCHEMA || "",
    snapshot_version: process.env.EVIDENCE_SPLIT_FLOW_SNAPSHOT_VERSION || "",
    state_machine_version: process.env.EVIDENCE_SPLIT_FLOW_STATE_MACHINE_VERSION || ""
  },
  split_flow_fixture_summary: {
    snapshot_count: Number(process.env.EVIDENCE_SPLIT_FLOW_FIXTURE_SNAPSHOT_COUNT || "0")
  },
  split_flow_runtime_regression: {
    status: process.env.EVIDENCE_SPLIT_FLOW_RUNTIME_REGRESSION_STATUS || ""
  },
  split_flow_runtime_policy_regression: {
    status: process.env.EVIDENCE_SPLIT_FLOW_RUNTIME_POLICY_REGRESSION_STATUS || ""
  }
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
NODE
}

main() {
  run_gate_g0
  run_gate_g1
  run_gate_g2
  run_gate_g3
  run_gate_split_audit_contract
  run_gate_split_flow_contract
  run_gate_xt_ready_contract
  run_gate_xt_ready_executable
  run_gate_supervisor_doctor
  run_gate_g4
  run_gate_g5
  run_gate_split_flow_runtime_policy_regression
  run_gate_release_evidence_matrix_regression
  render_report

  echo "[xt-gate] report: ${REPORT_FILE}"
  if (( fail_count > 0 )); then
    echo "[xt-gate] failed: ${fail_count}"
    return 1
  fi
  echo "[xt-gate] passed with ${warn_count} warning(s)"
  return 0
}

main "$@"
