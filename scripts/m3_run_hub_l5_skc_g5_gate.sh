#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

resolve_abs_path() {
  python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$1"
}

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/m3_run_hub_l5_skc_g5_gate.sh \
    --audit-json <path> \
    --connector-gate-json <path> \
    [--g3-db-path <path>] \
    [--out-prefix <path>] \
    [--window <utc-iso8601>] \
    [--xt-report-index <path>] \
    [--metrics-json-override <path>] \
    [--samples-json-override <path>]

Description:
  Hub-L5 one-click gate runner for SKC-W3-08/09/10:
  1) require-real XT-Ready chain (resolve -> extract -> generate -> strict-e2e check)
  2) SKC-G3 real sampling (import success rate + import_to_first_run_p95_ms)
  3) release evidence matrix regression + validator
  4) internal pass-lines machine decision (with require-real evidence wiring)

Exit code:
  0 -> all checks passed, internal pass-lines decision is GO, and SKC-G3 real sampling is PASS
  2 -> checks ran, but internal pass-lines is non-GO and/or SKC-G3 is not PASS
  1 -> fail-closed on missing inputs or gate execution failure
USAGE
}

AUDIT_JSON=""
CONNECTOR_JSON=""
G3_DB_PATH="${ROOT_DIR}/x-hub/grpc-server/hub_grpc_server/data/hub.sqlite3"
OUT_PREFIX="${ROOT_DIR}/build/hub_l5"
WINDOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
XT_REPORT_INDEX_PATH="${ROOT_DIR}/x-terminal/.axcoder/reports/xt-report-index.json"
METRICS_JSON_OVERRIDE=""
SAMPLES_JSON_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --audit-json)
      AUDIT_JSON="$2"
      shift 2
      ;;
    --connector-gate-json)
      CONNECTOR_JSON="$2"
      shift 2
      ;;
    --g3-db-path)
      G3_DB_PATH="$2"
      shift 2
      ;;
    --out-prefix)
      OUT_PREFIX="$2"
      shift 2
      ;;
    --window)
      WINDOW="$2"
      shift 2
      ;;
    --xt-report-index)
      XT_REPORT_INDEX_PATH="$2"
      shift 2
      ;;
    --metrics-json-override)
      METRICS_JSON_OVERRIDE="$2"
      shift 2
      ;;
    --samples-json-override)
      SAMPLES_JSON_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument '$1'" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${AUDIT_JSON}" ]]; then
  echo "error: missing required --audit-json" >&2
  usage
  exit 1
fi
if [[ -z "${CONNECTOR_JSON}" ]]; then
  echo "error: missing required --connector-gate-json" >&2
  usage
  exit 1
fi

AUDIT_JSON="$(resolve_abs_path "${AUDIT_JSON}")"
CONNECTOR_JSON="$(resolve_abs_path "${CONNECTOR_JSON}")"
G3_DB_PATH="$(resolve_abs_path "${G3_DB_PATH}")"
OUT_PREFIX="$(resolve_abs_path "${OUT_PREFIX}")"
XT_REPORT_INDEX_PATH="$(resolve_abs_path "${XT_REPORT_INDEX_PATH}")"
if [[ -n "${METRICS_JSON_OVERRIDE}" ]]; then
  METRICS_JSON_OVERRIDE="$(resolve_abs_path "${METRICS_JSON_OVERRIDE}")"
fi
if [[ -n "${SAMPLES_JSON_OVERRIDE}" ]]; then
  SAMPLES_JSON_OVERRIDE="$(resolve_abs_path "${SAMPLES_JSON_OVERRIDE}")"
fi

if [[ ! -f "${AUDIT_JSON}" ]]; then
  echo "error: audit json not found (${AUDIT_JSON})" >&2
  exit 1
fi
if [[ ! -f "${CONNECTOR_JSON}" ]]; then
  echo "error: connector gate json not found (${CONNECTOR_JSON})" >&2
  exit 1
fi
if [[ ! -f "${G3_DB_PATH}" ]]; then
  echo "error: SKC-G3 sqlite source not found (${G3_DB_PATH})" >&2
  exit 1
fi
if [[ ! -f "${XT_REPORT_INDEX_PATH}" ]]; then
  echo "error: xt-report-index json not found (${XT_REPORT_INDEX_PATH})" >&2
  exit 1
fi
if [[ -n "${METRICS_JSON_OVERRIDE}" && ! -f "${METRICS_JSON_OVERRIDE}" ]]; then
  echo "error: metrics override json not found (${METRICS_JSON_OVERRIDE})" >&2
  exit 1
fi
if [[ -n "${SAMPLES_JSON_OVERRIDE}" && ! -f "${SAMPLES_JSON_OVERRIDE}" ]]; then
  echo "error: samples override json not found (${SAMPLES_JSON_OVERRIDE})" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUT_PREFIX}")"

