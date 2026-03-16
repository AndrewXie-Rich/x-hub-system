#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILE_HELPER="${ROOT_DIR}/scripts/ci/xt_nested_gate_profile.sh"

RUN_BUILD="${XT_FAST_CHECK_RUN_BUILD:-0}"
RUN_VALIDATOR="${XT_FAST_CHECK_RUN_VALIDATOR:-1}"
RUN_MATRIX="${XT_FAST_CHECK_RUN_MATRIX:-0}"
RUN_BASELINE_GATE="${XT_FAST_CHECK_RUN_BASELINE_GATE:-0}"
ALLOW_BUILD_SANDBOX_FAILURE="${XT_FAST_CHECK_ALLOW_BUILD_SANDBOX_FAILURE:-1}"
WRITE_SUMMARY="${XT_FAST_CHECK_WRITE_SUMMARY:-1}"
APPEND_HISTORY="${XT_FAST_CHECK_APPEND_HISTORY:-1}"

GATE_SKIP_BUILD="${XT_FAST_CHECK_SKIP_BUILD:-1}"
GATE_SKIP_XT_READY_CONTRACT="${XT_FAST_CHECK_SKIP_XT_READY_CONTRACT:-1}"
GATE_SKIP_XT_READY_EXECUTABLE="${XT_FAST_CHECK_SKIP_XT_READY_EXECUTABLE:-0}"
FAST_REPORT_DIR="${XT_FAST_CHECK_REPORT_DIR:-${ROOT_DIR}/.axcoder/reports}"
FAST_REPORT_FILE="${XT_FAST_CHECK_REPORT_FILE:-${FAST_REPORT_DIR}/xt-fast-check-summary.json}"
FAST_HISTORY_FILE="${XT_FAST_CHECK_HISTORY_FILE:-${FAST_REPORT_DIR}/xt-fast-check-history.json}"
FAST_HISTORY_LIMIT="${XT_FAST_CHECK_HISTORY_LIMIT:-20}"

start_epoch="$(date +%s)"
start_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

swift_build_status="pending"
swift_build_note=""
validator_status="pending"
validator_note=""
matrix_gate_status="pending"
matrix_gate_note=""
baseline_gate_status="pending"
baseline_gate_note=""
PROFILE_ENV_LINES=()

step() {
  local message="$1"
  printf '[fast-check] %s\n' "${message}"
}

warn() {
  local message="$1"
  printf '[fast-check][warn] %s\n' "${message}"
}

require_profile_helper() {
  if [[ -f "${PROFILE_HELPER}" ]]; then
    return 0
  fi
  echo "[fast-check] nested gate profile helper missing: ${PROFILE_HELPER}" >&2
  return 1
}

load_profile_env() {
  local profile="$1"
  PROFILE_ENV_LINES=()
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    PROFILE_ENV_LINES+=("${line}")
  done < <(bash "${PROFILE_HELPER}" "${profile}")
}

