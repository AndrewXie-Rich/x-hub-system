#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE_SCRIPT="${ROOT_DIR}/scripts/ci/xt_release_gate.sh"
PROFILE_HELPER="${ROOT_DIR}/scripts/ci/xt_nested_gate_profile.sh"
KEEP_WORKDIR="${XT_SPLIT_FLOW_POLICY_REGRESSION_KEEP:-0}"

if [[ ! -f "${GATE_SCRIPT}" ]]; then
  echo "[split-flow-policy] gate script missing: ${GATE_SCRIPT}" >&2
  exit 2
fi

if [[ ! -f "${PROFILE_HELPER}" ]]; then
  echo "[split-flow-policy] nested gate profile helper missing: ${PROFILE_HELPER}" >&2
  exit 2
fi

if [[ -n "${XT_SPLIT_FLOW_POLICY_REGRESSION_WORKDIR:-}" ]]; then
  WORK_DIR="${XT_SPLIT_FLOW_POLICY_REGRESSION_WORKDIR}"
  mkdir -p "${WORK_DIR}"
else
  WORK_DIR="$(mktemp -d /tmp/xt_split_flow_policy_regression.XXXXXX)"
fi

cleanup() {
  if [[ -n "${XT_SPLIT_FLOW_POLICY_REGRESSION_WORKDIR:-}" ]]; then
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

DEFAULT_DOCTOR_REPORT="${ROOT_DIR}/.axcoder/reports/doctor-report.json"
DEFAULT_SECRETS_DRY_RUN_REPORT="${ROOT_DIR}/.axcoder/reports/secrets-dry-run-report.json"
FALLBACK_FIXTURE_DIR="${WORK_DIR}/fixtures"
FALLBACK_DOCTOR_REPORT="${FALLBACK_FIXTURE_DIR}/doctor-report.sample.json"
FALLBACK_SECRETS_DRY_RUN_REPORT="${FALLBACK_FIXTURE_DIR}/secrets-dry-run-report.sample.json"

record_pass() {
  pass_count=$((pass_count + 1))
  printf '[PASS] %s\n' "$1"
}

record_fail() {
  fail_count=$((fail_count + 1))
  printf '[FAIL] %s\n' "$1" >&2
}

require_file() {
  local path="$1"
  local label="$2"
  if [[ -f "${path}" ]]; then
    return 0
  fi
  record_fail "${label}: missing file (${path})"
  return 1
}

extract_split_flow_runtime_status() {
  local path="$1"
  node -e '
const fs = require("fs");
const file = process.argv[1];
try {
  const doc = JSON.parse(fs.readFileSync(file, "utf8"));
  const status = ((doc || {}).split_flow_runtime_regression || {}).status || "";
  process.stdout.write(String(status));
} catch (_) {
  process.stdout.write("");
}
' "${path}"
}

prepare_release_report_fallbacks() {
  mkdir -p "${FALLBACK_FIXTURE_DIR}"

  if [[ ! -f "${FALLBACK_DOCTOR_REPORT}" ]]; then
    cat >"${FALLBACK_DOCTOR_REPORT}" <<'JSON'
{
  "doctor": {
    "dmPolicy": "allow",
    "allowFrom": ["workspace"],
    "ws_origin": "https://example.com",
    "shared_token_auth": true,
    "authz_parity_for_all_ingress": true,
    "non_message_ingress_policy_coverage": 1,
    "unauthorized_flood_drop_count": 0
  }
}
JSON
  fi

  if [[ ! -f "${FALLBACK_SECRETS_DRY_RUN_REPORT}" ]]; then
    cat >"${FALLBACK_SECRETS_DRY_RUN_REPORT}" <<'JSON'
{
  "dry_run": true,
  "target_path": ".axcoder/secrets/ws_shared_token.env",
  "missing_variables": [],
  "permission_boundary": "ok"
}
JSON
  fi
}

resolve_release_report_path() {
  local preferred="$1"
  local fallback="$2"
  if [[ -f "${preferred}" ]]; then
    echo "${preferred}"
    return
  fi
  echo "${fallback}"
}

run_case() {
  local case_name="$1"
  local mode="$2"
  local release_preset="$3"
  local runtime_regression="$4"   # "__unset__" | "0" | "1"
  local expected_exit="$5"
  local expected_status="$6"
  local expected_pattern="$7"

  local case_dir="${WORK_DIR}/${case_name}"
  local report_dir="${case_dir}/reports"
  local report_file="${report_dir}/xt-gate-report.md"
  local report_index_file="${report_dir}/xt-report-index.json"
  local run_log="${case_dir}/run.log"
  mkdir -p "${case_dir}" "${report_dir}"

  local doctor_report_path
  doctor_report_path="$(resolve_release_report_path "${DEFAULT_DOCTOR_REPORT}" "${FALLBACK_DOCTOR_REPORT}")"
  local secrets_report_path
  secrets_report_path="$(resolve_release_report_path "${DEFAULT_SECRETS_DRY_RUN_REPORT}" "${FALLBACK_SECRETS_DRY_RUN_REPORT}")"

  local -a env_vars=(
    "XT_GATE_MODE=${mode}"
    "XT_GATE_RELEASE_PRESET=${release_preset}"
    "XT_DOCTOR_REPORT=${doctor_report_path}"
    "XT_SECRETS_DRY_RUN_REPORT=${secrets_report_path}"
    "XT_GATE_REPORT_DIR=${report_dir}"
    "XT_GATE_REPORT_FILE=${report_file}"
    "XT_GATE_REPORT_INDEX_FILE=${report_index_file}"
  )

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    env_vars+=("${line}")
  done < <(bash "${PROFILE_HELPER}" split_flow_policy)

  if [[ "${runtime_regression}" != "__unset__" ]]; then
    env_vars+=("XT_GATE_SPLIT_FLOW_RUNTIME_REGRESSION=${runtime_regression}")
  fi

  set +e
  (
    cd "${ROOT_DIR}"
    env "${env_vars[@]}" bash "${GATE_SCRIPT}"
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

  local actual_status
  actual_status="$(extract_split_flow_runtime_status "${report_index_file}")"
  if [[ "${actual_status}" != "${expected_status}" ]]; then
    record_fail "${case_name}: expected split_flow_runtime_regression.status=${expected_status}, got ${actual_status:-<empty>}"
    return
  fi

  if [[ -n "${expected_pattern}" ]]; then
    if ! rg -q --fixed-strings "${expected_pattern}" "${report_file}"; then
      record_fail "${case_name}: missing pattern '${expected_pattern}' in ${report_file}"
      return
    fi
  fi

  record_pass "${case_name}"
}

prepare_release_report_fallbacks

run_case "baseline_default_runtime_off" "baseline" "0" "__unset__" 0 "skipped" ""
run_case "strict_default_runtime_on" "strict" "0" "__unset__" 0 "pass" \
  "runtime regression enabled by default (mode=strict, release_preset=0)"
run_case "strict_runtime_opt_out" "strict" "0" "0" 0 "skipped" ""
run_case "release_preset_runtime_on_by_default" "baseline" "1" "__unset__" 0 "pass" \
  "runtime regression enabled by default (mode=baseline, release_preset=1)"
run_case "release_preset_runtime_forced_off_fails" "baseline" "1" "0" 1 "fail" \
  "release preset requires runtime regression (set XT_GATE_SPLIT_FLOW_RUNTIME_REGRESSION=1)"

printf '[split-flow-policy] workdir=%s\n' "${WORK_DIR}"
printf '[split-flow-policy] pass=%d fail=%d\n' "${pass_count}" "${fail_count}"

if (( fail_count > 0 )); then
  exit 1
fi
