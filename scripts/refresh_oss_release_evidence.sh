#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${ROOT_DIR}"

required_inputs=(
  "build/reports/lpr_w3_03_a_require_real_evidence.v1.json"
  "build/reports/xhub_doctor_source_gate_summary.v1.json"
  "build/reports/xhub_doctor_hub_local_service_snapshot_smoke_evidence.v1.json"
  "x-terminal/.axcoder/reports/xt-report-index.json"
  "x-terminal/.axcoder/reports/xt-gate-report.md"
  "x-terminal/.axcoder/reports/xt-rollback-last.json"
  "x-terminal/.axcoder/reports/xt-rollback-verify.json"
  "x-terminal/.axcoder/reports/secrets-dry-run-report.json"
)

xt_ready_report_candidates=(
  "build/xt_ready_gate_e2e_require_real_report.json"
  "build/xt_ready_gate_e2e_db_real_report.json"
  "build/xt_ready_gate_e2e_report.json"
)

missing_inputs=()
for rel_path in "${required_inputs[@]}"; do
  if [ ! -f "${rel_path}" ]; then
    missing_inputs+=("${rel_path}")
  fi
done

selected_xt_ready_report=""
selected_xt_ready_source=""
selected_connector_gate=""
selected_xt_ready_source_candidates=()
selected_connector_gate_candidates=()

if [ -f "build/xt_ready_gate_e2e_require_real_report.json" ]; then
  selected_xt_ready_report="build/xt_ready_gate_e2e_require_real_report.json"
  selected_xt_ready_source_candidates=(
    "build/xt_ready_evidence_source.require_real.json"
    "build/xt_ready_evidence_source.json"
  )
  selected_connector_gate_candidates=(
    "build/connector_ingress_gate_snapshot.require_real.json"
    "build/connector_ingress_gate_snapshot.json"
  )
elif [ -f "build/xt_ready_gate_e2e_db_real_report.json" ]; then
  selected_xt_ready_report="build/xt_ready_gate_e2e_db_real_report.json"
  selected_xt_ready_source_candidates=(
    "build/xt_ready_evidence_source.db_real.json"
    "build/xt_ready_evidence_source.require_real.json"
    "build/xt_ready_evidence_source.json"
  )
  selected_connector_gate_candidates=(
    "build/connector_ingress_gate_snapshot.db_real.json"
    "build/connector_ingress_gate_snapshot.require_real.json"
    "build/connector_ingress_gate_snapshot.json"
  )
elif [ -f "build/xt_ready_gate_e2e_report.json" ]; then
  selected_xt_ready_report="build/xt_ready_gate_e2e_report.json"
  selected_xt_ready_source_candidates=(
    "build/xt_ready_evidence_source.json"
  )
  selected_connector_gate_candidates=(
    "build/connector_ingress_gate_snapshot.json"
  )
fi

if [ -n "${selected_xt_ready_report}" ]; then
  for rel_path in "${selected_xt_ready_source_candidates[@]}"; do
    if [ -f "${rel_path}" ]; then
      selected_xt_ready_source="${rel_path}"
      break
    fi
  done
  for rel_path in "${selected_connector_gate_candidates[@]}"; do
    if [ -f "${rel_path}" ]; then
      selected_connector_gate="${rel_path}"
      break
    fi
  done
else
  missing_inputs+=("build/xt_ready_gate_e2e_require_real_report.json | build/xt_ready_gate_e2e_db_real_report.json | build/xt_ready_gate_e2e_report.json")
fi

if [ -n "${selected_xt_ready_report}" ] && [ -z "${selected_xt_ready_source}" ]; then
  missing_inputs+=("$(printf '%s | ' "${selected_xt_ready_source_candidates[@]}" | sed 's/ | $//')")
fi

if [ -n "${selected_xt_ready_report}" ] && [ -z "${selected_connector_gate}" ]; then
  missing_inputs+=("$(printf '%s | ' "${selected_connector_gate_candidates[@]}" | sed 's/ | $//')")
fi

if [ "${#missing_inputs[@]}" -gt 0 ]; then
  echo "[refresh-oss-release-evidence] missing upstream evidence inputs:" >&2
  printf ' - %s\n' "${missing_inputs[@]}" >&2
  echo "[refresh-oss-release-evidence] regenerate the listed upstream source-truth artifacts first, then rerun this helper." >&2
  exit 1
fi

echo "[refresh-oss-release-evidence] XT-ready evidence: ${selected_xt_ready_report} + ${selected_xt_ready_source} + ${selected_connector_gate}"

echo "[1/8] Refresh legacy release compatibility pack"
node scripts/generate_release_legacy_compat_artifacts.js

echo "[2/8] Refresh xhub_local_service operator recovery support"
node scripts/generate_xhub_local_service_operator_recovery_report.js

echo "[3/8] Refresh operator channel recovery support"
node scripts/generate_xhub_operator_channel_recovery_report.js

echo "[4/8] Refresh Hub OSS boundary readiness"
node scripts/generate_hub_r1_release_oss_boundary_report.js

echo "[5/8] Refresh OSS secret scrub report"
node scripts/generate_oss_secret_scrub_report.js

echo "[6/8] Refresh OSS release readiness bundle"
python3 scripts/generate_oss_release_readiness_report.py

echo "[7/8] Refresh product exit packet"
node scripts/generate_lpr_w4_09_c_product_exit_packet.js

echo "[8/8] Refresh human-readable release/support snippet"
node scripts/generate_oss_release_support_snippet.js

echo
echo "Refreshed reports:"
echo "- build/reports/release_legacy_compat_pack.v1.json"
echo "- build/reports/xhub_local_service_operator_recovery_report.v1.json"
echo "- build/reports/xhub_operator_channel_recovery_report.v1.json"
echo "- build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json"
echo "- build/reports/hub_l5_r1_release_oss_boundary_delta_3line.v1.json"
echo "- build/reports/xt_ready_release_diagnostics.v1.json"
echo "- build/reports/oss_secret_scrub_report.v1.json"
echo "- build/reports/oss_public_manifest_v1.json"
echo "- build/reports/oss_release_readiness_v1.json"
echo "- build/reports/lpr_w4_09_c_product_exit_packet.v1.json"
echo "- build/reports/oss_release_support_snippet.v1.md"