EVIDENCE_SOURCE_JSON="${OUT_PREFIX}_xt_ready_evidence_source.require_real.json"
INCIDENTS_JSON="${OUT_PREFIX}_xt_ready_incident_events.require_real.json"
E2E_JSON="${OUT_PREFIX}_xt_ready_e2e_evidence.require_real.json"
XT_READY_GATE_REPORT="${OUT_PREFIX}_xt_ready_gate_e2e_require_real_report.json"

MATRIX_LOG="${OUT_PREFIX}_release_evidence_matrix.log"
MATRIX_SUMMARY_JSON="${OUT_PREFIX}_release_evidence_matrix.summary.json"
MATRIX_VALIDATOR_REGRESSION_LOG="${OUT_PREFIX}_release_evidence_matrix.validator_regression.log"

SKC_G3_SAMPLING_JSON="${OUT_PREFIX}_skc_g3_real_sampling.json"

INTERNAL_PASS_LINES_JSON="${OUT_PREFIX}_internal_pass_lines_report.json"
INTERNAL_PASS_METRICS_JSON="${ROOT_DIR}/build/internal_pass_metrics.json"
INTERNAL_PASS_SAMPLES_JSON="${ROOT_DIR}/build/internal_pass_samples.json"
INTERNAL_PASS_INPUTS_PREP_JSON="${OUT_PREFIX}_internal_pass_inputs_prep.json"
SUMMARY_JSON="${OUT_PREFIX}_skc_g5_summary.json"

cd "${ROOT_DIR}"

XT_READY_AUDIT_EXPORT_JSON="${AUDIT_JSON}" node ./scripts/m3_resolve_xt_ready_audit_input.js \
  --require-real \
  --out-json "${EVIDENCE_SOURCE_JSON}"

node ./scripts/m3_extract_xt_ready_incident_events_from_audit.js \
  --strict \
  --audit-json "${AUDIT_JSON}" \
  --connector-gate-json "${CONNECTOR_JSON}" \
  --out-json "${INCIDENTS_JSON}"

node ./scripts/m3_generate_xt_ready_e2e_evidence.js \
  --strict \
  --events-json "${INCIDENTS_JSON}" \
  --out-json "${E2E_JSON}"

node ./scripts/m3_check_xt_ready_gate.js \
  --strict-e2e \
  --e2e-evidence "${E2E_JSON}" \
  --evidence-source "${EVIDENCE_SOURCE_JSON}" \
  --require-real-audit-source \
  --out-json "${XT_READY_GATE_REPORT}"

node ./scripts/m3_collect_skc_g3_real_sampling.js \
  --db-path "${G3_DB_PATH}" \
  --out-json "${SKC_G3_SAMPLING_JSON}"

bash ./x-terminal/scripts/ci/xt_release_evidence_matrix_regression.sh >"${MATRIX_LOG}" 2>&1

node ./x-terminal/scripts/ci/xt_release_evidence_matrix_log_validator.js \
  --log "${MATRIX_LOG}" \
  --out-json "${MATRIX_SUMMARY_JSON}"

node ./x-terminal/scripts/ci/xt_release_evidence_matrix_validator_regression.js \
  >"${MATRIX_VALIDATOR_REGRESSION_LOG}" 2>&1

node ./scripts/m3_prepare_internal_pass_inputs.js \
  --connector-gate-json "${CONNECTOR_JSON}" \
  --xt-ready-incidents-json "${INCIDENTS_JSON}" \
  --xt-ready-gate-report "${XT_READY_GATE_REPORT}" \
  --sample-db-path "${G3_DB_PATH}" \
  --out-metrics-json "${INTERNAL_PASS_METRICS_JSON}" \
  --out-samples-json "${INTERNAL_PASS_SAMPLES_JSON}" \
  --out-prep-json "${INTERNAL_PASS_INPUTS_PREP_JSON}"

if [[ -n "${METRICS_JSON_OVERRIDE}" ]]; then
  cp "${METRICS_JSON_OVERRIDE}" "${INTERNAL_PASS_METRICS_JSON}"
  echo "info - applied metrics override (${METRICS_JSON_OVERRIDE} -> ${INTERNAL_PASS_METRICS_JSON})"
fi
if [[ -n "${SAMPLES_JSON_OVERRIDE}" ]]; then
  cp "${SAMPLES_JSON_OVERRIDE}" "${INTERNAL_PASS_SAMPLES_JSON}"
  echo "info - applied samples override (${SAMPLES_JSON_OVERRIDE} -> ${INTERNAL_PASS_SAMPLES_JSON})"
fi

set +e
node ./scripts/m3_check_internal_pass_lines.js \
  --window "${WINDOW}" \
  --xt-report-index "${XT_REPORT_INDEX_PATH}" \
  --xt-ready-gate-report "${XT_READY_GATE_REPORT}" \
  --xt-ready-evidence-source "${EVIDENCE_SOURCE_JSON}" \
  --connector-gate-snapshot "${CONNECTOR_JSON}" \
  --metrics-json "${INTERNAL_PASS_METRICS_JSON}" \
  --sample-summary-json "${INTERNAL_PASS_SAMPLES_JSON}" \
  --out-json "${INTERNAL_PASS_LINES_JSON}" \
  >/tmp/hub_l5_internal_pass_lines.log 2>&1
