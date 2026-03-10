#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY_ONLY=0

CURRENT_MANIFEST="${XT_ROLLBACK_CURRENT_MANIFEST:-${ROOT_DIR}/.axcoder/release/current.manifest.json}"
PREVIOUS_MANIFEST="${XT_ROLLBACK_PREVIOUS_MANIFEST:-${ROOT_DIR}/.axcoder/release/previous.manifest.json}"
REPORT_FILE="${XT_ROLLBACK_REPORT_FILE:-${ROOT_DIR}/.axcoder/reports/xt-rollback-last.json}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --verify-only                 Validate rollback prerequisites only.
  --current-manifest <path>     Current release manifest path.
  --previous-manifest <path>    Previous stable release manifest path.
  --report-file <path>          Output JSON report path.
  -h, --help                    Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify-only)
      VERIFY_ONLY=1
      shift
      ;;
    --current-manifest)
      CURRENT_MANIFEST="$2"
      shift 2
      ;;
    --previous-manifest)
      PREVIOUS_MANIFEST="$2"
      shift 2
      ;;
    --report-file)
      REPORT_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[xt-rollback] unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

read_release_id() {
  local manifest_path="$1"
  node -e '
const fs = require("fs");
const manifestPath = process.argv[1];
const payload = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const releaseId = payload && payload.release_id;
if (!releaseId) {
  console.error("release_id_missing");
  process.exit(3);
}
process.stdout.write(String(releaseId));
' "${manifest_path}"
}

mkdir -p "$(dirname "${REPORT_FILE}")"
mkdir -p "$(dirname "${CURRENT_MANIFEST}")"
mkdir -p "$(dirname "${PREVIOUS_MANIFEST}")"

generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
mode="apply"
if [[ "${VERIFY_ONLY}" == "1" ]]; then
  mode="verify_only"
fi

status="pass"
reason="ok"
release_id=""
copied_previous_to_current=0

if [[ ! -f "${PREVIOUS_MANIFEST}" ]]; then
  status="fail"
  reason="previous_manifest_missing"
else
  if ! release_id="$(read_release_id "${PREVIOUS_MANIFEST}" 2>/tmp/xt_rollback_prev_manifest.err)"; then
    status="fail"
    reason="previous_manifest_invalid"
  fi
fi

if [[ "${status}" == "pass" && "${VERIFY_ONLY}" != "1" ]]; then
  cp "${PREVIOUS_MANIFEST}" "${CURRENT_MANIFEST}"
  copied_previous_to_current=1
  local_current_release_id=""
  if ! local_current_release_id="$(read_release_id "${CURRENT_MANIFEST}" 2>/tmp/xt_rollback_curr_manifest.err)"; then
    status="fail"
    reason="current_manifest_invalid_after_copy"
  elif [[ "${local_current_release_id}" != "${release_id}" ]]; then
    status="fail"
    reason="rollback_release_id_mismatch"
  fi
fi

cat > "${REPORT_FILE}" <<JSON
{
  "generated_at": "${generated_at}",
  "mode": "${mode}",
  "status": "${status}",
  "reason": "${reason}",
  "current_manifest": "${CURRENT_MANIFEST}",
  "previous_manifest": "${PREVIOUS_MANIFEST}",
  "release_id": "${release_id}",
  "verify_only": ${VERIFY_ONLY},
  "copied_previous_to_current": ${copied_previous_to_current}
}
JSON

if [[ "${status}" != "pass" ]]; then
  echo "[xt-rollback] failed (${reason}); report=${REPORT_FILE}" >&2
  exit 1
fi

if [[ "${VERIFY_ONLY}" == "1" ]]; then
  echo "[xt-rollback] verify-only passed (release_id=${release_id}); report=${REPORT_FILE}"
else
  echo "[xt-rollback] rollback applied (release_id=${release_id}); report=${REPORT_FILE}"
fi
