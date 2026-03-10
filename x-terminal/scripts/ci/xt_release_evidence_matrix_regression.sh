#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE_SCRIPT="${ROOT_DIR}/scripts/ci/xt_release_gate.sh"
KEEP_WORKDIR="${XT_RELEASE_EVIDENCE_MATRIX_KEEP:-0}"

if [[ ! -f "${GATE_SCRIPT}" ]]; then
  echo "[matrix] gate script missing: ${GATE_SCRIPT}" >&2
  exit 2
fi

if [[ -n "${XT_RELEASE_EVIDENCE_MATRIX_WORKDIR:-}" ]]; then
  WORK_DIR="${XT_RELEASE_EVIDENCE_MATRIX_WORKDIR}"
  mkdir -p "${WORK_DIR}"
else
  WORK_DIR="$(mktemp -d /tmp/xt_release_evidence_matrix.XXXXXX)"
fi

cleanup() {
  if [[ -n "${XT_RELEASE_EVIDENCE_MATRIX_WORKDIR:-}" ]]; then
    return
  fi
  if [[ "${KEEP_WORKDIR}" == "1" ]]; then
    return
  fi
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

pass_count=0
fail_count=0

green() {
  printf '[PASS] %s\n' "$1"
}

red() {
  printf '[FAIL] %s\n' "$1" >&2
}

record_pass() {
  pass_count=$((pass_count + 1))
  green "$1"
}

record_fail() {
  fail_count=$((fail_count + 1))
  red "$1"
}

require_file() {
  local path="$1"
  local hint="$2"
  if [[ -f "${path}" ]]; then
    return 0
  fi
  record_fail "${hint}: missing file (${path})"
  return 1
}

require_contains() {
  local path="$1"
  local pattern="$2"
  local hint="$3"
  if rg -q --fixed-strings "${pattern}" "${path}"; then
    return 0
  fi
  record_fail "${hint}: missing pattern '${pattern}' in ${path}"
  return 1
}

require_not_contains() {
  local path="$1"
  local pattern="$2"
  local hint="$3"
  if rg -q --fixed-strings "${pattern}" "${path}"; then
    record_fail "${hint}: unexpected pattern '${pattern}' in ${path}"
    return 1
  fi
  return 0
}

run_case() {
  local case_name="$1"
  local release_preset="$2"
  local auto_prepare="$3"
  local expected_exit="$4"
  local runtime_mode="$5"
  local expect_auto_prepare_note="$6"
  local expect_runtime_missing_note="$7"
  local expected_policy_status="$8"
  local expect_policy_default_note="$9"

  local case_dir="${WORK_DIR}/${case_name}"
  local report_dir="${case_dir}/reports"
  local report_file="${report_dir}/xt-gate-report.md"
  local report_index_file="${report_dir}/xt-report-index.json"
  local run_log="${case_dir}/run.log"
  mkdir -p "${case_dir}" "${report_dir}"

  local runtime_override=""
  if [[ "${runtime_mode}" == "missing" ]]; then
    runtime_override="${case_dir}/missing_runtime_events.json"
  fi

  local -a env_vars=(
    "XT_GATE_MODE=baseline"
    "XT_GATE_RELEASE_PRESET=${release_preset}"
    "XT_GATE_AUTO_PREPARE_RELEASE_EVIDENCE=${auto_prepare}"
    "XT_GATE_REPORT_DIR=${report_dir}"
    "XT_GATE_REPORT_FILE=${report_file}"
    "XT_GATE_REPORT_INDEX_FILE=${report_index_file}"
    "XT_GATE_VALIDATE_RELEASE_EVIDENCE_MATRIX=0"
  )

  if [[ -n "${runtime_override}" ]]; then
    env_vars+=("XT_READY_INCIDENT_EVENTS_JSON=${runtime_override}")
  fi

  set +e
  (
    cd "${ROOT_DIR}"
    env -u XT_GATE_VALIDATE_SPLIT_FLOW_RUNTIME_POLICY "${env_vars[@]}" bash "${GATE_SCRIPT}"
  ) >"${run_log}" 2>&1
  local rc=$?
  set -e

  if [[ "${rc}" -ne "${expected_exit}" ]]; then
    record_fail "${case_name}: expected exit=${expected_exit}, got ${rc} (log=${run_log})"
    return
  fi

  if ! require_file "${report_file}" "${case_name}"; then
    return
  fi
  if ! require_file "${report_index_file}" "${case_name}"; then
    return
  fi

  local decision=""
  decision="$(awk -F': ' '/^- decision: / {print $2; exit}' "${report_file}")"
  if [[ -z "${decision}" ]]; then
    record_fail "${case_name}: release decision missing in ${report_file}"
    return
  fi

  local policy_status=""
  policy_status="$(
    node -e '
const fs = require("fs");
const file = process.argv[1];
try {
  const doc = JSON.parse(fs.readFileSync(file, "utf8"));
  const status = ((doc || {}).split_flow_runtime_policy_regression || {}).status || "";
  process.stdout.write(String(status));
} catch (_) {
  process.stdout.write("");
}
' "${report_index_file}"
  )"
  if [[ "${policy_status}" != "${expected_policy_status}" ]]; then
    record_fail "${case_name}: expected split_flow_runtime_policy_regression.status=${expected_policy_status}, got ${policy_status:-<empty>}"
    return
  fi

  if [[ "${expected_exit}" -eq 0 ]]; then
    if [[ "${decision}" != "GO" && "${decision}" != "GO_WITH_RISK" ]]; then
      record_fail "${case_name}: expected GO/GO_WITH_RISK decision, got ${decision}"
      return
    fi
  else
    if [[ "${decision}" != "NO_GO" ]]; then
      record_fail "${case_name}: expected NO_GO decision, got ${decision}"
      return
    fi
  fi

  if [[ "${expect_auto_prepare_note}" == "present" ]]; then
    if ! require_contains "${report_file}" "auto-prepared release evidence via XTerminal smoke" "${case_name}"; then
      return
    fi
  else
    if ! require_not_contains "${report_file}" "auto-prepared release evidence via XTerminal smoke" "${case_name}"; then
      return
    fi
  fi

  if [[ "${expect_runtime_missing_note}" == "1" ]]; then
    if ! require_contains "${report_file}" "required runtime incident events file missing" "${case_name}"; then
      return
    fi
  fi

  if [[ "${expect_policy_default_note}" == "present" ]]; then
    if ! require_contains "${report_file}" "Split Flow Runtime Policy Regression: enabled by default (release_preset=1)" "${case_name}"; then
      return
    fi
  else
    if ! require_not_contains "${report_file}" "Split Flow Runtime Policy Regression: enabled by default (release_preset=1)" "${case_name}"; then
      return
    fi
  fi

  record_pass "${case_name}"
}

run_case "baseline_release0_auto0" "0" "0" 0 "default" "absent" "0" "skipped" "absent"
run_case "baseline_release0_auto1" "0" "1" 0 "default" "absent" "0" "skipped" "absent"
run_case "baseline_release1_auto0_fail_closed" "1" "0" 1 "missing" "absent" "1" "pass" "present"
run_case "baseline_release1_auto1_auto_prepare" "1" "1" 0 "default" "present" "0" "pass" "present"

printf '[matrix] workdir=%s\n' "${WORK_DIR}"
printf '[matrix] pass=%d fail=%d\n' "${pass_count}" "${fail_count}"

if (( fail_count > 0 )); then
  exit 1
fi