write_summary() {
  local exit_code="$1"
  if [[ "${WRITE_SUMMARY}" != "1" ]]; then
    return 0
  fi

  local end_epoch
  end_epoch="$(date +%s)"
  local end_iso
  end_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local elapsed
  elapsed="$((end_epoch - start_epoch))"
  local overall_status="pass"
  if [[ "${exit_code}" -ne 0 ]]; then
    overall_status="fail"
  fi

  FAST_SUMMARY_FILE="${FAST_REPORT_FILE}" \
  FAST_SCHEMA_VERSION="xt_fast_checks.v1" \
  FAST_ROOT_DIR="${ROOT_DIR}" \
  FAST_START_ISO="${start_iso}" \
  FAST_END_ISO="${end_iso}" \
  FAST_ELAPSED_SEC="${elapsed}" \
  FAST_EXIT_CODE="${exit_code}" \
  FAST_OVERALL_STATUS="${overall_status}" \
  FAST_RUN_BUILD="${RUN_BUILD}" \
  FAST_RUN_VALIDATOR="${RUN_VALIDATOR}" \
  FAST_RUN_MATRIX="${RUN_MATRIX}" \
  FAST_RUN_BASELINE_GATE="${RUN_BASELINE_GATE}" \
  FAST_ALLOW_BUILD_SANDBOX_FAILURE="${ALLOW_BUILD_SANDBOX_FAILURE}" \
  FAST_APPEND_HISTORY="${APPEND_HISTORY}" \
  FAST_HISTORY_FILE="${FAST_HISTORY_FILE}" \
  FAST_HISTORY_LIMIT="${FAST_HISTORY_LIMIT}" \
  FAST_GATE_SKIP_BUILD="${GATE_SKIP_BUILD}" \
  FAST_GATE_SKIP_XT_READY_CONTRACT="${GATE_SKIP_XT_READY_CONTRACT}" \
  FAST_GATE_SKIP_XT_READY_EXECUTABLE="${GATE_SKIP_XT_READY_EXECUTABLE}" \
  FAST_SWIFT_BUILD_STATUS="${swift_build_status}" \
  FAST_SWIFT_BUILD_NOTE="${swift_build_note}" \
  FAST_VALIDATOR_STATUS="${validator_status}" \
  FAST_VALIDATOR_NOTE="${validator_note}" \
  FAST_MATRIX_GATE_STATUS="${matrix_gate_status}" \
  FAST_MATRIX_GATE_NOTE="${matrix_gate_note}" \
  FAST_BASELINE_GATE_STATUS="${baseline_gate_status}" \
  FAST_BASELINE_GATE_NOTE="${baseline_gate_note}" \
  node - <<'NODE'
const fs = require("fs");
const path = require("path");

const outputPath = process.env.FAST_SUMMARY_FILE || "";
if (!outputPath) {
  throw new Error("missing FAST_SUMMARY_FILE");
}

const report = {
  schema_version: process.env.FAST_SCHEMA_VERSION || "",
  generated_at: process.env.FAST_END_ISO || "",
  started_at: process.env.FAST_START_ISO || "",
  elapsed_sec: Number(process.env.FAST_ELAPSED_SEC || "0"),
  root: process.env.FAST_ROOT_DIR || "",
  exit_code: Number(process.env.FAST_EXIT_CODE || "1"),
  overall_status: process.env.FAST_OVERALL_STATUS || "fail",
  config: {
    run_build: process.env.FAST_RUN_BUILD || "0",
    run_validator: process.env.FAST_RUN_VALIDATOR || "0",
    run_matrix: process.env.FAST_RUN_MATRIX || "0",
    run_baseline_gate: process.env.FAST_RUN_BASELINE_GATE || "0",
    allow_build_sandbox_failure: process.env.FAST_ALLOW_BUILD_SANDBOX_FAILURE || "0",
    append_history: process.env.FAST_APPEND_HISTORY || "0",
    history_file: process.env.FAST_HISTORY_FILE || "",
    history_limit: process.env.FAST_HISTORY_LIMIT || "0",
    gate_skip_build: process.env.FAST_GATE_SKIP_BUILD || "0",
    gate_skip_xt_ready_contract: process.env.FAST_GATE_SKIP_XT_READY_CONTRACT || "0",
    gate_skip_xt_ready_executable: process.env.FAST_GATE_SKIP_XT_READY_EXECUTABLE || "0"
  },
  steps: {
    swift_build: {
      status: process.env.FAST_SWIFT_BUILD_STATUS || "pending",
      note: process.env.FAST_SWIFT_BUILD_NOTE || ""
    },
    matrix_validator_regression: {
      status: process.env.FAST_VALIDATOR_STATUS || "pending",
      note: process.env.FAST_VALIDATOR_NOTE || ""
    },
    baseline_matrix_gate: {
      status: process.env.FAST_MATRIX_GATE_STATUS || "pending",
      note: process.env.FAST_MATRIX_GATE_NOTE || ""
    },
    baseline_gate: {
      status: process.env.FAST_BASELINE_GATE_STATUS || "pending",
      note: process.env.FAST_BASELINE_GATE_NOTE || ""
    }
  }
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
NODE
}

append_history() {
  if [[ "${APPEND_HISTORY}" != "1" ]]; then
    step "skip fast-check history append (XT_FAST_CHECK_APPEND_HISTORY=${APPEND_HISTORY})"
    return 0
  fi

  if [[ "${WRITE_SUMMARY}" != "1" ]]; then
    step "skip fast-check history append (summary disabled)"
    return 0
  fi

  if [[ ! -f "${FAST_REPORT_FILE}" ]]; then
    warn "fast-check summary missing, skip history append (${FAST_REPORT_FILE})"
    return 0
  fi

  local history_log="/tmp/xt_fast_check_history_append.log"
  if (
    cd "${ROOT_DIR}" && \
      node scripts/ci/xt_fast_check_trend_append.js \
        --summary "${FAST_REPORT_FILE}" \
        --history "${FAST_HISTORY_FILE}" \
        --limit "${FAST_HISTORY_LIMIT}" >"${history_log}" 2>&1
  ); then
    cat "${history_log}"
    return 0
  fi

  warn "failed to append fast-check history (see ${history_log})"
  cat "${history_log}" >&2
  return 0
}

on_exit() {
  local rc=$?
  set +e
  write_summary "${rc}"
  append_history
  return "${rc}"
}

trap on_exit EXIT

run_swift_build() {
  if [[ "${RUN_BUILD}" != "1" ]]; then
    step "skip swift build (XT_FAST_CHECK_RUN_BUILD=${RUN_BUILD})"
    swift_build_status="skipped"
    swift_build_note="XT_FAST_CHECK_RUN_BUILD=${RUN_BUILD}"
    return
  fi

  step "swift build"
  local build_log="/tmp/xt_fast_check_swift_build.log"

  if (cd "${ROOT_DIR}" && swift build >"${build_log}" 2>&1); then
    swift_build_status="pass"
    swift_build_note=""
    return
  fi

  if [[ "${ALLOW_BUILD_SANDBOX_FAILURE}" == "1" ]] \
    && rg -q "Operation not permitted|sandbox_apply: Operation not permitted|not accessible or not writable|Invalid manifest|failed to build module 'Swift'" "${build_log}"; then
    warn "swift build blocked by local sandbox/toolchain; continue (see ${build_log})"
    swift_build_status="warn"
    swift_build_note="${build_log}"
    return
  fi

  swift_build_status="fail"
  swift_build_note="${build_log}"
  cat "${build_log}" >&2
  return 1
}

run_matrix_validator_regression() {
  if [[ "${RUN_VALIDATOR}" != "1" ]]; then
    step "skip validator regressions (XT_FAST_CHECK_RUN_VALIDATOR=${RUN_VALIDATOR})"
    validator_status="skipped"
    validator_note="XT_FAST_CHECK_RUN_VALIDATOR=${RUN_VALIDATOR}"
    return
  fi

  step "validator regressions (matrix + trend)"
  local validator_log="/tmp/xt_fast_check_matrix_validator_regression.log"
  if (
    cd "${ROOT_DIR}" && \
      {
        node scripts/ci/xt_release_evidence_matrix_validator_regression.js
        node scripts/ci/xt_fast_check_trend_append_regression.js
      } >"${validator_log}" 2>&1
  ); then
    validator_status="pass"
    validator_note="${validator_log}"
    cat "${validator_log}"
    return
  fi

  validator_status="fail"
  validator_note="${validator_log}"
  cat "${validator_log}" >&2
  return 1
}

run_baseline_matrix_gate() {
  if [[ "${RUN_MATRIX}" != "1" ]]; then
    step "skip matrix gate (XT_FAST_CHECK_RUN_MATRIX=${RUN_MATRIX})"
    matrix_gate_status="skipped"
    matrix_gate_note="XT_FAST_CHECK_RUN_MATRIX=${RUN_MATRIX}"
    return
  fi

  step "baseline gate + release evidence matrix"
  local matrix_gate_log="/tmp/xt_fast_check_matrix_gate.log"
  require_profile_helper
  load_profile_env "fast_check_matrix"
  local -a env_vars=(
    "XT_GATE_MODE=baseline"
    "${PROFILE_ENV_LINES[@]}"
    "XT_GATE_SKIP_BUILD=${GATE_SKIP_BUILD}"
    "XT_GATE_SKIP_XT_READY_CONTRACT=${GATE_SKIP_XT_READY_CONTRACT}"
    "XT_GATE_SKIP_XT_READY_EXECUTABLE=${GATE_SKIP_XT_READY_EXECUTABLE}"
  )
  if (
    cd "${ROOT_DIR}" && \
      env "${env_vars[@]}" bash scripts/ci/xt_release_gate.sh >"${matrix_gate_log}" 2>&1
  ); then
    matrix_gate_status="pass"
    matrix_gate_note="${matrix_gate_log}"
    cat "${matrix_gate_log}"
    return
  fi

  matrix_gate_status="fail"
  matrix_gate_note="${matrix_gate_log}"
  cat "${matrix_gate_log}" >&2
  return 1
}

run_baseline_gate() {
  if [[ "${RUN_BASELINE_GATE}" != "1" ]]; then
    step "skip plain baseline gate (XT_FAST_CHECK_RUN_BASELINE_GATE=${RUN_BASELINE_GATE})"
    baseline_gate_status="skipped"
    baseline_gate_note="XT_FAST_CHECK_RUN_BASELINE_GATE=${RUN_BASELINE_GATE}"
    return
  fi

  step "plain baseline gate"
  local baseline_gate_log="/tmp/xt_fast_check_baseline_gate.log"
  require_profile_helper
  load_profile_env "fast_check_baseline"
  local -a env_vars=(
    "XT_GATE_MODE=baseline"
    "${PROFILE_ENV_LINES[@]}"
    "XT_GATE_SKIP_BUILD=${GATE_SKIP_BUILD}"
    "XT_GATE_SKIP_XT_READY_CONTRACT=${GATE_SKIP_XT_READY_CONTRACT}"
    "XT_GATE_SKIP_XT_READY_EXECUTABLE=${GATE_SKIP_XT_READY_EXECUTABLE}"
  )
  if (
    cd "${ROOT_DIR}" && \
      env "${env_vars[@]}" bash scripts/ci/xt_release_gate.sh >"${baseline_gate_log}" 2>&1
  ); then
    baseline_gate_status="pass"
    baseline_gate_note="${baseline_gate_log}"
    cat "${baseline_gate_log}"
    return
  fi

  baseline_gate_status="fail"
  baseline_gate_note="${baseline_gate_log}"
  cat "${baseline_gate_log}" >&2
  return 1
}

main() {
  step "start"
  run_swift_build
  run_matrix_validator_regression
  run_baseline_matrix_gate
  run_baseline_gate

  end_epoch="$(date +%s)"
  elapsed="$((end_epoch - start_epoch))"
  step "done in ${elapsed}s (summary=${FAST_REPORT_FILE})"
}

main "$@"