PASS_LINES_RC=$?
set -e

node - <<'NODE' \
  "${SUMMARY_JSON}" \
  "${XT_REPORT_INDEX_PATH}" \
  "${EVIDENCE_SOURCE_JSON}" \
  "${INCIDENTS_JSON}" \
  "${E2E_JSON}" \
  "${XT_READY_GATE_REPORT}" \
  "${MATRIX_LOG}" \
  "${MATRIX_SUMMARY_JSON}" \
  "${MATRIX_VALIDATOR_REGRESSION_LOG}" \
  "${SKC_G3_SAMPLING_JSON}" \
  "${INTERNAL_PASS_LINES_JSON}" \
  "${INTERNAL_PASS_METRICS_JSON}" \
  "${INTERNAL_PASS_SAMPLES_JSON}" \
  "${INTERNAL_PASS_INPUTS_PREP_JSON}" \
  "${WINDOW}" \
  "${PASS_LINES_RC}"
const fs = require("node:fs");
const path = require("node:path");

const [
  outJson,
  xtReportIndexPath,
  evidenceSourceJson,
  incidentsJson,
  e2eJson,
  xtReadyGateReport,
  matrixLog,
  matrixSummaryJson,
  matrixValidatorLog,
  skcG3SamplingJson,
  internalPassLinesJson,
  internalPassMetricsJson,
  internalPassSamplesJson,
  internalPassInputsPrepJson,
  windowLabel,
  passLinesRcRaw,
] = process.argv.slice(2);

const safeLoad = (p) => {
  try {
    return JSON.parse(fs.readFileSync(p, "utf8"));
  } catch {
    return null;
  }
};

const passLines = safeLoad(internalPassLinesJson);
const summary = {
  schema_version: "hub_l5_skc_g5_gate_summary.v1",
  generated_at: new Date().toISOString(),
  window: windowLabel,
  inputs: {
    xt_report_index_json: xtReportIndexPath,
    evidence_source_json: evidenceSourceJson,
    incidents_json: incidentsJson,
    e2e_json: e2eJson,
    xt_ready_gate_report: xtReadyGateReport,
    matrix_log: matrixLog,
    matrix_summary_json: matrixSummaryJson,
    matrix_validator_regression_log: matrixValidatorLog,
    skc_g3_sampling_json: skcG3SamplingJson,
    internal_pass_lines_json: internalPassLinesJson,
    internal_pass_metrics_json: internalPassMetricsJson,
    internal_pass_samples_json: internalPassSamplesJson,
    internal_pass_inputs_prep_json: internalPassInputsPrepJson,
  },
  checks: {
    xt_ready_require_real_ok: !!(safeLoad(xtReadyGateReport)?.ok),
    matrix_validator_ok: !!(safeLoad(matrixSummaryJson)?.summary?.all_required_passed),
    skc_g3_gate_status: safeLoad(skcG3SamplingJson)?.gate?.["SKC-G3"] || "UNKNOWN",
    skc_g3_kpi_snapshot: safeLoad(skcG3SamplingJson)?.kpi_snapshot || null,
    internal_pass_lines_rc: Number(passLinesRcRaw),
    internal_pass_lines_decision: passLines?.release_decision || "UNKNOWN",
    failed_hard_lines: passLines?.failed_hard_lines || [],
    missing_evidence: passLines?.missing_evidence || [],
  },
};

fs.mkdirSync(path.dirname(outJson), { recursive: true });
fs.writeFileSync(outJson, `${JSON.stringify(summary, null, 2)}\n`, "utf8");
NODE

PASS_LINES_DECISION="$(node -e 'const fs=require("node:fs");const p=process.argv[1];try{const d=JSON.parse(fs.readFileSync(p,"utf8"));process.stdout.write(String(d.release_decision||"UNKNOWN"));}catch(_){process.stdout.write("UNKNOWN");}' "${INTERNAL_PASS_LINES_JSON}")"
SKC_G3_GATE_DECISION="$(node -e 'const fs=require("node:fs");const p=process.argv[1];try{const d=JSON.parse(fs.readFileSync(p,"utf8"));process.stdout.write(String((d.gate||{})["SKC-G3"]||"UNKNOWN"));}catch(_){process.stdout.write("UNKNOWN");}' "${SKC_G3_SAMPLING_JSON}")"

echo "ok - Hub-L5 SKC gate summary generated (${SUMMARY_JSON})"
echo "info - internal pass-lines decision: ${PASS_LINES_DECISION}"
echo "info - SKC-G3 real sampling gate: ${SKC_G3_GATE_DECISION}"

if [[ "${PASS_LINES_DECISION}" != "GO" || "${SKC_G3_GATE_DECISION}" != "PASS" ]]; then
  echo "warn - release non-go: internal_pass_lines=${PASS_LINES_DECISION}, skc_g3=${SKC_G3_GATE_DECISION} (see /tmp/hub_l5_internal_pass_lines.log)" >&2
  exit 2
fi

exit 0
